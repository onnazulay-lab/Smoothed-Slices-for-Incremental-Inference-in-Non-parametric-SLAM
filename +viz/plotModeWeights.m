function plotModeWeights(ax, results, caseData, ref)
%PLOTMODEWEIGHTS Recovered mode weights against the exact ones.
%
%   Inputs
%     AX        the axes to draw into
%     RESULTS   the method results
%     CASEDATA  the case, carrying the doors
%     REF       the chain reference, carrying the exact weights
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Draw, for each pose, the posterior mass every method assigns to each
%     door, with the exact weights from the chain reference behind them.
%
%   This is the figure the Four Doors case exists to produce. Where the exact
%   posterior splits its mass evenly between two doors and a method puts all
%   of it on one, the bars say so immediately; the trajectory plot of the
%   same run looks fine, and the RMSE improves.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results struct
    caseData (1,1) struct
    ref (1,1) struct
end

cla(ax, 'reset');
hold(ax, 'on');

K = numel(caseData.mission.poseNames);
D = numel(caseData.doors);

% The exact weights as a stacked grey background, one bar per pose.
b = bar(ax, 1:K, ref.modeWeights.', 'stacked', 'BarWidth', 0.75);
grey = linspace(0.55, 0.9, D).';
for d = 1:D
    b(d).FaceColor = [grey(d) grey(d) grey(d)];
    b(d).EdgeColor = [0.4 0.4 0.4];
    b(d).FaceAlpha = 0.55;
    if d == 1
        b(d).DisplayName = 'exact (chain forward-backward)';
    else
        b(d).HandleVisibility = 'off';
    end
end

% Each method's weights as markers on top, one column of markers per pose.
% Markers rather than more bars: bars would triple the width and the reader
% would be comparing positions rather than heights.
offs = linspace(-0.22, 0.22, max(2, numel(results)));
for i = 1:numel(results)
    r = results(i);
    if ~isfield(r, 'status') || r.status ~= "ok", continue, end
    if ~isfield(r.metrics, 'modeWeights') || isempty(r.metrics.modeWeights), continue, end

    W = r.metrics.modeWeights;
    colour = viz.methodColors(string(r.methodName));
    cum = cumsum(W, 1);

    for d = 1:D
        plot(ax, (1:K) + offs(i), cum(d,:), 's', 'MarkerSize', 6, ...
            'MarkerFaceColor', colour, 'MarkerEdgeColor', colour*0.6, ...
            'HandleVisibility', localVis(d == 1));
    end
    % One invisible handle carries the legend entry for the whole method.
    plot(ax, NaN, NaN, 's', 'MarkerSize', 6, 'MarkerFaceColor', colour, ...
        'MarkerEdgeColor', colour*0.6, 'DisplayName', string(r.methodName));
end

ylim(ax, [0 1.02]);
xlim(ax, [0.4 K + 0.6]);
xticks(ax, 1:K);
legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'FontSize', 8);
hold(ax, 'off');

utils.applyLatexToAxes(ax);
utils.setLatexTitle(ax, 'Mode weights per pose: cumulative mass by door');
utils.setLatexXY(ax, 'increment $k$', 'cumulative posterior mass');
end

% =========================================================================
function v = localVis(tf)
%LOCALVIS A logical as the 'on'/'off' a graphics property wants.
%   Inputs   TF, logical
%   Outputs  V, "on" or "off"
%   Utility  keep one legend entry per method rather than one per pose.
if tf, v = 'off'; else, v = 'off'; end
end
