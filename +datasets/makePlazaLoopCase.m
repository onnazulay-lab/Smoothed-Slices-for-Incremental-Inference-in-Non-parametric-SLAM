function [caseData, loop] = makePlazaLoopCase(opts)
%MAKEPLAZALOOPCASE A Plaza case whose window is chosen to contain a loop closure.
%
%   Inputs
%     Dataset          "Plaza1" | "Plaza2"                    default "Plaza1"
%     Laps             how many circuits the window should span. Circuits only;
%                      Plaza2 has none and rejects anything but 1   default 1
%     Instance         which loop to take, 1 = the first available. Stage 3
%                      wants several representative Plaza2 closures, and this
%                      is how they are asked for                    default 1
%     ReturnRadius     metres, forwarded to datasets.plazaLoopSpan   default 8
%     MinGap           keyframes, forwarded likewise                default 10
%     CaseArgs         cell of name-value pairs forwarded verbatim to
%                      datasets.makePlazaCase, e.g.
%                      {'EliminationOrder', "automatic", 'Seed', 3}. A cell
%                      rather than loose pairs so that this function never has
%                      to restate makePlazaCase's option list and drift from
%                      it. NumPoses, WindowStart, MaxLandmarks and MaxVariables
%                      are derived here and are rejected if passed  default {}
%
%   Outputs
%     caseData         a case as datasets.makePlazaCase returns one
%     loop             struct describing the closure the window contains:
%                      isCircuit, startKeyframe, endKeyframe, numKeyframes,
%                      pathLength, numInstances, span (the full measurement)
%
%   Utility
%     Builds the case a loop-closure study needs. The chooser inside
%     makePlazaCase optimises for how well constrained a window is and has no
%     notion of returning to a place, so left to itself it will not produce a
%     window containing a closure however large NumPoses gets. This measures
%     the loop first and then asks for exactly that window.
%
%   WHY IT SETS THE TWO CAPS ITSELF. MaxLandmarks defaults to 2 and
%   MaxVariables to 13, both below what any loop window needs -- one Plaza1 lap
%   is 17 poses and sees all four surveyed landmarks, so 21 variables. Left at
%   their defaults every rule in the chooser fails, and it falls back to the
%   first window with any reading at all: a relaxed window that contains no
%   loop, announced by a warning, which is the opposite of what was asked for.
%   So they are derived here, and the caller is told the resulting count in
%   caseData.settings rather than having to work it out.
%
%   THIS IS A CONSTRUCTOR, NOT A CLAIM THAT THE ENGINE HANDLES IT. 21 variables
%   is well past the regime the method is measured on, and MaxVariables exists
%   to mark that line. Building the case is the part this function is
%   responsible for; whether the posterior is any good at that size is a
%   measurement, and it belongs to whoever runs it.
%
%   See also datasets.plazaLoopSpan, datasets.makePlazaCase.

