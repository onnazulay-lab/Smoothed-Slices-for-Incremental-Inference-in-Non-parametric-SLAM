function result = failedResult(methodName, caseData, config, err)
%FAILEDRESULT The unified contract, for a method that could not run this case.
%
%   Inputs
%     METHODNAME  which method failed
%     CASEDATA    the case it failed on
%     CONFIG      the config it was given
%     ERR         the MException it raised
%
%   Outputs
%     RESULT      status "failed", empty posterior fields, NaN metrics, and a
%                 FAILURE block carrying the identifier, the message and the
%                 first frames of the stack
%
%   Utility
%     Let a method fail on a case without taking the comparison down with it,
%     so that the failure is exported as evidence rather than lost as an error.
%
%   A FAILURE IS A FINDING. A method that refuses this case has told us
%   something about the case and about the method, and the brief's section 12
%   asks for exactly that: "all intended increments complete OR explicit
%   failure is exported". A failure that unwinds the run cannot be exported at
%   all, and it takes with it every method that had already finished -- so the
%   run that produced the most information is the one that keeps the least.
%
%   THIS IS NOT A LICENCE TO SWALLOW BUGS. It records a failure raised by a
%   method while running a case. An error raised because the caller asked for
%   something that does not exist is a bug in the caller, and methods.
%   runComparison validates those before the loop so they still throw.
%
%   The metrics are NaN rather than zero for the reason methods.cancelledResult
%   gives: a zero in a runtime column reads as "instant" rather than "never".
%
%   See also methods.cancelledResult, utils.runDiagnosticsSnapshot.

arguments
    methodName (1,1) string
    caseData (1,1) struct
    config (1,1) struct
    err (1,1) MException
end

result = struct();
result.methodName = methodName;
result.status     = "failed";
result.config     = utils.serializableConfig(config);
result.case       = struct('name', caseData.name, 'variant', caseData.variant, ...
                           'displayName', caseData.displayName, ...
                           'settings', caseData.settings);
result.seed       = struct('seed', config.seed);

% The block utils.runDiagnosticsSnapshot already knows how to read. Before
% this function existed it could only ever be filled by a cancellation.
frames = string.empty(1, 0);
for i = 1:min(numel(err.stack), 5)
    frames(end+1) = string(err.stack(i).name) + ":" + err.stack(i).line; %#ok<AGROW>
end
result.failure = struct('identifier', string(err.identifier), ...
                        'message', string(err.message), ...
                        'stack', frames);

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
result.logs    = "failed: " + string(err.identifier) + ": " + string(err.message);
end
