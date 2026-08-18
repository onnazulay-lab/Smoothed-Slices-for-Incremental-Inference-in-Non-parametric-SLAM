function plan = twoPoseSweepPlan(opts)
%TWOPOSESWEEPPLAN The grid of two-pose experiments the sweep runs.
%
%   Inputs
%     Budgets        posterior sample counts    default [50 100 200 400]
%     Separations    mixture offsets d          default [1.2 2.2 3.5]
%     WeakOdometry   [delta sigma], ambiguous          default [2 3.0]
%     TightOdometry  [delta sigma], resolving          default [2 0.6]
%     Seed           measurement seed, one for the whole grid   default 3
%
%   Outputs
%     PLAN  one element per cell: how to build its case, what to change about
%           the budgets, and where the cell sits on the axes a curve is later
%           plotted against
%
%   Utility
%     Ask where a method's ACCURACY breaks down, on the one case with an exact
%     reference to break down against.
%
%   A single run of the two-pose range benchmark answers "which method won
%   here". It cannot answer the question the benchmark exists for, which is
%   WHERE each method stops working. One number per method is a point; the
%   trend is the result, and a trend needs an axis.
%
%   THE GRID IS TWO AXES, NOT ONE.
%
%     budget      N in {50, 100, 200, 400}, the number of posterior samples a
%                 method may draw. Sampling error falls as N grows, so a
%                 method whose error does not fall with N is not paying for
%                 sampling error -- it is biased, and the budget axis is what
%                 separates the two. N sets numSamples AND numBackwardSamples
%                 for the reason documented at the override below: the Slices
%                 family reads the first, NF-iSAM reads only the second, and
%                 an axis that moves for two methods out of three is worse
%                 than no axis at all.
%
%     scenario    six problems, chosen so that separation and odometry can be
%                 read apart rather than confounded:
%
%                   unimodal, tight odometry     the control: one mode, and
%                                                nothing to get wrong
%                   unimodal, weak odometry      the same posterior shape
%                                                with far less information,
%                                                which separates "hard
%                                                because ambiguous" from
%                                                "hard because diffuse"
%                   d = 1.2, weak odometry       two modes that overlap
%                   d = 2.2, weak odometry       two modes, clearly apart
%                   d = 3.5, weak odometry       two modes, far apart
%                   d = 2.2, tight odometry      the same ambiguity as the
%                                                third multimodal cell, with
%                                                odometry strong enough to
%                                                resolve it
%
%   Cells 3, 4 and 5 vary ONLY the separation, so a curve across them is a
%   curve in separation. Cells 4 and 6 vary ONLY the odometry, so the pair is
%   a controlled comparison of whether the ambiguity was resolvable at all.
%   Reading the separation axis without holding odometry fixed would confound
%   the two, and the whole point of a sweep is to be able to say which knob
%   moved the result.
%
%   WHY WEAK ODOMETRY IS THE DEFAULT ON THE MULTIMODAL CELLS. It is not a
%   difficulty setting, it is what makes them multimodal at all:
%   makeTwoPoseRangeCase documents that a tight odometry resolves the range
%   ambiguity on its own and the posterior comes out unimodal. Sweeping
%   separation under tight odometry would sweep a knob that changes nothing
%   visible, and the plotted curve would be flat for a reason having nothing
%   to do with the methods.
%
%   ONE SEED ACROSS THE WHOLE GRID is deliberate. The cells are meant to
%   differ in the two axes and in nothing else; drawing fresh noise per cell
%   would add a third, invisible axis and put ragged Monte Carlo scatter into
%   every curve. It also means the curves show one realisation rather than an
%   expectation, which is a real limitation and is why the sweep reports the
%   seed alongside the numbers.
%
%   See also methods.parameterSweep, datasets.makeTwoPoseRangeCase.

arguments
    opts.Budgets (1,:) double {mustBeInteger, mustBePositive} = [50 100 200 400]
    opts.Separations (1,:) double {mustBePositive} = [1.2 2.2 3.5]
    opts.WeakOdometry (1,2) double = [2 3.0]
    opts.TightOdometry (1,2) double = [2 0.6]
    opts.Seed (1,1) double {mustBeInteger, mustBeNonnegative} = 3
end

% --- The scenario axis ----------------------------------------------------
% Built first and independently of the budgets, so that the grid below is a
% plain product and the scenario definitions stay readable as a list.
scen = struct('label', {}, 'variant', {}, 'separation', {}, ...
              'odometry', {}, 'family', {}, 'odometryName', {});

