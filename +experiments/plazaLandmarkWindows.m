function [windows, info] = plazaLandmarkWindows(dataset, ordinal, opts)
%PLAZALANDMARKWINDOWS Windows in which one surveyed node accumulates evidence.
%
%   Inputs
%     DATASET       "Plaza1" or "Plaza2"
%     ORDINAL       which surveyed node, by position in the id list
%     NumPoses      poses per window; travels on info.numPoses   default 8
%     SensorRange   the range gate, matching the case default    default 30
%     MaxLandmarks  landmark cap, matching the case default       default 2
%     NumWindows    how many rungs on the ladder                  default 3
%
%   Outputs
%     WINDOWS   the window start keyframes, fewest observing poses first
%     INFO      the landmark id, observingPoses per window, numPoses -- see
%               the counting note below -- firstSeenKeyframe, totalReadings
%               and the mapping note
%
%   Utility
%     Find the windows in which one surveyed node is observed by the fewest, a
%     middling and the most poses, so its posterior can be plotted along a
%     ladder of increasing evidence.
%
%   WHY THIS FUNCTION EXISTS INSTEAD OF THE LITERAL STEPS 0, 8 AND 22.
%   The showcase manual asks for landmark L2's marginals at Plaza2 time steps
%   0, 8 and 22. Those indices are the paper's own step numbering, and they do
%   not survive the trip into this repository: keyframes here are cut every
%   6 m of travel, which is not the paper's step definition. Checking the data
%   settles it -- with L2 taken as the second surveyed node by id, id 1:
%
%       manual step   our keyframe   landmark ids ranged within 30 m
%             0             1                [0 6]
%             8             9                [0 5]
%            22            23                [1]
%
%   L2 is ranged at exactly one of the three, and no other node is ranged at
%   all three either, so no relabelling rescues the literal indices. Plotting
%   keyframes 1, 9 and 23 anyway would produce a figure that looks like the
%   paper's and shows something else: two of its three panels would be the
%   marginal of a landmark that has received no measurement.
%
%   So the manual's INTENT is honoured rather than its indices. It asks for
%   the steps "where it receives important range measurements", and that is a
%   property of the data, which is what this function reads. The result is
%   the same narrative -- a posterior tightening as evidence arrives -- on
%   steps that are true of this dataset.
%
%   WHAT THE LADDER IS AND IS NOT. Each window is solved independently, so
%   this is not a filter accumulating evidence across time; it is three
%   separate posteriors under three different amounts of evidence. The paper's
%   curve is the former. This is the honest version available to an engine
%   that holds ten to thirteen variables depending on the problem, and
%   callers should label it as such.
%
%   NUMPOSES IS THE LADDER'S OWN NUMBER AND HAS TO TRAVEL WITH IT. Every
%   count below is a count of poses inside a K-keyframe window, and each
%   candidate is validated by building the case at that same K. A caller that
%   takes the returned start and builds the case at a DIFFERENT K gets a rung
%   labelled with evidence from a window it did not solve -- and, near the end
%   of the sequence, a start that makePlazaCase rejects outright. This used to
%   read "matching the case default", which described a coincidence rather
%   than a mechanism: both were 4, nothing enforced it, and raising the case
%   default broke the ladder silently. The number is on info.numPoses, and
%   runPlazaProtocol passes it back into the case.
%
%   THE DEFAULT IS 8, AND AGREES WITH THE CASE BECAUSE THAT WAS MEASURED.
%   When the case default moved to 8 the ladder was left at 4, and the plan
%   was to document the divergence rather than close it. Measuring it first
%   showed there was nothing to document: the ladder returns three distinct
%   rungs at every K from 4 to 10, and at 8 it returns a WIDER one. On the
%   default case, Plaza2 L2, the rungs go 1, 5, 8 observing poses instead of
%   1, 3, 4 -- the same three panels, with the top rung holding twice the
%   evidence, which is the thing the ladder exists to show. A divergence with
%   no reason behind it is worse documented than removed.
%
%   The agreement is still only cosmetic. What protects the ladder is the
%   paragraph above -- K travelling on info.numPoses -- not the two numbers
%   happening to match, and moving the case default again would be caught by
%   that mechanism rather than by this sentence.
%
%   See also datasets.makePlazaCase, experiments.runPlazaProtocol.

arguments
    dataset (1,1) string {mustBeMember(dataset, ["Plaza1","Plaza2"])}
    ordinal (1,1) double {mustBeInteger, mustBePositive}
    opts.NumPoses (1,1) double {mustBeInteger, mustBeGreaterThan(opts.NumPoses,1)} = 8
    opts.SensorRange (1,1) double {mustBePositive} = 30
    opts.MaxLandmarks (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual(opts.MaxLandmarks,2)} = 2
    opts.NumWindows (1,1) double {mustBeInteger, mustBePositive} = 3
