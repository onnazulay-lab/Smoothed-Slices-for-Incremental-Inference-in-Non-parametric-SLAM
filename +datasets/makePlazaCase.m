function caseData = makePlazaCase(opts)
%MAKEPLAZACASE A window of the real Plaza sequence, as a factor graph.
%
%   Inputs
%     Dataset      "Plaza2" (default) or "Plaza1"
%     WindowStart  first keyframe of the window     default chosen, see below
%     NumPoses     keyframes in the window K                       default 4
%     SensorRange  longest range admitted, metres                 default 30
%     Association  "known" (default) or "ambiguous"
%     EliminationOrder  "landmarksLast" (default) or "automatic"
%     (the remaining options are listed under Name-value options below)
%
%   Outputs
%     CASEDATA  the case struct, plus the plaza block recording the window,
%               the dead reckoning, the calibration and the window choice
%     CASEDATA.settings reports what the association actually came out as:
%               requestedAmbiguityFraction, numAmbiguousReadings,
%               effectiveAmbiguityFraction and, always zero,
%               numAmbiguityDeferredForInitialization
%
%   Utility
%     Build a case from real measurements: K consecutive keyframes, the
%     landmarks actually ranged from them, odometry along the window and
%     calibrated ranges across it.
%
%   THIS IS THE ONLY CASE IN THE APP WHOSE NOISE NOBODY CHOSE. The other
%   three draw their measurements from the model the estimator is given, so a
%   method that recovers the posterior exactly is recovering something that
%   is true by construction. Here the ranges come from radios and the
%   odometry from wheels, the noise is whatever they did that afternoon, and
%   a method can be beaten by the data rather than by the mathematics.
%
%   Name-value options:
%     Dataset      "Plaza2" (default) or "Plaza1"
%     WindowStart  first keyframe of the window       default: chosen, see below
%     NumPoses     keyframes in the window K                       default 4
%     SensorRange  longest range admitted, metres                 default 30
%     RangeSigma   range noise; [] takes the calibration residual  default []
%     OdomSigma    odometry noise per axis, metres              default 0.15
%     PriorSigma   prior on the first pose, metres              default 0.20
%     Association  "known" (default) or "ambiguous"
%     MaxLandmarks landmarks a chosen window may hold; 2 is what has
%                  been measured end to end                          default 2
%     KeyframeSpacing  metres of travel per keyframe               default 6
%     Calibration  passed to the loader: "fit", "none" or [a b]
%     EliminationOrder  "landmarksLast" (default) or "automatic"
%     Counter      a core.EvalCounter shared by all factors
%
%   WHY A WINDOW AND NOT THE TRAJECTORY. Both papers solve the whole
%   sequence; this engine solves a window of it. What the limit is NOT is
%   settled: not the variables' dimension and not the separator width --
%   measured on the grid world, the office fails on separators of 3 variables
%   and the warehouse fails on separators of 2. What it IS is not settled.
%   "About thirteen variables" was the working answer until the same sweep
%   found a second layout failing at ten, so the number is per-map and the
%   mechanism is open (see datasets.makeGridWorldCase).
%
%   So the window is sized against a stated BUDGET rather than a safety
%   margin, because there is no longer a number to be safely under. The
%   budget is MaxVariables, it is 13, and the search below reports whether it
%   held rather than assuming it did. A window is what is reachable, and the
%   figure says so on its face rather than presenting a windowed posterior as
%   the paper's.
%
%   POSES ARE ONLY HALF OF WHAT A WINDOW HOLDS, which is why the cap is on
%   variables and the pose count is an output of the search rather than the
%   thing chosen. How many landmarks a window ranges is a property of where
%   the robot was: eight keyframes of Plaza1 from keyframe 24 carry two, for
%   ten variables, while the same eight keyframes elsewhere carry more. A cap
%   on poses would be a cap on the half that does not vary.
%
%   THE RANGE LIMIT IS WHAT SIZES THE WINDOW. At a 6 m keyframe spacing and
%   a 30 m limit, a window of Plaza2 sees a median of two landmarks.
%   Lifting the limit puts
%   all four landmarks in every window (eight variables, separator 5) and
%   dropping it to 20 m leaves 10% of Plaza1's windows with no landmark at
%   all and nothing to estimate.
%
%   WHAT ACTUALLY DECIDES ACCURACY HERE IS THE ELIMINATION ORDER, and by a
%   wider margin than any of the above. See the note at the order below: the
%   two orders produce IDENTICAL separator sizes and pose RMSE differing by
%   more than tenfold, which is why separator size is not the quantity to
%   reason with.
%
%   THE LANDMARK POSTERIOR IS BIMODAL, AND ITS MEAN IS NOT AN ESTIMATE.
%   Ranges from a short pose chain fix a landmark only up to reflection in
%   that chain, and both modes carry real mass. Measured on the default
%   Plaza2 window, with the sample cloud splitting 51/49 and 48/52 either
%   side of the trajectory:
%
%       range residual at the TRUE position       l0 0.51 m    l6 1.25 m
%       range residual at the POSTERIOR MEAN      l0 15.94 m   l6 18.23 m
%
%   The true position explains the readings at the calibration noise floor;
%   the mean explains them 16-18 m worse, because it sits between two modes
%   on the trajectory itself, where no mass is. Individual samples do reach
%   truth (1.22 m and 3.09 m at their nearest).
%
%   So landmarkRMSE on this case measures the SEPARATION OF THE TWO MODES,
%   not the quality of the estimate, and no sample budget moves it: support
%   201 -> 3000 gave 17.8, 8.8, 23.2, 11.8 m with no trend. Read poseRMSE,
%   and read the landmark posterior as a distribution -- which is the whole
%   point of the methods being compared, and is what viz.plotPlazaContext
%   draws.
%
%   THE RANGE LIMIT IS A MODELLING CHOICE, NOT A PROPERTY OF THE RADIOS. They
%   ranged out to 88 m across a plaza 68 m wide. Discarding the long readings
%   is what makes the problem fit, and it is applied identically to every
%   method, but it does throw away information the papers keep. It is the
%   single biggest departure from them in this case.
%
%   WHY THE WINDOW IS ANCHORED ON TRUTH. The first pose gets a prior at its
%   true position, exactly as the grid world's x1 does. A window cut out of
%   the middle of a run has no other origin available: the alternative is to
%   inherit 1400 m of accumulated dead-reckoning drift as though it were
%   knowledge, which would make every window after the first a study of that
%   drift rather than of the methods.
%
%   See also datasets.loadPlazaDataset, datasets.makeGridWorldCase.

