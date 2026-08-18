function out = backwardSampleGeneral(conditionals, root, caseData, config, opts)
%BACKWARDSAMPLEGENERAL Joint posterior samples by root-to-leaf traversal.
%
%   Inputs
%     CONDITIONALS  the Bayes net from the forward pass
%     ROOT          the root marginal
%     CASEDATA      the case
%     CONFIG        carrying numBackwardSamples
%     Previous      the previous increment's marginals, for early stopping
%     EarlyStop     apply Algorithm S5 steps 5-7            default false
%
%   Outputs
%     OUT.joint           one coherent hypothesis per row
%     OUT.numSamples      how many were drawn
%     OUT.variableNames, OUT.variableDims   the joint's column layout
%     OUT.marginals       per-variable sample sets
%     OUT.earlyStop       where the stopping boundary fell, if it did
%     OUT.lookupDistance  how far off-support the generated factors were read
%
%   Utility
%     Draw joint samples of every variable in the graph.
%
%   The Bayes net factorizes as prod_j p(omega_j | S_j), and every variable
%   in S_j was eliminated AFTER omega_j. So the sampling order is the
%   elimination order reversed: the last variable eliminated has an empty
%   separator and is drawn from the root marginal, and by the time step j is
%   reached its whole separator has already been assigned.
%
%   The samples are JOINT. Each row of OUT.joint is one coherent hypothesis
%   about the entire trajectory and map, not a stack of independently drawn
%   marginals. That distinction is the whole point: a per-variable marginal
%   cannot show that a pose being at the far door implies the landmark is on
%   the near side, and a comparison that loses the correlation cannot
%   demonstrate posterior recovery at all.
%
%   EARLY STOPPING (Algorithm S5, steps 5-7). With PREVIOUS set to the
%   marginals of the previous increment and EARLYSTOP on, each variable's
%   fresh samples are compared to its old ones by MMD as the traversal walks
%   back through the trajectory. When the discrepancy falls below vartheta the
%   traversal stops and the remaining variables keep the samples they already
%   had: the new measurement did not reach that far back, so re-deriving those
%   poses would spend the whole cost of the lookup to reproduce the answer.
%
%   The traversal order is what makes this legitimate. The last variable
%   eliminated is the newest pose, so root-to-leaf is newest-to-oldest, and
%   "stop when it stops changing" walks backwards in TIME as well as in the
%   ordering.
%
%   WHAT IT COSTS. The reused samples come from the previous increment's
%   joint, so the correlation ACROSS the stopping boundary is broken: rows of
%   an old pose and rows of a new one are no longer one hypothesis. That is
%   the approximation the rule makes, it is why OUT.earlyStop reports where
%   the boundary fell, and it is why the rule is off unless asked for.

arguments
    conditionals (1,:) core.SliceConditional
    root (1,1) struct
    caseData (1,1) struct
    config (1,1) struct
    opts.Previous (1,1) struct = struct()
    opts.EarlyStop (1,1) logical = false
end

n = config.numBackwardSamples;

names = caseData.graph.VariableNames;
dims = arrayfun(@(v) v.Dim, caseData.graph.Variables);
joint = struct();
for i = 1:numel(names)
    joint.(matlab.lang.makeValidName(names(i))) = nan(n, dims(i));
end

% --- Root ----------------------------------------------------------------
% The last generated factor, on its own support, weighted by f_new/q.
idx = core.categoricalSample(root.weights(:), n);
col = 0;
for i = 1:numel(root.variable)
    key = matlab.lang.makeValidName(root.variable(i));
    joint.(key) = root.support(idx, col + (1:root.dims(i)));
    col = col + root.dims(i);
end

% --- Leafward traversal ---------------------------------------------------
earlyStop = localNewStopRecord(opts.EarlyStop, config);
patience = 1;
if isfield(config, 'mmdStopPatience'), patience = config.mmdStopPatience; end
consecutive = 0;

lookupDistance = zeros(n, numel(conditionals));
sampled = false(1, numel(conditionals));
stopAt = 0;

p = utils.progressOf(config);
nC = numel(conditionals);

