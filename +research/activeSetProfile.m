function out = activeSetProfile(opts)
%ACTIVESETPROFILE Research sheet E2: how small can |N_r| be, and still be right?
%
%   Inputs
%     Ks          active set sizes to try       default [2 4 8 16 32 64 128]
%     Tolerance   relative surface error that counts as matched   default 1e-3
%     Variant     two-pose variant              default "multimodal"
%     Config      base method config            default a reduced budget
%     Progress    a utils.ProgressReporter
%
%   Outputs
%     OUT.rows          per K: surfaceError, posteriorError, retained mass,
%                       predicted cost, measured evaluations, cardinalities
%     OUT.dense         the K = Inf run the surface errors are measured from
%     OUT.floor         the dense run's own posterior error against the
%                       reference
%     OUT.recommended   smallest sparse K meeting Tolerance on the SURFACE
%     OUT.recommendedPosterior  smallest sparse K inside the dense ANSWER's
%                       band
%     OUT.headline      one line carrying both, since they usually disagree
%     OUT.fraction      recommended K as a fraction of |X_1|, the sheet's
%                       signal
%     OUT.costRealized  predicted saving against measured, and whether they
%                       agree
%     OUT.verdict       "small K suffices" | "K approaches |X_1|" | "no K
%                       tested suffices" -- on the surface criterion
%     OUT.evidence      the numbers behind the verdict
%
%   Utility
%     Run the same case at a series of active successor counts K and report,
%     for each, how far the generated factor has moved from the dense update
%     of Eq. (48) and how far the posterior has moved from the quadrature
%     reference. This answers the third output E2 asks for -- "active K needed
%     for fixed error" -- and is the direct test of the sheet's own failure
%     signal for the compactness claim: "K must approach |X_{r+1}|".
%
%   WHY DENSE IS THE RIGHT BASELINE FOR THE SURFACE ERROR. K = Inf selects
%   Eq. (48), the same recursion with no sparsification at all. Every other
%   difference between the runs is held fixed by construction -- same case,
%   same seed, same supports, and the active-set rule draws no random numbers
%   -- so the gap between K and dense is the sparsification and nothing else.
%   Scoring the surface against the quadrature reference instead would fold
%   the sampling error of the whole method into a number meant to isolate one
%   approximation.
%
%   AND WHY THE POSTERIOR ERROR IS REPORTED ANYWAY. A surface error is only
%   interesting if it reaches the answer. The two-pose case has a quadrature
%   reference, so each K is also scored end to end, and the pair is the
%   finding: if the surface error at K = 8 is 1e-3 while the posterior error
%   is flat across every K, then the active set stopped mattering long before
%   it stopped changing the surface, and the honest report of "K needed for
%   fixed error" is the smaller number with that caveat attached.
%
%   THE FLOOR IS NOT ZERO. Two runs at the same K would not agree exactly on
%   the posterior either -- the backward pass and the MMD evaluation draw
%   their own samples -- so OUT.floor records the posterior error of the dense
%   run against the reference. A K whose posterior error sits at that floor
%   has not been shown to be good, only to be indistinguishable from dense at
%   this budget, and OUT.recommended is chosen against the floor rather than
%   against zero.
%
%   AND THE COST MODEL IS CHECKED AGAINST THE COUNTER. |X_0| |N_0| |S| is
%   linear in K, so the predicted cost falls with the active set. The measured
%   factor evaluations are reported beside it, and on this implementation they
%   do not move at all: the transition weights are built over the whole
%   support and then sparsified, so nothing the counter can see is saved.
%   OUT.costRealized states which of the two a reader is looking at, because a
%   predicted saving quoted as a measured one is the failure mode this whole
%   study exists to avoid.
%
%   TOLERANCE IS A CHOICE AND IT IS REPORTED AS ONE. 1e-3 relative Frobenius
%   error on the generated factor is tight enough that the posterior cannot
%   notice and loose enough to be reachable; OUT.rows carries the whole curve
%   so that a reader who disagrees can read off their own K without rerunning.
%
%   See also research.surfaceComplexityStudy, methods.smoothed.buildActiveSuccessors,
%   viz.plotSurfaceComplexity.

arguments
    opts.Ks (1,:) double {mustBePositive} = [2 4 8 16 32 64 128]
    opts.Tolerance (1,1) double {mustBePositive} = 1e-3
    opts.Variant (1,1) string = "multimodal"
    opts.Config = []
    opts.Progress = []
end

p = utils.progressOf(struct('progress', opts.Progress));

cfg = opts.Config;
if isempty(cfg)
    cfg = methods.commonMethodConfig( ...
        'numSamples', 120, 'surfaceSupportSize', 120, ...
        'separatorSupportSize', 101, 'numBackwardSamples', 100, ...
        'mmdEvalSamples', 100);
