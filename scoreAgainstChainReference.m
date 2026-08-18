function result = scoreAgainstChainReference(result, ref, caseData)
%SCOREAGAINSTCHAINREFERENCE Score a chain case against its exact marginals.
%
%   Inputs
%     RESULT    a method result
%     REF       the exact chain reference
%     CASEDATA  the case
%
%   Outputs
%     RESULT, with these metrics added:
%       modeWeights      D-by-K recovered mass per door per pose
%       modeWeightL1     total variation to the exact weights, per pose
%       maxModeWeightL1  the worst pose
%       collapsedModes   a mode the exact posterior gives real mass and this
%                        method gives almost none
%       marginalL1       total variation between the recovered marginal and
%                        the exact one, per pose
%
%   Utility
%     Make mode collapse measurable rather than merely suspected, on the one
%     case whose exact marginals are computable.
%
%   RMSE is reported too, and is reported with its usual warning attached:
%   on a four-mode posterior the mean is a place the robot has never been, so
%   a method can improve its RMSE by collapsing modes.

arguments
    result (1,1) struct
    ref (1,1) struct
    caseData (1,1) struct
end

if result.status ~= "ok"
    return
end

names = caseData.mission.poseNames;
K = numel(names);
grid_ = ref.grid;

W = metrics.modeWeightsPerPose(result, caseData);
L1 = sum(abs(W - ref.modeWeights), 1);

% Marginal shape, not just the mode bookkeeping. A method can get the mode
% weights right and still place each mode in the wrong spot.
margL1 = nan(1, K);
for k = 1:K
    key = matlab.lang.makeValidName(names(k));
    if ~isfield(result.posterior.marginals, key), continue, end
    S = result.posterior.marginals.(key);

    % A histogram on the reference's own grid: crude, but it introduces no
    % bandwidth choice, and a kernel estimate here would be scoring the
    % smoother rather than the method.
    edges = [grid_(1) - (grid_(2)-grid_(1))/2, ...
             (grid_(1:end-1) + grid_(2:end))/2, ...
             grid_(end) + (grid_(2)-grid_(1))/2];
    h = histcounts(S(:,1), edges, 'Normalization', 'pdf');
    margL1(k) = 0.5 * trapz(grid_, abs(h - ref.marginals(:,k).'));
end

% MAP-to-truth distance, which is the statistic that means something on a
% multimodal posterior where the mean does not.
mapErr = nan(1, K);
postMean = nan(1, K);
for k = 1:K
    key = matlab.lang.makeValidName(names(k));
    if ~isfield(result.posterior.marginals, key), continue, end
    S = result.posterior.marginals.(key);
    postMean(k) = mean(S(:,1));
    [~, near] = min(abs(S(:,1) - caseData.doors), [], 2);
    w = accumarray(near, 1, [numel(caseData.doors) 1]);
    [~, best] = max(w);
    mapErr(k) = abs(caseData.doors(best) - caseData.mission.truePoses(k));
end

result.metrics.modeWeights     = W;
result.metrics.modeWeightL1    = L1;
result.metrics.maxModeWeightL1 = max(L1);
result.metrics.collapsedModes  = nnz(ref.modeWeights > 0.15 & W < 0.02);
result.metrics.marginalL1      = margL1;
result.metrics.meanMarginalL1  = mean(margL1, 'omitnan');
result.metrics.relL1Error      = mean(margL1, 'omitnan');
result.metrics.mapDoorError    = mapErr;
% A scalar summary of the same thing, because a sweep cell can only carry
% scalars and the per-pose vector is invisible to it. Worst pose rather than
% mean: on a chain that resolves, the late poses are easy and averaging over
% them hides a method that never recovered from the ambiguous start.
result.metrics.maxMapDoorError = max(mapErr);
result.metrics.rmse            = sqrt(mean((postMean - caseData.mission.truePoses.').^2, 'omitnan'));
result.metrics.rmseWarning     = "the mean of a multimodal posterior is not a location the robot occupied";
end
