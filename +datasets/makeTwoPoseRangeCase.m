function caseData = makeTwoPoseRangeCase(opts)
%MAKETWOPOSERANGECASE Two poses, one landmark, and an exact answer.
%
%   Inputs
%     Variant   "gaussian" (default) or "multimodal"
%     Prior     [mu sigma] for f(x1)                   default [0 1]
%     Odometry  [delta sigma] for f(x1,x2)             default [2 0.6]
%     RangeA    [delta sigma] for f(x1,l1)             default [1.5 0.5]
%     RangeB    [delta sigma] for f(l1,x2)             default [0.5 0.5]
%     MixtureOffset  mode separation in the multimodal variant   default 2.2
%     Counter   a core.EvalCounter shared by all factors
%
%   Outputs
%     CASEDATA  the case struct: graph, elimination order, ground truth and
%               the settings it was built from
%
%   Utility
%     Build the smallest instance of the problem -- small enough that the
%     answer can be computed exactly and every estimator scored against it.
%
%   This is the three-variable factor graph that both implementation
%   specifications name as the mandatory first test.
%   It is the graph of Eq. (16) in the Slices paper, which is where this case
%   comes from and no longer what it is called: a case named after an equation
%   number in somebody else's paper says nothing about the problem to anyone
%   reading the app.
%
%       f(x1)        prior on the first pose
%       f(x1, x2)    odometry
%       f(x1, l1)    range to the landmark from x1
%       f(l1, x2)    range to the landmark from x2
%
%   Two poses and one landmark, tied by range alone: the smallest instance of
%   the problem the Plaza case runs at scale. The graph is deliberately 1-D so
%   that
%
%       f_new(x2) = int int f(x1) f(x1,x2) f(x1,l1) f(l1,x2) dl1 dx1
%
%   can be computed by dense quadrature and used as ground truth. Every
%   estimator in the app is scored against that reference, which is the only
%   way to tell a variance reduction from a bias.
%
%   Name-value options:
%     Variant   "gaussian" (default) or "multimodal". The multimodal variant
%               makes f(x1,l1) and f(l1,x2) two-component mixtures, which is
%               the T4 support test: RCS must not collapse the modes.
%     Prior     [mu sigma] for f(x1)                   default [0 1]
%     Odometry  [delta sigma] for f(x1,x2)             default [2 0.6]
%     RangeA    [delta sigma] for f(x1,l1)             default [1.5 0.5]
%     RangeB    [delta sigma] for f(l1,x2)             default [0.5 0.5]
%     Counter   a core.EvalCounter shared by all factors
%
%   The elimination order is (x1, l1, x2). It exercises the hard case
%   directly: l1 has no unary factor, so its samples must come through the
%   Lemma 1 structural route.

arguments
    opts.Variant  (1,1) string {mustBeMember(opts.Variant, ["gaussian","multimodal"])} = "gaussian"
    opts.Prior    (1,2) double = [0 1]
    % Unconstrained so that [] can mark "use the per-variant default"; an
    % arguments block validates its default value too, and (1,2) would
    % reject the empty sentinel outright.
    opts.Odometry double = []
    opts.RangeA   (1,2) double = [1.5 0.5]
    opts.RangeB   (1,2) double = [0.5 0.5]
    opts.MixtureOffset (1,1) double = 2.2
    opts.Counter = []
end

if isempty(opts.Odometry)
    % The multimodal variant needs a WEAK odometry, or it simply resolves the
    % range ambiguity on its own and the posterior comes out unimodal.
    switch opts.Variant
        case "gaussian",   opts.Odometry = [2 0.6];
        case "multimodal", opts.Odometry = [2 3.0];
    end
end
if numel(opts.Odometry) ~= 2
    error('datasets:makeTwoPoseRangeCase:badOdometry', ...
        'Odometry must be [delta sigma]; got %d element(s).', numel(opts.Odometry));
end
opts.Odometry = reshape(opts.Odometry, 1, 2);

counter = opts.Counter;
if isempty(counter)
    counter = core.EvalCounter();
end

% --- Variables ------------------------------------------------------------
% Domains must be wide enough that the quadrature reference captures
% essentially all of the mass; the reference asserts this at the x2 edge.
% l1 is given a deliberately wider domain than x1 and x2 because it is an
% INTEGRATION variable: the inner integral R_0(x1,x2) needs l1 support
% around both x1 + rangeA and x2 - rangeB, so an l1 domain merely as wide as
% x2 truncates R_0 near the x2 domain edge.
%
% The multimodal variant needs wider domains: its ambiguous range factor
% pushes x2 mass out to roughly 2 +/- MixtureOffset, on top of a much looser
% odometry, and a domain sized for the Gaussian case would truncate the modes
% it exists to exhibit.
switch opts.Variant
    case "gaussian"
        domX1 = [ -6  8]; domL1 = [-12 18]; domX2 = [ -6 12];
    case "multimodal"
        pad   = 3 * opts.MixtureOffset;
        domX1 = [ -8 10];
        domL1 = [-16 - pad, 22 + pad];
        domX2 = [-10 - pad, 16 + pad];
