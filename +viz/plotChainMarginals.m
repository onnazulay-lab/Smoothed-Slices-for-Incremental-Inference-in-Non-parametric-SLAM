function plotChainMarginals(ax, results, caseData, ref, k)
%PLOTCHAINMARGINALS One pose's marginal, exact against each method.
%
%   Inputs
%     AX        the axes to draw into
%     RESULTS   the method results
%     CASEDATA  the case
%     REF       the chain reference
%     K         which pose; 0 picks the most ambiguous one       default 0
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Draw the exact posterior marginal of pose K from the chain reference,
%     with each method's recovered marginal over it as a histogram.
%
%   Histograms rather than kernel estimates, deliberately. A kernel estimate
%   needs a bandwidth, and on a four-mode posterior the bandwidth decides
%   whether the modes appear at all; the figure would then be showing the
%   smoother's opinion rather than the method's. The reference grid supplies
%   the bin edges, so nothing else has to be chosen.
%
%   K defaults to the most ambiguous pose -- the one where the exact
%   posterior spreads its mass over the most doors -- because that is the
%   pose where the methods can differ and the others are all agreement.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results struct
    caseData (1,1) struct
    ref (1,1) struct
    k (1,1) double = 0
end

if k < 1
    live = sum(ref.modeWeights > 0.05, 1);
    [~, k] = max(live);
end

cla(ax, 'reset');
hold(ax, 'on');

g = ref.grid;
plot(ax, g, ref.marginals(:,k), '-', 'Color', [0.25 0.25 0.25], ...
    'LineWidth', 1.8, 'DisplayName', 'exact');

edges = [g(1) - (g(2)-g(1))/2, (g(1:end-1) + g(2:end))/2, g(end) + (g(2)-g(1))/2];
name = caseData.mission.poseNames(k);
key = matlab.lang.makeValidName(name);

for i = 1:numel(results)
    r = results(i);
    if ~isfield(r, 'status') || r.status ~= "ok", continue, end
    if ~isfield(r.posterior, 'marginals') || ~isfield(r.posterior.marginals, key)
        continue
    end
    S = r.posterior.marginals.(key);
    h = histcounts(S(:,1), edges, 'Normalization', 'pdf');

    % Smoothed only for legibility of the line, never for the metric: the
    % scoring in scoreAgainstChainReference uses the raw histogram.
    colour = viz.methodColors(string(r.methodName));
    plot(ax, g, movmean(h, 25), '-', 'Color', colour, 'LineWidth', 1.3, ...
        'DisplayName', string(r.methodName));
end

% Door positions, so a mode can be read off against the thing it means.
yl = ylim(ax);
for d = caseData.doors
    plot(ax, [d d], [0 yl(2)], ':', 'Color', [0.85 0.65 0.10], ...
        'LineWidth', 1.0, 'HandleVisibility', 'off');
end

legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'FontSize', 8);
hold(ax, 'off');

utils.applyLatexToAxes(ax);
utils.setLatexTitle(ax, sprintf('Marginal of $%s$ (most ambiguous pose)', ...
    regexprep(name, '^([a-zA-Z]+)(\d+)$', '$1_{$2}')));
utils.setLatexXY(ax, 'position', 'density');
end
