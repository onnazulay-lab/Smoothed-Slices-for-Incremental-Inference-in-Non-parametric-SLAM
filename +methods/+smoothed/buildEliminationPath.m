function path = buildEliminationPath(graph, order, startIndex, opts)
%BUILDELIMINATIONPATH The path xi_0 -> ... -> xi_H of Eq. (36), from the order.
%   PATH = BUILDELIMINATIONPATH(GRAPH, ORDER, STARTINDEX) returns the run of
%   consecutively eliminated variables beginning at ORDER(STARTINDEX) that the
%   recursive surface of spec section 9 can collapse into one update, together
%   with the sampling factor g_r joining each level to the next.
%
%   Inputs
%     GRAPH       core.FactorGraph, in its state BEFORE ORDER(STARTINDEX) is
%                 eliminated
%     ORDER       the elimination order, as a string array
%     STARTINDEX  where the path begins
%     MaxDepth    largest H to return.                        default Inf
%
%   Outputs
%     PATH  struct array, one entry per level r = 0..H, with fields
%       var         the variable at this level
%       orderIndex  where it sits in ORDER
%       gName       name of the sampling factor joining level r-1 to r, "" at
%                   r = 0
%
%   Utility
%     Supply Algorithm 1 with its "Elimination/path variables", which the
%     spec's pseudocode takes as an input and nothing in this project produced.
%
%   THE PATH SPANS ELIMINATION STEPS, IT DOES NOT LIVE INSIDE ONE. This is the
%   thing that is easy to get backwards, and getting it backwards makes the
%   recursion look inapplicable to a general graph. Spec section 5 sets out the
%   paper's own example: x_1 is the FIRST eliminated variable with separator
%   {l_1, x_2}, l_1 is the SECOND with separator {x_2}, and Eq. (19) is what
%   appears when the first step's slice estimator is substituted into the
%   second step's integral. So xi_0 = x_1 and xi_1 = l_1 are two consecutive
%   eliminations, not one elimination and one of its neighbours.
%
%   What the recursion buys is therefore doing H+1 consecutive elimination
%   steps without materializing the intermediate separator factors: R_r
%   summarizes the deeper ones instead. An engine that eliminates one variable
%   per step already has the path -- it is the elimination order -- and what it
%   lacks is the collapsing.
%
%   WHEN THE PATH STOPS, for either of two reasons.
%
%   ONE, no joining factor. Level r+1 joins only if a single factor in the
%   current graph covers both xi_r and xi_{r+1}. That factor is g_r, the one
%   that makes xi_{r+1} sampleable once xi_r is fixed, which is the Lemma 1
%   condition the spec keeps as "the safe support backbone". With no such factor
%   there is no proposal to draw the next level from and the recursion has no
%   q_r, so the path ends and the caller eliminates normally from there.
%
%   TWO, THE PATH MUST LEAVE A SEPARATOR BEHIND. The surface is a function of
%   the variables that remain, so the path cannot swallow all of them. On the
%   paper's own example this is not a corner case but the ordinary behaviour:
%   the order is x_1, l_1, x_2 and f(l_1,x_2) does join l_1 to x_2, so a walk
%   that only checked for a joining factor would return H = 2 and make x_2 a
%   third level. x_2 is the separator. Eq. (41) would then be left with no s
%   argument, R_0(xi_0, s) would be a scalar rather than a surface, and the
%   object computed would be the partition function instead of the new factor.
%
%   The bound is therefore against the graph's remaining variables rather than
%   against the length of ORDER, so it stays right when ORDER covers only part
%   of the graph: GRAPH is the state before ORDER(STARTINDEX) goes, so its
%   variables are exactly the ones not yet eliminated, and at least one of them
%   has to survive the path.
%
%   H IS EXPECTED TO BE SMALL ON REAL GRAPHS, and that is a finding rather than
%   a disappointment. On a range-only SLAM graph a pose is followed in the
%   order by a landmark only when the order chose to; a landmark seen from many
%   poses is usually eliminated far from any single one of them. Measuring the
%   distribution of H is part of what tells you whether the recursion is worth
%   its machinery on a given case, so this returns the path it finds rather
%   than forcing one.
%
%   See also methods.smoothed.evaluateSurfaceRecursion.

arguments
    graph (1,1) core.FactorGraph
    order (1,:) string
    startIndex (1,1) double {mustBeInteger, mustBePositive}
    opts.MaxDepth (1,1) double {mustBePositive} = Inf
end

if startIndex > numel(order)
    error('methods:smoothed:startBeyondOrder', ...
        'Start index %d is past the end of an order of %d variables.', ...
        startIndex, numel(order));
end

path = struct('var', order(startIndex), ...
              'orderIndex', startIndex, ...
              'gName', "");

nRemaining = numel(graph.VariableNames);

for k = (startIndex + 1):numel(order)
    if numel(path) - 1 >= opts.MaxDepth
        break
    end

    if numel(path) + 1 >= nRemaining
        % Adding this level would leave nothing to be the separator. See the
        % header: the surface has to be a function of something.
        break
    end

    prev = path(end).var;
    next = order(k);

    g = localJoiningFactor(graph, prev, next);
    if g == ""
        % No factor covers both, so nothing makes `next` sampleable given
        % `prev`. The run ends here rather than being continued through a
        % level with no proposal behind it.
        break
    end

    path(end+1) = struct('var', next, 'orderIndex', k, 'gName', g); %#ok<AGROW>
end
end

% =========================================================================
function name = localJoiningFactor(graph, a, b)
%LOCALJOININGFACTOR The factor covering both variables, or "" if none does.
%   Inputs   GRAPH; A, B variable names
%   Outputs  NAME, the factor's name, "" when the two are not joined
%   Utility  decide whether b can follow a on the path, and name the g_r that
%            would make it sampleable.
%
%   The FIRST such factor is taken when several qualify. Which one is chosen
%   changes q_r and therefore the estimator's variance, but not what it
%   estimates, since every removed factor is accounted for exactly once by
%   partitionPathFactors whichever is picked. A rule that chose by expected
%   variance would be Algorithm 3's job, not this one's.
name = "";
fs = graph.adjacentFactors(a);
for i = 1:numel(fs)
    if any(fs(i).Scope == b)
        name = fs(i).Name;
        return
    end
end
end