for c = nC:-1:1
    cond = conditionals(c);
    p.report((nC - c) / nC, sprintf("sampling %s (%d of %d)", ...
        cond.FrontalVar, nC - c + 1, nC));

    sepVals = zeros(n, sum(cond.SeparatorDims));
    col = 0;
    for i = 1:numel(cond.Separator)
        key = matlab.lang.makeValidName(cond.Separator(i));
        v = joint.(key);
        if any(isnan(v(:)))
            error('methods:general:separatorNotYetSampled', ...
                ['Conditional %d needs %s, which has not been sampled. The ' ...
                 'traversal order does not match the elimination order.'], ...
                c, cond.Separator(i));
        end
        sepVals(:, col + (1:cond.SeparatorDims(i))) = v;
        col = col + cond.SeparatorDims(i);
    end

    [vals, ~, dist] = cond.sample(sepVals);
    joint.(matlab.lang.makeValidName(cond.FrontalVar)) = vals;
    lookupDistance(:, c) = dist;
    sampled(c) = true;

    if ~opts.EarlyStop, continue, end

    prev = localPrevious(opts.Previous, cond.FrontalVar, size(vals, 2));
    if isempty(prev)
        % A variable this increment introduced has nothing to be compared
        % with, and a variable that never converged cannot be said to have
        % converged. Both reset the run of quiet steps.
        consecutive = 0;
        continue
    end

    [stop, d, info] = methods.slices.mmdEarlyStop( ...
        struct('samples', prev), struct('samples', vals), config);
    earlyStop.perVariable(end+1) = struct( ...
        'variable', cond.FrontalVar, 'step', c, 'mmd', d, ...
        'mmdSquaredRaw', info.mmdSquaredRaw, ...
        'indistinguishable', info.indistinguishable, ...
        'threshold', info.threshold, 'below', stop); %#ok<AGROW>
    earlyStop.kernel = info.kernel;
    earlyStop.bandwidth = info.bandwidth;
    earlyStop.estimator = info.estimator;
    earlyStop.numSamples = info.numSamples;

    if ~stop
        consecutive = 0;
        continue
    end

    consecutive = consecutive + 1;
    if consecutive < patience, continue, end

    % Everything still ahead must have somewhere to be copied from. One
    % uncovered variable is enough to make stopping wrong rather than
    % approximate, so the run continues and says why.
    [covered, missing] = localRemainderCovered(conditionals(1:c-1), opts.Previous);
    if ~covered
        earlyStop.blockedBy = missing;
        consecutive = 0;
        continue
    end

    stopAt = c;
    earlyStop.applied = true;
    earlyStop.stoppedAtStep = c;
    earlyStop.stoppedAtVariable = cond.FrontalVar;
    earlyStop.mmdAtStop = d;
    earlyStop.mmdSquaredAtStop = info.mmdSquaredRaw;
    earlyStop.indistinguishableAtStop = info.indistinguishable;
    break
end

% --- Reuse the tail -------------------------------------------------------
reused = string.empty(1, 0);
if stopAt > 0
    for c = (stopAt - 1):-1:1
        name = conditionals(c).FrontalVar;
        key = matlab.lang.makeValidName(name);
        joint.(key) = localResize(opts.Previous.(key), n);
        reused(end+1) = name; %#ok<AGROW>
    end
end
earlyStop.reusedVariables = reused;
earlyStop.numReused = numel(reused);
earlyStop.numResampled = nnz(sampled);

% --- Pack ----------------------------------------------------------------
out = struct();
out.joint = joint;
out.numSamples = n;
out.variableNames = names;
out.variableDims = dims;
out.earlyStop = earlyStop;

% Per-variable marginals are views on the joint, kept so plotting code does
% not have to know the traversal order.
out.marginals = struct();
for i = 1:numel(names)
    key = matlab.lang.makeValidName(names(i));
    out.marginals.(key) = joint.(key);
end

