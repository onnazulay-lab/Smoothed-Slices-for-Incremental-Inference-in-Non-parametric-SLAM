function setLatexXY(ax, xstr, ystr, zstr)
%SETLATEXXY Set axis labels through the LaTeX interpreter.
%
%   Inputs
%     AX          the axes
%     XSTR, YSTR  the x and y labels
%     ZSTR        the z label; omit or pass "" to skip it
%
%   Outputs
%     none
%
%   Utility
%     Label axes through the LaTeX interpreter everywhere, per specification
%     section 4.

arguments
    ax   (1,1) matlab.graphics.axis.Axes
    xstr (1,1) string
    ystr (1,1) string
    zstr (1,1) string = ""
end

xlabel(ax, char(xstr), 'Interpreter', 'latex', 'FontSize', 11);
ylabel(ax, char(ystr), 'Interpreter', 'latex', 'FontSize', 11);
if strlength(zstr) > 0
    zlabel(ax, char(zstr), 'Interpreter', 'latex', 'FontSize', 11);
end
end
