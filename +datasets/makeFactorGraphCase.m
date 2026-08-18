function caseData = makeFactorGraphCase(path, opts)
%MAKEFACTORGRAPHCASE A planar case from an NF-iSAM .fg graph, headings dropped.
%   CASEDATA = MAKEFACTORGRAPHCASE(PATH) builds this project's case struct from
%   one of NF-iSAM's released factor graphs, projected from SE2 onto the plane.
%
%   Inputs
%     PATH         a factor_graph.fg file, as read by datasets.readFactorGraphFile
%     MaxPoses     keep only the first N poses and the landmarks they see
%                                                                 default Inf
%     PriorSigma   fallback prior sigma when the file carries no prior  default 0.5
%
%   Outputs
%     CASEDATA     the usual case struct, plus
%       scopeNote    what the projection cost, in one paragraph
%       projection   struct recording how each SE2 record was projected
%       source       the reader's provenance block
%
%   Utility
%     Run this project's planar methods on NF-iSAM's OWN problem instances
%     rather than on a case rebuilt from the same survey, so that a comparison
%     against their published numbers is about the methods and not about
%     keyframing, calibration and heading conventions.
%
%   THE PROJECTION IS NOT FREE AND THIS IS WHERE IT IS PAID. Their poses are
%   SE2 and this project's are planar, so the heading has to go. The odometry is
%   what makes that awkward: SE2RelativeGaussianLikelihoodFactor carries its
%   translation in the FROM pose's BODY frame. In case1.fg, X0 is at (0,0) with
%   heading pi/2, X1 is at (0,30), and the odometry between them reads
%   (30, 0, 0) -- thirty metres straight ahead, which is northward only once
%   you know where the robot was pointing.
%
%   So a planar case cannot use that translation as a displacement without a
%   heading, and the only heading in the file is on the Variable Pose SE2
%   record. In these files that record is the TRUE pose: case1.fg's odometry is
%   exactly consistent with it. Rotating the body-frame translation by it would
%   hand our solver the true headings and make our planar problem EASIER than
%   the SE2 problem NF-iSAM actually solved, and any position RMSE we then
%   reported next to theirs would flatter us by exactly the amount of
%   information we had injected.
%
%   WHAT IS USED INSTEAD. Only the rotation-invariant part: the LENGTH of the
%   translation, as a range factor between consecutive pose positions. No
%   heading is read, no truth is injected, and the resulting problem is
%   strictly WEAKER than theirs -- it constrains how far the robot went and not
%   which way. That direction of error is the acceptable one: if our position
%   RMSE comes out comparable to theirs it means something, and if it comes out
%   worse, the projection is a candidate explanation rather than an excuse we
%   have to rule out.
%
%   The alternative worth naming: this project's own Plaza cases DO use a
%   world-frame displacement, taken from dead reckoning, whose heading is an
%   ESTIMATE rather than the truth. That is the standard setup and is fine.
%   These files carry no dead-reckoning track, which is the whole reason the
%   choice above has to be made at all.
%
%   WHAT THE WEAKENING ACTUALLY COST, MEASURED RATHER THAN PREDICTED. The
%   argument above says the projection makes the problem harder and calls that
%   the acceptable direction. It is the acceptable direction, and it is also
%   larger than "harder" suggests, so the number is recorded here instead of
%   being left as a reassurance.
%
%   Every surviving factor is a function of DISTANCES only -- a position prior
%   on the first pose, the pose-to-pose lengths, and the ranges. Distances are
%   invariant under a rigid rotation about the prior, so the projected posterior
%   has a GLOBAL ROTATIONAL GAUGE FREEDOM that the SE2 problem does not have:
%   there, the odometry's heading component pins the orientation. On case1.fg at
%   the fast budget, Slices returned a raw pose RMSE of 77.9 m which rigid
%   alignment onto the truth reduced to 17.1 m, recovering a rotation of -76
%   degrees. Roughly sixty of those seventy-eight metres were gauge and not
%   estimation error. Allowing a reflection changed nothing, so the estimate is
%   rotated and not mirrored.
%
%   TWO CONSEQUENCES, and the second is the one that limits what this case is
%   good for:
%
%     ANY POSE RMSE FROM THIS CASE MUST BE ALIGNED FIRST, via
%     utils.alignTrajectory, and reported with the before-and-after pair so the
%     gauge share is visible. An unaligned number here mostly measures a
%     rotation nobody constrained.
%
%     EVEN ALIGNED, THE COMPARISON IS WEAK. The residual 17 m sits on a track
%     of about 90 m extent, and the estimate placed the second pose 22.6 m from
%     the first where the measured length is 30 m, so the distance constraints
%     themselves are only loosely satisfied. Five chained lengths and ranges to
%     two landmarks leave the configuration poorly determined. This case is
%     therefore useful for running the methods on NF-iSAM's OWN graph structure
%     -- the factors, the ambiguity, the connectivity -- and NOT for putting a
%     position RMSE beside their published one and reading the difference as a
%     difference between methods.
%
%   None of this argues for injecting the true heading after all. It argues that
%   the projected problem is a different, weaker problem, which is what the
%   scope note says and what any figure built from this case has to repeat.
%
%   THE HEADINGS ARE STILL READ, for scoring only, and never reach a factor.
%
%   See also datasets.readFactorGraphFile, datasets.makePlazaCase.

