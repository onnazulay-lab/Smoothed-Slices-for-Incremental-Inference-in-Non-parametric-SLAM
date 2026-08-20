function span = plazaLoopSpan(dataset, opts)
%PLAZALOOPSPAN Measure the loop structure of a Plaza sequence from its geometry.
%
%   Inputs
%     dataset          "Plaza1" | "Plaza2", or a struct already returned by
%                      datasets.loadPlazaDataset
%     KeyframeSpacing  metres of travel per keyframe, used only when DATASET is
%                      a name and the sequence has to be loaded    default 6
%     ReturnRadius     metres; a keyframe closer than this to the reference is
%                      treated as revisiting it                    default 8
%     MinGap           keyframes; revisits nearer than this in time are ignored
%                      so that a keyframe's own neighbours do not count
%                                                                  default 10
%     Reference        keyframe whose place the laps are counted around
%                                                                  default 1
%
%   Outputs
%     span             struct with fields
%       isCircuit        true if the path passes the reference twice or more,
%                        which is what distinguishes a circuit from a there-
%                        and-back route
%       passes           keyframes at which the path revisits the reference
%       firstReturn      first entry of passes, or NaN
%       lapKeyframes     median gap between successive passes -- the pose count
%                        that spans ONE lap, and the number a loop-closing case
%                        should be built around
%       lapMetres        median arc length of one lap
%       lapSpread        [min max] of the per-lap keyframe gaps, so that a
%                        median quoted from irregular laps is not read as exact
%       medianRevisit    typical number of keyframes between a place and its
%                        own next revisit. Meaningful only when the path is
%                        NOT a circuit -- see the caveat below
%       shortestRevisit  fewest keyframes over the same set, and the more
%                        fragile of the two: on a densely self-crossing path it
%                        reports MinGap + 1 whatever MinGap is
%       revisits         table of every place-revisit pair found
%
%   Utility
%     Answers "how many poses is one loop" as a measurement rather than an
%     assumption. The window chooser in datasets.makePlazaCase optimises for
%     how well constrained a window is and has no notion of revisiting a place,
%     so a case meant to contain a loop closure needs this number first.
%
%   TWO RULES, AND THE SECOND ONE MATTERS. A revisit is a keyframe within
%   ReturnRadius of the reference AND a local minimum of the distance to it.
%   Without the local-minimum rule every keyframe in a radius-sized
%   neighbourhood counts separately, one pass is reported as a run of
%   consecutive revisits, and the shortest "loop" found is always MinGap + 1 --
%   the floor, not the geometry.
%
%   USE THE LAP ON A CIRCUIT AND THE REVISITS ON ANYTHING ELSE. The two
%   families of number here are not alternatives, and each sequence supports
%   exactly one of them.
%
%   On a densely self-crossing path EVERY revisit statistic is contaminated by
%   MinGap, because the track is near itself almost everywhere and there is
%   always some start whose next revisit falls just past the gap. Measured on
%   Plaza1 at MinGap 6, 8, 10, 12, 14, 18 and 22, shortestRevisit returns
%   exactly MinGap + 1 every time; the median is no better, moving 14 -> 17 ->
%   22 as the gap goes 8 -> 12 -> 18. Those are readings of the parameter. What
%   IS stable there is the lap: 16.5-17 keyframes and 101-104 m anywhere in a
%   3..15 m return radius.
%
%   On Plaza2 it is the other way round. There is no circuit, so there is no
%   lap to read; and because the lawnmower crosses itself in few places both
%   revisit figures hold at 34 across that same MinGap sweep and mean what they
%   say. So: lapKeyframes for Plaza1, medianRevisit for Plaza2, and neither
%   number is safe on the other sequence.
%
%   Plaza1 and Plaza2 answer differently and the difference is the point.
%   Plaza1 drives the same circuit repeatedly, so lapKeyframes is a real lap.
%   Plaza2 is a lawnmower pattern that never returns to where it began, so it
%   has no laps and only shortestRevisit is meaningful. Reporting both, instead
%   of one "loop length", keeps the sequences comparable without inventing a
%   circuit for Plaza2.
%
%   See also datasets.loadPlazaDataset, datasets.makePlazaCase.

