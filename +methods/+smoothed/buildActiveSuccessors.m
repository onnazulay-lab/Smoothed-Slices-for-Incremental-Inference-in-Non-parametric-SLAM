function [P, active, info] = buildActiveSuccessors(W, config)
%BUILDACTIVESUCCESSORS Active successor sets N_r(a) and weights P_r (Eq. 49).
%
%   Inputs
%     W       the dense unnormalized transition weights, |X_r| x |X_{r+1}|
%     CONFIG  carrying activeSetSize K and activeSetRule
%
%   Outputs
%     P       the row-stochastic transition matrix, sparse when K is finite
%     ACTIVE  one index list per row, the successor set N_r(a)
%     INFO    the retained mass summary, K, the rule, and the union over rows
%
%   Utility
%     Turn dense transition weights into a matrix supported on K successors
%     per row, which is the sparsification the cost model is written for.
%
%   Selection rules, all listed in specification section 11.1:
%     "transition"  keep the K highest transition weights   (default)
%     "nearest"     keep the K nearest successors by weight rank from the
%                   row maximum, i.e. a contiguous neighbourhood
%     "random"      keep K uniformly at random, as a control
%
%   Rows are renormalized over their active set, which section 11.1 requires
%   explicitly: without it the sparsification silently loses mass and the
%   surface is biased low rather than merely coarse.
%
%   K = Inf selects the dense update of Eq. (48). Comparing dense against
%   sparse on the same support is how the app separates "the recursion is
%   wrong" from "the active set is too small".

arguments
    W (:,:) double
    config (1,1) struct
end

[B0, B1] = size(W);
K = config.activeSetSize;

if isinf(K) || K >= B1
    % Dense update, Eq. (48).
    rowSum = sum(W, 2);
    P = W ./ max(rowSum, realmin);
    P(rowSum <= 0, :) = 0;
    active = repmat({(1:B1).'}, B0, 1);
    % The same field set as the sparse branch, built by the same function. It
    % used to be a shorter struct, and nothing broke only because both
    % consumers happened to guard every field they read.
    info = localInfo(ones(B0, 1), B1, "dense (Eq. 48)", false, B1, B1);
    return
end

K = round(K);
active = cell(B0, 1);
rows = zeros(B0 * K, 1);
cols = zeros(B0 * K, 1);
vals = zeros(B0 * K, 1);

retained = zeros(B0, 1);
totalMass = sum(W, 2);

for a = 1:B0
    w = W(a, :);
    switch config.activeSetRule
        case "transition"
            [~, ord] = sort(w, 'descend');
            idx = ord(1:K);
        case "nearest"
            [~, peak] = max(w);
            half = floor(K / 2);
            lo = max(1, min(peak - half, B1 - K + 1));
            idx = lo:(lo + K - 1);
        case "random"
            idx = randperm(B1, K);
    end
    idx = sort(idx(:));

    wk = w(idx);
    s  = sum(wk);
    if totalMass(a) > 0
        retained(a) = s / totalMass(a);
    else
        retained(a) = 0;
    end

    if s > 0
        wk = wk / s;              % renormalize over the active set
    else
        wk = zeros(size(wk));
    end

    span = (a-1)*K + (1:K);
    rows(span) = a;
    cols(span) = idx;
    vals(span) = wk;
    active{a}  = idx;
end

P = sparse(rows, cols, vals, B0, B1);

% --- How many successors the whole update actually touches ----------------
% DENSITY IS PER ROW AND IS NOT THE SAVING. Each row keeps K of B1, but the
% terminal surface R_1 is evaluated once per support point, not once per
% (row, point) pair, so what a sparse update could ever save is set by the
% UNION of the active sets over rows, not by K. The two coincide only when
% every row keeps the SAME successors; as soon as the rows disagree the union
% runs ahead of K, and at the limit -- every row keeping a different K -- it
% is B1 again and nothing is saved however small K is.
%
% AND THE MEASURED CASE SITS BETWEEN THOSE LIMITS, NEARER THE BAD ONE. On the
% multimodal two-pose case at |X_1| = 120 the union does fall, so the earlier
% reading of this comment -- that it stays pinned at B1 -- was wrong. But it
% falls far more slowly than the density: K = 2 keeps 1.7% of each row while
% touching 21.7% of X_1, a factor of 13 between the saving quoted per row and
% the one actually available, and by K = 64 the union has saturated at B1
% exactly while the density still reads 53%. Across K = 2..64 the density
% spans 32x and the union only 4.6x. So the density is not merely a different
% number from the saving, it is an optimistic one, and the gap widens as K
% shrinks -- precisely where a sparsification looks most attractive.
%
% Reported so the distinction is measured rather than argued.
unionSize = numel(unique(cols));

info = localInfo(retained, K, config.activeSetRule, true, unionSize, B1);
end

% =========================================================================
function info = localInfo(retained, K, rule, isSparse, unionSize, B1)
%LOCALINFO The diagnostics struct, one shape for both branches.
%   Inputs   RETAINED per-row kept fraction; K; RULE; ISSPARSE; UNIONSIZE; B1
%   Outputs  INFO, the summary plus this route's own fields
%   Utility  keep the dense and sparse branches from returning different
%            field sets, which is what forced every consumer to guard.
%
%   IndexedOver, Renormalized and IsEq49 are stated rather than defaulted,
%   because THIS is the route they are true of and the general engine's
%   separator truncation reports the same field names with the opposite
%   values. Being explicit here is what makes the two comparable.
info = utils.retainedMassSummary(retained, ...
    'IndexedOver',  "successors", ...
    'Renormalized', true, ...
    'IsEq49',       true);

info.applied       = isSparse;
info.K             = K;
info.activeSetSize = K;     % the name the exports and the app already read
info.rule          = rule;
info.sparse        = isSparse;
info.density       = K / B1;
info.unionSize     = unionSize;
info.unionFraction = unionSize / B1;

% Kept because callers and saved run_state.mat files read them by these names.
info.meanRetainedMass = info.retainedMassMean;
info.minRetainedMass  = info.retainedMassMin;
end
