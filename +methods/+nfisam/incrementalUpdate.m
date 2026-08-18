function [state, info] = incrementalUpdate(state, newFactors, opts)
%INCREMENTALUPDATE Algorithm N3 of the NF-iSAM spec.
%
%   Inputs
%     STATE         from methods.nfisam.initialState or a previous update
%     NEWFACTORS    the measurements to add
%     NewVariables  core.Variable array for names the new factors introduce
%     PreferredOrder complete case-level elimination order; it is restricted
%                    to variables currently present before the tree is built
%     NumSamples    n_train per clique; spec section 9 default is 2000
%     Training      forwarded to flows.trainFlow
%     AngleColumns  variable name -> which of its columns are orientations
%     Reuse         false retrains every clique                default true
%     Seed          seeds the global stream once
%
%   Outputs
%     STATE  the same state with a rebuilt tree and a trained sampler on every
%            clique
%     INFO   which cliques were trained and which reused, reuseFraction,
%            outsideSubtree, orderSource, and a per-clique record
%
%   Utility
%     Add the new measurements and return a state in which every clique of the
%     Bayes tree has a trained conditional sampler.
%
%   The three steps of the algorithm, and where each one is:
%
%     1. G.update(f, Theta)                      the graph copy below
%     2. T_delta <- T.extract(f, Theta)          CORE.AFFECTEDSUBTREE
%     3. leaf-to-root over T_delta:              the traversal below
%          x, o <- TrainingSampleSimulator(C)    METHODS.NFISAM.TRAININGSAMPLESIMULATOR
%          p(F|S), p(S) <- ConditionalSamplerTrainer(x, o)
%          append p(S_C) to the parent           METHODS.NFISAM.COMBINECHILDSEPARATORS
%
%   WHAT IS RETRAINED IS NOT WHAT STEP 2 RETURNS, and the difference is the
%   one substantive departure here. Step 2 names the cliques the new factors
%   change. This implementation rebuilds the whole Bayes tree after the graph
%   update rather than re-eliminating it surgically, and a rebuild can reshape
%   a clique BELOW the changed subtree: adding a loop closure can split a
%   clique whose own variables nobody measured, because its merge into its
%   parent depended on the parent's separator. Retraining is therefore driven
%   by clique identity -- METHODS.NFISAM.CLIQUEKEYS -- and step 2's answer is
%   computed alongside and reported. INFO.outsideSubtree is the cliques where
%   they disagreed; on a plain append it is empty, and a run in which it never
%   empties is a sign the elimination order is churning.
%
%   REUSE IS THE POINT. A clique outside the retraining set keeps the flow it
%   already has, at the cost of nothing: no simulation, no fit, no iteration.
%   INFO.reuseFraction is the direct counterpart of the StepCache hit rate on
%   the Slices side, and the one number that says whether the incremental
%   claim held on this case.
%
%   THE ELIMINATION ORDER FIRST FOLLOWS PREFERREDORDER, when one is supplied,
%   restricted to the variables currently present. This is a correctness
%   requirement for cases such as Plaza whose intended order is poses first and
%   landmarks last: a landmark can appear before a future pose in the data
%   stream, but it must not become permanently earlier than that pose in the
%   elimination order. If the preferred restricted order is unavailable or
%   invalid, the stable append order is tried next; only then is a fresh order
%   recomputed. INFO.orderSource records which route was used.
%
%   OPTION NOTES.
%     NewVariables     Not inferred: a variable carries a domain,
%                      and inventing one would put a made-up support into the
%                      graph the other two methods also read.
%     PreferredOrder   A complete case-level order. At each update it is
%                      restricted to the variables currently present. Any
%                      current variables not listed are appended defensively.
%     NumSamples       n_train per clique; spec section 9 default is 2000,
%                      which FLOWS.TRAINFLOW documents as measurably thin.
%     Training         forwarded to FLOWS.TRAINFLOW.
%     AngleColumns     variable name -> which of its columns are orientations,
%                      for the whole graph. Each clique is given the part of
%                      it that names its own variables, because
%                      METHODS.NFISAM.CONDITIONALSAMPLERTRAINER refuses a
%                      declaration it cannot apply -- rightly, since silently
%                      ignoring it there would leave orientations unwrapped.
%     Reuse            false retrains every clique. The counterfactual the
%                      incremental claim is measured against.
%     Seed             seeds the global stream once, so an update is
%                      reproducible end to end: simulation, training and the
%                      resampling in COMBINECHILDSEPARATORS all draw from it.

