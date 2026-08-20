function [R0, info] = surfaceRecursionGeneral(path, part, X0, separator, sepDims, S, config)
%SURFACERECURSIONGENERAL The R_r recursion of Eqs. (44)-(50), for any H and d.
%   [R0, INFO] = SURFACERECURSIONGENERAL(PATH, PART, X0, SEPARATOR, SEPDIMS,
%   S, CONFIG) walks the tower of Eq. (36) from level H back to level 0 and
%   returns the surface R_0 on the outer support and the separator support.
%
%   Inputs
%     PATH       struct array from methods.smoothed.buildEliminationPath
%     PART       role partition from methods.smoothed.partitionPathFactors
%     X0         B_0-by-D_0 support of level 0, one point per row
%     SEPARATOR  1-by-K separator variable names, in the order S is built
%     SEPDIMS    1-by-K dimensions, sum(SEPDIMS) == size(S, 2)
%     S          R_s-by-sum(SEPDIMS) separator support, one point per row
%     CONFIG     method config; surfaceSupportSize, activeSetSize,
%                activeSetRule, surfaceMode, surfaceDiagnostics are read
%
%   Outputs
%     R0    B_0-by-R_s surface, the R_0(xi_0, s) that Eq. (41) averages
%     INFO  struct with per-step diagnostics, the supports, the cost model and
%           the measured cost
%
%   Utility
%     Compute the cached conditional smoothing surface for a real elimination
%     path, which is the object the whole proposed extension is about and which
%     until now existed only for the paper's two-pose example at H = 1 with
%     scalar variables.
%
%   WHAT THIS ADDS OVER evaluateSurfaceRecursion, which is the H = 1 scalar
%   case and stays where it is. Three things, and the third is the one that
%   makes the first two worth having:
%
%     ANY H.  The tower is walked, not unrolled. evaluateSurfaceRecursion
%             hard-codes R_1 = a_1 and one matrix product, which is Eq. (50)
%             at H = 1 and cannot express a deeper path.
%
%     ANY d.  Supports are B-by-d matrices and pairs are enumerated rather
%             than broadcast, so a planar SLAM variable works. The scalar route
%             relies on a column-against-row outer product that has no meaning
%             once the second dimension means "coordinate".
%
%     THE REAL A_r.  Eq. (47)'s multiplier is a rank-3 tensor over (row,
%             successor, separator point), and it has to be, because a fusion
%             factor may depend on the row variable, the column variable and
%             the separator at once -- odometry between two consecutively
%             eliminated poses is exactly that. The scalar route notes that
%             "a_0 == 1 for this path, so the tensor collapses to a per-row
%             scalar and never needs to be materialized", which is true of that
%             path and not of a path in general.
%
%   THE STEP CONVENTION, which is partitionPathFactors' and is restated here
%   because this is the code that has to obey it:
%
%     step r has xi_r on the ROWS and xi_{r+1} on the COLUMNS
%     it consumes the sampling factor g_r = PART.g{r+1}
%     and the fusion factors PART.a{r+1}
%     R_H = 1, the empty product; Eq. (38)'s a_H is absorbed into step H-1
%
%   so each removed factor is multiplied in exactly once, which is the property
%   partitionPathFactors refuses to return without.
%
%   Z_r CANCELS AND IS STILL WRITTEN OUT, following the scalar route's reading
%   of Eq. (47). Z_r multiplies here and divides inside P_r's row
%   normalization, since sum_b g_r(a,b) w_b approximates Z_r(xi_r^a). Keeping
%   both makes the estimator insensitive to an inaccurate Z_r rather than
%   dependent on it, and it keeps the code readable against the equation.
%
%   WHAT IS NOT CLAIMED. This computes the surface; it does not yet replace the
%   general engine's inner integral, which is a separate wiring question with
%   its own measurement. Nothing here asserts the recursion is cheaper than
%   what the engine does now -- INFO reports the cost so that comparison can be
%   made rather than assumed, and the spec's own honest claim boundary applies:
%   the smoothing property does not eliminate the integrals, it reorganizes
%   them.
%
%   See also methods.smoothed.buildEliminationPath,
%            methods.smoothed.partitionPathFactors,
%            methods.smoothed.buildPathSupport,
%            methods.smoothed.evaluateSurfaceRecursion.

arguments
    path (1,:) struct
    part (1,1) struct
    X0 (:,:) double
    separator (1,:) string
    sepDims (1,:) double {mustBeInteger, mustBePositive}
    S (:,:) double
    config (1,1) struct
end

t0 = tic;

if config.surfaceMode ~= "finite"
    error('methods:smoothed:modeNotImplemented', ...
        ['Surface mode "%s" is Mode B/C of specification section 11. Mode A ' ...
         '("finite") is what is implemented, and the spec requires it to be ' ...
         'validated first.'], config.surfaceMode);
end

H = numel(path) - 1;
if H < 1
    error('methods:smoothed:pathTooShort', ...
        ['A path of one level has no recursion to run: R_0 would be the ' ...
         'empty product. Eliminate it normally instead.']);
