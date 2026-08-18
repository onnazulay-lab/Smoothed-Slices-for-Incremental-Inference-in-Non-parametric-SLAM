function info = plotPlazaContext(ax, caseData, results, opts)
%PLOTPLAZACONTEXT The solved window, drawn inside the run it was cut from.
%
%   Inputs
%     AX                 the axes to draw into
%     CASEDATA           the window, carrying the whole run as context
%     RESULTS            the method results; may be empty
%     ShowDeadReckoning  the odometry chain the window carries   default true
%     ShowEstimates      one marker per method per pose          default true
%     ShowLandmarkCloud  posterior samples per landmark          default true
%     MaxSamples         posterior samples scattered per pose     default 120
%
%   Outputs
%     INFO               which methods were drawn and how many samples were
%                        scattered
%
%   Utility
%     Draw the whole Plaza trajectory, all four surveyed nodes, and then the
%     window the methods actually solved, on top.
%
%   THIS FIGURE EXISTS TO PREVENT A SPECIFIC MISREADING. Every other Plaza
%   plot in the app shows the window: eight poses and the two landmarks they
%   range, a few metres of a 1400 m run. Shown alone it looks like a
%   trajectory estimate,
%   and next to the papers' figures it invites the conclusion that this is
%   the same experiment with better numbers. It is not. The papers solve the
%   sequence; this engine holds ten to thirteen variables depending on the
%   problem, so what is solved
%   here is a window and the rest of the run is context. Drawing the two
%   together, at the same scale, in one frame, is the honest way to say
%   that -- and it costs one figure.
%
%   The surveyed nodes the window never ranges are drawn too, hollow. They
%   are the difference between the variables this window holds and the ones
%   it would hold if the robot had heard every radio -- which is the clearest
%   statement the figure can make that the count is a fact about the route
%   rather than a setting.
%
%   THE LANDMARK CLOUD IS DRAWN, NOT JUST ITS MEAN, and on this case that is
%   not a stylistic choice. Ranges from a short pose chain fix a landmark
%   only up to reflection in that chain, both modes carry roughly half the
%   mass, and the mean falls between them -- on the trajectory, where no mass
%   is. Measured on the default window, the true position explains the
%   readings to 0.51 m and the mean explains them 15.94 m worse. A figure
%   showing only means would show two landmark markers sitting on the robot's
%   path and would look like a bug rather than the bimodality it is.
%
arguments
    ax (1,1) matlab.graphics.axis.Axes
    caseData (1,1) struct
    results struct = struct([])
    opts.ShowDeadReckoning (1,1) logical = true
    opts.ShowEstimates (1,1) logical = true
    opts.ShowLandmarkCloud (1,1) logical = true
    opts.MaxSamples (1,1) double = 120
end

cla(ax, 'reset');
hold(ax, 'on');

