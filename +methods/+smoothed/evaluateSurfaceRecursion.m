function [R0, info] = evaluateSurfaceRecursion(af, g0, fuse, omega, sepVar, S, config)
%EVALUATESURFACERECURSION Smoothed Slices inner estimator, Eqs. (48)-(53).
%
%   Inputs
%     AF       the approximate factor carrying the outer samples xi_0
%     G0       the sampling factor g_0
%     FUSE     the fusion factors a
%     OMEGA    the eliminated variable, the path variable xi_1
%     SEPVAR   the separator variable
%     S        the separator support
%     CONFIG   carrying surfaceSupportSize, activeSetSize and surfaceMode
%
%   Outputs
%     R0       the surface, |X_0|-by-|S|
%     INFO     the cardinalities, the support and its diagnostics, the
%              transition summary, the section 16.3 checks, the complexity of
%              both surfaces, and the cost model beside the measured count
%
%   Utility
%     Replace the nested sampling of Eq. (23) by a cached CONDITIONAL
%     SMOOTHING SURFACE. R0 is the same |X_0| x |S| object innerNestedEstimate
%     returns, so the two are interchangeable inside estimateNewFactor and
%     differ only in how the inner integral is approximated.
%
%   INDEXING CONVENTION. The specification is inconsistent about the index of
%   R: section 7 writes R_1(x1,x2), indexing by the CONDITIONING variable,
%   while section 9 writes R_r(xi_r,s) with R_H = a_H, indexing by LEVEL.
%   This implementation follows section 9, which is the form the matrix
%   recursion of section 10 actually implements, and maps the example onto it
%   as:
%
%       xi_0 = x1,  xi_1 = l1,  H = 1
%       R_1(l1, x2) = a_1(l1, x2) = f(l1, x2)              (Eq. 38)
%       R_0(x1, x2) = int g_0(x1,l1) R_1(l1,x2) dl1        (Eq. 40, a_0 = 1)
%
%   so this R_0 is exactly the surface written R_1(x1,x2) in section 7's
%   Eq. (26), and Eq. (41) then reproduces Eq. (27). The fusion factor a_0 is
%   identically 1 here because the only factor coupling l1 to the separator
%   is already the terminal surface; putting it in both places would double
%   count it.
%
%   Finite implementation (Eq. 50):
%
%       R_0(a,rho) = sum_{b in N_0(a)} P_0(a,b) A_0(a,b,rho) R_1(b,rho)
%
%   with P_0 the row-normalized transition matrix on the active successor set
%   and A_0(a,b,rho) = Z_0(xi_0^(a)) * a_0(xi_1^(b), s^(rho)) = Z_0(xi_0^(a)).
%
%   The gain claimed by the method comes from |N_r| << |X_1|, and from the
%   surface being reusable across increments. Both are measured in INFO
%   rather than asserted.

arguments
    af (1,1) core.ApproximateFactor
    g0 (1,1) core.Factor
    fuse (1,:) core.Factor
    omega (1,1) string
    sepVar (1,1) string
    S (1,:) double
    config (1,1) struct
end

t0 = tic;

if config.surfaceMode ~= "finite"
    error('methods:smoothed:modeNotImplemented', ...
        ['Surface mode "%s" is Mode B/C of specification section 11 and is ' ...
         'scheduled for iteration 5. Iteration 4 measured the surface ' ...
         'property that would justify building it (research sheet E2) ' ...
         'rather than assuming it. Mode A ("finite") is implemented, and ' ...
         'the spec requires it to be validated first.'], config.surfaceMode);
end

xi0 = af.Samples;            % X_0, |X_0| = B_0
B0  = numel(xi0);
Rs  = numel(S);
omegaKey = matlab.lang.makeValidName(omega);
outerKey = matlab.lang.makeValidName(af.EliminatedVar);
sepKey   = matlab.lang.makeValidName(sepVar);

