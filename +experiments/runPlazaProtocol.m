function out = runPlazaProtocol(experiment, opts)
%RUNPLAZAPROTOCOL The showcase manual's Plaza experiments, P1-A to P2-B.
%
%   Inputs
%     EXPERIMENT    "P1-A", "P1-B", "P2-A" or "P2-B", described below
%     Methods       which methods to run       default all three (P2-B: two)
%     Dataset       override the protocol's dataset    default per experiment
%     Fractions     P1-B ADA fractions            default [0 0.2 0.4 0.6]
%     Landmark      P2-A landmark ordinal                        default 2
%     NumWindows    P2-A rungs on the evidence ladder            default 3
%     SampleCounts  P2-B values of N                   default [50 150 400]
%     SupportSizes  P2-B values of |S|                 default [101 201 501]
%     Thresholds    P2-B early-stop thresholds vartheta
%                                                default [1e-3 1e-4 1e-5]
%     Config        a base config to start from   default paper-style below
%     Seed          measurement and sampling seed                default 7
%     Verbose       print each run as it finishes             default true
%
%   Outputs
%     OUT.experiment  which protocol was run
%     OUT.runs        every run made: its label, case, results and settings
%     OUT.metrics     one row per run per method, in the order they were run
%     OUT.alignment   what poseRMSEaligned was aligned by
%     OUT.methods     the methods actually run
%     OUT.config      the base config, serializable
%     OUT.notes       the independent-window caveat below, travelling with
%                     the data
%
%   Utility
%     Run one protocol from section 7 of the showcase manual and return every
%     run it made, the harmonized results and one metrics table across all of
%     them.
%
%       P1-A  Plaza1, association as loaded. Trajectory, landmarks, samples,
%             runtime, RMSE. The baseline the other three are read against.
%       P1-B  Plaza1 at a sweep of ADA fractions, 0 to 60% by default.
%             Robustness to data-association ambiguity.
%       P2-A  Plaza2, paper-style settings, on the windows where a chosen
%             landmark accumulates evidence. Feeds the L2 marginal figure.
%       P2-B  Plaza2, stress test over N, |S| and the early-stop threshold.
%             Slices and Smoothed Slices only by default; NF-iSAM does not
%             read those knobs, so including it would add half an hour of
%             runtime to produce a flat line.
%
%   WHAT THESE ARE NOT. The manual's protocols are written for a method that
%   filters along the whole sequence. This engine holds ten to thirteen
%   variables depending on the problem -- the figure is per-map, not a
%   property of the engine, see datasets.makeGridWorldCase -- so each run
%   here solves one WINDOW of the sequence, eight keyframes by default and
%   sized against a cap on VARIABLES rather than on poses (makePlazaCase's
%   MaxVariables), because poses are only half of what a window holds.
%   The runs are independent of one another. Read across runs as a set of
%   separate posteriors under different conditions, never as a trajectory
%   accumulating evidence -- OUT.notes says so on every returned struct, so
%   that the caveat travels with the data rather than living only here.
%
%   COST. Each configuration runs NF-iSAM at roughly 210-340 s on the shipped
%   budgets, against 2-6 s for the elimination methods. P1-B at four fractions
%   is therefore a twenty-minute experiment, and that is with everything else
%   held fixed. Methods="Slices" cuts it to under a minute when the question
%   does not need all three.
%
%   PAPER-STYLE DEFAULTS, from manual section 6: N = 150, N_M = 100,
%   vartheta = 1e-4, NF-iSAM training samples 2000. The repository default for
%   N is 200, so these protocols set it explicitly rather than inherit it.
%
%   See also experiments.plazaLandmarkWindows, viz.plotPlazaMarginal,
%   datasets.makePlazaCase.

