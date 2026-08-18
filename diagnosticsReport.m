function out = diagnosticsReport(results)
%DIAGNOSTICSREPORT The four tables behind the Diagnostics tab.
%
%   Inputs
%     RESULTS  the method results
%
%   Outputs
%     OUT.runtime, OUT.accuracy, OUT.replay   tables, ready for a uitable
%     OUT.warnings                            string array, method-prefixed
%     OUT.notes                               string array shown under the
%                                             tables
%
%   Utility
%     Assemble runtime and memory, accuracy and effective sample size, the
%     incremental-replay report, and the engine warnings, from what the
%     methods already recorded.
%
%   THE HARD PART IS THAT ESS MEANS THREE DIFFERENT THINGS HERE. The
%   three-node engine reports the effective sample size of the outer slice
%   weights; the general engine reports it for the separator support, which is
%   the quantity that collapses as separator dimension grows; NF-iSAM reports
%   it for the product of child separator densities, and has no support to
%   report one for at all. Putting those in one column labelled "ESS" would
%   invite a comparison between three unlike numbers, so the column comes with
%   a second one naming which quantity it is. Where a method reports none, the
%   answer is a dash and the words "not reported", never a zero.
%
%   Memory is two columns for the same reason. RESULTBYTES is the serialized
%   size of what a method handed back: deterministic, comparable, and a real
%   consequence of the representation each method chose. PROCESSMB is a
%   reading of the whole MATLAB process at the instant that method returned --
%   see utils.processMemoryBytes for why it is not a peak and not the method's.
%
%   See also methods.budgetComparison, utils.metricsTable.

arguments
    results (1,:) struct
end

n = numel(results);
Method   = strings(n, 1);
Status   = strings(n, 1);

% --- Runtime and memory ---------------------------------------------------
TotalSec    = nan(n, 1);
ForwardSec  = nan(n, 1);
BackwardSec = nan(n, 1);
ResultMB    = nan(n, 1);
ProcessMB   = nan(n, 1);

% --- Accuracy and ESS -----------------------------------------------------
RelL1     = nan(n, 1);
MMD       = nan(n, 1);
RMSE      = nan(n, 1);
MinESS    = nan(n, 1);
ESSMeans  = strings(n, 1);
FactorEvals = nan(n, 1);

% --- Replay ---------------------------------------------------------------
Mode        = strings(n, 1);
Increments  = nan(n, 1);
ReusePct    = nan(n, 1);
ReuseUnit   = strings(n, 1);
EarlyStops  = nan(n, 1);
MinMMDAtStop = nan(n, 1);

warnings = string.empty(0, 1);
notes    = string.empty(0, 1);

for i = 1:n
    r = results(i);
    Method(i) = string(r.methodName);
    Status(i) = localStatus(r);
    m = r.metrics;

    TotalSec(i)    = localGet(m, 'runtimeTotal');
    ForwardSec(i)  = localGet(m, 'runtimeForward');
    BackwardSec(i) = localGet(m, 'runtimeBackward');
    ResultMB(i)    = localResultBytes(r) / 1e6;
    ProcessMB(i)   = localGet(m, 'processMemoryAfter') / 1e6;

    RelL1(i)       = localGet(m, 'relL1Error');
    MMD(i)         = localGet(m, 'mmd');
    RMSE(i)        = localGet(m, 'rmse');
    FactorEvals(i) = localGet(m, 'factorEvaluations');
    [MinESS(i), ESSMeans(i)] = localESS(m);

    [Mode(i), Increments(i), ReusePct(i), ReuseUnit(i), ...
     EarlyStops(i), MinMMDAtStop(i), note] = localReplay(m);
    if strlength(note) > 0
        notes(end+1, 1) = Method(i) + ": " + note; %#ok<AGROW>
    end

    % A CANCELLED METHOD'S LOG IS NOT AN ENGINE WARNING. cancelledResult puts
    % its reason in the same logs field the engine uses -- "cancelled before
    % this method started" -- and this box is read as the engine's own health
    % complaints, under a heading that says so and a fallback line that says
    % "no engine warnings were raised". Filing a Stop there blames the engine
    % for the user pressing a button, and buries the real warnings from the
    % methods that did run underneath two that mean nothing. The status column
    % of all three tables already says the method was stopped.
    %
    % Only "cancelled" is filtered, not everything non-ok: a method that
    % genuinely failed may have logged why, and that IS the engine talking.
    if Status(i) ~= "cancelled" && isfield(r, 'logs') && ~isempty(r.logs)
        for w = string(r.logs(:)).'
            if strlength(w) == 0, continue, end
            warnings(end+1, 1) = Method(i) + " -- " + w; %#ok<AGROW>
        end
    end
end

out = struct();
out.runtime  = table(Method, Status, TotalSec, ForwardSec, BackwardSec, ...
                     ResultMB, ProcessMB);
