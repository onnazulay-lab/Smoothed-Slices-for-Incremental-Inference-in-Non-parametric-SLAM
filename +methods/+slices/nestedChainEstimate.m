function [R0, info] = nestedChainEstimate(path, part, X0, separator, sepDims, S, config)
%NESTEDCHAINESTIMATE The nested estimator of Eq. (23), unrolled to depth H.
%   [R0, INFO] = NESTEDCHAINESTIMATE(PATH, PART, X0, SEPARATOR, SEPDIMS, S,
%   CONFIG) estimates the same R_0(xi_0, s) that
%   methods.smoothed.surfaceRecursionGeneral computes, by nested Monte Carlo
%   instead of by the cached surface recursion.
%
%   Inputs
%     PATH       struct array from methods.smoothed.buildEliminationPath
%     PART       role partition from methods.smoothed.partitionPathFactors
%     X0         B_0-by-D_0 support of level 0, one point per row
%     SEPARATOR  1-by-K separator variable names, in the order S is built
%     SEPDIMS    1-by-K dimensions, sum(SEPDIMS) == size(S, 2)
%     S          R_s-by-sum(SEPDIMS) separator support
%     CONFIG     method config; numInnerSamples is N, and the optional
%                nestedBudget and nestedMaxBlock cap the work and the memory
%
%   Outputs
%     R0    B_0-by-R_s surface, or [] when the cell was refused
%     INFO  struct with .executed, the cost model, the predicted and measured
%           work, and .reason when the cell was refused
%
%   Utility
%     Give the E1-H depth study the OTHER side of its comparison. Without a
%     nested estimator that runs at the same H on the same path, "the recursion
%     costs sum_r |X_r||N_r||S|" is a number with nothing to be compared to,
%     and the plot the manual asks for cannot be drawn.
%
%   THIS IS THE SAME ESTIMATOR AS innerNestedEstimate, unrolled. At H = 1 the
%   two compute the same quantity by the same formula, which is checked rather
%   than asserted -- see tRecursionDepth. What is added is the tower: the inner
%   expectation of Eq. (23) is itself estimated by nested sampling rather than
%   being the bottom of the recursion, so
%
%       R_r(xi_r,s) = Z_r(xi_r) * (1/N) sum_m a_r(xi_r+1^m,s) R_r+1(xi_r+1^m,s)
%
%   with xi_r+1^m drawn from g_r(xi_r, .). That is the estimator whose cost is
%   the N^H the whole method exists to avoid, and writing it out is the only
%   way to MEASURE that it is N^H rather than assume it.
%
%   THE STEP CONVENTION IS THE RECURSION'S, not a second one. R_H = 1, the
%   empty product, and a{r+1} is consumed at step r with xi_r on the rows and
%   xi_{r+1} on the columns. Using a different convention here would make the
%   two estimators disagree for a reason that has nothing to do with nesting,
%   which is the one confound this comparison cannot afford.
%
%   THE PAIRING IS OUTER-MAJOR AND IT IS BUILT, NOT ASSUMED. core.Factor.sample
%   returns an M-by-N array whose linear order is sample-major, while REPELEM
%   of the parent points is outer-major; pairing the two as they come would
%   attach every child to the wrong parent and still return a smooth, plausible
%   surface. The transpose before the reshape is what makes the two agree, and
%   tRecursionDepth checks the pairing against a hand-built expectation rather
%   than trusting this comment.
%
%   Z_r IS CARRIED EXPLICITLY, exactly as innerNestedEstimate carries Z_g and
%   for the same reason: the sampling factor leaves the product when it becomes
%   the proposal, and its mass has to come back. Every relative Gaussian factor
%   here has Z_r = 1, so a dropped Z_r would be invisible on this case and
%   wrong on the next one.
%
%   REFUSAL IS AN OUTCOME, NOT AN ERROR. The leaf count is B_0 N^H and the work
%   is that times R_s; at N = 200 and H = 5 that is 3e11 leaves before the
%   separator axis is counted. The study needs those cells recorded as
%   infeasible WITH their predicted cost -- that is the finding -- so this
%   returns INFO.executed = false and a reason rather than raising, and rather
%   than running for a week to produce a number that was predictable in advance.
%
%   See also methods.slices.innerNestedEstimate,
%            methods.smoothed.surfaceRecursionGeneral,
%            research.recursionDepthStudy.

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

