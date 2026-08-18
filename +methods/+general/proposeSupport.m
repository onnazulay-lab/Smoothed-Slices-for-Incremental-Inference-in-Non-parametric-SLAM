function [S, logQ, info] = proposeSupport(separator, dims, omegaName, pOmega, pool, removed, domains, book, nS, config)
%PROPOSESUPPORT Draw the finite separator support and its proposal density.
%
%   Inputs
%     SEPARATOR   the separator variables
%     DIMS        their dimensions
%     OMEGANAME   the variable being eliminated
%     POMEGA      its proposal
%     POOL        L conditioning draws of omega
%     REMOVED     the factors leaving with omega
%     DOMAINS     each separator variable's domain box
%     BOOK        the proposal book, carrying earlier supports
%     NS          how many support points
%     CONFIG      the method config
%
%   Outputs
%     S     the support, NS-by-sum(DIMS)
%     LOGQ  the log proposal density at each point
%     INFO  which branch of variableProposal each variable used, the mixture
%           size and the conditioning pool size
%
%   Utility
%     Draw the finite separator support together with a density that can be
%     divided by, so the importance weights and the ESS mean something.
%
%   THE MIXTURE, AND WHY IT IS NEEDED. Each separator variable is proposed
%   conditionally on a draw of the variable being eliminated, because that is
%   where the factors put it: a range factor places the landmark on its
%   annulus around the pose. Drawing s_i from its own private omega' would
%   leave the marginal density of s_i an integral over omega' that cannot be
%   evaluated, and an importance weight with an unevaluable denominator is
%   not an importance weight at all.
%
%   So a POOL of L conditioning values is drawn once and the proposal is the
%   explicit finite mixture
%
%       q(s) = (1/L) sum_m prod_v q_v(s_v | omega'_m)
%
%   Each support point picks one component to be drawn from, but its density
%   is evaluated against every component. That costs NS-by-L density
%   evaluations per separator variable and makes q a real density, which is
%   the only thing that makes the weights and the ESS mean anything.
%
%   INFO.kinds records which branch of variableProposal each variable used,
%   so a support that came out defensive or uniform is visible in the
%   diagnostics rather than inferred from a bad ESS.

arguments
    separator (1,:) string
    dims (1,:) double
    omegaName (1,1) string
    pOmega (1,1) struct
    pool double
    removed (1,:) core.Factor
    domains (1,:) cell
    book (1,1) struct
    nS (1,1) double {mustBeInteger, mustBePositive}
    config (1,1) struct
end

nV = numel(separator);
dTotal = sum(dims);

% --- Conditioning pool ----------------------------------------------------
% L components. More components make q smoother and the weights better
% behaved; the cost is the NS-by-L density evaluation below.
L = min(nS, config.supportMixtureSize);
poolSub = pool;
if size(pool, 1) > L
    poolSub = pool(randperm(size(pool, 1), L), :);
elseif size(pool, 1) < L && size(pool, 2) > 0
    poolSub = pool(randi(size(pool, 1), L, 1), :);
elseif size(pool, 2) == 0
    poolSub = zeros(L, 0);
end
omegaPool = pOmega.draw(poolSub);          % L x d_omega

% --- Per-variable proposals ----------------------------------------------
props = cell(1, nV);
kinds = strings(1, nV);
for i = 1:nV
    props{i} = methods.general.variableProposal(separator(i), dims(i), ...
        domains{i}, removed, omegaName, book, ...
        'Defensive', config.defensiveWeight, ...
        'Bandwidth', config.proposalBandwidth);
    kinds(i) = props{i}.kind;
end

% --- Draw ----------------------------------------------------------------
comp = randi(L, nS, 1);                    % which mixture component each point uses
omegaFor = omegaPool(comp, :);

S = zeros(nS, dTotal);
col = 0;
for i = 1:nV
    S(:, col + (1:dims(i))) = props{i}.draw(omegaFor);
    col = col + dims(i);
end

% --- Density against every component -------------------------------------
% logComp(i, m) = sum_v log q_v(S(i,:) | omegaPool(m,:))
%
% Only the "conditional" branch actually varies with the component, so the
% others are evaluated once and added to every column. Without that shortcut
% a Lemma 1 proposal, whose own density is already a mixture over the outer
% samples, would be evaluated L times over and dominate the runtime.
logComp = zeros(nS, L);
fixed = zeros(nS, 1);
varying = false(1, nV);
col = 0;
for i = 1:nV
    pts = S(:, col + (1:dims(i)));
    if props{i}.dependsOnCondition
        varying(i) = true;
    else
        fixed = fixed + reshape(props{i}.logpdf(pts, omegaPool(1,:)), [], 1);
    end
    col = col + dims(i);
end

if ~any(varying)
    logComp = repmat(fixed, 1, L);
else
    for m = 1:L
        om = repmat(omegaPool(m,:), nS, 1);
        acc = fixed;
        col = 0;
        for i = 1:nV
            if varying(i)
                acc = acc + reshape(props{i}.logpdf( ...
                    S(:, col + (1:dims(i))), om), [], 1);
            end
            col = col + dims(i);
        end
        logComp(:, m) = acc;
    end
end

logQ = localLogSumExp(logComp, 2) - log(L);

info = struct('kinds', kinds, 'mixtureSize', L, ...
              'conditioningPoolSize', size(pool, 1));
end

% =========================================================================
function s = localLogSumExp(x, dim)
%LOCALLOGSUMEXP log(sum(exp(x))), shifted so it cannot overflow.
%   Inputs   X the log values, DIM which dimension to reduce
%   Outputs  S, the reduced log sum
%   Utility  a mixture density is a sum in linear space and the components
%           are logs; doing it directly underflows every time.
m = max(x, [], dim);
m(~isfinite(m)) = 0;
s = m + log(sum(exp(x - m), dim));
end
