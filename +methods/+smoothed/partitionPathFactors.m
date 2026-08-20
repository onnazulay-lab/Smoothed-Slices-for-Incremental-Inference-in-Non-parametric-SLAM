function part = partitionPathFactors(factors, path, separator)
%PARTITIONPATHFACTORS Split the removed factors into g_r, a_r and b_0.
%   PART = PARTITIONPATHFACTORS(FACTORS, PATH, SEPARATOR) assigns every factor
%   removed by a path of eliminations to exactly one role in Eqs. (37)-(41),
%   and refuses to return unless every one of them was assigned exactly once.
%
%   Inputs
%     FACTORS    core.Factor array, the union of the factors removed by
%                eliminating every variable on PATH
%     PATH       struct array from methods.smoothed.buildEliminationPath
%     SEPARATOR  string array, the variables left after the whole path is gone
%
%   Outputs
%     PART  struct with fields
%       g        1 x H cell, g{j} the sampling factor joining level j-1 to j
%       a        1 x H cell, a{j} the fusion factors whose deepest level is j,
%                consumed at step j-1
%       b0       core.Factor array, the front factors of Eq. (41)
%       counts   per-role factor counts, for the diagnostics
%
%   Utility
%     Turn "the removed factors" into the four symbols the recursion is written
%     in, once, so that no factor is used twice and none is dropped.
%
%   WHY THIS ASSERTS INSTEAD OF TRUSTING ITSELF. Double counting here is
%   invisible: the answer stays smooth, stays normalizable, stays plausible,
%   and is simply wrong by a factor that varies with the data. The existing
%   two-pose implementation had to reason about exactly this -- see
%   evaluateSurfaceRecursion's note that a_0 is identically 1 "because the only
%   factor coupling l1 to the separator is already the terminal surface;
%   putting it in both places would double count it". That reasoning was
%   correct and was carried in a comment. At H = 1 with four factors a comment
%   is enough; over an arbitrary path it is not.
%
%   THE ASSIGNMENT RULE. Each factor goes to the DEEPEST path level it touches:
%
%     touches no path variable          -> impossible; it would not have been
%                                          removed, and is an error
%     is the chosen g_r of some level   -> g, and only there
%     deepest path variable is xi_0     -> b_0, the front factor of Eq. (41)
%     deepest path variable is xi_j     -> a{j}, consumed at STEP j-1
%
%   WHICH SLOT IS WHICH, because the spec's own indexing does not survive being
%   read literally and this is where the reading is pinned. Eq. (39) types the
%   fusion factor a_r(xi_{r+1}, s) -- an argument at level r+1 -- while Eq. (38)
%   initializes R_H(xi_H, s) = a_H(xi_H, s). Taken literally, the r = H-1
%   instance of Eq. (40) and the base case of Eq. (38) both multiply in the
%   factors at level H, which is the double count this function exists to rule
%   out. The convention here, written out so it can be checked:
%
%     a{j} holds the factors whose deepest path level is j,   j = 1..H
%     step r forms R_r from R_{r+1} with xi_r on the ROWS and xi_{r+1} on the
%       COLUMNS, and consumes a{r+1}
%     R_H = 1, the empty product, NOT a_H
%
%   So a level-j-only factor arrives at step j-1 as a function of that step's
%   COLUMN variable, which is Eq. (47)'s a_r(xi_{r+1}, s) read literally, and
%   every slot is consumed exactly once. Eq. (38)'s a_H is then absorbed into
%   the last step rather than initialized separately; the integrand is the same
%   product either way, and putting a_H in both places is the double count.
%
%   WHY THE SLOT IS INDEXED BY THE DEEPEST LEVEL AND CONSUMED ONE STEP ABOVE
%   IT, which is the part that looks like an off-by-one and is not. A factor
%   over {xi_r, xi_{r+1}} -- odometry between two poses eliminated one after
%   the other, entirely ordinary -- depends on BOTH the row and the column
%   variable of step r. Only step r has both in scope, and its deepest level is
%   r+1, so "slot j is consumed at step j-1" is what places it correctly. An
%   arrangement that multiplied each slot in as a row-indexed matrix could not
%   represent that factor at all, which is why Eq. (47) carries the rank-3
%   tensor A_r(a,b,rho) rather than a matrix.
%
%   A FACTOR SPANNING THREE PATH LEVELS IS REFUSED. {xi_r, xi_{r+1}, xi_{r+2}}
%   has no step with all three in scope, because the tower of Eqs. (36)-(41) is
%   a CHAIN: each step sees one row level and one column level and nothing
%   else. That is a real limit of the recursion rather than of this function,
%   so it errors here instead of being evaluated at whichever two levels
%   happen to be available and quietly dropping the third.
%
%   See also methods.smoothed.buildEliminationPath.

