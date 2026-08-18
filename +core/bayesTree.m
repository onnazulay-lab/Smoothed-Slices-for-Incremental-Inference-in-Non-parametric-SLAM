function tree = bayesTree(graph, order)
%BAYESTREE Convert a factor graph to a Bayes tree under an elimination order.
%
%   Inputs
%     GRAPH  core.FactorGraph
%     ORDER  the elimination order
%
%   Outputs
%     TREE   struct with
%              cliques     core.BayesTreeClique array, root first
%              root        index into cliques
%              order       the elimination order used
%              cliqueOf    map from variable name to clique index
%              numCliques  size of the tree
%              roots       every root, one per graph component
%
%   Utility
%     Build the structure that makes an update incremental, without evaluating
%     or training anything.
%
%   NF-iSAM spec section 2: "the implementation must convert the factor graph
%   to a Bayes tree using a variable elimination ordering". The tree is what
%   makes the update incremental -- Algorithm N3 retrains only the changed
%   subtree -- so this function is the structural half of that claim and
%   core.affectedSubtree is the other half.
%
%   HOW A CLIQUE IS FOUND. Elimination gives each variable a conditional
%   p(omega_j | S_j); core.eliminationSchedule already computes every S_j, so
%   this reads the schedule rather than re-deriving it, and a Bayes tree and a
%   Bayes net drawn from the same case cannot disagree.
%
%   Each variable's tree parent is the member of S_j eliminated EARLIEST --
%   every separator variable is eliminated after omega_j, and the earliest of
%   them is where this conditional attaches. A variable then merges into its
%   parent's clique exactly when
%
%       S_j == {parent} union S_parent
%
%   which is the standard fundamental-supernode test: it says omega_j tells
%   the parent nothing the parent's own separator did not already carry, so
%   keeping them apart would split a clique that is really one. Everything
%   else starts a new clique.
%
%   The frontals of a clique are the variables that merged into it, in
%   elimination order; its separator is the separator of the LAST of them,
%   because merging grows the separator by one variable each step downward.

arguments
    graph (1,1) core.FactorGraph
    order (1,:) string
end

steps = core.eliminationSchedule(graph, order);
n = numel(steps);

if n == 0
    tree = struct('cliques', core.BayesTreeClique.empty(1,0), 'root', 0, ...
                  'order', order, 'cliqueOf', containers.Map('KeyType','char','ValueType','double'));
    return
end

% Elimination position of every variable, so "earliest eliminated" is a lookup.
pos = containers.Map('KeyType', 'char', 'ValueType', 'double');
for j = 1:n
    pos(char(steps(j).frontal)) = j;
end

% --- Tree parent of each variable, and whether it merges into that parent ---
parentVar = strings(1, n);
merges    = false(1, n);
for j = 1:n
    S = steps(j).separator;
    if isempty(S)
        continue    % eliminated last in its component: starts a clique, no parent
    end
    [~, first] = min(cellfun(@(v) pos(v), cellstr(S)));
    parentVar(j) = S(first);

    pj = pos(char(parentVar(j)));
    merges(j) = isequal(sort([parentVar(j) steps(pj).separator]), sort(S));
end

% --- Group variables into cliques ----------------------------------------
% Walk the elimination order backwards so a parent is always assigned before
% the children that might merge into it.
cliqueId = zeros(1, n);
next     = 0;
for j = n:-1:1
    if merges(j)
        cliqueId(j) = cliqueId(pos(char(parentVar(j))));
    else
        next = next + 1;
        cliqueId(j) = next;
    end
end

% Root first: the clique holding the last-eliminated variable is numbered 1
% above, and renumbering is not needed because we walked backwards.
numCliques = next;
cliques = core.BayesTreeClique.empty(1, 0);
for c = 1:numCliques
    members = find(cliqueId == c);          % already ascending = elimination order
    frontal = [steps(members).frontal];
    sepOfLast = steps(members(end)).separator;
    cliques(c) = core.BayesTreeClique( ...
        'Index', c, 'Frontal', frontal, 'Separator', sepOfLast, ...
        'Factors', localConsumedFactors(steps, members));
end

% --- Link cliques ---------------------------------------------------------
% A clique's parent is the clique that owns the earliest-eliminated variable
% of its separator, which is the tree parent of its last frontal.
for c = 1:numCliques
    S = cliques(c).Separator;
    if isempty(S), continue, end
    [~, first] = min(cellfun(@(v) pos(v), cellstr(S)));
    p = cliqueId(pos(char(S(first))));
    cliques(c).Parent = p;
    cliques(p).Children(end+1) = c;
end

cliqueOf = containers.Map('KeyType', 'char', 'ValueType', 'double');
for j = 1:n
    cliqueOf(char(steps(j).frontal)) = cliqueId(j);
end

roots = find(arrayfun(@(c) c.isRoot(), cliques));
tree = struct('cliques', cliques, 'root', roots(1), 'order', order, ...
              'cliqueOf', cliqueOf, 'numCliques', numCliques, 'roots', roots);
end

% -------------------------------------------------------------------------
function names = localConsumedFactors(steps, members)
%LOCALCONSUMEDFACTORS z_C: the graph's own factors eliminated by this clique.
%   Inputs   STEPS the elimination schedule, MEMBERS this clique's step indices
%   Outputs  NAMES, the consumed factor names
%   Utility  partition the original factors across the tree.
%
%   A factor is consumed exactly once, at the first of its variables to be
%   eliminated, so assigning it to that variable's clique partitions the
%   original factors across the tree with none lost and none counted twice.
%   Factors generated during elimination are skipped: they are messages
%   between cliques, not measurements.
names = string.empty(1, 0);
for j = members
    f = steps(j).factors;
    if isempty(f), continue, end
    take = steps(j).removed & ~[f.generated];
    names = [names f(take).name]; %#ok<AGROW>
end
end
