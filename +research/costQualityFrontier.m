function out = costQualityFrontier(sweep, opts)
%COSTQUALITYFRONTIER Does Smoothed Slices buy quality with fewer evaluations?
%
%   Inputs
%     SWEEP            a methods.parameterSweep result
%     Metric           quality column, lower is better    default auto, below
%     Baseline         the method being improved upon          default "Slices"
%     Challenger       the method under test         default "Smoothed Slices"
%     ExcludeZeroCost  drop methods reporting no evaluations     default true
%     Scenario         restrict to one scenario label         default "" (all)
%
%   Outputs
%     OUT.question    the open question, restated with this sweep's scope
%     OUT.metric      which quality column was used
%     OUT.curves      one struct per method: budgets, evaluations, error
%     OUT.comparison  per baseline budget: target error, cheapest challenger
%                     point reaching it, evaluation ratio, and whether it
%                     exists
%     OUT.verdict     "reduces" | "no reduction" | "quality not matched" |
%                     "insufficient data", plus the evidence behind it
%     OUT.excluded    methods dropped from the cost axis, with reasons
%
%   Utility
%     Answer the open research question of the research-tool instruction sheet
%     section 2: WHEN does Smoothed Slices reduce computations, and by how
%     much, relative to the original Slices nested sampling -- at matched
%     posterior quality.
%
%   THE COST AXIS IS FACTOR EVALUATIONS, NOT WALL TIME, and that is the whole
%   point. The instruction sheet calls the quality-versus-evaluations plot the
%   most important one it asks for, and it is right to: wall time confounds
%   the algorithm with the machine, with MATLAB's vectorisation, and with how
%   much of each method happens inside a loop rather than a matrix product.
%   Smoothed Slices replaces a nested sample TREE with a surface MATRIX, so it
%   is exactly the method that a wall-time comparison would flatter for
%   reasons having nothing to do with the idea being right. Evaluations are
%   what the two estimators actually spend.
%
%   WHAT "MATCHED QUALITY" MEANS HERE. Each method contributes a curve of
%   (evaluations, error) points, one per budget. To compare at matched
%   quality, the baseline's error at each of its budgets is taken as a target,
%   and the challenger is asked for the cheapest of ITS points that reaches
%   that error. The reported saving is the ratio of evaluations. Interpolation
%   is deliberately NOT used to invent a challenger point between budgets: the
%   sweep measured what it measured, and a frontier drawn through interpolated
%   points would report a saving at a budget nobody ran.
%
%   NF-iSAM IS EXCLUDED FROM THE COST AXIS BY DEFAULT, and this is not
%   tidiness. Algorithm N1 SIMULATES from its factors rather than evaluating
%   them, so its factor-evaluation count is zero -- runGeneralCore already
%   warns about exactly this. Putting a zero-cost point on a cost-quality plot
%   would show NF-iSAM winning infinitely, which is a units error, not a
%   result. It stays in OUT.excluded with the reason attached so that its
%   absence is visible rather than silent.
%
%   THE VERDICT CAN SAY "NO". The instruction sheet's section 11 pairs every
%   claim with its failure signal, and a tool that can only confirm is not
%   measuring. "quality not matched" is returned when the challenger never
%   reaches the baseline's error at any budget -- which is the sheet's
%   "surface approximation smooths away modes" failure, and is a different
%   answer from "it costs more".
%
%   METRIC SELECTION, when not given, prefers the sharpest available measure
%   of posterior SHAPE over any measure of location, because a method that
%   collapses a multimodal posterior improves every location metric by doing
%   so. Order: mmd, relL1Error, meanMarginalL1, maxModeWeightL1, rmse. The
%   chosen column is reported in OUT.metric so a reader never has to guess.
%
%   See also methods.parameterSweep, viz.plotCostQuality,
%   research.complexityExponent.

arguments
    sweep (1,1) struct
    opts.Metric (1,1) string = ""
    opts.Baseline (1,1) string = "Slices"
    opts.Challenger (1,1) string = "Smoothed Slices"
    opts.ExcludeZeroCost (1,1) logical = true
    opts.Scenario (1,1) string = ""
end

if ~isfield(sweep, 'table')
    error('research:costQualityFrontier:notASweep', ...
        'Expected a methods.parameterSweep result with a table field.');
end
T = sweep.table;

if height(T) == 0
    error('research:costQualityFrontier:emptySweep', ...
        'The sweep produced no rows; there is nothing to compare.');
end

if strlength(opts.Scenario) > 0
    if ~ismember('scenario', T.Properties.VariableNames)
        error('research:costQualityFrontier:noScenarioColumn', ...
            'This sweep has no scenario column to restrict on.');
    end
    T = T(T.scenario == opts.Scenario, :);