arguments
    factors (1,:) core.Factor
    path (1,:) struct
    separator (1,:) string
end

H = numel(path) - 1;
pathVars = [path.var];

% g_r joins level r to level r+1, and buildEliminationPath records each gName
% on the level it joins TO. So g_0 is path(2).gName and level 0 carries the ""
% placeholder, which is why the offset is here rather than [path.gName]:
% reading that directly looks for a factor named "" as g_0 and reports every
% path as missing its sampling factor.
gNames = [path(2:end).gName];

part = struct();
part.g  = cell(1, H);
part.a  = repmat({core.Factor.empty(1,0)}, 1, H);
part.b0 = core.Factor.empty(1, 0);

assigned = false(1, numel(factors));

% --- The sampling factors first, because they are named -------------------
for r = 1:H
    hit = find([factors.Name] == gNames(r), 1);
    if isempty(hit)
        error('methods:smoothed:missingSamplingFactor', ...
            'The path names %s as g_%d but it is not among the removed factors.', ...
            gNames(r), r - 1);
    end
    if assigned(hit)
        error('methods:smoothed:samplingFactorReused', ...
            'Factor %s is the sampling factor of two different levels.', ...
            gNames(r));
    end
    part.g{r} = factors(hit);
    assigned(hit) = true;
end

% --- Everything else, by the deepest path level it touches ----------------
for i = 1:numel(factors)
    if assigned(i)
        continue
    end
    scope = factors(i).Scope;

    % Every path level this factor touches, not only the deepest, because the
    % SPAN is what decides whether any step can see it whole.
    levels = find(ismember(pathVars, scope)) - 1;

    if isempty(levels)
        error('methods:smoothed:factorOffPath', ...
            ['Factor %s touches no path variable, so it was not removed by ' ...
             'this path and does not belong to it.'], factors(i).Name);
    end

    depth = max(levels);

    if depth - min(levels) > 1
        % See the header: the tower is a chain, so no step has three levels in
        % scope at once.
        error('methods:smoothed:factorSpansTooManyLevels', ...
            ['Factor %s touches path levels %s, which span more than two. ' ...
             'The recursion of Eqs. (36)-(41) is a chain -- each step sees ' ...
             'one row level and one column level -- so no step can evaluate ' ...
             'it, and evaluating it at two of the three would silently drop ' ...
             'the rest of its scope.'], ...
            factors(i).Name, strjoin(string(levels), ", "));
    end

    if depth == 0
        % b_0(xi_0, s): everything whose deepest level is the first one, which
        % is what Eq. (41) multiplies outside the recursion.
        %
        % NOT "and it also touches the separator", which is what this said
        % first and which sent the unary prior f(x1) to a{1} instead. There is
        % no slot in a that can hold it: a_r is typed a_r(xi_{r+1}, s) by
        % Eq. (39), so slot a{1} = a_0 is a function of xi_1 and never of xi_0.
        % A factor over xi_0 alone is a b_0 that happens not to vary in s,
        % which Eq. (41) multiplies in per sample exactly as it should.
        part.b0(end+1) = factors(i); %#ok<AGROW>
    else
        % Slot = deepest level, consumed at step depth-1, where that level is
        % the COLUMN variable and depth-1 the row.
        part.a{depth}(end+1) = factors(i); %#ok<AGROW>
    end
    assigned(i) = true;
end

% --- The invariant --------------------------------------------------------
% Not a defensive check that should never fire: it is the property the
% recursion's correctness rests on, and the one that silently breaks when a
% path grows a level or a case grows a factor.
if ~all(assigned)
    missing = [factors(~assigned).Name];
    error('methods:smoothed:factorUnassigned', ...
        ['%d removed factor(s) were assigned to no role: %s. Every removed ' ...
         'factor must appear exactly once across g, a and b_0, or the ' ...
         'estimator silently drops evidence.'], ...
        nnz(~assigned), strjoin(missing, ", "));
end

part.counts = struct( ...
    'total',     numel(factors), ...
    'sampling',  H, ...
    'front',     numel(part.b0), ...
    'fusion',    sum(cellfun(@numel, part.a)));

total = part.counts.sampling + part.counts.front + part.counts.fusion;
if total ~= numel(factors)
    error('methods:smoothed:factorCountMismatch', ...
        'Roles account for %d factors but %d were removed.', ...
        total, numel(factors));
end
end
