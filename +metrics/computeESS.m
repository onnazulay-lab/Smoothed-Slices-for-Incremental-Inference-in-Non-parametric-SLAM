function [ess, info] = computeESS(weights)
%COMPUTEESS Effective sample size of an importance/slice weight set.
%
%   Inputs
%     WEIGHTS  a weight vector, or a matrix whose columns are independent
%              weight sets
%
%   Outputs
%     ESS   Kish's effective sample size, (sum w)^2 / sum w^2, per column
%     INFO  carries ratio, which is ESS over the number of weights and is the
%           scale-free quantity to threshold on
%
%   Utility
%     Say how many samples a weight set is really worth, so a collapsed
%     representation is visible as a number.
%
%   Specification section 16 asks for this on the Slices and Smoothed Slices
%   paths and asks that a low value be highlighted in red; INFO.ratio is the
%   quantity to threshold on, being scale free.
%
%   WEIGHTS may be a matrix, in which case each column is treated as an
%   independent weight set and the per-column ESS is returned.

arguments
    weights (:,:) double
end

w = max(weights, 0);
n = size(w, 1);

s1 = sum(w, 1);
s2 = sum(w.^2, 1);

ess = zeros(1, size(w, 2));
ok  = s2 > 0;
ess(ok) = (s1(ok).^2) ./ s2(ok);

ratio = ess / n;

info = struct( ...
    'ess',        ess, ...
    'ratio',      ratio, ...
    'n',          n, ...
    'meanRatio',  mean(ratio), ...
    'minRatio',   min(ratio), ...
    'degenerate', any(ratio < 0.1), ...
    'note',       "ESS below 10 percent of the sample count indicates weight degeneracy");

if isscalar(ess)
    ess = ess(1);
end
end