end

data = datasets.loadPlazaDataset(dataset);

if ordinal > numel(data.landmarkIds)
    error('experiments:plazaLandmarkWindows:noSuchLandmark', ...
        '%s has %d surveyed nodes; L%d was asked for.', ...
        dataset, numel(data.landmarkIds), ordinal);
end
lmId = data.landmarkIds(ordinal);

R = data.ranges;
keep = [R.landmarkId] == lmId & [R.trueRange] <= opts.SensorRange;
poseIds = [R(keep).poseId];
if isempty(poseIds)
    error('experiments:plazaLandmarkWindows:neverObserved', ...
        'Node %d (L%d) is never ranged within %.1f m in %s.', ...
        lmId, ordinal, opts.SensorRange, dataset);
end

% Count the POSES in each window that range this landmark, not the raw
% readings. makePlazaCase thins to MaxReadingsPerPair readings per
% pose-landmark pair, so a K-pose window keeps at most K regardless of how
% many the radio logged. Counting raw readings builds a ladder whose top
% rungs are identical in the graph the methods actually see -- measured at
% K = 4, a raw count of 15 and a raw count of 6 both reduce to 4 observing
% poses.
% Distinct poses is the quantity that reaches the estimator.
K = opts.NumPoses;
lastStart = numel(data.steps) - K + 1;
starts = 1:lastStart;
counts = zeros(1, numel(starts));
obsPoses = unique(poseIds);
for i = 1:numel(starts)
    idx = starts(i) : starts(i) + K - 1;
    counts(i) = nnz(ismember(obsPoses, idx));
end

usable = find(counts > 0);
if isempty(usable)
    error('experiments:plazaLandmarkWindows:noWindow', ...
        'No %d-pose window of %s contains a reading of L%d.', K, dataset, ordinal);
end

% The ladder spans DISTINCT evidence levels, not evenly spaced positions in
% the sorted list. The count can only run from 1 to NumPoses, and most windows
% sit at the top of that range, so spacing by position put two rungs on the
% same count: measured, three rungs came back as 1, 4 and 4 observing poses --
% a ladder whose middle and top are the same graph, plotted as though they
% showed evidence accumulating.
%
% Within a level the earliest keyframe wins, so the choice is deterministic;
% an arbitrary tie-break would make the figure depend on sort order.
levels = unique(counts(usable));
pickLevels = levels(unique(round(linspace(1, numel(levels), opts.NumWindows))));

% A candidate is only a window if the case actually builds there AND keeps the
% landmark: the gate in makePlazaCase can reject one for reasons this function
% does not model, and a start that fails must be replaced rather than returned
% and left to throw inside a figure callback. So each level is tried in
% keyframe order until one holds, and a level with no usable window is dropped
% rather than allowed to demote the rung to a different evidence count.
windows = [];
kept = [];
for lv = pickLevels
    atLevel = sort(usable(counts(usable) == lv));
    for c = atLevel
        if localBuilds(dataset, c, K, opts.MaxLandmarks, lmId)
            windows(end+1) = c; %#ok<AGROW>
            kept(end+1) = lv;   %#ok<AGROW>
            break
        end
    end
end

if isempty(windows)
    error('experiments:plazaLandmarkWindows:noneBuild', ...
        ['Every candidate window for L%d of %s was rejected by ' ...
         'makePlazaCase. The landmark cap or pose count needs changing.'], ...
        ordinal, dataset);
end

info = struct( ...
    'dataset',       dataset, ...
    'ordinal',       ordinal, ...
    'landmarkId',    lmId, ...
    'observingPoses', kept, ...
    'numPoses',      K, ...
    'firstSeenKeyframe', min(poseIds), ...
    'totalReadings', nnz(keep), ...
    'note', "windows chosen from the data; the manual's steps 0/8/22 are " + ...
            "the paper's numbering and do not map onto these keyframes");
end

% =========================================================================
function tf = localBuilds(dataset, w0, K, maxLm, lmId)
%LOCALBUILDS True if the case builds there AND keeps the landmark.
%   Inputs   DATASET, W0 the window start, K the poses per window, MAXLM the
%           landmark cap, LMID the landmark that must survive it
%   Outputs  TF, logical
%   Utility  validate a candidate rung by building the case it labels.
%
%   Keeping the landmark is the second half of the test: the window can build
%   perfectly well and drop L2 at the MaxLandmarks cap, which would leave the
%   figure plotting a variable the case does not contain.
try
    c = datasets.makePlazaCase('Dataset', dataset, 'WindowStart', w0, ...
            'NumPoses', K, 'MaxLandmarks', maxLm);
    tf = ismember(lmId, c.landmarks.ids);
catch
    tf = false;
end
end
