function sweep = parameterSweep(plan, config, whichMethods)
%PARAMETERSWEEP Run every cell of a plan and collect one tidy row per method.
%
%   Inputs
%     PLAN          a struct array from methods.twoPoseSweepPlan or any
%                   caller supplying the same four fields:
%                     name       string, the cell's label
%                     build      function handle returning a caseData struct
%                     overrides  config fields to set for this cell
%                     axes       coordinates, copied verbatim onto its rows
%     CONFIG        the base method config
%     WHICHMETHODS  which methods to run             default all three
%
%   Outputs
%     SWEEP.rows       struct array, one per (cell, method)
%     SWEEP.table      the same as a MATLAB table, for sorting and export
%     SWEEP.plan       the plan as run
%     SWEEP.methods    the methods, in the order they were run
%     SWEEP.cancelled  true if Stop was pressed
%     SWEEP.numCells / numCompleted   cells planned, cells that finished
%     SWEEP.elapsedSeconds, SWEEP.ranAt, SWEEP.seed
%
%   Utility
%     Run methods.runComparison once per cell and return the metrics in long
%     form, one row per measurement with its coordinates attached.
%
%   LONG FORM IS THE POINT. A sweep could return a cube indexed by budget,
%   scenario and method, and every plot would then begin by working out which
%   dimension it wanted. One row per measurement, with its coordinates
%   attached, means a curve is a filter and a group -- and it means adding a
%   third axis later changes the plan and nothing else.
%
%   Each cell is scored against ITS OWN reference. runComparison rebuilds the
%   quadrature ground truth per case, so a cell with a different mixture
%   separation is compared against the exact posterior for that separation
%   rather than against a reference computed once and reused. This is the
%   expensive choice and the only correct one: the reference is a property of
%   the problem, not of the sweep.
%
%   A CANCELLED SWEEP RETURNS WHAT IT HAD, and the unit of "what it had" is
%   the (cell, method) pair rather than the cell. Every method that finished
%   keeps its row, including the ones in the cell Stop landed inside. Nothing
%   that did not finish contributes a row at all, rather than a row of NaN.
%   The distinction matters to a plot: a missing point is a curve that stops,
%   and a NaN point is a curve with a hole in it, and only one of those is
%   what actually happened.
%
%   SWEEP.numCompleted counts whole CELLS, so a sweep stopped inside cell one
%   can return rows while reporting zero completed. That is not a
%   contradiction: the cell is unfinished and the methods inside it that got
%   there are not.
%
%   See also methods.twoPoseSweepPlan, methods.runComparison, viz.plotSweepCurves.

arguments
    plan (1,:) struct
    config (1,1) struct = methods.commonMethodConfig()
    whichMethods (1,:) string = ["Slices", "NF-iSAM", "Smoothed Slices"]
end

localValidatePlan(plan);

p = utils.progressOf(config);
nCell = numel(plan);

% Accumulated as a cell and concatenated once. Growing a struct array by
% rows(end+1) needs the template to declare every field up front, including
% the axis coordinates -- which the plan owns and this function deliberately
% does not know.
rowCells = {};
cancelled = false;
numCompleted = 0;
tAll = tic;

for i = 1:nCell
    cell_ = plan(i);
    pc = p.sub((i-1)/nCell, i/nCell);

    try
        pc.report(0, sprintf("cell %d of %d: %s", i, nCell, cell_.name));

        cfg = localApply(config, cell_.overrides);
        cfg.progress = pc;
        caseData = cell_.build();

        [res, summary] = methods.runComparison(caseData, cfg, whichMethods);
    catch err
        % A cancellation raised between cells, or by the reference build
        % before runComparison's own handler is in scope. Either way the
        % sweep is over and what ran is kept.
        if ~utils.ProgressReporter.isCancellation(err), rethrow(err), end
        cancelled = true;
        break
    end

    % Per METHOD, not per cell. runComparison catches a cancellation inside a
    % method and returns normally with a stub for it, so a half-run cell
    % arrives as a mix: the methods that finished carry real metrics and the
    % one that was interrupted carries NaNs.
    %
    % Keep the first, drop the second. Both halves of that matter. Keeping the
    % finished methods is the whole point of Stop preserving work -- Slices
    % having finished is not made less true by NF-iSAM being stopped after it.
    % Dropping the stub is what this function's own contract promises: a cell
    % that did not run contributes no row rather than a row of NaN, because on
    % a plot a missing point is a curve that stops and a NaN point is a curve
    % with a hole in it. An interrupted method is exactly a method that did
    % not run, and it was being written into the rows as a hole.
    for j = 1:numel(res)
        if res(j).status == "cancelled", continue, end
        rowCells{end+1} = localRow(i, cell_, res(j), summary); %#ok<AGROW>
    end

    if summary.cancelled
        cancelled = true;
        break
    end
    numCompleted = numCompleted + 1;