arguments
    experiment (1,1) string {mustBeMember(experiment, ["P1-A","P1-B","P2-A","P2-B"])}
    opts.Methods (1,:) string = string.empty(1,0)
    opts.Dataset (1,1) string {mustBeMember(opts.Dataset, ["","Plaza1","Plaza2"])} = ""
    opts.Fractions (1,:) double {mustBeInRange(opts.Fractions, 0, 1)} = [0 0.2 0.4 0.6]
    opts.Landmark (1,1) double {mustBeInteger, mustBePositive} = 2
    opts.NumWindows (1,1) double {mustBeInteger, mustBePositive} = 3
    opts.SampleCounts (1,:) double = [50 150 400]
    opts.SupportSizes (1,:) double = [101 201 501]
    opts.Thresholds (1,:) double = [1e-3 1e-4 1e-5]
    opts.Config = []
    opts.Seed (1,1) double {mustBeInteger, mustBeNonnegative} = 7
    opts.Verbose (1,1) logical = true
end

base = opts.Config;
if isempty(base)
    base = methods.commonMethodConfig('seed', opts.Seed, ...
        'numSamples', 150, 'mmdSamples', 100, 'mmdThreshold', 1e-4, ...
        'nfisamTrainSamples', 2000);
end

allThree = ["Slices", "NF-iSAM", "Smoothed Slices"];
useMethods = opts.Methods;

runs = struct('label', {}, 'caseData', {}, 'results', {}, 'summary', {}, ...
              'settings', {});

switch experiment
    case "P1-A"
        ds = localDataset(opts.Dataset, "Plaza1");
        if isempty(useMethods), useMethods = allThree; end
        runs = localRun(runs, "as loaded (known)", ...
            {'Dataset', ds, 'Association', "known", 'Seed', opts.Seed}, ...
            base, useMethods, opts.Verbose, struct('association', "known"));

    case "P1-B"
        ds = localDataset(opts.Dataset, "Plaza1");
        if isempty(useMethods), useMethods = allThree; end
        for f = opts.Fractions
            % Fraction 0 is run through the AMBIGUOUS path deliberately. It
            % should reproduce the known-association result, and if it does
            % not, the ADA machinery is costing accuracy at a setting where
            % it is supposed to be inert -- which is worth catching here
            % rather than misreading as difficulty at 20%.
            runs = localRun(runs, sprintf("ADA %.0f%%", 100*f), ...
                {'Dataset', ds, 'Association', "ambiguous", ...
                 'AmbiguityFraction', f, 'Seed', opts.Seed}, ...
                base, useMethods, opts.Verbose, struct('ambiguityFraction', f));
        end

    case "P2-A"
        ds = localDataset(opts.Dataset, "Plaza2");
        if isempty(useMethods), useMethods = allThree; end
        [windows, winInfo] = experiments.plazaLandmarkWindows(ds, opts.Landmark, ...
            'NumWindows', opts.NumWindows);
        for i = 1:numel(windows)
            runs = localRun(runs, ...
                sprintf("L%d, %d pose(s), kf %d", opts.Landmark, ...
                        winInfo.observingPoses(i), windows(i)), ...
                {'Dataset', ds, 'Association', "known", ...
                 'WindowStart', windows(i), 'NumPoses', winInfo.numPoses, ...
                 'Seed', opts.Seed}, ...
                base, useMethods, opts.Verbose, ...
                struct('windowStart', windows(i), ...
                       'observingPoses', winInfo.observingPoses(i), ...
                       'landmarkId', winInfo.landmarkId));
        end

    case "P2-B"
        ds = localDataset(opts.Dataset, "Plaza2");
        if isempty(useMethods), useMethods = ["Slices", "Smoothed Slices"]; end
        % One knob moves per run, the others at the paper-style value. A
        % factorial sweep would be 27 runs and would answer a question about
        % interactions that nothing in the manual asks.
        for n = opts.SampleCounts
            cfg = localWith(base, 'numSamples', n);
            runs = localRun(runs, sprintf("N = %d", n), ...
                {'Dataset', ds, 'Association', "known", 'Seed', opts.Seed}, ...
                cfg, useMethods, opts.Verbose, struct('numSamples', n));
        end
        for s = opts.SupportSizes
            cfg = localWith(base, 'separatorSupportSize', s);
            runs = localRun(runs, sprintf("|S| = %d", s), ...
                {'Dataset', ds, 'Association', "known", 'Seed', opts.Seed}, ...
                cfg, useMethods, opts.Verbose, struct('separatorSupportSize', s));
        end
        for th = opts.Thresholds
            cfg = localWith(base, 'mmdThreshold', th);
            runs = localRun(runs, sprintf("vartheta = %g", th), ...
                {'Dataset', ds, 'Association', "known", 'Seed', opts.Seed}, ...
                cfg, useMethods, opts.Verbose, struct('mmdThreshold', th));
        end
