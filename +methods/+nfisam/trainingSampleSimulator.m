function [S, V, info] = trainingSampleSimulator(factors, opts)
%TRAININGSAMPLESIMULATOR Algorithm N1 of the NF-iSAM spec.
%
%   Inputs
%     FACTORS              the clique's factors
%     NumSamples           n_train; spec section 9 default is 2000
%     Given                variables already sampled -- separator draws handed
%                          down, or a child's separator density
%     Frontal, Separator   F_C and S_C, used to order the output for Algorithm
%                          N2 step 1 and to check that every frontal was
%                          actually reached
%
%   Outputs
%     S     the sample dictionary
%     V     the measured-value dictionary
%     INFO  the observation variables that were created, the O/S/F ordering,
%           and any measurement that had to be assumed
%
%   Utility
%     Simulate from the intermediate density p(O_C, S_C, F_C | z_C*) that
%     NF-iSAM trains on. Deliberately generative: no factor is ever evaluated.
%
%   The point of Algorithm N1 is that NF-iSAM never trains on the clique
%   posterior directly. It trains on samples from an intermediate density
%   p(O_C, S_C, F_C | z_C*) that is cheap to sample by ancestral simulation,
%   and only afterwards conditions on the measurements by fixing O_C = o_C.
%   So this function is deliberately generative and never evaluates a factor:
%   priors are sampled, a binary factor whose other end is already known is
%   used to simulate the end that is not, and a factor whose both ends are
%   known has nothing left to simulate but the measurement itself -- which
%   becomes an observation variable Z_i, with the value actually measured
%   recorded in V.
%
%   The queue in step 3 is what makes the order work out: a factor whose two
%   variables are both still unknown goes to the back and is retried once its
%   neighbours have been reached. A clique in which no progress is possible
%   is named rather than spun on, because the spec's loop has no termination
%   condition of its own and an unreachable variable would hang it.
%
%   See also methods.nfisam.factorRole, methods.nfisam.virtualMeasurement,
%   methods.nfisam.conditionalSamplerTrainer.

arguments
    factors (1,:) core.Factor
    opts.NumSamples (1,1) double {mustBeInteger, mustBePositive} = 2000
    opts.Given (1,1) struct = struct()
    opts.Frontal (1,:) string = string.empty(1,0)
    opts.Separator (1,:) string = string.empty(1,0)
    opts.MultimodalMeasurement (1,1) string = "maxWeight"
end

n = opts.NumSamples;
S = opts.Given;
V = struct();
observationOrder = string.empty(1, 0);
assumptions = string.empty(1, 0);

roles = arrayfun(@(f) methods.nfisam.factorRole(f), factors);

% --- Step 2: priors ------------------------------------------------------
for f = factors(roles == "prior")
    for v = f.Scope
        key = matlab.lang.makeValidName(v);
        if isfield(S, key), continue, end
        S.(key) = localRows(f.sample(v, struct(), n), n, f, v);
    end
end

% --- Step 3: binary measurement factors, as a queue ----------------------
B = factors(roles == "binary");
queue = 1:numel(B);
stalled = 0;

while ~isempty(queue)
    i = queue(1);
    queue(1) = [];
    f = B(i);

    keys  = arrayfun(@(v) string(matlab.lang.makeValidName(v)), f.Scope);
    known = arrayfun(@(k) isfield(S, k), keys);

    if nnz(~known) == 1
        % One end reached: simulate the other through the measurement model.
        target = f.Scope(~known);
        given  = localGivenOf(S, keys(known), f.Scope(known));
        if ~f.canSample(target)
            error('methods:nfisam:trainingSampleSimulator:notSampleable', ...
                ['Factor %s cannot simulate %s, so the clique cannot be ' ...
                 'reached from its priors. Algorithm N1 needs every ' ...
                 'measurement factor to be invertible in at least one ' ...
                 'direction.'], f.Name, target);
        end
        S.(matlab.lang.makeValidName(target)) = ...
            localRows(f.sample(target, given, 1), n, f, target);
        stalled = 0;

    elseif all(known)
        % Both ends reached: the measurement is what is left to simulate.
        [z, o, vinfo] = methods.nfisam.virtualMeasurement(f, S, ...
            'MultimodalMeasurement', opts.MultimodalMeasurement);
        zname = "Z_" + f.Name;
        S.(matlab.lang.makeValidName(zname)) = z;
        V.(matlab.lang.makeValidName(zname)) = o;
        observationOrder(end+1) = zname; %#ok<AGROW>
        if vinfo.assumed
            assumptions(end+1) = f.Name; %#ok<AGROW>
        end
        stalled = 0;

    else
        % Neither end reached yet: try again after its neighbours.
        queue(end+1) = i; %#ok<AGROW>
        stalled = stalled + 1;
        if stalled > numel(queue)
            stuck = arrayfun(@(j) B(j).Name, queue);
            error('methods:nfisam:trainingSampleSimulator:unreachable', ...
                ['No prior reaches %s. Algorithm N1 simulates forward from ' ...
                 'priors, so every variable in a clique must be connected to ' ...
                 'one; these factors have both ends unsampled: %s.'], ...
                strjoin(unique([B(queue).Scope]), ', '), strjoin(stuck, ', '));
        end
    end
