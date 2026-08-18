function info = plotMapStep(ax, caseData, results, k, opts)
%PLOTMAPSTEP The map at increment k, with one robot per method.
%
%   Inputs
%     AX             the axes to draw into
%     CASEDATA       the case, carrying the map and the increments
%     RESULTS        the method results; may be empty, see below
%     K              which increment                          default Inf
%     ShowExplored   shade the cells sensed so far            default true
%     ShowRays       draw the range readings at K             default true
%     ShowSamples    scatter posterior samples                default true
%     ShowTruth      draw the ground-truth path and robot     default true
%     MaxSamples     samples scattered per variable            default 150
%
%   Outputs
%     INFO           the increment drawn, which methods got an avatar, and how
%                    many observations that increment carried
%
%   Utility
%     Draw the map pane of app specification sections 6 and 15: blocks, start
%     and goal, the explored grid, the beacons, the ground-truth path, the
%     range rays available at increment K, and a robot avatar for every method
%     that has a posterior, each in its method colour.
%
%   THREE ROBOTS, ONE MAP. The methods are compared by driving them over the
%   same data and drawing where each of them thinks it is, side by side, at
%   the same increment. Where they agree the avatars overlap and the story is
%   dull; where they disagree the picture says immediately which one drifted
%   and in which direction, which no table of RMSE values does.
%
%   The ground truth is drawn as an outline rather than a filled body, so it
%   reads as a reference and never competes with the three estimates.
%
%   RESULTS may be empty, in which case only the world is drawn. That is the
%   state the Case Study tab is in before anything has been run, and it has
%   to look deliberate rather than broken.
%
arguments
    ax (1,1) matlab.graphics.axis.Axes
    caseData (1,1) struct
    results struct = struct([])
    k (1,1) double = Inf
    opts.ShowExplored (1,1) logical = true
    opts.ShowRays (1,1) logical = true
    opts.ShowSamples (1,1) logical = true
    opts.ShowTruth (1,1) logical = true
    opts.MaxSamples (1,1) double = 150
end

cla(ax, 'reset');
hold(ax, 'on');

