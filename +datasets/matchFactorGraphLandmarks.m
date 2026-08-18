function map = matchFactorGraphLandmarks(fg, dataset, opts)
%MATCHFACTORGRAPHLANDMARKS Pair a .fg file's landmarks with the survey ids.
%
%   Inputs
%     fg           struct from datasets.readFactorGraphFile
%     dataset      "Plaza1" | "Plaza2", or a struct from
%                  datasets.loadPlazaDataset
%     Tolerance    metres; a pairing further apart than this is refused
%                                                                 default 0.05
%
%   Outputs
%     map          table with one row per landmark in FG:
%                    fgName      the name in the file, e.g. "L2"
%                    surveyId     the surveyed node id, e.g. 6
%                    surveyRow    row of that id in dataset.gt.landmarks
%                    distance     metres between the two positions
%
%   Utility
%     Lets a result measured on an NF-iSAM graph be compared with one measured
%     on this project's loader, by saying which landmark is which.
%
%   MATCHED BY POSITION, NEVER BY ORDER, because the orders disagree. Measured
%   on Plaza1EFG the four landmarks are the same four surveyed nodes to the
%   centimetre, but L0 L1 L2 L3 correspond to survey ids 0, 1, 6, 5 -- the last
%   two exchanged. Mapping L0..L3 onto [0 1 5 6] positionally, which is the
%   obvious thing to do and looks right, swaps two landmarks and produces a
%   landmark RMSE that is wrong by the distance between them without any
%   symptom that says so. Positions are unambiguous and orders are not.
%
%   See also datasets.readFactorGraphFile, datasets.loadPlazaDataset.

arguments
    fg (1,1) struct
    dataset
    opts.Tolerance (1,1) double {mustBePositive} = 0.05
end

if isstruct(dataset)
    data = dataset;
else
    data = datasets.loadPlazaDataset(string(dataset));
end

theirs = vertcat(fg.landmarks.xy);
ours   = data.gt.landmarks;
ids    = data.landmarkIds(:);

n = size(theirs, 1);
if n ~= size(ours, 1)
    error('datasets:matchFactorGraphLandmarks:countMismatch', ...
        ['The graph carries %d landmarks and %s surveys %d, so they are not ' ...
         'the same site.'], n, data.name, size(ours, 1));
end

D = hypot(theirs(:,1) - ours(:,1).', theirs(:,2) - ours(:,2).');
[distance, row] = min(D, [], 2);

% Distance FIRST. A graph in another frame usually also collides two landmarks
% onto one node, so checking one-to-one first would report a duplicate pairing
% and send the reader looking for a duplicate that is not the problem.
if any(distance > opts.Tolerance)
    error('datasets:matchFactorGraphLandmarks:tooFar', ...
        ['Landmark %s is %.3f m from its nearest surveyed node, past the ' ...
         '%.3f m tolerance. These are probably not the same site, or the ' ...
         'graph is in a different frame.'], ...
        fg.landmarks(find(distance > opts.Tolerance, 1)).name, ...
        max(distance), opts.Tolerance);
end

% One-to-one, or the pairing is not a correspondence. Two graph landmarks
% claiming the same surveyed node pass every distance check individually.
if numel(unique(row)) ~= n
    error('datasets:matchFactorGraphLandmarks:notOneToOne', ...
        ['Two of the graph''s landmarks match the same surveyed node, so ' ...
         'the pairing is not a correspondence.']);
end

map = table(string({fg.landmarks.name}).', ids(row), row, distance, ...
    'VariableNames', {'fgName', 'surveyId', 'surveyRow', 'distance'});
end
