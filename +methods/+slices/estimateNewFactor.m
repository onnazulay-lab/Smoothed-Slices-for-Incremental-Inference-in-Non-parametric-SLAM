function [fnew, info] = estimateNewFactor(omega, separator, removedFactors, config, graph)
%ESTIMATENEWFACTOR Algorithm S2: build f_new_hat(S_j | D_j) by slices.
%
%   Inputs
%     OMEGA           the variable being eliminated
%     SEPARATOR       its separator S_j
%     REMOVEDFACTORS  F_{j-1}(omega_j)
%     CONFIG          the method config; innerEstimator selects the route
%     GRAPH           the graph, for the separator's own range
%
%   Outputs
%     FNEW   the generated separator factor
%     INFO   which route was taken, the sampling factor, the inner estimator,
%           the cardinalities and the elapsed time
%
%   Utility
%     Build the generated separator factor, by whichever of the two routes
%     the variable admits.
%
%   Two routes, selected by slices.lemma1Sampler:
%
%   UNARY ROUTE (Eq. S8). Draw omega^(n) from the unary factor f' and keep a
%   lazy mixture of slices. Nothing is evaluated until the factor is queried,
%   which is what lets the first elimination stay exact in the separator.
%
%   LEMMA-1 ROUTE (Eq. S13-S14 / Eq. 19-23). OMEGA has no unary factor and is
%   sampled through the slices of a previously generated factor. Writing the
%   removed factors as
%
%       b_0(xi_0, s)      front factors: outer variable to final separator
%       g_0(xi_0, omega)  sampling factor: makes omega sampleable
%       a  (omega,  s)    fusion factors: omega to final separator
%
%   the target is
%
%       f_new_hat(s) = (c_0/N_0) sum_n b_0(xi_0^(n), s) R(xi_0^(n), s),
%       R(xi_0, s)   = int g_0(xi_0, l) a(l, s) dl                    (Eq. 26)
%
%   and the two methods differ ONLY in how R is estimated. CONFIG.innerEstimator
%   selects it:
%
%       "nested"  Eq. (23): draw M samples of omega per outer sample and
%                 average a(.,s) over them. This is the Slices paper.
%       "rcs"     Eq. (50): evaluate R on a finite support by the sparse
%                 conditional-smoothing recursion. This is Smoothed Slices.
%
%   Keeping one function for both is deliberate: it guarantees the two
%   methods share the same outer samples, the same separator support and the
%   same front factors, so a measured difference between them is a difference
%   in the inner estimator and nothing else.

arguments
    omega (1,1) string
    separator (1,:) string
    removedFactors (1,:) core.Factor
    config (1,1) struct
    graph (1,1) core.FactorGraph
end

t0    = tic;
route = methods.slices.lemma1Sampler(omega, removedFactors);

info = struct();
info.route            = route.kind;
info.samplingFactor   = route.factor.Name;
info.innerEstimator   = "none";
info.numOuterSamples  = 0;
info.numInnerSamples  = 0;
info.separatorSupport = 0;

switch route.kind
    % =====================================================================
    case "unary"
    % =====================================================================
        N = config.numSamples;
        smp  = route.factor.sample(omega, struct(), N);
        smp  = reshape(smp, [], 1);
        logZ = route.factor.logNormalizer(omega, struct());

        fnew = core.ApproximateFactor(separator, omega, smp, route.others, ...
            'SourceFactorName', route.factor.Name, ...
            'LogScale', sum(logZ(:)), ...
            'Counter', graph.Counter, ...
            'Diagnostics', struct('route', "unary", 'numSamples', N));

        info.numOuterSamples = N;
        info.samplingRoute   = "unary factor " + route.factor.Name;

    % =====================================================================
    case "lemma1"
    % =====================================================================
        af = route.approximate;

        if numel(separator) ~= 1
            error('methods:slices:multiDimSeparator', ...
                ['The Lemma-1 route currently supports a 1-D final separator; ' ...
                 'S_j = {%s}. Multi-dimensional separators arrive with the ' ...
                 '2-D SLAM case study.'], strjoin(cellstr(separator), ','));
        end
        sepVar = separator(1);

        % Finite separator support S, |S| = R_s.
        S  = methods.slices.separatorSupport(graph, sepVar, config);
        Rs = numel(S);

        % Decompose the removed factors into b_0, g_0 and a.
        g0    = route.factor;                       % xi_0 -> omega
        front = af.sliceFactorsExcluding(omega);    % b_0(xi_0, s)
        fuse  = route.others;                       % a(omega, s)

        xi0 = af.Samples;                           % X_0, |X_0| = N_0
        N0  = numel(xi0);

        % b_0(xi_0^(n), s) : |X_0| x |S|
        B = ones(N0, 1);
        for i = 1:numel(front)
            B = B .* front(i).evaluate(struct( ...
                matlab.lang.makeValidName(af.EliminatedVar), xi0, ...
                matlab.lang.makeValidName(sepVar), S));
        end

        % R(xi_0^(n), s) : |X_0| x |S|, by the selected inner estimator.
        switch string(config.innerEstimator)
            case "nested"
                [R, innerInfo] = methods.slices.innerNestedEstimate( ...
                    af, g0, fuse, omega, sepVar, S, config);
            case "rcs"
                [R, innerInfo] = methods.smoothed.evaluateSurfaceRecursion( ...
                    af, g0, fuse, omega, sepVar, S, config);
            otherwise
                error('methods:slices:unknownInnerEstimator', ...
                    'Unknown innerEstimator "%s".', config.innerEstimator);
        end

        sliceMatrix = B .* R;

        fnew = core.ApproximateFactor.tabulated(separator, omega, S, sliceMatrix, ...
            'OuterSamples', xi0, ...
            'LogScale', af.LogScale, ...
            'SourceFactorName', route.factor.Name, ...
            'Counter', graph.Counter, ...
            'Diagnostics', struct( ...
                'route', "lemma1", ...
                'outerVar', af.EliminatedVar, ...
                'frontFactors', localNames(front), ...
                'samplingFactor', g0.Name, ...
                'fusionFactors', localNames(fuse), ...
                'inner', innerInfo));

        info.numOuterSamples  = N0;
        info.numInnerSamples  = innerInfo.numInnerSamples;
        info.separatorSupport = Rs;
        info.innerEstimator   = string(config.innerEstimator);
        info.samplingRoute    = "Lemma 1 through slices of " + af.describe();
        info.inner            = innerInfo;
end

info.elapsed = toc(t0);
end

% -------------------------------------------------------------------------
function names = localNames(factors)
%LOCALNAMES The names of a factor array, for the trace.
%   Inputs   FACTORS, a core.Factor array
%   Outputs  NAMES, a string array
%   Utility  record WHICH factors a step consumed, not just how many.
if isempty(factors)
    names = string.empty(1,0);
else
    names = [factors.Name];
end
end
