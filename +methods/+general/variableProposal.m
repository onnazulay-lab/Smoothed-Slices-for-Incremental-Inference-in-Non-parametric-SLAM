function p = variableProposal(varName, dim, domain, removed, condName, book, opts)
%VARIABLEPROPOSAL A proposal density for one separator variable.
%
%   Inputs
%     VARNAME    the separator variable to propose
%     DIM        its dimension
%     DOMAIN     its domain box
%     REMOVED    the factors leaving with the eliminated variable
%     CONDNAME   the variable to condition on, or "" for none
%     BOOK       the proposal book, carrying earlier supports
%     Defensive  uniform mixing weight for the defensive branch  default 0.1
%     Bandwidth  kernel width as a fraction of the support spread
%                                                               default 0.35
%
%   Outputs
%     P.draw(omegaPts)          n-by-DIM draws, one per row of OMEGAPTS
%     P.logpdf(pts, omegaPts)   n-by-1 log density of those draws
%     P.kind                    which of the five branches below was taken
%     P.factorName              the factor used, where one was
%     P.dependsOnCondition      whether the density varies with OMEGAPTS,
%                               which lets the caller evaluate it once
%                               instead of once per mixture component
%
%   Utility
%     Return a PROPER density with respect to Lebesgue measure, whichever
%     branch is taken. That is the whole point of this file: the separator
%     support of the general engine is an importance sample, so the weights
%     f(s)/q(s) are only meaningful if q is a real density.
%
%   Resampling an existing point cloud would be cheaper and would quietly
%   destroy the weights, because a discrete proposal has no density to divide
%   by.
%
%   Five branches, in order of preference:
%
%     "unary"       A removed factor is unary in VARNAME and can sample it.
%                   The prior on the first pose. Exact, and independent of
%                   anything else, so the conditioning argument is ignored.
%
%     "conditional" A removed factor connects VARNAME to CONDNAME and can
%                   sample it. This is the good case and the common one: a
%                   range factor puts the landmark on its annulus, odometry
%                   puts the next pose where it belongs.
%
%     "lemma1"      No surviving raw factor reaches VARNAME, but a GENERATED
%                   factor among the removed ones does: it still carries the
%                   raw factors it was built from, and one of those connects
%                   VARNAME to the variable that generated it. Drawing that
%                   variable from the generated factor's own weighted samples
%                   and then VARNAME from the raw factor is exactly the
%                   structural route of Lemma 1.
%
%                   This branch is the difference between a working engine
%                   and a plausible one. Eliminating a pose consumes the
%                   odometry factor that would place its successor, so
%                   without it every proposal after the first degrades to a
%                   kernel over a marginal and the effective sample size
%                   collapses by an order of magnitude.
%
%     "defensive"   No such factor, but the variable already has a support
%                   from an earlier elimination. Propose from a Gaussian
%                   kernel around that support, mixed with a uniform over the
%                   domain so no region has zero proposal mass. This is the
%                   q_def of the Smoothed Slices spec section 17: a kernel
%                   used as a PROPOSAL, never as the representation of the
%                   factor.
%
%     "uniform"     Nothing is known yet. Uniform over the domain box.
%
%   See also methods.general.proposeSupport,
%   methods.general.forwardEliminationGeneral.

arguments
    varName (1,1) string
    dim (1,1) double {mustBeInteger, mustBePositive}
    domain (:,2) double
    removed (1,:) core.Factor
    condName (1,1) string
    book (1,1) struct
    opts.Defensive (1,1) double {mustBeInRange(opts.Defensive, 0, 1)} = 0.1
    opts.Bandwidth (1,1) double {mustBePositive} = 0.35
end

lo = domain(:,1).';
hi = domain(:,2).';
vol = prod(hi - lo);
key = matlab.lang.makeValidName(varName);
okey = matlab.lang.makeValidName(condName);

