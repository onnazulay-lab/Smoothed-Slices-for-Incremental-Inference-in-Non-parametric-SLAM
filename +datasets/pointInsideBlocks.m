function inside = pointInsideBlocks(P, blocks)
%POINTINSIDEBLOCKS True for points that lie strictly inside an obstacle.
%
%   Inputs
%     P       N-by-2 points, one per row
%     BLOCKS  B-by-4 rows of [x y width height], (x,y) the lower-left corner
%
%   Outputs
%     INSIDE  N-by-1 logical, true where the point is inside some block
%
%   Utility
%     Decide whether a pose occupies blocked space.
%
%   BOUNDARIES COUNT AS FREE HERE, AND AS BLOCKED IN segmentClear, and the
%   difference is deliberate rather than an oversight in one of them. The two
%   answer different questions. segmentClear asks whether a wall interrupts a
%   line of sight, and a ray that runs along a face IS occluded by it, so the
%   face belongs to the block. This asks whether a pose stands in occupied
%   space, and a pose exactly on the face is against the wall rather than
%   inside it.
%
%   The combined feasibility test stays conservative in spite of that. A path
%   whose pose lands exactly on a face is still scored infeasible, because the
%   legs into and out of that pose touch the face and segmentClear blocks
%   them. What differs is only which counter records it, and exact boundary
%   coincidence has measure zero for a continuous posterior in any case.

arguments
    P (:,2) double
    blocks (:,4) double
end

inside = false(size(P,1), 1);
eps0 = 1e-9;
for b = 1:size(blocks,1)
    lo = blocks(b,1:2);
    hi = lo + blocks(b,3:4);
    inside = inside | ...
        (P(:,1) > lo(1)+eps0 & P(:,1) < hi(1)-eps0 & ...
         P(:,2) > lo(2)+eps0 & P(:,2) < hi(2)-eps0);
end
end
