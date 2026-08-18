function out = runIncrementalGeneral(caseData, config)
%RUNINCREMENTALGENERAL Re-eliminate the graph once per increment, k = 1..K.
%
%   Inputs
%     CASEDATA  the case, carrying the increments
%     CONFIG    the method config
%
%   Outputs
%     OUT.increments     one record per increment
%     OUT.final          the last pass, which is what the batch driver would
%                        have produced on its own
%     OUT.cache          the reuse the forward saving actually achieved
%     OUT.numIncrements, OUT.numCompleted
%
%   Utility
%     Replay the mission the way it actually arrives: at increment k the graph
%     holds only the variables and factors introduced up to k, and the
%     posterior is re-derived from that graph.
%
%   This is where the two savings the papers describe finally have somewhere
%   to stand, and they cut the pass from opposite ends:
%
%     FORWARD, spec Smoothed Slices sections 10-11. A new pose adds an
%     odometry factor and some range readings, all of them at the far end of
%     the elimination order. Every step before the first one those factors
%     touch has identical inputs to the step of the same name at increment
%     k-1, so its conditional smoothing surface is fetched from
%     methods.general.StepCache instead of being rebuilt.
%
%     BACKWARD, Slices Algorithm S5 steps 5-7. The traversal runs newest to
%     oldest, and once a pose's marginal stops moving -- MMD below vartheta --
%     the poses behind it are left as they were.
%
%   The two boundaries are found independently and need not coincide. Where
%   they differ is informative rather than embarrassing: the forward boundary
%   is structural (which factors changed) and the backward one is numerical
%   (whether the change was large enough to matter), and a structural change
%   that moves nothing is precisely what early stopping is for.
%
%   WHAT THIS IS NOT. It is not iSAM-style fluid relinearization: the graph is
%   re-eliminated from scratch each increment, and the cache makes the
%   unchanged prefix cheap rather than skipping it as a matter of policy. The
%   answer at increment K is therefore the batch answer, modulo the reuse the
%   stopping rule was explicitly asked for.

arguments
    caseData (1,1) struct
    config (1,1) struct
end

if ~isfield(caseData, 'increments') || isempty(caseData.increments)
    error('methods:general:noIncrements', ...
        ['Case %s carries no increments block, so there is nothing to ' ...
         'replay incrementally.'], caseData.name);
end

useCache = true;
if isfield(config, 'surfaceCache'), useCache = config.surfaceCache; end
earlyStop = true;
if isfield(config, 'mmdEarlyStopping'), earlyStop = config.mmdEarlyStopping; end

cache = methods.general.StepCache(config, 'Enabled', useCache);

K = numel(caseData.increments);
records = struct('k', {}, 'poseName', {}, 'numNewFactors', {}, ...
                 'numVariables', {}, 'numFactors', {}, 'numSteps', {}, ...
                 'variables', {}, 'order', {}, 'orderSource', {}, ...
                 'runtimeForward', {}, 'runtimeBackward', {}, ...
                 'factorEvaluations', {}, 'factorEvalsForward', {}, ...
                 'factorEvalsBackward', {}, 'cache', {}, 'earlyStop', {}, ...
                 'poseRMSE', {}, 'lookup', {}, 'status', {}, 'message', {});

previous = struct();
final = struct();
prevOrder = string.empty(1, 0);

p = utils.progressOf(config);

