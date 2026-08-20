function caseData = makeGridWorldCase(opts)
%MAKEGRIDWORLDCASE A robot on a blocked map, running a waypoint mission.
%
%   Inputs
%     Layout      "office" (default), "corridor" or "warehouse"
%     NumPoses    poses on the mission path        default from the layout
%     SensorRange range at which a beacon is seen  default from the layout
%     Association "known" (default) or "ambiguous"
%     Seed        measurement-noise seed                        default 11
%     (the remaining options are listed under Name-value options below)
%
%   Outputs
%     CASEDATA  the case struct, plus the map, the explored-cell pages and
%               the mission the poses were walked along
%     CASEDATA.settings reports what the association actually came out as:
%               numRangeReadings, numAmbiguousReadings,
%               effectiveAmbiguityFraction and, always zero,
%               numAmbiguityDeferredForInitialization. There is no requested
%               fraction here: ambiguity is geometric, so the fraction is a
%               measurement of the layout rather than a target to be met
%     CASEDATA.settings also carries nominalNumPoses for the layout and a
%               caseProfile of "nominal" or "stress" with caseProfileReason.
%               A K past the layout's measured pose count is scalability
%               evidence and is labelled so, since unlabelled beside the
%               nominal runs it would read as the benchmark getting worse
%
%   Utility
%     Build the general planar SLAM case that the two-pose benchmark is the
%     three-node special case of: K planar poses, M planar landmarks, odometry
%     between consecutive poses, and range-only measurements to whichever
%     beacons are in range and in line of sight past the blocks.
%
%   This is the case study that makes the comparison mean something. Range
%   without bearing leaves a landmark on an annulus, two annuli intersect in
%   two points, and a loop closure either resolves that ambiguity or collapses
%   the wrong mode. None of that is visible in a trajectory plot, which is the
%   argument spec section 3 makes for the whole app.
%
%   Name-value options:
%     Layout      "office" (default), "corridor" or "warehouse"
%     NumPoses    poses on the mission path             default: the
%                 layout's own, 5 for office, 6 for corridor and warehouse
%     SensorRange maximum range at which a beacon is seen  default: the
%                 layout's own, 5.5 m for office and corridor, 4.0 m for
%                 the warehouse. See WHY SENSOR RANGE IS PER LAYOUT below.
%     RangeSigma  standard deviation of a range reading          default 0.30
%     OdomSigma   standard deviation of odometry, per axis       default 0.25
%     PriorSigma  standard deviation of the prior on x1          default 0.20
%     Association "known" (default) or "ambiguous"
%     Blocks      override the layout's obstacles, [x y w h] per row
%     CellSize    occupancy cell size for the explored-grid view default 0.5
%     Seed        measurement-noise seed                         default 11
%     Counter     a core.EvalCounter shared by all factors
%
%   WHY THE OFFICE DEFAULT IS FIVE POSES. Past about thirteen variables the
%   office's numbers stop being trustworthy, and the office route has exactly
%   five stations, so five poses is both the complete mission and the last
%   size inside the regime. The two facts lining up is luck, not design, and
%   the measurement is what settles it. Each layout carries its own default
%   for the same reason and by the same measurement -- corridor six,
%   warehouse six -- and they live in datasets.gridWorldDefaults. At
%   numSamples 200, separator support 250, over the five seeds
%   [5 3 7 11 13]:
%
%       poses  variables  beacons  pose RMSE, per seed          median  landmark
%         4       11         7      0.40 0.66 0.86 0.23 1.09     0.66     3.98 m
%         5       13         8      0.40 1.01 0.75 0.18 1.35     0.75     3.94 m
%         6       14         8      2.56 18.3 12.9 11.1 13.5    12.86    14.66 m
%         7       15         8     11.39 15.0 12.8  4.30 6.73    11.39    11.81 m
%
%   On THIS layout that is not a gradual decay but a cliff between thirteen
%   and fourteen variables: every seed under 1.4 m at thirteen, four of five
%   over 11 m at fourteen.
%
%   AND THE NUMBER THIRTEEN DOES NOT TRAVEL. The warehouse was added to test
%   that, and it falsified it. Same engine, same budget, same support size,
%   from methods.gridWorldSweepPlan's eighteen cells:
%
%       office     13 variables    0.2 - 1.2 m   (twelve cells, four seeds)
%       warehouse  13 variables          7.5 m
%       warehouse  10 variables    9.2 - 12.7 m
%       office     14 variables    1.4 - 17.5 m
%
%   The warehouse is already gone three variables BELOW the office's ceiling,
%   and the office at fourteen is a spread rather than a uniform failure. So
%   "sound to about thirteen variables" is a fact about the office layout and
%   was never a fact about the engine; it read as one because it had only
%   ever been measured on one map. What survives is the weaker, true claim:
%   within a fixed geometry, error rises sharply with mission length, and
%   where it turns is a property of the map.
%
%   THREE EXPLANATIONS TESTED AND ELIMINATED, so that the next person does
%   not spend the time again:
%
%     Map scale. The warehouse diagonal is 28.8 m against the office's
%     24.4 m -- 18% larger, against an order of magnitude in the error. Not
%     a units artefact.
%
%     The variable count itself. Raising the warehouse's sensor range brings
%     more beacons into view, so it ADDS variables -- and the error falls.
%     Warehouse, five poses, seed 11, same budget:
%
%         range   variables   Slices    Smoothed Slices
%          4.0 m      10       9.19 m       13.46 m
%          4.5 m      12       9.86 m        2.19 m
%          5.0 m      13       7.48 m        6.05 m
%          5.5 m      13       7.48 m        6.05 m
%          6.0 m      13       7.48 m        6.05 m
%
%     Three more variables, less error, same map and same route. That is the
%     opposite of what "more variables is worse" predicts. (The range stops
%     buying beacons after 5.0 m because the remaining ones are behind racks
%     -- occlusion, not distance, which is what the warehouse was for.)
%
%     Loop closure. The office route ends 2.5 m from where it started and the
%     warehouse's ends 21 m away, which looks like the answer until you list
%     the factors: there is no loop-closure factor in ANY layout. All three
%     are open odometry chains, so the office's route nearly closing buys the
%     estimator precisely nothing. An earlier version of this comment said
%     "the loop closes at the fifth" -- it closes on the picture, not in the
%     graph.
%
%   IT IS NOT SEPARATOR SIZE EITHER, which is the one negative result that
%   held up. The largest separator is three variables at every row of the
%   office table above, including the fourteen-variable row that fails, and
%   the warehouse fails on separators of two. The same finding from the other
%   direction is in datasets.makePlazaCase: two elimination orders with
%   identical separator sizes differ tenfold in pose RMSE.
%
%   AND IT IS NOT TOTAL PATH LENGTH, WHICH THIS COMMENT USED TO OFFER AS THE
%   LAST CANDIDATE. It said drift accumulates along the chain and the office's
%   route is much the most compact of the three. The second half is simply
%   false: the office route is 53.5 m, the warehouse's 44.0 m and the
%   corridor's 24.0 m, so the office is the LONGEST of the three and is also
%   the one that is accurate at its own default. The hypothesis never fitted
%   the layout it was proposed to explain.
%
%   Measured, it fails twice more. localWalkPath subdivides a route rather
%   than extending it once the pose count passes the station count, so pose
%   count can be moved with the path length, the map and the beacon set all
%   held fixed. Two such comparisons, seed 11 at the usual budget:
%
%       layout      poses  path    variables   Slices   Smoothed
%       office        5    53.5 m      13        0.87      1.13
%       office        8    53.5 m      16       22.73     10.05
%       warehouse     8    44.0 m      15       13.10      4.53
%       warehouse    12    44.0 m      19        3.94      1.50
%
%   Same path, same beacons, more poses -- and the office gets an order of
%   magnitude worse while the warehouse gets three times better. One
%   direction would have been evidence; two opposite directions mean path
%   length is not the mechanism, and neither is pose count on its own.
%
%   SO NO MECHANISM IS NAMED HERE. Map scale, variable count, loop closure,
%   separator width and path length have each been tested and each failed.
%   What is left is a correlation that has not been isolated: the
%   configurations that hold their accuracy tend to be the ones whose beacons
%   accumulate three or more sightings. Beacon count, sightings per beacon
%   and pose spacing all move together across these layouts, and nothing
%   measured separates them. It is written down as the next experiment, and
%   this time as a correlation rather than as a reason.
%
%   ONE CAUTION ON READING ANY OF THESE NUMBERS. The scatter between runs of
%   the SAME configuration is large: the warehouse at five poses measured
%   12.7 m in the sweep and 9.2 m in a probe. Differences under about 3 m
%   are not evidence of anything here.
%
%   Both engine diagnostics call the cliff before the RMSE does -- support
%   effective sample size collapses and the nearest-support lookup distance
%   climbs -- and runGeneralCore turns those into warnings on the result.
%   Larger missions are allowed and will say so loudly; the default is the
%   regime where the numbers can be trusted.
%
%   The landmark column is in the table because leaving it out was
%   flattering. It never drops below about 3.9 m even in the good rows:
%   several beacons are seen from a short arc, which fixes them only up to
%   reflection in it, and the mean of a two-mode posterior is not an
%   estimate of either mode. Pose RMSE alone would report this case as
%   solved.
%
%   The default was six until the mission path was fixed to go around the
%   blocks rather than through them. The corrected route passes closer to
%   one more beacon, which bought a fourteenth variable and dropped the
%   case off the cliff -- so the collision fix cost a pose, and the pose it
%   cost was the redundant midpoint on the long bottom leg rather than any
%   part of the route.
%
%   A BEACON SEEN ONCE NEVER CONVERGES, and the office layout is full of
%   them. One range reading leaves a landmark on an annulus whose mean sits
%   at the observing pose, so its error is bounded below by the range itself
%   however many samples are spent -- a fine demonstration of why RMSE is the
%   wrong metric, and a poor property for a default case. The comment here
%   used to claim the sensor range was set so that each beacon is seen by two
%   or three CONSECUTIVE poses. Counted, at seed 11:
%
%       layout      poses  observed beacons  sightings each
%       office        5          8 of 8      1 1 1 1 1 1 1 1
%       office        7          8 of 8      2 2 1 1 2 2 1 1
%       corridor      6          4 of 4      3 3 2 3
%       warehouse     6          6 of 13     2 2 2 2 2 1
%
%   At its own default the office sees every one of its eight beacons
%   EXACTLY ONCE. The claim was true of a denser pose schedule than the one
%   that ships, and the layout was never re-checked after the pose count
%   changed. The office is kept as it is -- it is the layout every number in
%   the cliff table was measured on -- and the warehouse is placed to the
%   rule the comment stated: a beacon near the midpoint of a leg is about
%   3 m from both of its ends, and 3 m is inside the warehouse's 4 m range
%   while the 6 m from one station to the next is not.
%
%   WHICH CONFIGURATION AN INCREMENT ANIMATION CAN BE DRAWN ON, and why it is
%   not this layout at its default. The map view is stepped through the
%   increments as a sequence, so an animation needs three things at once:
%   frames, beacons that are re-observed so that something visibly tightens,
%   and an estimate that stays on the map for the whole mission. The office
%   default gives five frames, one sighting per beacon, and no ambiguous
%   readings at all. Running it longer does not buy any of the three. Seed 11,
%   pose RMSE in metres:
%
%       poses  variables  separator   Slices   Smoothed
%         5       13          6         0.87      1.13
%         7       15          6         3.65      7.91
%         8       16          4        22.73     10.05
%         9       17          4        21.51      9.53
%        10       18          4         3.95     16.05
%        12       20          4        12.19      4.46
%
%   NOT WIDTH, AND NOT BUDGET EITHER. The separator NARROWS to four dimensions
%   at eight poses and above and the case fails there anyway, which is the
%   verdict the warehouse already gave from the other direction. And at nine
%   poses, raising the separator support from 201 to 601, 1201 and 2001 points
%   moves Slices to 7.65, 11.63 and 11.24 m and Smoothed Slices to 14.14, 10.42
%   and 1.98 m. That is scatter, not convergence, and the last of those cells
%   costs 620 s for two methods.
%
%   AND THE ANIMATION IS THE AMBIGUOUS RUN, WHICH CHANGES WHICH SEPARATOR
%   COUNTS. A gaussian map sequence shows two trajectories closing on a
%   reference, which the estimator-versus-reference figure shows better. The
%   one thing only the map sequence shows is the alternative association --
%   viz.plotMapStep's dashed line to the other beacon a reading could have come
%   from. So the layout has to be chosen on the AMBIGUOUS graph, and an
%   ambiguous factor couples its pose to TWO landmarks and joins them in the
%   clique. The two separators are not the same number:
%
%       layout      poses  variables  sep known  sep ambiguous  ambiguous
%       corridor      9        13         6           10          4 of 16
%       corridor     12        16        10           14          6 of 22
%       warehouse     9        16         4            4         10 of 15
%       warehouse    12        19         4            6         10 of 18
%       warehouse    14        21         4            6         10 of 20
%       office        9        17         4            4          6 of 16
%
%   THE CORRIDOR LENGTHENS WELL KNOWN AND BADLY AMBIGUOUS. It carries four
%   beacons against the office's eight, so a longer mission adds one variable
%   per pose instead of one per pose and a beacon with it, and at nine poses it
%   is thirteen variables on a six-dimensional separator -- the office's
%   five-pose shape, reached with nine frames rather than five:
%
%       poses  variables  separator   Slices   Smoothed   support ESS
%         6       10          4         2.29      8.63     1.1 / 7.8
%         7       11          6         1.81      2.24    15.5 / 6.8
%         8       12          6         1.09      3.41    25.8 / 24.4
%         9       13          6         1.91      2.49    25.8 / 24.4
%        10       14          8         2.42      2.20     8.0 / 17.7
%        12       16         10         3.15      2.76    13.1 / 1.9
%
%   But those are the KNOWN numbers. Turn the association on and the same nine
%   pose cell is a ten-dimensional separator, which is the wall the finite
%   support is already known to hit here and on both Plaza windows. Over seeds
%   3, 7, 11, 13 and 17 it spans 1.96 to 4.78 m for Slices and 3.32 to 7.57 m
%   for Smoothed Slices, and at the last increment both estimates sit in the
%   left third of a sixteen-metre map while the vehicle is at x = 15. It
%   animates; it does not track.
%
%   THE WAREHOUSE HOLDS THE AMBIGUOUS SEPARATOR DOWN WHILE RAISING THE
%   AMBIGUITY. Thirteen beacons mean a reading has more neighbours that could
%   have produced it -- ten of eighteen ambiguous rather than four of sixteen --
%   while the aisles keep only a few in range at once, so the cliques stay
%   narrow. Ambiguous, two seeds, same engine and budget:
%
%       poses  variables  sep   Slices s11/s17   Smoothed s11/s17   seconds
%         9       16       4      3.86 / 1.54       2.08 / 3.41       5-9
%        10       17       6      2.24 / 2.51       3.31 / 3.63        7
%        12       19       6      2.14 / 2.58       1.63 / 3.04       10
%        14       21       6      0.91 / 3.41       2.83 / 4.40       10
%
%   Every warehouse row beats every corridor and office row, at a fifth of the
%   cost, so twelve poses is chosen inside the layout rather than against it:
%   it is where the two seeds sit closest together on both methods, with twelve
%   frames and sightings of three, three, three, three, two, two and two.
%
%   TWO CAUTIONS TRAVEL WITH THAT CELL. Six of its thirteen beacons are never
%   observed and the map draws all thirteen, so stars and rays will not tally --
%   the reason is range and occlusion, not a filtered figure. And ambiguity
%   still widens the graph, four to six on the same nineteen variables, so a
%   gap between the two associations is ambiguity AND width together and
%   belongs to neither alone. Six is inside the range every other shipped case
%   runs at, where the corridor's ten was not, so the control is worth reading
%   here in a way it was not there.
%
%   THE SEED SCATTER IS PART OF THE RESULT AND NOT AN ASIDE, on either layout.
%   The corridor known at nine poses, over the same five seeds:
%
%       seed        3     7    11    13    17
%       Slices    1.29  2.41  1.91  4.91  0.52
%       Smoothed  3.84  2.89  2.49  1.50  2.31
%
%   That is a wide band, and no cell in any table here should be quoted from a
%   single draw. What separates these layouts from the office is not that they
%   are tight but that they never leave the map: the office's eight- and
%   nine-pose cells sit above 20 m, larger than the layout is wide, and its
%   nine-pose cell run ambiguous is 8.53 and 5.94 m on a separator still four
%   wide -- so the office cliff is not the association either. The support
%   effective sample size moves with the seed too, falling to 1.1 on some
%   draws, so a run of any of these can still raise the coverage warning.
%
%   campaign.protocol_P20_gridWorldAnimation runs it and writes the frames.
%
%   WHY SENSOR RANGE IS PER LAYOUT. It is not a taste setting, it is what
%   decides how many variables the graph has: every beacon within range is a
%   new planar variable. The warehouse layout is denser than the office --
%   eight obstacles rather than four, thirteen beacons rather than eight,
%   packed into aisles -- so the office's 5.5 m would put five or six beacons
%   in view of the first two poses alone. Its 4.0 m was the range measured to
%   keep the six-pose mission under thirteen variables while still giving
%   every beacon it sees more than one sighting. Passing SensorRange
%   explicitly overrides the layout's choice, which is what
%   methods.gridWorldSweepPlan does to sweep the axis on purpose.
%
%   THAT REASONING IS NOW KNOWN TO BE BACKWARDS, and the range is left at 4.0
%   anyway. Holding the variable count down was supposed to keep the case
%   trustworthy; measured, the warehouse at 4.0 m and ten variables is worse
%   than the same route at 5.0 m and thirteen. Tightening the range to buy
%   variables spent sightings to get them, and the sightings were the part
%   that mattered. It stays at 4.0 because every table here was measured at
%   4.0 -- changing it would move numbers that are cited in four other files
%   and prove nothing that the 4.5/5.0/5.5/6.0 measurement above has not
%   already shown.
%
%   WHAT THE WAREHOUSE COSTS IN MISSION LENGTH, measured the same way. Its
%   route is eight stations rather than five, but a pose at a leg midpoint
%   brings a beacon into view with it, so over most of the route the variable
%   count climbs by TWO per pose rather than by one:
%
%       poses       3   4   5   6   7   8
%       variables   6   8  10  12  14  15
%
%   Six poses, twelve variables, is its default -- chosen as "the last
%   mission length inside the regime", which the measurement above says was
%   never the right way to choose it. It is kept as the baseline every
%   warehouse number on record was taken at. The full eight-station route is
%   a fifteen-variable graph; it is allowed, and it says so through the same
%   warnings the office does.
%
%   AND ITS SEPARATORS ARE NARROWER, WHICH IS THE POINT. Largest separator is
%   four dimensions -- two planar variables -- at every pose count above,
%   against the office's six. A map with twice the obstacles and a route that
%   weaves produces a NARROWER graph, because a beacon at a leg midpoint is
%   seen from exactly the two poses either side of it and couples nothing
%   else. So the warehouse at fourteen variables was a direct test of the
%   separator-width explanation, and it settled it: it fails there too, at
%   17.2 m, on separators two dimensions narrower than the office's. Narrower
%   graph, same failure. Width is not the mechanism.
%
%   It also failed at TEN variables, which is not what it was asked and is
%   the more useful answer -- see the tables above.
%
%   THE WAREHOUSE EXISTS TO BREAK THE OFFICE'S CONVENIENCES. The office is a
%   single perimeter loop around four rooms, and every beacon in it lines a
%   corridor the robot drives down: nothing is ever seen through a gap, and
%   the route never has to choose between two ways round. The warehouse is
%   six racks in two rows with cross-aisles between them, so the route weaves,
%   sightings cut across aisles at an angle, and a beacon three aisles away is
%   occluded by racks rather than by distance. Same engine, same factors, a
%   geometry that does not flatter them.
%
%   The returned structure carries the usual case contract plus a MAP, a
%   MISSION and an INCREMENTS block, so the map view and the increment slider
%   read from the case rather than from any one method's result.

