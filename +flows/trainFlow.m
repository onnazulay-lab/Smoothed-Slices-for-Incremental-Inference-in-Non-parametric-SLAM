function [flow, info] = trainFlow(X, opts)
%TRAINFLOW Fit a flow to training samples by the objective of Eq. N7.
%
%   Inputs
%     X                          training samples, one per row, n-by-D
%     NumSplines, HiddenUnits    K and the conditioner width, section 9
%     Bound                      the spline support
%     LearnRate, BatchSize       not from the paper; see below
%     MaxIterations, MinIterations, Window, RelTol   the stopping rule
%     Holdout                    fraction reserved for scoring     default 0
%     Flow                       continue from a trained flow rather than a
%                                fresh one
%     Seed, Verbose
%
%   Outputs
%     FLOW  the trained flows.RQSplineFlow
%     INFO  iterations, stoppedBy, the loss history, logLikelihood,
%           heldOutLogLikelihood, flatColumns, runtime and nonPaperChoices
%
%   Utility
%     Run step 2 of Algorithm N2: the training loop of spec section 16, with
%     the settings the paper leaves open reported back rather than buried.
%
%   THE OBJECTIVE, Eq. N7:
%
%       T* = argmin_T  sum_k sum_d [ 1/2 T_d(x^k)^2 - log dT_d/dx_d (x^k) ]
%
%   which is the KL divergence from the sample distribution to the flow's,
%   dropped of the terms that do not involve T. It is the negative log
%   likelihood of Eq. N4 up to the constant D/2 log(2*pi), so the loss
%   reported here is comparable across flows of the same width but is not a
%   log likelihood; INFO.logLikelihood gives that.
%
%   THE STOPPING RULE is the authors', spec section 9: after at least 100
%   iterations, compare the mean loss over the latest 50 iterations with the
%   mean over the 50 before it and stop when the relative change is under 1%.
%   It is a rule about the loss curve flattening, not about convergence, and
%   INFO.stoppedBy says which of the two exits was taken so that a run that
%   merely ran out of iterations is not mistaken for a converged one.
%
%   WHAT IS NOT FROM THE PAPER. Spec section 20 records that the optimizer,
%   learning rate, batch size and initialization are not specified. Adam at
%   1e-2 in batches of 2000 is the default here and every one of them is an
%   option; INFO.nonPaperChoices lists them back so a reported result carries
%   its own settings.
%
%   HOLDOUT, off by default, reserves a fraction of the samples and scores
%   them afterwards. The authors' n_train = 2000 is not always enough: a 4-D
%   clique fitted from 2000 samples here overfitted badly enough to shrink a
%   unit-variance marginal to 0.85, with a loss curve that flattened and
%   stopped as if converged. INFO.heldOutLogLikelihood against
%   INFO.logLikelihood is what makes that visible instead of silent.
%
%   Standardization, spec section 9, is computed here from X and handed to
%   the flow, which applies it on every call. Orientation columns must be
%   wrapped to [-pi, pi] before they get here: this function sees a matrix
%   and cannot know which columns are angles.

arguments
    X (:,:) double {mustBeNonempty}
    opts.NumSplines (1,1) double {mustBeInteger} = 9        % K, section 9
    opts.HiddenUnits (1,1) double {mustBeInteger} = 8       % section 9
    opts.Bound (1,1) double {mustBePositive} = 5
    opts.LearnRate (1,1) double {mustBePositive} = 1e-2     % not from paper
    opts.BatchSize double {mustBeScalarOrEmpty} = []        % not from paper
    opts.MaxIterations (1,1) double {mustBeInteger, mustBePositive} = 2000
    opts.MinIterations (1,1) double {mustBeInteger, mustBePositive} = 100
    opts.Window (1,1) double {mustBeInteger, mustBePositive} = 50
    opts.RelTol (1,1) double {mustBePositive} = 0.01
    opts.Seed double {mustBeScalarOrEmpty} = []
    opts.Verbose (1,1) logical = false
    opts.Flow = []      % continue from a trained flow instead of a fresh one
    opts.Holdout (1,1) double {mustBeInRange(opts.Holdout, 0, 0.5)} = 0
end

if ~all(isfinite(X), 'all')
    error('flows:trainFlow:nonFinite', ...
        ['The training samples contain %d non-finite values. Algorithm N1 ' ...
         'produced them, so the measurement model that simulated them is ' ...
         'the place to look.'], nnz(~isfinite(X)));
end

tStart = tic;

% --- Optional held-out slice ---------------------------------------------
% Off by default, so the default run is exactly the paper's. When it is on,
% the reserved rows are removed BEFORE standardization: leaving them in would
% put held-out data into mu and sigma and make the score look better than the
% fit is. The stopping rule is untouched -- this measures overfitting rather
% than preventing it, because the rule that stops training is the authors'
% and is not ours to replace.
Xheld = zeros(0, size(X, 2));
if opts.Holdout > 0
    nh = max(1, round(opts.Holdout * size(X, 1)));
    if nh >= size(X, 1)
        error('flows:trainFlow:holdoutTooLarge', ...
            'Holding out %d of %d samples leaves nothing to train on.', ...
            nh, size(X, 1));
    end
    held = false(size(X, 1), 1);
    held(randperm(size(X, 1), nh)) = true;
    Xheld = X(held, :);
    X     = X(~held, :);
end

[n, D] = size(X);