% How far the nearest-neighbour conditioning had to reach. A large value
% means the support did not cover where the traversal actually went, which
% is the failure this representation is prone to and the one a picture of
% the posterior will not reveal.
%
% Averaged over the steps that were actually sampled. Counting a skipped step
% as a zero-distance lookup would make early stopping look like it improved
% the health of the estimate, when all it did was decline to measure it.
D = lookupDistance(:, sampled);
if isempty(D), D = zeros(n, 1); end
out.lookupDistance = struct( ...
    'mean',   mean(D(:)), ...
    'max',    max(D(:)), ...
    'perStep', mean(lookupDistance, 1), ...
    'numStepsSampled', nnz(sampled), ...
    'numSteps', numel(conditionals));
end

% =========================================================================
function rec = localNewStopRecord(enabled, config)
%LOCALNEWSTOPRECORD The early-stopping record, before the traversal runs.
%   Inputs   ENABLED whether the rule is on, CONFIG for its threshold
%   Outputs  REC, with every field present
%   Utility  a run that never stops and a run with the rule off must report
%           the same field set, or a reader cannot tell them apart.
rec = struct( ...
    'enabled', enabled, ...
    'applied', false, ...
    'stoppedAtStep', 0, ...
    'stoppedAtVariable', "", ...
    'mmdAtStop', NaN, ...
    'mmdSquaredAtStop', NaN, ...
    'indistinguishableAtStop', false, ...
    'threshold', config.mmdThreshold, ...
    'numSamples', config.mmdSamples, ...
    'kernel', config.mmdKernel, ...
    'bandwidth', config.mmdBandwidth, ...
    'estimator', config.mmdEstimator, ...
    'blockedBy', string.empty(1, 0), ...
    'reusedVariables', string.empty(1, 0), ...
    'numReused', 0, ...
    'numResampled', 0, ...
    'perVariable', struct('variable', {}, 'step', {}, 'mmd', {}, ...
                          'mmdSquaredRaw', {}, 'indistinguishable', {}, ...
                          'threshold', {}, 'below', {}));
end

% =========================================================================
function P = localPrevious(previous, name, d)
%LOCALPREVIOUS One variable's samples from the previous increment, or [].
%   Inputs   PREVIOUS the previous marginals, NAME the variable, D its width
%   Outputs  P, the samples, or [] when the variable is new
%   Utility  a variable the previous increment did not hold cannot be
%           compared, and must not be silently treated as unchanged.
P = [];
key = matlab.lang.makeValidName(name);
if ~isfield(previous, key), return, end
P = previous.(key);
if isempty(P) || size(P, 2) ~= d || size(P, 1) < 2 || any(isnan(P(:)))
    P = [];
end
end

% =========================================================================
function [ok, missing] = localRemainderCovered(remaining, previous)
%LOCALREMAINDERCOVERED Can every variable behind the boundary be reused?
%   Inputs   REMAINING the variables the stop would skip, PREVIOUS the
%           previous marginals
%   Outputs  OK whether all are available, MISSING the ones that are not
%   Utility  stopping is only legitimate if there is something to keep; one
%           uncovered variable behind the boundary forbids the stop.
missing = string.empty(1, 0);
for i = 1:numel(remaining)
    key = matlab.lang.makeValidName(remaining(i).FrontalVar);
    if ~isfield(previous, key) || isempty(previous.(key)) ...
            || any(isnan(previous.(key)(:)))
        missing(end+1) = remaining(i).FrontalVar; %#ok<AGROW>
    end
end
ok = isempty(missing);
end

% =========================================================================
function Y = localResize(X, n)
%LOCALRESIZE A reused sample set adjusted to this increment's sample count.
%   Inputs   X the previous samples, N how many rows are wanted
%   Outputs  Y, N rows
%   Utility  the two increments need not have drawn the same number, and a
%           marginal of a different height cannot sit in the same joint.
%
%   The row COUNT is a budget, not information: these samples were drawn at
%   the previous increment and reusing them is the whole point. Resampling
%   with replacement when the previous run was smaller adds no information and
%   pretends to none.
m = size(X, 1);
if m == n
    Y = X;
elseif m > n
    Y = X(1:n, :);
else
    Y = X(randi(m, n, 1), :);
end
end
