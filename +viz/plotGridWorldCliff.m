function info = plotGridWorldCliff(ax, sweep, opts)
%PLOTGRIDWORLDCLIFF Error against problem size, with the office's ceiling drawn.
%
%   Inputs
%     AX        the axes to draw into
%     SWEEP     a grid-world sweep result
%     Metric    row field for the y-axis            default "poseRMSE"
%     Ceiling   variables the engine is good to     default 13
%     Jitter    x-offset per method, in variables   default 0.12
%
%   Outputs
%     INFO.numPoints   markers drawn
%     INFO.methods     methods drawn
%     INFO.layouts     layouts present
%     INFO.crossing    median metric below and at-or-above the ceiling
%
%   Utility
%     Draw every completed cell as one marker: the number of VARIABLES in the
%     graph on the x-axis, pose RMSE on the y, colour by method, marker shape
%     by layout, with a dashed line where the OFFICE layout turns.
%
%   THE LINE IS A MEASUREMENT ON ONE MAP, NOT AN ENGINE PROPERTY, and the
%   figure is the thing that proves it: the warehouse markers sit above the
%   line's height while still to the LEFT of it, failing at ten variables
%   where the office is fine at thirteen. It is drawn anyway, because a
%   reference the data visibly crosses is more use than no reference -- but
%   it is labelled as the office's, and anyone reading it as a threshold for
%   the engine is reading it as its earlier caption invited them to.
%   datasets.makeGridWorldCase carries the numbers and the three explanations
%   that were tested and eliminated.
%
%   WHY EVERY CELL AND NOT A MEDIAN. viz.plotSweepCurve aggregates, and it is
%   right to: on the budget axis each point is six different problems and the
%   median is the honest summary. Here the SCATTER IS THE RESULT. The claim
%   this figure exists to test is that the failure at fourteen variables is a
%   property of the case rather than of one seed, and a median hides exactly
%   the quantity that settles it -- whether the seeds agree. Four seeds at
%   thirteen variables all under 1.4 m and four at fourteen all above 11 m is
%   a cliff; the same medians with the points interleaved would not be, and
%   would plot identically.
%
%   MARKER SHAPE CARRIES THE LAYOUT, and that is what turned out to matter.
%   It was added to compare separator widths at equal variable counts -- the
%   warehouse reaches fourteen variables on separators of four dimensions
%   where the office needs six -- and it answered a bigger question than it
%   was asked: the warehouse markers are high at TEN variables, so the two
%   layouts do not share an edge to fall off. Pool the layouts into one
%   symbol and that reads as scatter around a single cliff. It is not
%   scatter; it is two different maps with two different answers.
%
%   THE JITTER IS COSMETIC AND IS DECLARED. Three methods run the same cell
%   and land on the same integer x, so without it the last method drawn hides
%   the other two. It moves markers by a tenth of a variable; the x-axis
%   ticks are the true integers.
%
%   See also methods.gridWorldSweepPlan, viz.plotSweepCurve.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    sweep (1,1) struct
    opts.Metric (1,1) string = "poseRMSE"
    opts.Ceiling (1,1) double = 13
    opts.Jitter (1,1) double = 0.12
end

cla(ax, 'reset');
hold(ax, 'on');

info = struct('numPoints', 0, 'methods', strings(1,0), ...
              'layouts', strings(1,0), ...
              'crossing', struct('below', NaN, 'atOrAbove', NaN, 'ratio', NaN));

rows = sweep.rows;
if isempty(rows) || ~isfield(rows, 'numVariables') || ~isfield(rows, opts.Metric)
    localNote(ax, 'No grid-world rows in this sweep.');
    return
end

ok = string({rows.status}) == "ok";
rows = rows(ok);
x = [rows.numVariables];
y = [rows.(opts.Metric)];
good = isfinite(x) & isfinite(y);
rows = rows(good); x = x(good); y = y(good);

if isempty(rows)
    localNote(ax, 'No completed rows with a variable count.');
    return
end

who = string({rows.method});
if isfield(rows, 'layout')
    lay = string({rows.layout});
else
    lay = repmat("", 1, numel(rows));
end

info.layouts = unique(lay, 'stable');
shapes = ["o", "s", "^", "d", "v"];

