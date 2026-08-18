function [sampler, info] = conditionalSamplerTrainer(S, V, opts)
%CONDITIONALSAMPLERTRAINER Algorithm N2 of the NF-iSAM spec.
%
%   Inputs
%     S             the sample dictionary from Algorithm N1
%     V             the measured-value dictionary from Algorithm N1
%     Observations, Separator, Frontal   the layout, as named by Algorithm N1
%     AngleColumns  which of each variable's columns are orientations
%     Training      options forwarded to flows.trainFlow
%
%   Outputs
%     SAMPLER  the methods.nfisam.ConditionalSampler the clique caches
%     INFO     the ordering and widths, the measured row, how far outside the
%              simulated spread it landed, which columns were wrapped, the
%              training record and the runtime
%
%   Utility
%     Turn one clique's simulated samples into the samplers of p(F_C|S_C,z_C)
%     and p(S_C|z_C).
%
%   The five steps of the algorithm, and where each one is:
%
%     1. Rearrange the samples to the order O, S, F        PACKSAMPLES
%     2. Train T~ of Eq. N9 by the objective of Eq. N7     FLOWS.TRAINFLOW
%     3. Fix the observations, T(S,F) <- T~(O=o, S, F)     the measured row o
%     4. Partition T(S,F) into T_S and T_F by Eq. N8       a column split
%     5. Get samplers of p(F|S) and p(S) by Eq. N6         the returned object
%
%   STEPS 3 TO 5 COST NOTHING, and that is the point of the whole
%   construction rather than a shortcut taken here. Because T~ is triangular,
%   holding its leading block at the measured values is what the inverse
%   already does with any dimensions it is not asked to solve, and the
%   partition of Eq. N8 is a partition of columns. So exactly one thing is
%   fitted per clique -- the flow of step 2 -- and the two samplers the
%   algorithm returns are two ways of calling it. See
%   METHODS.NFISAM.CONDITIONALSAMPLER.
%
%   THE ORDER IS THE ALGORITHM. Spec section 17 is explicit that (O, S, F) is
%   not cosmetic. Observations lead so that fixing them is a prefix;
%   separators come next so that T_S is a leading block and its density can be
%   read off and passed up; frontals come last so that they are conditioned on
%   everything the parent will have already drawn.
%
%   WHY IT MAY BE ASKED TO EXTRAPOLATE. The flow is trained on SIMULATED
%   observations and then evaluated at the MEASURED one. Those are the same
%   quantity but not the same value, and a measurement that the intermediate
%   density considers unlikely -- a tight loop closure, which is exactly the
%   informative case -- sits in the tail of the simulated spread. INFO reports
%   how far out in standardized units it landed, and past the spline support
%   the conditioners are extrapolating, so this warns rather than reporting a
%   posterior that looks as confident as any other.
%
%   OPTION NOTES.
%     Observations, Separator, Frontal   pass INFO.observations, .separator
%                                        and .frontal from Algorithm N1.
%     AngleColumns    struct: variable name -> which of ITS columns are
%                     orientations. Spec section 9 wraps those to [-pi, pi]
%                     before standardization, and this is the layer that can:
%                     FLOWS.TRAINFLOW sees a matrix and cannot know which
%                     columns are angles, while a clique knows its variables.
%     Training        struct of options forwarded to FLOWS.TRAINFLOW, so that
%                     the defaults of spec sections 9 and 16 stay written down
%                     in exactly one place. HOW MANY SAMPLES ARRIVE HERE is
%                     set at Algorithm N1, and the authors' n_train = 2000 was
%                     measurably not enough for the four-dimensional clique in
%                     tConditionalSampler: see the header of FLOWS.TRAINFLOW
%                     and its Holdout option, which is how that is detected
%                     rather than assumed.

arguments
    S (1,1) struct
    V (1,1) struct = struct()
    opts.Observations (1,:) string = string.empty(1,0)
    opts.Separator (1,:) string = string.empty(1,0)
    opts.Frontal (1,:) string = string.empty(1,0)
    opts.AngleColumns (1,1) struct = struct()
    opts.Training (1,1) struct = struct()
end

tStart = tic;

if isempty(opts.Frontal)
    error('methods:nfisam:conditionalSamplerTrainer:noFrontal', ...
        ['A clique with no frontal variables has no conditional to learn. ' ...
         'Every clique of a Bayes tree eliminates at least one variable.']);
end

names = [opts.Observations opts.Separator opts.Frontal];
dup = localDuplicates(names);
if ~isempty(dup)
    error('methods:nfisam:conditionalSamplerTrainer:duplicate', ...
        ['%s appears twice in the clique layout. A variable is an ' ...
         'observation, a separator or a frontal, and the flow would give it ' ...
         'two independent sets of columns.'], strjoin(dup, ', '));
end

% --- Step 1: rearrange to (O, S, F), Eq. N14 -----------------------------
[X, widths] = methods.nfisam.packSamples(S, names);
ends = cumsum([0 widths]);
nO   = numel(opts.Observations);
obsCols = 1:ends(nO+1);

% Orientations, spec section 9. Done before standardization because the
% wrap is a change of representation, not of scale.
[X, wrapped] = localWrapAngles(X, names, widths, opts.AngleColumns);

% --- Step 3, half of it: the measured values o_C -------------------------
% Assembled before training so that a missing measurement is reported before
% a minute is spent fitting a flow that could not have been conditioned.
o = localMeasuredRow(V, opts.Observations, widths(1:nO));
o(ismember(obsCols, wrapped)) = localWrapPi(o(ismember(obsCols, wrapped)));

% --- Step 2: train T~ of Eq. N9 by Eq. N7 --------------------------------
trainArgs = namedargs2cell(opts.Training);
[flow, trainInfo] = flows.trainFlow(X, trainArgs{:});

