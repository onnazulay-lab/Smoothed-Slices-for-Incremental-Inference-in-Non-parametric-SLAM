function [D, info] = sampleJointPosterior(state, n, opts)
%SAMPLEJOINTPOSTERIOR Draw joint posterior samples root to leaf, spec item 7.
%
%   Inputs
%     STATE  what methods.nfisam.incrementalUpdate returns: a Bayes tree and
%            one trained methods.nfisam.ConditionalSampler per clique
%     N      how many joint draws
%     Seed   the random seed                                    default []
%
%   Outputs
%     D      one N-by-d block per variable
%     INFO   the traversal order, the layout, a per-clique record and the
%            runtime
%
%   Utility
%     Draw N joint samples from
%
%       p(Theta | z) = prod_C p(F_C | S_C, z_C)                     (Eq. N1)
%
%   THE PRODUCT IS ALREADY THE POSTERIOR, so this pass does no inference. Eq.
%   N1 is a factorization into conditionals, not into potentials that still
%   need normalizing, and each clique's flow is exactly one of its factors.
%   Sampling a factorized density is ancestral sampling and nothing else: draw
%   the root's frontals, hand them down as the separator of each child, draw
%   the child's frontals conditioned on the values the parent actually drew.
%   There is no weighting here and no acceptance step, which is the whole
%   contrast with the backward pass of the Slices side -- there a marginal is
%   rebuilt on a grid at every variable, here the flow already IS the
%   conditional and is asked for a draw.
%
%   WHY ROOT TO LEAF, when Algorithm N3 trains leaf to root. The two passes
%   move opposite ways because they carry opposite things. Training goes
%   upward because a clique's flow must be fitted to what its children have
%   already learned, which reaches it as separator draws. Sampling goes
%   downward because a clique's frontals are conditioned on its separator,
%   and the separator's values are decided by the parent. Running either one
%   the other way round would ask for a quantity that does not exist yet.
%
%   ROW n IS ONE SAMPLE OF EVERYTHING, and that is the property worth
%   protecting. Every clique is handed the SAME row index its parent drew, so
%   row n of x1 and row n of l5 come from the same trajectory of the whole
%   system even though no flow ever saw both variables. Drawing each clique's
%   frontals from a fresh N-row separator sample would give correct marginals
%   and a joint that is a product of them -- an error invisible in every
%   per-variable plot and fatal to anything that reads two variables at once.
%
%   THE SEPARATOR MUST ALREADY BE DRAWN when a clique's turn comes, which is
%   the running-intersection property of a Bayes tree: S_C lies inside the
%   parent clique, so a parents-first traversal has it in hand. That is a
%   property of CORE.BAYESTREE rather than an assumption this function may
%   make, so it is checked and named rather than trusted -- a violation means
%   the tree is not a tree, and a silent failure here would be a posterior
%   with an unconditioned block in it.
%
%   A FOREST IS ALLOWED. CORE.BAYESTREE returns TREE.ROOTS, plural: a graph
%   with disconnected components has one root per component, and their
%   posteriors are genuinely independent. The traversal visits every clique in
%   order of depth, so each root starts its own descent and no component waits
%   on another.
%
%   Options
%     Order     "depth" (default) visits cliques by increasing depth. Any
%               parents-first order is valid; this one is stated so INFO is
%               reproducible.
%     Seed      seeds the global stream, so a posterior can be redrawn
%               exactly without retraining a single flow.

arguments
    state (1,1) struct
    n (1,1) double {mustBeInteger, mustBePositive}
    opts.Seed = []
end

tStart = tic;
if ~isempty(opts.Seed)
    rng(opts.Seed);
end

localRequireFields(state, ["tree" "samplers"]);
tree     = state.tree;
samplers = state.samplers;
cliques  = tree.cliques;
numC     = numel(cliques);

D = struct();
info = struct('numSamples', n, 'numCliques', numC, ...
              'order', zeros(1,0), 'names', string.empty(1,0), ...
              'widths', zeros(1,0), 'perClique', localRecord(), ...
              'numRoots', 0, 'runtime', 0);
info.perClique(:) = [];

if numC == 0
    info.runtime = toc(tStart);
    return
end

if numel(samplers) ~= numC
    error('methods:nfisam:sampleJointPosterior:samplerCount', ...
        ['The tree has %d clique(s) but the state holds %d sampler(s). ' ...
         'Every clique is one factor of Eq. N1; a missing one is a missing ' ...
         'factor, not a smaller posterior.'], numC, numel(samplers));
end

keys = methods.nfisam.cliqueKeys(tree);
rootToLeaf = flip(keys.leafToRoot);      % leafToRoot sorts depth descending

names  = string.empty(1, 0);
widths = zeros(1, 0);
recs   = cell(1, numC);

