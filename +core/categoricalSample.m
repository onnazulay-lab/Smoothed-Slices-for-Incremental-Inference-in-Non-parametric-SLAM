function idx = categoricalSample(w, n)
%CATEGORICALSAMPLE N draws from unnormalized weights, zeros allowed.
%
%   Inputs
%     W    column of unnormalized nonnegative weights; zeros are fine
%     N    number of draws
%
%   Outputs
%     IDX  N-by-1 indices into W, drawn with probability proportional to W
%
%   Utility
%     Resample a support without failing on the zero weights that resampling
%     itself produces.
%
%   Written by hand rather than with DISCRETIZE because a weight vector with
%   zeros in it produces repeated entries in the cumulative sum, and
%   DISCRETIZE rejects bin edges that are not STRICTLY increasing. Zeros are
%   not an edge case here: after a resampling step most of a slice column can
%   legitimately be zero, and a sampler that throws on that would fail
%   precisely when the diagnostics are trying to report the collapse.
%
%   A weight vector that is entirely zero or non-finite falls back to
%   uniform. That keeps the pass running; the caller's effective sample size
%   is the honest place for the problem to surface.

arguments
    w (:,1) double
    n (1,1) double {mustBeInteger, mustBeNonnegative}
end

m = numel(w);
if m == 0
    error('core:categoricalSample:empty', 'No categories to draw from.');
end

w(~isfinite(w) | w < 0) = 0;
s = sum(w);
if ~(s > 0)
    idx = randi(m, n, 1);
    return
end

c = cumsum(w) / s;
c(end) = 1;

u = rand(n, 1);
idx = zeros(n, 1);

% Chunked so a large draw against a large support does not allocate an
% n-by-m comparison in one go.
chunk = max(1, floor(4e6 / m));
for a = 1:chunk:n
    b = min(a + chunk - 1, n);
    idx(a:b) = sum(u(a:b) > c.', 2) + 1;
end
idx = min(idx, m);
end