arguments
    path (1,1) string {mustBeFile}
    opts.MaxPoses (1,1) double {mustBePositive} = Inf
    opts.PriorSigma (1,1) double {mustBePositive} = 0.5
end

fg = datasets.readFactorGraphFile(path);

% --- Which poses and landmarks survive the trim ---------------------------
nPose = min(numel(fg.poses), opts.MaxPoses);
poses = fg.poses(1:nPose);
poseNames = string({poses.name});

% A landmark is kept when some surviving pose ranges to it. Keeping the rest
% would leave variables with no factor at all, which the elimination refuses.
ranged = string.empty(1, 0);
for i = 1:numel(fg.ranges)
    if any(poseNames == fg.ranges(i).pose)
        ranged(end+1) = fg.ranges(i).landmark; %#ok<AGROW>
    end
end
for i = 1:numel(fg.ambiguous)
    if any(poseNames == fg.ambiguous(i).pose)
        ranged = [ranged, fg.ambiguous(i).candidates]; %#ok<AGROW>
    end
end
keepLm = ismember(string({fg.landmarks.name}), unique(ranged));
lms = fg.landmarks(keepLm);
lmNames = string({lms.name});

posesTrue = vertcat(poses.xy);
lmTrue    = vertcat(lms.xy);
if isempty(lmTrue), lmTrue = zeros(0, 2); end

% --- Variables ------------------------------------------------------------
pad = 10;
allXY = [posesTrue; lmTrue];
box = [min(allXY(:,1))-pad, max(allXY(:,1))+pad; ...
       min(allXY(:,2))-pad, max(allXY(:,2))+pad];

counter = core.EvalCounter();
vars = core.Variable.empty(1, 0);
for k = 1:numel(poseNames)
    vars(end+1) = core.Variable(poseNames(k), 'Dim', 2, ...
        'Type', "pose", 'Domain', box); %#ok<AGROW>
end
for m = 1:numel(lmNames)
    vars(end+1) = core.Variable(lmNames(m), 'Dim', 2, ...
        'Type', "landmark", 'Domain', box); %#ok<AGROW>
end

% --- Factors --------------------------------------------------------------
factors = core.Factor.empty(1, 0);
projection = struct('priors', 0, 'odometryAsRange', 0, 'ranges', 0, ...
                    'ambiguous', 0, 'droppedHeadingRecords', 0);

