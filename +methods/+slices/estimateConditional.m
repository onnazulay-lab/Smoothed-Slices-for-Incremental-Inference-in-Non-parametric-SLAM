function cond = estimateConditional(omega, separator, removedFactors, fnew, step, counter)
%ESTIMATECONDITIONAL Algorithm S3: build P_hat(omega_j | S_j, D_j).
%
%   Inputs
%     OMEGA           the eliminated variable
%     SEPARATOR       its separator S_j
%     REMOVEDFACTORS  F_{j-1}(omega_j), all of them
%     FNEW            the generated factor f_new_hat
%     STEP            the elimination step, for the trace       default 0
%     COUNTER         the factor-evaluation counter            default []
%
%   Outputs
%     COND            the core.ConditionalFactor
%
%   Utility
%     Build Eq. (S15) / paper Eq. (17):
%
%       P_hat(omega | s) = prod_{f in F_{j-1}(omega)} f(omega, s) / f_new_hat(s)
%
%   The numerator uses ALL removed factors, including the one used as the
%   sampling source. That is not an oversight in the paper: f' is excluded
%   only from the ESTIMATOR of f_new, never from the local joint. The
%   normalizer eta_j^{-1} appears above and below and is therefore never
%   computed, which is why ApproximateFactor records its scale as relative.

arguments
    omega (1,1) string
    separator (1,:) string
    removedFactors (1,:) core.Factor
    fnew (1,1) core.ApproximateFactor
    step (1,1) double = 0
    counter = []
end

cond = core.ConditionalFactor(omega, separator, removedFactors, fnew, ...
    'Step', step, 'Counter', counter);
end