out.accuracy = table(Method, Status, RelL1, MMD, RMSE, MinESS, ESSMeans, ...
                     FactorEvals);
out.replay   = table(Method, Mode, Increments, ReusePct, ReuseUnit, ...
                     EarlyStops, MinMMDAtStop);
out.warnings = warnings;
out.notes    = notes;

out.memoryNote = ...
    "Result MB is the serialized size of what the method handed back, which " + ...
    "is deterministic and comparable. Process MB is the whole MATLAB " + ...
    "process at the instant that method returned: it includes everything " + ...
    "else the session holds, it is not a peak, and MATLAB offers no way to " + ...
    "measure the high-water mark of a block of code -- so none is reported.";
end

% =========================================================================
function s = localStatus(r)
%LOCALSTATUS A result's status, or "unknown" when it has none.
%   Inputs   R, a method result
%   Outputs  S, the status
%   Utility  a malformed result must still produce a row saying so.
if isfield(r, 'status'), s = string(r.status); else, s = "ok"; end
end

function v = localGet(s, f)
%LOCALGET A field's value, or NaN when it is absent.
%   Inputs   S the struct, F the field
%   Outputs  V the value, or NaN
%   Utility  methods report different metrics, and a missing one is NaN rather
%           than a reason to drop the row.
if isstruct(s) && isfield(s, f) && isscalar(s.(f)) && isnumeric(s.(f))
    v = double(s.(f));
else
    v = NaN;
end
end

% =========================================================================
function b = localResultBytes(r)
%LOCALRESULTBYTES The serialized size of what a method handed back.
%   Inputs   R, a method result
%   Outputs  B, the byte count
%   Utility  deterministic and comparable, and a real consequence of the
%           representation each method chose -- unlike the process reading.
%
%   getByteStreamFromArray is the only thing that counts the contents of the
%   objects a result carries; WHOS reports a handle as its handle. It is
%   undocumented, so a failure falls back to WHOS with the undercount that
%   implies rather than failing the panel.
try
    b = numel(getByteStreamFromArray(r));
catch
    w = whos('r');
    b = w.bytes;
end
end

% =========================================================================
function [v, meaning] = localESS(m)
%LOCALESS The ESS a method reports, AND which quantity it is an ESS of.
%   Inputs   M, a result's metrics
%   Outputs  V the value, MEANING which quantity
%   Utility  three engines report three unlike ESS numbers, so the column
%           travels with a second one naming what it measured.
v = NaN;
meaning = "not reported by this method";

health = struct();
if isfield(m, 'health') && isstruct(m.health), health = m.health; end

if isfield(health, 'minEffectiveSampleSize') && isfinite(health.minEffectiveSampleSize)
    v = health.minEffectiveSampleSize;
    meaning = "product of child separator densities (NF-iSAM)";
elseif isfield(health, 'minEssSupport') && isfinite(health.minEssSupport)
    v = health.minEssSupport;
    meaning = "separator support, general engine";
elseif isfield(health, 'minEssOuter') && isfinite(health.minEssOuter)
    v = health.minEssOuter;
    meaning = "outer samples, general engine";
elseif isfield(m, 'ess') && isscalar(m.ess) && isnumeric(m.ess) && isfinite(m.ess)
    v = m.ess;
    meaning = "outer slice weights, three-node engine";
end
end

% =========================================================================
function [mode, nInc, reusePct, unit, stops, minMMD, note] = localReplay(m)
%LOCALREPLAY One method's row of the incremental-replay table.
%   Inputs   M, a result's metrics
%   Outputs  MODE batch or incremental, NINC how many increments, REUSEPCT and
%           UNIT the reuse and what it is measured in, STOPS how many early
%           stops fired, MINMMD the smallest discrepancy seen, NOTE any caveat
%   Utility  the reuse unit differs per method -- cached steps, reused cliques
%           -- so the number is never shown without it.
mode = "-"; nInc = NaN; reusePct = NaN; unit = "-";
stops = NaN; minMMD = NaN; note = "";

if ~isfield(m, 'incremental') || ~isstruct(m.incremental)
    return
end
s = m.incremental;

if isfield(s, 'mode'), mode = string(s.mode); end
nInc     = localGet(s, 'numIncrements');
reusePct = 100 * localGet(s, 'cacheHitRate');
stops    = localGet(s, 'numEarlyStops');
minMMD   = localGet(s, 'minMMDAtStop');
if isfield(s, 'note'), note = string(s.note); end

% The unit is the finding, not a label. The two engines reuse different
% objects -- a conditional smoothing surface per elimination step, versus a
% whole clique flow -- and a hit rate means a different amount of avoided
% work in each.
if isfield(s, 'meanCliquesReused')
    unit = "clique flows";
elseif isfield(s, 'meanVariablesReused')
    unit = "surfaces per step";
end
end