% Prior on the first pose's POSITION. The file's prior is over (x, y, theta)
% with a 3x3 covariance; the leading 2x2 block is the positional part and the
% heading row and column are discarded rather than marginalized, which for a
% block-diagonal prior is the same thing and for a correlated one is an
% approximation. Recorded either way.
firstPrior = [];
for i = 1:numel(fg.priors)
    if fg.priors(i).variable == poseNames(1)
        firstPrior = fg.priors(i);
        break
    end
end
if isempty(firstPrior)
    sig = opts.PriorSigma;
    mu = posesTrue(1, :);
else
    sig = sqrt(max(diag(firstPrior.covariance(1:2, 1:2))));
    mu = firstPrior.mean(1:2);
    projection.droppedHeadingRecords = projection.droppedHeadingRecords + 1;
end
factors(end+1) = core.Factor.gaussianVectorUnary(poseNames(1), mu, sig, ...
    'Name', sprintf("f(%s)", poseNames(1)), 'Counter', counter);
projection.priors = 1;

% Odometry, as a DISTANCE between consecutive positions. See the header.
for i = 1:numel(fg.odometry)
    o = fg.odometry(i);
    a = find(poseNames == o.from, 1);
    b = find(poseNames == o.to, 1);
    if isempty(a) || isempty(b)
        continue
    end

    dxy = o.delta(1:2);
    d = norm(dxy);
    sigmaD = localDistanceSigma(dxy, o.covariance(1:2, 1:2));

    factors(end+1) = core.Factor.rangeFactor(o.from, o.to, d, sigmaD, ...
        'Name', sprintf("f(%s,%s)", o.from, o.to), 'Counter', counter); %#ok<AGROW>
    projection.odometryAsRange = projection.odometryAsRange + 1;
    projection.droppedHeadingRecords = projection.droppedHeadingRecords + 1;
end

% Ranges are already rotation-free, so these cross the projection untouched.
for i = 1:numel(fg.ranges)
    r = fg.ranges(i);
    if ~any(poseNames == r.pose) || ~any(lmNames == r.landmark)
        continue
    end
    factors(end+1) = core.Factor.rangeFactor(r.pose, r.landmark, ...
        r.range, r.sigma, ...
        'Name', sprintf("f(%s,%s)", r.pose, r.landmark), ...
        'Counter', counter); %#ok<AGROW>
    projection.ranges = projection.ranges + 1;
end

for i = 1:numel(fg.ambiguous)
    amb = fg.ambiguous(i);
    if ~any(poseNames == amb.pose)
        continue
    end
    cands = amb.candidates(ismember(amb.candidates, lmNames));
    if numel(cands) < 2
        continue
    end
    w = amb.weights(1:numel(cands));
    factors(end+1) = core.Factor.ambiguousRangeFactor(amb.pose, cands, ...
        amb.observation, amb.sigma, w / sum(w), ...
        'Name', sprintf("f(%s,amb%d)", amb.pose, i), ...
        'Counter', counter); %#ok<AGROW>
    projection.ambiguous = projection.ambiguous + 1;
end

graph = core.FactorGraph(vars, factors, counter);

% --- The case struct ------------------------------------------------------
caseData = struct();
caseData.name        = "nfisam_fg";
caseData.variant     = "planar_projection";
caseData.displayName = sprintf("NF-iSAM %s (planar projection)", ...
                               localStem(path));
caseData.engine      = "general";
caseData.graph       = graph;
caseData.counter     = counter;
caseData.eliminationOrder = core.eliminationOrder(graph);
caseData.settings    = struct('maxPoses', opts.MaxPoses, ...
                              'priorSigma', opts.PriorSigma);

% The general engine needs a length scale to judge its own health against: it
% compares the nearest-support lookup distance to the size of the map, and
% without one the run fails several frames down on a missing field rather than
% saying which field. Same shape as makePlazaCase's, with no obstacles, so the
% engine and the figure code both read it unchanged.
caseData.map = struct( ...
    'bounds',   [box(1, 1), box(1, 2), box(2, 1), box(2, 2)], ...
    'blocks',   zeros(0, 4), ...
    'cellSize', 1);