scen(end+1) = localScenario("unimodal, tight odometry", "gaussian", ...
    0, opts.TightOdometry, "unimodal", "tight");
scen(end+1) = localScenario("unimodal, weak odometry", "gaussian", ...
    0, opts.WeakOdometry, "unimodal", "weak");

for d = opts.Separations
    scen(end+1) = localScenario(sprintf("d = %.1f, weak odometry", d), ...
        "multimodal", d, opts.WeakOdometry, "multimodal", "weak"); %#ok<AGROW>
end

% The controlled partner for the middle separation. Placed last rather than
% next to its partner so the separation cells stay contiguous: a plot that
% walks the scenario axis in order should not step out of the separation
% sweep and back into it.
dMid = opts.Separations(ceil(numel(opts.Separations) / 2));
scen(end+1) = localScenario(sprintf("d = %.1f, tight odometry", dMid), ...
    "multimodal", dMid, opts.TightOdometry, "multimodal", "tight");

% --- The product ----------------------------------------------------------
plan = struct('name', {}, 'build', {}, 'overrides', {}, 'axes', {});

for i = 1:numel(scen)
    s = scen(i);
    for N = opts.Budgets
        % Captured by value into the closure. A handle that read S and N from
        % the enclosing scope would see whatever the loop left there, and
        % every cell would build the last scenario -- a bug that produces a
        % complete, plausible, entirely wrong sweep.
        build = localBuilder(s.variant, s.separation, s.odometry);

        cell_ = struct();
        cell_.name = sprintf("%s, N = %d", s.label, N);
        cell_.build = build;
        % THE BUDGET MUST REACH ALL THREE METHODS, and numSamples alone does
        % not. runNFISAMMethod draws its posterior from numBackwardSamples and
        % never reads numSamples at all, so the first full sweep produced an
        % NF-iSAM curve that was identical to four decimal places at every
        % budget: not a flat curve but the same run plotted four times, at
        % twenty-nine seconds each. The axis said "budget" and NF-iSAM had no
        % budget on it.
        %
        % Both fields together, so the axis means the same thing for every
        % method: how many posterior samples it is allowed to draw. Training
        % samples (nfisamTrainSamples) are deliberately NOT swept -- they buy
        % the flow its capacity, not the estimate its resolution, and folding
        % them in would make a rising curve unattributable to either.
        cell_.overrides = struct('numSamples', N, 'numBackwardSamples', N, ...
                                 'seed', opts.Seed);
        cell_.axes = struct( ...
            'budget',       N, ...
            'separation',   s.separation, ...
            'odomSigma',    s.odometry(2), ...
            'family',       s.family, ...
            'odometryName', s.odometryName, ...
            'scenario',     s.label);
        plan(end+1) = cell_; %#ok<AGROW>
    end
end
end

% =========================================================================
function s = localScenario(label, variant, separation, odometry, family, odomName)
%LOCALSCENARIO One cell of the grid, as the sweep's own scenario struct.
%   Inputs   LABEL, VARIANT, SEPARATION, ODOMETRY, FAMILY, ODOMNAME
%   Outputs  S, one scenario
%   Utility  build every cell through one function, so two cells cannot
%           silently differ in a field neither axis names.
s = struct('label', label, 'variant', variant, 'separation', separation, ...
           'odometry', odometry, 'family', family, 'odometryName', odomName);
end

% =========================================================================
function h = localBuilder(variant, separation, odometry)
%LOCALBUILDER The case-building closure for one cell.
%   Inputs   VARIANT, SEPARATION, ODOMETRY
%   Outputs  H, a handle the sweep calls to build the case
%   Utility  this case draws NO measurements, so the seed reaches the config
%           alone -- which is why the seed is not an argument here.
%
%   Separated into its own function purely so the capture is by argument. It
%   is the one place in this file where getting it wrong would be silent.
%
%   No seed reaches the builder because this case has nothing to seed: the
%   two-pose factors are analytic and carry no drawn measurement, so the
%   seed belongs to the methods and travels in the config overrides. The
%   grid-world and Plaza cases do draw noise and will need it here.
if variant == "gaussian"
    h = @() datasets.makeTwoPoseRangeCase( ...
        'Variant', "gaussian", 'Odometry', odometry);
else
    h = @() datasets.makeTwoPoseRangeCase( ...
        'Variant', "multimodal", 'Odometry', odometry, ...
        'MixtureOffset', separation);
end
end