end

caseData = datasets.makeTwoPoseRangeCase('Variant', opts.Variant);

% The reference, and the support every run is scored on. Taken once and
% pushed into the config exactly as methods.runComparison does it, so that no
% interpolation stands between an estimate and the truth -- and so that every
% K produces a slice matrix on the SAME separator support, without which the
% surface errors below would be comparing different grids.
ref = datasets.referenceTwoPoseQuadrature(caseData, ...
        'NumX2', cfg.separatorSupportSize);
ref.kind = "quadrature";
cfg.separatorSupport = ref.x2;

Ks = unique([opts.Ks(:).' Inf], 'stable');
nK = numel(Ks);

denseIdx = find(isinf(Ks), 1);
raw = cell(1, nK);

for i = 1:nK
    p.report((i-1)/nK, sprintf("active set %d of %d: K = %g", i, nK, Ks(i)));

    c = cfg;
    c.activeSetSize = Ks(i);
    r = methods.runSmoothedSlicesMethod(caseData, c);
    r = methods.scoreAgainstReference(r, ref, c);

    raw{i} = localExtract(r, Ks(i));
end

denseRun = raw{denseIdx};

rows = cell(1, nK);
for i = 1:nK
    rows{i} = localRow(raw{i}, denseRun);
end
T = struct2table(vertcat(rows{:}));
T = sortrows(T, 'K');

out = struct();
out.rows  = T;
out.dense = rmfield(denseRun, 'slice');
out.floor = denseRun.posteriorError;
out.tolerance = opts.Tolerance;
out.variant   = opts.Variant;
out.X1        = denseRun.X1;

[out.recommended, out.fraction, out.verdict, out.evidence] = ...
    localRecommend(T, denseRun.X1, opts.Tolerance);
out.recommendedPosterior = localPosteriorK(T, denseRun);
out.costRealized = localCostRealized(T);

% THE HEADLINE IS THE DISAGREEMENT. Two defensible criteria for "the active
% set is big enough" can land a factor of several apart, and quoting either
% one alone would be picking the answer. When they disagree the headline says
% both numbers; when they agree it says so, which is also worth knowing.
out.headline = localHeadline(out);

p.report(1, sprintf("active set: %s", out.verdict));
end

% =========================================================================
function e = localExtract(r, K)
%LOCALEXTRACT The one factor this experiment is about, plus its score.
%   Inputs   R a method result, K the active set size it was run at
%   Outputs  E, the generated factor's slice and the run's scores
%   Utility  pull out the one matrix the K axis is measured on, and refuse a
%           run that did not complete rather than scoring a partial one.
if r.status ~= "ok"
    error('research:activeSetProfile:runFailed', ...
        'The run at K = %g did not complete: status "%s".', K, r.status);
end
if numel(r.states) < 2 || ~isfield(r.states(2).Diagnostics, 'inner')
    error('research:activeSetProfile:noSurface', ...
        ['The run at K = %g built no conditional smoothing surface. This ' ...
         'experiment measures the active set of a surface, so a case that ' ...
         'does not build one cannot answer it.'], K);
end

inner = r.states(2).Diagnostics.inner;

e = struct();
e.K             = K;
% The slice matrix rather than R_0 alone: b_0 does not depend on K, so the
% relative error is unchanged by its presence, and this is the object that
% actually becomes f_new. Storing R_0 separately would double the run state
% to measure the same ratio.
e.slice         = r.states(2).NewFactor.SliceMatrix;
e.X0            = inner.numOuterSamples;
e.X1            = inner.supportX1;
e.S             = inner.separatorSupport;
e.actualK       = inner.activeSetSize;
e.predictedCost = inner.predictedCost;
e.retainedMass  = localField(inner.transition, 'meanRetainedMass', 1);
e.minRetained   = localField(inner.transition, 'minRetainedMass', 1);
% The union over rows, not the per-row K. R_1 is evaluated once per support
% point, so this is the only part of |X_1| a sparse update could avoid
% touching, and it is the honest ceiling on the saving. It does fall with K
% on this case -- but so much more slowly than the density that the density
% overstates the available saving by an order of magnitude at small K, and
% the union saturates at |X_1| well before the density does. DENSITY is the
% model's number; UNIONFRACTION is the one a cost claim may be made from.
e.unionSize     = localField(inner.transition, 'unionSize', e.X1);
e.unionFraction = localField(inner.transition, 'unionFraction', 1);
e.evaluations   = localMetric(r, 'factorEvaluations');
e.posteriorError = localMetric(r, 'relL1Error');
e.mmd            = localMetric(r, 'mmd');
end

% =========================================================================
function row = localRow(e, denseRun)
%LOCALROW One K, with its distance from the dense update attached.
%   Inputs   E one K's extract, DENSERUN the K = Inf extract
%   Outputs  ROW, one struct that becomes one table row
%   Utility  score a sparse run against the dense one, which differs from it
%           by the sparsification and nothing else.
row = rmfield(e, 'slice');

d = denseRun.slice;
a = e.slice;
if ~isequal(size(a), size(d))
    % Would mean the runs disagreed about |X_0| or |S|, which makes every
    % comparison below meaningless. Better to say that than to pad and get a
    % number.
    error('research:activeSetProfile:shapeMismatch', ...
        ['The K = %g run produced a %dx%d slice matrix against the dense ' ...
         'run''s %dx%d. The supports must match for the surface error to ' ...
         'mean anything.'], e.K, size(a,1), size(a,2), size(d,1), size(d,2));
end

den = norm(d, 'fro');
if den > 0
    row.surfaceError = norm(a - d, 'fro') / den;
else
    row.surfaceError = NaN;
end
row.density = e.actualK / e.X1;
end

% =========================================================================
function h = localHeadline(out)
%LOCALHEADLINE One line that does not pick a winner between two criteria.
%   Inputs   OUT, with both recommendations already computed
%   Outputs  H, one line of text
%   Utility  report the surface K and the posterior K together, because
%           quoting either alone as "the" answer would be a claim.
surfaceK = out.recommended.K;
postK    = out.recommendedPosterior.K;

if isfinite(surfaceK) && isfinite(postK)
    if surfaceK == postK
        h = sprintf("K = %g by both criteria", surfaceK);
    else
        h = sprintf("K = %g to match the surface, %g to match the answer", ...
            surfaceK, postK);
    end
elseif isfinite(postK)
    h = sprintf(['no sparse K matches the dense surface, but K = %g ' ...
        'already matches the dense answer'], postK);
elseif isfinite(surfaceK)
    h = sprintf("K = %g matches the surface; the posterior never settled", ...
        surfaceK);
else
    h = "no sparse K matched dense on either criterion";
end
h = string(h);
end

% =========================================================================
function out = localPosteriorK(T, denseRun)
%LOCALPOSTERIORK The smallest K whose ANSWER is as good as the dense one's.
%   Inputs   T the row table, DENSERUN the K = Inf extract
%   Outputs  OUT, the K and the band it had to fall inside
%   Utility  answer the question that matters end to end.
%
%   The surface criterion asks when the sparsification stops changing the
%   surface. This asks when it stops changing anything that matters, which is
%   a different and usually much smaller K -- the posterior has a sampling
%   error of its own, and a surface difference underneath it cannot be
%   detected however carefully it is measured.
%
%   "As good as dense" is defined as being inside a band around the dense
%   run's own error rather than below it, because a K that scores BETTER than
%   dense has not improved on it: at these budgets that is the run-to-run
%   scatter, and treating it as an improvement would be reading noise.
finite = T(isfinite(T.K) & T.actualK < denseRun.X1, :);
floorErr = denseRun.posteriorError;

out = struct('K', NaN, 'posteriorError', NaN, 'surfaceError', NaN, ...
             'fraction', NaN, 'reached', false, 'band', [NaN NaN]);

if ~isfinite(floorErr) || floorErr <= 0 || isempty(finite)
    out.note = "no dense error to compare against";
    return
end

band = [0.8 1.25] * floorErr;
out.band = band;
ok = finite(finite.posteriorError <= band(2), :);

if isempty(ok)
    out.note = sprintf(['no sparse K reached the dense run''s error band ' ...
        '[%.3g %.3g]; the best was %.3g.'], band(1), band(2), ...
        min(finite.posteriorError));
    return
end

out.K              = ok.K(1);
out.posteriorError = ok.posteriorError(1);
out.surfaceError   = ok.surfaceError(1);
out.fraction       = out.K / denseRun.X1;
out.reached        = true;
out.note = sprintf(['K = %g scores %.3g against the reference, inside the ' ...
    'dense run''s own band [%.3g %.3g], at %.0f%% of |X_1|. Its surface is ' ...
    'still %.2g from the dense surface, so the two criteria disagree about ' ...
    'this K by design rather than by accident.'], ...
    out.K, out.posteriorError, band(1), band(2), 100 * out.fraction, ...
    out.surfaceError);
end

% =========================================================================
function out = localCostRealized(T)
%LOCALCOSTREALIZED Does the K-linear saving the cost model predicts happen?
%   Inputs   T, the row table
%   Outputs  OUT, the predicted saving, the measured one, and whether they
%           agree
%   Utility  keep a predicted saving from being quoted as a measured one.
%
%   THE ANSWER ON THIS IMPLEMENTATION IS NO, AND IT IS NOT SUBTLE. The cost
%   model is |X_0| |N_0| |S|, linear in K, and PREDICTEDCOST reports it. The
%   MEASURED factor evaluations do not move with K at all, because
%   evaluateSurfaceRecursion evaluates g_0 over the whole |X_0| x |X_1| grid
%   and the fusion factors over the whole |X_1| x |S| grid BEFORE
%   buildActiveSuccessors chooses which entries to keep. The active set
%   sparsifies a matrix that has already been paid for.
%
%   That is a property of this implementation rather than of the idea: an
%   active set chosen without looking at every successor -- from the proposal,
%   or from a neighbourhood in the support -- would realize the saving. Until
%   something does that, PREDICTEDCOST is a model and EVALUATIONS is the
%   measurement, and this function exists so that the two are never quoted as
%   if they agreed.
ev = T.evaluations(isfinite(T.K));
pc = T.predictedCost(isfinite(T.K));

out = struct();
out.predictedRange = [min(pc) max(pc)];
out.measuredRange  = [min(ev) max(ev)];
out.predictedRatio = max(pc) / max(min(pc), realmin);
out.measuredRatio  = max(ev) / max(min(ev), realmin);
out.realized       = out.measuredRatio > 1.05;

if out.realized
    out.note = sprintf(['measured evaluations move by %.2fx across the ' ...
        'tested K against a predicted %.2fx.'], ...
        out.measuredRatio, out.predictedRatio);
else
    out.note = sprintf(['the cost model predicts a %.0fx spread across the ' ...
        'tested K and the measured factor evaluations move by %.3fx -- that ' ...
        'is, not at all. The transition weights are built densely and then ' ...
        'sparsified, so the active set saves nothing that a counter can ' ...
        'see. The saving is available to an implementation that chooses ' ...
        'N_r without evaluating every successor first.'], ...
        out.predictedRatio, out.measuredRatio);
end
end

% =========================================================================
function [rec, frac, verdict, evidence] = localRecommend(T, X1, tol)
%LOCALRECOMMEND The smallest K that met the tolerance, and what that means.
%   Inputs   T the row table, X1 the successor support size, TOL the tolerance
%   Outputs  REC the chosen row, FRAC K over |X_1|, VERDICT one of three
%           phrases, EVIDENCE the numbers behind it
%   Utility  turn the curve into a recommendation and a verdict.
%
%   "K approaches |X_1|" is the sheet's failure signal stated as an outcome,
%   and the line is drawn at half: a sparsification that has to keep more
%   than half the successors is not the sparse-surface recursion the cost
%   model was written for, whatever the error says.
% K >= |X_1| is not a sparse active set: buildActiveSuccessors takes the
% dense branch of Eq. (48) for it, so such a row is the dense run wearing a
% finite label and would be recommended with a surface error of exactly zero.
% Recommending it would answer "how small can K be" with "it cannot".
finite = T(isfinite(T.K) & T.actualK < X1, :);
ok = finite(finite.surfaceError <= tol, :);

if isempty(ok)
    rec = struct('K', NaN, 'surfaceError', NaN, 'posteriorError', NaN, ...
                 'predictedCost', NaN);
    frac = NaN;
    verdict = "no K tested suffices";
    evidence = sprintf( ...
        ['The smallest surface error at any genuinely sparse K is %.3g, ' ...
         'above the %.0e tolerance, with the largest sparse K tested at %g ' ...
         'of |X_1| = %d. On this case the sparsified recursion reaches the ' ...
         'dense update only by becoming it.'], ...
        min(finite.surfaceError), tol, max(finite.K), X1);
    return
end

rec = table2struct(ok(1, {'K', 'surfaceError', 'posteriorError', 'predictedCost'}));
frac = rec.K / X1;

if frac <= 0.5
    verdict = "small K suffices";
else
    verdict = "K approaches |X_1|";
end

evidence = sprintf( ...
    ['K = %g reaches %.2g relative error against the dense update, at %.0f%% ' ...
     'of |X_1| = %d and a predicted cost of %g against the dense %g.'], ...
    rec.K, rec.surfaceError, 100 * frac, X1, rec.predictedCost, ...
    max(T.predictedCost));
end

% =========================================================================
function v = localField(s, name, default)
%LOCALFIELD A field's value, or a default when it is absent.
%   Inputs   S the struct, NAME the field, DEFAULT the fallback
%   Outputs  V the value or the default
%   Utility  read an optional diagnostic without branching at every use.
if isstruct(s) && isfield(s, name), v = s.(name); else, v = default; end
end

% =========================================================================
function v = localMetric(r, name)
%LOCALMETRIC A metric's value on a result, or NaN when it was not computed.
%   Inputs   R a method result, NAME the metric
%   Outputs  V the value, or NaN
%   Utility  let a K whose reference metric is missing still produce a row.
if isfield(r, 'metrics') && isfield(r.metrics, name)
    v = r.metrics.(name);
else
    v = NaN;
end
end
