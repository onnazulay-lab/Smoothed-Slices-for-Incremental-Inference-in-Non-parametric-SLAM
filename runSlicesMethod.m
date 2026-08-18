function result = runSlicesMethod(caseData, config)
%RUNSLICESMETHOD The Slices Perspective method, on whichever engine the case selects.
%
%   Inputs
%     CASEDATA  the case; its engine tag selects the route
%     CONFIG    the method config
%
%   Outputs
%     RESULT    the unified result contract of specification section 8,
%               including the implementation record that qualifies it
%
%   Utility
%     Run Algorithms S1-S4 with the paper's nested inner estimator, Eq. (23).
%
%   HOW FAITHFUL THIS IS DEPENDS ON THE CASE, so the answer is not in this
%   comment -- it is in result.implementation, which the driver fills in from
%   the engine that actually ran. This header used to read "reproduced
%   faithfully" full stop, and that was true of only one of the two routes:
%
%     A three-node case follows Algorithm S1 literally and is validated against
%     dense quadrature. That route can claim the paper.
%
%     A case with engine == "general" reaches runGeneralCore instead, which is
%     importance sampling with per-variable proposal densities and a finite
%     separator support lookup. The paper does not describe that, and it is
%     measurably not free of consequences: minimum essSupport falls to 1.0 of
%     201 on the Plaza1 lap window. It is an implementation generalization.
%
%   Both routes are reached through this same function and the same method
%   name, which is exactly why the qualification has to be attached to the
%   result rather than written down here once.
%
%   No KDE and no flow appear anywhere in this path: f_new is a mixture of
%   slices, the conditional is a ratio of factor products, and the backward
%   marginals are mixtures of conditional slices. The Slices spec section 13
%   lists each of those as a "do not do" if replaced by a reconstruction, and
%   the whole point of the comparison is that this method does not
%   reconstruct anything. That much holds on both engines.

arguments
    caseData (1,1) struct
    config (1,1) struct = methods.commonMethodConfig()
end

config.innerEstimator = "nested";
result = methods.runInferenceCore("Slices", caseData, config);
end
