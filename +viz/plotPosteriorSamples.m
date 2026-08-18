function plotPosteriorSamples(ax, results, varA, varB)
%PLOTPOSTERIORSAMPLES Joint posterior samples in two variables.
%
%   Inputs
%     AX       the axes to draw into
%     RESULTS  the method results
%     VARA     the first variable                             default "x1"
%     VARB     the second variable                            default "l1"
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Show that the backward traversal returns JOINT samples: if the pairing
%     were lost the cloud would be axis-aligned regardless of the factors, so
%     this panel doubles as a visual check on the traversal.
%
%   Two layouts, chosen by the dimension of the variables:
%
%     scalar   Scatter of (varA, varB). Two-pose range and Four Doors.
%
%     planar   Both variables are positions, so they cannot share a pair of
%              axes. Both clouds are drawn in the world plane and a thin
%              sample of the draws is joined pair to pair. Those segments are
%              the joint: draw the two clouds independently and the segments
%              become a uniform hairball, so the structure is still visible
%              and still falsifiable, just carried by the lines rather than
%              by the shape of a single cloud.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results (1,:) struct
    varA (1,1) string = "x1"
    varB (1,1) string = "l1"
end

cla(ax, 'reset');
hold(ax, 'on');

ka = matlab.lang.makeValidName(varA);
kb = matlab.lang.makeValidName(varB);

nLink = 60;                 % pairing segments per method
planar = false;
drew = false;

for i = 1:numel(results)
    r = results(i);
    if r.status ~= "ok", continue; end
    if ~isfield(r, 'posterior') || ~isfield(r.posterior, 'samples'), continue; end
    S = r.posterior.samples;
    if ~isfield(S, ka) || ~isfield(S, kb), continue; end

    A = S.(ka);
    B = S.(kb);
    if isempty(A) || isempty(B), continue; end
    col = viz.methodColors(r.methodName);
    drew = true;

    if size(A, 2) == 1 && size(B, 2) == 1
        scatter(ax, A, B, 8, 'MarkerEdgeColor', 'none', ...
            'MarkerFaceColor', col, 'MarkerFaceAlpha', 0.35, ...
            'DisplayName', char(r.methodName));
    else
        planar = true;
        A = A(:, 1:min(2, end));
        B = B(:, 1:min(2, end));
        if size(A,2) < 2 || size(B,2) < 2, continue; end

        scatter(ax, A(:,1), A(:,2), 8, 'MarkerEdgeColor', 'none', ...
            'MarkerFaceColor', col, 'MarkerFaceAlpha', 0.30, ...
            'DisplayName', char(r.methodName));
        scatter(ax, B(:,1), B(:,2), 8, 'o', 'MarkerEdgeColor', col, ...
            'MarkerFaceColor', 'none', 'MarkerEdgeAlpha', 0.30, ...
            'HandleVisibility', 'off');

        m = size(A, 1);
        pick = round(linspace(1, m, min(nLink, m)));
        plot(ax, [A(pick,1) B(pick,1)].', [A(pick,2) B(pick,2)].', '-', ...
            'Color', [col 0.18], 'LineWidth', 0.5, 'HandleVisibility', 'off');
    end
end

hold(ax, 'off');
utils.applyLatexToAxes(ax);
da = utils.mathName(varA);
db = utils.mathName(varB);

if ~drew
    text(ax, 0.5, 0.5, 'no joint samples for this pair', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.setLatexTitle(ax, sprintf("Joint posterior samples $(%s, %s)$", da, db));
    return
end

if planar
    axis(ax, 'equal');
    utils.setLatexTitle(ax, sprintf( ...
        "Joint samples: $%s$ filled, $%s$ open, pairs joined", da, db));
    utils.setLatexXY(ax, "$x$ [m]", "$y$ [m]");
else
    utils.setLatexTitle(ax, sprintf("Joint posterior samples $(%s, %s)$", da, db));
    utils.setLatexXY(ax, sprintf("$%s$", da), sprintf("$%s$", db));
end
legend(ax, 'Interpreter', 'latex', 'Location', 'best', 'Box', 'off');
end
