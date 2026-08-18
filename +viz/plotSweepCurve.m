function info = plotSweepCurve(ax, sweep, opts)
%PLOTSWEEPCURVE One metric against one axis of a sweep, a line per method.
%
%   Inputs
%     AX         the axes to draw into
%     SWEEP      a methods.parameterSweep result
%     Metric     row field to plot                    default "relL1Error"
%     XAxis      axis coordinate for x                default "budget"
%     Filter     struct of coordinate = value pairs held fixed  default none
%     Aggregate  "median" | "mean" | "none"           default "median"
%     YScale     "log" | "linear"                     default "log"
%     Label      y-axis label; defaults to the metric name
%
%   Outputs
%     INFO.numPerPoint   points aggregated into each plotted marker
%     INFO.methods       methods actually drawn (one with no finite data is
%                        not)
%     INFO.x             the x values, sorted
%     INFO.skipped       methods present in the sweep but with nothing finite
%
%   Utility
%     Draw one metric against one sweep axis, a line per method.
%
%   THIS IS THE FIGURE A SINGLE RUN CANNOT PRODUCE. One comparison says which
%   method won on one problem at one budget, which is a fact about that cell
%   and not about the methods. A curve says whether the error falls when the
%   budget grows -- and a method whose curve is flat in N is not losing to
%   sampling noise, it is biased, which is a different finding with a
%   different fix.
%
%   AGGREGATION IS OVER THE CELLS THE FILTER LEAVES BEHIND. Plotting error
%   against budget over a six-scenario grid means six measurements per method
%   per budget, and they are not repeats of one experiment -- they are six
%   different problems. The median across them is a statement about typical
%   behaviour, not an estimate of anything, and the count is returned in
%   INFO.numPerPoint so a caller can say so in the title rather than implying
%   a precision the sweep does not have.
%
%   The median, not the mean, because these are error metrics on problems of
%   different difficulty: one hard cell dominates a mean and the line then
%   tracks that cell rather than the method.
%
%   See also methods.parameterSweep, viz.methodColors.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    sweep (1,1) struct
    opts.Metric (1,1) string = "relL1Error"
    opts.XAxis (1,1) string = "budget"
    opts.Filter (1,1) struct = struct()
    opts.Aggregate (1,1) string {mustBeMember(opts.Aggregate, ["median","mean","none"])} = "median"
    opts.YScale (1,1) string {mustBeMember(opts.YScale, ["log","linear"])} = "log"
    opts.Label (1,1) string = ""
end

cla(ax, 'reset');
hold(ax, 'on');

info = struct('numPerPoint', [], 'methods', string.empty(1,0), ...
              'x', [], 'skipped', string.empty(1,0));

rows = sweep.rows;
if isempty(rows)
    localEmptyMessage(ax, 'No cells completed.');
    return
end

localRequireField(rows, opts.Metric, 'Metric');
localRequireField(rows, opts.XAxis, 'XAxis');

