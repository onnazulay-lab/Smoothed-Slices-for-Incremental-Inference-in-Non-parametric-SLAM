function [conditionals, states, book, root] = forwardEliminationGeneral(caseData, config, opts)
%FORWARDELIMINATIONGENERAL Slice elimination on a graph of any size or shape.
%
%   Inputs
%     CASEDATA  the case
%     CONFIG    the method config
%     Cache     a methods.general.StepCache, for reuse across increments
%     StepSeed  reseed the stream per step from its own signature
%                                                            default false
%
%   Outputs
%     CONDITIONALS  the Bayes net, one core.SliceConditional per eliminated
%                   variable, in elimination order
%     STATES        one core.EliminationState per step
%     BOOK          the proposal book, carrying each variable's support
%     ROOT          the root marginal
%
%   Utility
%     Run the forward pass over an arbitrary factor graph of vector-valued
%     variables.
%
%   RELATIONSHIP TO THE THREE-NODE ENGINE. methods.slices.forwardElimination
%   follows Algorithm S1 literally: the sampling factor f' is drawn from and
%   then EXCLUDED from the slice product, so its normalizer cancels and the
%   estimator needs no explicit proposal density (Eq. S8). That cancellation
%   needs f' to connect omega_j to an already eliminated variable, which is
%   the Lemma 1 condition, and it needs the previous generated factor to still
%   carry its mixture so the sampler can be reached.
%
%   This engine keeps every removed factor in the product and divides by an
%   EXPLICIT proposal density instead:
%
%       f_new_hat(s) = (1/N) sum_n prod_{f in F(omega)} f(omega^(n), s)
%                                  / q(omega^(n))
%
%   The two are the same estimator when q is the sampling factor: then
%   f'(omega^(n))/q(omega^(n)) = Z_{f'} and the constant comes back out.
%   Writing the density explicitly is what lets a generated factor be
%   tabulated and its mixture discarded, which is what stops the nesting cost
%   from multiplying out over thirteen eliminations. tGridWorld checks the
%   agreement by running this engine on the two-pose range benchmark and
%   scoring it against the same quadrature reference the paper-faithful
%   engine uses.
%
%   WHAT IS APPROXIMATE. Three things, all reported rather than implied:
%   the separator support is a finite importance sample, so its ESS is
%   recorded per step; the generated factor is looked up by nearest support
%   point off-support; and the proposal book is a marginal approximation used
%   only to propose, never to represent a factor.

%   REUSE ACROSS INCREMENTS. Name-value CACHE takes a
%   methods.general.StepCache, and then a step whose whole prefix is unchanged
%   is fetched rather than recomputed -- the surface caching of the Smoothed
%   Slices spec, applied across increments instead of within one. STEPSEED
%   reseeds the stream per step from that step's own signature, which is what
%   makes a cached run numerically identical to an uncached one; see the
%   StepCache class comment.

arguments
    caseData (1,1) struct
    config (1,1) struct
    opts.Cache = []
    opts.StepSeed (1,1) logical = false
end

order = caseData.eliminationOrder;
g     = caseData.graph.copy();
caseData.graph.validateEliminationOrder(order);

nX = config.numSamples;
nS = config.separatorSupportSize;

conditionals = core.SliceConditional.empty(1, 0);
states = core.EliminationState.empty(1, 0);
book = struct();
root = struct();

cache = opts.Cache;
useCache = ~isempty(cache);
prevSig = "";
if ~useCache && opts.StepSeed
    % Signatures are still needed as per-step seeds even with no cache to
    % put them in; an empty cache object is the cheapest way to keep one
    % definition of what a step signature is.
    cache = methods.general.StepCache(config, 'Enabled', false);
end

domains = localDomainMap(caseData.graph);
dimsOf  = localDimMap(caseData.graph);

p = utils.progressOf(config);

