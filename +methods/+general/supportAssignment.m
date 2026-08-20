function a = supportAssignment(vars, dims, S, a)
%SUPPORTASSIGNMENT Split joint support points back into per-variable columns.
%   A = SUPPORTASSIGNMENT(VARS, DIMS, S) returns an assignment struct whose
%   field for VARS(i) holds the DIMS(i) columns of S belonging to that
%   variable.
%
%   Inputs
%     VARS  1-by-K string array of variable names, in the order S was built
%     DIMS  1-by-K dimensions, so sum(DIMS) == size(S, 2)
%     S     N-by-sum(DIMS) joint points, one per row
%     A     an existing assignment struct to add the fields to  default struct()
%
%   Outputs
%     A     struct with one field per variable, each N-by-DIMS(i)
%
%   Utility
%     A joint separator support is stored as one wide matrix, but factors are
%     evaluated on a struct of per-variable values. This is the one place that
%     conversion happens, so the column order cannot drift between the code
%     that builds S and the code that reads it.
%
%   THE COLUMN ORDER IS THE CONTRACT. Getting it wrong swaps two variables'
%   coordinates and produces a factor value that is perfectly finite, smooth
%   and wrong, so the width is checked here rather than trusted.

arguments
    vars (1,:) string
    dims (1,:) double {mustBeInteger, mustBePositive}
    S (:,:) double
    a (1,1) struct = struct()
end

if numel(vars) ~= numel(dims)
    error('methods:general:assignmentCountMismatch', ...
        '%d variable(s) but %d dimension(s).', numel(vars), numel(dims));
end
if size(S, 2) ~= sum(dims)
    error('methods:general:assignmentWidthMismatch', ...
        ['The support is %d column(s) wide but the variables (%s) need %d. ' ...
         'A mismatch here silently reassigns coordinates between variables.'], ...
        size(S, 2), strjoin(cellstr(vars), ","), sum(dims));
end

col = 0;
for i = 1:numel(vars)
    a.(matlab.lang.makeValidName(vars(i))) = S(:, col + (1:dims(i)));
    col = col + dims(i);
end
end