end
if numel(part.g) ~= H || numel(part.a) ~= H
    error('methods:smoothed:partitionShapeMismatch', ...
        ['The partition has %d sampling and %d fusion slot(s) but the path ' ...
         'has H = %d. They must come from the same path.'], ...
        numel(part.g), numel(part.a), H);
end

Rs = size(S, 1);

% --- Supports of every level above 0 --------------------------------------
% Level 0's support is given: it is the outer sample set the caller drew. Every
% deeper level is pooled from its own structural proposal, which is the
% Lemma 1 backbone the path was built along.
X = cell(1, H + 1);
X{1} = X0;
supportInfo = cell(1, H);
for j = 1:H
    [X{j+1}, supportInfo{j}] = methods.smoothed.buildPathSupport( ...
        part.g{j}, path(j).var, X{j}, path(j+1).var, config.surfaceSupportSize);
end

% --- R_H = 1 (see the step convention above) ------------------------------
R = ones(size(X{H+1}, 1), Rs);

steps = repmat(struct('step', 0, 'rowVar', "", 'colVar', "", ...
    'numRows', 0, 'numCols', 0, 'fusionFactors', 0, ...
    'fusionShape', "", 'transition', struct(), 'flops', 0), 1, H);

for r = (H - 1):-1:0
    gr     = part.g{r + 1};
    rowVar = path(r + 1).var;
    colVar = path(r + 2).var;
    Xrow   = X{r + 1};
    Xcol   = X{r + 2};
    Br     = size(Xrow, 1);
    Bc     = size(Xcol, 1);

    % Every step holds a B_r-by-B_{r+1} matrix, so the support size is not a
    % free accuracy dial: it is squared at every step above the first. Refusing
    % here names the knob and the product, which an out-of-memory raised inside
    % ndgrid several frames down does not.
    if Br * Bc > localMaxPairs()
        error('methods:smoothed:stepTooLarge', ...
            ['Step %d would form a %d-by-%d transition matrix (%.3g entries) ' ...
             'between %s and %s. The recursion holds one such matrix per ' ...
             'step, so surfaceSupportSize (now %g) enters squared at every ' ...
             'step above the first; reduce it, or cap the path depth with ' ...
             'MaxDepth when building it.'], ...
            r, Br, Bc, Br * Bc, rowVar, colVar, config.surfaceSupportSize);
    end

    % --- P_r on the active successor set (Eqs. 46, 49) --------------------
    % The column weights make the row sums quadratures against the pooled
    % proposal rather than equally weighted averages over a support that
    % crowds where the proposal is dense.
    W = methods.smoothed.pairwiseFactorMatrix(gr, rowVar, Xrow, colVar, Xcol);
    W = W .* reshape(supportInfo{r + 1}.nodeWeights, 1, []);

    [P, active, actInfo] = methods.smoothed.buildActiveSuccessors(W, config);

    % --- A_r, Eq. (47), contracted as Eq. (48)/(50) ----------------------
    [R, shape] = localFuseAndContract(P, part.a{r + 1}, rowVar, Xrow, ...
        colVar, Xcol, separator, sepDims, S, R);

    % --- Z_r, the other half of A_r --------------------------------------
    logZ = reshape(gr.logNormalizer(colVar, ...
        struct(matlab.lang.makeValidName(rowVar), Xrow)), [], 1);
    if isscalar(logZ)
        logZ = repmat(logZ, Br, 1);
    end
    R = exp(logZ) .* R;

    steps(r + 1) = struct( ...
        'step',          r, ...
        'rowVar',        rowVar, ...
        'colVar',        colVar, ...
        'numRows',       Br, ...
        'numCols',       Bc, ...
        'fusionFactors', numel(part.a{r + 1}), ...
        'fusionShape',   shape, ...
        'transition',    actInfo, ...
        'flops',         Br * actInfo.K * Rs);
end

R0 = R;

% --- Checks, specification section 16.3 ----------------------------------
% Run on the LAST step's transition matrix and active set, which is step 0 --
% the one whose output is returned.
checks = methods.smoothed.surfaceChecks(R0, P, active);

% Elapsed read before the diagnostics, for the reason evaluateSurfaceRecursion
% gives: the E2 diagnostics take an SVD, which is real work in a method whose
% claim is about cost, and timing the measurement with the thing measured lets
% the diagnostic inflate the number it exists to defend.
elapsed = toc(t0);

if config.surfaceDiagnostics
    surfaceR0 = methods.smoothed.surfaceComplexity(R0);
else
    surfaceR0 = struct('verdict', "not measured", ...
        'reason', "config.surfaceDiagnostics is false");
end