% --- 0. a unary factor on this variable ----------------------------------
for f = removed
    if isscalar(f.Scope) && f.Scope == varName && f.canSample(varName)
        p = struct();
        p.kind = "unary";
        p.factorName = f.Name;
        p.dependsOnCondition = false;
        p.draw = @(om) localSqueezeDraw(f.sample(varName, struct(), ...
                            size(om, 1)), dim);
        p.logpdf = @(pts, ~) log(max(f.evaluate(struct(key, pts)), realmin)) ...
                            - f.logNormalizer(varName, struct());
        return
    end
end

% --- 1. conditional on the conditioning variable -------------------------
for f = removed
    if strlength(condName) > 0 && f.involves(varName) ...
            && f.involves(condName) && f.canSample(varName)
        p = struct();
        p.kind = "conditional";
        p.factorName = f.Name;
        p.dependsOnCondition = true;
        p.draw = @(om) localSqueezeDraw(f.sample(varName, ...
                            localGiven(okey, om), 1), dim);
        p.logpdf = @(pts, om) log(max(f.evaluate( ...
                            localPair(okey, om, key, pts)), realmin)) ...
                            - reshape(f.logNormalizer(varName, ...
                            localGiven(okey, om)), [], 1);
        return
    end
end

% --- 2. Lemma 1: reach through a generated factor ------------------------
% Searched breadth-first to a bounded depth, because a generated factor is
% often built from other generated factors: after two eliminations the raw
% odometry that can place the next pose is two mixtures down, and a
% single-level search would give up and fall to the defensive kernel with no
% sign that a far better proposal was sitting one level below.
[gfac, af] = localFindLemma1(removed, varName, 6);
if ~isempty(gfac)
    ukey = matlab.lang.makeValidName(af.EliminatedVar);
    U = af.Samples;
    wU = af.SampleWeights;
    if isempty(wU), wU = ones(size(U, 1), 1); end
    wU = wU(:) / sum(wU);

    p = struct();
    p.kind = "lemma1";
    p.factorName = gfac.Name;
    % The density is a mixture over U alone, so it does not vary with the
    % conditioning argument and the caller can evaluate it once.
    p.dependsOnCondition = false;
    p.draw = @(om) localLemma1Draw(gfac, varName, ukey, U, wU, ...
                        size(om, 1), dim);
    p.logpdf = @(pts, ~) localLemma1LogPdf(gfac, varName, ukey, key, ...
                        U, wU, pts);
    return
end

% --- 3. defensive kernel around an existing support ----------------------
if isfield(book, key) && ~isempty(book.(key).points)
    pts0 = book.(key).points;
    w0   = book.(key).weights(:);
    w0   = w0 / sum(w0);

    spread = std(pts0, w0, 1);
    spread(spread <= 0 | ~isfinite(spread)) = mean(hi - lo) / 10;
    h = opts.Bandwidth * spread;

    p = struct();
    p.kind = "defensive";
    p.factorName = "";
    p.dependsOnCondition = false;
    p.draw = @(om) localDefensiveDraw(size(om, 1), pts0, w0, h, lo, hi, opts.Defensive);
    p.logpdf = @(pts, ~) localDefensiveLogPdf(pts, pts0, w0, h, vol, opts.Defensive);
    return
end

% --- 4. uniform over the domain box --------------------------------------
p = struct();
p.kind = "uniform";
p.factorName = "";
p.dependsOnCondition = false;
p.draw = @(om) lo + rand(size(om, 1), dim) .* (hi - lo);
p.logpdf = @(pts, ~) localUniformLogPdf(pts, lo, hi, vol);
end

% =========================================================================
function [gfac, af] = localFindLemma1(factors, varName, maxDepth)
%LOCALFINDLEMMA1 A generated factor whose raw factors still reach VARNAME.
%   Inputs   FACTORS the removed factors, VARNAME the variable to place,
%           MAXDEPTH how far to follow generated factors into each other
%   Outputs  GFAC the raw factor found, AF the generated factor carrying it
%   Utility  find the structural route of Lemma 1, which is what keeps a
%           proposal conditional after the odometry factor has been consumed.
%
%   factor whose samples condition it. Breadth-first over nested mixtures.
gfac = [];
af = [];

