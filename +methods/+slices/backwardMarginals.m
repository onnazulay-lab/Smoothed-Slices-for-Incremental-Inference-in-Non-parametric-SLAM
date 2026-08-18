function out = backwardMarginals(bayesNet, caseData, config)
%BACKWARDMARGINALS Algorithm S4: marginals and joint samples by reverse order.
%
%   Inputs
%     BAYESNET  the conditionals from the forward pass
%     CASEDATA  the case
%     CONFIG    the method config
%
%   Outputs
%     OUT.marginals    one per variable
%     OUT.samples      joint draws, one field per variable
%     OUT.grids        the grid each marginal was tabulated on
%     OUT.diagnostics  per-step engine health
%     OUT.order        the reverse elimination order actually walked
%
%   Utility
%     Walk the Bayes net in reverse elimination order. Starting from the last
%     eliminated variable, whose separator is empty, each marginal is built as
%     the MIXTURE OF CONDITIONAL SLICES over separator samples drawn from the
%     marginal already available (Eq. S16):
%
%       P_hat(omega_j | D) = (1/N) sum_n P_hat(omega_j | S_j^(n), D_j),
%       S_j^(n) ~ P_hat(S_j | D).
%
%   Never a mean, never a MAP: the spec is explicit that the backward pass
%   must return the mixture. Joint samples follow the same traversal, so the
%   separator samples used at step j are genuine joint draws of S_j rather
%   than independently drawn marginals -- which matters as soon as the
%   separator holds more than one variable, as it does at the first
%   elimination here (S_1 = {l1, x2}).

arguments
    bayesNet (1,1) core.BayesNet
    caseData (1,1) struct
    config (1,1) struct
end

order    = caseData.eliminationOrder;
revOrder = flip(order);
g        = caseData.graph;
N        = config.numBackwardSamples;

marginals   = struct();
jointSample = struct();
grids       = struct();
diagnostics = struct();

p = utils.progressOf(config);

for k = 1:numel(revOrder)
    omega = revOrder(k);
    p.report((k-1) / numel(revOrder), sprintf("marginal of %s (%d of %d)", ...
        omega, k, numel(revOrder)));
    key   = matlab.lang.makeValidName(omega);
    cond  = bayesNet.conditionalFor(omega);

    gridVec = g.variable(omega).grid(config.marginalGridSize);
    grids.(key) = gridVec;

    if isempty(cond.Separator)
        % --- Root marginal: normalize the terminal factor numerically -----
        w = cond.evaluate(struct(key, gridVec(:)));
        w = reshape(w, [], 1);

        mass = trapz(gridVec(:), w);
        if ~(mass > 0)
            error('methods:slices:degenerateRoot', ...
                'Root marginal of %s has zero mass on its grid.', omega);
        end
        pdfVec = w / mass;

        diagnostics.(key) = struct('kind', "root", 'mass', mass);
    else
        % --- Mixture of conditional slices over separator samples ---------
        sepAssign = struct();
        for s = cond.Separator
            sk = matlab.lang.makeValidName(s);
            if ~isfield(jointSample, sk)
                error('methods:slices:separatorNotReady', ...
                    ['Separator variable %s has no samples yet while ' ...
                     'processing %s. The reverse order is inconsistent.'], s, omega);
            end
            % Separator samples go on dimension 2; the frontal grid on 1.
            sepAssign.(sk) = reshape(jointSample.(sk), 1, []);
        end
        % Evaluated in blocks of separator samples. The conditional's
        % denominator is a mixture over |X| slices, so a full evaluation
        % costs |X| x |grid| x N intermediates -- a few hundred megabytes at
        % ordinary settings. Chunking bounds the peak regardless of the
        % budgets the user dials in.
        [slices, dnDiag] = localEvaluateChunked(cond, sepAssign, key, gridVec(:), ...
                                                config.backwardChunkSize);
        pdfVec = mean(slices, 2);

        mass = trapz(gridVec(:), pdfVec);
        if ~(mass > 0)
            error('methods:slices:degenerateMarginal', ...
                ['Marginal of %s has zero mass. The conditional denominator ' ...
                 'collapsed on every separator sample.'], omega);
        end
        pdfVec = pdfVec / mass;

        dnDiag.kind = "mixture";
        dnDiag.numSeparatorSamples = size(slices, 2);
        diagnostics.(key) = dnDiag;

        % Column n of SLICES is P_hat(omega | S_j^(n)) for the SAME index n
        % whose separator values are already in jointSample. Drawing one
        % sample per column keeps omega paired with its own separator draw,
        % which is what makes the traversal produce joint posterior samples.
        % Sampling instead from the averaged mixture would give the right
        % marginal but destroy the pairing the next variable depends on.
        columnSamples = localSamplePerColumn(gridVec(:), slices);
    end

    marginals.(key) = struct( ...
        'variable', omega, ...
        'grid',     gridVec, ...
        'pdf',      reshape(pdfVec, 1, []), ...
        'mean',     trapz(gridVec(:), gridVec(:) .* pdfVec(:)));

    if isempty(cond.Separator)
        jointSample.(key) = core.ConditionalFactor.inverseCdfSample( ...
            gridVec(:), pdfVec(:), N);
    else
        jointSample.(key) = columnSamples;
    end