arguments
    opts.Dataset (1,1) string {mustBeMember(opts.Dataset, ["Plaza1","Plaza2"])} = "Plaza2"
    opts.WindowStart double = []
    % Eight, not four. Four was chosen when the elimination order could not
    % survive more: landmarksLast stranded a variable at ten poses and passed
    % at nine only by luck, so the case was pinned below the bug rather than
    % below any measured limit. With the deferral done inside the greedy loop
    % that ceiling is gone, and the window sweep says eight is where to sit --
    % it nearly doubles the readings (8 -> 15 on Plaza2) at the SAME separator
    % dimension and ten variables, which is inside the regime the engine is
    % measured on, and it works on both sequences rather than one.
    opts.NumPoses (1,1) double {mustBeInteger, mustBeGreaterThan(opts.NumPoses, 1)} = 8
    opts.SensorRange (1,1) double {mustBePositive} = 30
    opts.RangeSigma double = []
    opts.OdomSigma (1,1) double {mustBePositive} = 0.15
    opts.PriorSigma (1,1) double {mustBePositive} = 0.20
    opts.Association (1,1) string {mustBeMember(opts.Association, ["known","ambiguous"])} = "known"
    opts.AmbiguityFraction (1,1) double {mustBeNonnegative, ...
        mustBeLessThanOrEqual(opts.AmbiguityFraction, 1)} = 0.5
    opts.MaxReadingsPerPair (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.MaxLandmarks (1,1) double {mustBeInteger, mustBeGreaterThanOrEqual( ...
        opts.MaxLandmarks, 2)} = 2
    opts.KeyframeSpacing (1,1) double {mustBePositive} = 6
    % The engine's measured-safe regime, as a number with a name rather than a
    % 13 buried in a loop condition. It is not a constant of the method: the
    % grid world office fails at 13 and the warehouse at 10, so this is the
    % optimistic end of a range that is still unsettled. Named so that raising
    % K makes the operator meet it.
    opts.MaxVariables (1,1) double {mustBeInteger, mustBePositive} = 13
    opts.Calibration = "fit"
    opts.EliminationOrder (1,1) string {mustBeMember(opts.EliminationOrder, ...
        ["landmarksLast","automatic"])} = "landmarksLast"
    opts.Seed (1,1) double {mustBeInteger, mustBeNonnegative} = 7
    opts.Counter = []
end

counter = opts.Counter;
if isempty(counter), counter = core.EvalCounter(); end

data = datasets.loadPlazaDataset(opts.Dataset, ...
    'KeyframeSpacing', opts.KeyframeSpacing, 'Calibration', opts.Calibration);

rangeSigma = opts.RangeSigma;
if isempty(rangeSigma), rangeSigma = data.calibration.residualSigma; end

K = opts.NumPoses;

% --- Which window --------------------------------------------------------
readings = localWindowReadings(data, opts.SensorRange);

if isempty(opts.WindowStart)
    [w0, choice] = localChooseWindow(data, readings, K, opts.MaxLandmarks, ...
        opts.MaxVariables);
else
    w0 = opts.WindowStart;
    choice = "supplied";
end
localAssertWindow(data, w0, K);

idx = w0 : w0 + K - 1;

% --- The readings this window keeps --------------------------------------
inWindow = ismember([readings.poseId], idx);
obsAll   = readings(inWindow);
if isempty(obsAll)
    error('datasets:makePlazaCase:emptyWindow', ...
        ['Keyframes %d to %d of %s have no range reading within %.1f m. ' ...
         'The landmarks would be unconstrained and no elimination order ' ...
         'can rescue that; choose another window or a longer SensorRange.'], ...
        idx(1), idx(end), data.name, opts.SensorRange);
end

obsAll = localThinReadings(obsAll, data, idx, opts.MaxReadingsPerPair);

lmIds  = unique([obsAll.landmarkId], 'stable');
lmIds  = sort(lmIds);
nLm    = numel(lmIds);
lmRow  = arrayfun(@(id) find(data.landmarkIds == id, 1), lmIds);
lmTrue = data.gt.landmarks(lmRow, :);

% Both window-local, and for the same reason. The poses have always been
% x1..xK -- numbered within the window, not within the 219-keyframe sequence
% they were cut from. The landmarks were not: they carried the raw survey ids,
% so a four-pose window came out as x1 x2 x3 x4 with landmarks l0 and l6, and
% a reader had to know that one pair counts from one and the other does not.
% Two numbering schemes in one graph, distinguishable only by knowing which
% variables happen to be landmarks.
%
% The survey id is still the right label for the ranging node -- it is what
% the dataset's own documentation calls it -- so it is kept as DATA on
% caseData.landmarks.ids and shown in the panels, rather than smuggled into a
% variable name where it reads as an index.
poseNames = "x" + string(1:K);
lmNames   = "l" + string(1:nLm);

% --- The window's own dead reckoning -------------------------------------
% Rebuilt from the body-frame increments, starting at the window's anchor.
% The dataset deliberately does not carry a world-frame odometry: the world
% frame belongs to the window.
posesTrue = data.gt.poses(idx, :);
[drPoses, drHead] = localWindowDeadReckoning(data, idx, posesTrue(1,:), ...
                                             data.gt.headings(idx(1)));

% --- Variables ------------------------------------------------------------
pad = 8;
allXY = [posesTrue; lmTrue; drPoses];
box   = [min(allXY(:,1))-pad, max(allXY(:,1))+pad; ...
         min(allXY(:,2))-pad, max(allXY(:,2))+pad];

vars = core.Variable.empty(1, 0);
for k = 1:K
    vars(end+1) = core.Variable(poseNames(k), 'Dim', 2, 'Type', "pose", 'Domain', box); %#ok<AGROW>
end
for m = 1:nLm
    vars(end+1) = core.Variable(lmNames(m), 'Dim', 2, 'Type', "landmark", 'Domain', box); %#ok<AGROW>
end

% --- Factors, grouped by the increment that introduces them ---------------
factors = core.Factor.empty(1, 0);
increments = struct('k', {}, 'poseName', {}, 'newVariables', {}, ...
                    'factorIndex', {}, 'observations', {});
seenLm = false(1, nLm);
numAmbiguousActual   = 0;
numAmbiguousDeferred = 0;   % no reading is withheld; reported so it says so

% WHICH READINGS LOSE THEIR ASSOCIATION, decided once, up front, for exactly
% the requested fraction. A coin flip per reading would be the obvious way and
% is wrong at this size: on the eight readings of the default window, a fair
% coin at one half delivered one ambiguous reading, so an "ambiguous" case
% would have differed from the known-association one by a single factor. With
% a permutation the fraction is the fraction.
%
% Its own stream, so that which readings lose their association cannot change
% when a method changes how many samples it draws.
assocStream = RandStream('threefry', 'Seed', opts.Seed);
isAmbiguous = false(1, numel(obsAll));
if opts.Association == "ambiguous" && nLm >= 2 && opts.AmbiguityFraction > 0
    % The floor of one applies only to a POSITIVE fraction. It is there so a
    % requested 10% does not round to nothing on an eight-reading window and
    % quietly return a known-association case under an ambiguous label. It
    % used to apply unconditionally, which made fraction 0 impossible: the
    % case came back with exactly one ambiguous factor, so the 0% rung of an
    % ADA sweep was not the control it appears to be and every rung above it
    % was being read against the wrong baseline.
    nAmb = max(1, round(opts.AmbiguityFraction * numel(obsAll)));
    pick = randperm(assocStream, numel(obsAll));
    isAmbiguous(pick(1:nAmb)) = true;
end

for k = 1:K
    newFactorIdx = [];
    newVars = poseNames(k);

    if k == 1
        fp = core.Factor.gaussianVectorUnary(poseNames(1), posesTrue(1,:), ...
                 opts.PriorSigma, 'Name', "f(x1)", 'Counter', counter);
        factors(end+1) = fp; %#ok<AGROW>
        newFactorIdx(end+1) = numel(factors); %#ok<AGROW>
    else
        % The measured increment, in the world frame of this window.
        delta = drPoses(k,:) - drPoses(k-1,:);
        fo = core.Factor.gaussianVectorRelative(poseNames(k-1), poseNames(k), ...
                 delta, opts.OdomSigma, ...
                 'Name', sprintf("f(%s,%s)", poseNames(k-1), poseNames(k)), ...
                 'Counter', counter);
        factors(end+1) = fo; %#ok<AGROW>
        newFactorIdx(end+1) = numel(factors); %#ok<AGROW>
    end

    hereIdx = find([obsAll.poseId] == idx(k));
    obs = struct('landmark', {}, 'landmarkName', {}, 'landmarkId', {}, ...
                 'range', {}, 'rawRange', {}, 'trueRange', {}, ...
                 'ambiguousWith', {}, 'timestamp', {});

    for j = hereIdx
        r  = obsAll(j);
        vi = find(lmIds == r.landmarkId, 1);

        % AMBIGUOUS DATA ASSOCIATION, as the manual defines it: the reading's
        % landmark id is WIPED and the factor becomes a uniform mixture over
        % the candidates, p(r | x, L) = mean_j p(r | x, l_j). Which readings
        % lose their id is drawn from a seeded stream, so the case is the same
        % case on every run and across every method.
        %
        % Not a geometric rule. An earlier version only made a reading
        % ambiguous when another landmark happened to sit at a similar true
        % range, which fired on 4 readings of 66 here and on none at all in
        % Plaza1's window -- an "ambiguous" case with nothing ambiguous in it.
        % Real association failure does not wait for coincidence.
        partner = [];
        if isAmbiguous(j)
            partner = setdiff(1:nLm, vi);
        end

        if isempty(partner)
            fr = core.Factor.rangeFactor(poseNames(k), lmNames(vi), ...
                     r.measuredRange, rangeSigma, ...
                     'Name', sprintf("f(%s,%s)", poseNames(k), lmNames(vi)), ...
                     'Counter', counter);
        else
            numAmbiguousActual = numAmbiguousActual + 1;
            cand = sort([vi partner]);

            % THE ORDINAL IS NOT DECORATION. A factor name has to be unique:
            % methods.nfisam.trainingSampleSimulator names each simulated
            % observation "Z_" + f.Name, so two factors sharing a name become
            % one column asked to hold two measurements, and Algorithm N1
            % stops with "appears twice in the clique layout".
            %
            % Wiping the id is exactly what causes the collision. Under known
            % association a pose's readings are named by their landmarks --
            % f(x4,l0), f(x4,l6) -- and differ. Under ADA both readings from
            % x4 carry the same candidate set, so both would be f(x4;l0|l6).
            % The narrower the window, the fewer candidates, the likelier the
            % clash: with two landmarks it is certain. Numbering by position
            % within the pose keeps the name honest about what the estimator
            % is given, which the discarded id would not.
            fr = core.Factor.ambiguousRangeFactor(poseNames(k), ...
                     lmNames(cand), r.measuredRange, rangeSigma, ...
                     ones(1, numel(cand)), ...
                     'Name', sprintf("f(%s;%s)#%d", poseNames(k), ...
                                     strjoin(cellstr(lmNames(cand)), "|"), ...
                                     numel(obs) + 1), ...
                     'Counter', counter);
        end
        factors(end+1) = fr; %#ok<AGROW>
        newFactorIdx(end+1) = numel(factors); %#ok<AGROW>

        obs(end+1) = struct('landmark', vi, 'landmarkName', lmNames(vi), ...
            'landmarkId', r.landmarkId, 'range', r.measuredRange, ...
            'rawRange', r.rawRange, 'trueRange', r.trueRange, ...
            'ambiguousWith', partner, 'timestamp', r.timestamp); %#ok<AGROW>

        for c = [vi partner]
            if ~seenLm(c)
                newVars(end+1) = lmNames(c); %#ok<AGROW>
                seenLm(c) = true;
            end
        end
    end

    increments(end+1) = struct('k', k, 'poseName', poseNames(k), ...
        'newVariables', newVars, 'factorIndex', newFactorIdx, ...
        'observations', obs); %#ok<AGROW>
end

localAssertDistinctNames(factors);

graph = core.FactorGraph(vars, factors, counter);

% ELIMINATION ORDER IS THE LARGEST SINGLE EFFECT ON THIS CASE, larger than
% the sample budget by an order of magnitude. The min-degree order puts the
% landmarks in the middle -- x1 x2 l0 l6 x3 x4 -- and the per-pose error
% jumps exactly where the poses resume: [0.10 0.95 7.59 8.67] m. A landmark
% here is weakly determined (section above: its posterior is two modes 40 m
% apart), so eliminating it early hands that density to every variable
% eliminated after it, and the support cannot carry it.
%
% Measured at numSamples 200, support 250, across seeds 5/3/7/11/13:
%
%     automatic       pose RMSE 3.5 - 23.0 m,  support ESS  1.4 - 7.3
%     landmarksLast   pose RMSE 1.52 - 1.76 m, support ESS   32 - 236
%
% Not a Plaza-specific trick: it is what a weakly-determined variable does
% to a sample-based elimination, and the grid world hides it only because
% its beacons are well determined. Left as an option so the comparison can
% be made rather than asserted, and applied identically to every method.
% Asked for as a PREFERENCE inside the greedy loop, not by filtering a
% finished order. The filtering version worked up to nine poses and then
% stranded a variable: min-degree uses the landmarks as connectors, so lifting
% them out of the middle of a finished order cuts whatever they joined. See
% core.eliminationOrder's Defer option, which cannot fail that way because the
% choice is still made from the eligible set at every step.
if opts.EliminationOrder == "landmarksLast"
    [order, orderInfo] = core.eliminationOrder(graph, 'Defer', lmNames);
else
    [order, orderInfo] = core.eliminationOrder(graph);
end

% --- Case bundle ----------------------------------------------------------
% Both are reported because they are not interchangeable and confusing them
% is what produced an earlier, wrong account of this case's size: the
% engine's regime is stated in VARIABLES (ten to thirteen, per map), while the cost of
% a separator is stated in dimensions.
nVar = K + nLm;
nDim = 2 * nVar;

caseData = struct();
caseData.name            = sprintf("plaza_%s_%s", lower(data.name), opts.Association);
caseData.displayName     = sprintf("%s: real range-only data, %d-keyframe window", ...
                                   data.name, K);
caseData.variant         = opts.Association;
caseData.graph           = graph;
caseData.counter         = counter;
caseData.eliminationOrder = order;
caseData.orderInfo       = orderInfo;
caseData.targetVariable  = order(end);
caseData.pathVariables   = order(1:min(2, numel(order)-1));
caseData.numIncrements   = K;
caseData.increments      = increments;
caseData.engine          = "general";

% Said out loud rather than inferred from which fields happen to exist. A new
% case that forgets this would be scored against a quadrature reference built
% for the two-pose benchmark, which would not fail -- it would be wrong.
caseData.referenceKind   = "truthOnly";

caseData.groundTruth = struct( ...
    'poses', posesTrue, 'poseNames', poseNames, ...
    'landmarks', lmTrue, 'landmarkNames', lmNames, ...
    'observedLandmarks', seenLm);

% A MAP AND A MISSION, so this case reads through the same views as the grid
% world rather than needing its own. The plaza really is open ground: the
% blocks list is empty, which makes every occupancy cell free and every line
% of sight clear, and that is a fact about the site rather than a placeholder.
% The bounds frame the WINDOW and its landmarks, not the whole 68 m plaza --
% the run in full is in caseData.plaza for the panels that draw it behind.
caseData.map = localWindowMap(posesTrue, lmTrue, drPoses, opts.SensorRange);
caseData.mission = struct( ...
    'waypoints',   posesTrue, ...
    'truePoses',   posesTrue, ...
    'headings',    data.gt.headings(idx), ...
    'poseNames',   poseNames, ...
    'start',       posesTrue(1,:), ...
    'goal',        posesTrue(end,:), ...
    'sensorRange', opts.SensorRange, ...
    'domain',      caseData.map.bounds(1:2));

caseData.landmarks = struct( ...
    'truePositions', lmTrue, 'names', lmNames, ...
    'ids', lmIds, 'observed', seenLm);

% Everything a plot needs to put this window back into the run it came from:
% the whole true path, all four surveyed nodes including the ones this window
% never sees, and the dead reckoning the odometry actually carries.
%
% windowRelaxed is a boolean beside the prose of windowChoice, so a panel or a
% test can ask "did the rules actually hold" without parsing a sentence.
caseData.plaza = struct( ...
    'dataset',        data.name, ...
    'windowStart',    w0, ...
    'windowKeyframes', idx, ...
    'windowChoice',   choice, ...
    'windowRelaxed',  startsWith(choice, "relaxed"), ...
    'fullPath',       data.gt.fullPath, ...
    'allLandmarks',   data.gt.landmarks, ...
    'allLandmarkIds', data.landmarkIds, ...
    'keyframePath',   data.gt.poses, ...
    'deadReckoned',   drPoses, ...
    'deadReckonedHeadings', drHead, ...
    'times',          data.keyframes.time(idx), ...
    'calibration',    data.calibration, ...
    'sensorRange',    opts.SensorRange, ...
    'numVariables',   nVar, ...
    'numDimensions',  nDim, ...
    'source',         data.source);

caseData.settings = struct( ...
    'dataset', data.name, 'windowStart', w0, 'numPoses', K, ...
    'numLandmarks', nLm, 'numVariables', nVar, 'numDimensions', nDim, ...
    'maxVariables', opts.MaxVariables, ...
    'eliminationOrderChoice', opts.EliminationOrder, ...
    'sensorRange', opts.SensorRange, 'rangeSigma', rangeSigma, ...
    'odomSigma', opts.OdomSigma, 'priorSigma', opts.PriorSigma, ...
    'association', opts.Association, ...
    'requestedAmbiguityFraction', opts.AmbiguityFraction, ...
    'numAmbiguousReadings', numAmbiguousActual, ...
    'effectiveAmbiguityFraction', numAmbiguousActual / max(numel(obsAll), 1), ...
    'numAmbiguityDeferredForInitialization', numAmbiguousDeferred, ...
    'keyframeSpacing', opts.KeyframeSpacing, ...
    'numReadings', numel(obsAll));

caseData.latex = struct( ...
    'graph',  "$f(x_1)\prod_k f(x_k,x_{k+1}) \prod_{(k,m)\in\mathcal{V}} f(x_k,l_m)$", ...
    'target', sprintf("$f_{\\mathrm{new}}(%s \\mid D)$", ...
                      regexprep(order(end), '^([a-zA-Z]+)(\d+)$', '$1_{$2}')), ...
    'range',  "$\tilde r = \|l_m - x_k\| + \xi,\ \xi\sim\mathcal N(0,\sigma_r^2)$", ...
    'calibration', "$r_{\mathrm{cal}} = r_{\mathrm{raw}} - (a\,r_{\mathrm{raw}} + b)$", ...
    'headline', sprintf("Real radio ranges: %d readings over %d keyframes, %d variables", ...
                        numel(obsAll), K, nVar));
end

% =========================================================================
function readings = localWindowReadings(data, sensorRange)
%LOCALWINDOWREADINGS The readings short enough to be admitted, all keyframes.
%   Inputs   DATA the dataset, SENSORRANGE the longest range admitted
%   Outputs  READINGS, the surviving readings
%   Utility  apply the sensor range once, before any window is chosen, so the
%           choice is made over the readings the case will actually hold.
keep = [data.ranges.measuredRange] <= sensorRange;
readings = data.ranges(keep);
end

% =========================================================================
function map = localWindowMap(poses, lm, dr, sensorRange)
%LOCALWINDOWMAP An empty occupancy map framing the window.
%   Inputs   POSES, LM, DR the tracks and landmarks to frame, SENSORRANGE
%   Outputs  MAP, with bounds, an empty block list and a cell size
%   Utility  give the engine and the figures one length scale for the window.
%   The grid world's map carries obstacles; the plaza has none, so this is
%   the same structure with an empty block list. It exists so that the map
%   view, the graph layout and the engine's own scale check all read the
%   Plaza case through the paths they already use.
pad = 10;
all = [poses; lm; dr];
map = struct();
map.bounds = [min(all(:,1))-pad, max(all(:,1))+pad, ...
              min(all(:,2))-pad, max(all(:,2))+pad];
map.blocks = zeros(0, 4);
map.cellSize = 1;

xs = map.bounds(1) : map.cellSize : map.bounds(2);
ys = map.bounds(3) : map.cellSize : map.bounds(4);
map.gridX = xs(1:end-1) + map.cellSize/2;
map.gridY = ys(1:end-1) + map.cellSize/2;

[GX, GY] = ndgrid(map.gridX, map.gridY);
map.occupancy = false(size(GX));
map.cellCentres = [GX(:) GY(:)];

% Cumulative coverage, one page per pose. With no obstacles this is a union
% of discs, and the shadows the grid world's version computes cannot occur.
map.explored = false([size(GX) size(poses,1)]);
seen = false(size(map.cellCentres, 1), 1);
for k = 1:size(poses, 1)
    seen = seen | vecnorm(map.cellCentres - poses(k,:), 2, 2) <= sensorRange;
    map.explored(:,:,k) = reshape(seen, size(GX));
end
end

% =========================================================================
function kept = localThinReadings(obs, data, idx, maxPerPair)
%LOCALTHINREADINGS At most MAXPERPAIR readings per pose-landmark pair.
%   Inputs   OBS the readings, DATA the dataset, IDX the window keyframes,
%            MAXPERPAIR the cap
%   Outputs  KEPT, a logical mask over OBS
%   Utility  stop one pose-landmark pair from contributing dozens of nearly
%           identical factors.
%   The radios ping several times between keyframes: Plaza2's first window
%   carries sixty-six readings across four poses, sixteen per pose. Keeping
%   them all is not free information. Repeated readings of the same range
%   from the same pose average down the noise -- sixteen of them shrink it
%   fourfold -- so the posterior comes out sharp and unimodal and the case
%   stops showing the shape it exists to show. It also puts seventy factors
%   on twelve variables, which is a different problem from the one the papers
%   solve.
%
%   The kept reading is the one nearest in time to its keyframe, which is the
%   ordinary keyframing choice: the keyframe stands for an instant, and the
%   reading closest to that instant is the one least displaced from it.
kept = obs([]);
pairs = unique([[obs.poseId].', double([obs.landmarkId]).'], 'rows');

for i = 1:size(pairs, 1)
    sel = find([obs.poseId] == pairs(i,1) & [obs.landmarkId] == pairs(i,2));
    tKey = data.keyframes.time(idx == pairs(i,1));
    [~, ord] = sort(abs([obs(sel).timestamp] - tKey));
    kept = [kept, obs(sel(ord(1:min(maxPerPair, numel(sel)))))]; %#ok<AGROW>
end

[~, ord] = sort([kept.timestamp]);
kept = kept(ord);
end

% =========================================================================
function [w0, note] = localChooseWindow(data, readings, K, maxLm, maxVars)
%LOCALCHOOSEWINDOW The best-constrained window that the engine can still hold.
%   Inputs   DATA, READINGS, K the window length, MAXLM and MAXVARS the caps
%   Outputs  W0 the chosen first keyframe, NOTE the rule and what it picked
%   Utility  choose the window by a stated rule and say so, rather than by a
%           number someone liked.
%   Deterministic and stated, rather than a number someone liked. Among the
%   qualifying windows the one with the most pose-landmark pairs wins, ties
%   going to the earliest, because a window with five readings and one with
%   twelve are different demonstrations and the richer one is the case worth
%   shipping as the default. A window qualifies when it is inside the
%   engine's regime and has enough readings to constrain what it contains:
%
%     at least two landmarks   one landmark and four poses is a range-only
%                              problem with a rotational freedom the prior
%                              alone pins down; interesting, but it is not
%                              the SLAM problem the papers ran
%     at most MaxLandmarks     K + L variables must stay inside the engine's
%                              measured-safe regime. Bounded by the office's
%                              thirteen, which at K = 4 would allow nine. The tighter default of two is the
%                              configuration actually measured end to end;
%                              a four-landmark window is eight variables with
%                              a 5-variable separator and has NOT been
%                              validated. Raise it deliberately, and re-measure
%     each landmark ranged from at least two DIFFERENT poses, so that no
%                              landmark is left on a single annulus with
%                              nothing to intersect it against. Distinct
%                              poses rather than distinct readings: the
%                              thinning below keeps one reading per pose and
%                              landmark, so two readings from one pose become
%                              one, and counting readings here would promise
%                              an intersection the window cannot deliver
%
%   If nothing qualifies -- a short sequence, a tight range limit -- the
%   first window with any reading at all is returned rather than an error,
%   and the note says which rule was relaxed.
own = [readings.poseId];
ids = [readings.landmarkId];
nKf = numel(data.steps);

fallback = [];
best = struct('w', [], 'pairs', -1, 'nLm', 0, 'minPoses', 0);

for w = 1:nKf - K + 1
    sel = ismember(own, w:w+K-1);
    if ~any(sel), continue, end
    if isempty(fallback), fallback = w; end

    here = ids(sel);
    poses = own(sel);
    u = unique(here);
    if numel(u) < 2 || numel(u) > maxLm || K + numel(u) > maxVars, continue, end

    seenFrom = arrayfun(@(id) numel(unique(poses(here == id))), u);
    if any(seenFrom < 2), continue, end

    % One factor per pose-landmark pair, which is what survives the thinning.
    pairs = size(unique([poses(:), double(here(:))], 'rows'), 1);
    if pairs > best.pairs
        best = struct('w', w, 'pairs', pairs, 'nLm', numel(u), ...
                      'minPoses', min(seenFrom));
    end
end

if ~isempty(best.w)
    w0 = best.w;
    note = sprintf(['best-constrained window: %d landmarks, %d readings, ' ...
                    'each landmark ranged from %d+ poses, %d dimensions'], ...
                   best.nLm, best.pairs, best.minPoses, 2*K + 2*best.nLm);
    return
end

if isempty(fallback)
    error('datasets:makePlazaCase:noWindow', ...
        ['No %d-keyframe window of %s has a single admitted range reading. ' ...
         'The sensor range is probably too short.'], K, data.name);
end
% Loud, because this window satisfies NONE of the rules above and everything
% downstream goes on treating it as though it did. It can carry one landmark,
% or a landmark ranged from a single pose, or more variables than the engine
% has been measured to hold -- and the only previous signal was a note nobody
% reads. Raising K walks into this: at twelve poses on Plaza2 nothing
% qualifies and the case silently became fifteen variables.
%
% A warning rather than an error: a relaxed window is still a legitimate thing
% to ask for deliberately, and refusing would make MaxVariables a trap instead
% of a limit. The caller is told, and plaza.windowRelaxed records it so a
% panel can say so too.
w0 = fallback;
note = sprintf(['relaxed: NO window of %d keyframes satisfies the rules ' ...
                '(2..%d landmarks, each ranged from 2+ poses, at most %d ' ...
                'variables); fell back to the first window with any reading'], ...
               K, maxLm, maxVars);
warning('datasets:makePlazaCase:relaxedWindow', ...
    ['%s on %s. The case is still built, but it is outside the regime the ' ...
     'engine is measured on -- lower NumPoses, or raise MaxLandmarks or ' ...
     'MaxVariables deliberately and re-measure.'], note, data.name);
end

% =========================================================================
function localAssertWindow(data, w0, K)
%LOCALASSERTWINDOW The window has to fit inside the sequence.
%   Inputs   DATA the dataset, W0 the first keyframe, K the length
%   Outputs  none; errors when the window runs past the end
%   Utility  reject an impossible window here rather than indexing past it.
nKf = numel(data.steps);
if ~isscalar(w0) || w0 < 1 || w0 ~= round(w0) || w0 + K - 1 > nKf
    error('datasets:makePlazaCase:badWindow', ...
        ['WindowStart must be an integer in 1..%d for a %d-keyframe window ' ...
         'of %s, which has %d keyframes; got %s.'], ...
        nKf - K + 1, K, data.name, nKf, mat2str(w0));
end
end

% =========================================================================
function localAssertDistinctNames(factors)
%LOCALASSERTDISTINCTNAMES Two factors must not share a name.
%   Inputs   FACTORS, the assembled factor array
%   Outputs  none; errors on a duplicate name
%   Utility  names are identities elsewhere, so a collision silently merges
%           two measurements.
%   NF-iSAM names each simulated observation "Z_" + factor name, so a shared
%   name silently becomes one column carrying two measurements and surfaces
%   far away, inside Algorithm N1's clique layout. Ambiguous association is
%   what makes the clash reachable: it strips the landmark id that otherwise
%   tells a pose's readings apart. Checked here, where the fix is obvious,
%   rather than left for whichever method happens to trip on it first.
names = arrayfun(@(f) f.Name, factors);
[u, ~, ic] = unique(names);
dup = u(accumarray(ic, 1) > 1);
if ~isempty(dup)
    error('datasets:makePlazaCase:duplicateFactorName', ...
        ['%d factor name(s) used twice: %s. Every factor needs its own ' ...
         'name; see the ordinal in the ambiguous-range branch above.'], ...
        numel(dup), strjoin(dup, ', '));
end
end

% =========================================================================
function [xy, th] = localWindowDeadReckoning(data, idx, anchorXY, anchorTh)
%LOCALWINDOWDEADRECKONING The odometry chain, rebuilt from the window's anchor.
%   Inputs   DATA, IDX the window keyframes, ANCHORXY and ANCHORTH its start
%   Outputs  XY the dead-reckoned track, TH its headings
%   Utility  re-anchor the dead reckoning to the window, since the dataset's
%           legs are expressed relative to their own first keyframe.
%   The dataset carries each leg in the body frame of its own first keyframe,
%   so a window integrates them from wherever it starts. This is what makes a
%   window a window rather than a slice of one particular global solution:
%   nothing here depends on where the run began.
xy = zeros(numel(idx), 2);
th = zeros(numel(idx), 1);
xy(1,:) = anchorXY;
th(1)   = anchorTh;

for k = 2:numel(idx)
    leg = data.odom(idx(k) - 1);       % the leg ending at keyframe idx(k)
    c = cos(th(k-1)); s = sin(th(k-1));
    xy(k,:) = xy(k-1,:) + [c*leg.deltaLocal(1) - s*leg.deltaLocal(2), ...
                           s*leg.deltaLocal(1) + c*leg.deltaLocal(2)];
    th(k)   = th(k-1) + leg.dTheta;
end
end
