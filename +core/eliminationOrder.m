function [order, info] = eliminationOrder(graph, opts)
%ELIMINATIONORDER Greedy ordering for a general factor graph.
%
%   Inputs
%     GRAPH   core.FactorGraph
%     Method  "chain" (default), "minfill" or "mindegree"
%     First   variable to eliminate first, overriding the heuristic
%     Order   a complete order to SCORE rather than choose
%     Defer   variables to eliminate LAST WHERE POSSIBLE
%
%   Outputs
%     ORDER   the elimination order
%     INFO    the separator each step produces, so the price of the ordering is
%             reported rather than assumed
%
%   Utility
%     Choose an order that can actually be sampled at every step and that keeps
%     the separators representable.
%
%   A hand-written order is fine for three variables and hopeless for the grid
%   world, where the separator dimension decides whether the generated factor
%   can be represented at all.
%
%   Three things are traded off, in this priority:
%
%     1. Lemma 1 eligibility. A variable may be eliminated only if it carries
%        a unary factor or is adjacent to an already-eliminated variable,
%        because otherwise there is no route to sample it. This is a hard
%        constraint, not a preference: an ineligible variable is never picked,
%        which is why the returned order always passes
%        FactorGraph.validateEliminationOrder.
%
%     2. HOP DISTANCE from the variables that carry a prior, under the
%        default "chain" method. Eligibility only asks that SOME eliminated
%        neighbour exists; it does not ask that the resulting proposal be any
%        good. On the grid world a late pose becomes eligible as soon as any
%        beacon it saw is gone, and its only route is then a range factor,
%        which proposes it onto an annulus metres wide instead of onto the
%        tight odometry step from its predecessor. Pure minimum fill takes
%        that bait: it produced a smaller separator and a pose RMSE of 16 m
%        where following the chain gives 0.2 m. Representation cost is worth
%        optimizing, but not at the price of the proposal chain.
%
%     3. Separator DIMENSION, then fill-in. Cost is driven by the dimension of
%        the separator, not by how many variables it holds, so a separator of
%        one planar landmark is scored the same as two scalars. Minimum degree
%        alone would not see that.
%
%   MORE ON TWO OF THE OPTIONS, because both encode a failure already had.
%
%     Order    every step is still checked against Lemma 1, so an order that
%              cannot be sampled is refused here instead of failing somewhere
%              inside the elimination. Used where the caller knows something the
%              heuristic cannot see.
%
%     Defer    a preference, not a constraint: a deferred variable is passed
%              over while any other is eligible, and taken as soon as none is.
%              That "as soon as none is" is the whole point.
%
%              datasets.makePlazaCase wants its landmarks last, because their
%              posteriors are bimodal and handing that density to the poses
%              costs an order of magnitude of pose RMSE. It used to get that
%              by building a finished order and FILTERING the landmarks to the
%              end. That silently assumed what was left was still connected,
%              and it was not: min-degree uses the landmarks as connectors, so
%              deleting them from the middle strands whatever they joined.
%              Ten poses on Plaza2 produced x1 x2 l0 x3 x4 x5 x9 ..., and
%              removing l0 left x9 with no eliminated neighbour and no route
%              to sample it. Nine poses worked, but only because min-degree
%              happened to walk them in chain order.
%
%              Deferring inside the loop cannot have that failure, because the
%              choice is still made from the eligible set at every step.

arguments
    graph (1,1) core.FactorGraph
    opts.Method (1,1) string {mustBeMember(opts.Method, ["chain","minfill","mindegree"])} = "chain"
    opts.First (1,1) string = ""
    opts.Order (1,:) string = string.empty(1,0)
    opts.Defer (1,:) string = string.empty(1,0)
end

if ~isempty(opts.Order) && strlength(opts.First) > 0
    error('core:eliminationOrder:orderAndFirst', ...
        'Order and First both fix step 1; pass one or the other.');
end

if ~isempty(opts.Order) && ~isempty(opts.Defer)
    % Order fixes every step, so a preference about later steps can only be
    % ignored or contradicted. Refusing beats silently dropping one.
    error('core:eliminationOrder:orderAndDefer', ...
        'Order already fixes every step; Defer would have nothing to choose.');
end

names = graph.VariableNames;
n = numel(names);
order = strings(1, 0);

if n == 0
    info = struct('separatorSizes', [], 'separatorDims', [], ...
                  'maxSeparatorDim', 0, 'method', opts.Method, 'steps', struct([]));
    return
end

if ~isempty(opts.Order)
    missing = setdiff(names, opts.Order);
    extra   = setdiff(opts.Order, names);
    if ~isempty(missing) || ~isempty(extra) || numel(opts.Order) ~= n
        error('core:eliminationOrder:incompleteOrder', ...
            ['Order must list each of the %d variables exactly once. ' ...
             'Missing: %s. Not in the graph: %s.'], n, ...
            localOrNone(missing), localOrNone(extra));
    end
