function out = surfaceComplexity(R, opts)
%SURFACECOMPLEXITY Is the surface R_r actually compact? Research sheet E2.
%
%   Inputs
%     R            one conditional smoothing surface
%     RankTol      relative singular-value tolerance         default 1e-6
%     NnzTol       relative entry threshold                  default 1e-6
%     CompactFrac  energy rank at or below this fraction of min(size) counts
%                  as compact                                default 0.10
%     EnergyLevel  the level CompactFrac is judged at        default 0.99
%
%   Outputs
%     OUT.size            [rows cols] of the surface
%     OUT.rank            rank_eps, singular values above RankTol * sigma_1
%     OUT.rankTol         the relative tolerance that produced it
%     OUT.rankFraction    rank / min(size), so 1.0 means full rank
%     OUT.rankCurve       struct(tol, rank): rank against twelve decades
%     OUT.singularValues  the spectrum, normalized so sigma_1 = 1
%     OUT.sigmaMax        sigma_1 itself, since the spectrum above is unitless
%     OUT.spectralGap     sigma_2 / sigma_1, the sharpest one-number decay
%     OUT.energyRank      struct(level, k): singular values needed for
%                         90/99/99.9% of the squared energy
%     OUT.effectiveRank   exp(entropy of the normalized squared spectrum), a
%                         tolerance-free companion to rank_eps
%     OUT.nnz             nnz_eps, entries with |R| above NnzTol * max|R|
%     OUT.nnzTol          the relative threshold that produced it
%     OUT.sparsity        1 - nnz / numel, so 0 means nothing is near zero
%     OUT.verdict         "compact" | "not compact" | "separable" |
%                         "degenerate"
%     OUT.reason          one sentence naming the numbers behind the verdict
%     OUT.compact         logical, true only for "compact"
%
%   Utility
%     Measure the complexity of one conditional smoothing surface: numerical
%     rank under a tolerance, entries above a threshold, the singular
%     spectrum, and how much of the surface's energy the leading singular
%     directions hold.
%
%   THIS IS THE HYPOTHESIS, NOT A DECORATION. The research instruction sheet
%   states the idea as a conditional: "IF the conditional-smoothing surfaces
%   R_r are lower-rank, sparse, smooth, or well-approximated by small active
%   successor sets, THEN the working cost can move from nested-tree-like
%   growth toward sparse-surface recursion cost." Everything to the left of
%   that "then" is measured here, and the sheet's own failure signal for it is
%   blunt: "full rank / no sparsity". So this function has to be able to
%   return that.
%
%   THREE WAYS TO BE WRONG ABOUT THIS NUMBER, all of which the fields below
%   are shaped to prevent.
%
%   1. rank_eps HAS NO MEANING IN ABSOLUTE UNITS. A surface is a product of
%      unnormalized factor values; multiplying every entry by 1e6 multiplies
%      every singular value by 1e6, and a rank taken against a fixed absolute
%      tolerance would change with nothing but the scaling. The tolerance is
%      therefore RELATIVE to sigma_1, and RANKCURVE reports the rank across
%      twelve decades of tolerance so that a reader can see whether the number
%      is a cliff -- a genuine gap in the spectrum -- or a slope, which means
%      the rank is an artifact of where the threshold was put.
%
%   2. SPARSE AND LOW-RANK ARE DIFFERENT CLAIMS, and the cost model cares
%      about a third thing again. nnz_eps counts entries of R_r above a
%      threshold. It is NOT |N_r|: the active successor count is IMPOSED on
%      the transition matrix P_r by the active-set rule, not discovered in the
%      surface. A dense surface with a fast-decaying spectrum is compressible
%      and not sparse; a sparse surface can be full rank. Both are reported
%      because the sheet asks for both and they can disagree.
%
%   3. RANK 1 IS NOT GOOD NEWS. It is the best possible reading of this
%      diagnostic and it usually means the surface SEPARABLE -- R(a,rho) =
%      u(a) v(rho), so every path point sees the same shape over the
%      separator, and the conditional smoothing had nothing to condition on.
%      A compactness result that cannot tell that apart from a real one is
%      measuring the fusion factors rather than the method, so it is called
%      out in VERDICT as "separable" rather than folded into "compact".
%
%   COMPACTFRAC IS A CONVENTION, NOT A RESULT. Ten percent is a line this
%   file draws so that VERDICT can be a word; nothing in the sheet or the
%   specification sets it. RANKFRACTION and ENERGYRANK are the numbers to
%   quote, and the verdict is for a glance.
%
%   See also methods.smoothed.surfaceChecks, research.surfaceComplexityStudy,
%   methods.smoothed.evaluateSurfaceRecursion.

arguments
    R double
    opts.RankTol (1,1) double {mustBePositive} = 1e-6
    opts.NnzTol (1,1) double {mustBePositive} = 1e-6
    opts.CompactFrac (1,1) double {mustBePositive} = 0.10
    opts.EnergyLevel (1,1) double {mustBePositive} = 0.99
end

R = full(R);
[m, n] = size(R);
minDim = max(1, min(m, n));

