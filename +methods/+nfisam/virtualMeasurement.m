function [z, o, info] = virtualMeasurement(f, given, opts)
%VIRTUALMEASUREMENT Simulate Z_i between two sampled variables, and its z_i.
%
%   Inputs
%     F                       the factor to turn around
%     GIVEN                   the sample dictionary, holding both its
%                             variables
%     MultimodalMeasurement   what to take as o_C for a mixture factor; see
%                             the marked choice below
%
%   Outputs
%     Z     the simulated measurement, one row per given sample
%     O     the value actually measured, which Algorithm N2 fixes as O_C = o_C
%     INFO  the modes, and whether O was assumed rather than read
%
%   Utility
%     Draw the virtual measurement of Algorithm N1 steps 3 and 4: when both
%     latent variables of a factor are already in the sample dictionary, the
%     factor cannot simulate a variable, so it is turned around and used to
%     simulate the measurement it would have produced.
%
%   This is the forward measurement model, the direction the Slices engine
%   never needs: evaluation asks "how likely is this measurement given these
%   poses", simulation asks "what measurement would these poses produce".
%   Both read the same Meta the factor was built with, so a factor cannot
%   disagree with itself about its own noise.
%
%   MARKED CHOICE (spec section 0 permits these where code-level detail is
%   absent). A mixtureRelative factor folds the observation and the competing
%   hypotheses into one density: its modes ARE alternative displacements, so
%   no single measured value can be read back out of it. O is taken to be the
%   highest-weighted mode and every mode is returned in INFO.modes, with
%   INFO.assumed set. Change it through OPTS.MultimodalMeasurement.

arguments
    f (1,1) core.Factor
    given (1,1) struct
    opts.MultimodalMeasurement (1,1) string {mustBeMember( ...
        opts.MultimodalMeasurement, ["maxWeight", "first"])} = "maxWeight"
end

info = struct('kind', f.Kind, 'assumed', false, 'modes', [], 'component', []);
m = f.Meta;

switch f.Kind
    case "gaussianRelative"
        [a, b] = localPair(f, given);
        z = (b - a) + m.sigma * randn(size(a));
        o = m.delta;

    case "gaussianVectorRelative"
        [a, b] = localPair(f, given);
        L = core.Factor.cholOf(m.sigma, m.dim);
        z = (b - a) + randn(size(a, 1), m.dim) * L.';
        o = reshape(m.delta, 1, []);

    case "range"
        [x, l] = localPair(f, given);
        z = vecnorm(l - x, 2, 2) + m.sigma * randn(size(x, 1), 1);
        o = m.range;

    case "ambiguousRange"
        % The association is the unknown, not the range: draw which landmark
        % produced the reading, then measure to it.
        x = given.(matlab.lang.makeValidName(f.Scope(1)));
        n = size(x, 1);
        k = localCategorical(m.weights, n);
        z = zeros(n, 1);
        for c = 1:numel(m.candidates)
            hit = (k == c);
            if ~any(hit), continue, end
            l = given.(matlab.lang.makeValidName(m.candidates(c)));
            z(hit) = vecnorm(l(hit, :) - x(hit, :), 2, 2);
        end
        z = z + m.sigma * randn(n, 1);
        o = m.range;
        info.component = k;

    case "mixtureRelative"
        [a, b] = localPair(f, given);
        n = size(a, 1);
        k = localCategorical(m.weights, n);
        s = reshape(m.sigmas, 1, []);
        z = (b - a) + s(k).' .* randn(n, 1);
        d = reshape(m.deltas, 1, []);
        if opts.MultimodalMeasurement == "maxWeight"
            [~, star] = max(m.weights);
        else
            star = 1;
        end
        o = d(star);
        info.assumed   = true;
        info.modes     = d;
        info.component = k;

    otherwise
        error('methods:nfisam:virtualMeasurement:unsupported', ...
            ['Factor %s has kind "%s" and no forward measurement model. ' ...
             'Algorithm N1 can only simulate a virtual measurement for a ' ...
             'factor that knows what it measures.'], f.Name, f.Kind);
end
end

% -------------------------------------------------------------------------
function [a, b] = localPair(f, given)
%LOCALPAIR The two sampled variables a binary factor connects.
%   Inputs   F the factor, GIVEN the sample dictionary
%   Outputs  A and B, their sample blocks
%   Utility  read the pair in the factor's own scope order, since the
%           measurement model is not symmetric in them.
a = given.(matlab.lang.makeValidName(f.Scope(1)));
b = given.(matlab.lang.makeValidName(f.Scope(2)));
if size(a, 1) ~= size(b, 1)
    error('methods:nfisam:virtualMeasurement:unpaired', ...
        ['Factor %s was given %d samples of %s and %d of %s. A virtual ' ...
         'measurement is simulated per joint sample, so the two must match.'], ...
        f.Name, size(a, 1), f.Scope(1), size(b, 1), f.Scope(2));
end
end

function k = localCategorical(w, n)
%LOCALCATEGORICAL N draws from a categorical distribution.
%   Inputs   W the weights, N how many draws
%   Outputs  K, the drawn indices
%   Utility  choose which mode of a mixture factor each simulated measurement
%           comes from.
w = reshape(w, 1, []) / sum(w);
k = sum(rand(n, 1) > cumsum(w), 2) + 1;
k = min(k, numel(w));
end
