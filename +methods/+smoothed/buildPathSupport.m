function [X, info] = buildPathSupport(g, fromVar, Xfrom, toVar, target, opts)
%BUILDPATHSUPPORT Finite support X_{r+1} of Eq. (42), in any dimension.
%   [X, INFO] = BUILDPATHSUPPORT(G, FROMVAR, XFROM, TOVAR, TARGET) draws the
%   shared finite support of the next path variable from the structural
%   proposal q_r(xi_{r+1} | xi_r) proportional to G, pools it across every
%   point of XFROM, and returns a quadrature weight for each support point.
%
%   Inputs
%     G        core.Factor covering FROMVAR and TOVAR, the sampling factor g_r
%     FROMVAR  the level-r variable
%     XFROM    B_r-by-D_r support of level r, one point per row
%     TOVAR    the level-(r+1) variable
%     TARGET   requested |X_{r+1}|
%     Rng      "shuffle" is refused; pass a nonnegative integer or "inherit"
%                                                            default "inherit"
%
%   Outputs
%     X        B-by-D support, one point per row
%     INFO     struct with poolSize, perRowDraws, cardinality, nodeWeights,
%              weightRule, thinRule, essWeights
%
%   Utility
%     Supply the recursion with a support every row can share, plus the weights
%     that make the row sums quadratures rather than averages.
%
%   THE POOLING IS THE METHOD AND ALSO ITS EXPOSURE, exactly as in the scalar
%   route: the nested estimator keeps a private block of samples per outer
%   point, a TREE of size |X_r| x M, while here the draws are pooled into one
%   support of size |X_{r+1}| that every row shares. Pooling is what makes a
%   surface MATRIX possible, and it is what fails if one row's proposal lives
%   somewhere no other row visits.
%
%   WHAT REPLACED THE SCALAR CONSTRUCTION, and why it had to be replaced.
%   buildSamplingPath thinned the pool by even quantile spacing and weighted
%   each point by its Voronoi (midpoint) width. Both steps are irreducibly
%   one-dimensional: quantiles need a total order, and midpoint widths need
%   neighbours on a line. In the plane there is no order, and Voronoi cell
%   AREAS would need a tessellation whose cost is not in the method's cost
%   model. So neither step is generalized -- each is replaced by something that
%   never needed the line in the first place:
%
%     thinning   a uniform random subsample without replacement. A uniform
%                subsample of a q_mix sample is still a q_mix sample, so modes
%                survive in proportion to their mass. This is NOT the "blind
%                truncation" that section 18 calls support loss: that was
%                keeping the FIRST draws, which are ordered by outer row and
%                therefore cover only the first rows' proposals.
%
%     weights    pooled-proposal importance weights. The pool is drawn equally
%                from every row's proposal, so it is a sample from the mixture
%
%                    q_mix(x) = (1/B_r) sum_a g(xi_r^a, x) / Z_r(xi_r^a),
%
%                and the quadrature weight of a support point is
%                w_b = 1 / (B q_mix(x_b)). Then
%
%                    sum_b g(a,b) R(b,rho) w_b
%                        -> E_{x~q_mix}[ g R / q_mix ] = integral g R dx,
%
%                which is the integral Eq. (40) asks for, in any dimension.
%
%   THIS COSTS NOTHING EXTRA. q_mix needs g on every (row, support) pair and
%   Z_r per row -- the same matrix and the same normalizer the recursion
%   evaluates anyway. The weights are a by-product of work already budgeted,
%   which matters because the method's whole claim is about cost.
%
%   AND IT IS A STRICTLY BETTER STATEMENT OF THE QUADRATURE, not merely a
%   portable one. Voronoi widths make the reference measure implicit in where
%   the points happen to sit; importance weights name it. A support built any
%   other way -- a plain grid, which section 16.2 also permits -- gets correct
%   weights from the same formula without the formula knowing.
%
%   See also methods.smoothed.pairwiseFactorMatrix,
%            methods.smoothed.buildSamplingPath.

arguments
    g (1,1) core.Factor
    fromVar (1,1) string
    Xfrom (:,:) double
    toVar (1,1) string
    target (1,1) double {mustBePositive}
    opts.Rng = "inherit"
end

if isstring(opts.Rng) || ischar(opts.Rng)
    if string(opts.Rng) ~= "inherit"
        error('methods:smoothed:supportRng', ...
            ['Rng must be a nonnegative integer or "inherit"; "%s" would ' ...
             'make the support unreproducible.'], string(opts.Rng));
    end
else
    rng(opts.Rng);
end

B0 = size(Xfrom, 1);
fromKey = matlab.lang.makeValidName(fromVar);

% --- Draw the pool --------------------------------------------------------
% One extra draw per row beyond the even share, so that thinning has something
% to thin and a support of TARGET points is reachable from B0 rows.
perRow = max(2, ceil(target / max(B0, 1)) + 1);
raw = g.sample(toVar, struct(fromKey, Xfrom), perRow);