end

T = T(T.status == "ok", :);

metric = opts.Metric;
if strlength(metric) == 0
    metric = localPickMetric(T);
end
if ~ismember(metric, T.Properties.VariableNames)
    error('research:costQualityFrontier:noSuchMetric', ...
        'The sweep has no column "%s".', metric);
end
if ~ismember('factorEvaluations', T.Properties.VariableNames)
    error('research:costQualityFrontier:noCostColumn', ...
        ['This sweep recorded no factorEvaluations column. It was run ' ...
         'before the cost axis existed; re-run it.']);
end

% --- Per-method curves ----------------------------------------------------
curves = struct('method', {}, 'budgets', {}, 'evaluations', {}, ...
                'error', {}, 'runtime', {});
excluded = struct('method', {}, 'reason', {});

for m = unique(T.method).'
    rows = T(T.method == m, :);
    ev = rows.factorEvaluations;
    er = rows.(metric);

    if opts.ExcludeZeroCost && all(~isfinite(ev) | ev <= 0)
        excluded(end+1) = struct('method', m, ...
            'reason', "reports no factor evaluations; Algorithm N1 " + ...
                      "simulates from its factors rather than evaluating " + ...
                      "them, so a cost axis in evaluations does not " + ...
                      "measure its work"); %#ok<AGROW>
        continue
    end

    % Sorted by cost so a curve is a curve. Budgets travel alongside because
    % "which budget bought this point" is the first question a reader asks.
    bud = localBudgets(rows);
    [ev, ord] = sort(ev);
    curves(end+1) = struct('method', m, 'budgets', bud(ord), ...
        'evaluations', ev, 'error', er(ord), ...
        'runtime', localColumn(rows, 'runtimeTotal', ord)); %#ok<AGROW>
end

% --- The matched-quality comparison ---------------------------------------
comparison = struct('targetError', {}, 'baselineBudget', {}, ...
                    'baselineEvaluations', {}, 'challengerBudget', {}, ...
                    'challengerEvaluations', {}, 'ratio', {}, 'reached', {});

base = localCurve(curves, opts.Baseline);
chal = localCurve(curves, opts.Challenger);

verdict = "insufficient data";

if isempty(base) || isempty(chal)
    evidence = sprintf(['need both "%s" and "%s" in the sweep; ' ...
        'found %s'], opts.Baseline, opts.Challenger, ...
        localOrNone(string({curves.method})));
elseif localSameCost(base, chal)
    % THE MECHANISM UNDER TEST NEVER FIRED, and without this guard the
    % function would report a confident verdict about it anyway.
    %
    % innerEstimator -- "nested" for Slices, "rcs" for Smoothed Slices -- is
    % consulted ONLY on the Lemma 1 structural route, which elimination takes
    % when the variable being eliminated has neither a unary factor nor an
    % already-eliminated neighbour. On a case where every variable is
    % directly sampleable, both methods run the identical computation and
    % charge the identical evaluations. Measured across this repository's
    % cases: Four Doors, the grid world and Plaza2 all produce byte-identical
    % counts; only the two-pose range benchmark differs, because it is the
    % one case built to force the structural route.
    %
    % With identical costs, the matched-quality ratio degenerates into "which
    % method needed a bigger budget", which is a statement about sampling
    % noise wearing the costume of a complexity result. Refusing here is the
    % difference between a tool that measures and one that confirms.
    verdict = "mechanism not exercised";
    evidence = sprintf(['%s and %s charge identical factor evaluations at ' ...
        'every budget in this sweep, so the surface never replaced any ' ...
        'nested sampling. The case does not take the Lemma 1 structural ' ...
        'route, and no cost comparison on it can answer the question. ' ...
        'Use a case that forces that route.'], ...
        opts.Challenger, opts.Baseline);
