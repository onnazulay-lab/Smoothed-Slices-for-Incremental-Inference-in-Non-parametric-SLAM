function M = pairwiseFactorMatrix(f, fromVar, Xfrom, toVar, Xto)
%PAIRWISEFACTORMATRIX f evaluated on every (from, to) support pair.
%   M = PAIRWISEFACTORMATRIX(F, FROMVAR, XFROM, TOVAR, XTO) returns the
%   BFROM-by-BTO matrix M(a,b) = F(XFROM(a,:), XTO(b,:)).
%
%   Inputs
%     F        core.Factor whose scope covers FROMVAR and TOVAR
%     FROMVAR  name of the row variable
%     XFROM    BFROM-by-DFROM support, one point per row
%     TOVAR    name of the column variable
%     XTO      BTO-by-DTO support, one point per row
%
%   Outputs
%     M        BFROM-by-BTO, nonnegative
%
%   Utility
%     Form the g_r matrix of Eq. (47) for supports of ANY dimension, which the
%     scalar path cannot do.
%
%   WHY THIS EXISTS RATHER THAN THE ONE-LINER IT REPLACES. The two-pose route
%   builds the same matrix as
%
%       g0.evaluate(struct(outerKey, xi0(:), omegaKey, reshape(X1, 1, [])))
%
%   which works only because both variables are SCALAR: a column against a row
%   broadcasts to the outer product of indices, and the factor's vectorized
%   evaluation sees it. With 2-D points a column of pairs and a row of pairs
%   have no such reading -- the second dimension already means "coordinate",
%   not "the other variable's index" -- so the pairs are enumerated explicitly
%   instead. That is the whole content of this function, and it is the reason
%   the surface recursion was scalar-only.
%
%   COST. The expansion materializes BFROM*BTO rows of DFROM+DTO columns and
%   evaluates F once on all of them. One vectorized call is the point: a loop
%   over rows would make the recursion's cost model, |X_r| |N_r| |S|, a claim
%   about MATLAB rather than about the method.
%
%   See also methods.smoothed.surfaceRecursionGeneral.

arguments
    f (1,1) core.Factor
    fromVar (1,1) string
    Xfrom (:,:) double
    toVar (1,1) string
    Xto (:,:) double
end

if ~f.involves(fromVar) || ~f.involves(toVar)
    error('methods:smoothed:pairFactorScope', ...
        'Factor %s has scope (%s) and does not cover both %s and %s.', ...
        f.Name, strjoin(cellstr(f.Scope), ","), fromVar, toVar);
end

nFrom = size(Xfrom, 1);
nTo   = size(Xto, 1);

% ndgrid rather than meshgrid: ia varies along the FIRST dimension, so the
% linear index of (a,b) is a + (b-1)*nFrom and the reshape below lands each
% value in the row and column it was built from. meshgrid would transpose it
% silently, which is a bug that looks like a plausible surface.
[ia, ib] = ndgrid(1:nFrom, 1:nTo);

a = struct();
a.(matlab.lang.makeValidName(fromVar)) = Xfrom(ia(:), :);
a.(matlab.lang.makeValidName(toVar))   = Xto(ib(:), :);

v = f.evaluate(a);
M = reshape(v, nFrom, nTo);
end
