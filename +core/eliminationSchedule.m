function steps = eliminationSchedule(graph, order)
%ELIMINATIONSCHEDULE The structural replay of variable elimination.
%
%   Inputs
%     GRAPH  core.FactorGraph, in its initial state
%     ORDER  the elimination order
%
%   Outputs
%     STEPS  one entry per elimination, each holding the reduced graph G_{j-1}
%            as it stands when that step BEGINS, with fields
%              step        j
%              frontal     omega_j
%              separator   S_j
%              factors     struct array (name, scope, generated) making G_{j-1}
%              removed     logical over FACTORS, the F_{j-1}(omega_j) that go
%              generated   name of the factor this step creates, "" if none
%
%   Utility
%     Replay what elimination does to the graph, without running it.
%
%   STRUCTURE ONLY. The generated factor of step j is a clique over S_j,
%   which is everything the graph knows about it: its values need a run, its
%   scope does not. That distinction is what lets the app draw the whole
%   procedure on a freshly loaded case, and it is why this lives in +core
%   next to eliminationOrder rather than inside a plotting routine.
%
%   Both graph panels and the ordering diagnostics read this one function, so
%   a factor graph and a Bayes net drawn from the same case cannot disagree
%   about what the separator was.

arguments
    graph (1,1) core.FactorGraph
    order (1,:) string
end

raw = graph.Factors;
factors = struct('name', {}, 'scope', {}, 'generated', {});
for i = 1:numel(raw)
    factors(end+1) = struct('name', string(raw(i).Name), ...
                            'scope', raw(i).Scope, 'generated', false); %#ok<AGROW>
end

steps = struct('step', {}, 'frontal', {}, 'separator', {}, ...
               'factors', {}, 'removed', {}, 'generated', {});

for j = 1:numel(order)
    w = order(j);
    if isempty(factors)
        hit = false(1, 0);
    else
        hit = arrayfun(@(f) any(f.scope == w), factors);
    end

    sep = string.empty(1,0);
    if any(hit)
        sep = unique([factors(hit).scope], 'stable');
        sep(sep == w) = [];
    end

    genName = "";
    if ~isempty(sep)
        genName = sprintf("f_new_%d", j);
    end

    steps(end+1) = struct('step', j, 'frontal', w, 'separator', sep, ...
                          'factors', factors, 'removed', hit, ...
                          'generated', genName); %#ok<AGROW>

    factors(hit) = [];
    if ~isempty(sep)
        factors(end+1) = struct('name', genName, 'scope', sep, ...
                                'generated', true); %#ok<AGROW>
    end
end
end