else
    for i = 1:numel(base.error)
        target = base.error(i);
        % The cheapest challenger point that is at least as good. "At least
        % as good" rather than "within a tolerance": a tolerance here would
        % be a thumb on the scale, and the sheet's claim is a matched-quality
        % claim.
        ok = find(isfinite(chal.error) & chal.error <= target);
        if isempty(ok)
            comparison(end+1) = struct('targetError', target, ...
                'baselineBudget', base.budgets(i), ...
                'baselineEvaluations', base.evaluations(i), ...
                'challengerBudget', NaN, 'challengerEvaluations', NaN, ...
                'ratio', NaN, 'reached', false); %#ok<AGROW>
            continue
        end
        [cheapest, k] = min(chal.evaluations(ok));
        comparison(end+1) = struct('targetError', target, ...
            'baselineBudget', base.budgets(i), ...
            'baselineEvaluations', base.evaluations(i), ...
            'challengerBudget', chal.budgets(ok(k)), ...
            'challengerEvaluations', cheapest, ...
            'ratio', cheapest / base.evaluations(i), ...
            'reached', true); %#ok<AGROW>
    end

    reached = [comparison.reached];
    ratios = [comparison.ratio];
    ratios = ratios(reached);

    dom = localDominance(base, chal);

    if ~any(reached)
        verdict = "quality not matched";
        evidence = sprintf(['%s never reaches %s''s error at any budget ' ...
            'in this sweep. That is the instruction sheet''s "surface ' ...
            'approximation smooths away modes" failure signal, not a ' ...
            'statement about cost.'], opts.Challenger, opts.Baseline);
    elseif dom.dominates
        % THE STRONGEST FORM THE ANSWER CAN TAKE, and worth separating from
        % the ratio summary. Budget for budget, the challenger is both
        % cheaper AND better -- no interpolation, no matching rule, no
        % median over a spread of ratios that a reader has to trust. When
        % this holds, quoting a median would understate a clean result and
        % invite an argument about the matching rule instead.
        verdict = "reduces";
        evidence = sprintf(['budget for budget %s is both cheaper and more ' ...
            'accurate than %s at every one of the %d matched budgets: ' ...
            'evaluations %.0f%% to %.0f%% of baseline, error %.0f%% to ' ...
            '%.0f%%. This is dominance, not a matched-quality trade.'], ...
            opts.Challenger, opts.Baseline, dom.n, ...
            100*min(dom.costRatio), 100*max(dom.costRatio), ...
            100*min(dom.errorRatio), 100*max(dom.errorRatio));
    elseif median(ratios) < 1
        verdict = "reduces";
        evidence = sprintf(['at matched quality %s uses %.2fx the factor ' ...
            'evaluations of %s (median over %d matched target(s), range ' ...
            '%.2f to %.2f)'], opts.Challenger, median(ratios), ...
            opts.Baseline, numel(ratios), min(ratios), max(ratios));
    else
        verdict = "no reduction";
        evidence = sprintf(['at matched quality %s uses %.2fx the factor ' ...
            'evaluations of %s (median over %d matched target(s)), so the ' ...
            'surface overhead is not paid for in this sweep'], ...
            opts.Challenger, median(ratios), opts.Baseline, numel(ratios));
    end
end

out = struct( ...
    'question',   "When does Smoothed Slices reduce computations, and by " + ...
                  "how much, relative to Slices nested sampling?", ...
    'metric',     metric, ...
    'metricNote', "lower is better; chosen for posterior SHAPE over " + ...
                  "location where available", ...
    'costUnit',   "factor evaluations", ...
    'baseline',   opts.Baseline, ...
    'challenger', opts.Challenger, ...
    'scenario',   opts.Scenario, ...
    'curves',     curves, ...
    'comparison', comparison, ...
    'verdict',    verdict, ...
    'evidence',   string(evidence), ...
    'excluded',   excluded, ...
    'numRows',    height(T));
end

% =========================================================================
function m = localPickMetric(T)
%LOCALPICKMETRIC Shape before location, but only among columns that separate.
%   Inputs   T, the sweep's row table
%   Outputs  M, the chosen quality column
%   Utility  pick the sharpest available measure of posterior SHAPE that
%           actually varies across this sweep.
%
%   A COLUMN THAT CANNOT DISCRIMINATE IS NOT A METRIC, however principled it
%   is in the abstract. Measured on the two-pose sweep, five of eight MMD
%   values came back as exactly 0 and the non-zero ones were not monotone in
%   the budget: the unbiased estimator goes slightly negative when two sample
%   sets match well and is clamped at zero. Preferring MMD there produced a
%   confident verdict built on comparing zeros with zeros -- the challenger
%   "reached" the baseline's error because both were 0.
%
%   So a candidate must actually vary before it is chosen: at least three
%   distinct finite values, and NO exact zeros at all. The zero rule is the
%   strict one on purpose. These are sampled divergence estimates between two
%   finite sample sets; an exact zero is not a distance that happened to
%   vanish, it is the clamp on an unbiased estimator that went negative. One
%   such entry is enough to make "the challenger reached the target" true for
%   a reason that has nothing to do with the challenger. When MMD is
%   informative it is still preferred; when it has collapsed onto the clamp
%   the selection falls through to relL1Error, which on the same sweep
%   decreases monotonically with the budget.
for cand = ["mmd", "relL1Error", "meanMarginalL1", "maxModeWeightL1", "rmse"]
    if ~ismember(cand, T.Properties.VariableNames), continue, end
    v = T.(cand);
    v = v(isfinite(v));
    if numel(unique(v)) < 3, continue, end
    if any(v == 0), continue, end
    m = cand;
    return
