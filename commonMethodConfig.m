function config = commonMethodConfig(opts)
%COMMONMETHODCONFIG The shared budget and hyperparameter block.
%
%   Inputs
%     every field of the returned config, as a name-value pair; the groups
%     and their paper provenance are listed below
%
%   Outputs
%     CONFIG  the settings every method receives
%
%   Utility
%     Hand all three methods literally the same struct, which is the surest
%     way to honour the matched-budget requirement.
%
%   Comparability depends on this being ONE object: the app spec requires the
%   three methods to run with the same datasets, the same noise, the same
%   seeds and matched support budgets, and the surest way to honour that is
%   to give them literally the same struct.
%
%   Defaults follow the paper reproduction profiles where the papers state a
%   value, and are marked as implementation choices where they do not.
%
%   THE GROUPS, AND WHERE EACH NUMBER COMES FROM.
%
%   Sampling budgets
%     numSamples            N, outer samples per elimination step.
%                           Paper: 150 for Plaza2, 200 for Four Doors.
%     numInnerSamples       M, nested samples per outer sample (Eq. 23).
%                           Not specified by the paper; an implementation
%                           choice, and the quantity Smoothed Slices removes.
%     numBackwardSamples    separator samples in the backward pass (Eq. S16).
%     separatorSupportSize  |S| = R_s, the finite separator support.
%     marginalGridSize      display/normalization grid for marginals.
%
%   MMD early stopping (Slices spec section 16)
%     mmdSamples     N_M      paper: 100
%     mmdThreshold   vartheta paper: 1e-4
%     mmdKernel/Bandwidth/Estimator  NOT specified by the paper.
%
%   RCS surface settings (Smoothed Slices spec sections 10-11)
%     surfaceMode        "finite" (Mode A). "basis" and "regression" are
%                        Modes B and C, deferred to iteration 5.
%     surfaceSupportSize |X_1| = B_1, support of the inner path variable.
%     activeSetSize      |N_r| = K_r, active successors per row. Inf means
%                        the dense update of Eq. (48).
%     activeSetRule      how N_r(a) is chosen: "nearest" | "transition" | "random"