frontier = factors;
for depth = 1:maxDepth
    next = core.Factor.empty(1, 0);
    for f = frontier
        if f.Kind ~= "approximate" || ~isfield(f.Meta, 'approximateFactor')
            continue
        end
        cand = f.Meta.approximateFactor;
        if isempty(cand.Samples), continue, end

        for gf = cand.RemainingFactors
            if gf.involves(varName) && gf.involves(cand.EliminatedVar) ...
                    && gf.canSample(varName)
                gfac = gf;
                af = cand;
                return
            end
        end
        next = [next cand.RemainingFactors]; %#ok<AGROW>
    end
    if isempty(next), return, end
    frontier = next;
end
end

% =========================================================================
function s = localLemma1Draw(gfac, varName, ukey, U, wU, n, dim)
%LOCALLEMMA1DRAW Draw VARNAME through the generated factor's own samples.
%   Inputs   GFAC the raw factor, VARNAME, UKEY the generating variable's key,
%           U and WU its weighted samples, N how many draws, DIM its width
%   Outputs  S, N-by-DIM
%   Utility  draw the generating variable from the generated factor, then
%           VARNAME from the raw factor that connects them.
idx = localCategorical(wU, n);
given = struct();
given.(ukey) = U(idx, :);
s = localSqueezeDraw(gfac.sample(varName, given, 1), dim);
end

% =========================================================================
function lp = localLemma1LogPdf(gfac, varName, ukey, key, U, wU, pts)
%LOCALLEMMA1LOGPDF The density of that two-step draw, as a finite mixture.
%   Inputs   as localLemma1Draw, plus PTS the points to score
%   Outputs  LP, one log density per row
%   Utility  the draw is a mixture over the generating variable's samples, so
%           the density is that mixture written out -- not an approximation.
%
%   Evaluated against EVERY stored sample, not the one each draw happened to
%   use: the marginal density of the draw is the mixture, and weighting by
%   the component that produced it would be wrong by exactly the factor the
%   estimator is trying to correct for.
n = size(pts, 1);
m = size(U, 1);
lp = zeros(n, 1);