for k = 1:K
    pk = p.sub((k-1)/K, k/K);
    pk.report(0, sprintf("increment %d of %d", k, K));
    [subCase, orderSource] = localSubCase(caseData, k, prevOrder);
    prevOrder = subCase.eliminationOrder;

    evalsBefore = caseData.counter.snapshot();
    cache.resetCounters();

    rec = struct('k', k, 'poseName', caseData.increments(k).poseName, ...
        'numNewFactors', numel(caseData.increments(k).factorIndex), ...
        'numVariables', subCase.graph.NumVariables, ...
        'numFactors', subCase.graph.NumFactors, ...
        'numSteps', numel(subCase.eliminationOrder), ...
        'variables', {subCase.graph.VariableNames}, ...
        'order', {subCase.eliminationOrder}, ...
        'orderSource', orderSource, ...
        'runtimeForward', NaN, 'runtimeBackward', NaN, ...
        'factorEvaluations', 0, 'factorEvalsForward', 0, ...
        'factorEvalsBackward', 0, 'cache', cache.stats(), ...
        'earlyStop', [], 'poseRMSE', NaN, 'lookup', [], ...
        'status', "ok", 'message', "");

    try
        tf = tic;
        [conds, states, book, root] = methods.general.forwardEliminationGeneral( ...
            subCase, localWithProgress(config, pk.sub(0, 0.65)), ...
            'Cache', cache, 'StepSeed', true);
        rec.runtimeForward = toc(tf);
        evalsMid = caseData.counter.snapshot();

        tb = tic;
        post = methods.general.backwardSampleGeneral(conds, root, subCase, ...
            localWithProgress(config, pk.sub(0.65, 1)), ...
            'Previous', previous, 'EarlyStop', earlyStop && k > 1);
        rec.runtimeBackward = toc(tb);
    catch err
        % A cancellation is not an increment that failed to eliminate: it is
        % the user, and recording it as a failed increment would put a
        % fabricated engine diagnostic in the replay table and then carry on
        % running the increments they asked to stop.
        if utils.ProgressReporter.isCancellation(err), rethrow(err), end

        % An increment too sparse to eliminate is a fact about the mission,
        % not a bug: increment 1 of a case whose first pose carries no prior
        % has no Lemma 1 route. Record it and carry on rather than losing the
        % increments that would have worked.
        rec.status = "failed";
        rec.message = string(err.message);
        rec.cache = cache.stats();
        records(end+1) = rec; %#ok<AGROW>
        continue
    end

    rec.factorEvaluations = caseData.counter.snapshot() - evalsBefore;
    rec.factorEvalsForward  = evalsMid - evalsBefore;
    rec.factorEvalsBackward = caseData.counter.snapshot() - evalsMid;
    rec.cache = cache.stats();
    rec.earlyStop = post.earlyStop;
    rec.lookup = post.lookupDistance;
    rec.poseRMSE = localPoseRMSE(caseData, subCase, post.marginals);

    records(end+1) = rec; %#ok<AGROW>

    previous = post.marginals;
    final = struct('conditionals', conds, 'states', states, 'book', book, ...
                   'root', root, 'post', post, 'subCase', subCase, ...
                   'increment', k);
end

if isempty(fieldnames(final))
    % Carrying the first message into the error matters more here than
    % anywhere else in the engine: without it the caller is told that nothing
    % worked and given no way to find out why, K messages having been
    % recorded into a struct that is about to be discarded.
    error('methods:general:everyIncrementFailed', ...
        'No increment of %s could be eliminated. First failure at k = %d: %s', ...
        caseData.name, records(1).k, records(1).message);
end

% The cache's own counters are reset per increment so each record reports its
% own hits; the run total is therefore summed here rather than read off the
% object, which by now holds increment K's numbers alone.
perInc = [records.cache];
hits = sum([perInc.hits]);
misses = sum([perInc.misses]);
rate = 0;
if hits + misses > 0, rate = hits / (hits + misses); end

cs = cache.stats();

out = struct();
out.increments = records;
out.final = final;
out.cache = struct('enabled', useCache, 'hits', hits, 'misses', misses, ...
                   'hitRate', rate, 'entries', cs.entries, ...
                   'evictions', cs.evictions);
out.numIncrements = K;
out.numCompleted = sum([records.status] == "ok");
end

% =========================================================================
function [subCase, source] = localSubCase(caseData, k, prevOrder)
%LOCALSUBCASE The case as it stood at increment k, and where its order came from.
%   Inputs   CASEDATA the whole case, K the increment, PREVORDER the previous
%           increment's elimination order
%   Outputs  SUBCASE the truncated case, SOURCE "appended" or "recomputed"
%   Utility  append to the previous order rather than recomputing it, since a
%           churned order costs the whole cache; SOURCE says which happened.
%
%   Variables are taken from the SCOPES of the selected factors rather than
%   from the increments' newVariables list. The two agree on a healthy case
%   and only the scopes can be wrong: a landmark nobody ended up seeing is
%   dropped from the graph by the generator, and a variable list that still
%   named it would build a graph with an unconstrained node in it.
idx = sort([caseData.increments(1:k).factorIndex]);
factors = caseData.graph.Factors(idx);

