function result = runGeneralCore(methodName, caseData, config)
%RUNGENERALCORE Shared driver for the general-graph cases.
%
%   Inputs
%     METHODNAME  "Slices" or "Smoothed Slices"
%     CASEDATA    the case
%     CONFIG      the method config; incremental selects the second mode
%
%   Outputs
%     RESULT      the same contract as the three-node driver, plus a MAP block
%                 the map view reads: one estimated position and one posterior
%                 sample cloud per pose, per method
%
%   Utility
%     Run the general elimination engine on a graph of any size, through ONE
%     driver for both methods so the harness cannot explain a difference
%     between them.
%
%   As with runInferenceCore, Slices and Smoothed Slices differ here in
%   exactly one field of CONFIG. Routing both through one driver is what
%   rules out the harness as an explanation for any difference between them.
%
%   TWO MODES. By default the graph is eliminated ONCE with all the data
%   present, which is the batch pass every number this project reports was
%   measured on. With CONFIG.INCREMENTAL the mission is replayed k = 1..K by
%   methods.general.runIncrementalGeneral, and RESULT.POSTERIOR is then the
%   last increment's -- including whatever the MMD stopping rule chose to
%   carry forward rather than re-derive. RESULT.INCREMENT carries a record
%   per increment either way; only in replay does it carry any content.

arguments
    methodName (1,1) string
    caseData (1,1) struct
    config (1,1) struct
end

seedInfo = utils.setRandomSeed(config.seed);
caseData.counter.reset();

incremental = isfield(config, 'incremental') && config.incremental ...
    && isfield(caseData, 'increments') && ~isempty(caseData.increments);

p = utils.progressOf(config);

if incremental
    % The mission replayed as it arrives. The forward pass reuses the
    % unchanged prefix of the elimination and the backward pass stops once
    % the marginals stop moving; both boundaries are reported per increment
    % rather than folded into a single runtime number, because the whole
    % claim being made is about WHERE the work was avoided.
    inc = methods.general.runIncrementalGeneral(caseData, ...
        localWithProgress(config, p.sub(0, 0.97)));
    conds  = inc.final.conditionals;
    states = inc.final.states;
    book   = inc.final.book;
    post   = inc.final.post;

    runtimeForward  = sum([inc.increments.runtimeForward],  'omitnan');
    runtimeBackward = sum([inc.increments.runtimeBackward], 'omitnan');
    forwardEvals    = sum([inc.increments.factorEvalsForward]);
    backwardEvals   = sum([inc.increments.factorEvalsBackward]);
    incrementRecords = inc.increments;
    incrementSummary = localIncrementSummary(inc);
else
    tf = tic;
    [conds, states, book, root] = methods.general.forwardEliminationGeneral( ...
        caseData, localWithProgress(config, p.sub(0, 0.65)));
    runtimeForward = toc(tf);
    forwardEvals = caseData.counter.snapshot();

    tb = tic;
    post = methods.general.backwardSampleGeneral(conds, root, caseData, ...
        localWithProgress(config, p.sub(0.65, 0.97)));
    runtimeBackward = toc(tb);
    backwardEvals = caseData.counter.snapshot() - forwardEvals;

    nInc = 1;
    if isfield(caseData, 'numIncrements'), nInc = caseData.numIncrements; end
    incrementRecords = struct('k', num2cell(1:nInc));
    incrementSummary = struct('mode', "batch", ...
        'numIncrements', nInc, 'numCompleted', NaN, 'numFailed', 0, ...
        'firstFailure', "", ...
        'cacheHitRate', NaN, 'cacheHits', 0, 'cacheMisses', 0, ...
        'numEarlyStops', 0, 'numStopsIndistinguishable', 0, ...
        'meanVariablesReused', 0, ...
        'meanVariablesResampled', NaN, 'minMMDAtStop', NaN, ...
        'note', "batch pass: the graph was eliminated once, with all data present");
end

% --- Pose block -----------------------------------------------------------
% Every general case has poses. Only some have landmarks and a map: Four
% Doors is a bare chain in one dimension, and asking it for a landmark list
% would be asking it to pretend to be a different experiment.
poseNames = caseData.mission.poseNames;
nPose = numel(poseNames);
poseDim = size(caseData.groundTruth.poses, 2);

poseMean = nan(nPose, poseDim);
poseCov = cell(1, nPose);
poseSamples = cell(1, nPose);
for i = 1:nPose
    key = matlab.lang.makeValidName(poseNames(i));
    if ~isfield(post.marginals, key), continue, end
    P = post.marginals.(key);
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
        if ~isfield(post.marginals, key), continue, end
        P = post.marginals.(key);
        lmMean(i,:) = mean(P, 1);
        lmSamples{i} = P;
    end
    obs = caseData.landmarks.observed(:);
    lmErr = nan(numel(lmNames), 1);
    lmErr(obs) = vecnorm(lmMean(obs,:) - gt.landmarks(obs,:), 2, 2);
