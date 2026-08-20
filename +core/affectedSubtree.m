function [idx, info] = affectedSubtree(tree, variables)
%AFFECTEDSUBTREE The cliques a new factor changes, leaf-to-root.
%
%   Inputs
%     TREE       Bayes tree struct from core.bayesTree
%     VARIABLES  the variables the new factors touch
%
%   Outputs
%     IDX   clique indices to retrain, DEEPEST FIRST
%     INFO  struct with
%             touched     the cliques named directly
%             ancestors   those pulled in by the walk up
%             depth       depth of each returned clique
%             fraction    share of the tree needing retraining
%             numCliques  size of the tree
%
%   Utility
%     Draw the exact boundary between what an increment must retrain and what
%     it may reuse.
%
%   The fraction is the number worth reporting: it is what NF-iSAM's incremental
%   claim buys, and the direct counterpart of the StepCache hit rate on the
%   Slices side.
%
%   The order is leaf-to-root because that is the order Algorithm N3 step 3
%   trains in: a clique needs its children's separator densities first.
%
%   WHY ANCESTORS. NF-iSAM spec section 8: a clique conditional is
%   p(F_C | S_C, z_C), and the separator density p(S_C | z_C) is passed
%   upward as a factor. New information below a clique therefore changes what
%   that clique conditions on, all the way to the root, even where no new
%   variable appears. Descendants are untouched and their flows are reused
%   directly -- that is the whole saving, so the boundary has to be exact
%   rather than generous.
%
%   See also core.bayesTree, methods.nfisam.incrementalUpdate.

arguments
    tree (1,1) struct
    variables (1,:) string
end

cliques = tree.cliques;
if isempty(cliques)
    idx = zeros(1, 0);
    info = struct('touched', zeros(1,0), 'ancestors', zeros(1,0), ...
                  'depth', zeros(1,0), 'fraction', 0, 'numCliques', 0);
    return
end

% --- Cliques naming one of the variables as a frontal ---------------------
touched = zeros(1, 0);
for c = 1:numel(cliques)
    if any(ismember(variables, cliques(c).Frontal))
        touched(end+1) = c; %#ok<AGROW>
    end
end

% A variable that is only ever a separator still belongs to some clique's
% frontals elsewhere; if a name matches nothing at all, say so rather than
% silently retraining nothing.
unknown = variables(~ismember(variables, [cliques.Frontal]));
if ~isempty(unknown)
    error('core:affectedSubtree:unknownVariable', ...
        'No clique has %s as a frontal variable.', strjoin(unknown, ', '));
end

% --- Walk to the root -----------------------------------------------------
inSubtree = false(1, numel(cliques));
inSubtree(touched) = true;
for c = touched
    p = cliques(c).Parent;
    while p ~= 0 && ~inSubtree(p)
        inSubtree(p) = true;
        p = cliques(p).Parent;
    end
end

idx = find(inSubtree);

% --- Depth, so the caller can traverse leaf-to-root ------------------------
depth = zeros(1, numel(cliques));
for c = 1:numel(cliques)
    d = 0; p = cliques(c).Parent;
    while p ~= 0
        d = d + 1; p = cliques(p).Parent;
    end
    depth(c) = d;
end

[~, ord] = sort(depth(idx), 'descend');
idx = idx(ord);

info = struct( ...
    'touched',    touched, ...
    'ancestors',  setdiff(idx, touched), ...
    'depth',      depth(idx), ...
    'fraction',   numel(idx) / numel(cliques), ...
    'numCliques', numel(cliques));
end
