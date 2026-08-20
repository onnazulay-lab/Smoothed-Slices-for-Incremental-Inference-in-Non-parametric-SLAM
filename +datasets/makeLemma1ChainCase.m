function caseData = makeLemma1ChainCase(opts)
%MAKELEMMA1CHAINCASE A Lemma-1 chain of stated depth H, with an exact answer.
%
%   Inputs
%     Depth      H, the number of sampling steps xi_0 -> ... -> xi_H  default 1
%     Variant    "gaussian" (default) or "multimodal"
%     Prior      [mu sigma] for f(x0)                          default [0 1]
%     Step       [delta sigma] for every g_r                   default [0.5 0.8]
%     Fusion     [delta sigma] for a(x_H, s)                   default [0.5 0.9]
%     Front      [delta sigma] for b_0(x_0, s), [] to derive   default []
%     MixtureOffset  mode separation in the multimodal variant default 2.2
%     Counter    a core.EvalCounter shared by all factors
%
%   Outputs
%     CASEDATA   the case struct: graph, elimination order, path variables,
%                the depth, and the settings it was built from
%
%   Utility
%     Supply the E1-H recursion-depth study with the one thing it cannot get
%     from Plaza or Grid World: a graph whose elimination path is H levels deep
%     BY CONSTRUCTION, at an H the caller chooses.
%
%   WHY A SYNTHETIC CASE RATHER THAN A LONGER TRAJECTORY, which is the
%   substitution the Gap-Filling Manual explicitly forbids at Step 3A.6. Path
%   depth is not trajectory length. H is the number of CONSECUTIVELY ELIMINATED
%   variables joined by sampling factors, and on a range-only SLAM graph that
%   run is short however long the trajectory is: a landmark seen from many
%   poses is eliminated far from any single one of them, so the order breaks
%   the run. Adding poses to Plaza grows the graph and leaves H at one or two.
%   The only way to observe how the recursion behaves at H = 5 is to build a
%   graph whose order has a five-step run in it, which is this.
%
%   THE STRUCTURE, named in the symbols of Eqs. (36)-(41) so the case and the
%   recursion can be checked against each other:
%
%       f(x0)            the prior, a front factor of Eq. (41)
%       g_r(x_r,x_{r+1}) the sampling factor of level r, r = 0..H-1
%       a(x_H, s)        the fusion factor, the only one touching the separator
%       b_0(x_0, s)      the front factor coupling xi_0 to the separator
%
%   b_0 is what the two-pose case calls odometry, and it is here for the same
%   reason: without it xi_0 reaches the separator only through the chain, the
%   front factor of Eq. (41) is the prior alone, and the case stops exercising
%   the B .* R product that every slice estimator ends in.
%
%   ONLY THE FUSION FACTOR IS AMBIGUOUS in the multimodal variant, following
%   the two-pose case's reasoning: one ambiguous factor gives two modes of
%   equal weight, whereas mixing several gives a doubly-weighted centre mode
%   that dominates and leaves the side modes as bumps. Putting it at level H
%   also puts the ambiguity as deep in the tower as it goes, which is where a
%   surface that over-smooths will lose it.
%
%   H >= 2 IS NOT RUNNABLE BY THE THREE-NODE ENGINE, and the case says so in a
%   field rather than by crashing. The failure is at the SECOND elimination,
%   not the first: x_0 carries the prior and so leaves by the unary route,
%   which never looks at the separator width, while x_1 has no unary factor and
%   must take the Lemma-1 route -- where the chain has left it the separator
%   {x_2, s}. methods.slices.estimateNewFactor's Lemma-1 route accepts a
%   one-variable final separator only. That is a real limit of the paper-
%   literal route rather than a defect of this case, and it is why the manual
%   calls E1-H a developer-extension study with no GUI control: the depth sweep
%   drives the recursion directly through research.recursionDepthStudy.
%
%   AT H = 1 THE CASE IS THE TWO-POSE CASE'S STRUCTURE, which is deliberate.
%   x_0 with a prior, x_1 reached only through g_0, a separator reached from
%   both -- that is f(x1), f(x1,l1), f(l1,x2), f(x1,x2) with the names changed.
%   It is what lets the depth study's H = 1 row be checked against an estimator
%   that a quadrature reference has already validated.
%
%   See also datasets.referenceLemma1Chain, research.recursionDepthStudy,
%            methods.smoothed.surfaceRecursionGeneral.

