function keys = cliqueKeys(tree)
%CLIQUEKEYS What makes a clique's trained sampler reusable, as a string.
%
%   Inputs
%     TREE        a core.BayesTree
%
%   Outputs
%     KEYS.self       (1,:) string   F_C, S_C and z_C of each clique
%     KEYS.subtree    (1,:) string   .self plus the children's subtree keys
%     KEYS.depth      (1,:) double   distance to the root
%     KEYS.leafToRoot (1,:) double   clique indices, deepest first
%
%   Utility
%     Give each clique a cache key that is true exactly when its trained
%     sampler is still valid.
%
%   THE SUBTREE KEY IS THE CACHE KEY, and the reason is the whole correctness
%   argument of Algorithm N3's reuse. A clique's sampler is trained on samples
%   from its own factors AND on separator draws handed up by its children, so
%   it stays valid exactly when nothing below it moved. The subtree key is that
%   sentence written down: it changes if the clique's own frontals, separator
%   or factors change, and it changes if any of that changes anywhere beneath.
%
%   WHY NOT THE CLIQUE INDEX. Cliques are numbered by CORE.BAYESTREE from the
%   elimination order, so a new factor that creates or merges a clique
%   renumbers its neighbours. Caching by index would then hand a clique the
%   sampler of a different clique -- silently, since the shapes often still
%   fit.
%
%   WHY NOT CORE.AFFECTEDSUBTREE ALONE. That function answers spec section 7's
%   step 2, which cliques the new factors change, and it is the right answer to
%   that question. It is not sufficient here, because this implementation
%   rebuilds the tree after every update rather than surgically re-eliminating
%   it, and a rebuild can reshape a clique that lies BELOW the changed subtree.
%   Adding a loop closure f(x3,x5) to the chain in tNFiSAMIncremental moves a
%   clique from F={x2,x3}, S={x4} to F={x2}, S={x3,x4} while the changed
%   subtree is the root alone: the reshaped clique is the root's child, so
%   step 2 does not name it, and its cached sampler no longer even has the
%   right number of dimensions. Comparing keys catches that; comparing
%   positions does not.
%
%   The keys nest rather than hash, so a subtree key grows with the size of
%   the subtree. That is a few kilobytes for the trees this project builds, and
%   it buys a key that can be read in a debugger and diffed against the one it
%   failed to match.

arguments
    tree (1,1) struct
end

cliques = tree.cliques;
n = numel(cliques);

keys = struct('self', string.empty(1,0), 'subtree', string.empty(1,0), ...
              'depth', zeros(1,0), 'leafToRoot', zeros(1,0));
if n == 0
    return
end

% --- Depth, so children are always keyed before their parents -------------
depth = zeros(1, n);
for c = 1:n
    d = 0; p = cliques(c).Parent;
    while p ~= 0
        d = d + 1; p = cliques(p).Parent;
    end
    depth(c) = d;
end
[~, leafToRoot] = sort(depth, 'descend');

% --- Self keys ------------------------------------------------------------
self = strings(1, n);
for c = 1:n
    % Factors are sorted because the clique is the same clique whichever order
    % elimination happened to consume them in; frontals and separator are not,
    % because the frontal order IS the flow's column order.
    self(c) = strjoin(cliques(c).Frontal, ",") + "|" + ...
              strjoin(cliques(c).Separator, ",") + "|" + ...
              strjoin(sort(cliques(c).Factors), ",");
end

% --- Subtree keys, children first ----------------------------------------
subtree = strings(1, n);
for c = leafToRoot
    kids = cliques(c).Children;
    if isempty(kids)
        subtree(c) = self(c);
    else
        subtree(c) = self(c) + "<" + strjoin(sort(subtree(kids)), ";") + ">";
    end
end

keys.self       = self;
keys.subtree    = subtree;
keys.depth      = depth;
keys.leafToRoot = leafToRoot;
end