arguments
    opts.Layout (1,1) string {mustBeMember(opts.Layout, ["office","corridor","warehouse"])} = "office"
    % NaN means "the layout's own", as for SensorRange and for the same
    % reason: the pose count that fills a route without leaving the engine's
    % regime is a property of the route, and one number cannot be right for
    % a five-station office and a seven-station warehouse.
    opts.NumPoses (1,1) double = NaN
    % NaN means "the layout's own range", resolved below. mustBePositive
    % would reject that sentinel, so the check is made after resolution --
    % and it is still made, because an explicit SensorRange of 0 or -1 is a
    % caller error and not a layout default.
    opts.SensorRange (1,1) double = NaN
    opts.RangeSigma (1,1) double {mustBePositive} = 0.30
    opts.OdomSigma (1,1) double {mustBePositive} = 0.25
    opts.PriorSigma (1,1) double {mustBePositive} = 0.20
    opts.Association (1,1) string {mustBeMember(opts.Association, ["known","ambiguous"])} = "known"
    % Blocks overrides the layout's obstacles, as [x y w h] per row. It
    % exists so the build-time clearance check can be exercised against a
    % route that is known to be blocked; the shipped layouts are clear, so
    % without it the assertion could only be tested by breaking one.
    opts.Blocks double = []
    opts.CellSize (1,1) double {mustBePositive} = 0.5
    opts.Seed (1,1) double = 11
    opts.Counter = []
