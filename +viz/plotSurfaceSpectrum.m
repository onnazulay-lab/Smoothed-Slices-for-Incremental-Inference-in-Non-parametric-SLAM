function info = plotSurfaceSpectrum(ax, study, opts)
%PLOTSURFACESPECTRUM Singular-value decay of the surfaces R_r. Sheet E2.
%
%   Inputs
%     AX            the axes to draw into
%     STUDY         a research.surfaceComplexityStudy result
%     ShowTerminal  overlay the terminal surface R_1            default true
%     MaxCurves     stop after this many, legend says so        default 12
%     FloorDecades  clip the vertical axis this far below 1     default 12
%
%   Outputs
%     INFO          how many curves were drawn and how many were clipped
%
%   Utility
%     Draw one normalized spectrum per swept configuration, on a log vertical
%     axis, with the 99 %-energy rank marked on each curve.
%
%   HOW TO READ IT. Every curve starts at 1 because the spectrum is
%   normalized by its own sigma_1 -- surfaces are products of unnormalized
%   factors and their absolute scales are not comparable, so the shape is the
%   only honest thing to overlay. A curve that plunges is a compact surface: a
%   few directions carry it, and the sheet's "fast singular-value decay" is
%   satisfied. A curve that sags gently towards the right edge is the failure
%   signal, "full rank / no sparsity", and it looks like a straight line on
%   this axis rather than like anything dramatic.
%
%   THE MARKERS ARE WHERE THE ENERGY RUNS OUT, not where the curve looks
%   flat. Reading a rank off the elbow of a log plot is a habit worth
%   breaking: the elbow moves with the vertical limits, and two spectra with
%   the same elbow can need very different numbers of directions to hold the
%   same fraction of the surface. Each marker sits at the 99 %-energy rank,
%   which is a quantity rather than an impression.
%
%   ONE CURVE IS NOT DRAWN LIKE THE OTHERS. The terminal surface R_1 is shown
%   dashed and grey when ShowTerminal is on, because rank(R_0) is bounded by
%   rank(R_1): a fast-decaying R_0 that lies on top of a fast-decaying R_1 has
%   demonstrated nothing about the recursion. The gap between the solid curves
%   and the dashed one is what the smoothing did.
%
%   See also research.surfaceComplexityStudy, methods.smoothed.surfaceComplexity,
%   viz.plotSurfaceRankVsAxis.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    study (1,1) struct
    opts.ShowTerminal (1,1) logical = true
    opts.MaxCurves (1,1) double {mustBePositive} = 12
    opts.FloorDecades (1,1) double {mustBePositive} = 12
end

cla(ax, 'reset');
hold(ax, 'on');
info = struct('curves', 0, 'clipped', 0);

T = study.rows;
if height(T) == 0
    text(ax, 0.5, 0.5, 'no configurations in this study', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    return
end

n = min(height(T), opts.MaxCurves);
info.clipped = height(T) - n;

% Colour by which axis the configuration varies, so that the plot answers
% "does noise or overlap move the spectrum" before any legend is read.
axes_ = unique(T.axis, 'stable');
cmap  = lines(max(3, numel(axes_)));

floorVal = 10 ^ (-opts.FloorDecades);

for i = 1:n
    s = T.singularValues{i};
    s = s(:).';
    s = max(s, floorVal);          % a log axis cannot show an exact zero
    k = find(axes_ == T.axis(i), 1);
    col = cmap(k, :);

    plot(ax, 1:numel(s), s, '-', 'Color', col, 'LineWidth', 1.4, ...
        'DisplayName', char(T.label(i)));

    kE = T.energyRank99(i);
    if isfinite(kE) && kE >= 1 && kE <= numel(s)
        h = plot(ax, kE, s(kE), 'o', 'Color', col, 'MarkerFaceColor', col, ...
            'MarkerSize', 6);
        h.Annotation.LegendInformation.IconDisplayStyle = 'off';
    end
    info.curves = info.curves + 1;
end

if opts.ShowTerminal && ismember('terminalEnergyRank99', T.Properties.VariableNames)
    % The bound, not another measurement: drawn once, from the first
    % configuration, because overlaying every R_1 would triple the ink for a
    % curve whose only job is to be compared against.
    kT = T.terminalEnergyRank99(1);
    if isfinite(kT)
        h = xline(ax, kT, '--', 'Color', [0.45 0.45 0.45], 'LineWidth', 1.2, ...
            'DisplayName', sprintf('$R_1$ needs %d', kT));
        h.Interpreter = 'latex';
        h.LabelVerticalAlignment = 'bottom';
    end
end

set(ax, 'YScale', 'log');
ylim(ax, [floorVal 1.5]);
grid(ax, 'on');
hold(ax, 'off');

utils.setLatexXY(ax, "singular value index $k$", ...
    "$\sigma_k / \sigma_1$");
utils.setLatexTitle(ax, sprintf( ...
    "Surface spectra, %s: \\textbf{%s}", ...
    localEscape(study.baseline.variant), localEscape(study.verdict)));

legend(ax, 'Interpreter', 'latex', 'Location', 'northeast', 'Box', 'off', ...
    'FontSize', 7);
utils.applyLatexToAxes(ax);
end

% =========================================================================
function s = localEscape(t)
%LOCALESCAPE Text made safe for a LaTeX interpreter.
%   Inputs   T, a string that may hold %, _ or $
%   Outputs  S, the same text with those escaped
%   Utility  a verdict sentence goes straight into a legend or an annotation,
%           and an unescaped underscore would silently subscript it.
s = strrep(char(string(t)), '_', '\_');
end