end

out = struct( ...
    'experiment', experiment, ...
    'runs',       runs, ...
    'metrics',    localMetricsTable(experiment, runs), ...
    'alignment',  "poseRMSEaligned is after Kabsch-Umeyama onto the surveyed " + ...
                  "track, rigid only: no scale, no reflection", ...
    'methods',    useMethods, ...
    'config',     utils.serializableConfig(base), ...
    'notes',      "Each run solves an independent window of the sequence; " + ...
                  "runs are separate posteriors, not one filter over time.");

if opts.Verbose
    fprintf('\n=== %s: %d run(s), %d row(s) ===\n', experiment, ...
        numel(runs), height(out.metrics));
    disp(out.metrics);
end
end

% =========================================================================
function ds = localDataset(given, fallback)
%LOCALDATASET The override, or the protocol's own dataset.
%   Inputs   GIVEN the option, FALLBACK what the protocol asks for
%   Outputs  DS, the dataset name to load
%   Utility  let "" mean "leave the protocol alone".
ds = fallback;
if strlength(given) > 0, ds = given; end
end

% =========================================================================
function cfg = localWith(cfg, name, value)
%LOCALWITH A copy of the config with one field changed.
%   Inputs   CFG the base, NAME the field, VALUE the new value
%   Outputs  CFG, the modified copy
%   Utility  keep a sweep's per-run edit from mutating the base config.
cfg.(name) = value;
end

% =========================================================================
function runs = localRun(runs, label, caseArgs, config, whichMethods, verbose, settings)
%LOCALRUN One configuration, built and compared, recorded even if it fails.
%   Inputs   RUNS what has been run so far, LABEL this run's name, CASEARGS
%           the arguments to makePlazaCase, CONFIG the config, WHICHMETHODS,
%           VERBOSE, SETTINGS what this run varied
%   Outputs  RUNS, with this configuration appended
%   Utility  make one configuration and record it, failures included.
%
%   A protocol that stops at the first failed configuration reports nothing
%   about the ones that would have worked, and on a twenty-minute experiment
%   that is the difference between a result and a wasted afternoon. Failures
%   are recorded with their message and the sweep goes on.
if verbose
    fprintf('  %-34s ', label);
end

t0 = tic;
try
    caseData = datasets.makePlazaCase(caseArgs{:});
    [results, summary] = methods.runComparison(caseData, config, whichMethods);
    err = "";
catch e
    caseData = struct('failed', true, 'args', {caseArgs});
    results = struct([]);
    summary = struct('error', e.message);
    err = string(e.message);
end
el = toc(t0);

% THE VARIABLE NAME IS NOT KNOWABLE BEFORE THE CASE IS BUILT. makePlazaCase
% numbers the window's landmarks l1..lN in window order and keeps the survey
% node id on landmarks.ids, so "l" + surveyId names a DIFFERENT variable --
% it used to be handed to plotPlazaMarginal as a lookup key, which drew one
% landmark's marginal against another landmark's truth. Resolved here, where
% the id and the built case are both in hand.
%
% Set on every path, empty on a failed build, because runs(end+1) = struct(...)
% needs the same fields on every element of the array.
if isfield(settings, 'landmarkId')
    settings.landmarkName = "";
    if strlength(err) == 0
        row = find(caseData.landmarks.ids == settings.landmarkId, 1);
        if ~isempty(row)
            settings.landmarkName = caseData.landmarks.names(row);
        end
    end
end

if verbose
    if strlength(err) > 0
        fprintf('FAILED after %.0f s -- %s\n', el, err);
    else
        fprintf('%.0f s\n', el);
    end