arguments
    opts.numSamples (1,1) double {mustBeInteger, mustBePositive} = 200
    opts.numInnerSamples (1,1) double {mustBeInteger, mustBePositive} = 50
    opts.numBackwardSamples (1,1) double {mustBeInteger, mustBePositive} = 400
    opts.backwardChunkSize (1,1) double {mustBeInteger, mustBePositive} = 50
    opts.separatorSupportSize (1,1) double {mustBeInteger, mustBePositive} = 201
    opts.separatorSupport (1,:) double = []
    opts.marginalGridSize (1,1) double {mustBeInteger, mustBePositive} = 401

    opts.innerEstimator (1,1) string {mustBeMember(opts.innerEstimator, ["nested","rcs"])} = "nested"

    % N_M for the early-stopping heuristic. The paper's value; keep it.
    opts.mmdSamples (1,1) double {mustBeInteger, mustBePositive} = 100
    % Sample count for SCORING a posterior against the reference. Kept
    % separate from N_M on purpose: N_M = 100 is a budget for a cheap online
    % stopping test, and reusing it for evaluation leaves the unbiased MMD
    % estimator unable to separate two good posteriors -- it returns a small
    % negative value that clamps to exactly 0 and looks like a broken metric.
    opts.mmdEvalSamples (1,1) double {mustBeInteger, mustBePositive} = 1000
    opts.mmdThreshold (1,1) double {mustBePositive} = 1e-4
    opts.mmdKernel (1,1) string = "rbf"
    opts.mmdBandwidth = "median"
    opts.mmdEstimator (1,1) string {mustBeMember(opts.mmdEstimator, ["biased","unbiased"])} = "unbiased"

    % --- Incremental replay ----------------------------------------------
    % Off by default: the batch pass is the reference, and every number this
    % project has reported so far was measured on it. Turning this on replays
    % the mission increment by increment, which is what the two reuse rules
    % below need in order to have a previous increment to reuse from.
    opts.incremental (1,1) logical = false
    % Algorithm S5 steps 5-7, applied to the backward traversal.
    opts.mmdEarlyStopping (1,1) logical = true
    % Consecutive variables that must fall below vartheta before the
    % traversal stops. The paper stops at the first; requiring a run of them
    % guards against a single quiet variable on a trajectory that is still
    % moving. Implementation choice, hence configurable and reported.
    opts.mmdStopPatience (1,1) double {mustBeInteger, mustBePositive} = 1
    % Reuse of generated factors (the conditional smoothing surfaces) across
    % increments, keyed by the elimination prefix that produced them.
    opts.surfaceCache (1,1) logical = true

    opts.surfaceMode (1,1) string {mustBeMember(opts.surfaceMode, ["finite","basis","regression"])} = "finite"
    opts.surfaceSupportSize (1,1) double {mustBeInteger, mustBePositive} = 200
    opts.activeSetSize (1,1) double {mustBePositive} = Inf
    opts.activeSetRule (1,1) string {mustBeMember(opts.activeSetRule, ["nearest","transition","random"])} = "transition"
    % Used only on a general graph, where activeSetSize has no natural
    % absolute scale because |S| itself grows with separator dimension.
    opts.activeSetFraction (1,1) double {mustBeInRange(opts.activeSetFraction, 0, 1)} = 0.25
    % rank_eps, nnz_eps and the singular spectrum of each surface -- the
    % research sheet's E2 diagnostics, and the left-hand side of the whole
    % hypothesis. On by default because a claim about compact surfaces that
    % is never measured is not a claim. An SVD per surface update is not
    % free, so it is measured OUTSIDE the estimator's own timer and can be
    % switched off for a run whose purpose is timing.
    opts.surfaceDiagnostics (1,1) logical = true

    % --- General-graph engine (grid world) -------------------------------
    % The three-node engine cancels the sampling factor's normalizer; the
    % general engine divides by an explicit proposal density instead, and
    % these are that proposal's knobs.
    opts.defensiveWeight (1,1) double {mustBeInRange(opts.defensiveWeight, 0, 1)} = 0.10
    opts.proposalBandwidth (1,1) double {mustBePositive} = 0.35
    opts.supportMixtureSize (1,1) double {mustBeInteger, mustBePositive} = 64
    % A fixed support size cannot serve both a 2-D and an 8-D separator: the
    % same number of points that resolves a plane leaves an eight-dimensional
    % separator with an effective sample size near one. The support therefore
    % grows with separator dimension, capped, and the size actually used is
    % reported per step so the growth is visible rather than silent.
    opts.supportDimGrowth (1,1) double {mustBeGreaterThanOrEqual(opts.supportDimGrowth, 1)} = 2.0
    opts.maxSupportSize (1,1) double {mustBeInteger, mustBePositive} = 2000
    % Candidates drawn per retained support point. The support is resampled
    % down to |S| so that it ends up distributed according to f_new rather
    % than according to the proposal.
    opts.supportOverdraw (1,1) double {mustBeInteger, mustBePositive} = 4
    % Whether to resample the candidates down to |S|. Off by default: see the
    % comment at the resampling branch of forwardEliminationGeneral.
    opts.supportResample (1,1) logical = false
    % Whether a generated factor answers queries from its retained mixture
    % rather than by looking up its tabulated support. Exact costs |X| factor
    % evaluations per query; nearest-neighbour lookup on a scattered support
    % of four or more dimensions is biased, and that bias compounds over the
    % eliminations into a confident wrong answer.
    %
    % Off by default. Exact evaluation is the right answer numerically and
    % the wrong one in practice at this scale: each nested level multiplies
    % the expansion by |X|, so a single elimination step on the grid world
    % expands to tens of millions of rows. Turning it on is worth doing on a
    % small graph to measure how much the lookup costs.
    opts.exactGeneratedFactors (1,1) logical = false

    % --- NF-iSAM (spec section 9) ----------------------------------------
    % n_train, the samples Algorithm N1 simulates per clique. The authors'
    % value, and flows.trainFlow documents where it is measurably thin: a 4-D
    % clique fitted from 2000 samples overfits badly enough to shrink a
    % unit-variance marginal, with a loss curve that flattens as if converged.
    opts.nfisamTrainSamples (1,1) double {mustBeInteger, mustBePositive} = 2000
    % Forwarded verbatim to flows.trainFlow. MaxIterations is capped well
    % below that function's own ceiling of 2000: a comparative run trains one
    % flow per clique and the grid world has six, so the full ceiling makes a
    % single Run All take tens of minutes. 200 leaves the authors' stopping
    % rule room to fire -- it cannot trigger before iteration 100 and needs a
    % 50-iteration window on each side of that -- while keeping a clique to
    % about twenty seconds. Measured on the two-pose range benchmark at
    % n_train = 2000, the relative L1 against quadrature is 0.035 at 100
    % iterations, 0.050 at 150 and 0.037 at 250: flat inside its own Monte
    % Carlo noise, while the runtime is not. The cap is an implementation
    % choice and INFO.stoppedBy on every fit says whether it bound.
    opts.nfisamTraining (1,1) struct = struct('MaxIterations', 200)
    % false retrains every clique on every increment: the counterfactual the
    % incremental claim of Algorithm N3 is measured against.
    opts.nfisamReuse (1,1) logical = true

    opts.seed (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    opts.trackNormalizers (1,1) logical = true

    % --- Session, not settings -------------------------------------------
    % A utils.ProgressReporter, or [] for a run nobody is watching. This is
    % the one field here that is not a hyperparameter: it belongs to the
    % session rather than to the method, and utils.serializableConfig strips
    % it wherever a config is stored so it never reaches an export bundle.
    % It lives on the config anyway because the alternative is a new optional
    % argument on nine engine functions that already receive one.
    opts.progress = []
end

config = struct();
fn = fieldnames(opts);
for i = 1:numel(fn)
    config.(fn{i}) = opts.(fn{i});
end

% Provenance: which of these came from a paper and which are ours.
config.provenance = struct( ...
    'numSamples',        "paper: 150 (Plaza2) / 200 (Four Doors)", ...
    'numInnerSamples',   "implementation choice; not specified by the Slices paper", ...
    'mmdSamples',        "paper: N_M = 100 (Plaza2)", ...
    'mmdThreshold',      "paper: vartheta = 1e-4 (Plaza2)", ...
    'mmdKernel',         "implementation choice; kernel not specified by the paper", ...
    'mmdBandwidth',      "implementation choice", ...
    'mmdStopPatience',   "implementation choice; the paper stops at the first quiet variable", ...
    'incremental',       "replay mode; the batch pass remains the reference", ...
    'surfaceCache',      "Smoothed Slices spec sections 10-11, applied across increments", ...
    'surfaceMode',       "Smoothed Slices spec section 11, Mode A", ...
    'activeSetSize',     "Smoothed Slices spec Eq. (49); Inf selects the dense Eq. (48)", ...
    'defensiveWeight',   "implementation choice; q_def of the Smoothed Slices spec section 17", ...
    'supportMixtureSize', "implementation choice; makes the support proposal density evaluable", ...
    'nfisamTrainSamples', "paper: n_train = 2000 (NF-iSAM spec section 9)", ...
    'nfisamTraining',     "implementation choice; the optimizer, learning rate and iteration cap are not specified by the paper", ...
    'nfisamReuse',        "Algorithm N3 step 2-3; false is the batch counterfactual");
end
