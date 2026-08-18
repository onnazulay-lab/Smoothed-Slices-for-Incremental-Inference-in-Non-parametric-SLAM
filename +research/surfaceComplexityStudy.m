function out = surfaceComplexityStudy(opts)
%SURFACECOMPLEXITYSTUDY Research sheet E2: are the surfaces R_r compact?
%
%   Inputs
%     Config        base method config             default a reduced budget
%     Noise         odometry sigma levels, the control  default [0.3 1.2 3.0]
%     SamplingNoise g_0 sigma levels               default [0.2 0.5 1.0 2.0]
%     FusionNoise   fusion factor sigma levels     default [0.2 0.5 1.0 2.0]
%     Overlap       mixture offset levels          default [0.8 1.5 2.2 3.5]
%     Variants      "gaussian" and/or "multimodal"      default both
%     Baseline      variant the noise axis is run on    default "multimodal"
%     Progress      a utils.ProgressReporter
%
%   Outputs
%     OUT.rows       one row per run: axis, level, the cardinalities, and the
%                    complexity of R_0 and of the terminal surface R_1
%     OUT.baseline   the run every axis is varied away from
%     OUT.config     the config the runs were made with
%     OUT.compactFrac, OUT.compactBudget   the rank threshold "compact" means
%     OUT.verdict    "compact" | "not compact" | "separable" | "mixed"
%     OUT.evidence   the sentence behind the verdict, with numbers in it
%     OUT.inherited  whether R_0's rank is explained by R_1's -- see below
%     OUT.control    the odometry axis, which must not move at all -- see below
%     OUT.note       the design caveats below, as text, for the app and the
%                    export
%
%   Utility
%     Vary the case's noise, its multimodality and the overlap width between
%     its modes, and report what happens to the rank, the spectrum and the
%     sparsity of the conditional smoothing surface the method builds. The
%     sheet lists these outputs as "rank decay of R_r, sparsity, active K
%     needed for fixed error"; the first two are here and the third is
%     research.activeSetProfile, which needs a different experiment.
%
%   WHY THIS MATTERS MORE THAN A COST PLOT. research.costQualityFrontier
%   measures whether the method saved evaluations. This measures WHETHER THE
%   REASON IT WOULD is true. The sheet states the idea as a conditional -- if
%   the surfaces are lower-rank, sparse or well-approximated by small active
%   sets, then the cost can move -- so a saving with full-rank surfaces would
%   be a saving for some other reason, and a compact surface with no saving
%   localizes the problem to the implementation rather than the idea.
%
%   ONE CASE CAN ANSWER THIS, AND IT IS NOT A CHOICE. The surface exists only
%   on the Lemma 1 structural route, which is taken when an eliminated
%   variable has neither a unary factor nor an already-eliminated neighbour.
%   Four Doors, the grid world and Plaza are all tagged engine = "general" and
%   never consult config.innerEstimator at all -- their Slices and Smoothed
%   Slices runs are the same computation to the factor evaluation. The
%   two-pose range case is the one case with a surface to measure, and every
%   run below ASSERTS that it took that route rather than trusting it.
%
%   NOISE IS TWO AXES AND A CONTROL, not one axis. The recursion is built
%   from the sampling factor g_0 and the fusion factor a; the odometry factor
%   is a front factor b_0 that multiplies the result afterwards. So there are
%   three noise knobs on this case and only two of them can reach the
%   surface. All three are swept: the odometry under the name "control",
%   where the prediction is that nothing moves at all, and OUT.control checks
%   it to the bit rather than to a tolerance. A control that came out flat is
%   the evidence that the other two axes are being read off the right matrix.
%
%   THREE AXES OF THE SHEET'S FOUR. E2 names noise, nonlinearity,
%   multimodality and overlap width. The first, third and fourth are varied
%   here. NONLINEARITY IS NOT AVAILABLE ON THIS CASE and pretending otherwise
%   would be the more damaging choice: the two-pose case is built from
%   gaussianUnary and gaussianRelative factors, so it is linear-Gaussian by
%   construction, and its multimodal variant gets its two modes from an
%   explicit two-component mixture rather than from the annulus of a real
%   range measurement. The nonlinear cases -- Plaza's and the grid world's
%   range factors -- are exactly the cases that run the general engine and
%   build no surface. So on this case the sheet's nonlinearity axis and its
%   multimodality axis are the same knob, and OUT.note says so.
%
%   ONE AXIS AT A TIME, FROM A BASELINE. Four numeric axes at four levels
%   each, across two variants, is 512 runs as a factorial and 17 as a
%   screening design, and this is the screening design. The cost is that it
%   cannot see an interaction: if overlap only matters at high noise, this
%   will report that neither matters. That is a real limitation of the design
%   rather than a result, so it is stated in OUT.note rather than left for a
%   reader to assume away.
%
%   WHAT "INHERITED" IS FOR. R_0 = diag(Z) P_0 R_1, so rank(R_0) is bounded
%   by rank(R_1). If the terminal surface is already low rank then R_0 has no
%   choice, and reporting compactness would be reporting a property of the
%   fusion factors under a name that credits the smoothing. Both ranks are
%   measured on every run and OUT.inherited says how often R_0's rank simply
%   equals the bound.
%
%   OVERLAP IS A RATIO, NOT A DISTANCE. The mixture components sit at
%   RangeB(1) +/- d with standard deviation RangeB(2), so what decides whether
%   the modes are distinguishable is d / RangeB(2). The levels above are
%   distances and the ratio is reported beside them in the rows, because a
%   distance alone is unreadable without the sigma it is measured against.
%
%   See also methods.smoothed.surfaceComplexity, research.activeSetProfile,
%   research.costQualityFrontier, viz.plotSurfaceComplexity.