end

% Every row carries the same fields -- the axes come from one plan and the
% metric list is fixed -- so a plain concatenation is enough and
% harmonizeResults would only hide a plan that disagreed with itself.
if isempty(rowCells)
    rows = struct([]);
else
    rows = [rowCells{:}];
end

sweep = struct();
sweep.rows           = rows;
sweep.table          = localTable(rows);
sweep.plan           = plan;
sweep.methods        = whichMethods;
sweep.cancelled      = cancelled;
sweep.numCells       = nCell;
sweep.numCompleted   = numCompleted;
sweep.elapsedSeconds = toc(tAll);
sweep.ranAt          = datetime('now');
sweep.seed           = config.seed;
sweep.config         = utils.serializableConfig(config);

if cancelled
    % Held where it stopped, for the reason runComparison gives at length: a
    % full bar over a cancelled run reads as a run that finished.
    p.announce(p.Fraction, sprintf("cancelled: %d of %d cell(s) completed", ...
        numCompleted, nCell));
else
    p.announce(1, sprintf("done: %d cell(s), %d row(s) in %.0f s", ...
        numCompleted, numel(rows), sweep.elapsedSeconds));
end
end

% =========================================================================
function localValidatePlan(plan)
%LOCALVALIDATEPLAN Refuse a plan missing a field the sweep will need.
%   Inputs   PLAN, the struct array
%   Outputs  none; throws
%   Utility  a missing field would fail halfway through an hour-long sweep,
%           so it is caught before the first cell runs.
%
%   A plan with a missing field would otherwise raise on the cell that first
%   needed it, which on a long sweep is a failure the user waits for.
need = ["name", "build", "overrides", "axes"];
missing = need(~isfield(plan, need));
if ~isempty(missing)
    error('methods:parameterSweep:badPlan', ...
        'Plan is missing the field(s): %s.', strjoin(missing, ', '));
end
for i = 1:numel(plan)
    if ~isa(plan(i).build, 'function_handle')
        error('methods:parameterSweep:badBuild', ...
            'Cell %d ("%s") has a %s where its build handle should be.', ...
            i, plan(i).name, class(plan(i).build));
    end
end
end

% =========================================================================
function config = localApply(config, overrides)
%LOCALAPPLY A copy of the config with one cell's overrides set.
%   Inputs   CONFIG the base, OVERRIDES the cell's fields
%   Outputs  CONFIG, the copy
%   Utility  every cell starts from the same base, so the axes are the only
%           thing that differs between them.
%
%   Unknown fields are rejected rather than added. A typo in a plan would
%   otherwise create a config field nothing reads, and the cell would run at
%   the default budget while its label claimed otherwise -- a wrong number
%   with a plausible axis coordinate, which is the worst kind.
fn = fieldnames(overrides);
for i = 1:numel(fn)
    if ~isfield(config, fn{i})
        error('methods:parameterSweep:unknownOverride', ...
            'Override "%s" is not a field of the method config.', fn{i});
    end
    config.(fn{i}) = overrides.(fn{i});
end
end

% =========================================================================
function row = localRow(i, cell_, result, summary)
%LOCALROW One (cell, method) measurement, with its coordinates attached.
%   Inputs   I the cell index, CELL_ the cell, RESULT the method result,
%           SUMMARY the comparison summary
%   Outputs  ROW, one struct
%   Utility  long form is the point: a curve is then a filter and a group.
row = struct();
row.cellIndex     = i;
row.cellName      = string(cell_.name);
row.method        = string(result.methodName);
row.status        = string(result.status);
row.referenceKind = string(summary.referenceKind);

% The axes are copied verbatim so that a plan can add a coordinate without
% this function knowing about it.
ax = cell_.axes;
fn = fieldnames(ax);
for k = 1:numel(fn)
    row.(fn{k}) = ax.(fn{k});
end

