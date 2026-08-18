function ref = referenceFourDoorsGrid(caseData, opts)
%REFERENCEFOURDOORSGRID Exact marginals for the Four Doors chain.
%
%   Inputs
%     CASEDATA  the Four Doors case
%     GridSize  number of grid points                          default 4001
%
%   Outputs
%     REF  struct with
%            grid         1-by-G positions
%            marginals    G-by-K, one exact posterior marginal per pose
%            modeWeights  D-by-K, posterior mass nearest each door
%            logZ         log evidence
%
%   Utility
%     Compute every pose marginal by discrete forward-backward on a fine grid.
%     The graph is a chain, so this is exact up to the discretization, whose
%     error is bounded by the grid spacing against a smooth density.
%
%   This is the ground truth the multimodal case has been missing. The
%   two-pose range benchmark has two independent references and every
%   estimator is scored against them; the Four Doors case is the one that
%   actually exhibits mode collapse, and scoring mode weights without an
%   exact answer would mean comparing two approximations and calling the
%   difference a result.
%
%   Name-value options:
%     GridSize   number of grid points          default 4001
%     Counter    evaluate on this counter       default detached

arguments
    caseData (1,1) struct
    opts.GridSize (1,1) double {mustBeInteger, mustBePositive} = 4001
    opts.Counter = []
end

names = caseData.mission.poseNames;
K = numel(names);
dom = caseData.mission.domain;
x = linspace(dom(1), dom(2), opts.GridSize).';
dx = x(2) - x(1);
G = numel(x);

% The reference must not be charged to the cost counter: it is not part of
% any method, and letting it inflate the factor-evaluation totals would make
% every efficiency comparison meaningless.
factors = localUncounted(caseData.graph.Factors);

% --- Local evidence: every unary factor on each pose ----------------------
phi = ones(G, K);
for k = 1:K
    key = matlab.lang.makeValidName(names(k));
    for f = factors
        if isscalar(f.Scope) && f.Scope == names(k)
            phi(:,k) = phi(:,k) .* reshape(f.evaluate(struct(key, x)), [], 1);
        end
    end
end

% --- Pairwise potentials between consecutive poses ------------------------
psi = cell(1, K-1);
for k = 1:K-1
    ka = matlab.lang.makeValidName(names(k));
    kb = matlab.lang.makeValidName(names(k+1));
    M = ones(G, G);
    for f = factors
        if numel(f.Scope) == 2 && all(ismember([names(k) names(k+1)], f.Scope))
            M = M .* core.evalGrid(f, names(k), x, names(k+1), x);
        end
    end
    psi{k} = M;
end

% --- Forward and backward messages, rescaled at every step ---------------
% Rescaling is not cosmetic: the unnormalized products underflow to zero
% within a handful of steps at this grid size, and the log of the scales is
% exactly the log evidence, so nothing is lost by taking them out.
alpha = zeros(G, K);
logScaleA = zeros(1, K);
alpha(:,1) = phi(:,1);
[alpha(:,1), logScaleA(1)] = localRescale(alpha(:,1));
for k = 2:K
    alpha(:,k) = phi(:,k) .* (psi{k-1}.' * alpha(:,k-1) * dx);
    [alpha(:,k), logScaleA(k)] = localRescale(alpha(:,k));
end

beta = zeros(G, K);
beta(:,K) = 1;
for k = K-1:-1:1
    beta(:,k) = psi{k} * (phi(:,k+1) .* beta(:,k+1)) * dx;
    beta(:,k) = localRescale(beta(:,k));
end

marg = alpha .* beta;
for k = 1:K
    marg(:,k) = marg(:,k) / (sum(marg(:,k)) * dx);
end

% --- Mode weights: posterior mass nearest each door -----------------------
doors = caseData.doors;
[~, nearest] = min(abs(x - doors), [], 2);
modeW = zeros(numel(doors), K);
for d = 1:numel(doors)
    modeW(d,:) = sum(marg(nearest == d, :), 1) * dx;
end

ref = struct();
ref.grid = x.';
ref.marginals = marg;
ref.modeWeights = modeW;
ref.doors = doors;
ref.poseNames = names;
ref.logZ = sum(logScaleA);
ref.gridSize = opts.GridSize;
ref.gridSpacing = dx;

% A mode that the grid resolves with only a handful of points is a mode the
% reference itself is unsure about, so say so rather than let it pass.
obsSigma = caseData.settings.obsSigma;
ref.pointsPerMode = obsSigma / dx;
if ref.pointsPerMode < 8
    warning('datasets:referenceFourDoorsGrid:coarseGrid', ...
        ['Only %.1f grid points per observation sigma. The reference cannot ' ...
         'resolve the modes it is meant to certify; raise GridSize.'], ...
        ref.pointsPerMode);
end
end

% =========================================================================
function [v, logs] = localRescale(v)
%LOCALRESCALE Scale a message to unit maximum, returning the log scale removed.
%   Inputs   V, a nonnegative message
%   Outputs  V rescaled, and LOGS the log of the factor taken out
%   Utility  keep a long chain of message products in range, and carry the
%           removed scale so the evidence stays exact.
s = max(v);
if ~(s > 0) || ~isfinite(s)
    logs = 0;
    return
end
v = v / s;
logs = log(s);
end

% =========================================================================
function fs = localUncounted(factors)
%LOCALUNCOUNTED Copies of the factors with the evaluation counter detached.
%   Inputs   FACTORS, a core.Factor array
%   Outputs  FS, the same factors with Counter emptied
%   Utility  keep the reference's own evaluations out of the shared cost tally.
fs = factors;
for i = 1:numel(fs)
    fs(i).Counter = [];
end
end