% B0-by-perRow-by-D for a D-dimensional target, B0-by-perRow when D is 1.
% Column-major reshape puts coordinate k in column k for every (row, draw),
% which is the ordering the sampler documents.
d = size(raw, 3);
pool = reshape(raw, [], max(d, 1));
poolSize = size(pool, 1);

% --- Thin -----------------------------------------------------------------
if poolSize <= target
    X = pool;
    thinRule = "none, the pool is already at or under the target";
else
    keep = randperm(poolSize, round(target));
    X = pool(sort(keep), :);
    thinRule = "uniform random subsample without replacement";
end

B = size(X, 1);

% --- Pooled-proposal weights ---------------------------------------------
% W(a,b) = g(xi_r^a, x_b), the same matrix the recursion forms.
W = methods.smoothed.pairwiseFactorMatrix(g, fromVar, Xfrom, toVar, X);

logZ = reshape(g.logNormalizer(toVar, struct(fromKey, Xfrom)), [], 1);
if isscalar(logZ)
    logZ = repmat(logZ, B0, 1);
end

% q_mix as an average of NORMALIZED row proposals. Dividing by Z_r per row is
% what makes this a mixture of densities rather than a mixture of unnormalized
% factors; the rows would otherwise be weighted by their own mass and the
% weights would not integrate anything.
qmix = mean(W .* exp(-logZ), 1).';          % B x 1

good = qmix > 0 & isfinite(qmix);
nodeWeights = zeros(B, 1);
nodeWeights(good) = 1 ./ (B * qmix(good));

if ~any(good)
    error('methods:smoothed:supportHasNoProposalMass', ...
        ['Every one of the %d pooled support points for %s has zero mixture ' ...
         'density, so no quadrature weight can be formed. The proposal and ' ...
         'the factor disagree about where %s lives.'], B, toVar, toVar);
end

% A point the mixture cannot have produced gets weight zero rather than Inf.
% It contributes nothing instead of dominating, and the count is reported so a
% support that is mostly unreachable is visible rather than merely quiet.
numUnreachable = nnz(~good);

% --- How much of the support each row actually uses -----------------------
% PER ROW, and that is the whole point of measuring it here rather than on the
% weight vector alone. Kish's ESS of nodeWeights by itself is always poor and
% says nothing: w_b = 1/(B q_mix(x_b)) is largest exactly where the mixture is
% thinnest, so the tail points carry enormous weights and the raw ESS collapses
% even when every row's quadrature is healthy.
%
% What a row actually sums is g(xi_r^a, x_b) * w_b, whose weights are
% g(a,b)/q_mix(b) up to a constant. Because q_mix CONTAINS row a's own
% component,
%
%     q_mix(x) >= (1/B_r) g(xi_r^a, x) / Z_r(xi_r^a),
%
% so that ratio is bounded above by B_r Z_r whatever the tails do. This is the
% standard defensive-mixture argument, and it is the reason the pooled support
% is safe to share across rows at all. The per-row ESS is therefore the number
% that governs the quadrature, and the minimum over rows is the one to watch:
% one starved row is a bad surface row, which no average would show.
rowW = W .* nodeWeights.';
essRow = localRowESS(rowW);

info = struct( ...
    'rule',            "structural proposal, pooled across rows", ...
    'poolSize',        poolSize, ...
    'perRowDraws',     perRow, ...
    'cardinality',     B, ...
    'dimension',       size(X, 2), ...
    'requested',       target, ...
    'thinRule',        thinRule, ...
    'nodeWeights',     nodeWeights, ...
    'weightRule',      "pooled-proposal importance weight 1/(B q_mix)", ...
    'numUnreachable',  numUnreachable, ...
    'essRowMin',       min(essRow), ...
    'essRowMean',      mean(essRow), ...
    'essRowFraction',  min(essRow) / B, ...
    'essWeights',      localRowESS(nodeWeights.'), ...
    'essNote',         "essWeights is the raw weight vector and is expected " + ...
                       "to be low; essRowMin is the one that governs the " + ...
                       "quadrature");
end

% =========================================================================
function e = localRowESS(w)
%LOCALROWESS Kish's effective sample size of each row of a weight matrix.
%   Inputs   W, an M-by-N nonnegative weight matrix
%   Outputs  E, M-by-1 in [0, N]; NaN for a row carrying no mass
%   Utility  say how many support points each row of the quadrature is really
%            using, since a row whose weight sits on one point is a row of one.
s1 = sum(w, 2);
s2 = sum(w.^2, 2);
e = nan(size(w, 1), 1);
ok = s2 > 0;
e(ok) = s1(ok).^2 ./ s2(ok);
end