% --- Support X_1 of the inner path variable ------------------------------
% Built from the structural proposal itself (spec section 16.2: "samples
% inherited from the paper's structural sampling route"), pooled across the
% outer support so that one shared support serves every row. Pooling is what
% turns the nested sample TREE into a surface MATRIX.
[X1, supportInfo] = methods.smoothed.buildSamplingPath( ...
    af, g0, omega, config);
B1 = numel(X1);

% --- Terminal surface R_1(b,rho) = a_1(xi_1^(b), s^(rho))  (Eq. 38) -------
R1 = ones(B1, 1);
for i = 1:numel(fuse)
    R1 = R1 .* fuse(i).evaluate(struct(omegaKey, X1(:), sepKey, S));
end                                                  % B1 x Rs

% --- Transition weights P_0(a,b) on the active successor set (Eq. 46, 49) -
% q_0(xi_1 | xi_0) is proportional to g_0(xi_0, xi_1), and each support point
% carries the Voronoi width of its node so that the row sum approximates an
% integral rather than an equally-weighted average over a nonuniform support.
W = g0.evaluate(struct(outerKey, xi0(:), omegaKey, reshape(X1, 1, [])));  % B0 x B1
W = W .* reshape(supportInfo.nodeWeights, 1, []);

[P0, active, activeInfo] = methods.smoothed.buildActiveSuccessors(W, config);

% --- Fusion multiplier A_0(a,b,rho) = Z_0(xi_0^(a)) * a_0(...) ------------
% a_0 == 1 for this path (see the indexing note above), so the tensor
% collapses to a per-row scalar and never needs to be materialized.
logZ0 = reshape(g0.logNormalizer(omega, struct(outerKey, xi0)), [], 1);
if isscalar(logZ0)
    logZ0 = repmat(logZ0, B0, 1);
end

% --- Sparse recursion, Eq. (50) ------------------------------------------
% With a_0 constant in b, the row sum is a plain sparse matrix product.
%
% Note that Z_0 multiplies here and divides inside the row normalization of
% P_0, since sum_b g_0(a,b) w_b approximates Z_0(xi_0^(a)). The two cancel to
% leave sum_b g_0(a,b) R_1(b,rho) w_b, i.e. Eq. (26) evaluated by quadrature.
% Keeping both written out follows Eq. (47) literally and makes the estimator
% insensitive to an inaccurate Z_0.
R0 = exp(logZ0) .* (P0 * R1);                        % B0 x Rs

% --- Required numerical checks, specification section 16.3 ---------------
checks = methods.smoothed.surfaceChecks(R0, P0, active);

% --- Elapsed, read BEFORE the complexity diagnostics ----------------------
% The E2 diagnostics below take an SVD of the surface, which is real work in
% a method whose entire claim is about cost. Timing the measurement along
% with the thing measured would let the diagnostic inflate the number the
% diagnostic exists to defend, so the clock is read here and the SVD happens
% after it.
elapsed = toc(t0);

% --- Surface complexity, research sheet E2 -------------------------------
% BOTH surfaces, and that is the point. R_0 = diag(Z) P_0 R_1, so
% rank(R_0) <= min(rank(P_0), rank(R_1)): if the terminal surface is already
% rank 2 then R_0 is rank at most 2 whatever the recursion does, and reading
% that as "the smoothing produces compact surfaces" would be reading a
% property of the fusion factors. The two are reported side by side so the
% comparison is available to anyone who quotes either.
if config.surfaceDiagnostics
    surfaceR0 = methods.smoothed.surfaceComplexity(R0);
    surfaceR1 = methods.smoothed.surfaceComplexity(R1);
else
    surfaceR0 = struct('verdict', "not measured", ...
        'reason', "config.surfaceDiagnostics is false");
    surfaceR1 = surfaceR0;
end

info = struct( ...
    'estimator',        "RCS finite support (Eq. 50)", ...
    'mode',             config.surfaceMode, ...
    'numInnerSamples',  0, ...
    'numOuterSamples',  B0, ...
    'supportX1',        B1, ...
    'separatorSupport', Rs, ...
    'activeSetSize',    activeInfo.K, ...
    'activeSetRule',    config.activeSetRule, ...
    'support',          X1, ...
    'supportInfo',      supportInfo, ...
    'R1',               R1, ...
    'transition',       activeInfo, ...
    'checks',           checks, ...
    'surface',          surfaceR0, ...
    'terminalSurface',  surfaceR1, ...
    'costModel',        "|X_0| |N_0| |S|", ...
    'predictedCost',    B0 * activeInfo.K * Rs, ...
    'storage',          B0 * Rs, ...
    'elapsed',          elapsed);

% The whole claim of the method is that the surface replaces nested
% sampling; recording zero inner samples makes that explicit and lets the
% cost-scaling test compare like with like.
end
