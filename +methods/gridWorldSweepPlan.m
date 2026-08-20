function plan = gridWorldSweepPlan(opts)
%GRIDWORLDSWEEPPLAN The grid of blocked-map experiments the sweep runs.
%
%   Inputs
%     Budget    posterior sample count for every cell         default 200
%     Support   separator support size for every cell         default 250
%     Seeds     the extra seeds for the "seed" family     default [3 7 13]
%     BaseSeed  the seed the other families use               default 11
%
%   Outputs
%     PLAN  eighteen cells in four families, in the shape
%           methods.parameterSweep consumes
%
%   Utility
%     Sweep the PROBLEM SIZE at a fixed budget, so the claim about where this
%     engine turns can be re-run rather than quoted from a comment.
%
%   THIS SWEEP HAS A DIFFERENT AXIS FROM THE OTHER TWO, and that is the whole
%   reason it exists. The two-pose sweep varies the BUDGET and asks where
%   accuracy breaks down. The Four Doors sweep varies the AMBIGUITY and asks
%   whether the posterior's shape survives. Here the budget is held fixed and
%   the PROBLEM SIZE is swept, because the finding this case exists to
%   support is a claim about size: the engine is sound to about thirteen
%   variables and falls off a cliff at fourteen. That claim was measured once,
%   by hand, on one layout, and written into a comment. A comment is not a
%   measurement anyone can re-run.
%
%   AND RE-RUN, IT BROKE THE CLAIM. The eighteen cells put the warehouse at
%   9-13 m of pose error with TEN variables where the office is at 0.2-1.2 m
%   with thirteen, so the cliff is the office's and not the engine's. The
%   plan is unchanged by that -- it was built to test the claim, and it did --
%   but read its output as "where does THIS layout turn", never as one number
%   for the engine. datasets.makeGridWorldCase has the tables and the three
%   candidate explanations that were tested and eliminated.
%
%   THE FOUR FAMILIES.
%
%     "size"        office, four to seven poses, at the shipped seed. The
%                   cliff itself: eleven, thirteen, fourteen, fifteen
%                   variables. Four cells.
%
%     "seed"        office at five and six poses -- the two sides of the
%                   cliff -- over three further seeds. Six cells. A cliff
%                   that only one draw sees is a draw, not a cliff, and the
%                   scatter is the evidence for which it is.
%
%     "layout"      corridor and warehouse, five and seven poses. Four
%                   cells, and the sharpest ones in the grid: the warehouse
%                   reaches fourteen variables with a separator of FOUR
%                   dimensions where the office needs six. If it fails there
%                   too then the cliff tracks the number of eliminations, not
%                   the width of any of them -- which is what
%                   datasets.makeGridWorldCase claims and what nothing has
%                   independently checked.
%
%     "sensing"     office at five poses with the range at 4.5, 5.5 and 6.5 m
%                   and with ambiguous association. Four cells. Range is a
%                   confounded axis on purpose: a longer range gives more
%                   readings AND more variables, so a rise in error across it
%                   cannot be read as "more data hurt". The cell is here so
%                   that a reader who is going to draw that conclusion draws
%                   it from data with the confound in front of them, and the
%                   variables column is on every row for exactly that.
%
%   Eighteen cells, three methods, one budget.
%
%   WHY ONE BUDGET AND NOT FOUR. The other two sweeps put four budgets on the
%   x-axis and get a convergence curve. Doing that here would multiply
%   eighteen structural cells by four and produce a seventy-two cell grid
%   that runs for over an hour -- and would answer a question this case
%   cannot answer anyway, because the grid world has no exact posterior to
%   converge TO. Its quality metrics are distances to the SURVEYED TRUTH, and
%   an estimator can be perfectly converged and still sit at 12 m of pose
%   error once the lookup has broken down. Budget belongs on the two-pose
%   sweep, where a reference exists; size belongs here.
%
%   THE BUDGET DEFAULT IS THE ONE THE CLIFF WAS MEASURED AT: numSamples 200,
%   separator support 250, as recorded in datasets.makeGridWorldCase. A sweep
%   meant to reproduce a table has to run at the table's settings or it is
%   measuring something else and calling it a check.
%
%   See also methods.parameterSweep, methods.twoPoseSweepPlan,
%   methods.fourDoorsSweepPlan, datasets.makeGridWorldCase,
%   viz.plotGridWorldCliff.

arguments
    opts.Budget (1,1) double {mustBeInteger, mustBePositive} = 200
    opts.Support (1,1) double {mustBeInteger, mustBePositive} = 250
    opts.Seeds (1,:) double {mustBeInteger, mustBeNonnegative} = [3 7 13]
    opts.BaseSeed (1,1) double {mustBeInteger, mustBeNonnegative} = 11
end

cells = struct('label', {}, 'layout', {}, 'numPoses', {}, 'sensorRange', {}, ...
               'association', {}, 'seed', {}, 'family', {});

