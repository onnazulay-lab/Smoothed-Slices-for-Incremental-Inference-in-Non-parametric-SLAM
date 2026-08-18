function [y, logDet] = rqSplineTransform(x, params, opts)
%RQSPLINETRANSFORM Monotonic rational-quadratic spline, forward or inverse.
%
%   Inputs
%     X               the column to map, n-by-1; double, single or dlarray
%     PARAMS          one spline per sample:
%                       widths       n-by-K      positive, summing to 2B
%                       heights      n-by-K      positive, summing to 2B
%                       derivatives  n-by-(K+1)  positive
%     Inverse         solve the spline backwards                default false
%     Bound           the support [-B, B]                       default 5
%     MinDerivative   the positivity floor                      default 1e-3
%
%   Outputs
%     Y       the image
%     LOGDET  log d(output)/d(input), so the inverse reports the inverse map's
%             log derivative
%
%   Utility
%     Supply the scalar transform T_d of NF-iSAM spec section 9 in both
%     directions: forward for the density, backward for Eq. N6's forward
%     substitution, since sampling a flow means inverting it.
%
%   WHY A SPLINE AND NOT AN AFFINE MAP. The whole point of NF-iSAM is
%   posteriors that are not Gaussian -- the four-doors posterior has four
%   modes, and no affine map turns a unit Gaussian into that. A monotone
%   spline with enough bins can, while staying invertible by construction,
%   which is what makes the density exactly computable rather than estimated.
%
%   THE PARAMETERIZATION is the authors': K bins give 3K-1 numbers, being
%   2K-2 interior knot coordinates and K+1 derivatives. Derivatives at the
%   boundary knots are learned rather than pinned to 1, so outside [-B, B],
%   where this uses the identity, dY/dX can step at the boundary. Spec
%   section 9 standardizes every variable before training, which keeps
%   samples well inside B; the tails exist so the transform is total, not
%   because they are meant to carry mass.
%
%   X or PARAMS may be dlarray. Training differentiates Eq. N7 through the
%   spline parameters, and the trained transform must be the same code as the
%   tested one or the flow optimises something the tests never saw. The bin
%   index is taken from values rather than tracked: which bin a sample falls
%   in is a piecewise-constant choice and carries no gradient.

arguments
    x (:,1) {mustBeA(x, ["double" "single" "dlarray"])}
    params (1,1) struct
    opts.Inverse (1,1) logical = false
    opts.Bound (1,1) double {mustBePositive} = 5
    opts.MinDerivative (1,1) double {mustBePositive} = 1e-3
end

B = opts.Bound;
n = numel(x);
K = size(params.widths, 2);

localCheck(params, n, K, opts.MinDerivative);

% The output must track the spline parameters even when the samples
% themselves are plain data, which is the usual case during training.
if ~isa(x, 'dlarray') && (isa(params.widths, 'dlarray') || ...
        isa(params.heights, 'dlarray') || isa(params.derivatives, 'dlarray'))
    x = dlarray(x);
end

% Knot coordinates: cumulative widths and heights across [-B, B]. Written
% as a multiply by an upper-triangular ones matrix because cumsum is not a
% differentiable dlarray operation and the knots must carry gradient.
U = triu(ones(K));
xk = -B + [zeros(n,1) params.widths * U];
yk = -B + [zeros(n,1) params.heights * U];
xk(:,end) = B;      % cumsum drift, not a free parameter
yk(:,end) = B;
d  = params.derivatives;

y = x;
logDet = zeros(n, 1, 'like', x);

% Identity outside the modelled interval. The spline maps [-B, B] onto
% itself, so forward and inverse test the same interval.
xv = localValue(x);
idx = find(xv > -B & xv < B);
if isempty(idx)
    return
end
xi = x(idx);

% Which bin each sample falls in: a lookup, not a differentiable quantity.
if opts.Inverse
    edges = localValue(yk);
else
    edges = localValue(xk);
end
k = sum(xv(idx) >= edges(idx, 1:K), 2);
k = min(max(k, 1), K);

