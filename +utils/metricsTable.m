function tbl = metricsTable(results)
%METRICSTABLE Flatten an array of method results into a comparison table.
%
%   Inputs
%     RESULTS  an array of method result structs
%
%   Outputs
%     TBL      one row per method, every column plain text or numeric
%
%   Utility
%     Produce the comparison table. Specification section 4 forbids LaTeX
%     inside uitable cells, so the equations defining these quantities are
%     shown in the surrounding EquationPanel instead.

arguments
    results (1,:) struct
end

n = numel(results);
Method        = strings(n, 1);
Status        = strings(n, 1);
RelL1Error    = nan(n, 1);
RelL2Error    = nan(n, 1);
MMD           = nan(n, 1);
RMSE          = nan(n, 1);
ESS           = nan(n, 1);
RuntimeSec    = nan(n, 1);
OuterSamples  = nan(n, 1);
InnerSamples  = nan(n, 1);
SeparatorPts  = nan(n, 1);
FactorEvals   = nan(n, 1);

for i = 1:n
    r = results(i);
    Method(i) = string(r.methodName);
    if isfield(r, 'status'), Status(i) = string(r.status); else, Status(i) = "ok"; end

    RelL1Error(i)   = localGet(r.metrics, 'relL1Error');
    RelL2Error(i)   = localGet(r.metrics, 'relL2Error');
    MMD(i)          = localGet(r.metrics, 'mmd');
    RMSE(i)         = localGet(r.metrics, 'rmse');
    ESS(i)          = localGet(r.metrics, 'ess');
    RuntimeSec(i)   = localGet(r.metrics, 'runtimeTotal');

    if isfield(r.metrics, 'cardinality')
        c = r.metrics.cardinality;
        OuterSamples(i) = localGet(c, 'outer');
        InnerSamples(i) = localGet(c, 'inner');
        SeparatorPts(i) = localGet(c, 'separator');
    end
    FactorEvals(i) = localGet(r.metrics, 'factorEvaluations');
end

tbl = table(Method, Status, RelL1Error, RelL2Error, MMD, RMSE, ESS, ...
    RuntimeSec, OuterSamples, InnerSamples, SeparatorPts, FactorEvals);
end

function v = localGet(s, f)
%LOCALGET A field's value, or NaN when it is absent.
%   Inputs   S the struct, F the field name
%   Outputs  V the value, or NaN
%   Utility  let a method that reports fewer metrics still produce a row,
%           rather than failing the whole table.
if isstruct(s) && isfield(s, f) && isscalar(s.(f)) && isnumeric(s.(f))
    v = double(s.(f));
else
    v = NaN;
end
end
