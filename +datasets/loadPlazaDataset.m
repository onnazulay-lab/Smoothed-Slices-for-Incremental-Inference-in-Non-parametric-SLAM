function dataset = loadPlazaDataset(name, opts)
%LOADPLAZADATASET Plaza1 or Plaza2, parsed into keyframes the app can use.
%
%   Inputs
%     NAME             "Plaza1" or "Plaza2"
%     Root             folder holding the raw files    default data/plaza/raw
%     KeyframeSpacing  metres of travel per keyframe               default 6
%     Calibration      "fit" (default), "none", or [a b] to supply
%     HeadingOffset    "measure" (default), or a fixed offset in radians
%
%   Outputs
%     DATASET  the keyframed sequence: dead-reckoned track, true track,
%              surveyed node positions, per-keyframe ranges, and the
%              calibration and heading decisions that were made
%
%   Utility
%     Turn the raw sequence into the structure the case builder and every
%     method consume, and record the choices made on the way.
%
%   REAL DATA, AND THE ONLY REAL DATA IN THE APP. Both reference papers run
%   on these sequences: a vehicle driving a plaza with wheel odometry and
%   time-of-flight radio ranges to four fixed nodes. Everything else in the
%   app is simulated, which means everything else has a posterior that is
%   correct by construction. Here the noise is whatever the radios did.
%
%   Name-value options:
%     Root             folder holding the raw files    default data/plaza/raw
%     KeyframeSpacing  metres of travel per keyframe               default 6
%     Calibration      "fit" (default), "none", or [a b] to supply
%     HeadingOffset    "measure" (default), or a fixed offset in radians
%
%   WHAT COMES BACK, and why it is keyframed here rather than downstream.
%   The raw sequence is logged at about 10 Hz, and a step of it is a couple
%   of centimetres of travel: far below anything worth making a variable of.
%   A keyframe is the unit the estimator actually reasons about, so the
%   dataset is expressed in keyframes and the raw indices are kept alongside
%   for anyone who wants to go back.
%
%   FOUR THINGS IN THIS DATA WILL WRECK A CASE SILENTLY. All four were
%   measured out of the files rather than assumed, and data/plaza/PROVENANCE.md
%   carries the numbers.
%
%   0. PLAZA1'S SHIPPED DEAD-RECKONED PATH IS NOT ITS OWN ODOMETRY. No
%      integration convention reproduces it -- every one misses by about
%      42 m -- while integrating the increments drifts 4.45 m from truth over
%      1861 m against the shipped path's 36.89 m. Plaza2's shipped path is
%      the mid-heading integral to 0.063 m, so the discrepancy appears on one
%      sequence only, which is the worst way for it to appear. This loader
%      integrates the increments and treats the shipped path as a check.
%
%   1. Odometry integrates at the MID heading -- advance the heading by the
%      full step, translate along the average of the old and new headings.
%      Checked against the dead-reckoned path the distribution ships: 0.06 m
%      of disagreement over Plaza2's 1354 m, against 0.55 m and 0.44 m for
%      the two obvious alternatives. Half a metre of systematic error over
%      four thousand steps does not read as a bug. It reads as drift, and
%      drift is the subject of a range-only case.
%
%   2. Plaza2's ground-truth HEADING is offset by pi from its direction of
%      travel and Plaza1's is not. Course between consecutive true positions
%      agrees with the recorded heading on 100% of Plaza1's moving steps and
%      on 0% of Plaza2's until pi is added. The offset is therefore MEASURED
%      here, per sequence, rather than written down: a third sequence with a
%      third convention gets the same treatment, and the number is reported
%      on the dataset instead of hiding in a constant.
%
%   3. The landmark ids are 0, 1, 5 and 6, not 1 to 4. Indexing the surveyed
%      table by id returns the wrong landmark for id 0 and nothing at all for
%      the others. Ids are carried as labels and never as indices.
%
%   RANGE CALIBRATION follows the NF-iSAM paper, which fits and subtracts an
%   affine distance bias: r_cal = r_raw - (a*r_raw + b). Fitted here against
%   ground truth, which is worth stating plainly -- it is a preprocessing
%   step that uses truth, exactly as the paper's does. It is applied to every
%   method identically and can be switched off, and the raw range is kept on
%   every reading so the effect is inspectable rather than baked in. Measured:
%   the raw ranges are biased long by about 2.8 m, and calibration removes the
%   bias and leaves residuals with a standard deviation near 0.51 m. The two
%   sequences agree on the coefficients to three decimal places, which is the
%   evidence that the model is describing the radios and not the trajectory.
%
%   See also datasets.makePlazaCase, data/plaza/PROVENANCE.md.