end

counter = opts.Counter;
if isempty(counter), counter = core.EvalCounter(); end

% Measurement noise is drawn from its own stream so that changing the number
% of samples a method uses cannot change the data it is given. Comparing two
% methods on two different datasets would be the easiest way to fake a result.
noiseStream = RandStream('threefry', 'Seed', opts.Seed);

% --- Map ------------------------------------------------------------------
[map, waypoints, lmTrue] = localLayout(opts.Layout);
defaults = datasets.gridWorldDefaults(opts.Layout);

% The two sentinel defaults, resolved before anything reads them. Validation
% is here rather than in the arguments block because NaN is a legal input and
% mustBePositive would reject it; an explicitly passed 0, -1 or 1.5 is still
% a caller error and still says so.
if isnan(opts.SensorRange)
    opts.SensorRange = defaults.sensorRange;
elseif ~(opts.SensorRange > 0)
    error('datasets:makeGridWorldCase:badSensorRange', ...
        'SensorRange must be positive; got %g.', opts.SensorRange);
end
if isnan(opts.NumPoses)
    opts.NumPoses = defaults.numPoses;
elseif ~(opts.NumPoses > 1 && mod(opts.NumPoses, 1) == 0)
    error('datasets:makeGridWorldCase:badNumPoses', ...
        'NumPoses must be an integer greater than one; got %g.', opts.NumPoses);