% --- size: the cliff, on the layout it was measured on -------------------
for n = 4:7
    cells(end+1) = localCell(sprintf("office, %d poses", n), ...
        "office", n, NaN, "known", opts.BaseSeed, "size"); %#ok<AGROW>
end

% --- seed: is the cliff a property of the case or of one draw ------------
for n = [5 6]
    for s = opts.Seeds
        cells(end+1) = localCell(sprintf("office, %d poses, seed %d", n, s), ...
            "office", n, NaN, "known", s, "seed"); %#ok<AGROW>
    end
end

% --- layout: same variable counts, different geometry --------------------
for n = [5 7]
    cells(end+1) = localCell(sprintf("corridor, %d poses", n), ...
        "corridor", n, NaN, "known", opts.BaseSeed, "layout"); %#ok<AGROW>
    cells(end+1) = localCell(sprintf("warehouse, %d poses", n), ...
        "warehouse", n, NaN, "known", opts.BaseSeed, "layout"); %#ok<AGROW>
end

% --- sensing: how much the robot can see, and whether it knows what ------
for r = [4.5 5.5 6.5]
    cells(end+1) = localCell(sprintf("office, range %.1f m", r), ...
        "office", 5, r, "known", opts.BaseSeed, "sensing"); %#ok<AGROW>
end
cells(end+1) = localCell("office, ambiguous association", ...
    "office", 5, NaN, "ambiguous", opts.BaseSeed, "sensing");

% --- The plan -------------------------------------------------------------
plan = struct('name', {}, 'build', {}, 'overrides', {}, 'axes', {});

for i = 1:numel(cells)
    c = cells(i);

    cell_ = struct();
    cell_.name = c.label;
    cell_.build = localBuilder(c);
    % The seed goes into the overrides as well as into the case: the case
    % seed draws the measurements and the config seed drives the sampling,
    % and a cell that moved one without the other would be varying the data
    % and the estimator's luck at the same time.
    cell_.overrides = struct('numSamples', opts.Budget, ...
                             'numBackwardSamples', opts.Budget, ...
                             'separatorSupportSize', opts.Support, ...
                             'seed', c.seed);
    % numVariables is NOT an axis here. It cannot be: which beacons a
    % mission sees is decided by the geometry at build time, so the plan
    % does not know it. parameterSweep reads it off the built case and puts
    % it on the row, which is why it is a row field and not a plan field.
    cell_.axes = struct( ...
        'budget',      opts.Budget, ...
        'numPoses',    c.numPoses, ...
        'sensorRange', localRange(c), ...
        'layout',      c.layout, ...
        'association', c.association, ...
        'caseSeed',    c.seed, ...
        'family',      c.family, ...
        'scenario',    c.label);
    plan(end+1) = cell_; %#ok<AGROW>
end
end

% =========================================================================
function c = localCell(label, layout, numPoses, sensorRange, assoc, seed, family)
%LOCALCELL One cell of the grid, before it is turned into a scenario.
%   Inputs   LABEL, LAYOUT, NUMPOSES, SENSORRANGE, ASSOC, SEED, FAMILY
%   Outputs  C, the cell
%   Utility  build every cell through one function, so the four families
%           cannot drift apart in a field none of them varies.
c = struct('label', label, 'layout', layout, 'numPoses', numPoses, ...
           'sensorRange', sensorRange, 'association', assoc, ...
           'seed', seed, 'family', family);
end

% =========================================================================
function r = localRange(c)
%LOCALRANGE A cell's sensor range, or the case builder's own default.
%   Inputs   C, the cell
%   Outputs  R, the range
%   Utility  only the "sensing" family sets it, and the others must inherit
%           rather than restate it.
%
%   NaN in a cell means "the layout's own", which is what the case resolves
%   it to -- but an axis column of NaN cannot be plotted or filtered on, and
%   a reader comparing a corridor cell with an office one needs the number
%   that was used rather than a marker saying it was left alone.
if ~isnan(c.sensorRange)
    r = c.sensorRange;
    return
end
r = datasets.gridWorldDefaults(c.layout).sensorRange;
end

% =========================================================================
function h = localBuilder(c)
%LOCALBUILDER The case-building closure for one cell.
%   Inputs   C, the cell
%   Outputs  H, a handle the sweep calls to build the case
%   Utility  the grid world draws measurements, so the seed reaches the
%           builder and not only the config.
%
%   The trap twoPoseSweepPlan documents: a handle that read the loop
%   variables would build the last cell's case in every cell of the grid and
%   produce a complete, plausible, wrong sweep. Capturing c by value in this
%   function's scope is what stops that.
args = {'Layout', c.layout, 'NumPoses', c.numPoses, ...
        'Association', c.association, 'Seed', c.seed};
if ~isnan(c.sensorRange)
    args = [args, {'SensorRange', c.sensorRange}];
end
h = @() datasets.makeGridWorldCase(args{:});
end