H  = numel(path) - 1;
B0 = size(X0, 1);
Rs = size(S, 1);
N  = config.numInnerSamples;

if H < 1
    error('methods:slices:pathTooShort', ...
        'A path of one level has no inner expectation to nest.');
end
if numel(part.g) ~= H || numel(part.a) ~= H
    error('methods:slices:partitionShapeMismatch', ...
        ['The partition has %d sampling and %d fusion slot(s) but the path ' ...
         'has H = %d. They must come from the same path.'], ...
        numel(part.g), numel(part.a), H);
end
if sum(sepDims) ~= size(S, 2)
    error('methods:slices:separatorWidthMismatch', ...
        'sepDims sums to %d but S has %d column(s).', sum(sepDims), size(S, 2));
end

leaves        = B0 * N^H;
predictedCost = leaves * Rs;
perOuter      = N^H * Rs;

budget   = localOption(config, 'nestedBudget',   2e8);
maxBlock = localOption(config, 'nestedMaxBlock', 3e7);

info = struct( ...
    'estimator',        "nested Monte Carlo, depth H (Eq. 23 unrolled)", ...
    'H',                H, ...
    'executed',         false, ...
    'reason',           "", ...
    'numOuterSamples',  B0, ...
    'numInnerSamples',  N, ...
    'separatorSupport', Rs, ...
    'leafSamples',      leaves, ...
    'costModel',        "|X_0| N^H |S|", ...
    'predictedCost',    predictedCost, ...
    'measuredEvaluations', 0, ...
    'numDraws',         0, ...
    'storage',          B0 * Rs, ...
    'chunk',            0, ...
    'peakBlock',        0, ...
    'elapsed',          0);

R0 = [];
if predictedCost > budget
    info.reason = string(sprintf( ...
        ['|X_0| N^H |S| = %d * %d^%d * %d = %.3g exceeds the nested work ' ...
         'budget %.3g. The cell is infeasible by the cost model rather than ' ...
         'by this implementation, so it is recorded and not run.'], ...
        B0, N, H, Rs, predictedCost, budget));
    info.elapsed = toc(t0);
    return
end
if perOuter > maxBlock
    % Distinct from the work budget: even ONE outer point needs an
    % N^H-by-R_s block resident at the deepest step, so a cell can be within
    % the total budget and still have no block small enough to hold.
    info.reason = string(sprintf( ...
        ['One outer point needs an N^H-by-|S| block of %d * %d = %.3g ' ...
         'entries at the deepest step, past the %.3g the estimator will ' ...
         'hold. Nesting cannot be chunked below one outer point.'], ...
        N^H, Rs, perOuter, maxBlock));
    info.elapsed = toc(t0);
    return
end

% --- Chunk the outer samples ---------------------------------------------
% The chunk comes from the DEEPEST block, N^H-by-R_s per outer point, rather
% than from B_0. Without this the function is either restricted to tiny H or
% dies inside a reshape several frames down with a message that names neither
% H nor N.
chunk = min(B0, max(1, floor(maxBlock / perOuter)));
info.chunk     = chunk;
info.peakBlock = chunk * perOuter;

R0 = zeros(B0, Rs);
evals = 0;
draws = 0;
for lo = 1:chunk:B0
    hi = min(lo + chunk - 1, B0);
    [block, e, d] = localDescend(0, X0(lo:hi, :), H, path, part, ...
        separator, sepDims, S, N);
    R0(lo:hi, :) = block;
    evals = evals + e;
    draws = draws + d;
end

info.executed             = true;
info.measuredEvaluations  = evals;
info.numDraws             = draws;
info.elapsed              = toc(t0);
end

