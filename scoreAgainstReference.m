function result = scoreAgainstReference(result, ref, config)
%SCOREAGAINSTREFERENCE Attach error metrics computed against ground truth.
%
%   Inputs
%     RESULT  a method result
%     REF     the quadrature reference
%     CONFIG  the method config, for the MMD settings
%
%   Outputs
%     RESULT, with the error fields of the unified metrics block filled in:
%       relL1Error / relL2Error   on the unnormalized f_new(x2)
%       massError                 relative error of the total mass
%       mmd                       posterior-shape distance to reference
%                                 samples
%       rmse                      posterior mean against the reference mean
%       ess                       effective sample size of the outer slices
%
%   Utility
%     Score a run against the exact answer, on the one case that has one.
%
%   The pairing of RMSE with MMD is deliberate. RMSE alone is the metric the
%   specification warns can hide a wrong posterior SHAPE; on the multimodal
%   variant a method can collapse a mode, keep the mean, and score well.

arguments
    result (1,1) struct
    ref (1,1) struct
    config (1,1) struct
end

if result.status ~= "ok"
    return
end

est = result.posterior.estimator;

% NORMALIZED ESTIMATES ARE COMPARED AGAINST THE NORMALIZED REFERENCE. The
% elimination methods return the unnormalized generated factor of Eq. (19)
% and their mass is a result in its own right. NF-iSAM returns a flow, which
% is a density: it has no unnormalized counterpart to report, and scoring its
% curve against ref.fnew would measure the reference's normalizer rather than
% the method. A method that declares itself normalized is therefore scored on
% shape and reports no mass error, rather than a large one it cannot avoid.
normalized = isfield(est, 'normalized') && est.normalized;
if normalized
    estCurve = est.pdf;
    refCurve = ref.pdf;
else
    estCurve = est.fnew;
    refCurve = ref.fnew;
end

% --- Pointwise error on the generated factor ------------------------------
if isequal(size(est.support), size(ref.x2)) && max(abs(est.support - ref.x2)) < 1e-12
    e   = estCurve - refCurve;
    den = refCurve;
else
    % Fall back to interpolating the reference onto the estimate's support.
    refOn = interp1(ref.x2, refCurve, est.support, 'linear', 0);
    e     = estCurve - refOn;
    den   = refOn;
end

result.metrics.relL1Error = sum(abs(e)) / sum(abs(den));
result.metrics.relL2Error = norm(e) / norm(den);
result.metrics.maxAbsError = max(abs(e));
result.metrics.normalizedComparison = normalized;
if normalized
    result.metrics.massError = NaN;
else
    result.metrics.massError = abs(est.mass - ref.mass) / ref.mass;
end

% --- Posterior shape ------------------------------------------------------
targetKey = matlab.lang.makeValidName(est.variable);
if isfield(result.posterior.samples, targetKey)
    smp = result.posterior.samples.(targetKey);
    nM  = min([config.mmdEvalSamples, numel(smp), numel(ref.samples)]);
    [d, mmdInfo] = metrics.computeMMD(smp(1:nM), ref.samples(1:nM), ...
        'Kernel', config.mmdKernel, 'Bandwidth', config.mmdBandwidth, ...
        'Estimator', config.mmdEstimator);
    result.metrics.mmd     = d;
    result.metrics.mmdInfo = mmdInfo;
    % The unbiased estimator legitimately returns a small negative value when
    % the two samples are indistinguishable. Reporting the raw value next to
    % the clamped one keeps a displayed 0 from being mistaken for a stub.
    result.metrics.mmdSquaredRaw = mmdInfo.mmdSquaredRaw;
    result.metrics.mmdClamped    = mmdInfo.clamped;

    marg = result.posterior.marginals.(targetKey);
    [r, rmseInfo] = metrics.computeRMSE(marg.mean, ref.mean);
    result.metrics.rmse     = r;
    result.metrics.rmseInfo = rmseInfo;
end

% --- Weight health of the outer slices ------------------------------------
% Column mass of the slice matrix is the per-sample contribution to f_new at
% the posterior mode, which is the quantity whose degeneracy would make the
% estimator unreliable.
if isfield(est, 'slices') && ~isempty(est.slices)
    [~, peak] = max(est.fnew);
    [essVal, essInfo] = metrics.computeESS(est.slices(:, peak));
    result.metrics.ess     = essVal;
    result.metrics.essInfo = essInfo;
end

result.metrics.reference = struct( ...
    'method', ref.method, 'mass', ref.mass, 'mean', ref.mean, 'std', ref.std);
end