% --- Standardization, spec section 9 -------------------------------------
mu    = mean(X, 1);
sigma = std(X, 0, 1);
flat  = sigma < 1e-12;
if any(flat)
    % A column that never varies carries no information and would divide by
    % zero. Left at scale 1 and named, because in a clique it means a
    % variable was simulated without noise, which is worth knowing.
    sigma(flat) = 1;
end

% --- The model -----------------------------------------------------------
if isempty(opts.Flow)
    flow = flows.RQSplineFlow(D, ...
        'NumSplines', opts.NumSplines, 'HiddenUnits', opts.HiddenUnits, ...
        'Bound', opts.Bound, 'Mu', mu, 'Sigma', sigma, 'Seed', opts.Seed);
else
    flow = opts.Flow;
    if flow.Dimension ~= D
        error('flows:trainFlow:continueWidth', ...
            ['The flow to continue from has %d dimensions but the samples ' ...
             'have %d.'], flow.Dimension, D);
    end
end

params = dlupdate(@dlarray, flow.Params);
avgGrad = [];
avgSqGrad = [];

% Batch size is a non-paper choice, spec section 20. The default is the
% authors' own training-set size, which makes it the full batch at their
% n_train = 2000 and a minibatch above it. That is not arbitrary: on a 4-D
% clique at n = 8000 this measured 4 times faster than the full batch AND fit
% better, because the sample count that stops the flow overfitting is exactly
% the one that makes full-batch iterations expensive.
batch = opts.BatchSize;
if isempty(batch)
    batch = 2000;
end
batch = min(batch, n);

% --- The loop, spec section 16 -------------------------------------------
losses = zeros(opts.MaxIterations, 1);
checkFrom = max(opts.MinIterations, 2*opts.Window);
stoppedBy = "maxIterations";
iter = opts.MaxIterations;

for it = 1:opts.MaxIterations
    if batch < n
        Xb = X(randperm(n, batch), :);
    else
        Xb = X;
    end

    [grad, loss] = dlfeval(@localObjective, flow, params, Xb);
    [params, avgGrad, avgSqGrad] = adamupdate(params, grad, ...
        avgGrad, avgSqGrad, it, opts.LearnRate);

    losses(it) = double(loss);
    if ~isfinite(losses(it))
        error('flows:trainFlow:diverged', ...
            ['The loss became %g at iteration %d. The spline saw a sample ' ...
             'far outside its support, or the learning rate (%g) is too ' ...
             'large for this clique.'], losses(it), it, opts.LearnRate);
    end

    if opts.Verbose && mod(it, 50) == 0
        fprintf('  iteration %4d   loss %10.4f\n', it, losses(it));
    end

    if it >= checkFrom
        latest = mean(losses(it-opts.Window+1:it));
        prev   = mean(losses(it-2*opts.Window+1:it-opts.Window));
        if abs(prev) > 0 && abs(latest - prev)/abs(prev) < opts.RelTol
            stoppedBy = "relativeLoss";
            iter = it;
            break
        end
    end
end
losses = losses(1:iter);

% Back to plain numbers: outside this function a flow is numeric code.
flow = flow.setParameters(dlupdate(@extractdata, params));

info = struct( ...
    'iterations',     iter, ...
    'stoppedBy',      stoppedBy, ...
    'finalLoss',      losses(end), ...
    'lossHistory',    losses, ...
    'logLikelihood',  mean(flow.logProb(X)), ...
    'heldOutLogLikelihood', localHeldOut(flow, Xheld), ...
    'numHeldOut',     size(Xheld, 1), ...
    'numSamples',     n, ...
    'dimension',      D, ...
    'mu',             mu, ...
    'sigma',          sigma, ...
    'flatColumns',    find(flat), ...
    'runtime',        toc(tStart), ...
    'nonPaperChoices', struct('optimizer', "adam", ...
                              'learnRate', opts.LearnRate, ...
                              'batchSize', batch, ...
                              'initialization', "glorot hidden, identity output"));
end

% -------------------------------------------------------------------------
function ll = localHeldOut(flow, Xheld)
%LOCALHELDOUT Mean log likelihood on the reserved rows, NaN when there are
%   none.
%   Inputs   FLOW the trained flow, XHELD the reserved rows
%   Outputs  LL, the mean log likelihood, or NaN
%   Utility  score the samples training never saw.
%
%   The gap against INFO.logLikelihood is the overfitting: the authors'
%   n_train = 2000 is enough for a small clique and measurably not enough for
%   a wider one, and without this the symptom is a posterior that is too
%   narrow while looking perfectly well converged.
if isempty(Xheld)
    ll = NaN;
    return
end
ll = mean(flow.logProb(Xheld));
end

function [grad, loss] = localObjective(flow, params, X)
%LOCALOBJECTIVE Eq. N7 over one batch, and its gradient.
%   Inputs   FLOW the model, PARAMS its learnables as dlarray, X one batch
%   Outputs  GRAD the gradient w.r.t. PARAMS, LOSS the batch objective
%   Utility  the function dlfeval differentiates each iteration.
%
%   The mean over samples rather than the sum, following spec section 16, so
%   that the learning rate does not have to be retuned per clique size.
%
%   The log derivative carries the -log(sigma) of standardization. That is a
%   constant offset on the loss and does not move the minimizer, but it keeps
%   the number reported here equal to the density the flow actually defines.
flow = flow.setParameters(params);
[y, logDeriv] = flow.transform(X);
loss = mean(sum(0.5*y.^2 - logDeriv, 2));
grad = dlgradient(loss, params);
end
