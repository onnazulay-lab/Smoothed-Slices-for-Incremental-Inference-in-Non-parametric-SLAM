function [w, info] = computeModeWeights(samples, opts)
%COMPUTEMODEWEIGHTS Mass assigned to each posterior mode.
%
%   Inputs
%     SAMPLES    posterior samples, points down the rows
%     Modes      known mode locations; samples are then assigned to the
%                nearest one and no clustering is performed
%     NumModes   number of k-means clusters when Modes is not supplied
%     Grid, Pdf  when supplied, modes are found as local maxima of the
%                marginal density, which is more stable than clustering in 1-D
%
%   Outputs
%     W     the fraction of mass at each mode
%     INFO  how the modes were located, and where they were
%
%   Utility
%     Expose MODE COLLAPSE, which RMSE cannot see and which is the specific
%     failure the Smoothed Slices spec warns about when a surface is
%     over-smoothed.

arguments
    samples (:,1) double
    opts.Modes (1,:) double = []
    opts.NumModes (1,1) double {mustBeInteger, mustBePositive} = 2
    opts.Grid (1,:) double = []
    opts.Pdf (1,:) double = []
end

if ~isempty(opts.Grid) && ~isempty(opts.Pdf)
    % --- Density-based: locate local maxima, split at the valleys ---------
    [~, pk] = findpeaks(opts.Pdf, 'MinPeakProminence', 0.02 * max(opts.Pdf));
    if isempty(pk)
        [~, pk] = max(opts.Pdf);
    end
    modes = opts.Grid(pk);
    method = "density peaks";
elseif ~isempty(opts.Modes)
    modes = opts.Modes;
    method = "known modes";
else
    modes = [];
    method = "kmeans";
end

if isempty(modes)
    k = opts.NumModes;
    idx = kmeans(samples, k, 'Replicates', 5);
    modes = arrayfun(@(c) mean(samples(idx == c)), 1:k);
else
    [~, idx] = min(abs(samples - modes(:).'), [], 2);
end

k = numel(modes);
w = zeros(1, k);
for c = 1:k
    w(c) = mean(idx == c);
end

[modes, ord] = sort(modes);
w = w(ord);

info = struct( ...
    'modes',      modes, ...
    'weights',    w, ...
    'method',     method, ...
    'numSamples', numel(samples), ...
    'collapsed',  any(w < 0.02), ...
    'note',       "a mode weight near zero where the reference has mass is mode collapse");
end