end

out = struct();
out.marginals   = marginals;
out.samples     = jointSample;
out.grids       = grids;
out.diagnostics = diagnostics;
out.order       = revOrder;
end

% -------------------------------------------------------------------------
function [slices, diag] = localEvaluateChunked(cond, sepAssign, frontalKey, gridVec, chunk)
%LOCALEVALUATECHUNKED The conditional on the grid, a block of columns at a time.
%   Inputs   COND the conditional, SEPASSIGN the separator draws, FRONTALKEY
%           the frontal variable's valid name, GRIDVEC the grid, CHUNK how
%           many columns per block
%   Outputs  SLICES the evaluated mixture components, DIAG the per-column
%           health
%   Utility  the full grid times every separator draw does not always fit in
%           memory, and chunking bounds the peak without changing the result.
sepKeys = fieldnames(sepAssign);
N = numel(sepAssign.(sepKeys{1}));

slices = zeros(numel(gridVec), N);
minDen = Inf; zeroCount = 0; nonFinite = 0; denAcc = [];

for lo = 1:chunk:N
    hi  = min(lo + chunk - 1, N);
    blk = struct();
    for i = 1:numel(sepKeys)
        v = sepAssign.(sepKeys{i});
        blk.(sepKeys{i}) = reshape(v(lo:hi), 1, []);
    end
    blk.(frontalKey) = gridVec;

    [v, d] = cond.evaluate(blk);
    slices(:, lo:hi) = v;

    minDen    = min(minDen, d.minDenominator);
    zeroCount = zeroCount + d.zeroFraction * (hi - lo + 1);
    nonFinite = nonFinite + d.nonFinite;
    denAcc(end+1) = d.medDenominator; %#ok<AGROW>
end

diag = struct( ...
    'minDenominator', minDen, ...
    'medDenominator', median(denAcc), ...
    'zeroFraction',   zeroCount / N, ...
    'nonFinite',      nonFinite);
end

function s = localSamplePerColumn(gridVec, W)
%LOCALSAMPLEPERCOLUMN One draw from each column's tabulated density.
%   Inputs   GRIDVEC the grid, W one unnormalized density per column
%   Outputs  S, one sample per column
%   Utility  the joint draw at this step: each column is a different
%           separator sample, so each needs its own frontal draw.
%
%   W is |grid| x N with nonnegative columns. Returns an N x 1 vector, using
%   vectorized inverse-CDF with linear interpolation inside the located bin.
%   Columns whose mass has collapsed fall back to the pooled mixture, and
%   the count of such columns is worth watching: it is the visible symptom
%   of the denominator instability the Slices spec asks us to track.

G = numel(gridVec);
N = size(W, 2);

W       = max(W, 0);
colMass = sum(W, 1);
bad     = colMass <= 0 | ~isfinite(colMass);

cdf = zeros(G, N);
ok  = ~bad;
if any(ok)
    cdf(:, ok) = cumsum(W(:, ok), 1) ./ colMass(ok);
end

u = rand(1, N);

% cdf is nondecreasing down each column, so the first row at or above u is
% G - (number of rows at or above u) + 1.
idx = G - sum(cdf >= u, 1) + 1;
idx = min(max(idx, 1), G);
lo  = max(idx - 1, 1);

cols = 1:N;
cHi  = cdf(sub2ind([G N], idx, cols));
cLo  = cdf(sub2ind([G N], lo,  cols));
gHi  = reshape(gridVec(idx), 1, []);
gLo  = reshape(gridVec(lo),  1, []);

span = cHi - cLo;
t    = zeros(1, N);
move = span > 0;
t(move) = (u(move) - cLo(move)) ./ span(move);

s = (gLo + t .* (gHi - gLo)).';

if any(bad)
    pooled = sum(W, 2);
    if sum(pooled) > 0
        s(bad) = core.ConditionalFactor.inverseCdfSample(gridVec, pooled, sum(bad));
    else
        error('methods:slices:allColumnsDegenerate', ...
            'Every conditional slice collapsed to zero mass.');
    end
end
end