end

runs(end+1) = struct('label', label, 'caseData', caseData, ...
    'results', results, 'summary', summary, 'settings', settings);
end

% =========================================================================
function T = localMetricsTable(experiment, runs)
%LOCALMETRICSTABLE One row per run per method, in the order they were run.
%   Inputs   EXPERIMENT the protocol's name, RUNS every run made
%   Outputs  T, the protocol's metrics table
%   Utility  flatten the runs into the one table the protocol reports.
exper = strings(0,1); label = strings(0,1); method = strings(0,1);
poseRMSE = []; poseAligned = []; landmarkRMSE = []; runtime = [];
ess = []; status = strings(0,1); deadReckoned = []; deadReckonedAligned = [];

for i = 1:numel(runs)
    R = runs(i).results;
    if isempty(R)
        exper(end+1,1) = experiment;      %#ok<AGROW>
        label(end+1,1) = runs(i).label;   %#ok<AGROW>
        method(end+1,1) = "(none)";       %#ok<AGROW>
        poseRMSE(end+1,1) = NaN;          %#ok<AGROW>
        poseAligned(end+1,1) = NaN;       %#ok<AGROW>
        landmarkRMSE(end+1,1) = NaN;      %#ok<AGROW>
        runtime(end+1,1) = NaN;           %#ok<AGROW>
        ess(end+1,1) = NaN;               %#ok<AGROW>
        status(end+1,1) = "failed";       %#ok<AGROW>
        deadReckoned(end+1,1) = NaN;      %#ok<AGROW>
        deadReckonedAligned(end+1,1) = NaN; %#ok<AGROW>
        continue
    end
    dr = localDeadReckoningRmse(runs(i).caseData);
    for j = 1:numel(R)
        r = R(j);
        deadReckoned(end+1,1) = dr.raw;               %#ok<AGROW>
        deadReckonedAligned(end+1,1) = dr.aligned;    %#ok<AGROW>
        exper(end+1,1) = experiment;              %#ok<AGROW>
        label(end+1,1) = runs(i).label;           %#ok<AGROW>
        method(end+1,1) = string(r.methodName);   %#ok<AGROW>
        poseRMSE(end+1,1) = localField(r, 'poseRMSE');       %#ok<AGROW>
        poseAligned(end+1,1) = localAlignedRmse(r, runs(i).caseData); %#ok<AGROW>
        landmarkRMSE(end+1,1) = localField(r, 'landmarkRMSE'); %#ok<AGROW>
        runtime(end+1,1) = localField(r, 'runtimeTotal');     %#ok<AGROW>
        ess(end+1,1) = localEss(r);               %#ok<AGROW>
        status(end+1,1) = string(r.status);       %#ok<AGROW>
    end
end

T = table(exper, label, method, poseRMSE, poseAligned, landmarkRMSE, ...
    deadReckoned, deadReckonedAligned, runtime, ess, status, ...
    'VariableNames', {'experiment','run','method','poseRMSE', ...
                      'poseRMSEaligned','landmarkRMSE','deadReckoningRMSE', ...
                      'deadReckoningRMSEaligned','runtime','minEssSupport', ...
                      'status'});
end

