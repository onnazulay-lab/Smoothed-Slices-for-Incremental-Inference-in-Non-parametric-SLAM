function n = assignmentLength(assignment)
%ASSIGNMENTLENGTH Number of query points N in an assignment struct.
%
%   Inputs
%     ASSIGNMENT  struct with one field per variable, each N-by-d
%
%   Outputs
%     N           the shared row count; 1 for an empty struct
%
%   Utility
%     Establish how many points a factor is about to be evaluated at, and
%     refuse an assignment whose fields disagree.
%
%   Singleton rows are allowed and do not set N, so a fixed value can be paired
%   against a varying one without the caller replicating it first. A ragged
%   assignment is an error rather than a broadcast, because silently expanding
%   it would evaluate a factor at points the caller never asked for.

arguments
    assignment (1,1) struct
end

f = fieldnames(assignment);
n = 1;
for i = 1:numel(f)
    ni = size(assignment.(f{i}), 1);
    if ni == 1, continue, end
    if n == 1
        n = ni;
    elseif ni ~= n
        error('core:assignmentLength:ragged', ...
            ['Assignment field %s has %d row(s) but %d were already ' ...
             'established. Pair the values before evaluating, or use ' ...
             'core.evalGrid to form the outer product explicitly.'], ...
            f{i}, ni, n);
    end
end
end
