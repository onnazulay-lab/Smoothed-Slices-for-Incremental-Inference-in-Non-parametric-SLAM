function D = unpackSamples(X, names, widths)
%UNPACKSAMPLES Split a sample matrix back into a per-variable dictionary.
%
%   Inputs
%     X       the sample matrix, one row per sample
%     NAMES   the variables, in the matrix's own column order
%     WIDTHS  how many columns each one occupies
%
%   Outputs
%     D       one field per variable, the shape Algorithm N1 produces
%
%   Utility
%     Invert PACKSAMPLES: cut the columns at the block boundaries and return
%     them under the variable names.
%
%   Posterior samples leave the flow as a matrix and have to go back into the
%   dictionary the rest of the method speaks, both for the root-to-leaf pass
%   of Algorithm N3 -- where a parent's drawn frontals become a child's
%   separator values -- and for the results contract, which reports samples
%   per variable rather than per column.

arguments
    X (:,:) double
    names (1,:) string
    widths (1,:) double {mustBeInteger, mustBeNonnegative}
end

if numel(names) ~= numel(widths)
    error('methods:nfisam:unpackSamples:count', ...
        '%d name(s) against %d width(s).', numel(names), numel(widths));
end
if size(X, 2) ~= sum(widths)
    error('methods:nfisam:unpackSamples:width', ...
        ['The sample matrix has %d column(s) but the layout accounts for ' ...
         '%d. A layout that does not match its matrix would silently ' ...
         'rename variables.'], size(X, 2), sum(widths));
end

D = struct();
at = 0;
for i = 1:numel(names)
    D.(matlab.lang.makeValidName(names(i))) = X(:, at + (1:widths(i)));
    at = at + widths(i);
end
end
