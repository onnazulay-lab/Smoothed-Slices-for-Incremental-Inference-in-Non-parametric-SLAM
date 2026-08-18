function plotEstimatorComparison(ax, results, ref)
%PLOTESTIMATORCOMPARISON f_new(x2) from each method against ground truth.
%
%   Inputs
%     AX       the axes to draw into
%     RESULTS  the method results
%     REF      the quadrature reference, with x2 and fnew
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Show whether each estimator recovers the SHAPE of the generated factor,
%     not merely its mean. The reference is drawn as a filled band so that a
%     departure is visible rather than inferred from a table.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results (1,:) struct
    ref (1,1) struct
end

cla(ax);
hold(ax, 'on');

fill(ax, [ref.x2 fliplr(ref.x2)], [ref.fnew zeros(size(ref.fnew))], ...
    [0.85 0.88 0.92], 'EdgeColor', 'none', 'DisplayName', 'reference (quadrature)');

for i = 1:numel(results)
    r = results(i);
    if r.status ~= "ok", continue; end
    est = r.posterior.estimator;
    plot(ax, est.support, est.fnew, '-', 'LineWidth', 1.6, ...
        'Color', viz.methodColors(r.methodName), 'DisplayName', char(r.methodName));
end

hold(ax, 'off');
utils.applyLatexToAxes(ax);
utils.setLatexTitle(ax, "$\hat f_{\mathrm{new}}(x_2 \mid D_2)$ versus exact quadrature");
utils.setLatexXY(ax, "$x_2$", "$f_{\mathrm{new}}(x_2)$");
legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'Box', 'off');
end