end
if ~isempty(opts.Blocks)
    if size(opts.Blocks, 2) ~= 4
        error('datasets:makeGridWorldCase:badBlocks', ...
            'Blocks must be one [x y w h] row per obstacle; got %d column(s).', ...
            size(opts.Blocks, 2));
    end
    map.blocks = opts.Blocks;
end
map.cellSize = opts.CellSize;
map = localOccupancy(map);

% --- Mission --------------------------------------------------------------
[posesTrue, headings] = localWalkPath(waypoints, opts.NumPoses);
localAssertPathIsClear(waypoints, posesTrue, map.blocks, opts.Layout);

nPose = size(posesTrue, 1);
nLm   = size(lmTrue, 1);

poseNames = "x" + string(1:nPose);
lmNames   = "l" + string(1:nLm);

% --- Variables ------------------------------------------------------------
% Domains are the map box, padded so a posterior mode that leaks outside the
% walls is represented rather than clipped. A domain is a reference and
% plotting device here, not a constraint on samples.
pad = 2;
box = [map.bounds(1)-pad, map.bounds(2)+pad; map.bounds(3)-pad, map.bounds(4)+pad];

vars = core.Variable.empty(1, 0);
for k = 1:nPose
    vars(end+1) = core.Variable(poseNames(k), 'Dim', 2, 'Type', "pose", 'Domain', box); %#ok<AGROW>
