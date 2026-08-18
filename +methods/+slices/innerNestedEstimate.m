function [R, info] = innerNestedEstimate(af, g0, fuse, omega, sepVar, S, config)
%INNERNESTEDESTIMATE The paper's nested inner estimator, Eq. (23).
%
%   Inputs
%     AF       the approximate factor carrying the outer samples xi_0
%     G0       the sampling factor g_0
%     FUSE     the fusion factors a
%     OMEGA    the eliminated variable
%     SEPVAR   the separator variable
%     S        the separator support
%     CONFIG   carrying numInnerSamples, M
%
%   Outputs
%     R        the surface, |X_0|-by-|S|
%     INFO     the cardinalities, the runtime and the evaluation count
%
%   Utility
%     Approximate
%
%       R(xi_0, s) = int g_0(xi_0, l) a(l, s) dl
%
%     by drawing M samples of the eliminated variable from each slice and
%     averaging the fusion factors over them:
%
%       R_hat(xi_0^(n), s) = Z_g(xi_0^(n)) * (1/M) sum_m a(l^(n,m), s)
%
%   which is Eq. (22)-(23) of the Smoothed Slices spec. Z_g is carried
%   explicitly. When g_0 is normalized in its second argument, as every
%   relative Gaussian factor here is, Z_g is 1 and this reduces exactly to
%   Eq. (S14) of the Slices spec, whose compressed notation omits it.
%
%   This is the estimator whose inner Monte Carlo noise, the second term of
%   Eq. (35), Smoothed Slices sets out to remove.

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

M   = config.numInnerSamples;
xi0 = af.Samples;
N0  = numel(xi0);

% Nested draws: l^(n,m) ~ g_0(xi_0^(n), .) / Z_g(xi_0^(n)),  |X_0| x M
given = struct(matlab.lang.makeValidName(af.EliminatedVar), xi0);
L     = g0.sample(omega, given, M);
logZg = reshape(g0.logNormalizer(omega, given), [], 1);
if isscalar(logZg)
    logZg = repmat(logZg, N0, 1);
end

% Average the fusion factors over the nested samples.
% a(l^(n,m), s) is evaluated with the nested samples flattened onto
% dimension 1 and the separator on dimension 2, giving (N0*M) x |S|.
Lflat = reshape(L, [], 1);
A = ones(numel(Lflat), 1);
for i = 1:numel(fuse)
    A = A .* fuse(i).evaluate(struct( ...
        matlab.lang.makeValidName(omega),  Lflat, ...
        matlab.lang.makeValidName(sepVar), S));
end

A = reshape(A, N0, M, numel(S));
R = exp(logZg) .* squeeze(mean(A, 2));
if N0 == 1
    R = reshape(R, 1, []);
end

info = struct( ...
    'estimator',        "nested (Eq. 23)", ...
    'numInnerSamples',  M, ...
    'numOuterSamples',  N0, ...
    'separatorSupport', numel(S), ...
    'nestedSamples',    L, ...
    'logZg',            logZg, ...
    'costModel',        "|X_0| |L| |S|", ...
    'predictedCost',    N0 * M * numel(S), ...
    'elapsed',          toc(t0));
end
