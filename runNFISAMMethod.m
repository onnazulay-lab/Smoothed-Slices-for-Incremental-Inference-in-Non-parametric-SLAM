function result = runNFISAMMethod(caseData, config)
%RUNNFISAMMETHOD NF-iSAM: Bayes tree of normalizing flows.
%
%   Inputs
%     CASEDATA  the case
%     CONFIG    the method config; incremental selects the second mode
%
%   Outputs
%     RESULT    the unified result structure of app specification section 8,
%               with the differences noted below: no separator support, no
%               generated-factor mass, and an estimator that declares itself
%               NORMALIZED
%
%   Utility
%     Train one conditional flow per Bayes tree clique (Algorithms N1-N3) and
%     draw the joint posterior root to leaf.
%
%   THE WHOLE METHOD, in the two calls this function makes:
%
%     METHODS.NFISAM.INCREMENTALUPDATE     the graph becomes a Bayes tree and
%                                          every clique gets a flow fitted to
%                                          simulated samples, leaf to root
%     METHODS.NFISAM.SAMPLEJOINTPOSTERIOR  the flows are read root to leaf,
%                                          each clique conditioned on the
%                                          separator values its parent drew
%
%   Everything else here is the contract: shaping what those two return into
%   the fields the comparative layer, the map view and the metrics table
%   already read from the other two methods.
%
%   THE BUILD ORDER of NF-iSAM spec section 15, and where it stands:
%     1. factor graph -> Bayes tree conversion and update      core.bayesTree
%     2. Clique objects with F_C, S_C, z_C                     core.BayesTreeClique
%     3. Algorithm N1  TrainingSampleSimulator                 methods.nfisam
%     4. autoregressive RQ spline flow, density and sampling   flows.RQSplineFlow
%     5. Algorithm N2  ConditionalSamplerTrainer: train        methods.nfisam
%        T_tilde on ordered samples (O, S, F), fix O = o,      ConditionalSampler
%        partition into T_S and T_F
%     6. Algorithm N3  incrementalUpdate: update the graph,    methods.nfisam
%        rebuild the tree, retrain leaf-to-root where the      cliqueKeys
%        clique identity changed, reuse the rest
%     7. root-to-leaf joint posterior sampling                 methods.nfisam
%                                                              sampleJointPosterior
%
%   TWO MODES, matching METHODS.RUNGENERALCORE so that a comparative run puts
%   all three methods in the same regime. By default the tree is built once
%   with all the data present and every clique is trained from scratch, which
%   is the batch pass. With CONFIG.INCREMENTAL the mission is replayed
%   k = 1..K and each increment reuses the flows whose cliques did not change;
%   RESULT.INCREMENT then carries the reuse fraction per increment, which is
%   the number the incremental claim lives or dies by. In batch there is
%   nothing to reuse and reporting a reuse rate would be reporting a zero as
%   if it were a result.
%
%   WHAT THIS METHOD RETURNS THAT THE OTHER TWO DO NOT, and the reverse.
%   Slices and Smoothed Slices carry a finite separator support and a
%   generated factor evaluated on it; NF-iSAM has neither, because a flow is
%   a density with no support to speak of. What it has instead is a normalized
%   posterior it can sample from directly, so RESULT.POSTERIOR.ESTIMATOR
%   declares itself NORMALIZED and METHODS.SCOREAGAINSTREFERENCE compares it
%   against the reference's normalized marginal rather than against the
%   unnormalized f_new. The mass of Eq. (19)'s generated factor is not among
%   this method's outputs and is reported as NaN rather than guessed at.
%
%   THE MARGINAL CURVE IS A RECONSTRUCTION, and is the one place this method
%   is scored through something it did not produce. NF-iSAM's answer is a set
%   of joint draws; the quadrature reference is a curve on a grid, and the
%   two only meet if one is turned into the other. The draws are turned into
%   a density by a Gaussian kernel estimate, marked as such on
%   RESULT.POSTERIOR.ESTIMATOR.RECONSTRUCTION, and used for nothing else: the
%   MMD and the RMSE that the comparison actually turns on are computed from
%   the draws themselves, where no bandwidth choice can reach them.

arguments
    caseData (1,1) struct
    config (1,1) struct = methods.commonMethodConfig()
end

seedInfo = utils.setRandomSeed(config.seed);
if isfield(caseData, 'counter') && ~isempty(caseData.counter)
    caseData.counter.reset();
end

incremental = isfield(config, 'incremental') && config.incremental ...
    && isfield(caseData, 'increments') && ~isempty(caseData.increments);