arguments
    name (1,1) string {mustBeMember(name, ["Plaza1", "Plaza2"])}
    opts.Root (1,1) string = ""
    opts.KeyframeSpacing (1,1) double {mustBePositive} = 6
    opts.Calibration = "fit"
    opts.HeadingOffset = "measure"
end

root = opts.Root;
if root == "", root = localDefaultRoot(); end

file = fullfile(root, name + "_.mat");
if ~isfile(file)
    error('datasets:loadPlazaDataset:missingFile', ...
        ['Cannot find %s.\nThe Plaza sequences live in data/plaza/raw and ' ...
         'their origin is recorded in data/plaza/PROVENANCE.md.'], file);
end

raw = load(file);
localAssertShape(raw, file);

% The surveyed nodes, ordered by id so that the landmark list is stable
% across sequences and runs. The ids stay attached as LABELS.
TL  = sortrows(raw.TL, 1);
ids = TL(:,1).';

% --- Ground truth ---------------------------------------------------------
gtT   = raw.GT(:,1);
gtXY  = raw.GT(:,2:3);
gtTh  = raw.GT(:,4);

headingOffset = opts.HeadingOffset;
if isstring(headingOffset) || ischar(headingOffset)
    headingOffset = localMeasureHeadingOffset(gtXY, gtTh);
end
gtTh = gtTh + headingOffset;

% --- Dead reckoning, integrated here rather than taken from the file ------
% THE SHIPPED DEAD-RECKONED PATH IS NOT USABLE FOR PLAZA1. Its position
% columns are not the integral of its own odometry increments under any
% convention: mid-heading, turn-first and move-first all land about 42 m away
% from it over the run. The increments are not the problem -- integrating
% them drifts only 4.45 m from truth over 1861 m, while the shipped path ends
% 36.89 m out. Plaza2 has no such trouble; there the shipped path IS the
% mid-heading integral, to 0.063 m.
%
% Whatever produced Plaza1's path columns, it was not Plaza1's odometry. So
% the increments are the source of truth here and the shipped path is used
% only as the cross-check that caught this. A case built on it would have
% carried a 42 m disagreement between the odometry the estimator is given and
% the track it is scored beside, on one sequence but not the other.
%
% The heading column, by contrast, is exactly the cumulative sum of the
% increments' heading changes on BOTH sequences, to 1e-13 rad.
anchorPose = [gtXY(1,:), gtTh(1)];
[drXY, drTh] = localIntegrate(raw.DR, anchorPose);

% --- Keyframes ------------------------------------------------------------
% Cut on travelled distance rather than on time. The vehicle stops and turns
% in place during the run, and a time-based cut spends keyframes on the
% stops -- poses with no odometry between them, which is a rank problem
% dressed up as a mission.
arc  = [0; cumsum(vecnorm(diff(drXY), 2, 2))];

kf   = localKeyframeIndices(arc, opts.KeyframeSpacing);
nKf  = numel(kf);

% --- Calibration ----------------------------------------------------------
tdT   = raw.TD(:,1);
tdId  = raw.TD(:,3);
rRaw  = raw.TD(:,4);

% True range at each reading, by interpolating the true path to the reading's
% timestamp. Used for calibration and kept per reading as a diagnostic.
truthAt = [interp1(gtT, gtXY(:,1), tdT, 'linear', 'extrap'), ...
           interp1(gtT, gtXY(:,2), tdT, 'linear', 'extrap')];
lmRow   = localRowOfId(tdId, ids);
rTrue   = vecnorm(truthAt - TL(lmRow, 2:3), 2, 2);

[coef, calNote] = localCalibration(opts.Calibration, rRaw, rTrue);
rCal  = rRaw - (coef(1) * rRaw + coef(2));
resid = rCal - rTrue;

calibration = struct( ...
    'a', coef(1), 'b', coef(2), ...
    'model', "r_cal = r_raw - (a * r_raw + b)", ...
    'residualSigma', std(resid), ...
    'residualMean', mean(resid), ...
    'rawBias', mean(rRaw - rTrue), ...
    'rawSigma', std(rRaw - rTrue), ...
    'source', calNote);