for c = rootToLeaf
    tClique = tic;
    cl = cliques(c);
    s  = samplers{c};

    if ~isa(s, 'methods.nfisam.ConditionalSampler')
        error('methods:nfisam:sampleJointPosterior:notASampler', ...
            ['Clique %d (%s) holds a %s rather than a trained sampler. ' ...
             'Run METHODS.NFISAM.INCREMENTALUPDATE before sampling.'], ...
            c, cl.label(), class(s));
    end

    % The sampler was trained for THIS clique, so its layout and the clique's
    % must agree. They can only disagree if a state was assembled by hand or
    % a cache was keyed wrongly, and both would produce a plausible posterior
    % over the wrong variables.
    if ~isequal(s.Frontal, cl.Frontal) || ~isequal(s.Separator, cl.Separator)
        error('methods:nfisam:sampleJointPosterior:layoutMismatch', ...
            ['Clique %d is %s but its sampler is over F = {%s}, S = {%s}. ' ...
             'The flow and the clique disagree about which variables they ' ...
             'are.'], c, cl.label(), strjoin(s.Frontal, ", "), ...
            strjoin(s.Separator, ", "));
    end

    if isempty(cl.Separator)
        % A root of the forest: nothing to condition on, so this is the one
        % clique of its component whose draw starts from the flow alone.
        Dc = s.sampleClique(n);
        isRoot = true;
    else
        missing = cl.Separator(~ismember(cl.Separator, names));
        if ~isempty(missing)
            error('methods:nfisam:sampleJointPosterior:separatorNotDrawn', ...
                ['Clique %d (%s) needs %s, which no earlier clique drew. ' ...
                 'A Bayes tree separator lies inside the parent clique, so ' ...
                 'this means the tree violates the running-intersection ' ...
                 'property rather than that the traversal is out of order.'], ...
                c, cl.label(), strjoin(missing, ", "));
        end
        % The parent's own draw, row for row. PACKSAMPLES puts the blocks in
        % the clique's separator order, which is the order the flow's columns
        % were trained in.
        sv = methods.nfisam.packSamples(D, cl.Separator);
        F  = s.sampleFrontal(sv);
        Dc = methods.nfisam.unpackSamples(F, cl.Frontal, s.frontalWidths());
        isRoot = false;
    end

    for v = cl.Frontal
        key = matlab.lang.makeValidName(v);
        if isfield(D, key)
            error('methods:nfisam:sampleJointPosterior:duplicateFrontal', ...
                ['%s is frontal in clique %d and in an earlier one. The ' ...
                 'frontals of a Bayes tree partition the variables, so a ' ...
                 'repeat means two flows both claim to own it.'], v, c);
        end
        D.(key) = Dc.(key);
    end
    names  = [names cl.Frontal];            %#ok<AGROW>
    widths = [widths s.frontalWidths()];    %#ok<AGROW>

    recs{c} = localRecord(c, cl, s, isRoot, toc(tClique));
end

info.order     = rootToLeaf;
info.names     = names;
info.widths    = widths;
info.numRoots  = nnz([cliques.Parent] == 0);
info.perClique = [recs{:}];
info.runtime   = toc(tStart);
end

% =========================================================================
function localRequireFields(state, fields)
%LOCALREQUIREFIELDS Refuse a state that is not what incrementalUpdate returns.
%   Inputs   STATE the struct, FIELDS what it must carry
%   Outputs  none; throws
%   Utility  name the missing field rather than failing several lines later
%           on something that looks unrelated.
missing = fields(~isfield(state, fields));
if ~isempty(missing)
    error('methods:nfisam:sampleJointPosterior:notAState', ...
        ['The state is missing %s. Pass what ' ...
         'METHODS.NFISAM.INCREMENTALUPDATE returned.'], strjoin(missing, ", "));
end
end

% =========================================================================
function r = localRecord(c, cl, s, isRoot, runtime)
%LOCALRECORD One clique's line of the traversal record.
%   Inputs   C the clique index, CL the clique, S its separator draws, ISROOT
%           whether it started the pass, RUNTIME how long it took. Called with
%           no arguments to get the empty struct with the right fields.
%   Outputs  R, one record
%   Utility  build the record in one place so the empty and the filled forms
%           cannot have different fields.
if nargin == 0
    r = localRecord(0, core.BayesTreeClique(), [], false, 0);
    return
end

r = struct();
r.index         = c;
r.label         = cl.label();
r.frontal       = cl.Frontal;
r.separator     = cl.Separator;
r.isRoot        = isRoot;
r.runtime       = runtime;
r.frontalWidth  = 0;
r.separatorWidth = 0;
if isa(s, 'methods.nfisam.ConditionalSampler')
    r.frontalWidth   = s.frontalWidth();
    r.separatorWidth = s.separatorWidth();
end
end