caseData.mission = struct('poseNames', poseNames, ...
                          'landmarkNames', lmNames, ...
                          'domain', caseData.map.bounds(1:2));
% Landmark scoring needs this block, and every landmark kept above was kept
% BECAUSE some surviving pose ranges to it, so all of them are observed. Without
% the block the metrics code has no observation mask, reports landmarkRMSE as
% NaN, and the run looks like it had no landmarks at all -- which is how these
% cases first came back with a pose error and nothing beside it.
caseData.landmarks = struct( ...
    'truePositions', lmTrue, ...
    'names',         lmNames, ...
    'observed',      true(numel(lmNames), 1));

caseData.groundTruth = struct( ...
    'poses',             posesTrue, ...
    'poseNames',         poseNames, ...
    'landmarks',         lmTrue, ...
    'landmarkNames',     lmNames, ...
    'observedLandmarks', true(numel(lmNames), 1), ...
    'headings',          [poses.heading]);

caseData.projection = projection;
caseData.source     = fg.source;

caseData.scopeNote = sprintf([ ...
    'Projected from SE2 onto the plane. %d odometry factor(s) were reduced ' ...
    'to their translation LENGTH as a pose-to-pose range factor, because ' ...
    'their translation is expressed in the from-pose body frame and the only ' ...
    'heading available is the true one. Rotating by it would inject ground ' ...
    'truth and make this problem easier than the SE2 problem NF-iSAM solved; ' ...
    'using the length instead makes it strictly harder, which is the ' ...
    'acceptable direction. %d range factor(s) and %d ambiguous factor(s) ' ...
    'crossed unchanged, being rotation-free already. ' ...
    'CONSEQUENCE, MEASURED: every surviving factor depends on distances ' ...
    'alone, so the posterior is invariant under a rigid rotation about the ' ...
    'prior and carries a global rotational gauge freedom the SE2 problem ' ...
    'does not have. On case1.fg, Slices returned a raw pose RMSE of 77.9 m ' ...
    'that rigid alignment cut to 17.1 m by removing a -76 degree rotation. ' ...
    'Any pose RMSE from this case must therefore be reported after ' ...
    'utils.alignTrajectory and alongside its unaligned value. Even aligned, ' ...
    'the residual is large relative to the 90 m track and the length ' ...
    'constraints are only loosely satisfied, so this case is for running the ' ...
    'methods on NF-iSAM''s own graph structure and NOT for setting a ' ...
    'position RMSE beside their published one; it is not their problem.'], ...
    projection.odometryAsRange, projection.ranges, projection.ambiguous);
end

% =========================================================================
function s = localDistanceSigma(dxy, sigmaXY)
%LOCALDISTANCESIGMA The standard deviation of ||dxy|| under a 2-D covariance.
%   Inputs   DXY the translation, SIGMAXY its 2x2 covariance
%   Outputs  S, one standard deviation on the length
%   Utility  carry the file's stated uncertainty across the projection instead
%            of inventing one.
%
%   The linearized length error is u' * dxy_error where u is the unit
%   direction, so its variance is u' * SIGMAXY * u exactly. For a
%   differential-drive covariance this picks out the along-track term, which is
%   the larger one, rather than averaging it with the smaller cross-track term
%   and understating the uncertainty.
d = norm(dxy);
if d > 0
    u = dxy(:) / d;
    s = sqrt(max(u' * sigmaXY * u, realmin));
    return
end

% A zero-length increment is a pure rotation. It says the robot did not move,
% and the direction is undefined, so there is no along-track term to pick out.
s = sqrt(max(mean(diag(sigmaXY)), realmin));
end

function stem = localStem(path)
%LOCALSTEM The file name without its directory or extension.
%   Inputs   PATH, a file path
%   Outputs  STEM, a string
%   Utility  name the case after the graph it came from.
[~, stem] = fileparts(path);
stem = string(stem);
end
