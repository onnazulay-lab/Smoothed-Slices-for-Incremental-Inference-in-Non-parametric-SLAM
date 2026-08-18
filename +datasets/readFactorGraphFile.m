function fg = readFactorGraphFile(path)
%READFACTORGRAPHFILE Parse an NF-iSAM .fg factor graph file.
%
%   Inputs
%     path         path to a factor_graph.fg file as shipped by NF-iSAM
%                  (MarineRoboticsGroup/NF-iSAM, MIT)
%
%   Outputs
%     fg           struct with fields
%       poses        struct array: name, xy (1x2), heading
%       landmarks    struct array: name, xy (1x2)
%       priors       struct array: variable, mean (1x3), covariance (3x3)
%       odometry     struct array: from, to, delta (1x3), covariance (3x3)
%       ranges       struct array: pose, landmark, range, sigma
%       ambiguous    struct array: pose, candidates (string), weights,
%                    binaryKind, observation, sigma
%       source       struct: path, numLines, counts per record kind
%
%   Utility
%     Reads the problem instances the NF-iSAM paper reports on, so this
%     project's methods can be run on THEIR graph rather than on one rebuilt
%     from the same raw survey. Rebuilding agrees only up to every convention
%     in between -- keyframing, calibration, heading offset, which readings are
%     admitted -- and those are exactly what makes two papers' numbers
%     incomparable.
%
%   THE GRAMMAR, WHICH IS POSITIONAL AND UNDOCUMENTED. Six record kinds appear
%   across the released files:
%
%     Variable Pose SE2 <name> x y theta
%     Variable Landmark R2 <name> x y
%     Factor UnarySE2ApproximateGaussianPriorFactor <var> x y theta
%            covariance <9 values, row major>
%     Factor SE2RelativeGaussianLikelihoodFactor <from> <to> dx dy dtheta
%            covariance <9 values, row major>
%     Factor SE2R2RangeGaussianLikelihoodFactor <pose> <landmark> range sigma
%     Factor AmbiguousDataAssociationFactor Observer <pose> Observed <name>...
%            Weights <w>... Binary <kind> Observation <value> Sigma <sigma>
%
%   Only the last is keyword-delimited; the rest are fixed-arity. An unknown
%   record is an ERROR rather than a skipped line: a factor graph missing
%   factors nobody noticed still eliminates, still produces a posterior, and is
%   quietly about a different problem.
%
%   POSES ARE SE2 HERE AND PLANAR EVERYWHERE ELSE IN THIS PROJECT. The heading
%   is parsed and returned rather than dropped, so that the decision to ignore
%   it belongs to whoever builds a case from this, not to the reader.
%
%   See also datasets.makePlazaCase, datasets.loadPlazaDataset.

arguments
    path (1,1) string {mustBeFile}
end

lines = readlines(path);
lines = strtrim(lines);
lines = lines(strlength(lines) > 0);

poses     = struct('name', {}, 'xy', {}, 'heading', {});
landmarks = struct('name', {}, 'xy', {});
priors    = struct('variable', {}, 'mean', {}, 'covariance', {});
odometry  = struct('from', {}, 'to', {}, 'delta', {}, 'covariance', {});
ranges    = struct('pose', {}, 'landmark', {}, 'range', {}, 'sigma', {});
ambiguous = struct('pose', {}, 'candidates', {}, 'weights', {}, ...
                   'binaryKind', {}, 'observation', {}, 'sigma', {});

for i = 1:numel(lines)
    tok = split(lines(i));
    tok = tok(strlength(tok) > 0);

    switch tok(1)
        case "Variable"
            switch tok(2)
                case "Pose"
                    localExpect(tok, 7, i, lines(i));
                    poses(end+1) = struct('name', tok(4), ...
                        'xy', localNums(tok(5:6), i), ...
                        'heading', localNums(tok(7), i));               %#ok<AGROW>
                case "Landmark"
                    localExpect(tok, 6, i, lines(i));
                    landmarks(end+1) = struct('name', tok(4), ...
                        'xy', localNums(tok(5:6), i));                  %#ok<AGROW>
                otherwise
                    localUnknown(i, lines(i));
            end

        case "Factor"
            switch tok(2)
                case "UnarySE2ApproximateGaussianPriorFactor"
                    localExpect(tok, 16, i, lines(i));
                    localKeyword(tok(7), "covariance", i, lines(i));
                    priors(end+1) = struct('variable', tok(3), ...
                        'mean', localNums(tok(4:6), i), ...
                        'covariance', localCov(tok(8:16), i));          %#ok<AGROW>

                case "SE2RelativeGaussianLikelihoodFactor"
                    localExpect(tok, 17, i, lines(i));
                    localKeyword(tok(8), "covariance", i, lines(i));
                    odometry(end+1) = struct('from', tok(3), 'to', tok(4), ...
                        'delta', localNums(tok(5:7), i), ...
                        'covariance', localCov(tok(9:17), i));          %#ok<AGROW>

                case "SE2R2RangeGaussianLikelihoodFactor"
                    localExpect(tok, 6, i, lines(i));
                    ranges(end+1) = struct('pose', tok(3), 'landmark', tok(4), ...
                        'range', localNums(tok(5), i), ...
                        'sigma', localNums(tok(6), i));                 %#ok<AGROW>

                case "AmbiguousDataAssociationFactor"
                    ambiguous(end+1) = localAmbiguous(tok, i, lines(i)); %#ok<AGROW>

                otherwise
                    localUnknown(i, lines(i));
            end

        otherwise
            localUnknown(i, lines(i));
    end
