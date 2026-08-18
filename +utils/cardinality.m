function out = cardinality(symbol, value, mode)
%CARDINALITY Format a finite-support cardinality in the mandated notation.
%
%   Inputs
%     SYMBOL  the space letter, e.g. "\mathcal{X}_r"
%     VALUE   the cardinality
%     MODE    "latex" (default) or "plain", for logs and table headers where
%             LaTeX must not be used
%
%   Outputs
%     OUT     e.g. "$|\mathcal{X}_r| = 150$", or "|X_r| = 150" in plain mode
%
%   Utility
%     Show every finite space as |space letter|, in the one format sections 9
%     and 16 require.
%
%   Specification sections 9 and 16 require every finite space to be shown
%   as |space letter| and rendered in blue; use utils.cardinalityColor for
%   the colour so the two never drift apart.

arguments
    symbol (1,1) string
    value  (1,1) double
    mode   (1,1) string {mustBeMember(mode, ["latex", "plain"])} = "latex"
end

if mode == "latex"
    out = sprintf('$|%s| = %d$', symbol, round(value));
else
    plain = regexprep(symbol, '\\mathcal\{(\w)\}', '$1');
    plain = regexprep(plain, '\\(\w+)', '$1');
    plain = erase(plain, ["{", "}"]);
    out = sprintf('|%s| = %d', plain, round(value));
end
end
