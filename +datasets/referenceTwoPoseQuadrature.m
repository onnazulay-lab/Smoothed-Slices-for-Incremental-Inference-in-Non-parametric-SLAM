function ref = referenceTwoPoseQuadrature(caseData, opts)
%REFERENCETWOPOSEQUADRATURE Ground truth for the two-pose range benchmark.
%
%   Inputs
%     CASEDATA  the two-pose case
%     (options are listed below, under Name-value options)
%
%   Outputs
%     REF       struct carrying R_0, f_new, the normalized x2 marginal and
%               reference samples for MMD
%
%   Utility
%     Evaluate, by dense trapezoidal quadrature on a regular x1-by-l1 grid,
%
%       R_0(x1,x2) = int f(x1,l1) f(l1,x2) dl1                     (Eq. 26)
%       f_new(x2)  = int f(x1) f(x1,x2) R_0(x1,x2) dx1             (Eq. 19)
%
%     so that everything the app calls an "error" has something to be measured
%     against.
%
%   The inner integral is evaluated as a matrix product A * (w .* B) rather
%   than by broadcasting an |X1| x |L1| x |S| array, which would need
%   several gigabytes at the default resolution and gains nothing.
%
%   The quadrature is deliberately independent of the estimators: it never
%   touches core.ApproximateFactor or the surface recursion, so a bug in
%   either cannot hide by corrupting the reference too. Factor evaluations
%   made here are excluded from the shared cost counter for the same reason.
%
%   Name-value options:
%     NumX1  quadrature nodes for x1     default 1201
%     NumL1  quadrature nodes for l1     default 1201
%     NumX2  evaluation points for x2    default 401
%     NumSamples  reference samples drawn from the x2 marginal   default 4000
%     TailTolerance  maximum acceptable relative edge density     default 1e-5

arguments
    caseData (1,1) struct
    opts.NumX1 (1,1) double {mustBeInteger, mustBePositive} = 1201
    opts.NumL1 (1,1) double {mustBeInteger, mustBePositive} = 2401
    opts.NumX2 (1,1) double {mustBeInteger, mustBePositive} = 401
    opts.NumSamples (1,1) double {mustBeInteger, mustBePositive} = 4000
    opts.TailTolerance (1,1) double = 1e-5
end

g = caseData.graph;

% Evaluate against uncounted copies so the reference does not inflate the
% factor-evaluation tally used by the cost-scaling test.
f_x1   = localUncounted(g, "f(x1)");
f_x1x2 = localUncounted(g, "f(x1,x2)");
f_x1l1 = localUncounted(g, "f(x1,l1)");
f_l1x2 = localUncounted(g, "f(l1,x2)");

x1 = g.variable("x1").grid(opts.NumX1);
l1 = g.variable("l1").grid(opts.NumL1);
x2 = g.variable("x2").grid(opts.NumX2);

wx1 = localTrapzWeights(x1);   % |X1| x 1
wl1 = localTrapzWeights(l1);   % |L1| x 1

% --- R_0(x1, x2) = int f(x1,l1) f(l1,x2) dl1 ------------------------------
A  = f_x1l1.evaluate(struct('x1', x1(:),  'l1', l1(:).'));   % |X1| x |L1|
B  = f_l1x2.evaluate(struct('l1', l1(:),  'x2', x2(:).'));   % |L1| x |S|
R0 = A * (wl1 .* B);                                          % |X1| x |S|

% --- f_new(x2) = int f(x1) f(x1,x2) R_0(x1,x2) dx1 ------------------------
prior = f_x1.evaluate(struct('x1', x1(:)));                          % |X1| x 1
odom  = f_x1x2.evaluate(struct('x1', x1(:), 'x2', x2(:).'));         % |X1| x |S|
fnew  = (wx1 .* prior).' * (odom .* R0);                             % 1 x |S|

% --- Normalized marginal and reference samples ----------------------------
mass = trapz(x2, fnew);
if ~(mass > 0)
    error('datasets:referenceTwoPoseQuadrature:zeroMass', ...
        'Quadrature returned zero mass; check the factor domains.');
end
pdfX2 = fnew / mass;

samples = core.ConditionalFactor.inverseCdfSample(x2(:), pdfX2(:), opts.NumSamples);

% --- Domain adequacy check ------------------------------------------------
% If the reference itself is truncated, every error figure downstream is
% meaningless, so this is checked rather than assumed.
edgeDensity = max(pdfX2(1), pdfX2(end)) / max(pdfX2);
if edgeDensity > opts.TailTolerance
    warning('datasets:referenceTwoPoseQuadrature:truncated', ...
        ['Reference density at the x2 domain edge is %.2e of its peak ' ...
         '(tolerance %.1e). Widen the domain or the reference is truncated.'], ...
        edgeDensity, opts.TailTolerance);
end

ref = struct();
ref.x2          = x2;
ref.fnew        = fnew;        % unnormalized, directly comparable to estimators
ref.pdf         = pdfX2;       % normalized marginal
ref.mass        = mass;
ref.samples     = samples;
ref.x1          = x1;
ref.l1          = l1;
ref.R0          = R0;          % |X1| x |S| conditional smoothing surface
ref.mean        = trapz(x2, x2 .* pdfX2);
ref.std         = sqrt(trapz(x2, (x2 - trapz(x2, x2 .* pdfX2)).^2 .* pdfX2));
ref.grid        = struct('numX1', opts.NumX1, 'numL1', opts.NumL1, 'numX2', opts.NumX2);
ref.method      = "dense trapezoidal quadrature";
ref.edgeDensity = edgeDensity;

ref.R0Interp = @(xq, kq) interp1(x1(:), R0(:, kq), xq, 'linear', 0);
end

% -------------------------------------------------------------------------
function f = localUncounted(graph, name)
%LOCALUNCOUNTED Fetch a factor with its evaluation counter detached.
%   Inputs   GRAPH, and NAME of the factor
%   Outputs  F, the factor with Counter emptied
%   Utility  keep the reference's own evaluations out of the shared cost tally,
%           so the reference cannot inflate the number it exists to check.
idx = find([graph.Factors.Name] == name, 1);
if isempty(idx)
    error('datasets:referenceTwoPoseQuadrature:missingFactor', ...
        'Case has no factor named %s.', name);
end
f = graph.Factors(idx);
f.Counter = [];
end

function w = localTrapzWeights(gridVec)
%LOCALTRAPZWEIGHTS Composite trapezoidal weights for a uniform grid.
%   Inputs   GRIDVEC, the grid points
%   Outputs  W, one weight per point
%   Utility  turn a sum over grid points into an integral.
h = gridVec(2) - gridVec(1);
w = h * ones(numel(gridVec), 1);
w(1)   = 0.5 * h;
w(end) = 0.5 * h;
end