arguments
    state (1,1) struct
    newFactors (1,:) core.Factor = core.Factor.empty(1,0)
    opts.NewVariables (1,:) core.Variable = core.Variable.empty(1,0)
    opts.PreferredOrder (1,:) string = string.empty(1,0)
    opts.NumSamples (1,1) double {mustBeInteger, mustBePositive} = 2000
    opts.Training (1,1) struct = struct()
    opts.AngleColumns (1,1) struct = struct()
    opts.MultimodalMeasurement (1,1) string = "maxWeight"
    opts.Reuse (1,1) logical = true
    opts.Seed = []
    %PROGRESS A utils.ProgressReporter, or [] for a run nobody is watching.
    %   An option rather than a config field because this function takes no
    %   config: it is called with the pieces of one, and adding the whole
    %   struct just to carry a reporter would blur what it actually depends on.
    opts.Progress = []
end

tStart = tic;
if ~isempty(opts.Seed)
    rng(opts.Seed);
end

% --- Step 1: G.update(f, Theta) ------------------------------------------
% On a copy: the state is a value struct held across increments, and
% CORE.FACTORGRAPH is a handle, so appending in place would reach back into
% every earlier state the caller kept and into the case graph itself.
graph = state.graph.copy();

for i = 1:numel(opts.NewVariables)
    v = opts.NewVariables(i);
    if any(graph.VariableNames == v.Name)
        error('methods:nfisam:incrementalUpdate:duplicateVariable', ...
            '%s is already in the graph.', v.Name);
    end
    graph.addVariable(v);
end

for i = 1:numel(newFactors)
    unknown = newFactors(i).Scope(~ismember(newFactors(i).Scope, graph.VariableNames));
    if ~isempty(unknown)
        error('methods:nfisam:incrementalUpdate:unknownVariable', ...
            ['Factor %s names %s, which the graph does not have. Pass it as ' ...
             'NewVariables: a variable carries a domain, and this function ' ...
             'will not invent one.'], newFactors(i).Name, strjoin(unknown, ', '));
    end
    graph.addFactor(newFactors(i));
end

% --- The elimination order ------------------------------------------------
% Prefer the case-level order restricted to the variables that exist NOW.
% This intentionally allows a newly arriving pose to be inserted before a
% landmark that appeared in an earlier increment. Plaza needs exactly that:
% its correct poses-first / landmarks-last order cannot be represented by a
% permanently append-only prefix once a landmark has been observed.
present = graph.VariableNames;

kept = state.order(ismember(state.order, present));
appended = present(~ismember(present, kept));
appendOrder = [kept appended];

candidates = cell(1, 0);
sources = strings(1, 0);

if ~isempty(opts.PreferredOrder)
    preferred = opts.PreferredOrder(ismember(opts.PreferredOrder, present));
    % Defensive only: a caller should pass a complete case order, but do not
    % silently drop a current variable if an older caller does not.
    missingPreferred = present(~ismember(present, preferred));
    preferred = [preferred missingPreferred];
    candidates{end+1} = preferred; %#ok<AGROW>
    sources(end+1) = "preferred-restricted"; %#ok<AGROW>
end

candidates{end+1} = appendOrder;
sources(end+1) = "appended";

order = string.empty(1, 0);
orderSource = "recomputed";
for i = 1:numel(candidates)
    candidate = candidates{i};
    try
        graph.validateEliminationOrder(candidate);
        order = candidate;
        orderSource = sources(i);
        break
    catch
        % Try the next candidate. TrainingSampleSimulator remains the final
        % Algorithm-N1 guard if a structurally valid order is not generative
        % for a particular clique.
    end
end

if isempty(order)
    order = core.eliminationOrder(graph);
end

% --- Step 2: T_delta <- T.extract(f, Theta) ------------------------------
tree = core.bayesTree(graph, order);
keys = methods.nfisam.cliqueKeys(tree);
numC = numel(tree.cliques);

changed = string.empty(1, 0);
for i = 1:numel(newFactors)
    changed = [changed newFactors(i).Scope]; %#ok<AGROW>
end
changed = unique(changed, 'stable');

if isempty(changed) || state.numUpdates == 0
    % Nothing to extract from: the first update has no previous tree to
    % compare against, so the changed subtree is the whole tree.
    subtree = keys.leafToRoot;
else
    subtree = core.affectedSubtree(tree, changed);
end