lin  = sub2ind([n K], idx, k);
linD = sub2ind([n K+1], idx, k);
linD1 = sub2ind([n K+1], idx, k+1);

w  = params.widths(lin);
h  = params.heights(lin);
d0 = d(linD);
d1 = d(linD1);
s  = h ./ w;                                  % secant slope of the bin

xlo = xk(sub2ind([n K+1], idx, k));
ylo = yk(sub2ind([n K+1], idx, k));

if ~opts.Inverse
    t = (xi - xlo) ./ w;                      % position within the bin
    t = min(max(t, 0), 1);
    tc = t .* (1 - t);

    num = h .* (s .* t.^2 + d0 .* tc);
    den = s + (d1 + d0 - 2*s) .* tc;
    y(idx) = ylo + num ./ den;

    dnum = s.^2 .* (d1 .* t.^2 + 2*s .* tc + d0 .* (1 - t).^2);
    logDet(idx) = log(dnum) - 2*log(den);
else
    dy = xi - ylo;                            % xi is a y value here
    c2 = (d1 + d0 - 2*s);

    a = h .* (s - d0) + dy .* c2;
    b = h .* d0 - dy .* c2;
    c = -s .* dy;

    disc = b.^2 - 4*a.*c;
    disc = max(disc, 0);                      % monotone spline: root exists
    t = 2*c ./ (-b - sqrt(disc));
    t = min(max(t, 0), 1);
    y(idx) = t .* w + xlo;

    tc = t .* (1 - t);
    den = s + c2 .* tc;
    dnum = s.^2 .* (d1 .* t.^2 + 2*s .* tc + d0 .* (1 - t).^2);
    % Derivative of the inverse is the reciprocal of the forward derivative.
    logDet(idx) = 2*log(den) - log(dnum);
end
end

% -------------------------------------------------------------------------
function localCheck(params, n, K, minD)
%LOCALCHECK Refuse spline parameters that are not a valid spline.
%   Inputs   PARAMS, N the sample count, K the bin count, MIND the floor
%   Outputs  none; throws
%   Utility  a non-monotone or misshapen spline gives a wrong density rather
%           than an error, so the shapes and the signs are checked here.
for f = ["widths" "heights" "derivatives"]
    if ~isfield(params, f)
        error('flows:rqSplineTransform:missingParam', ...
            'PARAMS needs a %s field.', f);
    end
end
if size(params.widths, 1) ~= n || size(params.heights, 1) ~= n || ...
        size(params.derivatives, 1) ~= n
    error('flows:rqSplineTransform:unpaired', ...
        ['One spline per sample: got %d samples but %d/%d/%d parameter ' ...
         'rows.'], n, size(params.widths,1), size(params.heights,1), ...
        size(params.derivatives,1));
end
if size(params.heights, 2) ~= K || size(params.derivatives, 2) ~= K + 1
    error('flows:rqSplineTransform:shape', ...
        ['K bins need K widths, K heights and K+1 derivatives; got ' ...
         '%d/%d/%d.'], K, size(params.heights,2), size(params.derivatives,2));
end
wv = localValue(params.widths);
hv = localValue(params.heights);
dv = localValue(params.derivatives);
if any(wv(:) <= 0) || any(hv(:) <= 0)
    error('flows:rqSplineTransform:notMonotone', ...
        'Bin widths and heights must be positive or the spline is not invertible.');
end
if any(dv(:) < minD)
    error('flows:rqSplineTransform:notMonotone', ...
        ['Knot derivatives must be at least %g. A derivative at zero makes ' ...
         'the transform flat and the inverse undefined.'], minD);
end
end

% -------------------------------------------------------------------------
function v = localValue(x)
%LOCALVALUE The plain numbers behind a dlarray, for lookups and checks.
%   Inputs   X, a numeric array or a dlarray
%   Outputs  V, the plain numbers
%   Utility  the bin index is a piecewise-constant choice carrying no
%           gradient, so it is taken from values rather than tracked.
if isa(x, 'dlarray')
    v = extractdata(x);
else
    v = x;
end
end
