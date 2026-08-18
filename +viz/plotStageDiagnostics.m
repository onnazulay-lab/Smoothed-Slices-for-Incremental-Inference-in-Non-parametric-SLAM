function plotStageDiagnostics(ax, results, stage)
%PLOTSTAGEDIAGNOSTICS Per-stage engine health, with the current stage marked.
%
%   Inputs
%     AX       the axes to draw into
%     RESULTS  the method results
%     STAGE    the elimination step to mark                      default 1
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Draw the effective sample size of the separator support at every
%     elimination step, one line per method, with a marker on the stage the
%     slider is sitting at.
%
%   ESS is the right quantity for this panel because it is the one that goes
%   wrong first. On the grid world the pose error stays plausible while the
%   support ESS falls from fourteen to two, and by the time the trajectory
%   looks wrong the cause is several eliminations back. A reader dragging the
%   stage slider can watch it happen.
%
%   A reference line at ten marks where the support has effectively collapsed
%   to a handful of points. It is a rule of thumb and is labelled as one.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results struct
    stage (1,1) double = 1
end

cla(ax, 'reset');
hold(ax, 'on');

drew = false;
for i = 1:numel(results)
    r = results(i);
    if ~isfield(r, 'process') || isempty(r.process), continue, end

    stages = r.process.stages;
    ess = nan(1, numel(stages));
    for s = 1:numel(stages)
        d = stages(s).diagnostics;
        if isfield(d, 'essSupport'), ess(s) = d.essSupport; end
    end
    if all(isnan(ess)), continue, end

    colour = viz.methodColors(string(r.methodName));
    plot(ax, 1:numel(ess), ess, '-o', 'Color', colour, 'LineWidth', 1.4, ...
        'MarkerSize', 4, 'MarkerFaceColor', colour, ...
        'DisplayName', string(r.methodName));
    drew = true;

    s = min(max(1, round(stage)), numel(ess));
    if ~isnan(ess(s))
        plot(ax, s, ess(s), 'o', 'MarkerSize', 11, 'LineWidth', 1.6, ...
            'Color', colour, 'MarkerFaceColor', 'none', ...
            'HandleVisibility', 'off');
    end
end

if ~drew
    text(ax, 0.5, 0.5, 'no per-stage diagnostics for this case', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    hold(ax, 'off');
    return
end

yl = ylim(ax);
plot(ax, xlim(ax), [10 10], ':', 'Color', [0.7 0.2 0.2], 'LineWidth', 1.0, ...
    'DisplayName', 'collapse threshold (rule of thumb)');
ylim(ax, [0 max(yl(2), 12)]);

legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'FontSize', 8);
hold(ax, 'off');

utils.applyLatexToAxes(ax);
utils.setLatexTitle(ax, 'Support effective sample size per elimination step');
utils.setLatexXY(ax, 'elimination step $j$', 'ESS of $\hat f_{\mathrm{new}}$ support');
end
