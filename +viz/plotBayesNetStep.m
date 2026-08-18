function info = plotBayesNetStep(ax, caseData, step, opts)
%PLOTBAYESNETSTEP The Bayes net the elimination builds, up to one step.
%
%   Inputs
%     AX                the axes to draw into
%     CASEDATA          the case
%     STEP              how far the elimination has got; 0 draws the empty
%                       net, Inf the finished one                default Inf
%     ShowLabels        label the nodes                         default true
%     MaxLabelled       stop labelling past this many nodes        default 24
%     ShowFactorization print the factorization                 default true
%     Order             the order to replay, when a run eliminated in one the
%                       case does not carry
%
%   Outputs
%     INFO              the conditionals drawn, the step reached and the
%                       layout, for tests
%
%   Utility
%     Draw the directed graph produced by eliminating the first STEP variables
%     of the order -- the panel the factor graph cannot be, since what
%     elimination CREATES has nowhere to appear there.
%
%   THE PANEL THE FACTOR GRAPH CANNOT BE. Elimination turns an undirected
%   graph into a directed one, and the factor-graph view shows only what is
%   destroyed at each step: the variable leaves and its factors leave with
%   it. What is *created* -- the conditional p(omega_j | S_j) and the edges
%   S_j -> omega_j -- has nowhere to appear there. Both panels use the same
%   layout (viz.graphLayout) so the reader can read one against the other:
%   the orange factors that vanish on the left are the green arrows that
%   arrive on the right.
%
%   Arrows point PARENT -> CHILD, that is S_j -> omega_j, which is the
%   direction the backward pass travels: the separator is sampled first and
%   the frontal variable is drawn given it. An arrow is therefore also a
%   dependency the traversal must honour, and the step index printed on each
%   node is the reverse order in which they will be drawn.
%
%   Arrow colour runs along the elimination order, so a reader can see the
%   procedure sweep through the graph. Steps after STEP are drawn faintly:
%   the panel shows where the elimination has got to, not just where it ends.
%
arguments
    ax (1,1) matlab.graphics.axis.Axes
    caseData (1,1) struct
    step (1,1) double = Inf
    opts.ShowLabels (1,1) logical = true
    opts.MaxLabelled (1,1) double = 24
    opts.ShowFactorization (1,1) logical = true
    % An incremental replay APPENDS new variables to the previous
    % increment's order rather than re-deriving it, so its order can differ
    % from the case's own. Drawing the case's order against that run's
    % states would show two different eliminations side by side.
    opts.Order (1,:) string = string.empty(1, 0)
end

cla(ax, 'reset');
hold(ax, 'on');

L = viz.graphLayout(caseData);
names = L.names;
n = numel(names);
order = caseData.eliminationOrder;
if ~isempty(opts.Order), order = opts.Order; end

sched = core.eliminationSchedule(caseData.graph, order);
conds = struct('frontal', {sched.frontal}, 'separator', {sched.separator}, ...
               'step', {sched.step});
nc = numel(conds);
step = max(0, min(step, nc));

cRed   = [0.80 0.15 0.15];
cBlue  = [0.10 0.35 0.75];
cGhost = [0.84 0.84 0.84];

% A sequential map, so the arrow colour reads as "when", not "which".
cmap = localSequential(max(nc, 2));

mkVar = round(interp1([3 8 16 30], [20 15 11 8], min(max(n,3),30)));
doLabel = opts.ShowLabels && n <= opts.MaxLabelled;
headLen = 0.030 * L.span;

% --- arrows ---------------------------------------------------------------
for j = 1:nc
    c = conds(j);
    pc = localPos(L, c.frontal);
    if isempty(pc), continue, end

    done = j <= step;
    if j == step
        col = cRed; lw = 2.4; alpha = 1.0;
    elseif done
        col = cmap(j,:); lw = 1.5; alpha = 0.95;
    else
        col = cGhost; lw = 0.8; alpha = 0.5;
    end

    for k = 1:numel(c.separator)
        pp = localPos(L, c.separator(k));
        if isempty(pp), continue, end
        localArrow(ax, pp, pc, col, lw, alpha, headLen, mkVar, L.span);
    end

    % The root conditional has no parents, and an unmarked node is
    % indistinguishable from one whose arrows were clipped. Ring it instead.
    if isempty(c.separator) && done
        plot(ax, pc(1), pc(2), 'o', 'MarkerSize', mkVar + 7, ...
            'MarkerEdgeColor', col, 'LineWidth', 1.6, ...
            'HandleVisibility', 'off');
    end
end