arguments
    % Unconstrained so that [] can mark "use the study's own budget"; an
    % arguments block validates its default, and building the default config
    % here would run methods.commonMethodConfig on every call that overrides
    % it.
    opts.Config = []
    opts.Noise (1,:) double {mustBePositive} = [0.3 1.2 3.0]
    opts.SamplingNoise (1,:) double {mustBePositive} = [0.2 0.5 1.0 2.0]
    opts.FusionNoise (1,:) double {mustBePositive} = [0.2 0.5 1.0 2.0]
    opts.Overlap (1,:) double {mustBePositive} = [0.8 1.5 2.2 3.5]
    opts.Variants (1,:) string = ["gaussian", "multimodal"]
    opts.Baseline (1,1) string = "multimodal"
    opts.Progress = []
end

p = utils.progressOf(struct('progress', opts.Progress));

cfg = opts.Config;
if isempty(cfg)
    % A screening design runs seventeen times, and the quantity being screened is
    % the SHAPE of the surface rather than the accuracy of the posterior it
    % feeds. |X_0| and |S| set the surface's dimensions and so are kept
    % generous; the backward pass and the MMD evaluation do not enter the
    % measurement at all and are cut to what still lets a run complete.
    cfg = methods.commonMethodConfig( ...
        'numSamples', 120, 'surfaceSupportSize', 120, ...
        'separatorSupportSize', 101, 'numBackwardSamples', 100, ...
        'mmdEvalSamples', 100, 'activeSetSize', 24);
end
cfg.surfaceDiagnostics = true;   % the whole point of this study

% The baseline the axes are varied away from, READ OFF the case builder
% rather than restated here. Restating it is how a study drifts away from the
% case it claims to be studying: the builder picks a different odometry per
% variant, and a hardcoded copy would go on reporting the old one after any
% change to the case. Building a case runs no inference, so this costs
% nothing worth saving.
baseSettings = datasets.makeTwoPoseRangeCase('Variant', opts.Baseline).settings;
baseOverlap  = baseSettings.mixtureOffset;
baseNoise    = baseSettings.odometry(2);

runs = struct('axis', {}, 'level', {}, 'variant', {}, 'label', {}, 'args', {});

for v = opts.Variants
    runs(end+1) = struct('axis', "variant", 'level', NaN, 'variant', v, ...
        'label', sprintf("variant = %s", v), 'args', {{'Variant', v}}); %#ok<AGROW>
end

