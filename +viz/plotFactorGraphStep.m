function info = plotFactorGraphStep(ax, caseData, state, opts)
%PLOTFACTORGRAPHSTEP The factor graph with one elimination step highlighted.
%
%   Inputs
%     AX           the axes to draw into
%     CASEDATA     the case
%     STATE        one elimination state; [] draws G_0             default []
%     ShowLabels   label the nodes                              default true
%     MaxLabelled  stop labelling past this many nodes             default 24
%     Order        the order to replay, when a run eliminated in one the case
%                  does not carry
%
%   Outputs
%     INFO         the reduced graph that was drawn -- factors, eliminated,
%                  separator, removed and the layout -- so tests can assert on
%                  the structure rather than on pixels
%
%   Utility
%     Draw G_0, or G_{j-1} as it stands when step j begins with that step
%     marked up in the colour code specification section 11 fixes.
%
%   Specification section 11 fixes the colour code: the eliminated variable
%   omega_j in red, the removed factors F_{j-1}(omega_j) in orange, the
%   separator S_j in blue and the new factor f_new in green. Keeping to it
%   means a reader who knows the paper can read this panel immediately.
%
%   THE GRAPH IS REDUCED STRUCTURALLY, not read back from the method's state.
%   Starting from G_0 and replaying the eliminations gives G_{j-1} for any j
%   without a run having happened, which is what lets the panel show the
%   procedure on a freshly loaded case, and it makes the panel agree with the
%   engine by construction rather than by matching factor names.
%
%   Already-eliminated variables stay on the canvas, ghosted. Dropping them
%   would leave the reader with no way to see that the graph got denser as
%   the variables went away, which is the whole cost of elimination.
%
%   Layout comes from viz.graphLayout, shared with viz.plotBayesNetStep.
%
arguments
    ax (1,1) matlab.graphics.axis.Axes
    caseData (1,1) struct
    state = []
    opts.ShowLabels (1,1) logical = true
    opts.MaxLabelled (1,1) double = 24
    % See the note on viz.plotBayesNetStep: an incremental replay eliminates
    % in an order the case does not carry, and the panel has to be told.
    opts.Order (1,:) string = string.empty(1, 0)
end

cla(ax, 'reset');
hold(ax, 'on');

L = viz.graphLayout(caseData);
names = L.names;
n = numel(names);

cRed    = [0.80 0.15 0.15];
cOrange = [0.90 0.55 0.10];
cBlue   = [0.10 0.35 0.75];
cGreen  = [0.10 0.60 0.35];
cGrey   = [0.55 0.55 0.55];
cGhost  = [0.82 0.82 0.82];

% --- which step ----------------------------------------------------------
step = 0;
elim = "";
sep  = string.empty(1,0);
if ~isempty(state)
    step = state.Step;
    elim = state.EliminatedVar;
    sep  = state.Separator;
end

order = caseData.eliminationOrder;
if ~isempty(opts.Order), order = opts.Order; end
sched = core.eliminationSchedule(caseData.graph, order);

if step >= 1 && step <= numel(sched)
    factors    = sched(step).factors;
    removedMask = sched(step).removed;
    eliminated = order(1:step-1);
    if isempty(sep), sep = sched(step).separator; end
elseif step > numel(sched)
    factors = struct('name', {}, 'scope', {}, 'generated', {});
    removedMask = false(1, 0);
    eliminated = order;
else
    factors = sched(1).factors;             % G_0, nothing eliminated
    removedMask = false(1, numel(factors));
    eliminated = string.empty(1,0);
end

% --- sizes ----------------------------------------------------------------
mkVar = round(interp1([3 8 16 30], [20 15 11 8], min(max(n,3),30)));
mkFac = max(4, round(0.5 * mkVar));
off   = 0.090 * L.span;                 % unary-factor stub length
doLabel = opts.ShowLabels && n <= opts.MaxLabelled;

% --- factors --------------------------------------------------------------
for i = 1:numel(factors)
    f = factors(i);
    P = localPos(L, f.scope);
    if isempty(P), continue, end

    isGen = f.generated;
    if removedMask(i)
        col = cOrange; lw = 2.0; ls = '-';
    elseif isGen
        col = cGreen;  lw = 1.4; ls = ':';
    else
        col = cGrey;   lw = 1.0; ls = '-';
    end

    if size(P, 1) == 1
        node = P + off * [1 -1] / sqrt(2);
        plot(ax, [P(1) node(1)], [P(2) node(2)], ls, 'Color', col, ...
            'LineWidth', lw, 'HandleVisibility', 'off');
    else
        node = mean(P, 1);
        for k = 1:size(P, 1)
            plot(ax, [node(1) P(k,1)], [node(2) P(k,2)], ls, 'Color', col, ...
                'LineWidth', lw, 'HandleVisibility', 'off');
        end
    end
    plot(ax, node(1), node(2), 's', 'MarkerSize', mkFac, ...
        'MarkerFaceColor', col, 'MarkerEdgeColor', col, ...
        'HandleVisibility', 'off');