% Chunked over the query so the n-by-m expansion stays bounded.
chunk = max(1, floor(2e6 / m));
logw = log(max(wU(:).', realmin));

for a = 1:chunk:n
    b = min(a + chunk - 1, n);
    q = b - a + 1;

    given = struct();
    given.(ukey) = U(repmat(1:m, 1, q), :);
    pair = given;
    pair.(key) = pts(a - 1 + repelem(1:q, m), :);

    val = log(max(reshape(gfac.evaluate(pair), [], 1), realmin)) ...
        - reshape(gfac.logNormalizer(varName, given), [], 1);
    lp(a:b) = localLogSumExp(reshape(val, m, q).' + logw, 2);
end
end

% =========================================================================
function g = localGiven(okey, om)
%LOCALGIVEN A one-variable conditioning dictionary.
%   Inputs   OKEY the variable's valid name, OM its values
%   Outputs  G, the dictionary
%   Utility  factors take a struct, and building it inline four times would
%           be four chances to use the wrong key.
g = struct();
g.(okey) = om;
end

% =========================================================================
function a = localPair(okey, om, key, pts)
%LOCALPAIR A two-variable assignment dictionary.
%   Inputs   OKEY and OM, KEY and PTS
%   Outputs  A, the dictionary
%   Utility  the same, for evaluating a binary factor at both ends.
a = struct();
a.(okey) = om;
a.(key)  = pts;
end

% =========================================================================
function s = localSqueezeDraw(raw, dim)
%LOCALSQUEEZEDRAW A factor's draw reshaped to n-by-DIM.
%   Inputs   RAW what the factor returned, DIM the variable's width
%   Outputs  S, n-by-DIM
%   Utility  a scalar variable's draw comes back in more than one shape
%           depending on the factor, and the caller needs one.
%
%   Factor.sample returns n-by-m-by-d and MATLAB drops the trailing singleton
%   when d is 1, so the two cases have to be separated explicitly rather than
%   squeezed blindly: squeeze would turn n-by-1-by-2 into 2 columns for one
%   row and into a column vector for another.
if dim == 1
    s = reshape(raw, [], 1);
else
    s = reshape(raw, [], dim);
end
end

% =========================================================================
function s = localDefensiveDraw(n, pts0, w0, h, lo, hi, beta)
%LOCALDEFENSIVEDRAW A kernel around an earlier support, mixed with a uniform.
%   Inputs   N how many draws, PTS0 and W0 the earlier weighted support, H the
%           bandwidth, LO and HI the domain box, BETA the uniform weight
%   Outputs  S, N-by-dim
%   Utility  the q_def of Smoothed Slices spec section 17. The uniform part is
%           what stops any region having zero proposal mass, which would make
%           an importance weight there infinite.
dim = size(pts0, 2);
s = zeros(n, dim);

useUniform = rand(n, 1) < beta;
nu = nnz(useUniform);
if nu > 0
    s(useUniform, :) = lo + rand(nu, dim) .* (hi - lo);
end

nk = n - nu;
if nk > 0
    idx = localCategorical(w0, nk);
    s(~useUniform, :) = pts0(idx, :) + randn(nk, dim) .* h;
end
end

% =========================================================================
function lp = localDefensiveLogPdf(pts, pts0, w0, h, vol, beta)
%LOCALDEFENSIVELOGPDF The density of that defensive mixture.
%   Inputs   PTS the points to score, then the same mixture parameters
%   Outputs  LP, one log density per row
%   Utility  the kernel is a PROPOSAL and never the representation of the
%           factor, which is why its density is written out rather than
%           treated as an estimate.
n = size(pts, 1);
logK = zeros(n, 1);

% Chunked so a large support against a large query does not allocate an
% n-by-|P| distance matrix in one go.
chunk = max(1, floor(2e6 / max(1, size(pts0, 1))));
logNorm = -sum(log(h)) - 0.5 * numel(h) * log(2*pi);
for a = 1:chunk:n
    b = min(a + chunk - 1, n);
    d = (reshape(pts(a:b,:), [], 1, size(pts, 2)) ...
         - reshape(pts0, 1, [], size(pts0, 2))) ./ reshape(h, 1, 1, []);
    q = logNorm - 0.5 * sum(d.^2, 3);          % (b-a+1) x |P|
    logK(a:b) = localLogSumExp(q + log(w0(:).'), 2);
end

lp = localLogSumExp([log(beta) - log(vol) + zeros(n,1), ...
                     log1p(-beta) + logK], 2);
end

% =========================================================================
function lp = localUniformLogPdf(pts, lo, hi, vol)
%LOCALUNIFORMLOGPDF Uniform density on the domain box, -Inf outside it.
%   Inputs   PTS the points, LO and HI the box, VOL its volume
%   Outputs  LP, one log density per row
%   Utility  the last-resort branch, and the mixing component of the
%           defensive one.
inside = all(pts >= lo & pts <= hi, 2);
lp = -log(vol) * ones(size(pts, 1), 1);
lp(~inside) = -Inf;
end

% =========================================================================
function idx = localCategorical(w, n)
%LOCALCATEGORICAL N draws from a categorical distribution.
%   Inputs   W the weights, N how many draws
%   Outputs  IDX, the drawn indices
%   Utility  choose which mixture component each draw comes from.
idx = core.categoricalSample(w(:), n);
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
