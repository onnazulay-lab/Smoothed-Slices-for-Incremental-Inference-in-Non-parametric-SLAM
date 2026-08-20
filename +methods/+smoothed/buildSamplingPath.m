function [X1, info] = buildSamplingPath(af, g0, omega, config)
%BUILDSAMPLINGPATH Finite support X_r for the path variable (Eq. 42).
%
%   Inputs
%     AF      the approximate factor carrying the outer samples xi_0
%     G0      the sampling factor, which is also the proposal
%     OMEGA   the path variable xi_1
%     CONFIG  carrying surfaceSupportSize
%
%   Outputs
%     X1      the support, |X_1|-by-1
%     INFO    the pool size, the per-row draws, the range, the node weights
%             and the rule each was built by
%
%   Utility
%     Build the shared finite support of the inner path variable.
%
%   This is the SCALAR path builder, used by evaluateSurfaceRecursion's one
%   -step case. methods.smoothed.buildPathSupport is the general one, in any
%   dimension and with pooled-proposal importance weights.
%
%   Specification section 16.2 says X_r should use "samples inherited from
%   the paper's structural sampling route", so the support is drawn from the
%   very same proposal q_0(xi_1 | xi_0) that the nested estimator uses. The
%   difference is what happens next: the nested estimator keeps a separate
%   private block of samples per outer point, forming a TREE of size
%   |X_0| x M, while here the draws are POOLED into one support of size
%   |X_1| that every row shares. That pooling is what makes a surface matrix
%   possible, and it is also the method's exposure: a pooled support must
%   still cover every region any single row cares about.
%
%   The support is thinned to |X_1| = surfaceSupportSize by even quantile
%   spacing rather than by taking the first draws, so that a pooled support
%   built from a multimodal proposal retains all of its modes. Blind
%   truncation here is the "support loss" failure mode of section 18.

arguments
    af (1,1) core.ApproximateFactor
    g0 (1,1) core.Factor
    omega (1,1) string
    config (1,1) struct
end

xi0 = af.Samples;
B0  = numel(xi0);
target = config.surfaceSupportSize;

% Draw enough structural samples that the pooled support covers the union of
% the per-row proposals, then thin.
perRow = max(2, ceil(target / max(B0, 1)) + 1);
given  = struct(matlab.lang.makeValidName(af.EliminatedVar), xi0);
pool   = reshape(g0.sample(omega, given, perRow), [], 1);

pool = sort(pool);
raw  = numel(pool);

if raw <= target
    X1 = pool;
else
    % Even quantile spacing preserves the shape of the pooled distribution,
    % including separated modes.
    q  = linspace(0, 1, target);
    X1 = quantile(pool, q);
    X1 = unique(X1(:), 'stable');
end

X1 = reshape(X1, [], 1);

% Node weights. The support points are NOT equally spaced -- they are
% quantiles of a pooled proposal, so they crowd where the proposal is dense.
% Row-normalizing raw g_0 values over such a support would silently weight
% each point equally, which is a quadrature against the wrong reference
% measure and biases the surface toward the crowded region. Attaching the
% Voronoi width of each node turns the recursion into a genuine nonuniform
% quadrature and makes it independent of how the support was built, so a
% plain grid (also permitted by section 16.2) works unchanged.
nodeWeights = localNodeWeights(X1);

info = struct( ...
    'rule',        "structural proposal, pooled and quantile-thinned", ...
    'poolSize',    raw, ...
    'perRowDraws', perRow, ...
    'cardinality', numel(X1), ...
    'range',       [min(X1) max(X1)], ...
    'requested',   target, ...
    'nodeWeights', nodeWeights, ...
    'weightRule',  "Voronoi width of each support point");
end

% -------------------------------------------------------------------------
function w = localNodeWeights(x)
%LOCALNODEWEIGHTS Voronoi widths: what each support point stands in for.
%   Inputs   X, the sorted support
%   Outputs  W, one width per point
%   Utility  a thinned support is a quadrature rule, and a rule without
%           weights integrates the wrong thing. Only defined in 1-D, which is
%           why the general builder uses importance weights instead.
x = x(:);
n = numel(x);
if n == 1
    w = 1;
    return
end
edges = [x(1); 0.5 * (x(1:end-1) + x(2:end)); x(end)];
w = diff(edges);

% A degenerate support (repeated points) would give zero-width nodes; fall
% back to uniform weights rather than producing an all-zero transition row.
if all(w == 0)
    w = ones(n, 1) / n;
end
end
