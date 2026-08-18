function caseData = makeFourDoorsCase(opts)
%MAKEFOURDOORSCASE Classical 1-D multimodal localization along a corridor.
%
%   Inputs
%     Doors     door positions                       default [2 6 10 14]
%     NumPoses  poses along the corridor             default 6
%     Step      nominal odometry step                default 2.4
%     (the remaining options are listed under Name-value options below)
%
%   Outputs
%     CASEDATA  the case struct: graph, elimination order, ground truth and
%               the settings it was built from
%
%   Utility
%     Build a case whose posterior is genuinely multimodal, so that a method
%     which tracks the mean while destroying the shape can be caught.
%
%   App specification section 6: a robot drives down a corridor with several
%   identical doors, and each time it sees a door it learns that it is beside
%   ONE of them without learning which.
%
%   The posterior is genuinely multimodal and stays that way until the
%   accumulated odometry is sharp enough to rule modes out. That is the whole
%   point of the case: a method can track the mean of this posterior
%   perfectly while destroying its shape, and RMSE will applaud. Mode weights
%   over increments are the metric that does not.
%
%   The factor graph is a chain:
%
%       f(x1)                    broad prior, the robot starts unlocalized
%       f(x_k, x_{k+1})          odometry
%       f(x_k) = sum_d w_d N(x_k; door_d, sigma_z)    a door sighting
%
%   The door factor is UNARY and multimodal. That matters structurally as
%   well as statistically: it makes every observed pose independently
%   sampleable, so the Lemma 1 precondition is satisfied everywhere and the
%   elimination order is free. The two-pose range benchmark deliberately
%   does the opposite, forcing the structural route; between them the two
%   cases cover both branches.
%
%   Name-value options:
%     Doors        door positions                       default [2 6 10 14]
%     NumPoses     poses along the corridor             default 6
%     Step         nominal odometry step                default 2.4
%     OdomSigma    odometry noise                       default 0.35
%     ObsSigma     door-sighting noise                  default 0.30
%     SeeDoorAt    increments at which a door is seen   default [1 3 6]
%     StartPose    true starting position               default 1.0
%     Seed         measurement-noise seed               default 7
%     Counter      a core.EvalCounter shared by all factors

arguments
    opts.Doors (1,:) double = [2 6 10 14]
    opts.NumPoses (1,1) double {mustBeInteger, mustBeGreaterThan(opts.NumPoses,1)} = 6
    opts.Step (1,1) double = 2.4
    opts.OdomSigma (1,1) double {mustBePositive} = 0.35
    opts.ObsSigma (1,1) double {mustBePositive} = 0.30
    opts.SeeDoorAt (1,:) double = [1 3 6]
    opts.StartPose (1,1) double = 1.0
    opts.Seed (1,1) double = 7
    opts.Counter = []
end

counter = opts.Counter;
if isempty(counter), counter = core.EvalCounter(); end

% Measurement noise gets its own stream so that changing a method's sample
% budget cannot change the data it is given.
noise = RandStream('threefry', 'Seed', opts.Seed);

nPose = opts.NumPoses;
poseNames = "x" + string(1:nPose);

truePose = opts.StartPose + opts.Step * (0:nPose-1).';

