function out = runFactorGraphCaseStudy(opts)
%RUNFACTORGRAPHCASESTUDY Run the methods on NF-iSAM's own released graphs.
%   OUT = RUNFACTORGRAPHCASESTUDY() builds a planar case from each released
%   factor graph, runs the selected methods on it, and returns both the raw and
%   the gauge-aligned pose error for each.
%
%   Inputs
%     Files    graph file names under data/nfisam    default all *.fg found
%     Methods  any of "Slices", "Smoothed Slices", "NF-iSAM"    default all
%     Config   method config                    default configPreset("paperLike")
%     Seed     RNG seed, applied before each run                     default 11
%     MaxPoses passed through to the case builder                   default Inf
%
%   Outputs
%     OUT  struct with
%            rows       one struct per (case, method): rawPoseRMSE,
%                       alignedPoseRMSE, landmarkRMSE, rotationDeg,
%                       gaugeShare, seconds, status
%            table      the same as a MATLAB table, for printing
%            scopeNotes the scope note of each case, so the caveat travels
%            failures   rows whose run errored, with the identifier
%
%   Utility
%     Produce the case-study numbers reproducibly, with the gauge freedom
%     separated out rather than buried in the total.
%
%   WHY BOTH ERRORS ARE RETURNED, AND WHY THE ALIGNED ONE IS NOT THE HEADLINE.
%   Projecting NF-iSAM's SE2 graphs onto the plane leaves every factor a
%   function of DISTANCES only -- see datasets.makeFactorGraphCase for why the
%   heading cannot be used without injecting ground truth. Distances are
%   invariant under a rigid rotation about the prior, so the projected posterior
%   has a global rotational gauge freedom that the SE2 problem does not have.
%   The raw pose RMSE therefore mostly measures a rotation nobody constrained,
%   and reporting it alone would be reporting the gauge.
%
%   MEASURED, at the paper budget, seed 11, on the two released graphs:
%
%     case        method             raw   aligned   lmRMSE   rotation  gauge
%     case1       Slices          108.22     23.44   102.04    -178.9    78%
%     case1       Smoothed Slices  52.08     33.15    90.97     -42.7    36%
%     case1       NF-iSAM          67.38     38.90    54.41     161.7    42%
%     case1_da    Slices           68.06     33.04    44.36      67.5    52%
%     case1_da    Smoothed Slices  48.16     29.02    46.77     -24.4    40%
%     case1_da    NF-iSAM          62.56     39.07    51.64     -37.6    38%
%
%   EVERY method on EVERY case recovers a large rotation, one of them within a
%   degree of a full flip. That is not six failures; it is one property of the
%   projected problem showing up six times, and it is the reason this function
%   reports the split instead of a single number.
%
%   WHAT THIS CASE STUDY DOES AND DOES NOT SUPPORT. It runs the methods on
%   NF-iSAM's own graph structure -- their factors, their connectivity, their
%   data-association ambiguity in case1_da -- which is what makes it worth
%   having: no keyframing or calibration choice of ours sits between the methods
%   and the problem. It does NOT support putting any of these numbers beside
%   NF-iSAM's published position RMSE. Even after alignment the residuals are
%   large against a track of about 90 m extent, and the length constraints
%   themselves are loosely satisfied, because five chained distances and ranges
%   to two landmarks leave the configuration weakly determined. The comparison
%   would be between two different problems.
%
%   The aligned column is rigid only: utils.alignTrajectory defaults scale and
%   reflection off and this function does not turn them on. Scale is observable
%   from metric ranges, so a scale error is a real error; and a mirrored answer
%   is a distinct mode worth seeing rather than absorbing. Measured, allowing
%   reflection changed nothing on these cases, so the estimates are rotated and
%   not mirrored.
%
%   See also datasets.makeFactorGraphCase, utils.alignTrajectory,
%            experiments.runPlazaProtocol.

