function plotMarginalKDE(ax, results, varName, ref)
%PLOTMARGINALKDE Posterior marginal of one variable for every method.
%
%   Inputs
%     AX       the axes to draw into
%     RESULTS  the method results
%     VARNAME  which variable's marginal to draw
%     REF      the reference marginal, when one exists
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Draw the mixture-of-slices marginal from the backward pass, NOT a KDE of
%     the samples despite the specification's figure name. Both papers avoid
%     intermediate density reconstruction, and drawing a KDE here would put one
%     back in exactly the place the method removes it. The samples are shown
%     separately as a rug so the reader can still see them.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results (1,:) struct
    varName (1,1) string
    ref struct = struct()
end

cla(ax);
hold(ax, 'on');

key = matlab.lang.makeValidName(varName);

if isfield(ref, 'x2') && varName == "x2"
    plot(ax, ref.x2, ref.pdf, '--', 'LineWidth', 1.4, ...
        'Color', viz.methodColors("reference"), 'DisplayName', 'reference');
end

for i = 1:numel(results)
    r = results(i);
    if r.status ~= "ok" || ~isfield(r.posterior.marginals, key), continue; end
    m = r.posterior.marginals.(key);
    plot(ax, m.grid, m.pdf, '-', 'LineWidth', 1.5, ...
        'Color', viz.methodColors(r.methodName), 'DisplayName', char(r.methodName));
end

hold(ax, 'off');
utils.applyLatexToAxes(ax);
disp1 = regexprep(varName, '^([a-zA-Z]+)(\d+)$', '$1_{$2}');
utils.setLatexTitle(ax, sprintf("Marginal $\\hat P(%s \\mid D)$", disp1));
utils.setLatexXY(ax, sprintf("$%s$", disp1), sprintf("$p(%s)$", disp1));
legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'Box', 'off');
end