inScope = string.empty(1, 0);
for i = 1:numel(factors)
    inScope = [inScope factors(i).Scope]; %#ok<AGROW>
end
inScope = unique(inScope, 'stable');

keep = ismember(caseData.graph.VariableNames, inScope);
vars = caseData.graph.Variables(keep);

subGraph = core.FactorGraph(vars, factors, caseData.counter);

% --- The order, which is where incremental inference is won or lost ------
% Preference: keep the previous increment's order and APPEND what has just
% arrived, taking the new variables in the relative order the full-graph
% heuristic gives them.
%
% Re-running the heuristic per increment looks more principled and is worse
% on both counts this loop exists for. Four Doors is the example: the
% heuristic ranks hop distance from a unary factor, a door sighting IS a
% unary factor, so a door seen at k = 6 makes x6 the SECOND variable
% eliminated and shifts every step behind it. That costs most of the reuse --
% measured on Four Doors, the hit rate falls from 67 to 40 per cent, and the
% pose error moves with it -- and it also breaks
% the backward pass's assumption that root-to-leaf runs newest-to-oldest,
% which is the assumption the MMD stopping rule stands on. Appending keeps
% both: prefixes stay stable and the newest variable stays at the root.
%
% Lemma 1 still has to hold, and it is checked rather than assumed. A new
% pose is adjacent to the previous one, which by construction was eliminated
% earlier, so appending is normally safe; when it is not, the restricted full
% order and then a fresh ordering are tried in turn and which one was used is
% recorded, because a changed order invalidates the cache and the hit rate
% would otherwise look like a regression with no cause.
present = [vars.Name];
fullOrder = caseData.eliminationOrder(ismember(caseData.eliminationOrder, present));

kept = prevOrder(ismember(prevOrder, present));
appended = fullOrder(~ismember(fullOrder, kept));
candidates = {[kept appended], fullOrder};
sources = ["incremental", "restricted"];

order = string.empty(1, 0);
source = "recomputed";
for i = 1:numel(candidates)
    try
        subGraph.validateEliminationOrder(candidates{i});
        order = candidates{i};
        source = sources(i);
        break
    catch
        % try the next one
    end
end
if isempty(order)
    order = core.eliminationOrder(subGraph);
end

subCase = caseData;
subCase.graph = subGraph;
subCase.eliminationOrder = order;
subCase.targetVariable = order(end);
subCase.pathVariables = order(1:min(2, max(1, numel(order) - 1)));
end

% =========================================================================
function v = localPoseRMSE(caseData, subCase, marginals)
%LOCALPOSERMSE Pose RMSE of one increment, against the poses it actually held.
%   Inputs   CASEDATA the whole case, SUBCASE this increment's, MARGINALS its
%           posterior
%   Outputs  V, the RMSE in map units
%   Utility  score an increment against its own poses; scoring against the
%           full trajectory would charge it for poses it has not seen.
%
%   Scoring against poses the increment has not seen yet would report the
%   prior's error as if it were the estimate's.
names = caseData.mission.poseNames;
present = ismember(names, subCase.graph.VariableNames);
err = [];
for i = find(present)
    key = matlab.lang.makeValidName(names(i));
    if ~isfield(marginals, key), continue, end
    m = mean(marginals.(key), 1);
    err(end+1) = norm(m - caseData.groundTruth.poses(i, :)); %#ok<AGROW>
end
if isempty(err)
    v = NaN;
else
    v = sqrt(mean(err.^2));
end
end

% =========================================================================
function config = localWithProgress(config, p)
%LOCALWITHPROGRESS A copy of the config carrying one increment's sub-reporter.
%   Inputs   CONFIG the base, P the sub-reporter
%   Outputs  CONFIG, the copy
%   Utility  each increment reports its own 0..1 into its share of the whole
%           run's bar.
config.progress = p;
end
