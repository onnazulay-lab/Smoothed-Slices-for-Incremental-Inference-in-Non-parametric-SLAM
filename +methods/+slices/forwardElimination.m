function [bayesNet, states, finalFactor] = forwardElimination(caseData, config)
%FORWARDELIMINATION Algorithm S1: factor graph -> Bayes net by slices.
%
%   Inputs
%     CASEDATA     the case, carrying the graph and the elimination order
%     CONFIG       the method config
%
%   Outputs
%     BAYESNET     the conditionals, in elimination order
%     STATES       one core.EliminationState per step, for the Process
%                  Explorer
%     FINALFACTOR  the scalar mass the last elimination produced
%
%   Utility
%     Run the forward pass. Each step removes one variable, creates one
%     conditional and inserts one generated separator factor.
%
%   Step order, per Algorithm S1:
%     1. identify omega_j in G_{j-1}
%     2. collect removed factors F_{j-1}(omega_j)          (Eq. S2)
%     3. define the separator S_j                          (Eq. S3)
%     4. the local joint is the product of the removed factors (Eq. S4)
%     5. approximate f_new(S_j | D_j) by Algorithm S2       (Eq. S8)
%     6. build the conditional by Algorithm S3              (Eq. S15)
%     7. append the conditional to the Bayes net
%     8. remove omega_j and its factors from G_{j-1}
%     9. insert f_new_hat as a new factor of G_j
%
%   Step 9 is what makes D_{j+1} contain the generated factor rather than the
%   raw measurements, which is the point the paper stresses at Eq. (S12) and
%   which EliminationState records explicitly.
%
%   The last eliminated variable has an empty separator; its generated
%   "factor" is the scalar mass, and its conditional is the root marginal.

arguments
    caseData (1,1) struct
    config (1,1) struct
end

order = caseData.eliminationOrder;
g     = caseData.graph.copy();

% Fail early and clearly if the order cannot satisfy Lemma 1.
caseData.graph.validateEliminationOrder(order);

bayesNet = core.BayesNet();
states   = core.EliminationState.empty(1, 0);
finalFactor = [];

% One elimination step is the finest boundary this pass can be stopped at.
% Reporting BEFORE the step rather than after is what makes the message name
% the variable that is about to cost the time rather than the one that just
% stopped costing it.
p = utils.progressOf(config);

for j = 1:numel(order)
    omega = order(j);
    p.report((j-1) / numel(order), sprintf("eliminating %s (%d of %d)", ...
        omega, j, numel(order)));
    st    = core.EliminationState(j, omega);

    % 2-3. removed factors and separator
    removed   = g.adjacentFactors(omega);
    separator = g.separatorOf(omega);
    st        = st.recordLocalData(removed);
    st.Separator = separator;

    if isempty(removed)
        error('methods:slices:isolatedVariable', ...
            'Variable %s has no adjacent factors at step %d.', omega, j);
    end

    if isempty(separator)
        % Terminal elimination: the "new factor" is a scalar and the
        % conditional is the root marginal, held as the previous step's
        % tabulated factor. Nothing further needs to be generated.
        st.SamplingFactorName = "(terminal)";
        st.SamplingRoute      = "terminal";
        st.Diagnostics        = struct('terminal', true);
        states(end+1) = st; %#ok<AGROW>

        rootCond = methods.slices.rootConditional(removed, omega, j, g.Counter);
        bayesNet = bayesNet.appendConditional(rootCond);
        g.removeVariable(omega);
        continue
    end

    % 5. f_new_hat by Algorithm S2
    [fnew, info] = methods.slices.estimateNewFactor(omega, separator, removed, config, g);
    st.NewFactor          = fnew;
    st.SamplingFactorName = info.samplingFactor;
    st.SamplingRoute      = info.route;
    st.Diagnostics        = info;
    st.Timing             = struct('newFactor', info.elapsed);

    % 6-7. conditional by Algorithm S3
    cond = methods.slices.estimateConditional(omega, separator, removed, fnew, j, g.Counter);
    st.Conditional = cond;
    bayesNet = bayesNet.appendConditional(cond);

    % 8-9. reduce the graph and insert the generated factor
    g.removeVariable(omega);
    g.addFactor(fnew.toFactor());

    finalFactor = fnew;
    states(end+1) = st; %#ok<AGROW>
end
end
