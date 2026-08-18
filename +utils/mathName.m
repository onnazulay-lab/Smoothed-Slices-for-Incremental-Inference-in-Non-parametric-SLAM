function s = mathName(name)
%MATHNAME A variable name as a LaTeX math body, without the dollar signs.
%
%   Inputs
%     NAME  one or more variable names
%
%   Outputs
%     S     the subscripted names, as a STRING so arrayfun gets a uniform
%           result
%
%   Utility
%     Render x12 as x_{12} and l3 as l_{3}, in one place.
%
%   The same regular expression was inlined in seven files and had already
%   drifted: some copies anchored the trailing digits with $ and some did
%   not, so "x12" rendered as "x_{12}" in one panel and "x12" in another.
%   One function, one behaviour.
%
%   Returns a STRING. Callers that feed arrayfun get a uniform result, which
%   the char-returning version did not give them.

arguments
    name (1,:) string
end

s = regexprep(name, '^([a-zA-Z]+)(\d+)$', '$1_{$2}');
end