arguments
    opts.Dataset (1,1) string {mustBeMember(opts.Dataset, ["Plaza1","Plaza2"])} = "Plaza1"
    opts.Laps (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.Instance (1,1) double {mustBeInteger, mustBePositive} = 1
    opts.ReturnRadius (1,1) double {mustBePositive} = 8
    opts.MinGap (1,1) double {mustBeInteger, mustBePositive} = 10
    opts.KeyframeSpacing (1,1) double {mustBePositive} = 6
    opts.CaseArgs (1,:) cell = {}
end

forwarded = opts.CaseArgs;
localRejectDerived(forwarded);

data = datasets.loadPlazaDataset(opts.Dataset, ...
    'KeyframeSpacing', opts.KeyframeSpacing);
span = datasets.plazaLoopSpan(data, 'ReturnRadius', opts.ReturnRadius, ...
    'MinGap', opts.MinGap);

[w0, K, nInstances] = localLoopWindow(span, opts);

% All four surveyed landmarks are fair game: a loop window is long enough to
% see them all, and capping at two would reject every window that closes.
nLm = numel(data.landmarkIds);

caseData = datasets.makePlazaCase('Dataset', opts.Dataset, ...
    'KeyframeSpacing', opts.KeyframeSpacing, ...
    'NumPoses', K, 'WindowStart', w0, ...
    'MaxLandmarks', nLm, 'MaxVariables', K + nLm, forwarded{:});

arc = data.keyframes.arcLength(:);
loop = struct('isCircuit', span.isCircuit, 'startKeyframe', w0, ...
    'endKeyframe', w0 + K - 1, 'numKeyframes', K, ...
    'pathLength', arc(w0 + K - 1) - arc(w0), ...
    'numInstances', nInstances, 'span', span);
end

% =========================================================================
function [w0, K, nInstances] = localLoopWindow(span, opts)
%LOCALLOOPWINDOW Where the requested loop starts and how many keyframes it spans.
%   Inputs   span   as datasets.plazaLoopSpan returns
%            opts   the caller's Dataset, Laps and Instance
%   Outputs  w0     first keyframe of the window
%            K      keyframes in it, both endpoints included
%            nInstances  how many such loops the sequence offers
%   Utility  A circuit and a lawnmower are indexed differently -- laps around
%            a reference in one case, self-crossings in the other -- and this
%            is the only place that difference has to be handled.
if span.isCircuit
    % Lap boundaries are the passes THEMSELVES, and keyframe 1 is not one of
    % them. On Plaza1 the run starts off the circuit and takes 172 m to reach
    % it, so a window from keyframe 1 to the first pass is 1.7 laps and calling
    % it one lap would misreport the very quantity this function exists to get
    % right. Between consecutive passes is a lap; before the first is not.
    starts = span.passes(:).';
    nInstances = numel(starts) - opts.Laps;
    if nInstances < 1
        error('datasets:makePlazaLoopCase:notEnoughLaps', ...
            '%s offers %d complete lap(s) and %d were asked for.', ...
            opts.Dataset, max(0, numel(starts) - 1), opts.Laps);
    end
    localCheckInstance(opts, nInstances);
    w0 = starts(opts.Instance);
    K  = starts(opts.Instance + opts.Laps) - w0 + 1;
    return
end

% No circuit, so there are no laps to stack and Laps must be 1.
if opts.Laps > 1
    error('datasets:makePlazaLoopCase:noCircuit', ...
        ['%s never returns to where it began, so it has no laps to span. ' ...
         'Ask for Laps = 1, which takes one self-crossing instead.'], ...
        opts.Dataset);
end
if isempty(span.revisits)
    error('datasets:makePlazaLoopCase:noClosure', ...
        '%s offers no loop closure at all at this return radius.', opts.Dataset);
end

% Representative rather than shortest. The minimum over starts is a floor
% statistic -- see plazaLoopSpan -- so the closures are ordered by how near
% their span is to the median and taken from the middle outwards.
R = span.revisits;
[~, order] = sort(abs(R.numKeyframes - median(R.numKeyframes)));

% AND DISTINCT, which the ordering alone does not give. Consecutive keyframes
% each open their own closure of almost the same length, so the rows nearest
% the median are near-duplicates: on Plaza2 the first three were windows
% starting at keyframes 2, 3 and 4, overlapping in 33 of their 34 keyframes.
% Asking for three representative loops and getting one loop three times is
% the failure this guards. Windows are accepted greedily, best first, and only
% if they do not overlap one already taken.
picked = zeros(0, 2);
for r = order(:).'
    a = R.fromKeyframe(r);
    b = R.toKeyframe(r);
    if isempty(picked) || all(b <= picked(:,1) | a >= picked(:,2))
        picked(end+1, :) = [a b];             %#ok<AGROW>
    end
end

nInstances = size(picked, 1);
localCheckInstance(opts, nInstances);
w0 = picked(opts.Instance, 1);
K  = picked(opts.Instance, 2) - w0 + 1;
end

% =========================================================================
function localCheckInstance(opts, nInstances)
%LOCALCHECKINSTANCE Reject an Instance past what the sequence offers.
%   Inputs   opts, nInstances
%   Outputs  none; errors if out of range
%   Utility  Indexing past the end would otherwise be a bare MATLAB index
%            error naming a local variable the caller has never heard of.
if opts.Instance > nInstances
    error('datasets:makePlazaLoopCase:noSuchInstance', ...
        ['%s offers %d loop window(s) at these settings and instance %d ' ...
         'was asked for.'], opts.Dataset, nInstances, opts.Instance);
end
end

% =========================================================================
function localRejectDerived(forwarded)
%LOCALREJECTDERIVED Refuse passthrough arguments this function derives.
%   Inputs   forwarded  name-value cell bound for makePlazaCase
%   Outputs  none; errors on a conflict
%   Utility  Forwarding NumPoses here would be accepted by makePlazaCase and
%            then overridden, giving a case that quietly ignores the pose count
%            it was asked for. Refusing is the only reading that cannot mislead.
derived = ["NumPoses", "WindowStart", "MaxLandmarks", "MaxVariables"];
if mod(numel(forwarded), 2) ~= 0
    error('datasets:makePlazaLoopCase:unpairedCaseArgs', ...
        ['CaseArgs holds %d entries, so it is not a list of name-value ' ...
         'pairs.'], numel(forwarded));
end
names = forwarded(1:2:end);
if ~all(cellfun(@(n) ischar(n) || (isstring(n) && isscalar(n)), names))
    error('datasets:makePlazaLoopCase:badCaseArgName', ...
        'Every odd entry of CaseArgs must be an option name.');
end
names = string(names);
clash = intersect(names, derived, 'stable');
if ~isempty(clash)
    error('datasets:makePlazaLoopCase:derivedArgument', ...
        ['%s is derived from the loop measurement and cannot be supplied. ' ...
         'Use datasets.makePlazaCase directly to choose the window by hand.'], ...
        strjoin(clash, ', '));
end
end
