function plan = fourDoorsSweepPlan(opts)
%FOURDOORSSWEEPPLAN The grid of Four Doors experiments the sweep runs.
%
%   Inputs
%     Budgets        posterior sample counts     default [50 100 200 400]
%     Spacings       even door spacings to sweep default [2.5 4 6]
%     WeakOdometry   sigma that leaves modes live         default 0.55
%     TightOdometry  sigma that resolves them             default 0.18
%     Seed           measurement seed, one for the whole grid    default 3
%
%   Outputs
%     PLAN  one element per cell of the budget-by-scenario grid, in the shape
%           methods.parameterSweep consumes
%
%   Utility
%     Ask whether the posterior's SHAPE survives, which is the failure this
%     case has and the two-pose sweep's accuracy axis cannot see.
%
%   WHY THIS CASE NEEDS A SWEEP OF ITS OWN, and a different one. The two-pose
%   sweep asks where a method's ACCURACY breaks down. On a chain of identical
%   doors the interesting failure is not inaccuracy, it is CONFIDENCE: a
%   method that discards one of two live modes gets a lower RMSE for doing
%   it, because the surviving mode is closer to the truth than the average of
%   both. So the metric that matters here is mode weight against the exact
%   chain posterior, and the axes are the two things that decide how hard the
%   ambiguity is to keep alive.
%
%   THE GRID IS TWO AXES.
%
%     budget      N in {50, 100, 200, 400}, as in the two-pose sweep and for
%                 the same reason: a method whose shape error does not fall
%                 with N is not paying for sampling error, it is biased.
%                 Both numSamples and numBackwardSamples move together,
%                 because NF-iSAM reads only the second and an axis that
%                 moves two methods out of three is worse than no axis.
%
%     scenario    six corridors, chosen so that ambiguity and resolvability
%                 can be read apart:
%
%                   spacing 4, weak odometry   the shipped case: four doors,
%                                              modes stay live for a while
%                   spacing 2.5, weak          doors close together, so the
%                                              modes overlap and the mass is
%                                              hard to attribute at all
%                   spacing 6, weak            doors far apart, modes clean
%                                              and separate: the easy shape
%                   spacing 4, tight odometry  same corridor, odometry sharp
%                                              enough to resolve early. The
%                                              controlled partner of cell 1
%                   irregular spacing, weak    doors at [2 6 8 14]: the ONLY
%                                              asymmetric corridor, see below
%                   six doors, weak            a longer corridor, eight poses
%                                              and more sightings: does the
%                                              shape survive more steps
%
%   Cells 1, 2 and 3 vary ONLY the spacing, so a curve across them is a curve
%   in ambiguity. Cells 1 and 4 vary ONLY the odometry, so the pair says
%   whether the ambiguity was resolvable at all. Reading either without
%   holding the other fixed would confound them.
%
%   WHY AN IRREGULAR CORRIDOR IS IN THE GRID. Every evenly spaced corridor is
%   symmetric, and on a symmetric posterior a method that collapses to the
%   MIDDLE of two modes lands near the truth by construction -- the error
%   cancels, and both RMSE and the mode-weight L1 flatter it. Uneven doors
%   break that symmetry, so a collapsed estimate has nowhere safe to land.
%   Without this cell the grid could report a method as sound when it is
%   averaging modes.
%
%   ONE SEED ACROSS THE WHOLE GRID, for the reason twoPoseSweepPlan gives:
%   the cells must differ in the two axes and nothing else. Unlike the
%   two-pose case this one DOES draw measurements, so the seed reaches the
%   builder as well as the config -- see localBuilder.
%
%   See also methods.parameterSweep, methods.twoPoseSweepPlan,
%   datasets.makeFourDoorsCase, methods.scoreAgainstChainReference.

arguments
    opts.Budgets (1,:) double {mustBeInteger, mustBePositive} = [50 100 200 400]
    opts.Spacings (1,:) double {mustBePositive} = [2.5 4 6]
    opts.WeakOdometry (1,1) double {mustBePositive} = 0.55
    opts.TightOdometry (1,1) double {mustBePositive} = 0.18
    opts.Seed (1,1) double {mustBeInteger, mustBeNonnegative} = 3
end

% --- The scenario axis ----------------------------------------------------
scen = struct('label', {}, 'doors', {}, 'numPoses', {}, 'step', {}, ...
              'odomSigma', {}, 'seeDoorAt', {}, 'spacing', {}, ...
              'family', {}, 'odometryName', {});

