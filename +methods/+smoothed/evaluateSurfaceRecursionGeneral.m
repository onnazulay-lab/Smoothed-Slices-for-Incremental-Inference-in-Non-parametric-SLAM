function [R0, info] = evaluateSurfaceRecursionGeneral(af, g0, fuse, omega, sepVar, S, config)
%EVALUATESURFACERECURSIONGENERAL The H = 1 route, run through the general recursion.
%   [R0, INFO] = EVALUATESURFACERECURSIONGENERAL(AF, G0, FUSE, OMEGA, SEPVAR,
%   S, CONFIG) computes the same surface as
%   methods.smoothed.evaluateSurfaceRecursion, with the same signature and the
%   same INFO field names, by calling methods.smoothed.surfaceRecursionGeneral
%   instead of the scalar unrolling.
%
%   Inputs
%     AF       the approximate factor carrying the outer samples xi_0
%     G0       the sampling factor g_0
%     FUSE     the fusion factors a
%     OMEGA    the eliminated variable, xi_1
%     SEPVAR   the separator variable
%     S        the separator support
%     CONFIG   the method config
%
%   Outputs
%     R0    |X_0|-by-|S| surface
%     INFO  the diagnostics, in the field names the exports already read
%
%   Utility
%     Put the general recursion on a path that a validated implementation
%     already computes, so the two can be required to agree on a real case
%     rather than only on the closed forms in tSurfaceRecursion.
%
%   WHY THIS EXISTS AT ALL, given that the scalar route works. Because
%   surfaceRecursionGeneral was, until this was written, called by nothing but
%   its own test class. A recursion that no production path reaches is one
%   whose agreement with the shipped method has never been checked on a case
%   with a quadrature reference behind it -- and research.recursionDepthStudy
%   is about to rely on it at depths where no second implementation exists.
%   H = 1 is the one depth where both exist, so it is the one place the general
%   engine can be held to the scalar one's answer.
%
%   THE PATH AND PARTITION ARE BUILT HERE RATHER THAN DISCOVERED, and that is
%   sound rather than a shortcut around methods.smoothed.partitionPathFactors.
%   The caller has already decided every role: the Lemma-1 route picked g_0 as
%   the sampling factor, FUSE as the factors coupling omega to the separator,
%   and the front factors that stay outside the recursion entirely.
%   partitionPathFactors exists to make those assignments over an ARBITRARY
%   path, where one factor can plausibly belong to two slots; at H = 1 with the
%   roles already assigned there is nothing left to decide, and rebuilding a
%   graph here so the partitioner could rediscover them would be inventing a
%   second source of truth about the same four factors.
%
%   THE INFO IS TRANSLATED, NOT WIDENED. Exports, the process trace, the
%   cardinality collector and the diagnostics markdown all read supportX1,
%   activeSetSize, transition, terminalSurface and the cost fields off this
%   struct. Emitting the general recursion's own names would leave every one of
%   those reading a missing field, and quietly, since they all guard with
%   isfield. So the translation happens here, once, at the boundary.
%
%   R_1 IS RECONSTRUCTED, BECAUSE THE TWO ROUTES INDEX IT DIFFERENTLY. The
%   scalar route follows Eq. (38) literally and initializes R_1 = a_1; the
%   general recursion follows partitionPathFactors' convention, R_H = 1 with
%   a_H absorbed into step H-1. Those give the same R_0 -- that is the point of
%   the convention -- but they mean different things by "R_1", so the terminal
%   surface the exports plot is formed here from the fusion factors rather than
%   read off a recursion that never materialized it. When a fusion factor also
%   touches xi_0 there IS no such matrix, in either route, and the diagnostic
%   says so instead of returning a slice of a tensor.
%
%   See also methods.smoothed.evaluateSurfaceRecursion,
%            methods.smoothed.surfaceRecursionGeneral,
%            methods.slices.estimateNewFactor.

arguments
    af (1,1) core.ApproximateFactor
    g0 (1,1) core.Factor
    fuse (1,:) core.Factor
    omega (1,1) string
    sepVar (1,1) string
    S (1,:) double
    config (1,1) struct
end

% The two-level path of Eq. (36): xi_0 is the variable the slices were taken
% over, xi_1 is the variable being eliminated.
path = struct( ...
    'var',        {af.EliminatedVar, omega}, ...
    'orderIndex', {1, 2}, ...
    'gName',      {"", g0.Name});

part = struct('g', {{g0}}, 'a', {{fuse}}, ...
              'b0', {core.Factor.empty(1, 0)}, ...
              'counts', {struct('g', 1, 'a', numel(fuse), 'b0', 0)});

X0 = reshape(af.Samples, [], 1);
Scol = reshape(S, [], 1);

[R0, gen] = methods.smoothed.surfaceRecursionGeneral( ...
    path, part, X0, sepVar, 1, Scol, config);

step = gen.steps(1);          % H = 1, so step 0 is the only step
X1   = gen.supports{2};

[R1, terminal] = localTerminalSurface(fuse, af.EliminatedVar, omega, X1, ...
    sepVar, Scol, config);

info = struct( ...
    'estimator',        "RCS finite support, general path at H = 1 (Eqs. 44-50)", ...
    'mode',             gen.mode, ...
    'numInnerSamples',  0, ...
    'numOuterSamples',  gen.numOuterSamples, ...
    'supportX1',        gen.supportSizes(2), ...
    'separatorSupport', gen.separatorSupport, ...
    'activeSetSize',    step.transition.K, ...
    'activeSetRule',    config.activeSetRule, ...
    'support',          X1, ...
    'supportInfo',      gen.supportInfo{1}, ...
    'R1',               R1, ...
    'transition',       step.transition, ...
    'checks',           gen.checks, ...
    'surface',          gen.surface, ...
    'terminalSurface',  terminal, ...
    'costModel',        gen.costModel, ...
    'predictedCost',    gen.predictedCost, ...
    'storage',          gen.storage, ...
    'H',                gen.H, ...
    'fusionShape',      step.fusionShape, ...
    'elapsed',          gen.elapsed);
end

% =========================================================================
function [R1, terminal] = localTerminalSurface(fuse, outerVar, omega, X1, sepVar, S, config)
%LOCALTERMINALSURFACE a_1(xi_1, s) on the level-1 support, and its complexity.
%   Inputs   FUSE the fusion factors, OUTERVAR xi_0, OMEGA xi_1 with its
%            support X1, SEPVAR with its support S, and CONFIG
%   Outputs  R1 the |X_1|-by-|S| terminal surface or [], TERMINAL its
%            complexity diagnostic or a stated reason there is none
%   Utility  give the E2 surface plots the same object on this route as on the
%           scalar one, or say plainly that this path has no such object.
if any(arrayfun(@(f) any(f.Scope == outerVar), fuse))
    R1 = [];
    terminal = struct('verdict', "not measured", ...
        'reason', "a fusion factor also depends on " + outerVar + ...
                  ", so A_r is a rank-3 tensor and has no terminal surface " + ...
                  "to plot at any single level");
    return
end

R1 = ones(numel(X1), numel(S));
for k = 1:numel(fuse)
    R1 = R1 .* fuse(k).evaluate(struct( ...
        matlab.lang.makeValidName(omega), reshape(X1, [], 1), ...
        matlab.lang.makeValidName(sepVar), reshape(S, 1, [])));
end

if config.surfaceDiagnostics
    terminal = methods.smoothed.surfaceComplexity(R1);
else
    terminal = struct('verdict', "not measured", ...
        'reason', "config.surfaceDiagnostics is false");
end
end
