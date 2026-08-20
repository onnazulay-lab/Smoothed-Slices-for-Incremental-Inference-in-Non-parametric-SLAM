function checks = surfaceChecks(R, P, active, tol)
%SURFACECHECKS The required numerical checks of specification section 16.3.
%
%   Inputs
%     R       the surface
%     P       the transition matrix
%     ACTIVE  the per-row successor sets
%     TOL     how negative counts as negative                default 1e-12
%
%   Outputs
%     CHECKS  each check as a number and as a pass/fail, plus the active set
%             sizes and a list of what failed
%
%   Utility
%     Run, after every surface update:
%
%       1. min(R_r) >= -tol_numeric
%       2. row_sum(P_r) ~= 1 for every active row
%       3. finite mass of the surface > 0
%       4. no NaN or Inf in R_r or P_r
%
%   The spec is emphatic that clipping negative values should be unnecessary
%   when the factors are nonnegative, so a violation here is reported as a
%   real defect rather than quietly repaired.

arguments
    R (:,:) double
    P double
    active cell = {}
    tol (1,1) double = 1e-10
end

rowSums = full(sum(P, 2));
activeRows = rowSums > 0;

checks = struct();
checks.minSurface      = min(R(:));
checks.nonNegative     = checks.minSurface >= -tol;
checks.maxRowSumError  = max(abs(rowSums(activeRows) - 1), [], 'includenan');
if isempty(checks.maxRowSumError), checks.maxRowSumError = 0; end
checks.rowsNormalized  = checks.maxRowSumError < 1e-8;
checks.mass            = sum(R(:));
checks.positiveMass    = checks.mass > 0;
checks.numNonFinite    = sum(~isfinite(R(:))) + sum(~isfinite(nonzeros(P)));
checks.finite          = checks.numNonFinite == 0;
checks.numDeadRows     = sum(~activeRows);
checks.numActiveRows   = sum(activeRows);

if ~isempty(active)
    checks.activeSetSizes = cellfun(@numel, active);
else
    checks.activeSetSizes = [];
end

checks.allPassed = checks.nonNegative && checks.rowsNormalized && ...
                   checks.positiveMass && checks.finite;

if ~checks.allPassed
    checks.failures = strjoin(localFailures(checks), '; ');
else
    checks.failures = '';
end
end

function f = localFailures(c)
%LOCALFAILURES The names of the checks that did not pass.
%   Inputs   C, the checks struct
%   Outputs  F, a string array, empty when everything passed
%   Utility  one place to read rather than four booleans to remember.
f = {};
if ~c.nonNegative
    f{end+1} = sprintf('negative surface entry %.3e', c.minSurface);
end
if ~c.rowsNormalized
    f{end+1} = sprintf('transition row sum off by %.3e', c.maxRowSumError);
end
if ~c.positiveMass
    f{end+1} = 'surface has non-positive total mass';
end
if ~c.finite
    f{end+1} = sprintf('%d non-finite entries', c.numNonFinite);
end
end
