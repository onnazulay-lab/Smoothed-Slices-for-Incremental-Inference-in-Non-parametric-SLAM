function [W, info] = modeWeightsPerPose(result, caseData)
%MODEWEIGHTSPERPOSE Mode weights for every pose of a multimodal case.
%
%   Inputs
%     RESULT    a method result
%     CASEDATA  the case, carrying the known modes and the exact reference
%
%   Outputs
%     W     D-by-K, the posterior mass at each known mode, one column per
%           increment
%     INFO  carries l1PerPose, the total variation distance to the reference at
%           each pose, when the reference is available
%
%   Utility
%     Provide the metric the multimodal case exists for. The modes are known by
%     construction in the Four Doors case, so no clustering is involved and the
%     answer is directly comparable against the exact reference.
%
%   This is the metric the multimodal case exists for. A method can put the
%   posterior mean within centimetres of the truth while assigning all the
%   mass to one door out of two that the exact posterior splits evenly, and
%   RMSE will call that a success. Reported next to the exact weights, it is
%   visible as the mode collapse it is.
%
%   INFO.l1PerPose is the total variation distance to the reference at each
%   pose when the reference is available on CASEDATA.

arguments
    result (1,1) struct
    caseData (1,1) struct
end

if ~isfield(caseData, 'doors')
    error('metrics:modeWeightsPerPose:noKnownModes', ...
        ['This case has no known modes. Use metrics.computeModeWeights with ' ...
         'a density grid or a cluster count instead.']);
end

doors = caseData.doors(:).';
names = caseData.mission.poseNames;
K = numel(names);
W = zeros(numel(doors), K);

for k = 1:K
    key = matlab.lang.makeValidName(names(k));
    if ~isfield(result.posterior.marginals, key)
        W(:,k) = NaN;
        continue
    end
    S = result.posterior.marginals.(key);
    [~, near] = min(abs(S(:,1) - doors), [], 2);
    W(:,k) = accumarray(near, 1, [numel(doors) 1]) / numel(near);
end

info = struct('doors', doors, 'poseNames', names, 'method', "known modes");

if isfield(caseData, 'reference') && isfield(caseData.reference, 'modeWeights')
    R = caseData.reference.modeWeights;
    info.l1PerPose = sum(abs(W - R), 1);
    info.maxL1 = max(info.l1PerPose);
    % Collapse is specifically a mode the reference gives real mass that the
    % method gives almost none. A merely inaccurate weight is not collapse,
    % and conflating the two would make the diagnostic useless.
    info.collapsed = any(R > 0.15 & W < 0.02, 'all');
end
end
