function out = harmonizeResults(results)
%HARMONIZERESULTS Make heterogeneous method results concatenable.
%
%   Inputs
%     RESULTS  a cell array of result structs
%
%   Outputs
%     OUT      a struct array whose elements all carry the union of the
%              fields, missing entries filled with []
%
%   Utility
%     Let results that legitimately differ be concatenated.
%
%   This is needed because the methods legitimately differ: Smoothed Slices
%   carries a provenance block marking it as our proposed extension, and the
%   NF-iSAM stub omits fields it cannot yet populate. MATLAB refuses to
%   concatenate such structs. Padding here, rather than forcing every method
%   to declare every field, keeps the unified contract of specification
%   section 8 as a minimum rather than a straitjacket.

arguments
    results cell
end

if isempty(results)
    out = struct([]);
    return
end

allFields = string.empty(1,0);
for i = 1:numel(results)
    allFields = union(allFields, string(fieldnames(results{i})), 'stable');
end

% union returns a column when either input is one, and `for f = column`
% iterates exactly once over the whole column rather than element by element.
allFields = reshape(allFields, 1, []);

padded = cell(size(results));
for i = 1:numel(results)
    r = results{i};
    for f = allFields
        if ~isfield(r, f)
            r.(f) = [];
        end
    end
    padded{i} = orderfields(r, cellstr(allFields));
end

out = [padded{:}];
end
