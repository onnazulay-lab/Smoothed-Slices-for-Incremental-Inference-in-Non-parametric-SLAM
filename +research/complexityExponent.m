function out = complexityExponent(sweep, opts)
%COMPLEXITYEXPONENT How fast does each method's work grow with its budget?
%
%   Inputs
%     SWEEP     a methods.parameterSweep result
%     Work      column to fit             default "factorEvaluations"
%     Axis      independent variable      default "budget"
%     Scenario  restrict to one scenario label         default "" (all)
%
%   Outputs
%     OUT.methods   one struct per method: alpha, intercept, r2, points,
%                   usable
%     OUT.costUnit  what "work" was measured in
%     OUT.ranking   methods ordered by alpha, cheapest growth first
%     OUT.note      the depth caveat below
%
%   Utility
%     Fit work ~ C * N^alpha per method across the budget axis of a sweep, by
%     least squares on log(work) against log(N), and return alpha with the fit
%     quality beside it.
%
%   WHAT ALPHA IS FOR. The research instruction sheet frames the open question
%   as a contest between two cost models:
%
%       nested work      Cost_nested(H) ~ N^H |S|
%       surface work     Cost_RCS(H)    ~ sum_r |X_r| |N_r| |S|
%
%   The first is superlinear in N and gets worse with depth; the second is
%   linear in the support sizes. So the exponent on N is the sharpest single
%   number that separates them, and it is measurable without believing either
%   model: fit the line and read the slope. An alpha near 1 says work grows
%   with the budget; an alpha near 2 or above says something is compounding.
%
%   THIS IS A SLOPE, NOT A PROOF. Four budgets is four points, the sweep runs
%   one seed, and a log-log fit over less than a decade of N will happily
%   report a confident slope for a curve that is not a power law at all. That
%   is why r2 and the residual come back with alpha and why OUT.usable is
%   false when there are fewer than three finite points: the honest use of
%   this number is to compare methods measured the same way in the same
%   sweep, not to quote an asymptotic complexity.
%
%   DEPTH IS NOT SWEPT HERE. The sheet's experiment E1 sweeps the recursion
%   depth H as well, which this repository's cases cannot vary independently:
%   depth is set by the elimination order and the graph, so changing it
%   changes the problem rather than the budget. The exponent on N is the part
%   of E1 that the existing cases can answer honestly, and OUT.note says so
%   rather than leaving the omission to be discovered.
%
%   See also research.costQualityFrontier, methods.parameterSweep.

arguments
    sweep (1,1) struct
    opts.Work (1,1) string = "factorEvaluations"
    opts.Axis (1,1) string = "budget"
    opts.Scenario (1,1) string = ""
end

if ~isfield(sweep, 'table')
    error('research:complexityExponent:notASweep', ...
        'Expected a methods.parameterSweep result with a table field.');
end
T = sweep.table;

if strlength(opts.Scenario) > 0
    T = T(T.scenario == opts.Scenario, :);
end
T = T(T.status == "ok", :);

for need = [opts.Work, opts.Axis]
    if ~ismember(need, T.Properties.VariableNames)
        error('research:complexityExponent:missingColumn', ...
            'The sweep has no column "%s".', need);
    end
end

fits = struct('method', {}, 'alpha', {}, 'intercept', {}, 'r2', {}, ...
              'numPoints', {}, 'usable', {}, 'reason', {});

for m = unique(T.method).'
    rows = T(T.method == m, :);
    x = rows.(opts.Axis);
    y = rows.(opts.Work);

    % A power law is only defined on positive data, and dropping the
    % non-positive points silently would turn NF-iSAM's zero evaluations into
    % a fit over whatever remained.
    keep = isfinite(x) & isfinite(y) & x > 0 & y > 0;
    if nnz(keep) < 3
        fits(end+1) = struct('method', m, 'alpha', NaN, 'intercept', NaN, ...
            'r2', NaN, 'numPoints', nnz(keep), 'usable', false, ...
            'reason', "fewer than three positive (budget, work) points"); %#ok<AGROW>
        continue
    end

    lx = log(x(keep));
    ly = log(y(keep));
    if range(lx) < eps
        fits(end+1) = struct('method', m, 'alpha', NaN, 'intercept', NaN, ...
            'r2', NaN, 'numPoints', nnz(keep), 'usable', false, ...
            'reason', "the budget axis does not vary"); %#ok<AGROW>
        continue
    end

    p = polyfit(lx, ly, 1);
    resid = ly - polyval(p, lx);
    ssTot = sum((ly - mean(ly)).^2);
    r2 = 1;
    if ssTot > 0
        r2 = 1 - sum(resid.^2) / ssTot;
    end

    fits(end+1) = struct('method', m, 'alpha', p(1), 'intercept', p(2), ...
        'r2', r2, 'numPoints', nnz(keep), 'usable', true, ...
        'reason', ""); %#ok<AGROW>
end

usable = fits([fits.usable]);
[~, ord] = sort([usable.alpha]);
ranking = string({usable(ord).method});

out = struct( ...
    'methods',  fits, ...
    'costUnit', opts.Work, ...
    'axis',     opts.Axis, ...
    'scenario', opts.Scenario, ...
    'ranking',  ranking, ...
    'note',     "alpha is the slope of log(work) against log(budget) in " + ...
                "THIS sweep, not an asymptotic complexity; recursion depth " + ...
                "is fixed by the graph and is not swept here");
end