% =========================================================================
function v = localDeadReckoningRmse(caseData)
%LOCALDEADRECKONINGRMSE Pose RMSE of the window's odometry, integrated alone.
%   Inputs   CASEDATA, the window
%   Outputs  V, the dead-reckoned pose RMSE in metres
%   Utility  give the estimates something to be better than.
%
%   THE BASELINE THE ESTIMATES HAD NEVER BEEN CHECKED AGAINST. The case has
%   carried caseData.plaza.deadReckoned since the loader was written, and it
%   was used only to draw a dotted line on a figure; no metric, protocol or
%   table compared a posterior against it. An RMSE in metres cannot be read
%   without it -- 0.541 m is a good number or a bad one depending entirely on
%   what ignoring every range reading would have scored.
%
%   It is a FAIR baseline rather than a straw man: the dead reckoning is
%   integrated from the true first pose and heading, which is the same anchor
%   the estimator gets from its prior on the first pose. Both start level, and
%   only the estimate also sees the ranges.
%
%   It is also a STRONG one over a short window, and that should temper the
%   reading. Odometry has barely drifted after eight keyframes, so beating it
%   there is a high bar; the interesting comparison is how the gap moves as the
%   window grows and the drift accumulates.
%   BOTH COLUMNS, because comparing an unaligned baseline against an aligned
%   estimate is not like for like and reverses the answer here. On the Plaza1
%   default window the baseline is 0.414 m raw and 0.087 m aligned; NF-iSAM
%   scores 0.451 m raw and 0.042 m aligned, so it loses to odometry on one
%   column and beats it twofold on the other. A single baseline number would
%   have supported whichever conclusion it was placed next to.
v = struct('raw', NaN, 'aligned', NaN);
if ~isfield(caseData, 'plaza') || ~isfield(caseData.plaza, 'deadReckoned')
    return
end
dr = caseData.plaza.deadReckoned;
truth = caseData.mission.truePoses;
if isempty(dr) || ~isequal(size(dr), size(truth))
    return
end
v.raw = sqrt(mean(sum((dr - truth).^2, 2)));
try
    aligned = utils.alignTrajectory(dr, truth);
    v.aligned = sqrt(mean(sum((aligned - truth).^2, 2)));
catch
    % Leave it NaN. A baseline that cannot be aligned is a missing number,
    % not a reason to fail a protocol run that otherwise completed.
end
end

% =========================================================================
function v = localAlignedRmse(r, caseData)
%LOCALALIGNEDRMSE Pose RMSE after rigid alignment onto the surveyed track.
%   Inputs   R a method result, CASEDATA the window
%   Outputs  V, the aligned pose RMSE in metres
%   Utility  report the error the Plaza papers report, beside the raw one.
%
%   The Plaza papers report trajectory error after alignment, because a
%   range-only solution is determined only up to the gauge the priors do not
%   pin down. Both columns are reported rather than one: this case DOES carry
%   a prior on the first pose, so the two should be close, and a large gap
%   between them is information -- it says the window drifted as a rigid body
%   rather than deformed, which is a different failure from a bad estimate.
%
%   Rigid only. utils.alignTrajectory defaults scale and reflection off, and
%   this call does not turn them on: the measurements are metric ranges, so a
%   scale error is a real error, and a mirrored window is the mode collapse
%   the project exists to show.
v = NaN;
if ~isfield(r, 'map') || ~isstruct(r.map) || ~isfield(r.map, 'poseMean')
    return
end
if ~isfield(caseData, 'groundTruth') || ~isfield(caseData.groundTruth, 'poses')
    return
end
est = r.map.poseMean;
gt  = caseData.groundTruth.poses;
if size(est, 1) ~= size(gt, 1) || size(est, 2) < 2, return, end

try
    [~, tf] = utils.alignTrajectory(est(:, 1:2), gt(:, 1:2));
    v = tf.rmseAfter;
catch
    v = NaN;
end
end

% =========================================================================
function v = localField(r, name)
%LOCALFIELD A metric's value on a result, or NaN when it is absent.
%   Inputs   R a method result, NAME the metric
%   Outputs  V the value, or NaN
%   Utility  let a method reporting fewer metrics still produce a row.
v = NaN;
if isfield(r, 'metrics') && isfield(r.metrics, name)
    v = double(r.metrics.(name));
end
end

% =========================================================================
function v = localEss(r)
%LOCALESS The engine's own health number, NaN where the method has none.
%   Inputs   R, a method result
%   Outputs  V, the support ESS, or NaN
%   Utility  report the support's health without inventing one where the
%           concept does not apply.
%
%   NF-iSAM has no separator support and therefore no support ESS. Reporting
%   a zero would read as a collapsed support rather than an absent concept.
v = NaN;
if isfield(r, 'metrics') && isfield(r.metrics, 'health') ...
        && isfield(r.metrics.health, 'minEssSupport')
    v = double(r.metrics.health.minEssSupport);
end
end