arguments
    opts.Files (1,:) string = string.empty(1,0)
    opts.Methods (1,:) string {mustBeMember(opts.Methods, ...
        ["Slices", "Smoothed Slices", "NF-iSAM"])} = ...
        ["Slices", "Smoothed Slices", "NF-iSAM"]
    opts.Config (1,1) struct = methods.configPreset("paperLike")
    opts.Seed (1,1) double {mustBeInteger, mustBeNonnegative} = 11
    opts.MaxPoses (1,1) double {mustBePositive} = Inf
end

dataDir = fullfile(utils.projectRoot(), 'data', 'nfisam');

files = opts.Files;
if isempty(files)
    found = dir(fullfile(dataDir, '*.fg'));
    files = string({found.name});
end
if isempty(files)
    error('experiments:factorGraphCaseStudy:noGraphs', ...
        'No .fg graphs found in %s.', dataDir);
end

rows = struct('case', {}, 'method', {}, 'rawPoseRMSE', {}, ...
              'alignedPoseRMSE', {}, 'landmarkRMSE', {}, 'rotationDeg', {}, ...
              'gaugeShare', {}, 'seconds', {}, 'status', {}, 'identifier', {});
scopeNotes = struct();

for f = files
    p = fullfile(dataDir, char(f));
    if ~isfile(p)
        error('experiments:factorGraphCaseStudy:missingGraph', ...
            '%s is not in this checkout.', f);
    end

    caseData = datasets.makeFactorGraphCase(p, 'MaxPoses', opts.MaxPoses);
    scopeNotes.(matlab.lang.makeValidName(f)) = caseData.scopeNote;
    truth = caseData.groundTruth.poses;

    for m = opts.Methods
        % Seeded per run, not per case, so a method's number does not depend on
        % which methods ran before it.
        utils.setRandomSeed(opts.Seed);

        row = struct('case', f, 'method', m, 'rawPoseRMSE', NaN, ...
            'alignedPoseRMSE', NaN, 'landmarkRMSE', NaN, 'rotationDeg', NaN, ...
            'gaugeShare', NaN, 'seconds', NaN, 'status', "ok", 'identifier', "");

        t0 = tic;
        try
            result = localRun(m, caseData, opts.Config);
            row.seconds = toc(t0);

            est = result.map.poseMean(:, 1:2);
            row.rawPoseRMSE = sqrt(mean(sum((est - truth).^2, 2)));
            if isfield(result.metrics, 'landmarkRMSE')
                row.landmarkRMSE = result.metrics.landmarkRMSE;
            end

            [~, tf] = utils.alignTrajectory(est, truth);
            row.alignedPoseRMSE = tf.rmseAfter;
            row.rotationDeg = atan2d(tf.R(2,1), tf.R(1,1));
            if row.rawPoseRMSE > 0
                row.gaugeShare = ...
                    (row.rawPoseRMSE - row.alignedPoseRMSE) / row.rawPoseRMSE;
            end
        catch ME
            % Recorded rather than thrown: one method failing on one graph
            % should not discard the runs that finished, which is the same rule
            % runPlazaProtocol follows for a cancelled cell.
            row.seconds = toc(t0);
            row.status = "failed";
            row.identifier = string(ME.identifier);
        end

        rows(end+1) = row; %#ok<AGROW>
    end
end

out = struct();
out.rows = rows;
out.table = struct2table(rows);
out.scopeNotes = scopeNotes;
out.failures = rows([rows.status] == "failed");
out.config = utils.serializableConfig(opts.Config);
out.seed = opts.Seed;
end

% =========================================================================
function result = localRun(method, caseData, config)
%LOCALRUN Dispatch one method by name.
%   Inputs   METHOD the method name, CASEDATA the case, CONFIG the budget
%   Outputs  RESULT, the method's result struct
%   Utility  keep the dispatch in one place so every method receives exactly
%            the same case and config.
switch method
    case "Slices"
        result = methods.runSlicesMethod(caseData, config);
    case "Smoothed Slices"
        result = methods.runSmoothedSlicesMethod(caseData, config);
    case "NF-iSAM"
        result = methods.runNFISAMMethod(caseData, config);
    otherwise
        error('experiments:factorGraphCaseStudy:unknownMethod', ...
            'No method called %s.', method);
end
end
