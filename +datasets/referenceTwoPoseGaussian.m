function ref = referenceTwoPoseGaussian(caseData, x2Query)
%REFERENCETWOPOSEGAUSSIAN Closed-form ground truth for the Gaussian variant.
%
%   Inputs
%     CASEDATA  the two-pose case; must be the "gaussian" variant
%     X2QUERY   points to evaluate at             default the case's own grid
%
%   Outputs
%     REF       struct carrying the exact f_new(x2) and its normalization
%
%   Utility
%     Give the exact
%
%       f_new(x2) = int int f(x1) f(x1,x2) f(x1,l1) f(l1,x2) dl1 dx1
%
%     with no grid anywhere, to validate the quadrature reference itself.
%
%   Two independent references that agree leave very little room for a shared
%   mistake, and the quadrature is the only one that survives into the
%   multimodal variant.
%
%   The four factors are collected into the energy
%
%       E(z) = 1/2 z' Lambda z - b' z + const,   z = (x1, l1, x2)
%
%   by accumulating Lambda += a a'/sigma^2 and b += m a/sigma^2 for each
%   term (a'z - m)^2 / (2 sigma^2). Marginalizing x1 and l1 is then exact.

arguments
    caseData (1,1) struct
    x2Query (1,:) double = []
end

if caseData.variant ~= "gaussian"
    error('datasets:referenceTwoPoseGaussian:notGaussian', ...
        ['Closed form applies only to the gaussian variant; case "%s" is %s. ' ...
         'Use datasets.referenceTwoPoseQuadrature instead.'], ...
        caseData.name, caseData.variant);
end

s     = caseData.settings;
sig0  = s.prior(2);     mu0 = s.prior(1);
sigOd = s.odometry(2);  dOd = s.odometry(1);
sigA  = s.rangeA(2);    dA  = s.rangeA(1);
sigB  = s.rangeB(2);    dB  = s.rangeB(1);

% z = (x1, l1, x2)
Lambda = zeros(3);
b      = zeros(3, 1);

terms = { ...
    [1 0 0].',  mu0, sig0;  ...   % f(x1)      : (x1 - mu0)^2
    [-1 0 1].', dOd, sigOd; ...   % f(x1,x2)   : (x2 - x1 - dOd)^2
    [-1 1 0].', dA,  sigA;  ...   % f(x1,l1)   : (l1 - x1 - dA)^2
    [0 -1 1].', dB,  sigB};       % f(l1,x2)   : (x2 - l1 - dB)^2

logC  = 0;   % product of the four Gaussian normalizing constants
const0 = 0;  % the m^2/(2 sigma^2) tail of each completed square
for i = 1:size(terms, 1)
    a = terms{i,1};  m = terms{i,2};  sg = terms{i,3};
    Lambda = Lambda + (a * a.') / sg^2;
    b      = b      + (m * a)   / sg^2;
    logC   = logC   - log(sg * sqrt(2*pi));
    const0 = const0 + m^2 / (2 * sg^2);
end

Sigma = inv(Lambda);
mu    = Sigma * b;

% prod f = exp(logC) * exp(-const0) * exp(-1/2 z'Lambda z + b'z), so the
% total mass picks up both the normalizers and the completed-square constant.
% Dropping const0 inflates the mass by exp(const0) while leaving the shape
% correct, which is exactly the kind of error the quadrature cross-check
% is here to catch.
logTotal = logC - const0 + 1.5*log(2*pi) ...
           - 0.5*localLogDet(Lambda) + 0.5 * (b.' * (Lambda \ b));
total    = exp(logTotal);

muX2  = mu(3);
varX2 = Sigma(3,3);

if isempty(x2Query)
    x2Query = linspace(muX2 - 6*sqrt(varX2), muX2 + 6*sqrt(varX2), 401);
end

pdfX2  = exp(-0.5 * ((x2Query - muX2).^2) / varX2) / sqrt(2*pi*varX2);
fnewX2 = total * pdfX2;

ref = struct();
ref.x2      = x2Query;
ref.fnew    = fnewX2;
ref.pdf     = pdfX2;
ref.mass    = total;
ref.mean    = muX2;
ref.var     = varX2;
ref.std     = sqrt(varX2);
ref.Lambda  = Lambda;
ref.Sigma   = Sigma;
ref.jointMean = mu;
ref.method  = "closed-form Gaussian marginalization";

% R_0(x1,x2) = int f(x1,l1) f(l1,x2) dl1 is itself Gaussian:
% l1 | x1 ~ N(x1 + dA, sigA^2) as a density, and f(l1,x2) = N(x2 - l1; dB, sigB^2),
% so the convolution is N(x2; x1 + dA + dB, sigA^2 + sigB^2).
rVar = sigA^2 + sigB^2;
ref.R0 = @(x1v, x2v) exp(-0.5 * ((x2v - x1v - dA - dB).^2) / rVar) / sqrt(2*pi*rVar);
end

function ld = localLogDet(M)
%LOCALLOGDET log|det M| through the LU factors.
%   Inputs   M, square
%   Outputs  LD, the log determinant
%   Utility  det() overflows on the covariances this reference builds; the
%            factors do not.
[L, U, P] = lu(M); %#ok<ASGLU>
ld = sum(log(abs(diag(U))));
end