% NOISE, AND WHICH NOISE. The surface is built from the sampling factor g_0
% (x1 -> l1) and the fusion factor a (l1 -> x2). The odometry factor f(x1,x2)
% is a FRONT factor b_0: it multiplies the slice matrix after R_0 is built and
% never enters the recursion. So sweeping the odometry sigma cannot move the
% spectrum of R_0, by construction and not as a finding -- which makes it a
% control worth running rather than a noise axis worth believing. It is swept
% under its own name, and OUT.control reports whether it did in fact stay
% flat. A diagnostic that moved here would be measuring something other than
% the surface.
for s = opts.Noise
    runs(end+1) = struct('axis', "control", 'level', s, 'variant', opts.Baseline, ...
        'label', sprintf("odometry sigma = %.2f (control)", s), ...
        'args', {{'Variant', opts.Baseline, 'Odometry', [2 s]}}); %#ok<AGROW>
end

% The noise the surface can actually see, split by where it enters. The
% sampling sigma sets the transition weights W and so the active successor
% sets; the fusion sigma sets the terminal surface R_1 and so the bound on
% rank(R_0). They are separate axes because they act on separate factors of
% the recursion and there is no reason to expect them to act alike.
for s = opts.SamplingNoise
    runs(end+1) = struct('axis', "samplingNoise", 'level', s, ...
        'variant', opts.Baseline, ...
        'label', sprintf("g_0 sigma = %.2f", s), ...
        'args', {{'Variant', opts.Baseline, 'RangeA', [1.5 s]}}); %#ok<AGROW>
end

for s = opts.FusionNoise
    runs(end+1) = struct('axis', "fusionNoise", 'level', s, ...
        'variant', opts.Baseline, ...
        'label', sprintf("a sigma = %.2f", s), ...
        'args', {{'Variant', opts.Baseline, 'RangeB', [0.5 s]}}); %#ok<AGROW>
end

for d = opts.Overlap
    runs(end+1) = struct('axis', "overlap", 'level', d, 'variant', "multimodal", ...
        'label', sprintf("mixture offset = %.2f", d), ...
        'args', {{'Variant', "multimodal", 'Odometry', [2 baseNoise], ...
                  'MixtureOffset', d}}); %#ok<AGROW>
end

nR = numel(runs);
rows = cell(1, nR);

for i = 1:nR
    p.report((i-1)/nR, sprintf("E2 %d of %d: %s", i, nR, runs(i).label));

    caseData = datasets.makeTwoPoseRangeCase(runs(i).args{:});
    result   = methods.runSmoothedSlicesMethod(caseData, cfg);

    inner = localInnerOrFail(result, runs(i).label);
    rows{i} = localRow(runs(i), inner, caseData.settings);
end

out = struct();
out.rows     = struct2table(vertcat(rows{:}));
out.baseline = struct('variant', opts.Baseline, 'odomSigma', baseNoise, ...
                      'mixtureOffset', baseOverlap);
out.config   = utils.serializableConfig(cfg);

% The line the word "compact" is drawn at, carried out of the study so that a
% figure can show it instead of restating it. Recomputed from the surfaces
% that were actually measured rather than from the requested budgets: the
% support sizes a run ends up with are the ones the verdict was taken against.
out.compactFrac   = 0.10;      % methods.smoothed.surfaceComplexity's default
out.compactBudget = max(1, out.compactFrac * ...
                        min(min(out.rows.X0), min(out.rows.S)));

[out.verdict, out.evidence] = localVerdict(out.rows);
out.inherited = localInherited(out.rows);
out.control   = localControl(out.rows);
out.note = [
    "One axis at a time from a baseline, not a factorial: an interaction " + ...
    "between noise and overlap would read here as neither mattering."
    "Nonlinearity, the sheet's fourth axis, is not varied. The only case " + ...
    "that builds a surface is linear-Gaussian, and the nonlinear cases run " + ...
    "the general engine, which never consults the inner estimator."
    "Overlap is reported as a ratio d/sigma as well as a distance, because " + ...
    "the distance alone does not say whether the modes are separable."];
p.report(1, sprintf("E2: %s", out.verdict));
end