arguments
    opts.Depth   (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.Variant (1,1) string {mustBeMember(opts.Variant, ["gaussian","multimodal"])} = "gaussian"
    opts.Prior   (1,2) double = [0 1]
    opts.Step    (1,2) double = [0.5 0.8]
    opts.Fusion  (1,2) double = [0.5 0.9]
    % Unconstrained so [] can mark "derive it from the chain"; an arguments
    % block validates its own default, and (1,2) would reject the sentinel.
    opts.Front   double = []
    opts.MixtureOffset (1,1) double = 2.2
    opts.Counter = []
end

H = opts.Depth;

% b_0 is derived to AGREE with the chain unless the caller overrides it: its
% mean shift is the shift the chain itself accumulates, and its sigma is loose.
% A front factor that disagreed would be a second, conflicting measurement of
% the separator, which changes what the case tests from "how does the recursion
% behave at depth H" to "how does it behave under conflict" -- a fair question,
% and a different one.
if isempty(opts.Front)
    opts.Front = [H * opts.Step(1) + opts.Fusion(1), 2.0];
end
if numel(opts.Front) ~= 2
    error('datasets:makeLemma1ChainCase:badFront', ...
        'Front must be [delta sigma]; got %d element(s).', numel(opts.Front));
end
opts.Front = reshape(opts.Front, 1, 2);

counter = opts.Counter;
if isempty(counter)
    counter = core.EvalCounter();
end

pathNames = "x" + string(0:H);
sepName   = "s";

% --- Domains --------------------------------------------------------------
% Sized from the forward marginals rather than fixed, because the chain
% accumulates variance: at H = 5 the deepest level is nearly three times as
% wide as the prior, and a domain chosen for H = 1 would truncate it. The
% reference quadrature re-checks the edge density, so an undersized domain is
% reported rather than silently integrated over.
pad = 6;
sigmaLevel = sqrt(opts.Prior(2)^2 + (0:H) * opts.Step(2)^2);
muLevel    = opts.Prior(1) + (0:H) * opts.Step(1);

extra = 0;
if opts.Variant == "multimodal"
    extra = opts.MixtureOffset;
end
muS    = muLevel(end) + opts.Fusion(1);
sigmaS = sqrt(sigmaLevel(end)^2 + opts.Fusion(2)^2);

vars = core.Variable.empty(1, 0);
for r = 0:H
    % Levels above 0 are INTEGRATION variables, so they get the wider domain
    % for the reason the two-pose case gives l1 one: the surface needs support
    % on both sides of the neighbouring levels, and a domain merely as wide as
    % the marginal truncates it where the neighbour's mass sits.
    width = pad * sigmaLevel(r + 1) + extra;
    if r > 0
        width = width + pad * opts.Step(2) + opts.Fusion(2);
    end
    vars(end+1) = core.Variable(pathNames(r + 1), 'Type', "pose", ...
        'Domain', [muLevel(r + 1) - width, muLevel(r + 1) + width]); %#ok<AGROW>
end
vars(end+1) = core.Variable(sepName, 'Type', "pose", ...
    'Domain', [muS - pad * sigmaS - extra, muS + pad * sigmaS + extra]);

% --- Factors --------------------------------------------------------------
f_prior = core.Factor.gaussianUnary(pathNames(1), opts.Prior(1), opts.Prior(2), ...
    'Name', "f(" + pathNames(1) + ")", 'Counter', counter);

g = core.Factor.empty(1, 0);
for r = 0:(H - 1)
    g(end+1) = core.Factor.gaussianRelative( ...
        pathNames(r + 1), pathNames(r + 2), opts.Step(1), opts.Step(2), ...
        'Name', sprintf("g%d(%s,%s)", r, pathNames(r + 1), pathNames(r + 2)), ...
        'Counter', counter); %#ok<AGROW>
end

switch opts.Variant
    case "gaussian"
        f_fuse = core.Factor.gaussianRelative(pathNames(end), sepName, ...
            opts.Fusion(1), opts.Fusion(2), ...
            'Name', "a(" + pathNames(end) + "," + sepName + ")", 'Counter', counter);
    case "multimodal"
        d = opts.MixtureOffset;
        f_fuse = core.Factor.mixtureRelative(pathNames(end), sepName, ...
            [opts.Fusion(1) - d, opts.Fusion(1) + d], ...
            [opts.Fusion(2), opts.Fusion(2)], [0.5 0.5], ...
            'Name', "a(" + pathNames(end) + "," + sepName + ")", 'Counter', counter);
end

f_front = core.Factor.gaussianRelative(pathNames(1), sepName, ...
    opts.Front(1), opts.Front(2), ...
    'Name', "b0(" + pathNames(1) + "," + sepName + ")", 'Counter', counter);

graph = core.FactorGraph(vars, [f_prior g f_fuse f_front], counter);

% --- Case bundle ----------------------------------------------------------
caseData = struct();
caseData.name            = sprintf("lemma1chain_h%d_%s", H, opts.Variant);
caseData.displayName     = sprintf("Lemma-1 chain, H = %d", H);
caseData.variant         = opts.Variant;
caseData.depth           = H;
caseData.graph           = graph;
caseData.counter         = counter;
caseData.eliminationOrder = [pathNames sepName];
caseData.targetVariable  = sepName;
caseData.pathVariables   = pathNames;
caseData.numIncrements   = 1;
caseData.engine          = "slices3";

% Stated rather than discovered by failing. See the header note on H >= 2.
caseData.runnableByEngine = (H == 1);
if H == 1
    caseData.engineNote = "x0 leaves by the unary route on its prior; x1 " + ...
        "then takes the Lemma-1 route and, at H = 1, sees the one-variable " + ...
        "separator {s} that route requires. This is the two-pose structure.";
else
    caseData.engineNote = string(sprintf( ...
        ['x0 leaves by the unary route, but x1 must then take the Lemma-1 ' ...
         'route and at H = %d it sees the separator {%s, %s}. That route ' ...
         'accepts a one-variable final separator only, so this depth is ' ...
         'reachable through research.recursionDepthStudy and not through ' ...
         'the app.'], H, pathNames(3), sepName));
end

caseData.settings = struct( ...
    'depth',   H, ...
    'prior',   opts.Prior, ...
    'step',    opts.Step, ...
    'fusion',  opts.Fusion, ...
    'front',   opts.Front, ...
    'mixtureOffset', opts.MixtureOffset, ...
    'caseProfile', "nominal");

caseData.latex = struct( ...
    'graph',  "$f(x_0)\,b_0(x_0,s)\,\prod_{r=0}^{H-1} g_r(x_r,x_{r+1})\,a(x_H,s)$", ...
    'target', "$f_{\mathrm{new}}(s) = \int\!\cdots\!\int f(x_0)\,b_0(x_0,s)\prod_r g_r(x_r,x_{r+1})\,a(x_H,s)\,dx_0\cdots dx_H$", ...
    'headline', "$R_r(\xi_r,s) = Z_r(\xi_r)\,\mathbb{E}_{q_r}\!\left[a_r(\xi_{r+1},s)\,R_{r+1}(\xi_{r+1},s)\right]$");

caseData.groundTruth = struct();   % filled by datasets.referenceLemma1Chain
end
