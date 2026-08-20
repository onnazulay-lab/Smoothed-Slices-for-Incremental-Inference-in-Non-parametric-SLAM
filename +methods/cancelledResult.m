function result = cancelledResult(methodName, caseData, config, note)
%CANCELLEDRESULT The unified contract, for a method that never got to run.
%
%   Inputs
%     METHODNAME  which method did not run
%     CASEDATA    the case it would have run on
%     CONFIG      the config it would have used
%     NOTE        why                                 default a stock line
%
%   Outputs
%     RESULT      status "cancelled", empty posterior fields, NaN metrics
%
%   Utility
%     Give the panels, the metrics table and the export a row of the right
%     shape for a method Stop reached before it started.
%
%   Stop keeps the work that finished. A run of three methods interrupted
%   during the second has one complete answer in hand, and throwing it away to
%   report a clean failure would make the button cost more than it saves. The
%   methods that never started therefore need a result of the right shape, for
%   the same reason the NF-iSAM stub needed one through iterations 1 and 2:
%   the metrics table, the panels and the export bundle all iterate over every
%   method and each of them already knows how to skip a row whose status is
%   not "ok".
%
%   What this deliberately does NOT do is report zeros. Every metric is NaN,
%   because a cancelled method has no runtime, no error and no cardinality --
%   and a zero in the runtime column of a comparison table reads as "instant".

arguments
    methodName (1,1) string
    caseData (1,1) struct
    config (1,1) struct
    note (1,1) string = "cancelled before this method started"
end

result = struct();
result.methodName = methodName;
result.status     = "cancelled";
result.config     = utils.serializableConfig(config);
result.case       = struct('name', caseData.name, 'variant', caseData.variant, ...
                           'displayName', caseData.displayName, ...
                           'settings', caseData.settings);
result.seed       = struct('seed', config.seed);

result.increment  = struct([]);
result.posterior  = struct('samples', struct(), 'marginals', struct(), ...
                           'grids', struct(), 'estimator', struct());
result.bayesNet   = struct('factorization', "", 'latex', "");

result.metrics = struct( ...
    'runtimeTotal',      NaN, ...
    'runtimeForward',    NaN, ...
    'runtimeBackward',   NaN, ...
    'factorEvaluations', NaN, ...
    'cardinality',       struct('outer', NaN, 'inner', NaN, 'separator', NaN));

result.process = struct('method', methodName, 'stages', struct([]), ...
                        'numStages', 0, 'stageTypes', string.empty(1,0));
result.states  = core.EliminationState.empty(1, 0);
result.figures = methods.figureRegistryFor(methodName);
result.logs    = note;
end