if ~isfield(caseData, 'plaza')
    text(ax, 0.5, 0.5, 'not a Plaza case', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    info = struct('drawn', false);
    return
end

P = caseData.plaza;

% --- the whole run, behind everything ------------------------------------
plot(ax, P.fullPath(:,1), P.fullPath(:,2), '-', ...
    'Color', [0.75 0.78 0.82], 'LineWidth', 1.0, ...
    'DisplayName', 'true path, whole run');

% --- the surveyed nodes ---------------------------------------------------
% Filled if this window ranges them, hollow if not. The hollow ones are the
% dimensions the range limit bought back.
used = ismember(P.allLandmarkIds, caseData.landmarks.ids);
for m = find(~used)
    plot(ax, P.allLandmarks(m,1), P.allLandmarks(m,2), '^', ...
        'MarkerSize', 9, 'MarkerFaceColor', 'none', ...
        'MarkerEdgeColor', [0.45 0.45 0.50], 'LineWidth', 1.2, ...
        'DisplayName', sprintf('node %d, outside the window', P.allLandmarkIds(m)));
end
% The ranged ones are named by BOTH: the variable this window calls them and
% the surveyed node they are. The graph numbers its landmarks l1..lL within
% the window, exactly as it numbers its poses x1..xK, so this legend is the
% one place the two vocabularies are tied together -- without it, "l1" and
% "node 0" are the same physical radio with no visible connection.
for m = find(used)
    vi = find(caseData.landmarks.ids == P.allLandmarkIds(m), 1);
    plot(ax, P.allLandmarks(m,1), P.allLandmarks(m,2), '^', ...
        'MarkerSize', 10, 'MarkerFaceColor', [0.95 0.75 0.20], ...
        'MarkerEdgeColor', 'k', 'LineWidth', 1.0, ...
        'DisplayName', sprintf('%s = node %d, ranged', ...
            caseData.landmarks.names(vi), P.allLandmarkIds(m)));
end

% --- the window's truth ---------------------------------------------------
gt = caseData.groundTruth.poses;
plot(ax, gt(:,1), gt(:,2), '-o', 'Color', [0.10 0.10 0.10], ...
    'LineWidth', 1.8, 'MarkerSize', 5, 'MarkerFaceColor', 'w', ...
    'DisplayName', 'window, true');

if opts.ShowDeadReckoning
    dr = P.deadReckoned;
    plot(ax, dr(:,1), dr(:,2), '--s', 'Color', [0.55 0.35 0.75], ...
        'LineWidth', 1.3, 'MarkerSize', 4, ...
        'DisplayName', 'window, dead reckoning');
end

% --- the estimates --------------------------------------------------------
info = struct('drawn', true, 'methods', strings(1,0), 'numSamples', 0);

if opts.ShowEstimates && ~isempty(results) && numel(fieldnames(results)) > 0
    poseNames = caseData.groundTruth.poseNames;
    for i = 1:numel(results)
        r = results(i);
        col = viz.methodColors(r.methodName);
        xy = localPoseMeans(r, poseNames);
        if isempty(xy), continue, end

        plot(ax, xy(:,1), xy(:,2), '-', 'Color', col, 'LineWidth', 1.4, ...
            'Marker', 'o', 'MarkerSize', 4, 'MarkerFaceColor', col, ...
            'DisplayName', char(r.methodName));
        info.methods(end+1) = string(r.methodName);

        % The landmark posterior, as a cloud. Drawn UNDER the pose track and
        % faint, because it is wide on purpose: two modes either side of the
        % path. Its mean is deliberately not marked -- it lies between the
        % modes and marking it would assert an estimate the data does not
        % support.
        if opts.ShowLandmarkCloud
            info.numSamples = info.numSamples + ...
                localScatterLandmarks(ax, r, col, opts.MaxSamples);
        end
    end
end

% --- frame ----------------------------------------------------------------
% Framed on the WINDOW, not on the run. The run is context and is allowed to
% leave the axes; a frame wide enough to hold 68 m of plaza would reduce the
% thing actually being estimated to a smudge.
pad = 12;
box = [min([gt(:,1); caseData.landmarks.truePositions(:,1)]) - pad, ...
       max([gt(:,1); caseData.landmarks.truePositions(:,1)]) + pad, ...
       min([gt(:,2); caseData.landmarks.truePositions(:,2)]) - pad, ...
       max([gt(:,2); caseData.landmarks.truePositions(:,2)]) + pad];
axis(ax, 'equal');
xlim(ax, box(1:2));
ylim(ax, box(3:4));
grid(ax, 'on');

xlabel(ax, '$x$ [m]');
ylabel(ax, '$y$ [m]');
title(ax, sprintf('%s: keyframes %d--%d of %d, %d of %d nodes ranged', ...
    P.dataset, P.windowKeyframes(1), P.windowKeyframes(end), ...
    size(P.keyframePath, 1), nnz(used), numel(P.allLandmarkIds)));
legend(ax, 'Location', 'bestoutside', 'Interpreter', 'latex', 'FontSize', 8);
utils.applyLatexToAxes(ax);
end

% =========================================================================
function n = localScatterLandmarks(ax, result, col, maxSamples)
%LOCALSCATTERLANDMARKS One method's landmark sample clouds.
%   Inputs   AX the axes, RESULT a method result, COL its colour, MAXSAMPLES
%           how many draws to scatter per landmark
%   Outputs  N, how many points were drawn
%   Utility  draw the cloud rather than its mean; on this case the mean falls
%           between two modes, where no mass is.
n = 0;
if ~isfield(result, 'map') || ~isstruct(result.map) ...
        || ~isfield(result.map, 'landmarkSamples')
    return
end

S = result.map.landmarkSamples;
if ~iscell(S), S = {S}; end

for i = 1:numel(S)
    X = S{i};
    if iscell(X), X = X{1}; end
    if isempty(X) || size(X, 2) < 2, continue, end

    % Thinned by a stride rather than at random: the figure must be the same
    % figure every time it is drawn, and a cloud is not made more honest by
    % being resampled on each repaint.
    if size(X, 1) > maxSamples
        X = X(round(linspace(1, size(X,1), maxSamples)), :);
    end

    h = scatter(ax, X(:,1), X(:,2), 6, col, 'filled', ...
        'MarkerFaceAlpha', 0.16, 'MarkerEdgeColor', 'none');
    if i == 1
        h.DisplayName = char(result.methodName + " landmark posterior");
    else
        h.Annotation.LegendInformation.IconDisplayStyle = 'off';
    end
    uistack(h, 'bottom');
    n = n + size(X, 1);
end
end

% =========================================================================
function xy = localPoseMeans(result, poseNames)
%LOCALPOSEMEANS One method's posterior mean position per pose.
%   Inputs   RESULT a method result, POSENAMES the poses in order
%   Outputs  XY, one row per pose, NaN where the method has no estimate
%   Utility  a pose the method did not hold leaves a gap in the line rather
%           than a segment to the origin.
xy = [];
if ~isfield(result, 'map') || ~isstruct(result.map) ...
        || ~isfield(result.map, 'poseMean')
    return
end
pm = result.map.poseMean;
if size(pm, 1) ~= numel(poseNames) || size(pm, 2) < 2
    return
end
xy = pm(:, 1:2);
end