% The split is lopsided in a way the other two methods are not: fitting the
% flows is essentially all of the cost and drawing from them is essentially
% none of it, so the bar gives the training pass almost everything.
p = utils.progressOf(config);

% --- Forward: the tree and its flows --------------------------------------
tf = tic;
if incremental
    [state, updates] = localReplay(caseData, config, p.sub(0, 0.95));
else
    [state, updates] = localBatch(caseData, config, p.sub(0, 0.95));
end
runtimeForward = toc(tf);
forwardEvals = localEvals(caseData);

% --- Backward: the root-to-leaf draw --------------------------------------
p.report(0.95, "drawing the joint posterior root to leaf");
tb = tic;
[draws, drawInfo] = methods.nfisam.sampleJointPosterior(state, config.numBackwardSamples);
runtimeBackward = toc(tb);
backwardEvals = localEvals(caseData) - forwardEvals;

% --- The contract ---------------------------------------------------------
result = struct();
result.methodName = "NF-iSAM";
result.status     = "ok";
result.config     = utils.serializableConfig(config);
result.case       = struct('name', caseData.name, 'variant', caseData.variant, ...
                           'displayName', caseData.displayName, ...
                           'settings', caseData.settings);
result.seed       = seedInfo;

result.increment = localIncrementRecords(updates, caseData, incremental);

result.posterior = localPosterior(draws, state, caseData, config);

result.bayesNet = localBayesNet(state.tree);

health = localHealth(updates, state, drawInfo);

result.metrics = struct( ...
    'runtimeTotal',      runtimeForward + runtimeBackward, ...
    'runtimeForward',    runtimeForward, ...
    'runtimeBackward',   runtimeBackward, ...
    'factorEvaluations', localEvals(caseData), ...
    'factorEvalsForward',  forwardEvals, ...
    'factorEvalsBackward', backwardEvals, ...
    'health',            health, ...
    'incremental',       localIncrementSummary(updates, incremental), ...
    'cardinality',       struct('outer', config.nfisamTrainSamples, ...
                                'separator', health.maxSeparatorDim));

if isfield(caseData, 'mission') && isfield(caseData, 'groundTruth')
    [result.map, mapMetrics] = localMapBlock(draws, caseData);
    result.metrics = localMerge(result.metrics, mapMetrics);
end

result.process = localProcessTrace(state, updates, config);
result.states  = core.EliminationState.empty(1, 0);
result.figures = methods.figureRegistryFor("NF-iSAM");
result.logs    = localLogs(updates, health, incremental, config, localEvals(caseData));

% Follows the paper's clique factorization, with a rebuilt tree, sample-based
% separator propagation and a custom flow. Recorded rather than implied.
result.implementation = methods.implementationRecord("NF-iSAM", "bayes_tree_flow");

result.plan = struct( ...
    'iteration', 3, ...
    'buildOrder', ["bayes tree", "cliques", "Algorithm N1", "RQ spline flow", ...
                   "Algorithm N2", "Algorithm N3", "top-down sampling"], ...
    'buildOrderDone', 7, ...
    'flowBackendDecided', true, ...
    'flowBackend', "flows.RQSplineFlow");
end

% =========================================================================
function [state, updates] = localBatch(caseData, config, p)
%LOCALBATCH One update with all the data present, which is the batch solve.
%   Inputs   CASEDATA, CONFIG, P the progress reporter
%   Outputs  STATE the trained state, UPDATES the one update's record
%   Utility  the first call from an empty state finds an empty cache and
%           trains every clique, so no separate batch entry point exists.
%
%   METHODS.NFISAM.INITIALSTATE documents why there is no separate batch
%   entry point. The first update has nothing cached, so its retraining set
%   is every clique, which is the batch solve by construction rather than by
%   a second code path that could drift from the incremental one.
state = methods.nfisam.initialState(caseData.graph, caseData.eliminationOrder);
[state, info] = methods.nfisam.incrementalUpdate(state, core.Factor.empty(1,0), ...
    'NumSamples', config.nfisamTrainSamples, ...
    'Training',   config.nfisamTraining, ...
    'Reuse',      config.nfisamReuse, ...
    'Progress',   p);
info.k = 1;
updates = info;
end