% --- the markers ----------------------------------------------------------
methodsSeen = unique(who, 'stable');
for mi = 1:numel(methodsSeen)
    m = methodsSeen(mi);
    col = viz.methodColors(m);
    dx = (mi - (numel(methodsSeen) + 1) / 2) * opts.Jitter;

    drewAny = false;
    for li = 1:numel(info.layouts)
        sel = who == m & lay == info.layouts(li);
        if ~any(sel), continue, end
        shape = shapes(min(li, numel(shapes)));

        h = plot(ax, x(sel) + dx, y(sel), shape, 'Color', col, ...
            'MarkerFaceColor', col, 'MarkerSize', 6, 'LineStyle', 'none');
        if drewAny
            h.Annotation.LegendInformation.IconDisplayStyle = 'off';
        else
            h.DisplayName = char(m);
            drewAny = true;
        end
        info.numPoints = info.numPoints + nnz(sel);
    end
    if drewAny, info.methods(end+1) = m; end
end

% --- the shape key --------------------------------------------------------
% Drawn as NaN handles: they claim a legend entry and no data point. A
% caption naming the shapes would go stale the first time a layout is added.
if numel(info.layouts) > 1
    for li = 1:numel(info.layouts)
        plot(ax, NaN, NaN, shapes(min(li, numel(shapes))), ...
            'Color', [0.35 0.35 0.35], 'MarkerFaceColor', 'none', ...
            'LineStyle', 'none', 'DisplayName', char(info.layouts(li)));
    end
end

% --- the ceiling ----------------------------------------------------------
% This pools the layouts, and pooling costs something now that the layouts are
% known to disagree about where they turn: warehouse cells to the LEFT of the
% line are failures, so they land in "below" and pull the good side up. The
% ratio is therefore a floor on the step, not an estimate of it. Left pooled
% because the alternative -- a per-layout summary in a one-line title -- says
% less than the scatter it sits above already says.
below = y(x < opts.Ceiling + 1);       % 13 variables and under
above = y(x >= opts.Ceiling + 1);      % 14 and over
info.crossing.below = median(below, 'omitnan');
info.crossing.atOrAbove = median(above, 'omitnan');
if isfinite(info.crossing.below) && info.crossing.below > 0
    info.crossing.ratio = info.crossing.atOrAbove / info.crossing.below;
end

yl = ylim(ax);
h = plot(ax, (opts.Ceiling + 0.5) * [1 1], yl, '--', ...
    'Color', [0.55 0.15 0.15], 'LineWidth', 1.2, ...
    'DisplayName', sprintf('office turns here (%d)', opts.Ceiling));
ylim(ax, yl);
uistack(h, 'bottom');

if all(y > 0), set(ax, 'YScale', 'log'); end
xticks(ax, unique(round(x)));
grid(ax, 'on');
hold(ax, 'off');

legend(ax, 'Interpreter', 'latex', 'Location', 'northwest', 'FontSize', 7, ...
    'Box', 'off');
utils.setLatexXY(ax, "variables in the graph", localLabel(opts.Metric));

if isfinite(info.crossing.ratio)
    utils.setLatexTitle(ax, sprintf( ...
        "median %s, all layouts: %.2f m left of the line, %.2f m at or right of it ($\\times$%.0f)", ...
        localPlain(opts.Metric), info.crossing.below, ...
        info.crossing.atOrAbove, info.crossing.ratio));
end
utils.applyLatexToAxes(ax);
end

% =========================================================================
function localNote(ax, msg)
%LOCALNOTE Write a short note into otherwise empty axes.
%   Inputs   AX the axes, MSG the text
%   Outputs  none; draws into AX
%   Utility  say why a panel is empty rather than leaving blank axes, which
%           read as a rendering failure.
text(ax, 0.5, 0.5, msg, 'Units', 'normalized', ...
    'HorizontalAlignment', 'center', 'FontAngle', 'italic', ...
    'Color', [0.45 0.45 0.45]);
axis(ax, 'off');
end

% =========================================================================
function s = localLabel(metric)
%LOCALLABEL The LaTeX y-axis label for a metric.
%   Inputs   METRIC, the row field being plotted
%   Outputs  S, its label
%   Utility  the metric is an option, so the label has to follow it.
switch string(metric)
    case "poseRMSE",      s = "pose RMSE (m)";
    case "landmarkRMSE",  s = "landmark RMSE (m)";
    case "minEssSupport", s = "support ESS (higher is better)";
    case "lookupMean",    s = "mean nearest-support lookup (m)";
    otherwise,            s = metric;
end
end

% =========================================================================
function s = localPlain(metric)
%LOCALPLAIN The same label without LaTeX, for a legend or a message.
%   Inputs   METRIC, the row field being plotted
%   Outputs  S, plain text
%   Utility  not every place the name appears has a LaTeX interpreter.
s = strrep(char(string(metric)), '_', '\_');
end
