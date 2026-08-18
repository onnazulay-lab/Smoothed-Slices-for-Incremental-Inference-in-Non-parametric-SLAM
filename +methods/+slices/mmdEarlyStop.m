function [stop, d, info] = mmdEarlyStop(oldMarginal, newMarginal, config)
%MMDEARLYSTOP The backward-pass stopping rule of Algorithm S5, steps 5-7.
%
%   Inputs
%     OLDMARGINAL  the previous increment's marginal
%     NEWMARGINAL  this increment's marginal
%                  -- either form, see below
%     CONFIG       carrying mmdSamples N_M and mmdThreshold vartheta
%
%   Outputs
%     STOP   whether the rule fires
%     D      the MMD itself
%     INFO   the kernel, the estimator, N_M and where each sample set came
%            from
%
%   Utility
%     Apply the stopping rule
%
%       stop = MMD(P_new, P_old) < vartheta
%
%   The paper fixes N_M = 100 and vartheta = 1e-4 for Plaza2 but does NOT
%   specify the kernel or the biased/unbiased estimator. Those are therefore
%   configuration, and are reported in INFO so that any published number
%   carries the assumption that produced it.
%
%   TWO WAYS TO PASS A MARGINAL. Either
%
%       struct('grid', g, 'pdf', p)     a tabulated 1-D density
%       struct('samples', X)            an n-by-d sample set
%
%   The tabulated form is what the three-node engine holds and is sampled by
%   inverse CDF. The sample form is what the general engine's backward pass
%   produces, and it is the form the incremental re-elimination loop compares:
%   a pose on the grid world is planar, and a rule that only accepted a 1-D
%   grid could not be applied to the case it was needed for. The rule itself
%   is identical either way, which is why both live in this one function
%   rather than in two that could drift apart.
%
%   Sample sets larger than N_M are SUBSAMPLED rather than used whole. N_M is
%   the paper's budget for a cheap online test, and spending the full backward
%   sample on it would change the test's operating point -- the same MMD value
%   means something different at n = 400 than at n = 100.

arguments
    oldMarginal (1,1) struct
    newMarginal (1,1) struct
    config (1,1) struct
end

nM = config.mmdSamples;

[X, sourceOld] = localDraw(oldMarginal, nM);
[Y, sourceNew] = localDraw(newMarginal, nM);

[d, mmdInfo] = metrics.computeMMD(X, Y, ...
    'Kernel', config.mmdKernel, ...
    'Bandwidth', config.mmdBandwidth, ...
    'Estimator', config.mmdEstimator);

% THE COMPARISON IS MADE IN SQUARED UNITS, on the UNCLAMPED estimate.
%
% computeMMD returns sqrt(max(MMD^2, 0)) because a negative MMD is not a
% distance and should not be displayed as one. Testing that clamped value
% against vartheta would make every negative estimate compare equal to zero
% and stop unconditionally, which reads as a threshold that works and is
% really a threshold that is never consulted. The U-statistic is unbiased for
% MMD^2, not for MMD, so the honest test is MMD^2 < vartheta^2 with the raw
% value -- and a negative raw value then means what it should: at N_M samples
% the two sets are not separable, so the marginal has stopped moving as far
% as this budget can tell.
%
% That distinction is not academic here. At the paper's N_M = 100 the
% sampling noise on MMD^2 is of order 1/N_M, so vartheta = 1e-4 sits far
% below the noise floor for BOTH estimators: no pair of genuinely different
% marginals can be told apart at that threshold, and every stop the rule
% makes is a stop on an estimate that went negative. INDISTINGUISHABLE
% records exactly that, so a run can report how many of its stops were
% decisions and how many were the estimator giving up.
stop = mmdInfo.mmdSquaredRaw < config.mmdThreshold^2;

info = struct( ...
    'mmd',        d, ...
    'mmdSquaredRaw', mmdInfo.mmdSquaredRaw, ...
    'indistinguishable', mmdInfo.mmdSquaredRaw < 0, ...
    'threshold',  config.mmdThreshold, ...
    'numSamples', nM, ...
    'numX',       mmdInfo.numX, ...
    'numY',       mmdInfo.numY, ...
    'dim',        size(X, 2), ...
    'source',     sourceOld + "/" + sourceNew, ...
    'stop',       stop, ...
    'kernel',     mmdInfo.kernel, ...
    'bandwidth',  mmdInfo.bandwidth, ...
    'estimator',  mmdInfo.estimator, ...
    'paperSpecified', "threshold and sample count only; kernel is an implementation choice");
end

% =========================================================================
function [Z, source] = localDraw(marginal, nM)
%LOCALDRAW N_M samples from a marginal, in either of the two forms.
%   Inputs   MARGINAL the marginal, NM how many samples
%   Outputs  Z the samples, SOURCE which form it was given in
%   Utility  accept a tabulated density or a sample set, so the same rule
%           applies to the three-node engine and the general one.
if isfield(marginal, 'samples')
    Z = marginal.samples;
    if isrow(Z), Z = Z(:); end
    source = "samples";
    n = size(Z, 1);
    if n > nM
        % Without replacement: drawing with replacement would put duplicate
        % points in both sets and pull the median-heuristic bandwidth down.
        Z = Z(randperm(n, nM), :);
    end
    return
end

if ~isfield(marginal, 'grid') || ~isfield(marginal, 'pdf')
    error('methods:slices:mmdEarlyStop:badMarginal', ...
        ['A marginal must carry either SAMPLES or a GRID and PDF pair; ' ...
         'got fields %s.'], strjoin(fieldnames(marginal), ', '));
end

Z = core.ConditionalFactor.inverseCdfSample( ...
        marginal.grid(:), marginal.pdf(:), nM);
source = "grid";
end