for j = 1:numel(order)
    omega = order(j);
    p.report((j-1) / numel(order), sprintf("eliminating %s (%d of %d)", ...
        omega, j, numel(order)));
    tStep = tic;

    st = core.EliminationState(j, omega);
    removed   = g.adjacentFactors(omega);
    separator = g.separatorOf(omega);
    st = st.recordLocalData(removed);
    st.Separator = separator;

    if isempty(removed)
        error('methods:general:isolatedVariable', ...
            'Variable %s has no adjacent factors at step %d.', omega, j);
    end

    % --- 0. cache key and stream -----------------------------------------
    % The signature is computed whether or not a cache was handed over,
    % because it is also the per-step seed. Deriving the seed from the step's
    % own inputs is what decouples a step's randomness from how many steps
    % before it happened to be skipped.
    sig = "";
    if ~isempty(cache)
        sig = cache.signature(prevSig, omega, removed, separator);
        prevSig = sig;
        if opts.StepSeed
            rng(methods.general.StepCache.seedFor(sig), 'twister');
        end
    end

    if useCache && ~isempty(separator)
        [hit, payload] = cache.fetch(sig);
        if hit
            % Everything this step would have produced, replayed. The
            % assertion is cheap insurance against a hash collision: a
            % payload whose separator disagrees with the graph would corrupt
            % the rest of the pass silently.
            if ~isequal(payload.separator, separator) || payload.frontal ~= omega
                error('methods:general:cacheCollision', ...
                    'Cached step %s does not match %s at step %d.', ...
                    payload.frontal, omega, j);
            end
            st.NewFactor   = payload.tab;
            st.Conditional = payload.cond;
            st.SamplingFactorName = payload.samplingFactorName;
            st.SamplingRoute = payload.route;
            st.Diagnostics = payload.diagnostics;
            st.Diagnostics.cacheHit = true;
            st.Timing = struct('step', toc(tStep), 'cached', true);

            conditionals(end+1) = payload.cond; %#ok<AGROW>
            book = localUpdateBook(book, separator, payload.sepDims, ...
                                   payload.support, payload.supportWeights);
            root = payload.root;

            g.removeVariable(omega);
            g.addFactor(payload.tab.toFactor());
            states(end+1) = st; %#ok<AGROW>
            continue
        end
    end

    if isempty(separator)
        % Terminal step: nothing is left to condition on. The root marginal
        % is the previous generated factor on its own support, which ROOT
        % already holds, so this step only closes the Bayes net. No samples
        % are drawn, because there is nothing for them to be weighted against.
        st.SamplingFactorName = "(terminal)";
        st.SamplingRoute = "terminal";
        st.Diagnostics = struct('terminal', true);

        if isempty(fieldnames(root))
            % ...unless this is ALSO the first step, which happens at
            % increment 1 of a mission whose first pose is the whole graph.
            % There is no previous generated factor to be the root, so the
            % root is this variable under its own factors: propose, weight by
            % their product over the proposal density, and hand the weighted
            % sample set to the backward pass as the support it would
            % otherwise have inherited. Falling through instead would leave
            % ROOT empty and fail in the backward pass on a missing field,
            % which is a long way from the cause.
            [pOmega, condName] = localOmegaProposal(omega, dimsOf(omega), ...
                domains(omega), removed, separator, book, config);
            pool  = localConditioningPool(condName, book, nX);
            X     = pOmega.draw(pool);
            logQx = reshape(pOmega.logpdf(X, pool), [], 1);

            a = struct(matlab.lang.makeValidName(omega), X);
            fx = core.evalProduct(removed, a);
            lw = log(max(fx(:), realmin)) - logQx;
            lw(~isfinite(lw)) = -Inf;
            wx = exp(lw - max(lw));
            if sum(wx) <= 0
                error('methods:general:singleVariableHasNoMass', ...
                    ['The only variable %s carries no mass under its own ' ...
                     'factors; the proposal missed their support.'], omega);
            end

            st.SamplingFactorName = pOmega.factorName;
            st.SamplingRoute = "terminal-root";
            st.Diagnostics = struct('terminal', true, 'route', pOmega.kind, ...
                'numOuter', nX, 'essOuter', sum(wx)^2 / sum(wx.^2));

            root = struct('variable', omega, 'dims', dimsOf(omega), ...
                          'support', X, 'weights', wx / sum(wx), ...
                          'fnew', reshape(fx, 1, []), 'logScale', 0);
        end

        st.Timing = struct('step', toc(tStep), 'cached', false);
        states(end+1) = st; %#ok<AGROW>
        g.removeVariable(omega);
        continue
    end

    dOmega = dimsOf(omega);
    sepDims = arrayfun(@(v) dimsOf(v), separator);

    % --- 1. propose omega -------------------------------------------------
    [pOmega, condName] = localOmegaProposal(omega, dOmega, domains(omega), ...
                                            removed, separator, book, config);
    pool = localConditioningPool(condName, book, nX);
    X    = pOmega.draw(pool);
    logQx = reshape(pOmega.logpdf(X, pool), [], 1);

    st.SamplingFactorName = pOmega.factorName;
    st.SamplingRoute = pOmega.kind;

    % --- 2. propose the separator support ---------------------------------
    % The support grows with separator dimension. A plane and an
    % eight-dimensional separator cannot be covered by the same number of
    % points, and holding |S| fixed drives the effective sample size to one
    % without anything in the output saying so.
    dS = sum(sepDims);
    nSj = min(config.maxSupportSize, ...
              ceil(nS * config.supportDimGrowth^((dS - 2) / 2)));
    nCand = min(config.maxSupportSize * config.supportOverdraw, ...
                nSj * config.supportOverdraw);

    [Scand, logQs, propInfo] = methods.general.proposeSupport( ...
        separator, sepDims, omega, pOmega, pool, removed, ...
        cellfun(@(v) domains(v), cellstr(separator), 'UniformOutput', false), ...
        book, nCand, config);

    % --- 3. the slice matrix ----------------------------------------------
    % Every removed factor stays in the product; the proposal density is
    % divided out explicitly rather than cancelled.
    af = core.ApproximateFactor(separator, omega, X, removed, ...
        'SourceFactorName', pOmega.factorName, 'Counter', g.Counter, ...
        'ScopeDims', sepDims);
    Mcand = af.evaluateSlices( ...
        methods.general.supportAssignment(separator, sepDims, Scand));

    % Importance-weighted slice average. The weights are per OUTER sample and
    % constant across the support, so they scale rows of M. The largest
    % weight is factored out into LogScale so the stored matrix stays in a
    % sane numeric range; mean(SliceMatrix,1)*exp(LogScale) then recovers
    % f_new exactly, which is the convention runInferenceCore already uses.
    logScale = max(-logQx);
    wx = exp(-logQx - logScale);          % in (0, 1]
    Mcand = Mcand .* wx;

    % --- Smoothed Slices: separator-support truncation ---------------------
    % This is the one place the two methods differ on a general graph:
    % Slices keeps the whole slice matrix, Smoothed Slices keeps only the K
    % largest entries of each row. Everything else -- the case, the seed, the
    % proposals, the ordering, the backward pass -- is literally the same
    % code, so a difference in the answers is a difference between the methods
    % and not between two harnesses.
    %
    % IT IS NOT THE SPARSE RECURSION OF EQ. (50), and this comment used to say
    % it was. The columns pruned here are separator points, not the successor
    % path points Eq. (49) indexes over; see localTruncateSeparatorSupport.
    % The real recursion is still to be built on this engine.
    % THE FRACTION IS TAKEN AGAINST THE MATRIX THAT IS PRUNED, which is the
    % correction that made this item matter. runSmoothedSlicesMethod used to
    % compute an absolute K as activeSetFraction * separatorSupportSize, but
    % the matrix here has nCand columns and nCand is nSj * supportOverdraw --
    % four times |S| at the shipped overdraw. So the default fraction of 0.25
    % kept about a sixteenth of the columns rather than a quarter, and a
    % fraction of 1.0, which reads as "keep everything", still discarded three
    % quarters of them. Deciding K here is the only place the real width is
    % known.
    activeInfo = localTruncationInfo(ones(size(Mcand, 1), 1), Inf, Inf, false);
    if config.innerEstimator == "rcs"
        kTrunc = config.activeSetSize;
        if ~isfinite(kTrunc)
            % The floor of 8 keeps a separator that has collapsed to a handful
            % of candidates from being cut to nothing.
            kTrunc = max(8, round(config.activeSetFraction * nCand));
        end
        if kTrunc < nCand
            [Mcand, activeInfo] = localTruncateSeparatorSupport(Mcand, kTrunc);
        end
    end

    fcand = exp(logScale) * mean(Mcand, 1);   % 1 x |candidates|

    essOuter = sum(wx)^2 / sum(wx.^2);

    % --- 4. resample the support, then tabulate ---------------------------
    % Candidate weights are f_new(s)/q(s), formed in logs because f_new spans
    % many decades. Resampling to |S| points leaves a support distributed
    % according to f_new ITSELF rather than according to the proposal.
    %
    % This matters more than any amount of extra support. The proposal draws
    % the separator variables independently given omega, but the removed
    % factors couple them -- a range factor between two separator variables
    % is common -- so the weights are wildly uneven and the effective sample
    % size falls to near one however many points are drawn. Resampling puts
    % the points where the factor actually has mass, and makes the reference
    % weights uniform for everything downstream. The PRE-resampling ESS is
    % kept as the diagnostic, because resampling improves the support without
    % creating any information, and reporting the post-resampling ESS would
    % claim otherwise.
    lwS = log(max(fcand(:), realmin)) - logQs(:);
    lwS(~isfinite(lwS)) = -Inf;
    wCand = exp(lwS - max(lwS));
    wCand(~isfinite(wCand) | wCand < 0) = 0;
    if sum(wCand) <= 0
        error('methods:general:supportHasNoMass', ...
            ['The separator support of %s carries no mass. The proposal ' ...
             'missed the region the factors support, at step %d.'], omega, j);
    end
    essSupport = sum(wCand)^2 / sum(wCand.^2);

    if config.supportResample
        keep = localSystematicResample(wCand, nSj);
        S    = Scand(keep, :);
        Mw   = Mcand(:, keep);
        fnew = fcand(keep);
        wS   = ones(nSj, 1);      % the points already carry the distribution
    else
        % Keep every candidate, weighted. Resampling would leave the support
        % distributed according to f_new, which sounds strictly better and is
        % not: with an effective sample size of two, resampling four hundred
        % points yields four hundred copies of a handful of distinct
        % locations, and the nearest-neighbour lookup that every later step
        % depends on then has almost nothing to snap to. Diversity is worth
        % more here than distributional correctness.
        keep = (1:nCand).';
        S    = Scand;
        Mw   = Mcand;
        fnew = fcand;
        wS   = wCand;
    end

    % The marginal weight of each OUTER sample: its slice integrated over the
    % separator. This is what the next elimination needs when it reaches back
    % through this factor for a Lemma 1 proposal, and it is a strictly better
    % weight than 1/q alone, which ignores the factors entirely.
    sampleWeights = Mw * (wS / sum(wS));

    diagStep = struct( ...
        'route', pOmega.kind, 'conditionedOn', condName, ...
        'proposalKinds', propInfo.kinds, ...
        'numOuter', nX, 'numSupport', size(S, 1), 'numCandidates', nCand, ...
        'separatorDim', dS, ...
        'essOuter', essOuter, ...
        'essSupport', essSupport, ...
        'uniqueSupport', numel(unique(keep)), ...
        ... % Named for what it is. It was 'activeSet', which is the Eq. (49)
        ... % object this route does not compute; the struct itself now says so
        ... % too, in isEq49 and indexedOver.
        'sparsification', activeInfo);

    tab = core.ApproximateFactor.tabulated(separator, omega, S, Mw, ...
        'OuterSamples', X, 'ScopeDims', sepDims, 'LogScale', logScale, ...
        'SourceFactorName', pOmega.factorName, ...
        'MixtureFactors', removed, 'SampleWeights', sampleWeights, ...
        'ExactEvaluation', config.exactGeneratedFactors, ...
        'Diagnostics', diagStep, 'Counter', g.Counter);
    st.NewFactor = tab;

    % --- 5. the conditional -----------------------------------------------
    % Column i of M, normalized, IS the conditional p(omega | s_i) evaluated
    % at the outer samples: the removed-factor product over the proposal
    % density is exactly the importance weight of omega^(n) under that
    % conditional, and the normalizer cancels column by column.
    cond = core.SliceConditional(omega, X, separator, sepDims, S, Mw, ...
        'Step', j, 'Diagnostics', diagStep);
    conditionals(end+1) = cond; %#ok<AGROW>
    st.Conditional = cond;

    % --- 6. proposal book and graph reduction -----------------------------
    book = localUpdateBook(book, separator, sepDims, S, wS);

    st.Diagnostics = diagStep;
    st.Diagnostics.cacheHit = false;
    st.Timing = struct('step', toc(tStep), 'cached', false);

    root = struct('variable', separator, 'dims', sepDims, ...
                  'support', S, 'weights', wS / sum(wS), ...
                  'fnew', fnew, 'logScale', logScale);

    if useCache
        cache.store(sig, struct( ...
            'frontal', omega, 'separator', separator, 'sepDims', sepDims, ...
            'tab', tab, 'cond', cond, 'diagnostics', diagStep, ...
            'samplingFactorName', pOmega.factorName, 'route', pOmega.kind, ...
            'support', S, 'supportWeights', wS, 'root', root));
    end

    g.removeVariable(omega);
    g.addFactor(tab.toFactor());

    states(end+1) = st; %#ok<AGROW>
