function info = plotSurfaceRankVsAxis(ax, study, opts)
%PLOTSURFACERANKVSAXIS Does the surface stay compact as the case gets harder?
%
%   Inputs
%     AX            the axes to draw into
%     STUDY         a research.surfaceComplexityStudy result
%     Axis          which swept axis to draw
%                                       default the first with 2+ levels
%     ShowSparsity  draw the right-hand axis                   default true
%
%   Outputs
%     INFO          which axis was drawn, how many points, and whether the
%                   sparsity series was shown
%
%   Utility
%     Plot the 99 %-energy rank of R_0 against the level of one swept axis,
%     with the sparsity on a right-hand axis and the compactness budget drawn
%     as a line.
%
%   NOT "RANK VS STEP", AND THE DIFFERENCE MATTERS. The research sheet asks
%   for numerical rank against elimination step. The one case in this
%   repository that builds a conditional smoothing surface builds exactly ONE
%   of them -- the two-pose graph has a single Lemma 1 elimination -- so there
%   is no step axis to plot against, and drawing a one-point line under that
%   title would be a figure pretending to a sequence it does not have. The
%   axis here is the independent variable E2 actually names: how hard the case
%   is. When a multi-step case takes the surface route, that plot becomes
%   available and this one stays worth having.
%
%   TWO SERIES, TWO CLAIMS, ONE PLOT. Low rank and high sparsity are separate
%   properties -- a dense surface can be compressible and a sparse one can be
%   full rank -- and E2 asks for both. They share a horizontal axis and
%   nothing else, so sparsity gets the right-hand axis and its own colour, and
%   the two are never joined by a line.
%
%   THE BUDGET LINE IS A CONVENTION. The dashed horizontal is the compactness
%   threshold that methods.smoothed.surfaceComplexity uses to turn a number
%   into the word "compact": ten percent of min(|X_0|, |S|). Nothing in the
%   sheet sets it. It is drawn so that a reader can see how far a point sits
%   from a line they may disagree with, rather than being told a verdict.
%
%   See also research.surfaceComplexityStudy, viz.plotSurfaceSpectrum.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    study (1,1) struct
    opts.Axis (1,1) string = ""
    opts.ShowSparsity (1,1) logical = true
end

cla(ax, 'reset');
% Every field set here rather than on the branch that happens to reach it, so
% that callers get the same shape whichever way the function returns.
info = struct('axis', "", 'points', 0, 'sparsityShown', false);

T = study.rows;
if height(T) == 0
    text(ax, 0.5, 0.5, 'no configurations in this study', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    return
end

wanted = opts.Axis;
if strlength(wanted) == 0
    wanted = localFirstNumericAxis(T);
end
if strlength(wanted) == 0
    text(ax, 0.5, 0.5, 'no axis in this study has a numeric level', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    return
end

sub = T(T.axis == wanted, :);
sub = sortrows(sub, 'level');
info.axis   = wanted;
info.points = height(sub);

yyaxis(ax, 'left');
plot(ax, sub.level, sub.energyRank99, '-o', 'LineWidth', 1.6, ...
    'MarkerFaceColor', 'auto', 'DisplayName', '99\% energy rank');
hold(ax, 'on');

% min(|X_0|,|S|) is the same for every row of a study, so one line serves.
budget = study.compactBudget;
yline(ax, budget, '--', 'Color', [0.4 0.4 0.4], 'LineWidth', 1.2, ...
    'DisplayName', sprintf('compact below %.0f', budget));
ylabel(ax, '');
utils.setLatexXY(ax, localAxisLabel(wanted), "99\% energy rank of $R_0$");
hold(ax, 'off');

if opts.ShowSparsity
    yyaxis(ax, 'right');
    plot(ax, sub.level, sub.sparsity, ':s', 'LineWidth', 1.4, ...
        'DisplayName', 'sparsity');
    ylim(ax, [0 1]);
    ylabel(ax, 'sparsity', 'Interpreter', 'latex');
    yyaxis(ax, 'left');
    info.sparsityShown = true;
end

grid(ax, 'on');
utils.setLatexTitle(ax, sprintf("Surface complexity against %s", ...
    localEscape(wanted)));
legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'Box', 'off', ...
    'FontSize', 7);
utils.applyLatexToAxes(ax);
end

% =========================================================================
function name = localFirstNumericAxis(T)
%LOCALFIRSTNUMERICAXIS The first swept axis with more than one level.
%   Inputs   T, the study's row table
%   Outputs  NAME, the axis to draw, or "" when none has two levels
%   Utility  choose an axis worth plotting rather than drawing a one-point
%           line under a title that promises a curve.
%
%   The variant axis is categorical -- "gaussian" against "multimodal" -- and
%   has no numeric level, so it is skipped rather than plotted at NaN.
name = "";
for a = unique(T.axis, 'stable').'
    lv = T.level(T.axis == a);
    if sum(isfinite(lv)) >= 2
        name = a;
        return
    end
end
end

% =========================================================================
function s = localAxisLabel(a)
%LOCALAXISLABEL The LaTeX label for one swept axis.
%   Inputs   A, the axis name
%   Outputs  S, its label
%   Utility  name the axis in the notation the rest of the figures use.
switch string(a)
    case "noise",   s = "odometry $\sigma$";
    case "overlap", s = "mixture offset $d$";
    otherwise,      s = localEscape(a);
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