end

% Checked rather than quietly ignored: a misspelled name in Defer would
% otherwise look exactly like a preference the heuristic declined to honour,
% which is the kind of no-op that survives for months.
isDeferred = false(1, n);
if ~isempty(opts.Defer)
    unknown = setdiff(opts.Defer, names);
    if ~isempty(unknown)
        error('core:eliminationOrder:noSuchDeferred', ...
            'Defer names variables that are not in this graph: %s.', ...
            localOrNone(unknown));
    end
    isDeferred = reshape(ismember(names, opts.Defer), 1, []);
end

dims = zeros(1, n);
for i = 1:n
    dims(i) = graph.Variables(i).Dim;
end

% Adjacency over variables, plus which variables carry a unary factor. Both
% are derived once from the factor scopes and then maintained as elimination
% proceeds; the graph object itself is left untouched.
adj = false(n, n);
hasUnary = false(1, n);
for f = graph.Factors
    idx = find(ismember(names, f.Scope));
    if isscalar(idx)
        hasUnary(idx) = true;
    end
    adj(idx, idx) = true;
end
adj(1:n+1:end) = false;

% Hop distance from the nearest variable carrying a prior, in the ORIGINAL
% graph. Computed once: this is a property of the problem, not of how far the
% elimination has got, and recomputing it as edges are added would let the
% fill-in edges create shortcuts that do not correspond to any real factor.
hop = localHopDistance(adj, hasUnary);

alive = true(1, n);
% Whether a variable has had a neighbour eliminated. This is tracked as its
% own flag rather than read back off the adjacency, because eliminating a
% variable also deletes its edges: asking the adjacency afterwards would say
% nobody has an eliminated neighbour and stall the order at step 2.
touched = false(1, n);
steps = struct('variable', {}, 'separator', {}, 'separatorDim', {}, 'fill', {});

for step = 1:n
    % Eligibility: a unary factor, or a neighbour already gone.
    eligible = alive & (hasUnary | touched);

    if ~isempty(opts.Order)
        pick = find(names == opts.Order(step), 1);
        if ~eligible(pick)
            % Naming the step and what was already gone is the difference
            % between a fixable message and a puzzle.
            error('core:eliminationOrder:ineligibleInOrder', ...
                ['Order puts %s at step %d, but it has no unary factor and ' ...
                 'no eliminated neighbour yet, so Lemma 1 gives no route to ' ...
                 'sample it. Already eliminated: %s.'], ...
                opts.Order(step), step, localOrNone(order));
        end
    elseif step == 1 && strlength(opts.First) > 0
        pick = find(names == opts.First, 1);
        if isempty(pick)
            error('core:eliminationOrder:noSuchVariable', ...
                'First = %s is not a variable of this graph.', opts.First);
        end
        if ~eligible(pick)
            error('core:eliminationOrder:ineligibleFirst', ...
                ['%s cannot be eliminated first: it has no unary factor, so ' ...
                 'Lemma 1 gives no route to sample it.'], opts.First);
        end
    else
        if ~any(eligible)
            % Every remaining variable is unreachable. Naming one is far more
            % useful than reporting that the order failed.
            stuck = names(alive);
            error('core:eliminationOrder:noEligibleVariable', ...
                ['No remaining variable satisfies Lemma 1 at step %d. ' ...
                 'Unreachable: %s. A landmark observed by nothing, or a ' ...
                 'disconnected component with no prior, causes this.'], ...
                step, strjoin(cellstr(stuck), ', '));
        end
        % Deferred variables are passed over while anything else is eligible,
        % and taken the moment nothing else is. Falling back to them rather
        % than excluding them is what keeps the order connected: excluding
        % them outright is precisely the filtering this option replaces, and
        % it strands whatever they were connecting. The candidate set is a
        % subset of ELIGIBLE either way, so Lemma 1 holds by construction.
        preferred = eligible & ~isDeferred;
        if any(preferred), candidates = find(preferred); else, candidates = find(eligible); end
        pick = localBestCandidate(candidates, adj, dims, alive, hop, opts.Method);
    end

    sepIdx = find(adj(pick,:) & alive);
    sepIdx(sepIdx == pick) = [];

    fill = localFillCount(sepIdx, adj);
    steps(end+1) = struct('variable', names(pick), ...
        'separator', names(sepIdx), 'separatorDim', sum(dims(sepIdx)), ...
        'fill', fill); %#ok<AGROW>

    % The generated factor makes the separator a clique, and every variable
    % in it now has an eliminated neighbour.
    adj(sepIdx, sepIdx) = true;
    adj(1:n+1:end) = false;
    touched(sepIdx) = true;

    alive(pick) = false;
    adj(pick,:) = false;
    adj(:,pick) = false;

    order(end+1) = names(pick); %#ok<AGROW>