end
end

% =========================================================================
function [p, condName] = localOmegaProposal(omega, dOmega, domain, removed, separator, book, config)
%LOCALOMEGAPROPOSAL The proposal for the variable being eliminated.
%   Inputs   OMEGA, DOMEGA its width, DOMAIN its box, REMOVED its factors,
%           SEPARATOR the separator, BOOK the proposal book, CONFIG
%   Outputs  P the proposal, CONDNAME what it conditions on, or ""
%   Utility  omega is drawn first and the separator is proposed conditionally
%           on it, so this choice sets the quality of everything downstream.
%
%   Prefers a unary factor, then a removed factor tying omega to a separator
%   variable that already has a support. The conditioning variable is
%   returned so the caller can build the matching pool.
condName = "";
p = methods.general.variableProposal(omega, dOmega, domain, removed, "", book, ...
        'Defensive', config.defensiveWeight, 'Bandwidth', config.proposalBandwidth);
if any(p.kind == ["unary" "lemma1"])
    % A prior, or the structural route through a generated factor. Both are
    % unconditional, so there is nothing better to look for.
    return
end

for v = separator
    key = matlab.lang.makeValidName(v);
    if ~isfield(book, key), continue, end
    q = methods.general.variableProposal(omega, dOmega, domain, removed, v, book, ...
            'Defensive', config.defensiveWeight, 'Bandwidth', config.proposalBandwidth);
    if q.kind == "conditional"
        p = q;
        condName = v;
        return
    end