end

result.map = struct( ...
    'poseMean', poseMean, 'poseCov', {poseCov}, 'poseSamples', {poseSamples}, ...
    'landmarkMean', lmMean, 'landmarkSamples', {lmSamples}, ...
    'landmarkNames', lmNames, 'poseNames', poseNames, ...
    'hasLandmarks', hasLandmarks);

% --- Engine health, reported rather than implied -------------------------
essOuter = []; essSupport = []; sepDims = []; supportSizes = [];
for s = states
    if ~isfield(s.Diagnostics, 'essOuter'), continue, end
    essOuter(end+1) = s.Diagnostics.essOuter; %#ok<AGROW>
    essSupport(end+1) = s.Diagnostics.essSupport; %#ok<AGROW>
    sepDims(end+1) = s.Diagnostics.separatorDim; %#ok<AGROW>
    supportSizes(end+1) = s.Diagnostics.numSupport; %#ok<AGROW>
end

health = struct( ...
    'minEssOuter', min([essOuter Inf]), 'meanEssOuter', mean(essOuter), ...
    'minEssSupport', min([essSupport Inf]), 'meanEssSupport', mean(essSupport), ...
    'maxSeparatorDim', max([sepDims 0]), ...
    'maxSupportSize', max([supportSizes 0]), ...
    'lookupMean', post.lookupDistance.mean, ...
    'lookupMax', post.lookupDistance.max);

% The nearest-support lookup distance is the honest health check on this
% representation. Large values mean the finite support did not cover where
% the backward traversal actually went, and the posterior is then confidently
% wrong rather than merely uncertain -- the failure mode a plot of the
% trajectory cannot show.
logs = strings(0, 1);
if isfield(caseData, 'map')
    scale = mean(caseData.map.bounds([2 4]) - caseData.map.bounds([1 3]));
else
    scale = diff(caseData.mission.domain);
end
if health.lookupMean > 0.05 * scale
    logs(end+1) = sprintf(['Nearest-support lookup averaged %.2f m on a %.0f m map. ' ...
        'The finite support is not covering the posterior; treat the ' ...
        'estimate as unreliable and raise separatorSupportSize.'], ...
        health.lookupMean, scale);
end
if incremental
    % Reuse is a claim about the answer, not only about the cost, so it goes
    % in the log next to the health warnings rather than into a metrics field
    % nobody reads.
    logs(end+1) = sprintf(['Incremental replay: %d of %d increments completed, ' ...
        'surface cache hit %.0f%% of steps, early stopping fired on %d ' ...
        'increment(s) and reused %.1f variables on average.'], ...
        incrementSummary.numCompleted, incrementSummary.numIncrements, ...
        100 * incrementSummary.cacheHitRate, incrementSummary.numEarlyStops, ...
        incrementSummary.meanVariablesReused);
    if incrementSummary.numStopsIndistinguishable > 0
        logs(end+1) = sprintf(['%d of %d early stops were made on an MMD ' ...
            'estimate that had gone negative: at N_M = %d the U-statistic ' ...
            'cannot separate the two marginals, so the rule stopped because ' ...
            'it could not tell rather than because nothing moved.'], ...
            incrementSummary.numStopsIndistinguishable, ...
            incrementSummary.numEarlyStops, config.mmdSamples);
    end
    if incrementSummary.numFailed > 0
        logs(end+1) = sprintf(['%d increment(s) could not be eliminated: %s. ' ...
            'The posterior reported is the last one that completed.'], ...
            incrementSummary.numFailed, incrementSummary.firstFailure);
    end
end
if health.minEssSupport < 10
    logs(end+1) = sprintf(['Support effective sample size fell to %.1f at a ' ...
        'separator of %d dimensions. Mode A cannot represent this ' ...
        'separator; Modes B and C exist for it.'], ...
        health.minEssSupport, health.maxSeparatorDim);
end

% A step that zeroed most of a row's separator mass belongs where a reader will
% meet it, not only in states(i).Diagnostics.
logs = [logs(:); methods.sparsificationLogs(states)];

% --- Result contract, specification section 8 -----------------------------
result.methodName = methodName;
result.status     = "ok";
result.config     = utils.serializableConfig(config);
result.case       = struct('name', caseData.name, 'variant', caseData.variant, ...
                           'displayName', caseData.displayName, ...
                           'settings', caseData.settings);
result.seed       = seedInfo;

result.increment = incrementRecords;

% SAMPLES and JOINT are the same struct under two names. The three-node
% driver calls it "samples" and every plotting routine reads that field, so
% omitting it here made the general cases crash the moment a panel wanted
% posterior draws. The unified contract of specification section 8 is only
% unified if both engines answer to the same field name.
result.posterior = struct( ...
    'samples',   post.joint, ...
    'joint',     post.joint, ...
    'marginals', post.marginals, ...
    'numSamples', post.numSamples);

