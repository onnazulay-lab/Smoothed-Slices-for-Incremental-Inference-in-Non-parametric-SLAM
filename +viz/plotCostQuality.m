function info = plotCostQuality(ax, frontier, opts)
%PLOTCOSTQUALITY Posterior error against measured factor evaluations.
%
%   Inputs
%     AX            the axes to draw into
%     FRONTIER      a research.costQualityFrontier result
%     ShowTies      draw the matched-quality connectors        default true
%     LogX          logarithmic evaluation axis               default true
%     LogY          logarithmic error axis                    default true
%     LabelBudgets  annotate each marker with its N           default true
%
%   Outputs
%     INFO          which methods were drawn, how many ties were connected,
%                   and how many baseline targets went unmatched
%
%   Utility
%     Draw the figure the research-tool instruction sheet names as the most
%     important one it asks for: quality error on the vertical axis, factor
%     evaluations on the horizontal, one curve per method, one marker per
%     sample budget.
%
%   HOW TO READ IT. Down is better and left is cheaper, so the useful
%   direction is down-and-left and the question is whether one curve sits
%   below-left of another. A curve that is merely LOWER is not a result: it
%   may have bought that quality with more evaluations, which is what the
%   horizontal axis exists to reveal. Wall time is deliberately not on either
%   axis -- it confounds the algorithm with the machine, and Smoothed Slices
%   is precisely the method a wall-time plot would flatter, because it turns
%   a sample tree into a matrix product that MATLAB happens to run fast.
%
%   THE MATCHED-QUALITY TIES ARE DRAWN. For each baseline budget whose error
%   the challenger reaches, a horizontal connector runs from the baseline
%   point to the cheapest challenger point at or below it. Each connector is
%   one entry of the comparison table, and its direction IS the answer:
%   pointing left, the challenger reached that quality for fewer evaluations.
%   A baseline point with no connector is a target the challenger never met
%   at any budget, which the legend names rather than leaves blank.
%
%   See also research.costQualityFrontier, research.complexityExponent.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    frontier (1,1) struct
    opts.ShowTies (1,1) logical = true
    opts.LogX (1,1) logical = true
    opts.LogY (1,1) logical = true
    opts.LabelBudgets (1,1) logical = true
end

cla(ax, 'reset');
hold(ax, 'on');

info = struct('drawn', strings(1,0), 'ties', 0, 'unmatched', 0);

if isempty(frontier.curves)
    text(ax, 0.5, 0.5, 'no method has a cost axis', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    return
end

for i = 1:numel(frontier.curves)
    c = frontier.curves(i);
    col = viz.methodColors(c.method);
    good = isfinite(c.evaluations) & isfinite(c.error);
    if ~any(good), continue, end

    plot(ax, c.evaluations(good), c.error(good), '-o', 'Color', col, ...
        'LineWidth', 1.6, 'MarkerSize', 6, 'MarkerFaceColor', col, ...
        'DisplayName', char(c.method));
    info.drawn(end+1) = c.method;

    if opts.LabelBudgets
        b = c.budgets(good);
        e = c.evaluations(good);
        q = c.error(good);
        for k = 1:numel(b)
            if ~isfinite(b(k)), continue, end
            text(ax, e(k), q(k), sprintf('  %d', b(k)), ...
                'FontSize', 7, 'Color', col * 0.7, ...
                'VerticalAlignment', 'bottom', 'Interpreter', 'latex');
        end
    end
end

% --- the matched-quality ties --------------------------------------------
if opts.ShowTies && ~isempty(frontier.comparison)
    shown = false;
    for k = 1:numel(frontier.comparison)
        cmp = frontier.comparison(k);
        if ~cmp.reached
            info.unmatched = info.unmatched + 1;
            continue
        end
        h = plot(ax, [cmp.baselineEvaluations cmp.challengerEvaluations], ...
            [cmp.targetError cmp.targetError], ':', ...
            'Color', [0.35 0.35 0.35], 'LineWidth', 1.1);
        info.ties = info.ties + 1;
        if ~shown
            h.DisplayName = 'matched quality';
            shown = true;
        else
            h.Annotation.LegendInformation.IconDisplayStyle = 'off';
        end
    end
end

if opts.LogX, set(ax, 'XScale', 'log'); end
if opts.LogY, set(ax, 'YScale', 'log'); end
grid(ax, 'on');
hold(ax, 'off');

utils.setLatexXY(ax, "factor evaluations", ...
    sprintf("$%s$ (lower is better)", localMetricLabel(frontier.metric)));

% The verdict belongs in the title. A reader who takes one thing from this
% figure should take the answer, not the axes.
utils.setLatexTitle(ax, sprintf("%s vs %s: \\textbf{%s}", ...
    localEscape(frontier.challenger), localEscape(frontier.baseline), ...
    localEscape(frontier.verdict)));

legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'Box', 'off', ...
    'FontSize', 8);
utils.applyLatexToAxes(ax);
end

% =========================================================================
function s = localMetricLabel(metric)
%LOCALMETRICLABEL The axis label for whichever quality column was chosen.
%   Inputs   METRIC, the column name
%   Outputs  S, its LaTeX label
%   Utility  the metric is picked at run time, so the label has to be too.
switch string(metric)
    case "mmd",             s = "\mathrm{MMD}";
    case "relL1Error",      s = "\mathrm{rel}\,L_1";
    case "meanMarginalL1",  s = "\overline{L_1}\ \mathrm{marginal}";
    case "maxModeWeightL1", s = "\max L_1\ \mathrm{mode\ weight}";
    case "rmse",            s = "\mathrm{RMSE}";
    otherwise,              s = localEscape(metric);
end
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