info = struct( ...
    'estimator',        "RCS finite support, general path (Eqs. 44-50)", ...
    'mode',             config.surfaceMode, ...
    'H',                H, ...
    'pathVars',         [path.var], ...
    'numInnerSamples',  0, ...
    'numOuterSamples',  size(X0, 1), ...
    'supportSizes',     cellfun(@(x) size(x, 1), X), ...
    'supportDims',      cellfun(@(x) size(x, 2), X), ...
    'separatorSupport', Rs, ...
    'supports',         {X}, ...
    'supportInfo',      {supportInfo}, ...
    'steps',            steps, ...
    'checks',           checks, ...
    'surface',          surfaceR0, ...
    'costModel',        "sum_r |X_r| |N_r| |S|", ...
    'predictedCost',    sum([steps.flops]), ...
    'storage',          size(X0, 1) * Rs, ...
    'elapsed',          elapsed);
end

% =========================================================================
function n = localMaxPairs()
%LOCALMAXPAIRS Largest B_r*B_{r+1} this function will attempt.
%   Inputs   none
%   Outputs  N, a number of matrix entries
%   Utility  turn a support size that cannot work into a message that says so.
%
%   2e7 entries is about 160 MB per matrix, and a step holds several at once
%   (the pair matrix, the transition, one fusion slice). It is a backstop
%   against a support size chosen without noticing it gets squared, not a
%   statement about the largest useful problem.
n = 2e7;
end

% =========================================================================
function [Rout, shape] = localFuseAndContract(P, fuse, rowVar, Xrow, ...
    colVar, Xcol, separator, sepDims, S, Rin)
%LOCALFUSEANDCONTRACT A_r times R_{r+1}, summed over b: Eqs. (47), (48), (50).
%   Inputs   P the B_r-by-B_{r+1} transition (sparse on the active set), FUSE
%            the fusion factors of this step, the row and column variables with
%            their supports, the separator variables/dims/support, and RIN the
%            B_{r+1}-by-R_s surface from the level below
%   Outputs  ROUT B_r-by-R_s, and SHAPE naming the form A_r took
%   Utility  compute R_r(a,rho) = sum_b P(a,b) A_r(a,b,rho) R_{r+1}(b,rho)
%            without ever holding A_r whole.
%
%   Eq. (50) rather than Eq. (48) comes purely from P being sparse: the sum over
%   b runs over the stored entries, which are exactly N_r(a). The two equations
%   are therefore the same code, which is what makes "the sparse update is the
%   dense one restricted to the active set" checkable rather than a comment.
%
%   THREE FORMS FOR A_r, chosen by SCOPE and not by inspecting values -- a
%   factor that happens to be flat in s this time still gets the tensor form,
%   because deciding on values would make the shape depend on the data:
%
%     "unit"    no fusion factors. A plain matrix product.
%     "matrix"  no fusion factor touches the separator, so A_r does not vary in
%               rho and is B_r-by-B_{r+1}.
%     "tensor"  a fusion factor touches the separator, so A_r is Eq. (47) in
%               full -- but see below.
%
%   THE TENSOR IS NEVER MATERIALIZED, and that is a fix rather than a flourish.
%   Building A_r as B_r-by-B_{r+1}-by-R_s ran out of memory on a two-step path
%   at a support size that the one-step path handled comfortably: the first step
%   has the caller's small outer support on its rows, while every deeper step
%   has a full pooled support on BOTH indices. Eq. (51) makes B_r B_{r+1} R_s
%   the flop count, and it stays the flop count here -- the same number of
%   factor evaluations happens either way -- but the separator index is walked
%   one slice at a time so the memory is B_r B_{r+1} instead. The cost model is
%   unchanged; only the peak is.
nRow = size(Xrow, 1);
nCol = size(Xcol, 1);
nS   = size(S, 1);

if isempty(fuse)
    shape = "unit";
    Rout = P * Rin;
    return
end

if ~any(arrayfun(@(f) any(ismember(separator, f.Scope)), fuse))
    shape = "matrix";
    A = ones(nRow, nCol);
    for k = 1:numel(fuse)
        A = A .* methods.smoothed.pairwiseFactorMatrix( ...
            fuse(k), rowVar, Xrow, colVar, Xcol);
    end
    Rout = (P .* A) * Rin;
    return
end

shape = "tensor";
rowKey = matlab.lang.makeValidName(rowVar);
colKey = matlab.lang.makeValidName(colVar);

% The (a,b) pair expansion is the same at every rho, so it is built once and
% only the separator block is rewritten per slice.
[ia, ib] = ndgrid(1:nRow, 1:nCol);
base = struct();
base.(rowKey) = Xrow(ia(:), :);
base.(colKey) = Xcol(ib(:), :);
ones_ = ones(nRow * nCol, 1);

Rout = zeros(nRow, nS);
for rho = 1:nS
    a = methods.general.supportAssignment(separator, sepDims, ...
        S(rho * ones_, :), base);

    Arho = ones(nRow, nCol);
    for k = 1:numel(fuse)
        Arho = Arho .* reshape(fuse(k).evaluate(a), nRow, nCol);
    end

    Rout(:, rho) = (P .* Arho) * Rin(:, rho);
end
end
