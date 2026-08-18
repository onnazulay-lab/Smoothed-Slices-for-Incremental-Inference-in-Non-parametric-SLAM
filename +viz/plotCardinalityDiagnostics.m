function plotCardinalityDiagnostics(ax, results)
%PLOTCARDINALITYDIAGNOSTICS The |space letter| budgets, side by side.
%
%   Inputs
%     AX       the axes to draw into
%     RESULTS  the method results
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Make the cost story visible: the nested estimator spends its budget on
%     inner samples, the RCS surface on support points and active successors.
%     Specification sections 9 and 16 require every finite space to be shown
%     as |space letter| in blue, which is why the y axis is coloured.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results (1,:) struct
end

cla(ax);

labels = ["$|\mathcal{X}_0|$", "$|L_n|$", "$|\mathcal{S}|$", ...
          "$|\mathcal{X}_1|$", "$|\mathcal{N}_0|$"];
fields = ["outer", "inner", "separator", "pathSupport", "activeSet"];

ok = arrayfun(@(r) r.status == "ok", results);
res = results(ok);
if isempty(res)
    text(ax, 0.5, 0.5, 'no completed runs', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Interpreter', 'latex');
    return
end

vals = zeros(numel(res), numel(fields));
for i = 1:numel(res)
    c = res(i).metrics.cardinality;
    for j = 1:numel(fields)
        if isfield(c, fields(j)) && ~isempty(c.(fields(j)))
            vals(i,j) = c.(fields(j));
        end
    end
end

b = bar(ax, vals.', 'grouped');
for i = 1:numel(res)
    b(i).FaceColor = viz.methodColors(res(i).methodName);
    b(i).EdgeColor = 'none';
    b(i).DisplayName = char(res(i).methodName);
end

utils.applyLatexToAxes(ax);
ax.XTick = 1:numel(labels);
ax.XTickLabel = labels;
ax.YColor = utils.cardinalityColor();
utils.setLatexTitle(ax, "Finite-support cardinalities");
utils.setLatexXY(ax, "", "count");
legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'Box', 'off');
end