% =========================================================================
function inner = localInnerOrFail(result, label)
%LOCALINNERORFAIL The surface, or an error saying no surface was built.
%   Inputs   RESULT a method result, LABEL the run's name for the message
%   Outputs  INNER, the surface diagnostics
%   Utility  refuse a run that took the general route, loudly.
%
%   Asserted rather than assumed. Three of the four cases in this repository
%   never consult the inner estimator, so a study that silently reported
%   empty diagnostics would look like "no surface complexity" instead of "no
%   surface". If this ever fires on the two-pose case, the elimination stopped
%   taking the Lemma 1 route and the study is measuring nothing.
if result.status ~= "ok"
    error('research:surfaceComplexityStudy:runFailed', ...
        'The run for %s did not complete: status "%s".', label, result.status);
end
if numel(result.states) < 2 || ~isfield(result.states(2).Diagnostics, 'inner') ...
        || ~isfield(result.states(2).Diagnostics.inner, 'surface')
    error('research:surfaceComplexityStudy:noSurface', ...
        ['The run for %s built no conditional smoothing surface, so there ' ...
         'is no E2 measurement to take. This case must take the Lemma 1 ' ...
         'route and record its inner diagnostics.'], label);
end
inner = result.states(2).Diagnostics.inner;
if ~isfield(inner.surface, 'rank')
    error('research:surfaceComplexityStudy:diagnosticsOff', ...
        ['The run for %s has a surface but no complexity measurement: ' ...
         'config.surfaceDiagnostics was false.'], label);
end
end

% =========================================================================
function r = localRow(spec, inner, settings)
%LOCALROW One run flattened, with both surfaces side by side.
%   Inputs   SPEC the run's axis and level, INNER its surface diagnostics,
%           SETTINGS the case as it was actually built
%   Outputs  R, one struct that becomes one table row
%   Utility  flatten a run into the study's table.
%
%   The overlap is read back off the case that was actually built rather than
%   off the request, so that a level this study did not set -- the baseline's
%   own offset, or a sigma the case builder chose per variant -- is reported
%   as what ran.
s0 = inner.surface;
s1 = inner.terminalSurface;

d     = settings.mixtureOffset;
sigma = settings.rangeB(2);
if string(spec.variant) ~= "multimodal"
    % The unimodal variant carries the builder's default offset in its
    % settings and never uses it. Reporting 2.2 here would put a number in
    % the overlap column for a case that has one mode and nothing to overlap.
    d     = NaN;
    sigma = NaN;
end

r = struct();
r.axis            = spec.axis;
r.level           = spec.level;
r.variant         = string(spec.variant);
r.label           = string(spec.label);

% Cardinalities, in the sheet's notation, so a plot legend can quote them.
r.X0              = inner.numOuterSamples;
r.X1              = inner.supportX1;
r.S               = inner.separatorSupport;
r.K               = inner.activeSetSize;

r.overlapDistance = d;
r.overlapRatio    = d / sigma;    % see the docstring: the ratio is the reading

r.rank            = s0.rank;
r.rankFraction    = s0.rankFraction;
r.energyRank99    = s0.energyRankAtLevel;
r.effectiveRank   = s0.effectiveRank;
r.spectralGap     = s0.spectralGap;
r.nnz             = s0.nnz;
r.sparsity        = s0.sparsity;
r.verdict         = string(s0.verdict);

r.terminalRank    = s1.rank;
r.terminalEnergyRank99 = s1.energyRankAtLevel;
% R_0 = diag(Z) P_0 R_1 caps rank(R_0) at rank(R_1). Equality means R_0's
% compactness was decided before the recursion ran.
r.rankIsInherited = isfinite(s0.rank) && isfinite(s1.rank) && s0.rank >= s1.rank;