end

x1 = core.Variable("x1", 'Type', "pose",     'Domain', domX1);
l1 = core.Variable("l1", 'Type', "landmark", 'Domain', domL1);
x2 = core.Variable("x2", 'Type', "pose",     'Domain', domX2);

% --- Factors --------------------------------------------------------------
f_x1    = core.Factor.gaussianUnary("x1", opts.Prior(1), opts.Prior(2), ...
              'Name', "f(x1)", 'Counter', counter);
f_x1x2  = core.Factor.gaussianRelative("x1", "x2", opts.Odometry(1), opts.Odometry(2), ...
              'Name', "f(x1,x2)", 'Counter', counter);

switch opts.Variant
    case "gaussian"
        f_x1l1 = core.Factor.gaussianRelative("x1", "l1", opts.RangeA(1), opts.RangeA(2), ...
                     'Name', "f(x1,l1)", 'Counter', counter);
        f_l1x2 = core.Factor.gaussianRelative("l1", "x2", opts.RangeB(1), opts.RangeB(2), ...
                     'Name', "f(l1,x2)", 'Counter', counter);
    case "multimodal"
        % A 1-D stand-in for range ambiguity: from x2 the landmark could lie
        % on either side, so f(l1,x2) is a symmetric two-component mixture
        % while f(x1,l1) stays a clean range measurement.
        %
        % Making only ONE factor ambiguous is deliberate. With both factors
        % mixed, the four sign combinations give x2 - x1 shifts of -2d, 0, 0
        % and +2d, so the doubly-weighted centre mode dominates and the side
        % modes stay minor bumps however the noise is tuned. One ambiguous
        % factor gives two modes of equal weight, which is the structure that
        % actually punishes an over-smoothed surface and the one the Four
        % Doors case will generalize in iteration 2.
        d = opts.MixtureOffset;
        f_x1l1 = core.Factor.gaussianRelative("x1", "l1", opts.RangeA(1), opts.RangeA(2), ...
                     'Name', "f(x1,l1)", 'Counter', counter);
        f_l1x2 = core.Factor.mixtureRelative("l1", "x2", ...
                     [opts.RangeB(1)-d, opts.RangeB(1)+d], ...
                     [opts.RangeB(2), opts.RangeB(2)], [0.5 0.5], ...
                     'Name', "f(l1,x2)", 'Counter', counter);
end

graph = core.FactorGraph([x1 l1 x2], [f_x1 f_x1x2 f_x1l1 f_l1x2], counter);

% --- Case bundle ----------------------------------------------------------
caseData = struct();
caseData.name            = sprintf("tworange_%s", opts.Variant);
caseData.displayName     = "Two-pose range benchmark";
caseData.variant         = opts.Variant;
caseData.graph           = graph;
caseData.counter         = counter;
caseData.eliminationOrder = ["x1" "l1" "x2"];
caseData.targetVariable  = "x2";        % the final separator of interest
caseData.pathVariables   = ["x1" "l1"]; % xi_0 -> xi_1 of the RCS recursion
caseData.numIncrements   = 1;           % batch case; iteration 2 adds steps
caseData.engine          = "slices3";   % the paper-faithful Algorithm S1 route
caseData.settings        = struct( ...
    'prior',    opts.Prior, ...
    'odometry', opts.Odometry, ...
    'rangeA',   opts.RangeA, ...
    'rangeB',   opts.RangeB, ...
    'mixtureOffset', opts.MixtureOffset);

caseData.latex = struct( ...
    'graph',   "$f(x_1)\,f(x_1,x_2)\,f(x_1,l_1)\,f(l_1,x_2)$", ...
    'target',  "$f_{\mathrm{new}}(x_2 \mid D_2) = \int\!\!\int f(x_1)f(x_1,x_2)f(x_1,l_1)f(l_1,x_2)\,dl_1\,dx_1$", ...
    'headline', "$\tilde f^{(2)}_{\mathrm{new}}(x_2) = \frac{c_1}{N_1}\sum_n f(x_1^{(n)},x_2)\int f(x_1^{(n)},l_1)f(l_1,x_2)\,dl_1$");

caseData.groundTruth = struct();   % filled by datasets.referenceTwoPoseQuadrature
end