end

% --- the factor this step will generate -----------------------------------
% Drawn even when the separator is a single variable, or the last elimination
% would appear to produce nothing at all.
if strlength(elim) > 0 && ~isempty(sep)
    P = localPos(L, sep);
    if size(P, 1) == 1
        node = P + off * [-1 -1] / sqrt(2);
        plot(ax, [P(1) node(1)], [P(2) node(2)], ':', 'Color', cGreen, ...
            'LineWidth', 2.5, 'HandleVisibility', 'off');
    else
        node = mean(P, 1);
        for k = 1:size(P, 1)
            plot(ax, [node(1) P(k,1)], [node(2) P(k,2)], ':', 'Color', cGreen, ...
                'LineWidth', 2.5, 'HandleVisibility', 'off');
        end
    end
    plot(ax, node(1), node(2), 's', 'MarkerSize', mkFac + 2, ...
        'MarkerFaceColor', cGreen, 'MarkerEdgeColor', cGreen, ...
        'HandleVisibility', 'off');
end

% --- variables ------------------------------------------------------------
for i = 1:n
    v = names(i);
    p = L.pos(i,:);
    gone = any(eliminated == v);

    if v == elim
        face = cRed;  edge = cRed;  lw = 2.0; txt = 'w';
    elseif any(sep == v)
        face = cBlue; edge = cBlue; lw = 2.0; txt = 'w';
    elseif gone
        face = [1 1 1]; edge = cGhost; lw = 1.0; txt = cGhost;
    else
        face = [1 1 1]; edge = 'k'; lw = 1.0; txt = 'k';
    end

    marker = 'o';
    if L.isLandmark(i), marker = '^'; end     % beacons are not poses
    plot(ax, p(1), p(2), marker, 'MarkerSize', mkVar, ...
        'MarkerFaceColor', face, 'MarkerEdgeColor', edge, ...
        'LineWidth', lw, 'HandleVisibility', 'off');

    if doLabel
        text(ax, p(1), p(2), sprintf('$%s$', utils.mathName(v)), ...
            'Interpreter', 'latex', 'HorizontalAlignment', 'center', ...
            'VerticalAlignment', 'middle', ...
            'FontSize', max(7, round(0.62 * mkVar)), 'Color', txt);
    end
end

hold(ax, 'off');
axis(ax, 'equal');
xlim(ax, L.xlim);
ylim(ax, L.ylim);
utils.applyLatexToAxes(ax);
grid(ax, 'off');
ax.XTick = []; ax.YTick = [];

% --- title ----------------------------------------------------------------
if isempty(state)
    utils.setLatexTitle(ax, sprintf( ...
        "Factor graph $G_0$: $|\\Theta| = %d$, $|F| = %d$", n, numel(factors)));
else
    % Spacing macros such as \; and \quad are only valid INSIDE math mode in
    % MATLAB's LaTeX interpreter; outside it they raise "invalid interpreter
    % syntax" and the label silently fails to render. Ordinary spaces are
    % used between the math groups instead.
    % The terminal elimination has an EMPTY separator, and arrayfun over an
    % empty string array returns a double, which cellstr then refuses. The
    % empty case is the root marginal and deserves its own wording anyway.
    % Braces on every subscript. Without them \omega_13 renders as omega
    % sub-one followed by a literal 3, which is wrong and, worse, is wrong
    % only for the double-digit steps the grid world spends most of its time
    % in.
    if isempty(sep)
        sepStr = '\emptyset';
    else
        sepStr = sprintf('\\{%s\\}', strjoin(cellstr(utils.mathName(sep)), ','));
    end
    utils.setLatexTitle(ax, sprintf( ...
        "Step %d: eliminate $\\omega_{%d} = %s$, $S_{%d} = %s$, $|F_{%d}(\\omega_{%d})| = %d$", ...
        step, step, utils.mathName(elim), step, sepStr, ...
        step - 1, step, nnz(removedMask)));
end

info = struct('factors', factors, 'eliminated', eliminated, ...
              'separator', sep, 'layout', L, 'removed', removedMask);
end

% =========================================================================
function P = localPos(L, scope)
%LOCALPOS The layout positions of a factor's scope, in its own order.
%   Inputs   L the layout, SCOPE the variable names
%   Outputs  P, one row per name
%   Utility  draw a factor's edges without re-deriving the layout.
P = zeros(0, 2);
for i = 1:numel(scope)
    j = find(L.names == scope(i), 1);
    if ~isempty(j), P(end+1, :) = L.pos(j, :); end %#ok<AGROW>
end
end