end

% --- Step 4: multi-modal data-association factors ------------------------
for f = factors(roles == "multimodal")
    missing = f.Scope(~arrayfun(@(v) isfield(S, matlab.lang.makeValidName(v)), f.Scope));
    if ~isempty(missing)
        error('methods:nfisam:trainingSampleSimulator:associationUnreached', ...
            ['Data-association factor %s needs %s, which no prior or binary ' ...
             'factor reached. Step 4 can only simulate a virtual measurement ' ...
             'between variables that already have samples.'], ...
            f.Name, strjoin(missing, ', '));
    end
    [z, o, vinfo] = methods.nfisam.virtualMeasurement(f, S, ...
        'MultimodalMeasurement', opts.MultimodalMeasurement);
    zname = "Z_" + f.Name;
    S.(matlab.lang.makeValidName(zname)) = z;
    V.(matlab.lang.makeValidName(zname)) = o;
    observationOrder(end+1) = zname; %#ok<AGROW>
    if vinfo.assumed
        assumptions(end+1) = f.Name; %#ok<AGROW>
    end
end

% --- Every frontal must have been reached --------------------------------
unreached = opts.Frontal(~arrayfun(@(v) ...
    isfield(S, matlab.lang.makeValidName(v)), opts.Frontal));
if ~isempty(unreached)
    error('methods:nfisam:trainingSampleSimulator:frontalUnreached', ...
        ['The clique frontal %s was never simulated. Its conditional cannot ' ...
         'be trained without samples of it.'], strjoin(unreached, ', '));
end

% Algorithm N2 step 1 wants the columns in the order O, S, F.
info = struct( ...
    'numSamples',    n, ...
    'observations',  observationOrder, ...
    'separator',     opts.Separator, ...
    'frontal',       opts.Frontal, ...
    'ordering',      [observationOrder opts.Separator opts.Frontal], ...
    'assumedMeasurement', assumptions);
end

% -------------------------------------------------------------------------
function x = localRows(x, n, f, v)
%LOCALROWS A sample block forced to n rows, or an error naming what produced it.
%   Inputs   X the block, N the required rows, F the factor, V the variable
%   Outputs  X, n-by-d
%   Utility  a factor that returns one row where n were asked for would
%           broadcast silently and correlate every training sample.
%
%   core.Factor.sample returns SIZE(GIVEN)-by-N, so a paired draw of a
%   2-D variable arrives as n-by-1-by-2. Training samples are a matrix with
%   one row per sample and one column per dimension, so the singleton is
%   folded out here rather than at every call site.
if size(x, 1) == n
    if ndims(x) > 2
        x = reshape(x, n, []);
    end
    return
end
if isvector(x) && numel(x) == n
    x = reshape(x, n, 1);
    return
end
error('methods:nfisam:trainingSampleSimulator:shape', ...
    ['Factor %s returned a %s sample block for %s; Algorithm N1 needs one ' ...
     'row per training sample (%d).'], f.Name, mat2str(size(x)), v, n);
end

function given = localGivenOf(S, keys, names)
%LOCALGIVENOF The sub-dictionary a factor needs, by variable name.
%   Inputs   S the sample dictionary, KEYS its valid names, NAMES what the
%           factor asks for
%   Outputs  GIVEN, the sub-dictionary
%   Utility  hand a factor exactly what it conditions on.
given = struct();
for i = 1:numel(keys)
    given.(matlab.lang.makeValidName(names(i))) = S.(keys(i));
end
end