end
error('research:costQualityFrontier:noQualityMetric', ...
    ['The sweep carries no quality column that varies enough to compare ' ...
     'on: every candidate is absent, constant, or mostly zero.']);
end

% =========================================================================
function b = localBudgets(rows)
%LOCALBUDGETS The budget axis, or NaNs if this plan did not define one.
%   Inputs   ROWS, the sweep's row table
%   Outputs  B, one budget per row
%   Utility  let a sweep over something other than the budget still be read.
if ismember('budget', rows.Properties.VariableNames)
    b = rows.budget;
else
    b = nan(height(rows), 1);
end
end

% =========================================================================
function v = localColumn(rows, name, ord)
%LOCALCOLUMN One column of the sweep table in a given row order, or NaNs.
%   Inputs   ROWS the table, NAME the column, ORD the row order to apply
%   Outputs  V, the column reordered, or NaNs when it is absent
%   Utility  read a column that a plan may not have produced.
v = nan(height(rows), 1);
if ismember(name, rows.Properties.VariableNames)
    v = rows.(name);
end
v = v(ord);
end

% =========================================================================
function c = localCurve(curves, name)
%LOCALCURVE One method's curve by name, or empty when it is not there.
%   Inputs   CURVES the array, NAME the method
%   Outputs  C, the curve or []
%   Utility  let a missing baseline or challenger become "insufficient data"
%           rather than an index error.
c = [];
for i = 1:numel(curves)
    if curves(i).method == name
        c = curves(i);
        return
    end
end
end

% =========================================================================
function d = localDominance(base, chal)
%LOCALDOMINANCE Is the challenger cheaper AND better at every shared budget?
%   Inputs   BASE, CHAL, the two curves
%   Outputs  D, whether it dominates and on how many shared budgets
%   Utility  separate dominance from "cheaper and better somewhere".
%
%   Compared BUDGET BY BUDGET rather than across the whole curve, because
%   "cheaper and better somewhere" is not dominance and the distinction is
%   the whole value of the claim. Budgets present in only one curve are
%   skipped rather than matched to their nearest neighbour: a comparison
%   between different budgets is exactly the matched-quality question, which
%   the ratio summary already answers.
d = struct('dominates', false, 'n', 0, 'costRatio', [], 'errorRatio', []);
if isempty(base.budgets) || any(~isfinite(base.budgets)), return, end

shared = intersect(base.budgets, chal.budgets);
if isempty(shared), return, end

cr = zeros(1, numel(shared));
er = zeros(1, numel(shared));
for i = 1:numel(shared)
    ib = find(base.budgets == shared(i), 1);
    ic = find(chal.budgets == shared(i), 1);
    if isempty(ib) || isempty(ic), return, end
    if ~isfinite(base.error(ib)) || ~isfinite(chal.error(ic)), return, end
    if base.evaluations(ib) <= 0, return, end
    cr(i) = chal.evaluations(ic) / base.evaluations(ib);
    er(i) = chal.error(ic) / max(base.error(ib), realmin);
end

d.n = numel(shared);
d.costRatio = cr;
d.errorRatio = er;
d.dominates = all(cr < 1) && all(er < 1);
end

% =========================================================================
function tf = localSameCost(a, b)
%LOCALSAMECOST True if two curves were charged the same work throughout.
%   Inputs   A, B, the two curves
%   Outputs  TF, logical
%   Utility  detect the case where both methods ran the same computation, so
%           a zero saving is reported as that rather than as a loss.
%
%   Exact equality, not a tolerance. These are integer counters incremented
%   by the same factor objects; when the two methods run the same
%   computation the counts agree exactly, and when they do not they differ by
%   thousands. A tolerance here would only create a band in which the
%   function guesses.
tf = numel(a.evaluations) == numel(b.evaluations) && ...
     ~isempty(a.evaluations) && ...
     isequal(sort(a.evaluations(:)), sort(b.evaluations(:)));
end

% =========================================================================
function s = localOrNone(names)
%LOCALORNONE A name list as one string, or "none".
%   Inputs   NAMES, a string array
%   Outputs  S, the joined list or "none"
%   Utility  a blank field next to a label reads as a rendering failure.
if isempty(names)
    s = "none";
else
    s = strjoin(names, ", ");
end
end