end
for m = 1:nLm
    vars(end+1) = core.Variable(lmNames(m), 'Dim', 2, 'Type', "landmark", 'Domain', box); %#ok<AGROW>
end

% --- Factors, grouped by the increment that introduces them ---------------
factors = core.Factor.empty(1, 0);
increments = struct('k', {}, 'poseName', {}, 'newVariables', {}, ...
                    'factorIndex', {}, 'observations', {});

seenLandmark = false(1, nLm);
numRangeReadings     = 0;
numAmbiguousActual   = 0;
numAmbiguousDeferred = 0;   % no reading is withheld; reported so it says so

for k = 1:nPose
    newFactorIdx = [];
    newVars = poseNames(k);

    if k == 1
        fp = core.Factor.gaussianVectorUnary(poseNames(1), posesTrue(1,:), ...
                 opts.PriorSigma, 'Name', "f(x1)", 'Counter', counter);
        factors(end+1) = fp; %#ok<AGROW>
        newFactorIdx(end+1) = numel(factors); %#ok<AGROW>
    else
        % Odometry is the noisy measured increment, not the true one.
        delta = posesTrue(k,:) - posesTrue(k-1,:) ...
                + opts.OdomSigma * randn(noiseStream, 1, 2);
        fo = core.Factor.gaussianVectorRelative(poseNames(k-1), poseNames(k), ...
                 delta, opts.OdomSigma, ...
                 'Name', sprintf("f(%s,%s)", poseNames(k-1), poseNames(k)), ...
                 'Counter', counter);
        factors(end+1) = fo; %#ok<AGROW>
        newFactorIdx(end+1) = numel(factors); %#ok<AGROW>
    end

    % --- Range readings from this pose ------------------------------------
    obs = struct('landmark', {}, 'landmarkName', {}, 'range', {}, ...
                 'trueRange', {}, 'ambiguousWith', {});

    d  = vecnorm(lmTrue - posesTrue(k,:), 2, 2);
    los = datasets.segmentClear(posesTrue(k,:), lmTrue, map.blocks);
    visible = find(d <= opts.SensorRange & los);

    for vi = visible.'
        r = d(vi) + opts.RangeSigma * randn(noiseStream);
        r = max(r, 1e-3);
        numRangeReadings = numRangeReadings + 1;

        partner = [];
        if opts.Association == "ambiguous"
            % A reading is ambiguous when another visible beacon sits at a
            % similar range: the classic association failure, and the one
            % that produces a genuinely multimodal posterior rather than a
            % wide unimodal one.
            others = visible(visible ~= vi);
            near = others(abs(d(others) - d(vi)) < 3 * opts.RangeSigma);
            if ~isempty(near), partner = near(1); end
        end

        if isempty(partner)
            fr = core.Factor.rangeFactor(poseNames(k), lmNames(vi), r, opts.RangeSigma, ...
                     'Name', sprintf("f(%s,%s)", poseNames(k), lmNames(vi)), ...
                     'Counter', counter);
            obs(end+1) = struct('landmark', vi, 'landmarkName', lmNames(vi), ...
                'range', r, 'trueRange', d(vi), 'ambiguousWith', []); %#ok<AGROW>
        else
            numAmbiguousActual = numAmbiguousActual + 1;
            fr = core.Factor.ambiguousRangeFactor(poseNames(k), ...
                     [lmNames(vi) lmNames(partner)], r, opts.RangeSigma, [0.5 0.5], ...
                     'Name', sprintf("f(%s;%s|%s)", poseNames(k), ...
                                     lmNames(vi), lmNames(partner)), ...
                     'Counter', counter);
            obs(end+1) = struct('landmark', vi, 'landmarkName', lmNames(vi), ...
                'range', r, 'trueRange', d(vi), 'ambiguousWith', partner); %#ok<AGROW>
        end

        factors(end+1) = fr; %#ok<AGROW>
        newFactorIdx(end+1) = numel(factors); %#ok<AGROW>

        if ~seenLandmark(vi)
            newVars(end+1) = lmNames(vi); %#ok<AGROW>
            seenLandmark(vi) = true;
        end
        if ~isempty(partner) && ~seenLandmark(partner)
            newVars(end+1) = lmNames(partner); %#ok<AGROW>
            seenLandmark(partner) = true;
        end
    end

    increments(end+1) = struct('k', k, 'poseName', poseNames(k), ...
        'newVariables', newVars, 'factorIndex', newFactorIdx, ...
        'observations', obs); %#ok<AGROW>
end

% A landmark nobody ever sees is an unconstrained variable that no elimination
% order can handle. Drop it from the graph rather than fail later with a
% message about Lemma 1 that points at the wrong cause.
keptLm = find(seenLandmark);
if numel(keptLm) < nLm
    dropped = lmNames(~seenLandmark);
    vars(ismember([vars.Name], dropped)) = [];
end

graph = core.FactorGraph(vars, factors, counter);

% --- Elimination order ----------------------------------------------------
[order, orderInfo] = core.eliminationOrder(graph);

% --- Explored occupancy, per increment ------------------------------------
map.explored = localExploredCells(map, posesTrue, opts.SensorRange);

% --- Case bundle ----------------------------------------------------------
caseData = struct();
caseData.name            = sprintf("gridworld_%s_%s", opts.Layout, opts.Association);
caseData.displayName     = "Grid world: blocked map, range-only mission";
caseData.variant         = opts.Association;
caseData.graph           = graph;
caseData.counter         = counter;
caseData.eliminationOrder = order;
caseData.orderInfo       = orderInfo;
caseData.targetVariable  = order(end);
caseData.pathVariables   = order(1:min(2, numel(order)-1));
caseData.numIncrements   = nPose;
caseData.increments      = increments;
caseData.engine          = "general";

