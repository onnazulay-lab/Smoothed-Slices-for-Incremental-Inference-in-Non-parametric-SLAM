function rgb = methodColors(name)
%METHODCOLORS One colour per method, shared by every figure and the UI.
%
%   Inputs
%     NAME  a method name, or "reference"          default "reference"
%
%   Outputs
%     RGB   the colour, 1-by-3
%
%   Utility
%     Keep a method looking the same wherever it appears. The palette stays
%     distinguishable in greyscale and under the common forms of colour vision
%     deficiency, since these figures are headed for slides and a paper.

arguments
    name (1,1) string = "reference"
end

switch name
    case "Slices",          rgb = [0.00 0.45 0.70];   % blue
    case "NF-iSAM",         rgb = [0.84 0.37 0.00];   % vermilion
    case "Smoothed Slices", rgb = [0.00 0.62 0.45];   % bluish green
    case "reference",       rgb = [0.35 0.35 0.35];   % grey
    otherwise,              rgb = [0.50 0.50 0.50];
end
end