arguments
    dataset
    opts.KeyframeSpacing (1,1) double {mustBePositive} = 6
    % Eight metres, chosen from the sensitivity rather than picked. On Plaza1
    % the lap reads 16.5-17 keyframes and 101-104 m anywhere in 3..15 m, so the
    % measurement is not radius-driven; but at 5 m the lap whose closest
    % approach is 5.29 m is missed and the per-lap spread jumps from [16 18] to
    % [16 33], and at 2 m only one pass survives and there is no lap at all.
    % Eight sits in the flat middle of that range.
    opts.ReturnRadius (1,1) double {mustBePositive} = 8
    opts.MinGap (1,1) double {mustBeInteger, mustBePositive} = 10
    opts.Reference (1,1) double {mustBeInteger, mustBePositive} = 1
end

if isstruct(dataset)
    data = dataset;
else
    data = datasets.loadPlazaDataset(string(dataset), ...
        'KeyframeSpacing', opts.KeyframeSpacing);
end

xy  = data.gt.poses;
arc = data.keyframes.arcLength(:);
n   = size(xy, 1);

span = struct('isCircuit', false, 'passes', [], 'firstReturn', NaN, ...
              'lapKeyframes', NaN, 'lapMetres', NaN, 'lapSpread', [NaN NaN], ...
              'medianRevisit', NaN, 'shortestRevisit', NaN, 'revisits', table());

% --- Laps around the reference -------------------------------------------
passes = localRevisits(xy, opts.Reference, opts.ReturnRadius, opts.MinGap);
span.passes = passes(:).';
if ~isempty(passes)
    span.firstReturn = passes(1);
end
if numel(passes) >= 2
    gaps = diff(passes(:));
    span.isCircuit    = true;
    span.lapKeyframes = median(gaps);
    span.lapMetres    = median(diff(arc(passes(:))));
    span.lapSpread    = [min(gaps) max(gaps)];
end

% --- Shortest revisit anywhere in the run --------------------------------
fromKf = []; toKf = []; lenKf = []; metres = [];
for i = 1:n
    j = localRevisits(xy, i, opts.ReturnRadius, opts.MinGap);
    if isempty(j), continue, end
    fromKf(end+1,1) = i;                        %#ok<AGROW>
    toKf(end+1,1)   = j(1);                     %#ok<AGROW>
    lenKf(end+1,1)  = j(1) - i + 1;             %#ok<AGROW>
    metres(end+1,1) = arc(j(1)) - arc(i);       %#ok<AGROW>
end

if ~isempty(fromKf)
    span.revisits = table(fromKf, toKf, lenKf, metres, 'VariableNames', ...
        {'fromKeyframe','toKeyframe','numKeyframes','pathLength'});
    span.medianRevisit   = median(lenKf);
    span.shortestRevisit = min(lenKf);
end
end

% =========================================================================
function j = localRevisits(xy, ref, radius, minGap)
%LOCALREVISITS Keyframes after REF that revisit its place.
%   Inputs   xy      keyframe positions, n-by-2
%            ref     reference keyframe index
%            radius  metres within which a keyframe counts as the same place
%            minGap  keyframes; closer partners in time are ignored
%   Outputs  j       column of revisit keyframe indices, ascending
%   Utility  A revisit is BOTH within radius and a local minimum of distance
%            to ref, so that one pass through the neighbourhood yields one
%            revisit rather than one per keyframe inside it.
d = hypot(xy(:,1) - xy(ref,1), xy(:,2) - xy(ref,2));
d(1 : min(numel(d), ref + minGap - 1)) = inf;

near = d < radius;
% Strict on the left, non-strict on the right, so a flat pair is one minimum.
isMin = near & [false; d(2:end) < d(1:end-1)] & [d(1:end-1) <= d(2:end); false];
j = find(isMin);
end