% --- nodes ----------------------------------------------------------------
for i = 1:n
    v = names(i);
    p = L.pos(i,:);
    j = find(order == v, 1);
    if isempty(j), j = NaN; end

    if ~isnan(j) && j == step
        face = cRed;  edge = cRed;  txt = 'w'; lw = 2.0;
    elseif ~isnan(j) && j <= step
        face = cmap(j,:); edge = cmap(j,:); txt = 'w'; lw = 1.4;
    else
        face = [1 1 1]; edge = cGhost; txt = [0.45 0.45 0.45]; lw = 1.0;
    end
    % A variable that is in this step's separator is blue in the factor-graph
    % panel; ringing it blue here is what ties the two together.
    ringBlue = step >= 1 && step <= nc && any(conds(step).separator == v);

    marker = 'o';
    if L.isLandmark(i), marker = '^'; end
    plot(ax, p(1), p(2), marker, 'MarkerSize', mkVar, ...
        'MarkerFaceColor', face, 'MarkerEdgeColor', edge, 'LineWidth', lw, ...
        'HandleVisibility', 'off');
    if ringBlue
        plot(ax, p(1), p(2), marker, 'MarkerSize', mkVar + 5, ...
            'MarkerEdgeColor', cBlue, 'MarkerFaceColor', 'none', ...
            'LineWidth', 1.8, 'HandleVisibility', 'off');
    end

    if doLabel
        text(ax, p(1), p(2), sprintf('$%s$', utils.mathName(v)), ...
            'Interpreter', 'latex', 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', max(7, round(0.62 * mkVar)), 'Color', txt);
        if ~isnan(j)
            % The elimination index, offset above the node. This is what
            % makes the panel a picture of the PROCEDURE rather than of the
            % result: the reader can follow 1, 2, 3, ... across the map.
            text(ax, p(1), p(2) + 0.045 * L.span, sprintf('\\textbf{%d}', j), ...
                'Interpreter', 'latex', 'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'bottom', 'FontSize', 8, ...
                'Color', [0.35 0.35 0.35]);
        end
    end
end

hold(ax, 'off');
axis(ax, 'equal');
xlim(ax, L.xlim);
ylim(ax, L.ylim + [0 0.06 * L.span]);   % room for the step indices
utils.applyLatexToAxes(ax);
grid(ax, 'off');
ax.XTick = []; ax.YTick = [];

% --- title ----------------------------------------------------------------
if step == 0
    utils.setLatexTitle(ax, "Bayes net: nothing eliminated yet");
else
    utils.setLatexTitle(ax, sprintf("Bayes net after %d of %d eliminations: %s", ...
        step, nc, localFactorization(conds, step, opts.ShowFactorization)));
end

info = struct('conditionals', conds, 'step', step, 'layout', L);
end

% =========================================================================
function s = localFactorization(conds, step, show)
%LOCALFACTORIZATION The net's factorization as one LaTeX line.
%   Inputs   CONDS the conditionals, STEP how far to go, SHOW whether to
%           produce anything at all
%   Outputs  S, the line, or "" when SHOW is false
%   Utility  say in symbols what the arrows say in geometry.
if ~show
    s = '';
    return
end
% Long factorizations do not fit an axes title and truncating in the middle
% loses the root, which is the informative end. Keep the head and the tail.
parts = strings(1, step);
for j = 1:step
    c = conds(j);
    if isempty(c.separator)
        parts(j) = sprintf("P(%s)", utils.mathName(c.frontal));
    else
        parts(j) = sprintf("P(%s \\mid %s)", utils.mathName(c.frontal), ...
            strjoin(cellstr(utils.mathName(c.separator)), ','));
    end
end
if step > 4
    parts = [parts(1:2), "\cdots", parts(end)];
end
s = char("$" + join(parts, " ") + "$");
end

% =========================================================================
function localArrow(ax, from, to, col, lw, alpha, headLen, mkVar, span)
%LOCALARROW One parent -> child arrow, stopping short of both node markers.
%   Inputs   AX, FROM and TO positions, COL the colour, LW the width, ALPHA
%           the transparency, HEADLEN the head size, MKVAR the node marker
%           radius, SPAN the axis span the sizes are relative to
%   Outputs  none; draws into AX
%   Utility  annotation() works in figure coordinates, not data coordinates,
%           so the arrow is drawn as a line and a patch instead.
%
%   annotation() lives in figure coordinates and would need the axes position
%   recomputed on every resize; quiver draws heads whose size does not track
%   the data limits. A patch head in data coordinates is the only one of the
%   three that stays correct when the panel is exported at another size.
d = to - from;
Ld = norm(d);
if Ld < eps, return, end
u = d / Ld;

% Stop at the node edge, not the node centre: an arrowhead buried under the
% marker is an arrowhead the reader cannot see.
rad = 0.5 * mkVar / 72 * span * 0.55;
rad = min(rad, 0.35 * Ld);
a = from + u * rad;
b = to   - u * rad;

plot(ax, [a(1) b(1)], [a(2) b(2)], '-', 'Color', [col alpha], ...
    'LineWidth', lw, 'HandleVisibility', 'off');

h = min(headLen, 0.3 * norm(b - a));
p = [-u(2) u(1)];
tri = [b; b - h*u + 0.45*h*p; b - h*u - 0.45*h*p];
patch(ax, 'XData', tri(:,1), 'YData', tri(:,2), 'FaceColor', col, ...
    'EdgeColor', 'none', 'FaceAlpha', alpha, 'HandleVisibility', 'off');
end

% =========================================================================
function c = localSequential(n)
%LOCALSEQUENTIAL N colours running along the elimination order.
%   Inputs   N, how many steps
%   Outputs  C, N-by-3
%   Utility  let a reader see the procedure sweep through the graph.
t = linspace(0, 1, max(n, 2)).';
c = [0.12 + 0.10*t, 0.30 + 0.42*t, 0.75 - 0.35*t];
end

% =========================================================================
function p = localPos(L, name)
%LOCALPOS One variable's layout position, by name.
%   Inputs   L the layout, NAME the variable
%   Outputs  P, 1-by-2
%   Utility  share the layout with the factor-graph panel by name rather than
%           by index.
j = find(L.names == name, 1);
if isempty(j)
    p = [];
else
    p = L.pos(j, :);
end
end
