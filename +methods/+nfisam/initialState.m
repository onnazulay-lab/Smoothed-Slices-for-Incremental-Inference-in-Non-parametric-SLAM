function state = initialState(graph, order)
%INITIALSTATE The Bayes tree state Algorithm N3 updates, before any update.
%
%   Inputs
%     GRAPH  the factor graph as it stands
%     ORDER  the elimination order
%
%   Outputs
%     STATE  the graph (copied, see below), the order, no tree and no trained
%            samplers
%
%   Utility
%     Give methods.nfisam.incrementalUpdate its starting point.
%
%   There is deliberately no separate batch entry point. The first call to
%   Algorithm N3 from this state finds an empty cache, so every clique misses
%   and every clique is trained -- which IS the batch solve, and says so in the
%   same INFO fields that later increments report their reuse in. Two entry
%   points would have meant two orderings of the same leaf-to-root loop, and
%   the batch one would have been the one nobody ran twice.
%
%   THE GRAPH IS COPIED. CORE.FACTORGRAPH is a handle so that the elimination
%   engine can reduce it in place, and this state is a value struct that
%   callers hold across increments. Without the copy, appending a factor at
%   increment k would reach back into the caller's case graph -- shared with
%   the two other methods in the comparison -- and into every earlier state
%   anyone kept for reference.

arguments
    graph (1,1) core.FactorGraph
    order (1,:) string = string.empty(1,0)
end

if isempty(order)
    order = core.eliminationOrder(graph);
end

missing = order(~ismember(order, graph.VariableNames));
if ~isempty(missing)
    error('methods:nfisam:initialState:unknownVariable', ...
        'The elimination order names %s, which the graph does not have.', ...
        strjoin(missing, ', '));
end

state = struct();
state.graph      = graph.copy();
state.order      = order;
state.tree       = struct('cliques', core.BayesTreeClique.empty(1,0), ...
                          'root', 0, 'numCliques', 0);
state.keys       = methods.nfisam.cliqueKeys(state.tree);
state.samplers   = {};
state.cache      = struct('keys', string.empty(1,0), 'samplers', {{}});
state.numUpdates = 0;
end