caseData.map = map;
caseData.mission = struct( ...
    'waypoints', waypoints, ...
    'truePoses', posesTrue, ...
    'headings',  headings, ...
    'poseNames', poseNames, ...
    'start',     posesTrue(1,:), ...
    'goal',      posesTrue(end,:), ...
    'sensorRange', opts.SensorRange);
caseData.landmarks = struct( ...
    'truePositions', lmTrue, ...
    'names', lmNames, ...
    'observed', seenLandmark);

caseData.groundTruth = struct( ...
    'poses', posesTrue, 'poseNames', poseNames, ...
    'landmarks', lmTrue, 'landmarkNames', lmNames, ...
    'observedLandmarks', seenLandmark);

% numVariables, numObservedLandmarks and maxSeparatorDim are here because a
% sweep needs them as AXES and can only know them after the case is built:
% which beacons are in view is a fact about the geometry and the sensor
% range together, not about any option the plan sets. numLandmarks counts
% the beacons PLACED and numObservedLandmarks the ones that made it into the
% graph, and the gap between them is how much of a layout a short mission
% actually visits.
% A K past the layout's measured pose count is scalability evidence, not the
% nominal benchmark, and the case says so itself rather than leaving a reader
% to notice. Nothing about the run changes; only what it may be compared to.
if nPose > defaults.numPoses
    profile = "stress";
    profileWhy = sprintf(['%d poses against the nominal %d for the %s ' ...
        'layout: scalability evidence, not the nominal benchmark'], ...
        nPose, defaults.numPoses, opts.Layout);
else
    profile = "nominal";
    profileWhy = sprintf('%d poses, within the nominal %d for the %s layout', ...
        nPose, defaults.numPoses, opts.Layout);
end

caseData.settings = struct( ...
    'layout', opts.Layout, 'numPoses', nPose, 'numLandmarks', nLm, ...
    'numObservedLandmarks', nnz(seenLandmark), ...
    'numVariables', numel(vars), ...
    'maxSeparatorDim', orderInfo.maxSeparatorDim, ...
    'numBlocks', size(map.blocks, 1), ...
    'sensorRange', opts.SensorRange, 'rangeSigma', opts.RangeSigma, ...
    'odomSigma', opts.OdomSigma, 'priorSigma', opts.PriorSigma, ...
    'association', opts.Association, 'seed', opts.Seed, ...
    'numRangeReadings', numRangeReadings, ...
    'numAmbiguousReadings', numAmbiguousActual, ...
    'effectiveAmbiguityFraction', numAmbiguousActual / max(numRangeReadings, 1), ...
    'numAmbiguityDeferredForInitialization', numAmbiguousDeferred, ...
    'cellSize', opts.CellSize, ...
    'nominalNumPoses', defaults.numPoses, ...
    'caseProfile', profile, 'caseProfileReason', profileWhy);

caseData.latex = struct( ...
    'graph',  "$\prod_k f(x_k,x_{k+1}) \prod_{(k,m)\in\mathcal{V}} f(x_k,l_m)$", ...
    'target', sprintf("$f_{\\mathrm{new}}(%s \\mid D)$", ...
                      regexprep(order(end), '^([a-zA-Z]+)(\d+)$', '$1_{$2}')), ...
    'range',  "$f(x_k,l_m) = \mathcal{N}\!\left(\|l_m - x_k\|;\, r_{km},\, \sigma_r^2\right)$", ...
    'headline', "$f(x_k,l_m)$ leaves $l_m$ on an annulus: the posterior shape RMSE cannot see");
end