end

fg = struct('poses', poses, 'landmarks', landmarks, 'priors', priors, ...
    'odometry', odometry, 'ranges', ranges, 'ambiguous', ambiguous, ...
    'source', struct('path', path, 'numLines', numel(lines), ...
        'counts', struct('poses', numel(poses), 'landmarks', numel(landmarks), ...
            'priors', numel(priors), 'odometry', numel(odometry), ...
            'ranges', numel(ranges), 'ambiguous', numel(ambiguous))));
end

% =========================================================================
function a = localAmbiguous(tok, i, raw)
%LOCALAMBIGUOUS Parse one AmbiguousDataAssociationFactor record.
%   Inputs   tok  whitespace-split tokens of the line
%            i    line number, for errors
%            raw  the line itself, for errors
%   Outputs  a    struct: pose, candidates, weights, binaryKind,
%                 observation, sigma
%   Utility  This record is the only keyword-delimited one, and the candidate
%            and weight lists are variable length, so the sections are located
%            by keyword rather than counted off from the start.
keys = ["Observer", "Observed", "Weights", "Binary", "Observation", "Sigma"];
at = zeros(1, numel(keys));
for k = 1:numel(keys)
    hit = find(tok == keys(k));
    if numel(hit) ~= 1
        error('datasets:readFactorGraphFile:ambiguousLayout', ...
            ['Line %d: expected exactly one "%s" keyword in an ambiguous ' ...
             'data association factor, found %d.\n  %s'], ...
            i, keys(k), numel(hit), raw);
    end
    at(k) = hit;
end
if ~issorted(at, 'strictascend')
    error('datasets:readFactorGraphFile:ambiguousOrder', ...
        'Line %d: ambiguous factor keywords are out of order.\n  %s', i, raw);
end

candidates = tok(at(2)+1 : at(3)-1);
weights    = localNums(tok(at(3)+1 : at(4)-1), i);
if numel(candidates) ~= numel(weights)
    error('datasets:readFactorGraphFile:ambiguousMismatch', ...
        ['Line %d: %d candidate landmarks but %d weights. A mismatch here ' ...
         'would silently reweight the association.\n  %s'], ...
        i, numel(candidates), numel(weights), raw);
end

a = struct('pose', tok(at(1)+1), 'candidates', {candidates(:).'}, ...
    'weights', weights(:).', 'binaryKind', tok(at(4)+1), ...
    'observation', localNums(tok(at(5)+1), i), ...
    'sigma', localNums(tok(at(6)+1), i));
end

% =========================================================================
function localExpect(tok, n, i, raw)
%LOCALEXPECT Reject a fixed-arity record of the wrong length.
%   Inputs   tok, n (expected token count), i (line number), raw (the line)
%   Outputs  none; errors on mismatch
%   Utility  These records are positional, so a wrong count means every field
%            after the gap is read from the wrong column.
if numel(tok) ~= n
    error('datasets:readFactorGraphFile:arity', ...
        'Line %d: expected %d tokens for a %s record, found %d.\n  %s', ...
        i, n, tok(min(2, numel(tok))), numel(tok), raw);
end
end

% =========================================================================
function localKeyword(got, want, i, raw)
%LOCALKEYWORD Check a literal keyword sits where the grammar says.
%   Inputs   got, want, i, raw
%   Outputs  none; errors on mismatch
%   Utility  The only thing separating the mean from the covariance block is
%            this word; if it has moved, the arity check alone would pass.
if got ~= want
    error('datasets:readFactorGraphFile:keyword', ...
        'Line %d: expected "%s" where "%s" appears.\n  %s', i, want, got, raw);
end
end

% =========================================================================
function v = localNums(tok, i)
%LOCALNUMS Convert tokens to doubles, refusing anything unparseable.
%   Inputs   tok  string array of numeric tokens
%            i    line number, for errors
%   Outputs  v    row of doubles
%   Utility  str2double returns NaN rather than raising, and a NaN covariance
%            propagates into a posterior instead of stopping the load.
v = str2double(tok);
if any(isnan(v))
    error('datasets:readFactorGraphFile:notNumeric', ...
        'Line %d: "%s" is not a number.', i, strjoin(tok(isnan(v)), '", "'));
end
v = v(:).';
end

% =========================================================================
function C = localCov(tok, i)
%LOCALCOV Read nine tokens as a 3x3 covariance.
%   Inputs   tok  nine numeric tokens, row major
%            i    line number, for errors
%   Outputs  C    3x3 double
%   Utility  Row major, and reshape fills column major, so the transpose is
%            required. Symmetric covariances hide the difference, which is why
%            it is asserted here rather than trusted.
C = reshape(localNums(tok, i), 3, 3).';
if norm(C - C.', 'fro') > 1e-9 * max(1, norm(C, 'fro'))
    error('datasets:readFactorGraphFile:asymmetricCovariance', ...
        'Line %d: covariance is not symmetric, so its storage order is unclear.', i);
end
end

% =========================================================================
function localUnknown(i, raw)
%LOCALUNKNOWN Refuse a record kind the grammar does not cover.
%   Inputs   i, raw
%   Outputs  none; always errors
%   Utility  Skipping unknown lines yields a graph missing factors nobody
%            noticed, which still eliminates and is quietly a different
%            problem. Failing is the only outcome that cannot mislead.
error('datasets:readFactorGraphFile:unknownRecord', ...
    ['Line %d is not a record kind this reader knows. Extend the grammar ' ...
     'deliberately rather than skipping it.\n  %s'], i, raw);
end
