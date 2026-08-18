function result = runInferenceCore(methodName, caseData, config)
%RUNINFERENCECORE Shared driver for the two elimination-based methods.
%
%   Inputs
%     METHODNAME  "Slices" or "Smoothed Slices"
%     CASEDATA    the case
%     CONFIG      the method config; innerEstimator is the one field the two
%                 methods differ in
%
%   Outputs
%     RESULT      the unified result structure of app specification section 8
%
%   Utility
%     Run the forward pass, the backward pass and the diagnostics through ONE
%     driver, so any difference between the two methods' outputs is a
%     difference in the inner estimator rather than in the harness.
%
%   Slices and Smoothed Slices share this driver on purpose. They differ in
%   exactly one field, CONFIG.innerEstimator, which selects Eq. (23) or
%   Eq. (50) for the inner integral. Any other difference between their
%   outputs would be an artifact of the harness rather than of the methods,
%   and routing both through one driver is what rules that out.

arguments
    methodName (1,1) string
    caseData (1,1) struct
    config (1,1) struct
end

% Two engines, one entry point. The three-node engine follows Algorithm S1
% literally and is validated against dense quadrature; the general engine
% handles graphs of any shape by dividing out an explicit proposal density.
% The case says which one it needs, because the choice is a property of the
% graph rather than of the method, and both methods must take the same route
% for the comparison between them to mean anything.
if isfield(caseData, 'engine') && caseData.engine == "general"
    result = methods.runGeneralCore(methodName, caseData, config);
    return
end

seedInfo = utils.setRandomSeed(config.seed);
caseData.counter.reset();

timings = struct();

% The split is measured, not guessed: on the shipped two-pose budgets the
% forward pass is where roughly two thirds of the time goes, because it is
% the pass that carries the nested inner estimate.
p = utils.progressOf(config);

% --- Forward pass ---------------------------------------------------------
tf = tic;
[bayesNet, states, finalFactor] = methods.slices.forwardElimination( ...
    caseData, localWithProgress(config, p.sub(0, 0.65)));
timings.forward = toc(tf);
forwardEvals = caseData.counter.snapshot();

% --- Backward pass --------------------------------------------------------
tb = tic;
back = methods.slices.backwardMarginals(bayesNet, caseData, ...
    localWithProgress(config, p.sub(0.65, 0.97)));
timings.backward = toc(tb);
backwardEvals = caseData.counter.snapshot() - forwardEvals;

% --- The generated factor over the target variable ------------------------
target    = caseData.targetVariable;
targetKey = matlab.lang.makeValidName(target);

est = struct();
est.variable = target;
% The support is stored canonically as |S|-by-d so that a planar separator
% is a point list. A scalar target is handed back as a 1-by-|S| ROW, next to
% the equally shaped f_new, because that is the orientation the quadrature
% reference, trapz and every 1-D plot expect.
est.support  = finalFactor.SeparatorSupport;
if finalFactor.SeparatorDim == 1
    est.support = reshape(est.support, 1, []);
end
est.fnew     = exp(finalFactor.LogScale) * mean(finalFactor.SliceMatrix, 1);
est.slices   = finalFactor.SliceMatrix;
est.mass     = trapz(est.support, est.fnew);
est.pdf      = est.fnew / est.mass;

% --- Process trace for the Process Explorer -------------------------------
process = methods.buildProcessTrace(methodName, states, back, config);

% --- Result contract, specification section 8 -----------------------------
result = struct();
result.methodName = methodName;
result.status     = "ok";
result.config     = utils.serializableConfig(config);
result.case       = struct('name', caseData.name, 'variant', caseData.variant, ...
                           'displayName', caseData.displayName, ...
                           'settings', caseData.settings);
result.seed       = seedInfo;

result.increment = struct('k', 1, 'numNewFactors', numel(states), ...
                          'states', {arrayfun(@(s) s.describe(), states, 'UniformOutput', false)});

result.posterior = struct( ...
    'samples',   back.samples, ...
    'marginals', back.marginals, ...
    'grids',     back.grids, ...
    'estimator', est);

result.bayesNet = struct( ...
    'factorization', bayesNet.factorizationString(), ...
    'latex',         bayesNet.latex());

result.metrics = struct( ...
    'runtimeTotal',      timings.forward + timings.backward, ...
    'runtimeForward',    timings.forward, ...
    'runtimeBackward',   timings.backward, ...
    'factorEvaluations', caseData.counter.snapshot(), ...
    'factorEvalsForward',  forwardEvals, ...
    'factorEvalsBackward', backwardEvals, ...
    'cardinality',       methods.collectCardinality(states, config), ...
    'incremental',       localNoReplay());

result.process = process;
result.states  = states;
result.figures = methods.figureRegistryFor(methodName);
% A sparsification that discarded most of a row's mass belongs where a reader
% will meet it, not only in states(i).Diagnostics.
result.logs    = methods.sparsificationLogs(states);

% This is the paper-literal route, and it is the ONLY one that may say so.
% The same method name reaching runGeneralCore gets a different record.
result.implementation = methods.implementationRecord(methodName, "three_node_demo");
end

% =========================================================================
function s = localNoReplay()
%LOCALNOREPLAY The replay record for a batch run.
%   Inputs   none
%   Outputs  S, the record with the incremental fields as "not applicable"
%   Utility  a batch pass must not report a reuse rate of zero: NaN is "not
%           applicable" and 0 is "tried and failed", and only one is true.
%
%   The general engine and NF-iSAM both record an incremental block, and a
%   diagnostics panel reading three results wants the same field on all three.
%   Omitting it here made the Diagnostics tab show a bare dash, which cannot
%   be told apart from a number that failed to arrive. "none" with a reason
%   can.
%
%   The distinction is real and not bookkeeping: mode "batch" means a graph
%   that COULD have been replayed was eliminated in one pass, while "none"
%   means the case has one increment and there is no such choice to make.
s = struct( ...
    'mode',          "none", ...
    'numIncrements', 1, ...
    'numCompleted',  1, ...
    'cacheHitRate',  NaN, ...
    'note',          "the three-node engine has no replay mode: the case is " + ...
                     "one graph with all of its data present, so there is no " + ...
                     "previous increment for anything to be reused from");
end

% =========================================================================
function config = localWithProgress(config, p)
%LOCALWITHPROGRESS A copy of the config carrying one phase's sub-reporter.
%   Inputs   CONFIG the base, P the sub-reporter
%   Outputs  CONFIG, the copy
%   Utility  each phase reports its own 0..1 into its share of the whole run's
%           bar.
config.progress = p;
end