end
% Nothing better: the defensive or uniform proposal already in P stands.
end

% =========================================================================
function pool = localConditioningPool(condName, book, n)
%LOCALCONDITIONINGPOOL The L draws the separator mixture conditions on.
%   Inputs   CONDNAME the conditioning variable, BOOK the proposal book, N how
%           many draws
%   Outputs  POOL, N-by-d, empty when there is nothing to condition on
%   Utility  drawn once and shared, so the mixture density of proposeSupport
%           has a finite, evaluable set of components.
%
%   A proposal that ignores its conditioning argument still needs to be told
%   how many draws to make, so the pool is never empty.
if strlength(condName) == 0
    pool = zeros(n, 0);
    return
end
b = book.(matlab.lang.makeValidName(condName));
pool = b.points(core.categoricalSample(b.weights(:), n), :);
end

% =========================================================================
function book = localUpdateBook(book, separator, dims, S, w)
%LOCALUPDATEBOOK Record this step's separator support in the proposal book.
%   Inputs   BOOK the book, SEPARATOR the variables, DIMS their widths, S the
%           support, W its weights
%   Outputs  BOOK, updated
%   Utility  a later elimination with no factor reaching a variable proposes
%           defensively from what this step learned about it.
%
%   This is a PROPOSAL book, not a posterior. It exists so the next
%   elimination knows roughly where a variable lives; it is never used as the
%   representation of a factor.
col = 0;
for i = 1:numel(separator)
    key = matlab.lang.makeValidName(separator(i));
    book.(key) = struct('points', S(:, col + (1:dims(i))), 'weights', w(:));
    col = col + dims(i);