if ~isfield(caseData, 'map')
    text(ax, 0.5, 0.5, 'this case has no map', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Interpreter', 'latex');
    utils.applyLatexToAxes(ax);
    info = struct('drawn', false);
    return
end

map = caseData.map;
poses = caseData.mission.truePoses;
nPose = size(poses, 1);
k = max(1, min(nPose, floor(k)));

% --- explored grid --------------------------------------------------------
% Drawn first and faintly: it is context, not data. Free cells the robot has
% sensed are light; everything else stays white, so the shadows the blocks
% cast are visible as unexplored wedges.
if opts.ShowExplored && isfield(map, 'explored')
    ex = double(map.explored(:,:,k));
    im = imagesc(ax, map.gridX, map.gridY, ex.');
    im.AlphaData = 0.22 * (ex.');
    colormap(ax, [1 1 1; 0.35 0.55 0.75]);
    clim(ax, [0 1]);
end

% --- blocks ---------------------------------------------------------------
for b = 1:size(map.blocks, 1)
    rectangle(ax, 'Position', map.blocks(b,:), ...
        'FaceColor', [0.30 0.30 0.34], 'EdgeColor', [0.15 0.15 0.18], ...
        'LineWidth', 1.0);
end

% --- beacons --------------------------------------------------------------
lm = caseData.landmarks.truePositions;
plot(ax, lm(:,1), lm(:,2), 'p', 'MarkerSize', 11, ...
    'MarkerFaceColor', [0.95 0.75 0.10], 'MarkerEdgeColor', [0.45 0.35 0.05], ...
    'LineWidth', 0.8);

% --- ground truth ---------------------------------------------------------
if opts.ShowTruth
    plot(ax, poses(1:k,1), poses(1:k,2), '-', 'Color', [0.2 0.2 0.2 0.55], ...
        'LineWidth', 1.4);
    plot(ax, poses(1,1), poses(1,2), 'o', 'MarkerSize', 8, ...
        'MarkerFaceColor', [0.20 0.70 0.30], 'MarkerEdgeColor', 'k');
    plot(ax, caseData.mission.goal(1), caseData.mission.goal(2), 's', ...
        'MarkerSize', 8, 'MarkerFaceColor', [0.85 0.25 0.25], 'MarkerEdgeColor', 'k');
end

% --- range readings available at k ---------------------------------------
% A blocked reading is not drawn at all, because it does not exist: what the
% shadows in the explored grid already show is why.
if opts.ShowRays && isfield(caseData, 'increments')
    obs = caseData.increments(k).observations;
    for o = obs
        target = lm(o.landmark, :);
        plot(ax, [poses(k,1) target(1)], [poses(k,2) target(2)], '-', ...
            'Color', [0.95 0.75 0.10 0.75], 'LineWidth', 1.0);

        % The measured range as an arc: this is the annulus the factor puts
        % the beacon on, and it is the shape the whole comparison is about.
        th = linspace(0, 2*pi, 120);
        plot(ax, poses(k,1) + o.range*cos(th), poses(k,2) + o.range*sin(th), ...
            ':', 'Color', [0.95 0.75 0.10 0.35], 'LineWidth', 0.7);

        if ~isempty(o.ambiguousWith)
            % Ambiguous association: the same reading could belong to
            % another beacon, and the dashed line names the alternative.
            alt = lm(o.ambiguousWith, :);
            plot(ax, [poses(k,1) alt(1)], [poses(k,2) alt(2)], '--', ...
                'Color', [0.80 0.20 0.60 0.75], 'LineWidth', 1.0);
        end
    end
end

% --- one robot per method -------------------------------------------------
drawn = strings(1, 0);
for i = 1:numel(results)
    r = results(i);
    if ~isfield(r, 'status') || r.status ~= "ok", continue, end
    if ~isfield(r, 'map') || ~isfield(r.map, 'poseMean'), continue, end

    colour = viz.methodColors(string(r.methodName));
    pm = r.map.poseMean;
    kk = min(k, size(pm, 1));

    plot(ax, pm(1:kk,1), pm(1:kk,2), '-', 'Color', [colour 0.9], 'LineWidth', 1.6);

    if opts.ShowSamples && isfield(r.map, 'poseSamples') ...
            && numel(r.map.poseSamples) >= kk && ~isempty(r.map.poseSamples{kk})
        P = r.map.poseSamples{kk};
        if size(P, 1) > opts.MaxSamples
            P = P(randperm(size(P,1), opts.MaxSamples), :);
        end
        scatter(ax, P(:,1), P(:,2), 6, colour, 'filled', ...
            'MarkerFaceAlpha', 0.22, 'MarkerEdgeColor', 'none');
    end

    heading = localHeadingAt(pm, kk);
    viz.robotAvatar(ax, pm(kk,:), heading, colour, ...
        'Scale', 0.42, 'Label', localShortName(r.methodName));
    drawn(end+1) = string(r.methodName); %#ok<AGROW>
end

% --- the true robot, last, as an outline ---------------------------------
if opts.ShowTruth
    viz.robotAvatar(ax, poses(k,:), caseData.mission.headings(k), [0.15 0.15 0.15], ...
        'Scale', 0.52, 'Ghost', true, 'LineWidth', 1.4, ...
        'SensorRange', caseData.mission.sensorRange);
end

% --- frame ----------------------------------------------------------------
axis(ax, 'equal');
xlim(ax, map.bounds(1:2));
ylim(ax, map.bounds(3:4));
hold(ax, 'off');

utils.applyLatexToAxes(ax);
utils.setLatexTitle(ax, sprintf('Map at increment $k = %d$ of $%d$', k, nPose));
utils.setLatexXY(ax, '$x$ [m]', '$y$ [m]');

info = struct('drawn', true, 'increment', k, 'methods', drawn, ...
              'numObservations', numel(caseData.increments(k).observations));
end

% =========================================================================
function h = localHeadingAt(path, k)
%LOCALHEADINGAT Which way the robot faces at increment k, from the path.
%   Inputs   PATH the ground-truth positions, K the increment
%   Outputs  H, the heading in radians
%   Utility  the avatar needs a heading and the case carries only positions,
%           so it is taken from the direction of travel.
%
%   The state carries no orientation: these are position-only variables, and
%   inventing a heading variable to draw an arrow would be a state the
%   inference never estimated. The direction of travel is a property of the
%   estimated path, so it is taken from there and is honest about what it is.
if k > 1
    d = path(k,:) - path(k-1,:);
elseif size(path, 1) > 1
    d = path(2,:) - path(1,:);
else
    d = [1 0];
end
if all(d == 0), d = [1 0]; end
h = atan2(d(2), d(1));
end

% =========================================================================
function s = localShortName(name)
%LOCALSHORTNAME A method name short enough to sit beside an avatar.
%   Inputs   NAME, the method name
%   Outputs  S, a two- or three-character label
%   Utility  three labels on one map at overlapping positions; the full names
%           would cover the thing they label.
switch string(name)
    case "Slices",          s = "S";
    case "NF-iSAM",         s = "N";
    case "Smoothed Slices", s = "RCS";
    otherwise,              s = extractBefore(string(name) + " ", 2);
end
end
