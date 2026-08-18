function applyLatexToAxes(ax)
%APPLYLATEXTOAXES Apply the mandatory LaTeX and paper styling to axes.
%
%   Inputs
%     AX  one axes or an array of them
%
%   Outputs
%     none
%
%   Utility
%     Set the tick interpreter, font and grid required by specification
%     section 4, in one call per panel.

arguments
    ax matlab.graphics.axis.Axes {mustBeNonempty}
end

for k = 1:numel(ax)
    a = ax(k);
    a.TickLabelInterpreter = 'latex';
    a.FontName  = 'Times New Roman';
    a.FontSize  = 11;
    a.LineWidth = 1.0;
    grid(a, 'on');
    box(a, 'on');
    a.GridAlpha = 0.15;
end
end
