function cmap = surfaceColormap(n)
%SURFACECOLORMAP Perceptually ordered map for nonnegative surfaces.
%
%   Inputs
%     N      how many rows                                   default 256
%
%   Outputs
%     CMAP   the colormap, N-by-3
%
%   Utility
%     A single-hue ramp from near-white to deep blue. Sequential rather than
%     diverging because R_r is nonnegative, and monotone in lightness so the
%     figure survives greyscale printing.

arguments
    n (1,1) double {mustBeInteger, mustBePositive} = 256
end

anchors = [ ...
    0.988 0.992 1.000; ...
    0.855 0.902 0.949; ...
    0.647 0.776 0.886; ...
    0.420 0.624 0.808; ...
    0.212 0.451 0.706; ...
    0.098 0.290 0.553; ...
    0.031 0.153 0.353];

x = linspace(0, 1, size(anchors, 1));
q = linspace(0, 1, n);
cmap = [interp1(x, anchors(:,1), q).', ...
        interp1(x, anchors(:,2), q).', ...
        interp1(x, anchors(:,3), q).'];
end