% describe and latex return char, so arrayfun needs them wrapped: a char row
% is not a scalar and uniform output rejects it.
result.bayesNet = struct( ...
    'factorization', join(arrayfun(@(c) string(c.describe()), conds), " "), ...
    'latex', join(arrayfun(@(c) string(c.latex()), conds), "\,"));

result.metrics = struct( ...
    'runtimeTotal',      runtimeForward + runtimeBackward, ...
    'runtimeForward',    runtimeForward, ...
    'runtimeBackward',   runtimeBackward, ...
    'factorEvaluations', caseData.counter.snapshot(), ...
    'factorEvalsForward',  forwardEvals, ...
    'factorEvalsBackward', backwardEvals, ...
    'poseRMSE',          sqrt(mean(poseErr.^2)), ...
    'poseMaxError',      max(poseErr), ...
    'poseErrors',        poseErr, ...
    'landmarkRMSE',      localRms(lmErr(obs)), ...
    'rmse',              localRms([poseErr; lmErr(obs)]), ...
    'health',            health, ...
    'incremental',       incrementSummary, ...
    'cardinality',       struct('separatorDims', sepDims, ...
                                'supportSizes', supportSizes, ...
                                'numOuter', config.numSamples));

result.process = methods.buildGeneralProcessTrace(methodName, states, config);
result.states  = states;
result.book    = book;
result.figures = methods.figureRegistryFor(methodName);
result.logs    = logs;

% Importance sampling with a finite support lookup, which the Slices paper does
% not describe. Recorded so that a result from here cannot be read as a
% reproduction merely because the method name matches the paper's.
result.implementation = methods.implementationRecord(methodName, ...
    "general_importance_sampling");
end

% =========================================================================
function s = localIncrementSummary(inc)
%LOCALINCREMENTSUMMARY The replay record, or the batch pass's version of it.
%   Inputs   INC, what runIncrementalGeneral returned, or []
%   Outputs  S, the summary
%   Utility  a batch pass reports NaN for the reuse rate while keeping the
%           real counts: NaN is "not applicable" and 0 is "tried and failed".
ok = [inc.increments.status] == "ok";
recs = inc.increments(ok);

stops = 0; blind = 0; reused = []; resampled = []; mmdAtStop = [];
for i = 1:numel(recs)
    es = recs(i).earlyStop;
    if isempty(es) || ~isstruct(es), continue, end
    resampled(end+1) = es.numResampled; %#ok<AGROW>
    if es.applied
        stops = stops + 1;
        blind = blind + double(es.indistinguishableAtStop);
        reused(end+1) = es.numReused; %#ok<AGROW>
        mmdAtStop(end+1) = es.mmdAtStop; %#ok<AGROW>
    else
        reused(end+1) = 0; %#ok<AGROW>
    end
end

failures = inc.increments(~ok);
firstFailure = "";
if ~isempty(failures)
    firstFailure = sprintf("k = %d: %s", failures(1).k, failures(1).message);
end

s = struct( ...
    'mode',                  "incremental", ...
    'numIncrements',         inc.numIncrements, ...
    'numCompleted',          inc.numCompleted, ...
    'numFailed',             numel(failures), ...
    'firstFailure',          firstFailure, ...
    'cacheHitRate',          inc.cache.hitRate, ...
    'cacheHits',             inc.cache.hits, ...
    'cacheMisses',           inc.cache.misses, ...
    'numEarlyStops',         stops, ...
    'numStopsIndistinguishable', blind, ...
    'meanVariablesReused',   localMean(reused), ...
    'meanVariablesResampled', localMean(resampled), ...
    'minMMDAtStop',          min([mmdAtStop Inf]), ...
    'note',                  "cache hit rate counts elimination steps; reuse counts backward-pass variables");
end

% =========================================================================
function m = localMean(v)
%LOCALMEAN The mean over the finite entries, or NaN when there are none.
%   Inputs   V, the values
%   Outputs  M, the mean or NaN
%   Utility  one non-finite diagnostic must not turn a whole summary into NaN.
if isempty(v), m = 0; else, m = mean(v); end
end

% =========================================================================
function v = localRms(e)
%LOCALRMS Root-mean-square of the per-row residual norms.
%   Inputs   E, an n-by-d residual matrix
%   Outputs  V, the scalar RMSE
%   Utility  one definition of pose error, used everywhere in this driver.
%
%   A case with no landmarks must report NaN rather than the NaN-with-a-
%   warning that mean([]) produces, and must not be mistaken for zero error.
e = e(~isnan(e));
if isempty(e)
    v = NaN;
else
    v = sqrt(mean(e.^2));
end
end

% =========================================================================
function config = localWithProgress(config, p)
%LOCALWITHPROGRESS A copy of the config carrying one phase's sub-reporter.
%   Inputs   CONFIG the base, P the sub-reporter
%   Outputs  CONFIG, the copy
%   Utility  each phase reports its own 0..1 into its share of the run's bar.
config.progress = p;
end
