function info = plotPlazaMarginal(ax, results, varName, coord, opts)
%PLOTPLAZAMARGINAL One coordinate of one planar variable, every method.
%
%   Inputs
%     AX          the axes to draw into
%     RESULTS     the method results
%     VARNAME     which planar variable, e.g. "l1"
%     COORD       "x" or "y"
%     TrueValue   truth for this coordinate, drawn as a line     default NaN
%     NumBins     histogram bins                                 default 40
%     Smooth      overlay a kernel density estimate            default false
%     ShowMean    mark each method's posterior mean            default false
%
%   Outputs
%     INFO        which methods were drawn, how many samples each had, and
%                 which were missing this variable
%
%   Utility
%     Draw the posterior marginal of one coordinate of one planar variable for
%     each method on shared axes, which is the comparison the showcase manual
%     asks for on Plaza2's landmark L2.
%
%   WHY A HISTOGRAM AND NOT A KDE, despite the manual saying "marginal KDE".
%   viz.plotMarginalKDE draws the mixture-of-slices marginal the backward pass
%   produces, and refuses to smooth because both papers avoid reconstructing
%   an intermediate density. That marginal is available for scalar variables.
%   A Plaza variable is planar, so what comes back is a cloud of joint samples
%   and one coordinate of it has no closed-form marginal to draw. The choice
%   is then between a histogram and a KDE, and a histogram is the estimator
%   that adds least: a KDE's bandwidth is a free parameter that would smooth
%   a two-mode posterior into one mode at exactly the settings that flatter
%   the result. On this case that is not hypothetical -- the landmark
%   posteriors here really are bimodal -- so the bins are drawn as they fall.
%   Pass Smooth=true to overlay a kernel estimate for readability; the
%   histogram stays underneath it.
%
%   THE TRUE VALUE IS DRAWN AS A LINE, NOT SCORED. Where truth sits relative
%   to the modes is the whole content of the figure; a number in a legend
%   would hide it. If truth falls between two modes and the mean sits on top
%   of truth, that is a coincidence of a symmetric posterior, not accuracy.
%
%   See also viz.plotPlazaContext, experiments.plazaLandmarkWindows.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results (1,:) struct
    varName (1,1) string
    coord (1,1) string {mustBeMember(coord, ["x","y"])}
    opts.TrueValue (1,1) double = NaN
    opts.NumBins (1,1) double {mustBeInteger, mustBePositive} = 40
    opts.Smooth (1,1) logical = false
    opts.ShowMean (1,1) logical = false
end

cla(ax, 'reset');
hold(ax, 'on');

col = double(coord == "y") + 1;
key = matlab.lang.makeValidName(varName);

info = struct('drawn', strings(1,0), 'numSamples', [], 'missing', strings(1,0));

% One set of bin edges for every method, computed over the pooled samples.
% Per-method edges would make two histograms of different posteriors look
% comparable when they are not even on the same grid.
pooled = [];
for i = 1:numel(results)
    v = localColumn(results(i), key, col);
    pooled = [pooled; v]; %#ok<AGROW>
end

if isempty(pooled)
    text(ax, 0.5, 0.5, sprintf('no samples for %s', varName), ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    return
end

lo = min(pooled);
hi = max(pooled);
if isfinite(opts.TrueValue)
    % Truth must be inside the frame even when every method missed it --
    % especially then, since that is the case the figure exists to show.
    lo = min(lo, opts.TrueValue);
    hi = max(hi, opts.TrueValue);
end
if hi - lo < eps
    hi = lo + 1;
end
pad = 0.05 * (hi - lo);
edges = linspace(lo - pad, hi + pad, opts.NumBins + 1);

for i = 1:numel(results)
    r = results(i);
    v = localColumn(r, key, col);
    if isempty(v)
        info.missing(end+1) = string(r.methodName);
        continue
    end
    c = viz.methodColors(r.methodName);

    histogram(ax, v, edges, 'Normalization', 'pdf', ...
        'FaceColor', c, 'FaceAlpha', 0.25, 'EdgeColor', c, ...
        'EdgeAlpha', 0.55, 'DisplayName', char(r.methodName));

    if opts.Smooth && numel(v) > 4
        [f, xi] = localKde(v, edges);
        h = plot(ax, xi, f, '-', 'Color', c, 'LineWidth', 1.6);
        h.Annotation.LegendInformation.IconDisplayStyle = 'off';
    end

    if opts.ShowMean
        xline(ax, mean(v), ':', 'Color', c, 'LineWidth', 1.2, ...
            'HandleVisibility', 'off');
    end

    info.drawn(end+1) = string(r.methodName);
    info.numSamples(end+1) = numel(v);
end

if isfinite(opts.TrueValue)
    xline(ax, opts.TrueValue, '-', 'Color', [0.1 0.1 0.1], ...
        'LineWidth', 1.8, 'DisplayName', 'surveyed truth');
end

hold(ax, 'off');
grid(ax, 'on');
disp1 = regexprep(varName, '^([a-zA-Z]+)(\d+)$', '$1_{$2}');
utils.setLatexTitle(ax, sprintf("Marginal of $%s$ in $%s$", disp1, coord));
utils.setLatexXY(ax, sprintf("$%s_%s$ [m]", disp1, coord), "density");
legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'Box', 'off', ...
    'FontSize', 8);
utils.applyLatexToAxes(ax);
end

% =========================================================================
function v = localColumn(result, key, col)
%LOCALCOLUMN One coordinate of one variable's posterior samples.
%   Inputs   RESULT a method result, KEY the variable's valid name, COL the
%           coordinate index
%   Outputs  V, the samples as a column, or [] when the method has none
%   Utility  read one coordinate out of a planar sample cloud.
v = [];
if ~isfield(result, 'status') || result.status ~= "ok", return, end
if ~isfield(result, 'posterior') || ~isfield(result.posterior, 'marginals')
    return
end
M = result.posterior.marginals;
if ~isfield(M, key), return, end
S = M.(key);
if isempty(S) || size(S, 2) < col, return, end
v = S(:, col);
v = v(isfinite(v));
end

% =========================================================================
function [f, xi] = localKde(v, edges)
%LOCALKDE A kernel estimate on the histogram's own grid.
%   Inputs   V the samples, EDGES the histogram's bin edges
%   Outputs  F the density, XI where it was evaluated
%   Utility  the optional overlay, on the same grid as the bins so the two
%           can be read against each other rather than merely stacked.
%
%   Silverman's rule, stated rather than tuned. It is a readability overlay
%   and must not be the thing the reader measures, which is why the bins stay
%   visible underneath it.
xi = linspace(edges(1), edges(end), 256);
s = std(v);
if s < eps, s = 1; end
h = 1.06 * s * numel(v)^(-1/5);
f = mean(exp(-0.5 * ((xi - v) / h).^2), 1) / (h * sqrt(2*pi));
end