% =========================================================================
function [state, updates] = localReplay(caseData, config, p)
%LOCALREPLAY The mission replayed k = 1..K, reusing what did not change.
%   Inputs   CASEDATA, CONFIG, P the progress reporter
%   Outputs  STATE the final state, UPDATES one record per increment
%   Utility  produce the reuse fraction the incremental claim lives by.
%
%   The first increment builds the state; the rest are Algorithm N3 proper.
%
%   THE CASE'S INTENDED FULL ORDER IS RESTRICTED TO THE VARIABLES PRESENT at
%   each increment and passed to Algorithm N3 as the preferred order. This is
%   required on Plaza: landmarks may appear in an early increment, while later
%   poses must still precede them in the poses-first / landmarks-last order.
%   Purely appending new variables would permanently place those later poses
%   behind early landmarks and can strand an ambiguous data-association factor
%   in a clique before its pose has an ancestral/binary sampling route.
%   INFO.orderSource records whether the preferred restricted order, the stable
%   append order, or a fresh recomputation was used.
incs = caseData.increments;
K = numel(incs);
recs = cell(1, K);
state = [];

for k = 1:K
    [vars, facs] = localIncrementContent(caseData, incs(k));
    pk = p.sub((k-1)/K, k/K);
    pk.report(0, sprintf("increment %d of %d", k, K));

    if isempty(state)
        g = core.FactorGraph(vars, facs, localCounter(caseData));
        state = methods.nfisam.initialState(g, g.VariableNames);
        [state, info] = methods.nfisam.incrementalUpdate(state, core.Factor.empty(1,0), ...
            'PreferredOrder', caseData.eliminationOrder, ...
            'NumSamples', config.nfisamTrainSamples, ...
            'Training',   config.nfisamTraining, ...
            'Reuse',      config.nfisamReuse, ...
            'Progress',   pk);
    else
        [state, info] = methods.nfisam.incrementalUpdate(state, facs, ...
            'NewVariables',   vars, ...
            'PreferredOrder', caseData.eliminationOrder, ...
            'NumSamples',     config.nfisamTrainSamples, ...
            'Training',       config.nfisamTraining, ...
            'Reuse',          config.nfisamReuse, ...
            'Progress',       pk);
    end

    info.k = k;
    recs{k} = info;
end

updates = [recs{:}];
end

% =========================================================================
function [vars, facs] = localIncrementContent(caseData, inc)
%LOCALINCREMENTCONTENT What one increment introduces.
%   Inputs   CASEDATA the case, INC the increment
%   Outputs  VARS the new variables, FACS the new factors
%   Utility  incrementalUpdate will not infer a variable, because a variable
%           carries a domain; this reads the ones the case declared.
g = caseData.graph;

names = inc.newVariables;
% Sorted by the case's own elimination order, so that the appended tail of
% the order is at least locally what the case would have chosen.
[~, ord] = ismember(names, caseData.eliminationOrder);
ord(ord == 0) = numel(caseData.eliminationOrder) + 1;
[~, perm] = sort(ord);
names = names(perm);

vars = core.Variable.empty(1, 0);
for i = 1:numel(names)
    vars(end+1) = g.variable(names(i)); %#ok<AGROW>
end

facs = g.Factors(inc.factorIndex);
end

% =========================================================================
function c = localCounter(caseData)
%LOCALCOUNTER The case's factor-evaluation counter, if it has one.
%   Inputs   CASEDATA, the case
%   Outputs  C, the counter or []
%   Utility  read it so the count can be reported -- knowing it will be zero,
%           since Algorithm N1 simulates rather than evaluates.
if isfield(caseData, 'counter') && ~isempty(caseData.counter)
    c = caseData.counter;
else
    c = core.EvalCounter();
end
end

function n = localEvals(caseData)
%LOCALEVALS How many factor evaluations this method spent.
%   Inputs   CASEDATA, the case
%   Outputs  N, the count
%   Utility  it is zero by construction, which is why this method is excluded
%           from the cost axis by default rather than plotted as free.
if isfield(caseData, 'counter') && ~isempty(caseData.counter)
    n = caseData.counter.snapshot();
else
    n = NaN;
end
end

% =========================================================================
function post = localPosterior(draws, state, caseData, config)
%LOCALPOSTERIOR The posterior block, from joint draws alone.
%   Inputs   DRAWS the joint samples, STATE the trained state, CASEDATA,
%           CONFIG
%   Outputs  POST, the posterior block of the result contract
%   Utility  declare the estimator NORMALIZED and mark the marginal curve as
%           a reconstruction, since it is the one thing here the method did
%           not itself produce.
%
%   The two drivers disagree about what MARGINALS means -- the three-node one
%   stores a grid and a density per variable, the general one stores the
%   sample matrix -- and the scorers read whichever the case implies. This
%   answers in the caller's dialect rather than adding a third.
post = struct();
post.samples    = draws;
post.joint      = draws;
post.numSamples = config.numBackwardSamples;

general = isfield(caseData, 'engine') && caseData.engine == "general";
if general
    post.marginals = draws;
    return
end

