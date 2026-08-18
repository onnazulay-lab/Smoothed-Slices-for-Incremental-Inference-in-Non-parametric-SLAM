function v = evalProduct(factors, assignment)
%EVALPRODUCT Product of factors at N paired assignments.
%
%   Inputs
%     FACTORS     core.Factor array; the product is over all of them
%     ASSIGNMENT  struct whose every field is N-by-d: N points down the rows,
%                 d coordinates across the columns, per core.Variable
%
%   Outputs
%     V           N-by-1 nonnegative column
%
%   Utility
%     Evaluate a factor product at paired points, in any dimension.
%
%   This is the dimension-agnostic replacement for the implicit-expansion trick
%   used in iteration 1. Implicit expansion made the 1-D slice matrix free, but
%   it silently conflates "coordinate" with "query point" the moment a variable
%   stops being scalar, so a caller wanting a grid now builds it explicitly
%   through core.evalGrid and a caller wanting paired values comes here.
%
%   Fields not in a factor's scope are ignored, which is what lets one
%   assignment be handed to every factor of a product.
%
%   See also core.evalGrid, core.assignmentLength.

arguments
    factors (1,:)
    assignment (1,1) struct
end

n = core.assignmentLength(assignment);
v = ones(n, 1);
for i = 1:numel(factors)
    fi = reshape(factors(i).evaluate(assignment), [], 1);
    if isscalar(fi)
        fi = repmat(fi, n, 1);
    elseif numel(fi) ~= n
        error('core:evalProduct:badFactorShape', ...
            ['Factor %s returned %d value(s) for %d assignment(s). A factor ' ...
             'must return one nonnegative value per row of the assignment.'], ...
            factors(i).Name, numel(fi), n);
    end
    v = v .* fi;
end
end