% Domain: the corridor plus a margin, wide enough that no mode is clipped.
lo = min([opts.Doors truePose.']) - 4;
hi = max([opts.Doors truePose.']) + 4;

vars = core.Variable.empty(1, 0);
for k = 1:nPose
    vars(end+1) = core.Variable(poseNames(k), 'Dim', 1, 'Type', "pose", ...
        'Domain', [lo hi]); %#ok<AGROW>
end

factors = core.Factor.empty(1, 0);
increments = struct('k', {}, 'poseName', {}, 'newVariables', {}, ...
                    'factorIndex', {}, 'sawDoor', {}, 'observation', {});

w = ones(1, numel(opts.Doors)) / numel(opts.Doors);

for k = 1:nPose
    idx = [];

    if k == 1
        % A deliberately BROAD prior. A tight prior would localize the robot
        % before any door is seen and the case would have no ambiguity left
        % to resolve, which is the one thing it exists to show.
        fp = core.Factor.gaussianUnary(poseNames(1), truePose(1), 3.0, ...
                 'Name', "f(x1)", 'Counter', counter);
        factors(end+1) = fp; %#ok<AGROW>
        idx(end+1) = numel(factors); %#ok<AGROW>
    else
        delta = opts.Step + opts.OdomSigma * randn(noise);
        fo = core.Factor.gaussianRelative(poseNames(k-1), poseNames(k), ...
                 delta, opts.OdomSigma, ...
                 'Name', sprintf("f(%s,%s)", poseNames(k-1), poseNames(k)), ...
                 'Counter', counter);
        factors(end+1) = fo; %#ok<AGROW>
        idx(end+1) = numel(factors); %#ok<AGROW>
    end

    sawDoor = ismember(k, opts.SeeDoorAt);
    obs = struct('nearestDoor', NaN, 'residual', NaN);
    if sawDoor
        % The robot sees A door. Which one is exactly what it does not learn,
        % so the factor is the equally weighted mixture over all of them and
        % carries no association information whatsoever.
        [~, near] = min(abs(opts.Doors - truePose(k)));
        obs.nearestDoor = near;
        obs.residual = opts.ObsSigma * randn(noise);

        fd = localDoorFactor(poseNames(k), opts.Doors + obs.residual, ...
                 opts.ObsSigma, w, counter);
        factors(end+1) = fd; %#ok<AGROW>
        idx(end+1) = numel(factors); %#ok<AGROW>
    end

    increments(end+1) = struct('k', k, 'poseName', poseNames(k), ...
        'newVariables', poseNames(k), 'factorIndex', idx, ...
        'sawDoor', sawDoor, 'observation', obs); %#ok<AGROW>
end

graph = core.FactorGraph(vars, factors, counter);
[order, orderInfo] = core.eliminationOrder(graph);

caseData = struct();
caseData.name            = "four_doors";
caseData.displayName     = "Four Doors: 1-D multimodal localization";
caseData.variant         = "multimodal";
caseData.graph           = graph;
caseData.counter         = counter;
caseData.eliminationOrder = order;
caseData.orderInfo       = orderInfo;
caseData.targetVariable  = order(end);
caseData.pathVariables   = order(1:min(2, numel(order)-1));
caseData.numIncrements   = nPose;
caseData.increments      = increments;
caseData.engine          = "general";

caseData.doors = opts.Doors;
caseData.mission = struct('truePoses', truePose, 'poseNames', poseNames, ...
                          'step', opts.Step, 'domain', [lo hi]);
caseData.groundTruth = struct('poses', truePose, 'poseNames', poseNames, ...
                              'doors', opts.Doors);

caseData.settings = struct( ...
    'doors', opts.Doors, 'numPoses', nPose, 'step', opts.Step, ...
    'odomSigma', opts.OdomSigma, 'obsSigma', opts.ObsSigma, ...
    'seeDoorAt', opts.SeeDoorAt, 'startPose', opts.StartPose, ...
    'seed', opts.Seed, 'domain', [lo hi]);

caseData.latex = struct( ...
    'graph',  "$f(x_1)\prod_k f(x_k,x_{k+1})\prod_{k \in \mathcal{D}} f_{\mathrm{door}}(x_k)$", ...
    'target', sprintf("$f_{\\mathrm{new}}(%s \\mid D)$", ...
                      regexprep(order(end), '^([a-zA-Z]+)(\d+)$', '$1_{$2}')), ...
    'door',   "$f_{\mathrm{door}}(x_k) = \frac{1}{D}\sum_{d=1}^{D}\mathcal{N}(x_k;\, m_d,\, \sigma_z^2)$", ...
    'headline', "Mode weights, not RMSE: the mean of a four-mode posterior is a place the robot has never been");
end

% =========================================================================
function f = localDoorFactor(varName, centres, sigma, w, counter)
%LOCALDOORFACTOR The unary multimodal factor for one door sighting.
%   Inputs   VARNAME the observed pose, CENTRES the door positions, SIGMA the
%            sighting noise, W the mode weights, COUNTER the shared tally
%   Outputs  F, a sampleable core.Factor
%   Utility  build the factor that makes the case multimodal AND makes every
%           observed pose independently sampleable.
%
%   Sampleable directly, which is what makes every observed pose satisfy the
%   Lemma 1 precondition on its own.
key = matlab.lang.makeValidName(varName);

evalFcn = @(a) localMixturePdf(a.(key), centres, sigma, w);

samplers = struct();
samplers.(key) = struct( ...
    'draw', @(~, n) localMixtureDraw(centres, sigma, w, n), ...
    'logZ', @(~) 0);          % normalized in the variable

f = core.Factor(sprintf("fdoor(%s)", varName), varName, evalFcn, ...
    'Kind', "doorMixture", 'Samplers', samplers, ...
    'Meta', struct('centres', centres, 'sigma', sigma, 'weights', w), ...
    'Counter', counter);
end

% =========================================================================
function v = localMixturePdf(x, centres, sigma, w)
%LOCALMIXTUREPDF Density of a weighted Gaussian mixture.
%   Inputs   X the query points, CENTRES, SIGMA, W the mixture parameters
%   Outputs  V, the density at each point
%   Utility  evaluate the door factor.
v = zeros(size(x, 1), 1);
for d = 1:numel(centres)
    v = v + w(d) * exp(-0.5 * ((x(:,1) - centres(d)) ./ sigma).^2) ...
                 ./ (sigma * sqrt(2*pi));
end
end

% =========================================================================
function s = localMixtureDraw(centres, sigma, w, n)
%LOCALMIXTUREDRAW N draws from a weighted Gaussian mixture.
%   Inputs   CENTRES, SIGMA, W the mixture parameters, N the number of draws
%   Outputs  S, N-by-1 draws
%   Utility  sample the door factor, which is the proposal for an observed pose.
comp = core.categoricalSample(w(:), n);
s = reshape(centres(comp), [], 1) + sigma * randn(n, 1);
end