% --- Filter ---------------------------------------------------------------
keep = true(1, numel(rows));
fn = fieldnames(opts.Filter);
for i = 1:numel(fn)
    localRequireField(rows, string(fn{i}), 'Filter');
    want = opts.Filter.(fn{i});
    have = localColumn(rows, fn{i});
    if isstring(want) || ischar(want)
        keep = keep & (string(have(:)).' == string(want));
    else
        keep = keep & (double(have(:)).' == double(want));
    end
end

% Only completed methods contribute. A cancelled stub carries NaN throughout,
% and dropping it here rather than letting NaN propagate is what keeps a
% cancelled sweep's curve ending early instead of dipping to nothing.
keep = keep & (localColumn(rows, 'status') == "ok");
rows = rows(keep);

if isempty(rows)
    localEmptyMessage(ax, 'No completed rows match this filter.');
    return
end

x   = double(localColumn(rows, char(opts.XAxis)));
y   = double(localColumn(rows, char(opts.Metric)));
who = localColumn(rows, 'method');

xs = unique(x, 'sorted');
info.x = xs;

% --- One line per method --------------------------------------------------
% Reshaped to a row before iterating. `for m = column` runs ONCE with m bound
% to the whole column, which here would draw a single line labelled with
% every method name at once -- the same trap harmonizeResults documents.
% unique does return a row for a row input today; this does not depend on it.
for m = reshape(unique(who, 'stable'), 1, [])
    isM = (who == m);
    yv = nan(1, numel(xs));
    nv = zeros(1, numel(xs));

    for k = 1:numel(xs)
        v = y(isM & x == xs(k));
        v = v(isfinite(v));
        nv(k) = numel(v);
        if isempty(v), continue, end
        switch opts.Aggregate
            case "median", yv(k) = median(v);
            case "mean",   yv(k) = mean(v);
            case "none",   yv(k) = v(1);
        end
    end

    % A method that produced nothing finite is named in INFO rather than
    % drawn as an empty line. An empty line still claims a legend entry, and
    % a legend entry with no curve reads as a curve at zero.
    if ~any(isfinite(yv))
        info.skipped(end+1) = m;
        continue
    end

    colour = viz.methodColors(m);
    plot(ax, xs, yv, '-o', 'Color', colour, 'LineWidth', 1.6, ...
        'MarkerSize', 5, 'MarkerFaceColor', colour, 'DisplayName', m);

    info.methods(end+1) = m;
    if isempty(info.numPerPoint)
        info.numPerPoint = nv;
    else
        info.numPerPoint = max(info.numPerPoint, nv);
    end
end

% --- Scales ---------------------------------------------------------------
% A log y-axis is right for the error metrics, which span decades, and wrong
% the moment a value is zero or negative -- the unbiased MMD estimator
% legitimately returns a small negative number when two samples are
% indistinguishable. Falling back rather than dropping the point keeps a
% converged method on the plot.
if opts.YScale == "log" && all(localPlottedY(ax) > 0)
    set(ax, 'YScale', 'log');
else
    set(ax, 'YScale', 'linear');
end
if opts.XAxis == "budget"
    % The budgets are geometric, so a linear axis crowds three of the four
    % points against the left edge.
    set(ax, 'XScale', 'log');
    xticks(ax, xs);
    xticklabels(ax, string(xs));
end

if ~isempty(info.methods)
    legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'FontSize', 8);
end
grid(ax, 'on');
hold(ax, 'off');

label = opts.Label;
if strlength(label) == 0, label = localMetricLabel(opts.Metric); end

utils.applyLatexToAxes(ax);
utils.setLatexXY(ax, localAxisLabel(opts.XAxis), label);
end

% =========================================================================
function y = localPlottedY(ax)
%LOCALPLOTTEDY Every finite y value currently on the axes.
%   Inputs   AX, the axes
%   Outputs  Y, the values as a column
%   Utility  set the limits from what was actually drawn, so a log axis is not
%           given a zero to place.
h = findobj(ax, 'Type', 'line');
y = [];
for i = 1:numel(h)
    v = h(i).YData(:).';
    y = [y, v(isfinite(v))]; %#ok<AGROW>
end
if isempty(y), y = 1; end   % nothing drawn: do not veto the log scale
end

% =========================================================================
function localRequireField(rows, name, what)
%LOCALREQUIREFIELD Refuse a metric or axis the sweep does not carry.
%   Inputs   ROWS the sweep table, NAME the column, WHAT it was asked for as
%   Outputs  none; throws
%   Utility  a missing column would otherwise draw as an empty panel and read
%           as "the methods produced nothing".
if ~isfield(rows, name)
    error('viz:plotSweepCurve:noSuchField', ...
        '%s "%s" is not a field of the sweep rows. Available: %s.', ...
        what, name, strjoin(string(fieldnames(rows)).', ', '));
end
end

% =========================================================================
function v = localColumn(rows, name)
%LOCALCOLUMN One column of the sweep table as a double column.
%   Inputs   ROWS the table, NAME the column
%   Outputs  V, one value per row
%   Utility  read a column whatever type the sweep stored it as.
c = {rows.(name)};
if all(cellfun(@(e) isstring(e) || ischar(e), c))
    v = string(c);
else
    v = cell2mat(c);
end
end

% =========================================================================
function localEmptyMessage(ax, msg)
%LOCALEMPTYMESSAGE Say why the panel is empty, inside the panel.
%   Inputs   AX the axes, MSG the text
%   Outputs  none; draws into AX
%   Utility  blank axes read as a rendering failure.
text(ax, 0.5, 0.5, msg, 'Units', 'normalized', ...
    'HorizontalAlignment', 'center', 'FontAngle', 'italic', ...
    'Color', [0.45 0.45 0.45]);
axis(ax, 'off');
end

% =========================================================================
function s = localMetricLabel(metric)
%LOCALMETRICLABEL The LaTeX y-axis label for a metric.
%   Inputs   METRIC, the row field being plotted
%   Outputs  S, its label
%   Utility  the metric is an option, so the label has to follow it.
switch metric
    case "relL1Error",  s = "relative $L_1$ error";
    case "relL2Error",  s = "relative $L_2$ error";
    case "massError",   s = "relative mass error";
    case "mmd",         s = "MMD to the reference";
    case "rmse",        s = "posterior-mean RMSE";
    case "ess",         s = "effective sample size";
    case "runtimeTotal", s = "runtime (s)";
    otherwise,          s = metric;
end
end

% =========================================================================
function s = localAxisLabel(name)
%LOCALAXISLABEL The LaTeX x-axis label for a sweep coordinate.
%   Inputs   NAME, the coordinate
%   Outputs  S, its label
%   Utility  name the axis in the notation the rest of the figures use.
switch name
    case "budget",     s = "outer samples $N$";
    case "separation", s = "mixture separation $d$";
    case "odomSigma",  s = "odometry $\sigma$";
    otherwise,         s = name;
end
end
