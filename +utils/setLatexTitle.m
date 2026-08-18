function h = setLatexTitle(ax, str)
%SETLATEXTITLE Set an axes title through the LaTeX interpreter.
%
%   Inputs
%     AX   the axes
%     STR  the title; should contain $...$ math
%
%   Outputs
%     H    the title handle
%
%   Utility
%     The only sanctioned way to title an axes in this app, per specification
%     section 4, so no panel ends up with a default-interpreter title.

arguments
    ax (1,1) matlab.graphics.axis.Axes
    str (1,1) string
end

h = title(ax, char(str), 'Interpreter', 'latex', 'FontSize', 12);
end
