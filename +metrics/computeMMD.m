function [d, info] = computeMMD(X, Y, opts)
%COMPUTEMMD Maximum mean discrepancy between two sample sets.
%
%   Inputs
%     X, Y       the two sample sets, points down the rows
%     Kernel     "rbf" (default)
%     Bandwidth  "median" for the median heuristic (default), or a positive
%                scalar sigma
%     Estimator  "unbiased" (default, U-statistic) or "biased" (V-statistic)
%     Squared    true to return MMD^2 instead of MMD              default false
%
%   Outputs
%     D     the discrepancy
%     INFO  the kernel, bandwidth and estimator actually used
%
%   Utility
%     Compare two sample sets by a distance that sees the whole distribution
%     rather than only its mean.
%
%   Both papers use MMD, and the Slices paper fixes N_M = 100 and a threshold
%   of 1e-4 for Plaza2, but NEITHER specifies the kernel, the bandwidth, or
%   whether the estimator is biased or unbiased. All three are exposed here and
%   echoed in INFO, because an MMD number without them is not reportable.
%
%   The unbiased estimator can return a small negative value when the two
%   samples come from the same distribution; that is expected, and the square
%   root is taken of the clamped value with the raw one kept in INFO.

arguments
    X (:,:) double
    Y (:,:) double
    opts.Kernel (1,1) string {mustBeMember(opts.Kernel, "rbf")} = "rbf"
    opts.Bandwidth = "median"
    opts.Estimator (1,1) string {mustBeMember(opts.Estimator, ["biased","unbiased"])} = "unbiased"
    opts.Squared (1,1) logical = false
end

if isrow(X), X = X(:); end
if isrow(Y), Y = Y(:); end

n = size(X, 1);
m = size(Y, 1);
if n < 2 || m < 2
    error('metrics:computeMMD:tooFewSamples', ...
        'MMD needs at least two samples per set (got %d and %d).', n, m);
end

% --- Bandwidth ------------------------------------------------------------
if isnumeric(opts.Bandwidth)
    sigma = double(opts.Bandwidth);
    bandwidthRule = "fixed";
else
    Z = [X; Y];
    dz = pdist(Z);
    med = median(dz(dz > 0));
    if isempty(med) || ~isfinite(med) || med <= 0
        med = 1;
    end
    sigma = med / sqrt(2);      % median heuristic
    bandwidthRule = "median heuristic";
end

k = @(A, B) exp(-pdist2(A, B, 'squaredeuclidean') / (2 * sigma^2));

Kxx = k(X, X);
Kyy = k(Y, Y);
Kxy = k(X, Y);

switch opts.Estimator
    case "unbiased"
        sxx = (sum(Kxx(:)) - trace(Kxx)) / (n * (n - 1));
        syy = (sum(Kyy(:)) - trace(Kyy)) / (m * (m - 1));
        sxy = sum(Kxy(:)) / (n * m);
    case "biased"
        sxx = sum(Kxx(:)) / n^2;
        syy = sum(Kyy(:)) / m^2;
        sxy = sum(Kxy(:)) / (n * m);
end

mmd2raw = sxx + syy - 2 * sxy;
mmd2    = max(mmd2raw, 0);

if opts.Squared
    d = mmd2;
else
    d = sqrt(mmd2);
end

info = struct( ...
    'kernel',        opts.Kernel, ...
    'bandwidth',     sigma, ...
    'bandwidthRule', bandwidthRule, ...
    'estimator',     opts.Estimator, ...
    'mmdSquaredRaw', mmd2raw, ...
    'clamped',       mmd2raw < 0, ...
    'numX',          n, ...
    'numY',          m, ...
    'note',          "kernel and bandwidth are implementation choices; neither paper specifies them");
end
