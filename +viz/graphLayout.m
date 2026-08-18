function L = graphLayout(caseData)
%GRAPHLAYOUT Node positions for the factor graph and the Bayes net.
%
%   Inputs
%     CASEDATA  the case whose variables are to be placed
%
%   Outputs
%     L         names, pos (n-by-2), kind, xlim, ylim, isLandmark
%
%   Utility
%     Return one layout shared by viz.plotFactorGraphStep and
%     viz.plotBayesNetStep, so a variable sits in the same place in both
%     panels. Reading one against the other is the point of showing them side
%     by side, and it only works if the geometry agrees.
%
%   Four layouts, in order of preference:
%
%     "map"    The case has a mission with 2-D poses. Every variable is drawn
%              where it actually is. This is the layout worth having: the
%              factor graph of the grid world then IS the map, and a reader
%              can see that a beacon is tied to the two poses that saw it
%              rather than having to trust a caption.
%
%     "demo"   The three-node two-pose range benchmark. Kept as the fixed
%              triangle both papers draw, so the iteration-1 figure does
%              not move.
%
%     "chain"  Every variable is a 1-D pose. Laid out by index along a line,
%              not by value: on Four Doors the true positions are collinear
%              and equally spaced, so a value layout would be the index
%              layout with worse labels.
%
%     "ring"   Anything else, and any variable the layouts above did not
%              place. Never fails, never claims to be meaningful.
%
arguments
    caseData (1,1) struct
end

names = caseData.graph.VariableNames;
n = numel(names);
pos = nan(n, 2);
kind = "ring";

isLandmark = startsWith(names, "l");

% --- map ------------------------------------------------------------------
hasMission = isfield(caseData, 'mission') && isstruct(caseData.mission) ...
    && isfield(caseData.mission, 'truePoses');
if hasMission && size(caseData.mission.truePoses, 2) == 2
    kind = "map";
    pos = localPlace(pos, names, caseData.mission.poseNames, ...
                     caseData.mission.truePoses);
    if isfield(caseData, 'landmarks') && isfield(caseData.landmarks, 'names')
        pos = localPlace(pos, names, caseData.landmarks.names, ...
                         caseData.landmarks.truePositions);
    end
end

% --- three-node demonstrator ---------------------------------------------
if kind == "ring" && n == 3 && all(ismember(["x1" "l1" "x2"], names))
    kind = "demo";
    pos = localPlace(pos, names, ["x1" "l1" "x2"], [0 0; 1 1; 2 0]);
end

% --- pose chain -----------------------------------------------------------
if kind == "ring" && all(~isLandmark)
    dims = arrayfun(@(v) v.Dim, caseData.graph.Variables);
    if all(dims == 1)
        kind = "chain";
        pos = [(1:n).', zeros(n, 1)];
    end
end

% --- ring, and anything still unplaced ------------------------------------
missing = find(any(isnan(pos), 2));
if ~isempty(missing)
    if all(any(isnan(pos), 2))
        r = max(1, n / (2*pi));
        th = 2*pi * (0:n-1).' / n;
        pos = r * [cos(th) sin(th)];
    else
        % A few orphans around the outside of what is already placed, so a
        % variable no layout understood is still visible and still labelled.
        c = mean(pos(~any(isnan(pos), 2), :), 1);
        rad = 1.15 * max(vecnorm(pos(~any(isnan(pos), 2), :) - c, 2, 2));
        if ~isfinite(rad) || rad <= 0, rad = 1; end
        th = 2*pi * (0:numel(missing)-1).' / max(1, numel(missing));
        pos(missing, :) = c + rad * [cos(th) sin(th)];
    end
end

% --- separate coincident nodes -------------------------------------------
% A beacon lining a corridor sits a metre from the pose that saw it, and at
% panel scale the two labels land on top of each other. Pushing overlapping
% pairs apart costs a little geometric fidelity and buys a graph that can be
% read; the map panel is where the true positions are authoritative.
span0 = max(max(pos, [], 1) - min(pos, [], 1));
if ~isfinite(span0) || span0 <= 0, span0 = 1; end
pos = localSpread(pos, 0.11 * span0);

% --- limits ---------------------------------------------------------------
span = max(max(pos, [], 1) - min(pos, [], 1));
if ~isfinite(span) || span <= 0, span = 1; end
pad = 0.12 * span;

L = struct();
L.names      = names;
L.pos        = pos;
L.kind       = kind;
L.isLandmark = isLandmark;
L.span       = span;
L.xlim       = [min(pos(:,1)) - pad, max(pos(:,1)) + pad];
L.ylim       = [min(pos(:,2)) - pad, max(pos(:,2)) + pad];

% A chain is one-dimensional and would otherwise be drawn in a zero-height
% axes; give it room for the factor stubs that hang below it.
if L.ylim(2) - L.ylim(1) < 0.35 * span
    mid = mean(L.ylim);
    L.ylim = mid + 0.3 * span * [-1 1];
end
end

% =========================================================================
function pos = localSpread(pos, minDist)
%LOCALSPREAD Push coincident nodes apart, just enough to be distinguishable.
%   Inputs   POS the positions, MINDIST how close is too close
%   Outputs  POS, with overlaps relieved
%   Utility  two variables at the same true position would draw as one node.
%
%   A few passes of pairwise repulsion, bounded so the layout stays close to
%   where it started. Not a force-directed layout: the positions are already
%   meaningful and the job is only to stop two of them from coinciding.
n = size(pos, 1);
if n < 2 || minDist <= 0, return, end

for iter = 1:60
    moved = false;
    for i = 1:n-1
        for j = i+1:n
            d = pos(j,:) - pos(i,:);
            r = norm(d);
            if r >= minDist, continue, end
            if r < 1e-9
                % Exactly coincident: no direction to push along, so pick
                % one deterministically rather than leaving them stacked.
                d = [cos(2*pi*i/n) sin(2*pi*i/n)];
                r = 1;
            end
            shift = 0.5 * (minDist - r) * d / r;
            pos(i,:) = pos(i,:) - shift;
            pos(j,:) = pos(j,:) + shift;
            moved = true;
        end
    end
    if ~moved, break, end
end
end

% =========================================================================
function pos = localPlace(pos, names, subsetNames, subsetPos)
%LOCALPLACE Write a subset's positions into the full position array by name.
%   Inputs   POS the array, NAMES its row order, SUBSETNAMES and SUBSETPOS the
%           values to place
%   Outputs  POS, with those rows filled in
%   Utility  match by name rather than by index, so a layout that places only
%           some variables leaves the rest to the ring fallback.
for i = 1:numel(subsetNames)
    j = find(names == subsetNames(i), 1);
    if ~isempty(j) && i <= size(subsetPos, 1)
        pos(j, :) = subsetPos(i, 1:2);
    end
end
end
