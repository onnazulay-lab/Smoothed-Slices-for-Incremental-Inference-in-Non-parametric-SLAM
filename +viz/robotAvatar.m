function h = robotAvatar(ax, position, heading, colour, opts)
%ROBOTAVATAR Draw one robot on the map.
%
%   Inputs
%     AX           the axes to draw into
%     POSITION     1-by-2, where the robot is
%     HEADING      radians, which way it faces
%     COLOUR       1-by-3
%     Scale        body radius in map units                    default 0.45
%     SensorRange  radius of the sensor arc, 0 to omit         default 0
%     Alpha        face transparency                           default 0.85
%     LineWidth    outline width                               default 1.2
%     Label        short text drawn beside the robot           default ""
%     Ghost        true to draw an outline only, for the truth default false
%
%   Outputs
%     H            the graphics handles that were created
%
%   Utility
%     Draw one robot, readably, where three of them share a map.
%
%   The avatar is deliberately a FRAME rather than a dot. Three robots share
%   this map, one per method, and at any interesting increment two of them
%   are within centimetres of each other; a marker would simply overplot. A
%   body with a nose, a heading spoke and a sensor arc stays readable when
%   the estimates overlap, and it shows what the robot can see, which is the
%   thing the map is there to explain.
%
arguments
    ax (1,1) matlab.graphics.axis.Axes
    position (1,2) double
    heading (1,1) double
    colour (1,3) double
    opts.Scale (1,1) double {mustBePositive} = 0.45
    opts.SensorRange (1,1) double {mustBeNonnegative} = 0
    opts.Alpha (1,1) double = 0.85
    opts.LineWidth (1,1) double = 1.2
    opts.Label (1,1) string = ""
    opts.Ghost (1,1) logical = false
end

r = opts.Scale;
c = cos(heading); s = sin(heading);
R = [c -s; s c];

h = gobjects(0);

% --- sensor arc -----------------------------------------------------------
% Drawn first so the body sits on top of it.
if opts.SensorRange > 0
    th = linspace(0, 2*pi, 90);
    h(end+1) = plot(ax, position(1) + opts.SensorRange*cos(th), ...
                        position(2) + opts.SensorRange*sin(th), ...
                    ':', 'Color', [colour 0.45], 'LineWidth', 0.8);
end

% --- body -----------------------------------------------------------------
% A disc with a nose: the nose gives the heading unambiguously, which a
% symmetric shape cannot, and the disc keeps the footprint honest about the
% robot having extent.
th = linspace(-pi, pi, 40).';
body = [r*cos(th), r*sin(th)];
nose = [1.9*r 0; 0.75*r 0.62*r; 0.75*r -0.62*r];

body = body * R.' + position;
nose = nose * R.' + position;

if opts.Ghost
    h(end+1) = plot(ax, body([1:end 1],1), body([1:end 1],2), '-', ...
        'Color', colour, 'LineWidth', opts.LineWidth);
    h(end+1) = plot(ax, nose([1:end 1],1), nose([1:end 1],2), '-', ...
        'Color', colour, 'LineWidth', opts.LineWidth);
else
    h(end+1) = patch(ax, 'XData', body(:,1), 'YData', body(:,2), ...
        'FaceColor', colour, 'FaceAlpha', opts.Alpha, ...
        'EdgeColor', colour * 0.6, 'LineWidth', opts.LineWidth);
    h(end+1) = patch(ax, 'XData', nose(:,1), 'YData', nose(:,2), ...
        'FaceColor', colour, 'FaceAlpha', min(1, opts.Alpha + 0.15), ...
        'EdgeColor', colour * 0.6, 'LineWidth', opts.LineWidth);
end

% --- heading spoke --------------------------------------------------------
spoke = [0 0; 1.75*r 0] * R.' + position;
h(end+1) = plot(ax, spoke(:,1), spoke(:,2), '-', ...
    'Color', colour * 0.5, 'LineWidth', opts.LineWidth);

if strlength(opts.Label) > 0
    h(end+1) = text(ax, position(1) + 1.2*r, position(2) + 1.2*r, opts.Label, ...
        'Interpreter', 'latex', 'FontSize', 8, 'Color', colour * 0.7);
end
end