for s = opts.Spacings
    % Four doors, evenly spaced, starting at 2. The corridor length follows
    % the spacing so the robot still walks past all of them: a fixed pose
    % count over a spacing-6 corridor would stop short of the last door and
    % the cell would sweep corridor length as well as spacing.
    doors = 2 + s * (0:3);
    step  = s * 0.6;
    scen(end+1) = localScenario( ...
        sprintf("spacing %.1f, weak odometry", s), doors, 6, step, ...
        opts.WeakOdometry, [1 3 6], s, "even", "weak"); %#ok<AGROW>
end

sMid = opts.Spacings(ceil(numel(opts.Spacings) / 2));
scen(end+1) = localScenario( ...
    sprintf("spacing %.1f, tight odometry", sMid), 2 + sMid * (0:3), 6, ...
    sMid * 0.6, opts.TightOdometry, [1 3 6], sMid, "even", "tight");

scen(end+1) = localScenario("irregular doors, weak odometry", ...
    [2 6 8 14], 6, 2.4, opts.WeakOdometry, [1 3 6], NaN, "irregular", "weak");

scen(end+1) = localScenario("six doors, eight poses, weak odometry", ...
    2 + 3 * (0:5), 8, 2.2, opts.WeakOdometry, [1 3 5 8], 3, "long", "weak");

% --- The product ----------------------------------------------------------
plan = struct('name', {}, 'build', {}, 'overrides', {}, 'axes', {});

for i = 1:numel(scen)
    sc = scen(i);
    for N = opts.Budgets
        % Captured by value, for the reason twoPoseSweepPlan documents: a
        % closure reading the loop variables would build the last scenario in
        % every cell and produce a complete, plausible, wrong sweep.
        build = localBuilder(sc.doors, sc.numPoses, sc.step, ...
                             sc.odomSigma, sc.seeDoorAt, opts.Seed);

        cell_ = struct();
        cell_.name = sprintf("%s, N = %d", sc.label, N);
        cell_.build = build;
        cell_.overrides = struct('numSamples', N, 'numBackwardSamples', N, ...
                                 'seed', opts.Seed);
        cell_.axes = struct( ...
            'budget',       N, ...
            'spacing',      sc.spacing, ...
            'odomSigma',    sc.odomSigma, ...
            'numDoors',     numel(sc.doors), ...
            'numPoses',     sc.numPoses, ...
            'family',       sc.family, ...
            'odometryName', sc.odometryName, ...
            'scenario',     sc.label);
        plan(end+1) = cell_; %#ok<AGROW>
    end
end
end

% =========================================================================
%LOCALSCENARIO One cell of the grid, as the sweep's own scenario struct.
%   Inputs   LABEL, the corridor's doors, poses, step and odometry sigma, and
%           the axis coordinates the curve is later plotted against
%   Outputs  S, one scenario
%   Utility  build every cell through one function, so two cells cannot
%           silently differ in a field neither axis names.
function s = localScenario(label, doors, numPoses, step, odomSigma, ...
                           seeDoorAt, spacing, family, odomName)
s = struct('label', label, 'doors', doors, 'numPoses', numPoses, ...
           'step', step, 'odomSigma', odomSigma, 'seeDoorAt', seeDoorAt, ...
           'spacing', spacing, 'family', family, 'odometryName', odomName);
end

% =========================================================================
function h = localBuilder(doors, numPoses, step, odomSigma, seeDoorAt, seed)
%LOCALBUILDER The case-building closure for one cell.
%   Inputs   the corridor's parameters, and SEED
%   Outputs  H, a handle the sweep calls to build the case
%   Utility  this case DRAWS measurements, so the seed has to reach the
%           builder and not only the config.
%
%   THE SEED REACHES THE CASE HERE, unlike the two-pose plan. That case is
%   analytic and carries no drawn measurement, so its seed belongs to the
%   methods alone. This one draws odometry and door sightings, so a cell that
%   left the case seed to default would hold the METHOD seed fixed across the
%   grid while the DATA changed with it -- the opposite of what the grid is
%   for.
%
%   Sightings are clamped to the pose count so a scenario with fewer poses
%   than the default schedule cannot ask for a sighting at a pose that does
%   not exist.
seeDoorAt = seeDoorAt(seeDoorAt <= numPoses);
h = @() datasets.makeFourDoorsCase( ...
    'Doors', doors, 'NumPoses', numPoses, 'Step', step, ...
    'OdomSigma', odomSigma, 'SeeDoorAt', seeDoorAt, 'Seed', seed);
end