% --- The three-node dialect: a curve per variable and a target estimator ---
grids     = struct();
marginals = struct();
for name = state.order
    key = matlab.lang.makeValidName(name);
    if ~isfield(draws, key), continue, end
    s = draws.(key);
    if size(s, 2) ~= 1, continue, end        % a curve is a 1-D notion
    gridVec = caseData.graph.variable(name).grid(config.marginalGridSize);
    pdfVec  = localKernelDensity(s, gridVec);
    grids.(key) = gridVec;
    marginals.(key) = struct('variable', name, 'grid', gridVec, ...
        'pdf', reshape(pdfVec, 1, []), ...
        'mean', mean(s));                    % from the draws, not from the curve
end
post.grids     = grids;
post.marginals = marginals;

% --- The estimator block --------------------------------------------------
target = caseData.targetVariable;
key    = matlab.lang.makeValidName(target);

support = caseData.graph.variable(target).grid(config.marginalGridSize);
if isfield(config, 'separatorSupport') && ~isempty(config.separatorSupport)
    % The reference's own support, when the comparison provided one: every
    % method is then evaluated at the same points and no interpolation
    % stands between an estimate and the truth.
    support = reshape(config.separatorSupport, 1, []);
end

est = struct();
est.variable   = target;
est.support    = support;
est.normalized = true;
est.reconstruction = "Gaussian kernel density estimate of the posterior " + ...
    "draws, Silverman bandwidth. Not part of the method: NF-iSAM returns " + ...
    "samples and a flow, and this curve exists only so that a sample-based " + ...
    "posterior can be compared against a reference defined on a grid.";

if isfield(draws, key) && size(draws.(key), 2) == 1
    est.pdf = reshape(localKernelDensity(draws.(key), support), 1, []);
else
    est.pdf = nan(1, numel(support));
end
est.fnew = est.pdf;      % normalized: there is no unnormalized counterpart
est.mass = NaN;          % and therefore no mass to report
post.estimator = est;
end

% =========================================================================
function p = localKernelDensity(s, gridVec)
%LOCALKERNELDENSITY A Gaussian kernel estimate of one variable's marginal.
%   Inputs   S the samples, GRIDVEC the grid to evaluate on
%   Outputs  P, the density
%   Utility  the ONLY place a bandwidth is chosen in this project, used to
%           draw a curve against the quadrature reference and for nothing
%           else: the MMD and the RMSE come from the draws themselves.
%
%   Written out rather than taken from ksdensity because this curve is the
%   only thing standing between the draws and a reported error figure, and a
%   toolbox default chosen somewhere else would be an unrecorded assumption
%   inside a number the comparison turns on. The bandwidth rule belongs where
%   the curve is made, so it is four lines and they are here.
s = s(:);
n = numel(s);
sd = std(s);
iqr_ = diff(prctileLocal(s, [25 75]));
spread = min(sd, iqr_ / 1.349);
if ~(spread > 0), spread = sd; end
if ~(spread > 0), spread = 1; end
h = 0.9 * spread * n^(-1/5);

