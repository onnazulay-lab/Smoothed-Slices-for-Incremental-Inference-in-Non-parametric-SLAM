function route = lemma1Sampler(omega, removedFactors)
%LEMMA1SAMPLER Algorithm S2a: choose the sampling factor f' for omega.
%
%   Inputs
%     OMEGA           the variable about to be eliminated
%     REMOVEDFACTORS  F_{j-1}(omega), the factors that leave with it
%
%   Outputs
%     ROUTE  kind         "unary" | "lemma1"
%            factor       the sampling factor f' (core.Factor)
%            approximate  the approximate factor carrying the slices
%                         (lemma1 only)
%            outerVar     the already-sampled variable indexing those slices
%            others       the removed factors that stay in the product
%
%   Utility
%     Choose the sampling route of the Slices spec section 5:
%
%       1. If a unary factor f(omega) is present, use it.
%       2. Otherwise find a previously generated approximate factor whose
%          slices make OMEGA conditionally sampleable, i.e. a factor built by
%          eliminating a neighbour of OMEGA. This is the Lemma 1 guarantee.
%       3. If neither exists, the elimination order is invalid.
%
%     The route is DESCRIBED and no sampling is performed, so the Process
%     Explorer can display it and the estimators can branch on it.

arguments
    omega (1,1) string
    removedFactors (1,:) core.Factor
end

% --- 1. Unary factor on omega --------------------------------------------
isUnary = arrayfun(@(f) numel(f.Scope) == 1 && f.Scope == omega, removedFactors);
if any(isUnary)
    idx = find(isUnary, 1);
    route = struct( ...
        'kind',        "unary", ...
        'factor',      removedFactors(idx), ...
        'approximate', [], ...
        'outerVar',    omega, ...
        'others',      removedFactors(setdiff(1:numel(removedFactors), idx)));
    return
end

% --- 2. Structural route through a generated approximate factor ----------
for i = 1:numel(removedFactors)
    f = removedFactors(i);
    if f.Kind ~= "approximate" || ~isfield(f.Meta, 'approximateFactor')
        continue
    end
    af = f.Meta.approximateFactor;
    if af.canSampleSlices(omega)
        route = struct( ...
            'kind',        "lemma1", ...
            'factor',      af.findSliceSampler(omega), ...
            'approximate', af, ...
            'outerVar',    af.EliminatedVar, ...
            'others',      removedFactors(setdiff(1:numel(removedFactors), i)));
        return
    end
end

% --- 3. No route ----------------------------------------------------------
error('methods:slices:eliminationOrderError', ...
    ['Variable %s has no unary factor and no generated factor whose slices ' ...
     'make it sampleable. The elimination order violates the Lemma 1 ' ...
     'condition (Slices spec, Algorithm S2a).'], omega);
end
