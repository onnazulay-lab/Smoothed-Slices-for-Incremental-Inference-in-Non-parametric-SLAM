function [r, info] = computeRMSE(estimate, truth)
%COMPUTERMSE Root mean square error against ground truth.
%
%   Inputs
%     ESTIMATE  the empirical posterior mean
%     TRUTH     the reference value
%
%   Outputs
%     R     the RMSE
%     INFO  carries the warning below to wherever the number is displayed
%
%   Utility
%     Report the error against truth, together with what it cannot see.
%
%   Specification section 16 requires this to be reported WITH the warning
%   that it can hide posterior-shape errors, so INFO carries that warning to
%   wherever the number is displayed. On a multimodal posterior the mean can
%   sit in a region of near-zero density, and two methods with identical RMSE
%   can recover completely different distributions -- which is exactly why
%   the app is built around MMD and marginal shape as well.

arguments
    estimate (:,:) double
    truth (:,:) double
end

e = estimate(:) - truth(:);
r = sqrt(mean(e.^2));

info = struct( ...
    'rmse',    r, ...
    'bias',    mean(estimate(:) - truth(:)), ...
    'maxAbs',  max(abs(e)), ...
    'n',       numel(e), ...
    'warning', "RMSE compares point estimates and can hide posterior-shape errors; read it alongside MMD and the marginal curves");
end