% =========================================================================
function [R, evals, draws] = localDescend(r, Xr, H, path, part, separator, sepDims, S, N)
%LOCALDESCEND R_r on the given level-r points, by descending to level H.
%   Inputs   R the level index, XR the M-by-D points at that level, and the
%            path, partition, separator and sample count
%   Outputs  R the M-by-R_s surface at those points, EVALS the fusion-factor
%            evaluations made below this frame, DRAWS the samples drawn
%   Utility  walk the tower down and average back up, one level per frame.
%
%   RECURSION RATHER THAN A LOOP, because the shape of the work is a tree: each
%   level-r point spawns N level-(r+1) points, and the average that collapses
%   them belongs to the level that drew them. A loop would have to carry the
%   parent index of every point at every level by hand, which is this tree
%   written out badly.
M  = size(Xr, 1);
Rs = size(S, 1);

if r == H
    % R_H = 1, the empty product. See the step convention in the header.
    R     = ones(M, Rs);
    evals = 0;
    draws = 0;
    return
end

gr     = part.g{r + 1};
rowVar = path(r + 1).var;
colVar = path(r + 2).var;
fuse   = part.a{r + 1};

% --- Draw N successors per row, ordered outer-major ----------------------
given = struct(matlab.lang.makeValidName(rowVar), Xr);
L = gr.sample(colVar, given, N);            % M-by-N, or M-by-N-by-d
if ndims(L) == 3
    d     = size(L, 3);
    Xnext = reshape(permute(L, [2 1 3]), M * N, d);
else
    Xnext = reshape(L.', M * N, 1);
end

[Rnext, evals, draws] = localDescend(r + 1, Xnext, H, path, part, ...
    separator, sepDims, S, N);              % (M*N)-by-R_s
draws = draws + M * N;

% --- a_r(xi_r, xi_r+1, s) on the paired points ---------------------------
T = Rnext;
if ~isempty(fuse)
    Xrep = repelem(Xr, N, 1);               % matched to Xnext by construction
    for k = 1:numel(fuse)
        T = T .* localFactorMatrix(fuse(k), rowVar, Xrep, colVar, Xnext, ...
            separator, sepDims, S);
        evals = evals + M * N * Rs;
    end
end

% --- Average over the N draws, and put Z_r back --------------------------
R = reshape(mean(reshape(T, N, M, Rs), 1), M, Rs);

logZ = reshape(gr.logNormalizer(colVar, given), [], 1);
if isscalar(logZ)
    logZ = repmat(logZ, M, 1);
end
R = exp(logZ) .* R;
end

% =========================================================================
function V = localFactorMatrix(f, rowVar, Xrow, colVar, Xcol, separator, sepDims, S)
%LOCALFACTORMATRIX One fusion factor over the paired points and the separator.
%   Inputs   F the factor, the row and column variables with their ALREADY
%            PAIRED supports (equal row counts), and the separator with its
%            dimensions and support
%   Outputs  V, an nPairs-by-R_s matrix
%   Utility  evaluate a_r once per (pair, separator point) without building a
%           rank-3 array.
%
%   The pairs arrive already expanded, which is what separates this from
%   methods.smoothed.pairwiseFactorMatrix: the nested estimator never forms a
%   row-by-column grid, because every column point belongs to exactly one row
%   point. That is the structural difference between the two estimators, and
%   the reason the nested one has no surface to cache.
nPairs = size(Xrow, 1);
Rs     = size(S, 1);

args = struct();
if any(f.Scope == rowVar)
    args.(matlab.lang.makeValidName(rowVar)) = repmat(Xrow, Rs, 1);
end
if any(f.Scope == colVar)
    args.(matlab.lang.makeValidName(colVar)) = repmat(Xcol, Rs, 1);
end

col = 0;
for k = 1:numel(separator)
    idx = col + (1:sepDims(k));
    col = col + sepDims(k);
    if any(f.Scope == separator(k))
        args.(matlab.lang.makeValidName(separator(k))) = repelem(S(:, idx), nPairs, 1);
    end
end

V = reshape(f.evaluate(args), nPairs, Rs);
end

% =========================================================================
function v = localOption(config, name, fallback)
%LOCALOPTION Read an optional config field.
%   Inputs   CONFIG, NAME and FALLBACK
%   Outputs  V, the field or the fallback
%   Utility  let the study raise the caps without every other caller having to
%           carry fields it does not use.
v = fallback;
if isfield(config, name) && ~isempty(config.(name))
    v = config.(name);
end
end
