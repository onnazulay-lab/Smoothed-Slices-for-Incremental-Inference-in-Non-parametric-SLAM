function plotEngineHealth(ax, results)
%PLOTENGINEHEALTH Per-pose error next to the diagnostic that predicts it.
%
%   Inputs
%     AX       the axes to draw into
%     RESULTS  the method results
%
%   Outputs
%     none; draws into AX
%
%   Utility
%     Plot each method's per-pose position error against the true pose, on a
%     map case where no exact posterior exists.
%
%   The point of the panel is the pairing with the engine's own health
%   numbers, which are printed on it. On the grid world the error and the
%   nearest-support lookup distance move together: when the finite support
%   stops covering where the backward traversal goes, the estimate becomes
%   confidently wrong, and the lookup distance says so before the error
%   becomes obvious. A panel that showed only the error would invite the
%   reader to treat a bad run as noise.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    results struct
end

cla(ax, 'reset');
hold(ax, 'on');

notes = string.empty(1,0);
drew = false;

for i = 1:numel(results)
    r = results(i);
    if ~isfield(r, 'status') || r.status ~= "ok", continue, end
    if ~isfield(r, 'map') || ~isfield(r.map, 'poseMean'), continue, end
    if ~isfield(r, 'case'), continue, end

    colour = viz.methodColors(string(r.methodName));
    pm = r.map.poseMean;

    % The ground truth is not on the result, so the error is recomputed
    % here only if the metrics block already carries it; otherwise the
    % per-pose curve is skipped rather than invented.
    if isfield(r.metrics, 'poseErrors')
        e = r.metrics.poseErrors;
    else
        e = nan(size(pm,1), 1);
    end

    if all(isnan(e)), continue, end
    plot(ax, 1:numel(e), e, '-o', 'Color', colour, 'LineWidth', 1.4, ...
        'MarkerSize', 4, 'MarkerFaceColor', colour, ...
        'DisplayName', string(r.methodName));
    drew = true;

    % Each engine names its own health. The elimination methods have a finite
    % support and a nearest-neighbour lookup; NF-iSAM has neither, and
    % printing those two fields for it would put a NaN on the panel where a
    % diagnostic belongs. A method that supplies a SUMMARY says what its own
    % failure mode looks like instead.
    h = r.metrics.health;
    if isfield(h, 'summary') && strlength(string(h.summary)) > 0
        notes(end+1) = sprintf("%s: %s", string(r.methodName), string(h.summary)); %#ok<AGROW>
    else
        notes(end+1) = sprintf("%s: ESS$_{\\min}$ %.1f, lookup %.2f m", ...
            string(r.methodName), h.minEssSupport, h.lookupMean); %#ok<AGROW>
    end
end

if ~drew
    text(ax, 0.5, 0.5, 'per-pose errors are not recorded for this case', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
        'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    hold(ax, 'off');
    return
end

if ~isempty(notes)
    yl = ylim(ax);
    text(ax, 0.02, 0.96, strjoin(cellstr(notes), newline), ...
        'Units', 'normalized', 'VerticalAlignment', 'top', ...
        'Interpreter', 'latex', 'FontSize', 8);
    ylim(ax, [0 yl(2) * 1.25]);
end

legend(ax, 'Interpreter', 'latex', 'Location', 'southeast', 'FontSize', 8);
hold(ax, 'off');

utils.applyLatexToAxes(ax);
utils.setLatexTitle(ax, 'Position error per pose, with engine health');
utils.setLatexXY(ax, 'increment $k$', 'error [m]');
end