end
end

% =========================================================================
function [Msparse, info] = localTruncateSeparatorSupport(M, k)
%LOCALTRUNCATESEPARATORSUPPORT Keep the k heaviest separator columns per row.
%   Inputs   M the slice matrix, K how many columns to keep
%   Outputs  MSPARSE the truncated matrix, INFO the retained mass summary
%   Utility  this is NOT Eq. (49): it truncates the SEPARATOR support of a
%           slice matrix, is indexed over separator points rather than
%           successors, and does not renormalize. localTruncationInfo says so
%           in the same field names buildActiveSuccessors uses, so the two are
%           comparable rather than confusable.
%
%   Inputs   M, |X_0| x |candidate separator points|; K, entries kept per row
%   Outputs  MSPARSE, M with the rest zeroed; INFO, the kept-mass summary
%   Utility  the general engine's cost control on the slice matrix.
%
%   THIS IS NOT EQ. (49), AND IT USED TO SAY IT WAS. Eq. (49) defines
%   N_r(a) as a subset of {1,...,B_{r+1}} -- SUCCESSOR path points, indexed by
%   b. The columns of M here are separator support points, indexed by rho.
%   Sorting along them keeps, for each outer sample, the separator values where
%   its slice happens to be largest. That is a different approximation from
%   dropping a successor, and the difference is visible in the answer: fcand is
%   mean(M, 1), so a separator point that no outer sample ranked in its top K
%   gets f_new(s) = 0 exactly. The support of the answer is truncated, not just
%   a surface coarsened. methods.smoothed.buildActiveSuccessors is where the
%   real Eq. (49) lives, on the two-pose route.
%
%   The rows are deliberately NOT renormalized, which is the branch spec
%   section 11.1 allows with "unless the unnormalized form is intended": the
%   dropped mass is reported instead of absorbed, so the truncation cannot look
%   free. buildActiveSuccessors takes the other branch and renormalizes. That
%   the two routes differ on both the index set AND the normalization, while
%   reporting a field of the same name, is what utils.retainedMassSummary's
%   indexedOver and isEq49 now record.
%
%   AND THE OLD HEADER'S NUMBER DID NOT SURVIVE MEASUREMENT. It claimed that
%   "retaining 30 per cent of the mass tripled the surface error". Sweeping K
%   with research.activeSetProfile puts retained mass near 0.30 between K = 4
%   and K = 8, where the surface error is 0.34 to 0.27 against 0.064 at K = 48
%   -- a factor of about five, not three -- and the claim never said what it
%   was tripling from. The curve is in utils.retainedMassSummary; a reader can
%   take the ratio they actually need instead of this one.
[nx, nsCols] = size(M);
k = min(round(k), nsCols);

