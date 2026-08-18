function lbl = latexLabel(parent, txt, layout, opts)
%LATEXLABEL Create a uilabel that renders its text as LaTeX.
%
%   Inputs
%     PARENT     the container
%     TXT        the label text, containing $...$ math
%     LAYOUT     struct with Row and Column, to place it in a grid layout
%     FontSize   point size                                    default 12
%     FontColor  text colour; use utils.cardinalityColor for |X| notation
%     Alignment  'left' (default), 'center' or 'right'
%
%   Outputs
%     LBL        the label handle
%
%   Utility
%     Provide the LaTeX-capable component specification section 4 requires
%     every mathematical string in the UI to be rendered through.
%
%   Specification section 4 requires every mathematical string in the UI to
%   be rendered through a LaTeX-capable component; this is that component.

arguments
    parent
    txt (1,1) string
    layout = []
    opts.FontSize (1,1) double = 12
    opts.FontColor = [0 0 0]
    opts.Alignment (1,1) string = "left"
end

lbl = uilabel(parent);
lbl.Text            = char(txt);
lbl.Interpreter     = 'latex';
lbl.WordWrap        = 'on';
lbl.FontSize        = opts.FontSize;
lbl.FontColor       = opts.FontColor;
lbl.HorizontalAlignment = char(opts.Alignment);

if ~isempty(layout)
    if isfield(layout, 'Row'),    lbl.Layout.Row    = layout.Row;    end
    if isfield(layout, 'Column'), lbl.Layout.Column = layout.Column; end
end
end