out = struct();
out.size          = [m n];
out.rankTol       = opts.RankTol;
out.nnzTol        = opts.NnzTol;
out.compactFrac   = opts.CompactFrac;
out.energyLevel   = opts.EnergyLevel;

% A surface with a non-finite entry has already failed surfaceChecks; svd
% would either error or return garbage, and returning a confident rank for it
% would hide the earlier failure behind a later number.
if isempty(R) || ~all(isfinite(R(:)))
    out = localDegenerate(out, ...
        "surface is empty or contains non-finite entries");
    return
end

s = svd(R);
s = s(:);
sigmaMax = s(1);

if sigmaMax <= 0
    out = localDegenerate(out, "surface is identically zero");
    return
end

sn = s / sigmaMax;

% --- Rank, and the curve that says whether to believe it ------------------
out.singularValues = sn;
out.sigmaMax       = sigmaMax;
out.rank           = sum(sn > opts.RankTol);
out.rankFraction   = out.rank / minDim;
if numel(sn) >= 2
    out.spectralGap = sn(2);
else
    % One singular value: the ratio has no second term. Zero is the right
    % reading -- there is no second direction to decay to -- and it keeps
    % "small gap means fast decay" true for callers that sort on it.
    out.spectralGap = 0;
end

tols = 10 .^ (-1:-1:-12);
out.rankCurve = struct( ...
    'tol',  tols, ...
    'rank', arrayfun(@(t) sum(sn > t), tols));

% --- Energy, and a rank that does not need a threshold at all -------------
e2  = sn .^ 2;
cum = cumsum(e2) / sum(e2);
levels = [0.90 0.99 0.999];
if ~ismember(opts.EnergyLevel, levels)
    levels = sort([levels opts.EnergyLevel]);
end
out.energyRank = struct( ...
    'level', levels, ...
    'k',     arrayfun(@(L) find(cum >= L - 1e-12, 1, 'first'), levels));

% Pulled out here rather than beside the verdict that uses it, so that this
% struct's fields land in the same ORDER as the degenerate one below.
% MATLAB concatenates structs by field order, and a study that collects one
% of these per cell would otherwise fail on the first zero surface.
kAt = out.energyRank.k(out.energyRank.level == opts.EnergyLevel);
out.energyRankAtLevel = kAt;

p = e2 / sum(e2);
p = p(p > 0);
out.effectiveRank = exp(-sum(p .* log(p)));

% --- Sparsity, which is a different claim from the one above --------------
a = abs(R(:));
out.nnz      = sum(a > opts.NnzTol * max(a));
out.sparsity = 1 - out.nnz / numel(R);

% --- Verdict --------------------------------------------------------------
budget = max(1, opts.CompactFrac * minDim);

if out.rank <= 1
    out.verdict = "separable";
    out.reason  = sprintf( ...
        ['rank 1 at tol %g: the surface factorizes as u(a)v(rho), so every ' ...
         'path point sees the same shape over the separator and the ' ...
         'conditioning carries no information. Compact, but about the ' ...
         'fusion factors rather than the smoothing.'], opts.RankTol);
elseif kAt <= budget
    out.verdict = "compact";
    out.reason  = sprintf( ...
        ['%d of %d singular values hold %g%% of the energy (rank_eps %d, ' ...
         'sigma_2/sigma_1 %.3g), inside the %g of min(size) this file ' ...
         'calls compact.'], kAt, minDim, 100 * opts.EnergyLevel, ...
        out.rank, out.spectralGap, opts.CompactFrac);
else
    out.verdict = "not compact";
    out.reason  = sprintf( ...
        ['%d of %d singular values are needed for %g%% of the energy ' ...
         '(rank_eps %d, %.1f%% of full; sparsity %.2f), which is the ' ...
         'sheet''s "full rank / no sparsity" failure signal.'], ...
        kAt, minDim, 100 * opts.EnergyLevel, out.rank, ...
        100 * out.rankFraction, out.sparsity);
end
out.compact = out.verdict == "compact";
end

% =========================================================================
function out = localDegenerate(out, why)
%LOCALDEGENERATE Fill the whole struct for a surface there is nothing to say
%   about.
%   Inputs   OUT the partly built struct, WHY the reason
%   Outputs  OUT, with every field present
%   Utility  an empty or all-zero surface must still return the same field
%           set, or every consumer has to guard.
%
%   Every field is present so that callers can concatenate results without
%   testing for the degenerate case, and every measured field is NaN rather
%   than 0, because a rank of 0 and an unmeasurable rank are different facts.
out.singularValues    = zeros(0, 1);
out.sigmaMax          = NaN;
out.rank              = NaN;
out.rankFraction      = NaN;
out.spectralGap       = NaN;
out.rankCurve         = struct('tol', 10 .^ (-1:-1:-12), 'rank', nan(1, 12));
out.energyRank        = struct('level', [0.90 0.99 0.999], 'k', nan(1, 3));
out.energyRankAtLevel = NaN;
out.effectiveRank     = NaN;
out.nnz               = NaN;
out.sparsity          = NaN;
out.verdict           = "degenerate";
out.reason            = why;
out.compact           = false;
end
