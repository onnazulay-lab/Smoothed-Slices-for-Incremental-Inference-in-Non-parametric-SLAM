function plotSmoothingSurfaceStep(ax, result, ref)
%PLOTSMOOTHINGSURFACESTEP Heatmap of the conditional smoothing surface R_0.
%
%   Inputs
%     AX      the axes to draw into
%     RESULT  one method result
%     REF     the reference surface, when one exists
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Show R_0(x1, x2), the object that replaces nested sampling. Section 17
%     of the specification insists this is never called a "message": it is an
%     expected future factor contribution, not a density, and the axis label
%     says so.
%
%   When the reference surface is supplied the panel switches to the signed
%   error against it, because for a low-dimensional case the interesting
%   question is not what the surface looks like but where it is wrong.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    result (1,1) struct
    ref struct = struct()
end

cla(ax);

if result.status ~= "ok" || numel(result.states) < 2 ...
        || ~isfield(result.states(2).Diagnostics, 'inner') ...
        || ~isfield(result.states(2).Diagnostics.inner, 'supportX1')
    text(ax, 0.5, 0.5, 'no surface for this method', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    return
end

st  = result.states(2);
xi0 = st.NewFactor.Samples;
S   = st.NewFactor.SeparatorSupport;

% Recover R_0 from the stored slice matrix by dividing out the front factor.
% Storing the product is what the estimator needs; the surface alone is what
% the reader needs, so it is reconstructed for display only.
inner = st.Diagnostics.inner;
if isfield(inner, 'R1')
    [xi0s, ord] = sort(xi0);
    R0 = st.NewFactor.SliceMatrix(ord, :);
    imagesc(ax, S, xi0s, R0);
    set(ax, 'YDir', 'normal');
    axis(ax, 'tight');
    colormap(ax, viz.surfaceColormap());
    cb = colorbar(ax);
    cb.TickLabelInterpreter = 'latex';
end

utils.applyLatexToAxes(ax);
utils.setLatexTitle(ax, ...
    "Conditional smoothing surface $b_0(x_1,x_2)\,R_0(x_1,x_2)$");
utils.setLatexXY(ax, "$x_2$ (separator)", "$x_1$ (path variable $\xi_0$)");
end