% =========================================================================
function [map, waypoints, lmTrue] = localLayout(layout)
%LOCALLAYOUT Blocks, mission waypoints and beacon positions for a layout.
%   Inputs   LAYOUT, the layout name
%   Outputs  MAP the bounds and blocks, WAYPOINTS the route, LMTRUE the beacons
%   Utility  define the three layouts in one place.
%   Beacon PLACEMENT decides the treewidth of the graph, which decides
%   whether the inference is possible at all. A beacon sitting in the middle
%   of the map is seen from opposite ends of the mission and ties those poses
%   together, and a few such beacons take the separator past ten dimensions,
%   where a finite support has an effective sample size near one and the
%   whole estimate is carried by a single point.
%
%   So the beacons line the corridors the robot actually drives, close to the
%   path and shadowed from the far side by the blocks. Each is then seen by
%   two or three CONSECUTIVE poses, the graph stays banded, and the
%   separators stay at two or three planar variables. Two beacons are left on
%   block corners, where occlusion decides visibility, because a layout in
%   which nothing is ever occluded makes the blocks decoration.
%   The sensor range and pose count that go with each layout live in
%   datasets.gridWorldDefaults, because the sweep plan and the app need them
%   too and three copies of a pair of numbers is three chances to disagree.
switch layout
    case "office"
        map = struct();
        map.bounds = [0 20 0 14];
        map.blocks = [ 3  2  4  4;      % lower-left room
                       3  9  4  3;      % upper-left store
                      11  2  5  3;      % lower-right room
                      11  8  6  4];     % upper-right hall

        % A perimeter loop: the last pose returns near the first, so the
        % final increment is a loop closure and the ambiguity either resolves
        % or collapses onto the wrong mode.
        waypoints = [ 1.5  1.5
                     18.5  1.5
                     18.5 12.5
                      1.5 12.5
                      1.5  4.0];

        lmTrue = [ 5.5  0.7        % bottom corridor
                  13.5  0.7        % bottom corridor
                  19.3  4.5        % right corridor
                  19.3 10.0        % right corridor
                  14.0 13.3        % top corridor
                   6.0 13.3        % top corridor
                   0.7  9.5        % left corridor
                   2.5  7.0];      % left corridor, shadowed by the lower-left room

    case "corridor"
        map = struct();
        map.bounds = [0 16 0 8];
        map.blocks = [ 3  0  2  5;
                       8  3  2  5;
                      12  0  2  5];
        % A serpentine, because the blocks are staggered and the route has
        % to weave between them. Its predecessor was a lap of the map --
        % straight along the top, down the right, straight back along the
        % bottom -- which reads as a sensible patrol and is not one: the
        % top run goes through the centre block and the bottom run through
        % the other two. Six stations, so the six-pose default puts a pose
        % on each, and every leg is an axis-aligned run through free space.
        waypoints = [ 1.0  6.5
                      6.5  6.5
                      6.5  1.5
                     11.0  1.5
                     11.0  6.5
                     15.0  6.5];
        lmTrue = [ 5.0  5.0
                   8.0  3.0
                  14.0  5.0
                  10.0  1.5];

    case "warehouse"
        % Six racks in two rows, a conveyor along the top and an office in
        % the top-left corner: eight obstacles against the office layout's
        % four, on a floor half again as large. The cross-aisles between the
        % racks are the point -- they are the only way between the bottom
        % aisle and the middle corridor, so the route has to weave, and a
        % beacon two aisles over is hidden by a rack rather than by range.
        map = struct();
        map.bounds = [0 24 0 16];
        map.blocks = [ 3  3  4  3;      % rack A1
                      10  3  4  3;      % rack A2
                      17  3  4  3;      % rack A3
                       3  9  4  3;      % rack B1
                      10  9  4  3;      % rack B2
                      17  9  4  3;      % rack B3
                       8 13.5 8 1.5;    % overhead conveyor
                       0 13  5  3];     % shift office

        % Eight stations: along the bottom aisle, up the first cross-aisle,
        % along the middle corridor, up the second cross-aisle, across the
        % top and back down the right-hand side. Every leg is axis-aligned
        % and inside free space, and localWalkPath truncates to the first N
        % stations, so a five-pose mission drives the first five of these
        % rather than a coarser version of all eight.
        %
        % THE RIGHT-HAND RUN IS SPLIT IN TWO, and the measurement is why. As
        % one 11.5 m leg it was longer than twice the sensor range, so no
        % beacon could be within 4 m of both of its ends and the two poses on
        % it took no range readings at all -- odometry-only poses whose error
        % is pure dead reckoning. A station in the middle makes both halves
        % about 6 m, which is the length the rest of the route already had.
        waypoints = [ 1.5  1.5
                      8.5  1.5
                      8.5  7.5
                     15.5  7.5
                     15.5 13.0
                     22.5 13.0
                     22.5  7.5
                     22.5  1.5];

        % Thirteen beacons in two groups, and the split is deliberate.
        %
        % The first seven sit near the MIDPOINT of each leg, which at a 4.0 m
        % range is the only placement that gets a beacon seen from both of
        % the stations either side of it: the legs are 5.5 to 7 m long, so a
        % midpoint beacon is about 3 m from each end and a beacon near a
        % station is 6 m from the next one. This is the placement rule the
        % office layout does NOT follow, and the sighting counts measured in
        % the class comment are the difference it makes.
        %
        % The other six are off the route, behind racks or across the floor,
        % most of them further than 4 m from any station,
        % and most are never seen at all. They are not padding. A layout
        % where every beacon placed is a beacon observed cannot exercise the
        % unobserved-landmark path -- the one that drops a variable nothing
        % constrains before elimination reaches it and fails with a message
        % about Lemma 1 -- and it hides the gap between the map a surveyor
        % laid out and the map a short mission actually uses, which is what
        % settings.numLandmarks against numObservedLandmarks reports.
        lmTrue = [ 5.0  1.0        % leg 1 midpoint, bottom aisle
                   8.6  4.6        % leg 2 midpoint, cross-aisle A1/A2
                  12.0  8.1        % leg 3 midpoint, middle corridor
                  15.4 10.4        % leg 4 midpoint, cross-aisle B2/B3
                  19.0 13.8        % leg 5 midpoint, above the conveyor
                  23.2 10.2        % leg 6 midpoint, right-hand aisle
                  23.2  4.6        % leg 7 midpoint, right-hand aisle
                   4.0  7.6        % middle corridor, west of the route
                   1.0 11.0        % far left, past the racks
                  12.5  0.6        % bottom aisle, east end
                  18.5  1.2        % bottom aisle, far east
                   2.0 15.2        % top-left, beside the shift office
                  15.4  3.4];      % cross-aisle A2/A3, off the route
end
end

% =========================================================================
function map = localOccupancy(map)
%LOCALOCCUPANCY Rasterize the blocks onto the occupancy grid.
%   Inputs   MAP, carrying bounds, blocks and cellSize
%   Outputs  MAP with its occupancy grid filled in
%   Utility  give the explored-cell view something to mask against.
xs = map.bounds(1) : map.cellSize : map.bounds(2);
ys = map.bounds(3) : map.cellSize : map.bounds(4);
map.gridX = xs(1:end-1) + map.cellSize/2;
map.gridY = ys(1:end-1) + map.cellSize/2;

[GX, GY] = ndgrid(map.gridX, map.gridY);
occ = false(size(GX));
for b = 1:size(map.blocks, 1)
    lo = map.blocks(b, 1:2);
    hi = lo + map.blocks(b, 3:4);
    occ = occ | (GX >= lo(1) & GX <= hi(1) & GY >= lo(2) & GY <= hi(2));
end
map.occupancy = occ;
map.cellCentres = [GX(:) GY(:)];
end

% =========================================================================
function explored = localExploredCells(map, poses, sensorRange)
%LOCALEXPLOREDCELLS Cumulative sensor coverage, one page per pose.
%   Inputs   MAP, POSES the true track, SENSORRANGE
%   Outputs  EXPLORED, a logical page per pose
%   Utility  show what the robot could actually see, which is what makes a
%           missing measurement legible as occlusion rather than as a gap.
%   EXPLORED(:,:,k) is true for every free cell within range and in line of
%   sight of poses 1..k. This is the "exploring the grid" view: the robot
%   reveals the map as it moves, and the blocks cast shadows it never sees.
c = map.cellCentres;
n = size(c, 1);
explored = false([size(map.occupancy) size(poses, 1)]);
seen = false(n, 1);