% --- Steps 3 to 5: fix, partition, and hand back the two samplers --------
% All three are the same object: fixing is a prefix, partitioning is a column
% split, and sampling is the inverse of Eq. N6 over the block asked for.
sampler = methods.nfisam.ConditionalSampler(flow, ...
    'Observations', opts.Observations, ...
    'Separator', opts.Separator, ...
    'Frontal', opts.Frontal, ...
    'Widths', widths, ...
    'ObservationValue', o);

% How far the measurement sits from what the intermediate density simulated.
obsZ = (o - trainInfo.mu(obsCols)) ./ trainInfo.sigma(obsCols);
% The spline is the identity outside its support, so a measurement past it is
% being read off a linear tail. Asked of the flow rather than assumed, since
% another FLOWS.FLOWMODEL need not be built from splines at all.
if isprop(flow, 'Bound'), support = flow.Bound; else, support = 5; end
outside = abs(obsZ) > support;
if any(outside)
    first = find(outside, 1);
    warning('methods:nfisam:conditionalSamplerTrainer:observationFarFromSamples', ...
        ['Measured value %d is %.1f standard deviations from the simulated ' ...
         'observations, past the flow support of %g. The flow is being ' ...
         'asked to extrapolate, so the clique posterior is not trustworthy ' ...
         'there; more training samples or a wider Bound is the remedy.'], ...
        first, obsZ(first), support);
end

info = struct( ...
    'ordering',      names, ...
    'widths',        widths, ...
    'columns',       sampler.Columns, ...
    'dimension',     size(X, 2), ...
    'numSamples',    size(X, 1), ...
    'observationValue', o, ...
    'observationZ',  obsZ, ...
    'observationOutOfSupport', any(outside), ...
    'wrappedColumns', wrapped, ...
    'training',      trainInfo, ...
    'runtime',       toc(tStart));
end

% -------------------------------------------------------------------------
function d = localDuplicates(names)
%LOCALDUPLICATES Names appearing more than once in the layout.
%   Inputs   NAMES, the O/S/F ordering
%   Outputs  D, the repeated names
%   Utility  a variable listed in two blocks would occupy two column ranges
%           and the partition of Eq. N8 would no longer be a partition.
[u, ~, k] = unique(names, 'stable');
d = u(accumarray(k, 1) > 1);
end

function row = localMeasuredRow(V, obsNames, obsWidths)
%LOCALMEASUREDROW The measured values o_C, laid out like the observation block.
%   Inputs   V the measured-value dictionary, OBSNAMES the observation
%           variables in order, OBSWIDTHS their widths
%   Outputs  ROW, 1-by-(sum of widths)
%   Utility  step 3 of Algorithm N2 fixes O_C = o_C as a prefix, and a prefix
%           has to be in the flow's own column order.
row = zeros(1, 0);
for i = 1:numel(obsNames)
    key = matlab.lang.makeValidName(obsNames(i));
    if ~isfield(V, key)
        error('methods:nfisam:conditionalSamplerTrainer:noMeasuredValue', ...
            ['%s was simulated as an observation variable but no measured ' ...
             'value came with it. Step 3 has nothing to fix it to; ' ...
             'Algorithm N1 records the value in V when it creates the ' ...
             'variable.'], obsNames(i));
    end
    v = V.(key);
    v = reshape(v, 1, []);
    if numel(v) ~= obsWidths(i)
        error('methods:nfisam:conditionalSamplerTrainer:measuredWidth', ...
            ['%s was simulated as %d column(s) but its measured value has ' ...
             '%d. The virtual measurement and the real one must be the same ' ...
             'quantity.'], obsNames(i), obsWidths(i), numel(v));
    end
    row = [row v]; %#ok<AGROW>
end
end

function [X, wrapped] = localWrapAngles(X, names, widths, spec)
%LOCALWRAPANGLES Wrap the orientation columns to [-pi, pi], spec section 9.
%   Inputs   X the sample matrix, NAMES and WIDTHS the layout, SPEC which of
%           each variable's columns are angles
%   Outputs  X wrapped, WRAPPED which columns were
%   Utility  this is the layer that CAN: flows.trainFlow sees a matrix and
%           cannot know which columns are angles, while a clique knows its
%           variables.
%
%   SPEC names variables and, for each, which of its own columns are angles,
%   so that a pose packed as (x, y, theta) declares 3 rather than the whole
%   variable.
wrapped = zeros(1, 0);
ends = cumsum([0 widths]);
for f = string(fieldnames(spec)).'
    hit = find(arrayfun(@(v) string(matlab.lang.makeValidName(v)) == f, names), 1);
    if isempty(hit)
        error('methods:nfisam:conditionalSamplerTrainer:angleUnknown', ...
            ['AngleColumns names %s, which is not a variable of this ' ...
             'clique. The declaration would be silently ignored.'], f);
    end
    local = reshape(spec.(f), 1, []);
    if any(local < 1 | local > widths(hit) | mod(local, 1) ~= 0)
        error('methods:nfisam:conditionalSamplerTrainer:angleColumn', ...
            ['%s is %d column(s) wide; AngleColumns asks for %s.'], ...
            names(hit), widths(hit), mat2str(local));
    end
    g = ends(hit) + local;
    X(:, g) = localWrapPi(X(:, g));
    wrapped = [wrapped g]; %#ok<AGROW>
end
wrapped = sort(wrapped);
end

function a = localWrapPi(a)
%LOCALWRAPPI One angle array wrapped to [-pi, pi].
%   Inputs   A, the angles
%   Outputs  A, wrapped
%   Utility  standardizing an unwrapped angle would put its mean between the
%           two ends of the circle.
%
%   Toolbox, which this project does not depend on.
a = mod(a + pi, 2*pi) - pi;
end