% --- Readings, assigned to keyframes --------------------------------------
% Every reading belongs to the keyframe nearest in time. Nearest rather than
% "the interval it falls in" because a reading taken between two keyframes is
% a measurement from a pose that is not in the graph either way, and the
% nearest keyframe is the smaller lie.
[~, owner] = min(abs(tdT.' - gtT(kf)), [], 1);
owner = owner(:);

ranges = struct( ...
    'poseId',        num2cell(owner), ...
    'landmarkId',    num2cell(tdId), ...
    'measuredRange', num2cell(rCal), ...
    'rawRange',      num2cell(rRaw), ...
    'trueRange',     num2cell(rTrue), ...
    'sigma',         num2cell(repmat(calibration.residualSigma, size(rCal))), ...
    'timestamp',     num2cell(tdT));
ranges = reshape(ranges, 1, []);

% --- Odometry between keyframes -------------------------------------------
% Carried in the BODY frame of the leg's first keyframe, plus the heading
% change across the leg. Body frame rather than world because the world frame
% of a window depends on where that window is anchored, and an odometry
% measurement that has already committed to one anchor is not a measurement
% any more -- it is a measurement plus somebody's guess about where the run
% started. A window rebuilds the chain from its own anchor; see
% makePlazaCase.
odom = struct('fromPose', {}, 'toPose', {}, 'deltaLocal', {}, 'dTheta', {}, ...
              'delta', {}, 'drHeading', {}, 'arcLength', {});
for k = 2:nKf
    i0 = kf(k-1);
    i1 = kf(k);
    world = drXY(i1,:) - drXY(i0,:);
    c = cos(drTh(i0)); s = sin(drTh(i0));
    odom(end+1) = struct( ...
        'fromPose',   k-1, ...
        'toPose',     k, ...
        'deltaLocal', [ c*world(1) + s*world(2), -s*world(1) + c*world(2)], ...
        'dTheta',     drTh(i1) - drTh(i0), ...
        'delta',      world, ...
        'drHeading',  drTh(i0), ...
        'arcLength',  arc(i1) - arc(i0)); %#ok<AGROW>
end

% --- The bundle -----------------------------------------------------------
dataset = struct();
dataset.name       = name;
dataset.steps      = 1:nKf;
dataset.odom       = odom;
dataset.ranges     = ranges;
dataset.landmarkIds = ids;
dataset.calibration = calibration;

dataset.gt = struct( ...
    'poses',     gtXY(kf,:), ...
    'headings',  gtTh(kf), ...
    'landmarks', TL(:,2:3), ...
    'landmarkIds', ids, ...
    'headingOffset', headingOffset, ...
    'fullPath',  gtXY, ...
    'fullTime',  gtT);

dataset.deadReckoned = struct( ...
    'poses',    drXY(kf,:), ...
    'headings', drTh(kf), ...
    'fullPath', drXY, ...
    'shippedPath', raw.DRp(:,2:3), ...
    'note', "integrated from DR at the mid heading; the shipped DRp is kept only as a cross-check");

dataset.keyframes = struct( ...
    'rawIndex',  kf, ...
    'time',      gtT(kf).', ...
    'arcLength', arc(kf).', ...
    'spacing',   opts.KeyframeSpacing);

dataset.scenarios = struct( ...
    'association', ["known", "ambiguous"], ...
    'note', "ambiguous wipes landmark ids and gives every reading a candidate set");

dataset.source = struct( ...
    'file', file, ...
    'provenance', fullfile(fileparts(root), 'PROVENANCE.md'), ...
    'numRawSteps', size(raw.DR, 1), ...
    'pathLength', arc(end));
end

% =========================================================================
function root = localDefaultRoot()
%LOCALDEFAULTROOT data/plaza/raw, found relative to this file.
%   Inputs   none
%   Outputs  ROOT, an absolute path
%   Utility  find the data without depending on the current directory.
here = fileparts(mfilename('fullpath'));           % src/+datasets
root = fullfile(fileparts(fileparts(here)), 'data', 'plaza', 'raw');
end

% =========================================================================
function localAssertShape(raw, file)
%LOCALASSERTSHAPE The five variables, with the widths they must have.
%   Inputs   RAW the loaded struct, FILE its name for the message
%   Outputs  none; errors when a variable is missing or the wrong width
%   Utility  reject a malformed file at the file.
%
%   Checked here because the failure otherwise arrives much later as a size
%   mismatch inside a factor, pointing at the graph rather than at the file.
need = struct('DR', 3, 'DRp', 4, 'GT', 4, 'TD', 4, 'TL', 3);
f = fieldnames(need);
for i = 1:numel(f)
    if ~isfield(raw, f{i})
        error('datasets:loadPlazaDataset:badFile', ...
            '%s has no %s. Expected DR, DRp, GT, TD and TL.', file, f{i});
    end
    if size(raw.(f{i}), 2) ~= need.(f{i})
        error('datasets:loadPlazaDataset:badFile', ...
            '%s: %s has %d columns, expected %d.', ...
            file, f{i}, size(raw.(f{i}), 2), need.(f{i}));
    end
end
if size(raw.GT, 1) ~= size(raw.DRp, 1)
    error('datasets:loadPlazaDataset:badFile', ...
        '%s: GT has %d rows and DRp has %d. They share a time base.', ...
        file, size(raw.GT, 1), size(raw.DRp, 1));
end
end

% =========================================================================
function [xy, th] = localIntegrate(DR, anchor)
%LOCALINTEGRATE The odometry increments, integrated at the MID heading.
%   Inputs   DR the [time, distance, heading change] rows, ANCHOR the
%            [x y theta] the chain starts from
%   Outputs  XY the integrated track, TH the heading at each step
%   Utility  produce the dead-reckoned track the case's odometry comes from.
%
%   Mid heading: advance the heading by the full step, translate along the
%   average of the old heading and the new one. Measured against the path
%   Plaza2 ships, over 1354 m: 0.063 m for this convention, 0.552 m for
%   turning first and 0.444 m for translating first. The wrong choice is a
%   systematic error that accumulates in the same direction as real drift,
%   which is why it survives inspection.
n  = size(DR, 1);
xy = zeros(n+1, 2);
th = zeros(n+1, 1);
xy(1,:) = anchor(1:2);
th(1)   = anchor(3);

for k = 1:n
    mid = th(k) + DR(k,3)/2;
    xy(k+1,:) = xy(k,:) + DR(k,2) * [cos(mid), sin(mid)];
    th(k+1)   = th(k) + DR(k,3);
end
end

% =========================================================================
function offset = localMeasureHeadingOffset(xy, th)
%LOCALMEASUREHEADINGOFFSET Zero, or pi, decided by the data.
%   Inputs   XY the track, TH the recorded headings
%   Outputs  OFFSET, 0 or pi
%   Utility  settle the heading convention by measurement rather than by
%           assumption, since guessing it wrong reverses the whole track.
%   Compares the recorded heading against the direction actually travelled,
%   over the steps where the vehicle moved far enough for that direction to
%   mean something. Plaza1 comes out at zero and Plaza2 at pi.
%
%   Rounded to a multiple of pi ON PURPOSE. The residual after the offset is
%   a couple of hundredths of a radian, and that residual is real sensor
%   behaviour: absorbing it here would be fitting the vehicle's heading to
%   its own trajectory, which is a different and much less honest thing than
%   undoing a convention.
v = diff(xy);
moved = vecnorm(v, 2, 2) > 0.05;
if ~any(moved), offset = 0; return, end

course = atan2(v(moved,2), v(moved,1));
recorded = th([moved; false]);
err = angle(exp(1i * (course - recorded)));

offset = pi * round(median(err) / pi);
end

% =========================================================================
function kf = localKeyframeIndices(arc, spacing)
%LOCALKEYFRAMEINDICES First index at or past each multiple of SPACING.
%   Inputs   ARC the cumulative travelled distance, SPACING metres per keyframe
%   Outputs  KF, the chosen indices
%   Utility  keyframe by distance travelled rather than by time, so a pause
%           does not produce a run of identical poses.
kf = zeros(1, 0);
next = 0;
for i = 1:numel(arc)
    if arc(i) >= next
        kf(end+1) = i; %#ok<AGROW>
        next = arc(i) + spacing;
    end
end
end

% =========================================================================
function row = localRowOfId(queryIds, ids)
%LOCALROWOFID Row in the surveyed table for each landmark id.
%   Inputs   QUERYIDS the ids wanted, IDS the table's id column
%   Outputs  ROW, one row index per query
%   Utility  map an id to a row explicitly.
%   The ids are 0, 1, 5 and 6. This function exists so that no caller is
%   tempted to write TL(id,:), which for id 0 is an error and for id 5 is
%   either out of bounds or, worse, the wrong landmark.
[found, row] = ismember(queryIds, ids);
if ~all(found)
    bad = unique(queryIds(~found));
    error('datasets:loadPlazaDataset:unknownLandmark', ...
        'Readings reference landmark id(s) %s, which are not surveyed.', ...
        mat2str(bad(:).'));
end
end

% =========================================================================
function [coef, note] = localCalibration(spec, rRaw, rTrue)
%LOCALCALIBRATION The affine bias model, fitted, supplied or switched off.
%   Inputs   SPEC the Calibration option, RRAW the measured ranges, RTRUE the
%            surveyed distances
%   Outputs  COEF the [a b] coefficients, NOTE what was done and why
%   Utility  remove the radios' known range bias, and record which of the
%           three routes produced the coefficients.
if isnumeric(spec)
    if numel(spec) ~= 2
        error('datasets:loadPlazaDataset:badCalibration', ...
            'Supplied calibration must be [a b]; got %d value(s).', numel(spec));
    end
    coef = spec(:);
    note = "supplied";
    return
end

switch string(spec)
    case "none"
        coef = [0; 0];
        note = "uncalibrated: ranges are biased long by about 2.8 m";
    case "fit"
        A = [rRaw, ones(size(rRaw))];
        coef = A \ (rRaw - rTrue);
        note = "fitted against ground truth, as the NF-iSAM paper does";
    otherwise
        error('datasets:loadPlazaDataset:badCalibration', ...
            'Calibration must be "fit", "none" or [a b]; got "%s".', spec);
end
end