% Every metric is fetched defensively. A cancelled method carries NaNs, a
% normalized method reports no mass error by design, and the grid-world
% reference kind produces no relative-L1 at all -- so an absent field is a
% normal outcome here rather than a fault, and NaN is what a plot should skip.
m = result.metrics;
for f = ["relL1Error", "relL2Error", "massError", "mmd", "rmse", "ess", ...
         "runtimeTotal", "runtimeForward", "runtimeBackward", ...
         ... % THE COST AXIS THE RESEARCH QUESTION IS ACTUALLY ABOUT. The
         ... % research instruction sheet's decisive plot is posterior error
         ... % against MEASURED FACTOR EVALUATIONS, not against wall time,
         ... % because wall time confounds the algorithm with the machine and
         ... % with MATLAB's vectorisation. Every sweep before this one
         ... % recorded runtime and not this, so the one number the open
         ... % question turns on was being thrown away at the point of
         ... % measurement. See research.costQualityFrontier.
         "factorEvaluations", "factorEvalsForward", "factorEvalsBackward", ...
         ... % Shape, not just location. These exist only on the chain-exact
         ... % reference, so they are NaN on every other case -- which is the
         ... % normal outcome localGet is built for. Without them a Four Doors
         ... % sweep could only report RMSE, and RMSE is precisely the metric
         ... % that improves when a method collapses the posterior to one mode.
         "collapsedModes", "maxModeWeightL1", "meanMarginalL1", ...
         "maxMapDoorError", ...
         ... % Where the error actually is, on the map cases. rmse pools
         ... % poses and landmarks into one number, and on a range-only
         ... % problem those two are not the same quantity: a bimodal
         ... % landmark posterior can carry 20 m of landmarkRMSE while every
         ... % pose is within a metre. Pooling them reports one failure as
         ... % two, or hides a good trajectory behind a reflected beacon.
         "poseRMSE", "poseMaxError", "landmarkRMSE"]
    row.(f) = localGet(m, f);
end

% Engine health, one level down. These are the diagnostics that call the
% grid world's cliff BEFORE the RMSE does -- support effective sample size
% collapses and the nearest-support lookup distance climbs -- so a sweep
% over problem size that could not plot them would be watching the symptom
% and not the cause. NF-iSAM reports NaN for the two sampling ones by
% construction: it has no finite support and no lookup, and NaN is the
% honest entry rather than a zero that would plot as perfect health.
if isstruct(m) && isfield(m, 'health')
    for f = ["minEssSupport", "maxSeparatorDim", "lookupMean", "lookupMax"]
        row.(f) = localGet(m.health, f);
    end
else
    for f = ["minEssSupport", "maxSeparatorDim", "lookupMean", "lookupMax"]
        row.(f) = NaN;
    end
end

% The problem's size, read off the case that was actually built rather than
% off the plan. A grid-world plan can ask for seven poses; how many
% VARIABLES that turns into depends on which beacons the mission passes
% within sensor range of, which is geometry and is settled at build time.
% This is the x-axis of the cliff plot, so it has to be the built number.
row.numVariables = localSettingOf(result, 'numVariables');
row.numObservedLandmarks = localSettingOf(result, 'numObservedLandmarks');
end

% =========================================================================
function v = localSettingOf(result, field)
%LOCALSETTINGOF One config field as the METHOD actually ran it.
%   Inputs   RESULT a method result, FIELD the config field
%   Outputs  V the value, or NaN
%   Utility  read the config carried back rather than the one handed in, since
%           a method may legitimately have changed it.
%
%   The two-pose and Four Doors cases do not report a variable count, and
%   absent is the normal outcome here rather than a fault -- the same
%   contract localGet has for metrics.
v = NaN;
if ~isfield(result, 'case') || ~isstruct(result.case), return, end
if ~isfield(result.case, 'settings') || ~isstruct(result.case.settings), return, end
s = result.case.settings;
if isfield(s, field) && isscalar(s.(field)) && isnumeric(s.(field))
    v = double(s.(field));
end
end

% =========================================================================
function v = localGet(m, f)
%LOCALGET A metric's value, or NaN when the method did not report it.
%   Inputs   M the metrics struct, F the field
%   Outputs  V the value, or NaN
%   Utility  keep the table rectangular across methods that report different
%           metrics.
if isstruct(m) && isfield(m, f) && isscalar(m.(f)) && isnumeric(m.(f))
    v = double(m.(f));
else
    v = NaN;
end
end

% =========================================================================
function t = localTable(rows)
%LOCALTABLE The rows as a MATLAB table, for sorting and export.
%   Inputs   ROWS, the struct array
%   Outputs  T, the table; empty with the right variables when there are none
%   Utility  a cancelled sweep with no rows must still return a table a plot
%           can ask for column names from.
%
%   struct2table errors on a 0x0 struct array, and a sweep cancelled before
%   its first cell finished is exactly that. Returning an empty table with no
%   variables keeps every caller's `height(t) == 0` test working.
if isempty(rows)
    t = table();
    return
end
t = struct2table(rows);
end