g = gridVec(:);
p = mean(exp(-0.5 * ((g.' - s) / h).^2), 1) / (h * sqrt(2*pi));
p = reshape(p, size(gridVec));

mass = trapz(gridVec(:), p(:));
if mass > 0
    p = p / mass;
end
end

function q = prctileLocal(s, pcts)
%PRCTILELOCAL Percentiles without the Statistics Toolbox.
%   Inputs   S the samples, PCTS the percentiles wanted
%   Outputs  Q, the values
%   Utility  keep the method runnable without a toolbox it needs for nothing
%           else.
s = sort(s(:));
n = numel(s);
pos = pcts(:).' / 100 * n + 0.5;
pos = min(max(pos, 1), n);
lo = floor(pos); hi = ceil(pos);
q = s(lo).' + (pos - lo) .* (s(hi).' - s(lo).');
end

% =========================================================================
function bn = localBayesNet(tree)
%LOCALBAYESNET The Bayes tree flattened into the Bayes-net shape the app draws.
%   Inputs   TREE, the core.BayesTree
%   Outputs  BN, one entry per clique with its frontals and separator
%   Utility  the process panels are written against the elimination methods'
%           conditionals, and a clique is the nearest true equivalent.
if isempty(tree.cliques)
    bn = struct('factorization', "", 'latex', "");
    return
end
parts = strings(1, numel(tree.cliques));
tex   = strings(1, numel(tree.cliques));
for c = 1:numel(tree.cliques)
    cl = tree.cliques(c);
    F = strjoin(cl.Frontal, ",");
    Ftex = strjoin(cellstr(utils.mathName(cl.Frontal)), ",");
    if isempty(cl.Separator)
        parts(c) = sprintf("p(%s|z)", F);
        tex(c)   = sprintf("p(%s \\mid z)", Ftex);
    else
        S = strjoin(cl.Separator, ",");
        Stex = strjoin(cellstr(utils.mathName(cl.Separator)), ",");
        parts(c) = sprintf("p(%s|%s,z)", F, S);
        tex(c)   = sprintf("p(%s \\mid %s, z)", Ftex, Stex);
    end
end
bn = struct('factorization', strjoin(parts, " "), ...
            'latex', "$" + strjoin(tex, "\,") + "$");
end

% =========================================================================
function recs = localIncrementRecords(updates, caseData, incremental)
%LOCALINCREMENTRECORDS One record per increment, for the replay table.
%   Inputs   UPDATES the per-update info, CASEDATA, INCREMENTAL which mode
%   Outputs  RECS, the records
%   Utility  a batch pass has one update and no increments, and must still
%           return the field set the table reads.
%
%   ORDER is here because the Process Explorer reads it to redraw the Bayes
%   net in the order a run actually eliminated in, which for a replay is not
%   the case's order.
n = numel(updates);
recs = struct([]);
for i = 1:n
    u = updates(i);
    nNew = 0;
    if incremental && isfield(caseData, 'increments') && u.k <= numel(caseData.increments)
        nNew = numel(caseData.increments(u.k).factorIndex);
    elseif ~incremental
        nNew = caseData.graph.NumFactors;
    end

    recs(i).k             = u.k;
    recs(i).numNewFactors = nNew;
    recs(i).order         = u.order;
    recs(i).orderSource   = u.orderSource;
    recs(i).numCliques    = u.numCliques;
    recs(i).trained       = numel(u.trained);
    recs(i).reused        = numel(u.reused);
    recs(i).reuseFraction = u.reuseFraction;
    recs(i).runtime       = u.runtime;
    recs(i).status        = "ok";
end
end

% =========================================================================
function s = localIncrementSummary(updates, incremental)
%LOCALINCREMENTSUMMARY The replay summary, or the batch pass's version of it.
%   Inputs   UPDATES the per-update info, INCREMENTAL which mode
%   Outputs  S, the summary
%   Utility  in batch the counts are real and the RATE stays NaN: NaN is "not
%           applicable" and 0 is "tried and failed", and only one is true.
%
%   Both modes report numTrained and numReused, counted the same way from the
%   same field. The batch branch used to hardcode cacheHits = 0 AND
%   cacheMisses = 0, which reads as a run that did no work at all -- for a pass
%   that trains every clique in the tree. Zero hits is right; zero misses is
%   not, and the pair together made the batch counterfactual look free next to
%   the incremental run it exists to be compared against.
hits   = sum(arrayfun(@(u) numel(u.reused), updates));
misses = sum(arrayfun(@(u) numel(u.trained), updates));

if ~incremental
    % THE RATE STAYS NaN HERE WHILE THE COUNTS ARE REAL, and the two are not in
    % tension. cacheMisses is a count of work actually done, so reporting it as
    % zero was the bug fixed above. A hit RATE is a different kind of claim: it
    % answers "of the cliques that could have been reused, how many were", and
    % on a batch pass nothing could have been, because there was no cache to
    % hit. Computing 0/(0+N) = 0 would answer a question nobody asked and read
    % as a reuse mechanism that ran and achieved nothing, which is exactly what
    % the incremental comparison must not be allowed to conclude. NaN is "not
    % applicable" and 0 is "tried and failed"; only one of those is true.
    s = struct('mode', "batch", 'numIncrements', numel(updates), ...
        'numCompleted', numel(updates), ...
        'cacheHitRate', NaN, ...
        'cacheHits', hits, 'cacheMisses', misses, ...
        'numTrained', misses, 'numReused', hits, ...
        'meanCliquesReused', mean(arrayfun(@(u) numel(u.reused), updates)), ...
        'numOrderRecomputes', 0, ...
        'treeWasRebuilt', true, ...
        'reuseRule', "batch pass: nothing was cached beforehand, so every clique was trained", ...
        'note', "batch pass: the tree was built once, so no clique had a previous flow to keep");
    return
end

s = struct( ...
    'mode',               "incremental", ...
    'numIncrements',      numel(updates), ...
    'numCompleted',       numel(updates), ...
    'cacheHitRate',       localRate(hits, hits + misses), ...
    'cacheHits',          hits, ...
    'cacheMisses',        misses, ...
    'numTrained',         misses, ...
    'numReused',          hits, ...
    'meanCliquesReused',  mean(arrayfun(@(u) numel(u.reused), updates)), ...
    'numOrderRecomputes', sum(arrayfun(@(u) u.orderSource == "recomputed", updates)), ...
    ... % True on every update, and worth stating next to the reuse numbers: a
    ... % clique kept its flow because its subtree key matched, not because the
    ... % tree around it was left standing.
    'treeWasRebuilt',     all(arrayfun(@(u) u.treeWasRebuilt, updates)), ...
    'reuseRule',          updates(end).reuseRule, ...
    'note',               "hit rate counts cliques whose subtree key was already cached");
end

function r = localRate(a, b)
%LOCALRATE A over B, or NaN when there was nothing to divide.
%   Inputs   A, B
%   Outputs  R, the ratio or NaN
%   Utility  the same distinction, in the one place both branches share.
if b == 0, r = NaN; else, r = a / b; end
end

% =========================================================================
function h = localHealth(updates, state, drawInfo)
%LOCALHEALTH The engine-health block: what this method can report and cannot.
%   Inputs   UPDATES the per-update info, STATE the trained state, DRAWINFO
%           the sampling pass's record
%   Outputs  H, the health block
%   Utility  report the ESS of the child-separator products, and NaN -- not
%           zero -- for the support ESS this method has no support to have.
%
%   Not the Slices ones. There is no finite support here and no
%   nearest-neighbour lookup, so reporting those fields with plausible
%   numbers in them would be inventing a diagnostic. What can go wrong with a
%   trained flow is that it overfitted -- visible as a held-out log likelihood
%   below the training one -- that the fixed measurement landed outside the
%   support the flow was fitted on, or that a product of two children's
%   separator densities was carried by a handful of the samples.
%
%   COLLECTED OVER EVERY INCREMENT, not only the last. A clique reused at the
%   final increment was fitted earlier and its held-out score was recorded
%   then; reading only the last increment would report the health of whatever
%   happened to be refitted at the end and call it the health of the tree.
per = struct([]);
for i = 1:numel(updates)
    p = updates(i).perClique;
    for j = 1:numel(p)
        if p(j).action ~= "trained", continue, end
        if isempty(per), per = p(j); else, per(end+1) = p(j); end %#ok<AGROW>
    end
end

flowDim = 0; sepDim = 0;
for c = 1:numel(state.tree.cliques)
    s = state.samplers{c};
    if isa(s, 'methods.nfisam.ConditionalSampler')
        flowDim = max(flowDim, s.Flow.Dimension);
        sepDim  = max(sepDim, s.separatorWidth());
    end
end

held  = localCollect(per, 'heldOutLogLikelihood');
train = localCollect(per, 'logLikelihood');
ess   = localCollect(per, 'minEffectiveSampleSize');
z     = localCollect(per, 'maxObservationZ');
outOf = localCollect(per, 'outOfSupport');

approximated = string.empty(1, 0);
for i = 1:numel(per)
    approximated = [approximated per(i).approximatedSeparators]; %#ok<AGROW>
end

h = struct();
h.numCliques          = numel(state.tree.cliques);
h.maxFlowDim          = flowDim;
h.maxSeparatorDim     = sepDim;
h.minEffectiveSampleSize = min([ess Inf]);
h.maxObservationZ     = max([z 0]);
h.numOutOfSupport     = nnz(outOf);
h.minHeldOutLogLikelihood = min([held Inf]);
h.meanTrainLogLikelihood  = mean(train, 'omitnan');
h.approximatedSeparators  = unique(approximated);
h.numRoots            = drawInfo.numRoots;
h.summary = sprintf("%d cliques, max flow dim %d, %d approximate separator(s)", ...
    h.numCliques, h.maxFlowDim, numel(h.approximatedSeparators));

% The two fields plotEngineHealth reads from the Slices side. NaN, not a
% number: this method has neither quantity, and a zero would read as perfect
% health rather than as absent.
h.minEssSupport = NaN;
h.lookupMean    = NaN;
end

function v = localCollect(per, field)
%LOCALCOLLECT One field gathered across every per-clique record.
%   Inputs   PER the records, FIELD the field
%   Outputs  V, the values
%   Utility  summarise across cliques without every caller writing the loop.
v = [];
for i = 1:numel(per)
    if isfield(per(i), field) && isscalar(per(i).(field))
        v(end+1) = double(per(i).(field)); %#ok<AGROW>
    end
end
v = v(~isnan(v));
end

% =========================================================================
function [map, mm] = localMapBlock(draws, caseData)
%LOCALMAPBLOCK The map view's block: a mean and a cloud per pose and landmark.
%   Inputs   DRAWS the joint samples, CASEDATA the case
%   Outputs  MAP the block, MM the pose and landmark RMSEs
%   Utility  give the map view the same block the other two methods return,
%           so one panel draws all three.
poseNames = caseData.mission.poseNames;
nPose = numel(poseNames);
poseDim = size(caseData.groundTruth.poses, 2);

poseMean = nan(nPose, poseDim);
poseCov = cell(1, nPose);
poseSamples = cell(1, nPose);
for i = 1:nPose
    key = matlab.lang.makeValidName(poseNames(i));
    if ~isfield(draws, key), continue, end
    P = draws.(key);
    poseMean(i,:) = mean(P, 1);
    poseCov{i} = cov(P);
    poseSamples{i} = P;
end

gt = caseData.groundTruth;
poseErr = vecnorm(poseMean - gt.poses, 2, 2);

hasLandmarks = isfield(caseData, 'landmarks');
lmNames = string.empty(1, 0);
lmMean = zeros(0, poseDim);
lmSamples = {};
lmErr = zeros(0, 1);
obs = false(0, 1);

if hasLandmarks
    lmNames = caseData.landmarks.names;
    lmMean = nan(numel(lmNames), poseDim);
    lmSamples = cell(1, numel(lmNames));
    for i = 1:numel(lmNames)
        key = matlab.lang.makeValidName(lmNames(i));
        if ~isfield(draws, key), continue, end
        P = draws.(key);
        lmMean(i,:) = mean(P, 1);
        lmSamples{i} = P;
    end
    obs = caseData.landmarks.observed(:);
    lmErr = nan(numel(lmNames), 1);
    lmErr(obs) = vecnorm(lmMean(obs,:) - gt.landmarks(obs,:), 2, 2);
end

map = struct( ...
    'poseMean', poseMean, 'poseCov', {poseCov}, 'poseSamples', {poseSamples}, ...
    'landmarkMean', lmMean, 'landmarkSamples', {lmSamples}, ...
    'landmarkNames', lmNames, 'poseNames', poseNames, ...
    'hasLandmarks', hasLandmarks);

mm = struct( ...
    'poseRMSE',     localRms(poseErr), ...
    'poseMaxError', max(poseErr), ...
    'poseErrors',   poseErr, ...
    'landmarkRMSE', localRms(lmErr(obs)), ...
    'rmse',         localRms([poseErr; lmErr(obs)]));
end

function v = localRms(e)
%LOCALRMS Root-mean-square of the per-row residual norms.
%   Inputs   E, an n-by-d residual matrix
%   Outputs  V, the scalar RMSE
%   Utility  one definition of pose error, matching the other drivers'.
e = e(~isnan(e));
if isempty(e), v = NaN; else, v = sqrt(mean(e.^2)); end
end

function a = localMerge(a, b)
%LOCALMERGE Copy every field of B onto A.
%   Inputs   A the base struct, B the additions
%   Outputs  A, merged
%   Utility  assemble the result contract in pieces without a long literal.
for f = string(fieldnames(b)).'
    a.(f) = b.(f);
end
end

% =========================================================================
function trace = localProcessTrace(state, updates, config)
%LOCALPROCESSTRACE The Process Explorer trace, in clique vocabulary.
%   Inputs   STATE the trained state, UPDATES the per-update info, CONFIG
%   Outputs  TRACE, an ordered dense stage list
%   Utility  the same contract methods.buildProcessTrace returns; the stages
%           are cliques rather than eliminations, which is what this method
%           actually has.
%
%   Same contract as METHODS.BUILDGENERALPROCESSTRACE, different vocabulary:
%   this method has no elimination steps to step through, it has cliques, and
%   the stage slider walks them leaf to root the way Algorithm N3 did.
per = updates(end).perClique;
stages = struct('stageType', {}, 'nodeLabel', {}, 'latex', {}, ...
                'cardinality', {}, 'diagnostics', {}, 'step', {});

order = state.keys.leafToRoot;           % deepest first, as Algorithm N3 visited them

step = 0;
for c = order
    step = step + 1;
    r = per([per.index] == c);
    if isempty(r), continue, end
    r = r(1);

    stages(end+1) = struct( ...
        'stageType',   "cliqueFlow", ...
        'nodeLabel',   sprintf('clique %d: %s [%s]', c, r.label, r.action), ...
        'latex',       localCliqueLatex(r), ...
        'cardinality', struct('outer', config.nfisamTrainSamples, ...
                              'separator', 0, ...
                              'separatorDim', numel(r.separator)), ...
        'diagnostics', r, ...
        'step',        step); %#ok<AGROW>
end

trace = struct();
trace.method     = "NF-iSAM";
trace.stages     = stages;
trace.numStages  = numel(stages);
trace.stageTypes = "cliqueFlow";
trace.budgets    = struct('numSamples', config.nfisamTrainSamples, ...
                          'separatorSupportSize', NaN);
end

function s = localCliqueLatex(r)
%LOCALCLIQUELATEX The LaTeX line the Process Explorer shows for one clique.
%   Inputs   R, one clique's record
%   Outputs  S, its equation line
%   Utility  specification section 4 requires every mathematical string in the
%           UI to be rendered as LaTeX, and the stage caption is one.
F = strjoin(cellstr(utils.mathName(r.frontal)), ",");
if isempty(r.separator)
    s = sprintf('$p(%s \\mid z_C)$', F);
else
    S = strjoin(cellstr(utils.mathName(r.separator)), ",");
    s = sprintf('$p(%s \\mid %s, z_C)$', F, S);
end
end

% =========================================================================
function logs = localLogs(updates, health, incremental, config, evals)
%LOCALLOGS The engine warnings this run earned, as text.
%   Inputs   UPDATES, HEALTH, INCREMENTAL which mode, CONFIG, EVALS the factor
%           evaluation count
%   Outputs  LOGS, a string array
%   Utility  say the things a reader would otherwise have to infer: that the
%           evaluation count is zero by construction, that a measurement
%           landed outside the simulated spread, that nothing was reused.
logs = strings(0, 1);

% A ZERO IN THE FACTOR-EVALUATION COLUMN IS A RESULT, not a missing number,
% and next to the tens of millions the elimination methods spend it will be
% read as a stub unless it is said out loud. Algorithm N1 is generative: it
% draws from a factor and never asks it for a value, so the cost of this
% method is gradient steps rather than factor calls, and the two columns are
% not commensurable. What it spends instead is on the line after.
if isfinite(evals) && evals == 0
    logs(end+1) = sprintf(['0 factor evaluations. Algorithm N1 simulates from ' ...
        'the factors rather than evaluating them, so this method''s cost is ' ...
        '%d clique fit(s) at n_train = %d, not factor calls. The column is ' ...
        'not comparable with the elimination methods'' -- read the runtime.'], ...
        sum(arrayfun(@(u) numel(u.trained), updates)), config.nfisamTrainSamples);
end

if incremental
    hits = sum(arrayfun(@(u) numel(u.reused), updates));
    tot  = hits + sum(arrayfun(@(u) numel(u.trained), updates));
    recomputes = sum(arrayfun(@(u) u.orderSource == "recomputed", updates));
    logs(end+1) = sprintf(['Incremental replay: %d increments, %d of %d clique ' ...
        'fits avoided by reuse (%.0f%%), %d order recomputation(s).'], ...
        numel(updates), hits, tot, 100 * localRate(hits, tot), recomputes);
    if recomputes > 0
        logs(end+1) = sprintf(['%d increment(s) could not append to the ' ...
            'elimination order and recomputed it. A recomputed order ' ...
            'renumbers and reshapes cliques, so every cached flow was ' ...
            'discarded on those increments.'], recomputes);
    end
end

if ~isempty(health.approximatedSeparators)
    logs(end+1) = sprintf(['%d separator product(s) were approximated by ' ...
        'keeping the first child''s draws: %s. Partially overlapping ' ...
        'separators need a marginal a flow does not give in closed form.'], ...
        numel(health.approximatedSeparators), ...
        strjoin(health.approximatedSeparators, "; "));
end

if isfinite(health.minEffectiveSampleSize) && health.minEffectiveSampleSize < 0.1 * config.nfisamTrainSamples
    logs(end+1) = sprintf(['A product of children''s separator densities fell ' ...
        'to an effective sample size of %.0f out of %d. The parent clique was ' ...
        'trained on far fewer distinct samples than it was given.'], ...
        health.minEffectiveSampleSize, config.nfisamTrainSamples);
end

if health.numOutOfSupport > 0
    logs(end+1) = sprintf(['%d clique(s) fixed their observation outside the ' ...
        'range the flow was fitted on. The conditional is being read where it ' ...
        'has no training data behind it.'], health.numOutOfSupport);
end

if isfinite(health.minHeldOutLogLikelihood) && isfinite(health.meanTrainLogLikelihood) ...
        && health.minHeldOutLogLikelihood < health.meanTrainLogLikelihood - 0.5
    logs(end+1) = sprintf(['Held-out log likelihood fell to %.2f against %.2f ' ...
        'on the training samples. At n_train = %d a wide clique overfits, and ' ...
        'the flow is then confident where it has seen nothing.'], ...
        health.minHeldOutLogLikelihood, health.meanTrainLogLikelihood, ...
        config.nfisamTrainSamples);
end
end
