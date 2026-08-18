function cond = rootConditional(removedFactors, omega, step, counter)
%ROOTCONDITIONAL The conditional of the last eliminated variable.
%
%   Inputs
%     REMOVEDFACTORS  the factors still standing at the last elimination
%     OMEGA           the last variable
%     STEP            the elimination step, for the trace
%     COUNTER         the factor-evaluation counter            default []
%
%   Outputs
%     COND            the core.ConditionalFactor the backward pass starts at
%
%   Utility
%     Start Algorithm S4's backward pass.
%
%   The final elimination has an empty separator, so Eq. (S5) degenerates to
%
%       P_joint(omega | D) = P(omega | D) * f_new(empty),
%
%   where f_new(empty) is the scalar mass. The conditional is therefore the
%   product of the remaining factors, normalized numerically when it is first
%   displayed or sampled. Algorithm S4 starts the backward pass here.

arguments
    removedFactors (1,:) core.Factor
    omega (1,1) string
    step (1,1) double
    counter = []
end

cond = core.ConditionalFactor(omega, string.empty(1,0), removedFactors, [], ...
    'Step', step, 'Counter', counter);
end
