function [clear_, tHit] = segmentClear(p, q, blocks)
%SEGMENTCLEAR Line-of-sight test between point pairs and axis-aligned blocks.
%
%   Inputs
%     P, Q    N-by-2 segment endpoints; either may be a single 1-by-2 row,
%             which is then used for all N
%     BLOCKS  B-by-4 rows of [x y width height], (x,y) the lower-left corner
%
%   Outputs
%     CLEAR   N-by-1 logical, true where the segment misses every block
%     THIT    parametric distance along the segment of the first block hit,
%             Inf where the path is clear
%
%   Utility
%     Decide which measurements a wall blocks, and where it blocks them.
%
%   THIT is what turns a blocked measurement into a drawable ray stub rather
%   than a ray that simply vanishes.
%
%   The slab method: intersect the segment's parameter interval [0,1] with the
%   per-axis interval on which it lies inside the block. A segment misses the
%   block when those intervals fail to overlap. Vectorized over N so the whole
%   sensor sweep of one pose costs one call per block.
%
%   Endpoints ON a block boundary count as clear. A landmark placed on a wall
%   would otherwise occlude itself, and beacons sit on walls in every layout
%   here.

arguments
    p (:,2) double
    q (:,2) double
    blocks (:,4) double
end

n = max(size(p, 1), size(q, 1));
if size(p, 1) == 1, p = repmat(p, n, 1); end
if size(q, 1) == 1, q = repmat(q, n, 1); end
if size(p, 1) ~= n || size(q, 1) ~= n
    error('datasets:segmentClear:sizeMismatch', ...
        'P has %d row(s) and Q has %d; they must match or be single rows.', ...
        size(p, 1), size(q, 1));
end

clear_ = true(n, 1);
tHit   = inf(n, 1);
if isempty(blocks), return, end

d = q - p;
% A shrink of the parameter interval keeps a segment that merely grazes a
% wall, or that starts or ends exactly on one, from reading as blocked.
eps0 = 1e-9;

for b = 1:size(blocks, 1)
    lo = blocks(b, 1:2);
    hi = lo + blocks(b, 3:4);

    tmin = zeros(n, 1) + eps0;
    tmax = ones(n, 1)  - eps0;
    miss = false(n, 1);

    for ax = 1:2
        da = d(:, ax);
        pa = p(:, ax);

        parallel_ = abs(da) < 1e-12;
        % Parallel to this slab: either always inside it or never.
        miss = miss | (parallel_ & (pa < lo(ax) | pa > hi(ax)));

        da(parallel_) = 1;   % neutral value; those rows are settled above
        t1 = (lo(ax) - pa) ./ da;
        t2 = (hi(ax) - pa) ./ da;
        tlo = min(t1, t2);
        thi = max(t1, t2);

        tmin(~parallel_) = max(tmin(~parallel_), tlo(~parallel_));
        tmax(~parallel_) = min(tmax(~parallel_), thi(~parallel_));
    end

    hit = ~miss & (tmin <= tmax);
    clear_ = clear_ & ~hit;
    tHit(hit) = min(tHit(hit), tmin(hit));
end
end