r.singularValues  = {s0.singularValues(:).'};
r.reason          = string(s0.reason);
end

% =========================================================================
function [verdict, evidence] = localVerdict(T)
%LOCALVERDICT One word for the whole study, and the numbers behind it.
%   Inputs   T, the study's row table
%   Outputs  VERDICT one of four words, EVIDENCE the sentence behind it
%   Utility  answer the sheet's question in one word without deleting the
%           conditional it was asked as.
%
%   "mixed" is a real answer and the most likely one: the sheet's hypothesis
%   is conditional, and a surface that is compact at wide mode separation and
%   full rank at narrow separation is precisely the finding worth reporting.
%   Collapsing that to a majority vote would delete it.
v = string(T.verdict);
u = unique(v);

if isscalar(u)
    verdict = u;
else
    verdict = "mixed";
end

% The two ranks are quoted together and in that order on purpose. The verdict
% is taken on the ENERGY rank, which is the smaller and more flattering of
% the two, so leaving rank_eps out would let "compact" stand on the number
% that was chosen for it. Where they disagree -- and here they disagree by a
% factor of three -- the disagreement is the interesting part: rank_eps counts
% every direction with any content at all, and the energy rank counts the ones
% that carry the surface.
nCompact = sum(v == "compact");
frac = 100 * mean(T.rankFraction, 'omitnan');
% string(), not the char sprintf returns. Appending to a char array with +
% adds the character codes, which is a silent size error on a match and a
% loud one otherwise -- it was the loud one.
evidence = string(sprintf( ...
    ['%d of %d configurations compact, judged on the 99%% energy rank, ' ...
     'which runs %d to %d of min(|X_0|,|S|). rank_eps is looser and ' ...
     'averages %.0f%% of full. Sparsity %.2f to %.2f.'], ...
    nCompact, height(T), min(T.energyRank99), max(T.energyRank99), frac, ...
    min(T.sparsity), max(T.sparsity)));

if verdict == "mixed"
    axesThatMove = unique(T.axis(v ~= v(1)));
    evidence = evidence + string(sprintf(' The answer changes along: %s.', ...
        strjoin(cellstr(axesThatMove), ', ')));
end
end

% =========================================================================
function info = localControl(T)
%LOCALCONTROL Did the knob that cannot reach the surface leave it alone?
%   Inputs   T, the study's row table
%   Outputs  INFO, whether every control row produced the same spectrum
%   Utility  check the negative prediction, which is what makes the positive
%           readings trustworthy.
%
%   The odometry sigma is a front factor. R_0 is built without it, so every
%   control row must produce the SAME spectrum -- not a similar one. This
%   checks for bit-level agreement rather than agreement to a tolerance,
%   because the prediction is exact: identical inputs to an identical
%   computation. A tolerance here would quietly accept a real leak.
sub = T(T.axis == "control", :);
info = struct('levels', height(sub), 'flat', true, 'note', "");

if height(sub) < 2
    info.flat = NaN;
    info.note = "fewer than two control levels; nothing to compare";
    return
end

cols = ["rank", "energyRank99", "effectiveRank", "spectralGap", "sparsity"];
moved = strings(1, 0);
for c = cols
    v = sub.(c);
    if ~all(v == v(1) | (isnan(v) & isnan(v(1))))
        moved(end+1) = c; %#ok<AGROW>
    end
end

info.flat = isempty(moved);
if info.flat
    info.note = sprintf(['the odometry sigma moved across %g levels and ' ...
        'every surface statistic was identical, as it must be: the ' ...
        'odometry is a front factor and R_0 is built without it.'], ...
        height(sub));
else
    info.note = sprintf(['the odometry sigma changed %s, which it cannot ' ...
        'do through the recursion. Either a front factor is leaking into ' ...
        'the surface or the diagnostic is reading the wrong matrix.'], ...
        strjoin(cellstr(moved), ', '));
end
end

% =========================================================================
function info = localInherited(T)
%LOCALINHERITED How much of R_0's compactness was already in R_1.
%   Inputs   T, the study's row table
%   Outputs  INFO, how often rank(R_0) simply equals the bound rank(R_1)
%   Utility  keep a property of the fusion factors from being reported under a
%           name that credits the smoothing.
n = sum(T.rankIsInherited);
info = struct( ...
    'count',    n, ...
    'total',    height(T), ...
    'always',   n == height(T), ...
    'note',     sprintf(['rank(R_0) reaches its rank(R_1) bound in %d of ' ...
                         '%d runs; where it does, the compactness is a ' ...
                         'property of the fusion factors rather than of ' ...
                         'the smoothing recursion.'], n, height(T)));
end