for k = 1:size(poses, 1)
    d = vecnorm(c - poses(k,:), 2, 2);
    cand = find(d <= sensorRange & ~map.occupancy(:));
    if ~isempty(cand)
        ok = datasets.segmentClear(poses(k,:), c(cand,:), map.blocks);
        seen(cand(ok)) = true;
    end
    explored(:,:,k) = reshape(seen, size(map.occupancy));
end
end

% =========================================================================
function [poses, headings] = localWalkPath(waypoints, n)
%LOCALWALKPATH N poses along the route, every leg inside one route segment.
%   Inputs   WAYPOINTS the route vertices, N the number of poses
%   Outputs  POSES the positions, HEADINGS the direction of travel
%   Utility  place poses so that no leg cuts a corner, which is what keeps the
%           path clear of the blocks the route was drawn around.
%   The route's vertices are STATIONS, not hints. Every pose is a vertex or
%   a subdivision of a single segment, so the straight leg between any two
%   consecutive poses never leaves the segment it was cut from.
%
%   THIS REPLACES EVEN SPACING BY ARC LENGTH, WHICH DROVE THE ROBOT THROUGH
%   WALLS. Arc length puts poses on the route but not at its corners, and
%   the leg between the two poses either side of a corner is a chord across
%   it. That chord is what the map view draws and what the odometry factor
%   models -- pose k to pose k+1, in a straight line -- so the corner being
%   cut is a corner the robot is shown, and told, to drive through. At the
%   six-pose default it cut three of the office layout's five legs and six
%   of the corridor layout's nine, every one of them into a block.
%
%   Nothing downstream noticed, which is the reason it survived: the
%   occupancy view rasterizes the blocks from the map and not from the
%   path, line of sight is computed per pose rather than along the leg, and
%   an odometry factor is a displacement with no opinion about what lies
%   between. The geometry was wrong in the one place nobody was looking.
%
%   FEWER POSES THAN VERTICES MEANS A SHORTER MISSION -- the first N
%   stations -- not a coarser one. Sampling the whole route more coarsely
%   is exactly the corner-cutting this function exists to prevent, so the
%   robot stops early instead of teleporting past a wall.
nV = size(waypoints, 1);

if n <= nV
    poses = waypoints(1:n, :);
else
    seg   = vecnorm(diff(waypoints, 1, 1), 2, 2);
    extra = localApportion(seg, n - nV);

    poses = zeros(n, 2);
    p = 0;
    for j = 1:nV-1
        m = extra(j);
        t = (0:m).' / (m + 1);          % vertex j, then m interior points
        poses(p + (1:m+1), :) = waypoints(j,:) ...
            + t .* (waypoints(j+1,:) - waypoints(j,:));
        p = p + m + 1;
    end
    poses(end,:) = waypoints(end,:);
end

% Heading is the direction actually travelled to the next pose, so it agrees
% with the leg the odometry factor models. The final pose keeps the heading
% it arrived on: there is no next leg to point along.
d = diff(poses, 1, 1);
headings = [atan2(d(:,2), d(:,1)); 0];
headings(end) = headings(max(1, end-1));
end

% =========================================================================
function counts = localApportion(weights, total)
%LOCALAPPORTION Hand TOTAL extra poses to the segments, longest first.
%   Inputs   WEIGHTS the segment lengths, TOTAL the poses to distribute
%   Outputs  COUNTS, one per segment, summing to TOTAL
%   Utility  distribute by largest remainder, since rounding each share
%           independently does not sum to the total.
%   Largest remainder. Rounding each segment's share independently does not
%   sum to TOTAL, and a pose count that quietly differs from the one asked
%   for is a pose count nobody can reason about against the engine's
%   thirteen-variable ceiling.
counts = zeros(numel(weights), 1);
if total <= 0 || sum(weights) <= 0
    return
end

share  = total * weights(:) / sum(weights);
counts = floor(share);
short  = total - sum(counts);
if short > 0
    [~, ord] = sort(share - counts, 'descend');
    counts(ord(1:short)) = counts(ord(1:short)) + 1;
end
end

% =========================================================================
function localAssertPathIsClear(waypoints, poses, blocks, layout)
%LOCALASSERTPATHISCLEAR No route segment and no pose-to-pose leg is in a block.
%   Inputs   WAYPOINTS, POSES, BLOCKS, LAYOUT for the message
%   Outputs  none; errors when either contract is broken
%   Utility  catch a layout whose route drives through a wall.
%   Two separate contracts, and it is worth keeping them separate because
%   they fail for different reasons and are fixed in different places.
%
%   The LAYOUT contract is that consecutive route vertices see each other.
%   No choice of pose count can rescue a route that is itself inside a wall,
%   which is what the corridor layout was: a straight run down the middle of
%   the map, through the centre block, and back along the bottom through two
%   more. That one is fixed by rerouting.
%
%   The SAMPLING contract is that, given a clear route, every leg stays
%   inside one segment. That one is fixed by localWalkPath.
%
%   Both are checked at build time, on every call, rather than only in a
%   test. Layouts are edited by hand and by eye, and this failure is
%   invisible in every view the app draws.
localAssertLegsClear(waypoints, blocks, sprintf('%s layout route', layout));
localAssertLegsClear(poses,     blocks, sprintf('%s mission path', layout));
end

% =========================================================================
function localAssertLegsClear(pts, blocks, what)
%LOCALASSERTLEGSCLEAR Every consecutive pair of PTS has clear line of sight.
%   Inputs   PTS the ordered points, BLOCKS, WHAT the name for the message
%   Outputs  none; errors on the first blocked leg
%   Utility  the shared check behind both of the contracts above.
for i = 1:size(pts, 1) - 1
    if ~datasets.segmentClear(pts(i,:), pts(i+1,:), blocks)
        error('datasets:makeGridWorldCase:pathThroughBlock', ...
            ['%s leg %d, (%.2f, %.2f) -> (%.2f, %.2f), passes through a ' ...
             'block. The robot cannot drive through a wall, and the ' ...
             'odometry factor for that leg would be a measurement of a ' ...
             'motion that never happened.'], ...
            what, i, pts(i,1), pts(i,2), pts(i+1,1), pts(i+1,2));
    end
end
end