% --- Step 3: leaf to root ------------------------------------------------
% Every clique is visited, not only those of T_delta, because the retraining
% set is decided by key and a clique with no cache entry has no sampler at
% all. The set is upward closed -- a clique's subtree key contains its
% children's -- so deepest-first is still the order that has each clique's
% children ready before it is trained.
samplers = cell(1, numC);
recCell  = cell(1, numC);
trained  = zeros(1, 0);
reused   = zeros(1, 0);

% One clique is the natural boundary: a flow fit is seconds to tens of
% seconds and is the unit of work Algorithm N3 either does or reuses. There
% is no finer place to stop -- flows.trainFlow owns the iteration loop, and
% stopping inside one would leave a half-fitted flow in the cache under a
% subtree key that claims it is finished.
p = utils.progressOf(struct('progress', opts.Progress));
done = 0;

for c = keys.leafToRoot
    done = done + 1;
    tClique = tic;
    cl = tree.cliques(c);
    p.report((done - 1) / numC, sprintf("clique %d of %d (%s)", ...
        done, numC, strjoin(tree.cliques(c).Frontal, ",")));

    hit = [];
    if opts.Reuse && ~isempty(state.cache.keys)
        hit = find(state.cache.keys == keys.subtree(c), 1);
    end

    if ~isempty(hit)
        samplers{c} = state.cache.samplers{hit};
        reused(end+1) = c; %#ok<AGROW>
        recCell{c} = localRecord(c, cl, samplers{c}, "reused", toc(tClique), ...
            struct(), struct(), struct());
        continue
    end

    % The children's separator densities, which is what step 3 appends to
    % this clique. A child's separator is normally among this clique's
    % frontals; where it reaches into this clique's own separator as well,
    % the draw simply lands there instead and is passed further up, which is
    % what a shared variable is supposed to do.
    [given, gInfo] = methods.nfisam.combineChildSeparators( ...
        samplers(cl.Children), opts.NumSamples);

    [Sd, Vd, n1] = methods.nfisam.trainingSampleSimulator( ...
        localFactorsNamed(graph, cl.Factors), ...
        'NumSamples', opts.NumSamples, 'Given', given, ...
        'Frontal', cl.Frontal, 'Separator', cl.Separator, ...
        'MultimodalMeasurement', opts.MultimodalMeasurement);

    [samplers{c}, n2] = methods.nfisam.conditionalSamplerTrainer(Sd, Vd, ...
        'Observations', n1.observations, ...
        'Separator', cl.Separator, 'Frontal', cl.Frontal, ...
        'AngleColumns', localAnglesFor(opts.AngleColumns, ...
                            [n1.observations cl.Separator cl.Frontal]), ...
        'Training', opts.Training);

    trained(end+1) = c; %#ok<AGROW>
    recCell{c} = localRecord(c, cl, samplers{c}, "trained", toc(tClique), ...
        n1, n2, gInfo);
end

if numC == 0
    perClique = localRecord();
    perClique(:) = [];
else
    perClique = [recCell{:}];
end

% --- The cache, pruned to the tree that now exists ------------------------
% A clique shape that has gone will not come back: the order only grows, so
% keeping its flow would hold a trained network per increment for the life of
% the run. What was dropped is reported rather than dropped quietly.
evicted = sum(~ismember(state.cache.keys, keys.subtree));

cache = struct();
cache.keys     = keys.subtree;
cache.samplers = samplers;

state.graph      = graph;
state.order      = order;
state.tree       = tree;
state.keys       = keys;
state.samplers   = samplers;
state.cache      = cache;
state.numUpdates = state.numUpdates + 1;

outside = setdiff(trained, subtree);
frac = @(x) localFraction(numel(x), numC);

% WHAT DECIDED REUSE, AND WHETHER THE TREE SURVIVED. Both are conditions the
% incremental claim of Algorithm N3 rests on, and neither was reported.
%
% treeWasRebuilt is true on every update and that is the point of saying it:
% this implementation rebuilds the whole Bayes tree after the graph update
% instead of re-eliminating surgically, so a clique kept its flow because its
% subtree key matched, NOT because the tree around it was left alone. A reader
% comparing the reuse fraction against the paper's needs to know which of those
% two things was measured.
if opts.Reuse
    reuseRule = "subtree key match against the previous update's cache";
else
    reuseRule = "disabled (Reuse=false): every clique retrained, the batch counterfactual";
end