end

sepDims = [steps.separatorDim];
method = opts.Method;
if ~isempty(opts.Order), method = "supplied"; end
if ~isempty(opts.Defer), method = method + "+defer"; end
% How many deferred variables did NOT make it to the tail. Zero is the usual
% answer and the interesting one is any other: it says the graph forced a
% deferred variable out early, which is exactly the case the old filtering
% approach got wrong by pretending it could not happen.
deferredEarly = 0;
if ~isempty(opts.Defer)
    % unique, because a name repeated in Defer would otherwise push the tail
    % past the start of the order and index it with a negative range.
    tailStart = max(1, n - numel(unique(opts.Defer)) + 1);
    deferredEarly = sum(ismember(order(1:tailStart-1), opts.Defer));
end
info = struct( ...
    'method',          method, ...
    'deferred',        opts.Defer, ...
    'deferredEarly',   deferredEarly, ...
    'steps',           steps, ...
    'separatorSizes',  cellfun(@numel, {steps.separator}), ...
    'separatorDims',   sepDims, ...
    'maxSeparatorDim', max([sepDims 0]), ...
    'totalFill',       sum([steps.fill]));
end

% =========================================================================
function s = localOrNone(names)
%LOCALORNONE A readable list, or "none", for error messages.
%   Inputs   NAMES, a string array
%   Outputs  S, a char row
%   Utility  keep the error messages readable when a set is empty.
if isempty(names)
    s = "none";
else
    s = strjoin(cellstr(names), ', ');
end
end

% =========================================================================
function pick = localBestCandidate(cand, adj, dims, alive, hop, method)
%LOCALBESTCANDIDATE Cheapest eligible variable under the chosen heuristic.
%   Inputs   CAND the eligible indices, ADJ the adjacency, DIMS the variable
%            dimensions, ALIVE the un-eliminated mask, HOP the prior distances,
%            METHOD the heuristic
%   Outputs  PICK, the chosen index
%   Utility  apply the priority order documented at the top of this file.
best = Inf(1, 4);
pick = cand(1);
for c = cand(:).'
    sepIdx = find(adj(c,:) & alive);
    sepIdx(sepIdx == c) = [];

    sepDim = sum(dims(sepIdx));
    fill = localFillCount(sepIdx, adj);

    switch method
        case "chain"
            score = [hop(c), sepDim, fill, c];
        case "minfill"
            score = [0, sepDim, fill, c];
        case "mindegree"
            score = [0, sepDim, numel(sepIdx), c];
    end

    % Lexicographic comparison, with the index last so the result is
    % deterministic rather than dependent on candidate order.
    if localLess(score, best)
        best = score;
        pick = c;
    end
end
end

% =========================================================================
function hop = localHopDistance(adj, hasUnary)
%LOCALHOPDISTANCE Breadth-first distance from the prior-carrying variables.
%   Inputs   ADJ the adjacency, HASUNARY which variables carry a unary factor
%   Outputs  HOP, distance per variable; Inf where unreachable
%   Utility  measure how far a variable is from a prior, which is what keeps
%            the proposal chain tight rather than merely legal.
%   A variable with no prior anywhere in its component gets Inf, which the
%   lexicographic comparison then ignores in favour of the later terms.
n = size(adj, 1);
hop = inf(1, n);
frontier = find(hasUnary);
hop(frontier) = 0;
d = 0;
while ~isempty(frontier)
    d = d + 1;
    next = find(any(adj(frontier, :), 1) & ~isfinite(hop));
    hop(next) = d;
    frontier = next;
end
if all(~isfinite(hop))
    hop(:) = 0;   % no priors at all; fall back to pure fill
end
end

% =========================================================================
function f = localFillCount(sepIdx, adj)
%LOCALFILLCOUNT Edges the generated factor would have to add.
%   Inputs   SEPIDX the separator indices, ADJ the adjacency
%   Outputs  F, the number of missing edges among the separator
%   Utility  score the representation cost an elimination creates.
f = 0;
for a = 1:numel(sepIdx)
    for b = a+1:numel(sepIdx)
        if ~adj(sepIdx(a), sepIdx(b)), f = f + 1; end
    end
end
end

% =========================================================================
function tf = localLess(a, b)
%LOCALLESS Lexicographic comparison of two score vectors.
%   Inputs   A, B, equal-length score vectors
%   Outputs  TF, true when A sorts before B
%   Utility  break ties in a stated priority order rather than by whichever
%            term happened to be summed first.
tf = false;
for i = 1:numel(a)
    if a(i) < b(i), tf = true;  return, end
    if a(i) > b(i), tf = false; return, end
end
end
