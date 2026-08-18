function [aligned, tf] = alignTrajectory(X, Y, opts)
%ALIGNTRAJECTORY Kabsch-Umeyama rigid alignment of an estimate onto truth.
%
%   Inputs
%     X           the estimate, n-by-2, one pose per row
%     Y           the reference, n-by-2, in the same order
%     Scale       fit an isotropic scale factor              default false
%     Reflection  allow the improper rotation                default false
%
%   Outputs
%     ALIGNED  X mapped through the fitted transform
%     TF       struct with R (2x2), t (1x2), s, rmseBefore and rmseAfter
%
%   Utility
%     Minimise sum ||s*R*x_i + t - y_i||^2, and report the error before and
%     after so the gauge share of it is visible rather than absorbed.
%
%   WHY THIS EXISTS. The Plaza papers report trajectory error after aligning
%   the estimate to the surveyed track, because a range-only solution is only
%   determined up to the gauge freedom the priors do not pin down. Comparing
%   an unaligned estimate against those published numbers compares two
%   different quantities. This case does carry a prior on the first pose, so
%   the alignment here is small -- which is the point: it is reported, not
%   assumed, and TF.rmseBefore next to TF.rmseAfter says how much of the
%   error was gauge and how much was estimation.
%
%   SCALE IS OFF BY DEFAULT AND THAT IS A SUBSTANTIVE CHOICE. Umeyama's
%   estimator includes a scale factor, and turning it on always lowers the
%   reported RMSE. On this data it would be cheating: the measurements are
%   metric ranges in metres, so scale is observable, and a method that got
%   the scale wrong made a real error. Fitting scale would hide exactly the
%   failure the metric exists to catch. Pass Scale=true only when comparing
%   against a source that itself fitted scale.
%
%   REFLECTION IS OFF BY DEFAULT, via the standard determinant correction.
%   The temptation to allow it is specific to this project: range-only
%   posteriors here really are bimodal under reflection, so a mirrored
%   estimate can look like a good fit. But a mirrored trajectory is a
%   different trajectory, not the same one viewed differently, and letting
%   the alignment flip it would report a mode collapse as a success. The
%   bimodality is a finding to be shown -- see viz.plotPlazaContext, which
%   draws the landmark cloud rather than its mean -- not something to be
%   normalised away in the metric.
%
%   Name-value options:
%     Scale       fit an isotropic scale factor          default false
%     Reflection  allow the improper rotation            default false
%
%   See also datasets.makePlazaCase, viz.plotPlazaContext.

arguments
    X (:,2) double
    Y (:,2) double
    opts.Scale (1,1) logical = false
    opts.Reflection (1,1) logical = false
end

if size(X, 1) ~= size(Y, 1)
    error('utils:alignTrajectory:sizeMismatch', ...
        'X has %d rows and Y has %d; alignment needs a correspondence.', ...
        size(X, 1), size(Y, 1));
end

n = size(X, 1);
if n < 2
    error('utils:alignTrajectory:tooFewPoints', ...
        'Alignment needs at least 2 corresponding points, got %d.', n);
end

keep = all(isfinite(X), 2) & all(isfinite(Y), 2);
if nnz(keep) < 2
    error('utils:alignTrajectory:tooFewFinite', ...
        'Only %d of %d correspondences are finite.', nnz(keep), n);
end

% The transform is FITTED on the finite rows only, then APPLIED to all of
% them. Dropping a row from the fit is unavoidable if it is NaN; dropping it
% from the output would silently shorten a trajectory the caller is about to
% plot against its own pose list.
Xf = X(keep, :);
Yf = Y(keep, :);

muX = mean(Xf, 1);
muY = mean(Yf, 1);
Xc = Xf - muX;
Yc = Yf - muY;

% Cross-covariance, then its SVD. This is Kabsch: the optimal rotation is
% V*U' up to the determinant fix below.
H = (Xc' * Yc) / size(Xf, 1);
[U, S, V] = svd(H);

D = eye(2);
if ~opts.Reflection && det(V * U') < 0
    % V*U' came out improper -- a reflection. Flipping the sign on the
    % smallest singular direction is the least-damaging way back to a proper
    % rotation, which is why it is the last diagonal entry and not the first.
    D(end, end) = -1;
end

R = V * D * U';

if opts.Scale
    varX = mean(sum(Xc.^2, 2));
    if varX < eps
        s = 1;   % a stationary estimate has no scale to fit
    else
        s = trace(S * D) / varX;
    end
else
    s = 1;
end

t = muY - s * (R * muX')';

aligned = (s * R * X')' + t;

tf = struct( ...
    'R', R, 't', t, 's', s, ...
    'numPoints', nnz(keep), ...
    'reflected', det(R) < 0, ...
    'rotationDeg', atan2d(R(2,1), R(1,1)), ...
    'rmseBefore', localRms(X(keep,:) - Y(keep,:)), ...
    'rmseAfter',  localRms(aligned(keep,:) - Y(keep,:)));
end

% =========================================================================
function r = localRms(E)
%LOCALRMS Root-mean-square of the per-row residual norms.
%   Inputs   E, an n-by-2 residual matrix
%   Outputs  R, the scalar RMSE
%   Utility  score both sides of the alignment the same way.
r = sqrt(mean(sum(E.^2, 2)));
end