info = struct( ...
    'update',            state.numUpdates, ...
    'order',             order, ...
    'orderSource',       orderSource, ...
    'treeWasRebuilt',    true, ...
    'reuseRule',         reuseRule, ...
    'numTrained',        numel(trained), ...
    'numReused',         numel(reused), ...
    'changedVariables',  changed, ...
    'numCliques',        numC, ...
    'subtree',           subtree, ...
    'subtreeFraction',   frac(subtree), ...
    'trained',           trained, ...
    'reused',            reused, ...
    'outsideSubtree',    outside, ...
    'retrainedFraction', frac(trained), ...
    'reuseFraction',     frac(reused), ...
    'cache',             struct('hits', numel(reused), 'misses', numel(trained), ...
                                'entries', numC, 'evicted', evicted), ...
    'numSamples',        opts.NumSamples, ...
    'perClique',         perClique, ...
    'runtime',           toc(tStart));
end

% =========================================================================
function f = localFraction(a, b)
%LOCALFRACTION A over B, or NaN when there was nothing to divide.
%   Inputs   A, B
%   Outputs  F, the ratio or NaN
%   Utility  NaN is "not applicable" and 0 is "tried and failed"; a tree with
%           no cliques must not report a reuse rate of zero.
if b == 0, f = 0; else, f = a / b; end
end

function fs = localFactorsNamed(graph, names)
%LOCALFACTORSNAMED The graph's factors with the given names.
%   Inputs   GRAPH, NAMES
%   Outputs  FS, the factor array
%   Utility  a clique records its factors by name, and training needs the
%           objects.
all = graph.Factors;
if isempty(all) || isempty(names)
    fs = core.Factor.empty(1, 0);
    return
end
fs = all(ismember(arrayfun(@(f) string(f.Name), all), names));
end

function a = localAnglesFor(spec, names)
%LOCALANGLESFOR The part of an angle declaration that names a clique's variables.
%   Inputs   SPEC the whole-graph declaration, NAMES this clique's variables
%   Outputs  A, the applicable part
%   Utility  conditionalSamplerTrainer refuses a declaration it cannot apply,
%           rightly, so each clique is handed only its own share.
a = struct();
if isempty(fieldnames(spec)) || isempty(names), return, end
valid = arrayfun(@(v) string(matlab.lang.makeValidName(v)), names);
for f = string(fieldnames(spec)).'
    if any(valid == f)
        a.(f) = spec.(f);
    end
end
end

function r = localRecord(c, cl, sampler, action, runtime, n1, n2, gInfo)
%LOCALRECORD One clique's line of the update record.
%   Inputs   C the index, CL the clique, SAMPLER its sampler, ACTION trained
%           or reused, RUNTIME, N1 and N2 the two algorithms' info, GINFO the
%           child-separator combination. Called with no arguments to get the
%           empty struct with the right fields.
%   Outputs  R, one record
%   Utility  build the record in one place so a reused clique and a trained
%           one cannot have different fields.
if nargin == 0
    r = localRecord(0, core.BayesTreeClique(), [], "", 0, struct(), struct(), struct());
    return
end

r = struct();
r.index      = c;
r.label      = cl.label();
r.action     = action;
r.frontal    = cl.Frontal;
r.separator  = cl.Separator;
r.numChildren = numel(cl.Children);
r.runtime    = runtime;

r.dimension  = NaN;
if isa(sampler, 'methods.nfisam.ConditionalSampler')
    r.dimension = sampler.Flow.Dimension;
end

r.numObservations = numel(localField(n1, 'observations', string.empty(1,0)));

t = localField(n2, 'training', struct());
r.iterations   = localField(t, 'iterations', NaN);
r.finalLoss    = localField(t, 'finalLoss', NaN);
r.logLikelihood = localField(t, 'logLikelihood', NaN);
r.heldOutLogLikelihood = localField(t, 'heldOutLogLikelihood', NaN);

z = localField(n2, 'observationZ', []);
if isempty(z), r.maxObservationZ = NaN; else, r.maxObservationZ = max(abs(z)); end
r.outOfSupport = localField(n2, 'observationOutOfSupport', false);

ess = localField(gInfo, 'effectiveSampleSize', []);
if isempty(ess), r.minEffectiveSampleSize = NaN; else, r.minEffectiveSampleSize = min(ess); end
r.approximatedSeparators = localField(gInfo, 'approximated', string.empty(1,0));
end

function v = localField(s, name, default)
%LOCALFIELD A field's value, or a default when it is absent.
%   Inputs   S the struct, NAME the field, DEFAULT the fallback
%   Outputs  V the value or the default
%   Utility  a reused clique carries no fresh training info, so the record
%           has to tolerate its absence.
if isstruct(s) && isscalar(s) && isfield(s, name)
    v = s.(name);
else
    v = default;
end
end