Msparse = zeros(nx, nsCols);
total = sum(M, 2);

[~, ord] = sort(M, 2, 'descend');
keepIdx = ord(:, 1:k);
rows = repmat((1:nx).', 1, k);
lin = sub2ind([nx nsCols], rows(:), keepIdx(:));
Msparse(lin) = M(lin);

kept = sum(Msparse, 2);

% Per row, and a row with no mass at all retained nothing rather than
% everything. This used to be collapsed to a scalar mean under the name
% retainedMass, which is the same name the two-pose route uses for the whole
% vector -- and the app printed it with %.2f, correct only by accident of
% which route it reached.
retained = zeros(nx, 1);
good = total > 0;
retained(good) = kept(good) ./ total(good);

info = localTruncationInfo(retained, k, nsCols, true);
end

% =========================================================================
function info = localTruncationInfo(retained, k, nsCols, applied)
%LOCALTRUNCATIONINFO The retained-mass summary for the truncation above.
%   Inputs   RETAINED per-row kept fraction, K the cap, NSCOLS how many
%           columns there were, APPLIED whether truncation happened at all
%   Outputs  INFO, the summary
%   Utility  state IndexedOver, Renormalized and IsEq49 explicitly, because
%           this route's answers are the opposite of Eq. (49)'s.
%
%   Inputs   RETAINED per-row kept fraction; K; NSCOLS; APPLIED
%   Outputs  INFO, the shared summary plus this route's fields
%   Utility  stop the not-applied default from being a shorter struct than the
%            applied one, which is why minRetainedMass was missing from it.
info = utils.retainedMassSummary(retained, ...
    'IndexedOver',  "separatorPoints", ...
    'Renormalized', false, ...
    'IsEq49',       false);

info.applied = applied;
if applied
    info.activeSetSize = k;
    info.density       = k / nsCols;
else
    % Nothing was pruned, so every column survives. Reported as Inf and 1
    % rather than as the numbers a truncation would have produced, because a
    % density of 1 with a finite K would read as a truncation that kept
    % everything -- which is a different run from one that never truncated.
    info.activeSetSize = Inf;
    info.density       = 1;
end

info.meanRetainedMass = info.retainedMassMean;
info.minRetainedMass  = info.retainedMassMin;
end

% =========================================================================
function idx = localSystematicResample(w, n)
%LOCALSYSTEMATICRESAMPLE Resampling indices, one stratified pass.
%   Inputs   W the weights, N how many draws
%   Outputs  IDX, one index per draw
%   Utility  systematic rather than multinomial: same expectation, lower
%           variance, and it cannot drop a heavy particle by chance.
%
%   Systematic resampling has strictly lower variance than N independent
%   multinomial draws, which matters here because the support IS the
%   representation: a multinomial draw that happens to miss a high-mass
%   region leaves a hole the rest of the pass can never fill.
w = w(:) / sum(w);
c = cumsum(w);
c(end) = 1;
u = (rand() + (0:n-1).') / n;
idx = zeros(n, 1);
i = 1;
for k = 1:n
    while u(k) > c(i) && i < numel(c)
        i = i + 1;
    end
    idx(k) = i;
end
end

% =========================================================================
function lookup = localDomainMap(graph)
%LOCALDOMAINMAP Each variable's domain box, by name.
%   Inputs   GRAPH, the factor graph
%   Outputs  LOOKUP, name -> box
%   Utility  built once; the graph is reduced in place as elimination
%           proceeds, so a variable's domain must be read before it leaves.
tbl = containers.Map('KeyType', 'char', 'ValueType', 'any');
for v = graph.Variables
    tbl(char(v.Name)) = v.Domain;
end
lookup = @(name) tbl(char(name));
end

% =========================================================================
function lookup = localDimMap(graph)
%LOCALDIMMAP Each variable's dimension, by name.
%   Inputs   GRAPH, the factor graph
%   Outputs  LOOKUP, name -> width
%   Utility  the same, for the widths the separator layout is cut at.
tbl = containers.Map('KeyType', 'char', 'ValueType', 'any');
for v = graph.Variables
    tbl(char(v.Name)) = v.Dim;
end
lookup = @(name) tbl(char(name));
end
