function info = plotActiveSetError(ax, profile, opts)
%PLOTACTIVESETERROR How small can the active set be? Research sheet E2.
%
%   Inputs
%     AX              the axes to draw into
%     PROFILE         a research.activeSetProfile result
%     ShowPosterior   draw the reference-scored curve and floor  default true
%     LogY            logarithmic error axis                     default true
%
%   Outputs
%     INFO            how many points were drawn, and the K at which the
%                     tolerance was crossed
%
%   Utility
%     Draw relative error against the dense update on the vertical axis,
%     active successor count K on the horizontal, with the tolerance, the
%     posterior error and the |X_1| limit all marked.
%
%   THE VERTICAL LINE IS THE WHOLE FIGURE. It sits at |X_1|, the support the
%   active set is chosen from, and the sheet's failure signal for the
%   compactness claim is written as "K must approach |X_{r+1}|". A curve that
%   only reaches the tolerance as it approaches that line has answered the
%   research question in the negative: the sparse recursion needed to be
%   dense. A curve that crosses the tolerance far to the left of it is the
%   positive answer, and the distance between the crossing and the line is
%   how much was won.
%
%   TWO ERRORS, DELIBERATELY ON ONE AXIS. The solid curve is the distance
%   from the dense update -- the sparsification and nothing else. The dotted
%   curve is the posterior's own error against the quadrature reference, and
%   the horizontal band is where that error sits for the DENSE run. Wherever
%   the dotted curve lies inside the band, sparsification has stopped being
%   the thing that limits the answer, and a K chosen by the solid curve alone
%   is stricter than the problem requires. Plotting them apart would let a
%   reader take a surface error of 1e-2 seriously in a run whose posterior
%   error is 1e-1 either way.
%
%   See also research.activeSetProfile, viz.plotSurfaceSpectrum.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    profile (1,1) struct
    opts.ShowPosterior (1,1) logical = true
    opts.LogY (1,1) logical = true
end

cla(ax, 'reset');
hold(ax, 'on');
info = struct('points', 0, 'crossing', NaN);

T = profile.rows;
fin = T(isfinite(T.K), :);
if height(fin) == 0
    text(ax, 0.5, 0.5, 'no finite active set was tested', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    return
end
info.points = height(fin);

% The band goes down FIRST so the curves draw over it. uistack would be the
% obvious way to say that afterwards, and it throws on a uiaxes -- "Children
% may only be set to a permutation of itself" -- so the ordering is expressed
% as drawing order, which works on both kinds of axes.
if opts.ShowPosterior && isfinite(profile.floor) && profile.floor > 0
    % A band rather than a line: the floor is one dense run's error, and a
    % second dense run would not reproduce it exactly. Drawing it as a
    % hairline would invite comparisons it cannot support.
    lo = profile.floor * 0.8;
    hi = profile.floor * 1.25;
    xl = [min(fin.K) max(fin.K)];
    fill(ax, [xl fliplr(xl)], [lo lo hi hi], [0.75 0.35 0.10], ...
        'FaceAlpha', 0.12, 'EdgeColor', 'none', ...
        'DisplayName', 'dense run''s own error');
end

plot(ax, fin.K, max(fin.surfaceError, realmin), '-o', 'LineWidth', 1.8, ...
    'Color', [0.15 0.35 0.70], 'MarkerFaceColor', [0.15 0.35 0.70], ...
    'DisplayName', 'distance from dense update');

if opts.ShowPosterior && any(isfinite(fin.posteriorError))
    plot(ax, fin.K, max(fin.posteriorError, realmin), ':s', 'LineWidth', 1.4, ...
        'Color', [0.75 0.35 0.10], 'DisplayName', 'posterior vs reference');
end

yline(ax, profile.tolerance, '--', 'Color', [0.35 0.35 0.35], ...
    'LineWidth', 1.2, 'DisplayName', sprintf('tolerance %.0e', profile.tolerance));

h = xline(ax, profile.X1, '-', 'Color', [0.70 0.15 0.15], 'LineWidth', 1.6, ...
    'DisplayName', sprintf('$|X_1| = %d$', profile.X1));
h.Interpreter = 'latex';

if isfinite(profile.recommended.K)
    info.crossing = profile.recommended.K;
    h = xline(ax, profile.recommended.K, ':', 'Color', [0.15 0.55 0.25], ...
        'LineWidth', 1.6, 'DisplayName', sprintf('$K^\\ast = %g$', ...
        profile.recommended.K));
    h.Interpreter = 'latex';
end

set(ax, 'XScale', 'log');
if opts.LogY, set(ax, 'YScale', 'log'); end
grid(ax, 'on');
hold(ax, 'off');

utils.setLatexXY(ax, "active successors $K = |N_0|$", "relative error");
% The headline rather than the verdict: the verdict is the surface criterion
% alone, and on this case the two criteria disagree by a factor of several.
% A title that quoted one of them would be choosing the answer for the reader.
utils.setLatexTitle(ax, sprintf("Active set on %s: \\textbf{%s}", ...
    localEscape(profile.variant), localEscape(profile.headline)));
legend(ax, 'Interpreter', 'latex', 'Location', 'southwest', 'Box', 'off', ...
    'FontSize', 7);
utils.applyLatexToAxes(ax);
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
