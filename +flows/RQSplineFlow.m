classdef RQSplineFlow < flows.FlowModel
    %RQSPLINEFLOW Autoregressive rational-quadratic spline flow, spec section 9.
    %
    %   Properties
    %     Dimension                    D, the number of variables
    %     NumSplines, HiddenUnits      K and the conditioner width, section 9
    %     Bound                        the spline support [-B, B]
    %     MinDerivative, MinBin        floors keeping the map invertible
    %     Mu, Sigma                    standardization, per dimension
    %     Params                       one conditioner's learnables per dimension
    %
    %   Methods
    %     setParameters   replace the learnables, checking their shapes
    %     transform       Eq. N3, with its per-dimension log derivative
    %     invert          Eq. N6 by forward substitution
    %     conditioner     the spline parameters for one dimension
    %
    %   Utility
    %     Supply the concrete flow the method actually trains: the authors'
    %     spline flow, MATLAB-native so it runs in this process and inside
    %     this test suite.
    %
    %   The authors' flow: each dimension is mapped by a monotone RQ spline
    %   whose knots are produced by a fully connected conditioner network
    %   reading the dimensions before it.
    %
    %       T_d(x_d ; c_d(x_<d ; w_d))
    %
    %   so the conditioner for dimension d has input width d-1 and output
    %   width 3K-1, being 2K-2 knot coordinates and K+1 derivatives. Spec
    %   section 9 defaults: K = 9 splines, two hidden layers, 8 hidden units.
    %
    %   DIMENSION 1 IS NOT A SPECIAL CASE. Its conditioner has input width 0,
    %   and an 8-by-0 weight matrix times a 0-by-n input is an 8-by-n block of
    %   zeros, so the network degenerates to its biases -- a learned constant
    %   spline, which is what an unconditional first dimension should be. The
    %   arithmetic does this without a branch.
    %
    %   THE FLOW STARTS AS THE IDENTITY. The last layer is initialized to zero
    %   weights and to biases that produce uniform bins and unit derivatives,
    %   which section 9's own parameterization makes exactly the identity map.
    %   Since the samples are standardized first, an untrained flow is the
    %   standard normal fitted to the training samples: training starts from
    %   the Gaussian answer and moves away from it only as the data demands.
    %   That is a deliberate choice, not an accident of initialization.
    %
    %   STANDARDIZATION is the Preprocessor of spec section 12, folded in here
    %   so that everything outside works in raw units: TRANSFORM standardizes
    %   on the way in, INVERT restores on the way out, and the log derivative
    %   carries the -log(sigma) that makes LOGPROB a density in raw space.
    %   Angle wrapping to [-pi, pi] is not done here: which columns are
    %   orientations is known to the caller building the clique, not to a
    %   flow that only sees a matrix.
    %
    %   Parameters are stored as plain numbers. FLOWS.TRAINFLOW wraps
    %   them in dlarray for the duration of training and unwraps them again,
    %   so a trained flow evaluates like ordinary numeric code.

    properties (SetAccess = protected)
        Dimension                  = 1      % D; validated in the constructor
        NumSplines    (1,1) double = 9      % K, spec section 9
        HiddenUnits   (1,1) double = 8      % spec section 9
        Bound         (1,1) double = 5      % spline support [-B, B]
        MinDerivative (1,1) double = 1e-3   % floor keeping the map invertible
        MinBin        (1,1) double = 1e-3   % floor keeping bins non-degenerate
        Mu            (1,:) double = 0      % standardization, per dimension
        Sigma         (1,:) double = 1
        Params        (1,:) cell = {}       % one conditioner per dimension
    end

    methods

        function obj = RQSplineFlow(D, opts)
            %RQSPLINEFLOW Build an untrained flow over D dimensions.
            %   Inputs   D the width, then the section 9 hyperparameters, the
            %           standardization Mu/Sigma, and Seed
            %   Outputs  OBJ, a flow that is exactly the identity map
            %   Utility  build the model before training, at the Gaussian
            %           answer rather than at a random one.
            arguments
                D (1,1) double {mustBeInteger, mustBePositive}
                opts.NumSplines (1,1) double {mustBeInteger} = 9
                opts.HiddenUnits (1,1) double {mustBeInteger, mustBePositive} = 8
                opts.Bound (1,1) double {mustBePositive} = 5
                opts.MinDerivative (1,1) double {mustBePositive} = 1e-3
                opts.MinBin (1,1) double {mustBePositive} = 1e-3
                opts.Mu (1,:) double = []
                opts.Sigma (1,:) double = []
                opts.Seed double {mustBeScalarOrEmpty} = []
            end

            if opts.NumSplines < 2
                error('flows:RQSplineFlow:tooFewSplines', ...
                    ['A spline needs at least 2 bins; got %d. Spec section 9 ' ...
                     'uses 9.'], opts.NumSplines);
            end
            if opts.MinBin * opts.NumSplines >= 2*opts.Bound
                error('flows:RQSplineFlow:binFloorTooLarge', ...
                    ['%d bins of at least %g do not fit in [-%g, %g].'], ...
                    opts.NumSplines, opts.MinBin, opts.Bound, opts.Bound);
            end

            obj.Dimension     = D;
            obj.NumSplines    = opts.NumSplines;
            obj.HiddenUnits   = opts.HiddenUnits;
            obj.Bound         = opts.Bound;
            obj.MinDerivative = opts.MinDerivative;
            obj.MinBin        = opts.MinBin;
            obj.Mu    = localFill(opts.Mu, 0, D, 'Mu');
            obj.Sigma = localFill(opts.Sigma, 1, D, 'Sigma');

            if any(obj.Sigma <= 0)
                error('flows:RQSplineFlow:degenerateScale', ...
                    ['Standardization needs a positive spread in every ' ...
                     'dimension; dimension %d has %g.'], ...
                    find(obj.Sigma <= 0, 1), min(obj.Sigma));
            end

            % Initialization is the only randomness in an untrained flow, and
            % restoring the stream keeps it from moving the caller's draws.
            if ~isempty(opts.Seed)
                state = rng(opts.Seed);
                restore = onCleanup(@() rng(state)); %#ok<NASGU>
            end

            obj.Params = cell(1, D);
            for d = 1:D
                obj.Params{d} = obj.initConditioner(d);
            end
        end

        function obj = setParameters(obj, params)
            %SETPARAMETERS Replace the learnables, keeping everything else.
            %   Inputs   PARAMS, one conditioner struct per dimension
            %   Outputs  OBJ, a new flow carrying them
            %   Utility  let the trainer hand its result back in.
            %
            %   The trainer lives outside the class -- Algorithm N2 owns the
            %   training loop, not the model -- so it needs a way back in.
            %   Shapes are checked here rather than trusted.
            arguments
                obj (1,1) flows.RQSplineFlow
                params (1,:) cell
            end
            if numel(params) ~= obj.Dimension
                error('flows:RQSplineFlow:parameterCount', ...
                    'The flow has %d conditioners; %d were given.', ...
                    obj.Dimension, numel(params));
            end
            for d = 1:obj.Dimension
                want = obj.conditionerShapes(d);
                for f = string(fieldnames(want)).'
                    if ~isfield(params{d}, f)
                        error('flows:RQSplineFlow:parameterField', ...
                            'Conditioner %d has no %s.', d, f);
                    end
                    if ~isequal(size(params{d}.(f)), want.(f))
                        error('flows:RQSplineFlow:parameterShape', ...
                            'Conditioner %d, %s: expected %s, got %s.', ...
                            d, f, mat2str(want.(f)), ...
                            mat2str(size(params{d}.(f))));
                    end
                end
            end
            obj.Params = params;
        end

        function [y, logDeriv] = transform(obj, x)
            %TRANSFORM Eq. N3 dimension by dimension, with its log derivative.
            %   Inputs   X, samples down the rows, in raw units
            %   Outputs  Y the image, LOGDERIV the log dT_d/dX_d per column
            %   Utility  apply the map, standardizing on the way in so the
            %           log derivative carries the -log(sigma) that makes
            %           LOGPROB a density in raw space.
            %
            %   X may be narrower than the flow: the leading block of a
            %   triangular map is a flow in its own right, which is the
            %   partition of Eq. N8.
            arguments
                obj (1,1) flows.RQSplineFlow
                x (:,:) {mustBeA(x, ["double" "single" "dlarray"])}
            end

            m = size(x, 2);
            obj.checkWidth(m);

            z = (x - obj.Mu(1:m)) ./ obj.Sigma(1:m);
            z = localPromote(z, obj.Params);

            y = z;
            logDeriv = zeros(size(z), 'like', z);
            for d = 1:m
                p = obj.conditioner(d, z(:, 1:d-1));
                [yd, ld] = flows.rqSplineTransform(z(:, d), p, ...
                    'Bound', obj.Bound, 'MinDerivative', obj.MinDerivative);
                y(:, d) = yd;
                % Standardization is part of the map, so its Jacobian belongs
                % here: without it LOGPROB would be a density in the wrong
                % units and separator densities would not compose.
                logDeriv(:, d) = ld - log(obj.Sigma(d));
            end
        end

        function x = invert(obj, y, prefix)
            %INVERT Eq. N6 by forward substitution, with an optional prefix.
            %   Inputs   Y the target rows, PREFIX the leading values to pin
            %   Outputs  X solving T(X) = Y, in raw units
            %   Utility  invert the map, which is what sampling a flow is.
            %
            %   Dimension d needs x_1..x_{d-1} to build its conditioner, and
            %   by then they are solved. PREFIX pins the leading dimensions to
            %   given values instead of solving them: that is observation
            %   fixing (O_C = o_C) and conditional sampling (S_C = s) alike.
            arguments
                obj (1,1) flows.RQSplineFlow
                y (:,:) double
                prefix (:,:) double = zeros(size(y, 1), 0)
            end

            m = size(y, 2);
            obj.checkWidth(m);
            np = size(prefix, 2);
            if np > m
                error('flows:RQSplineFlow:prefixWidth', ...
                    ['The prefix fixes %d leading variables but only %d are ' ...
                     'being solved.'], np, m);
            end
            if np > 0 && size(prefix, 1) ~= size(y, 1)
                error('flows:RQSplineFlow:prefixRows', ...
                    ['The prefix must have one row per sample: %d rows ' ...
                     'against %d.'], size(prefix, 1), size(y, 1));
            end

            z = zeros(size(y, 1), m);
            if np > 0
                z(:, 1:np) = (prefix - obj.Mu(1:np)) ./ obj.Sigma(1:np);
            end
            for d = np+1:m
                p = obj.conditioner(d, z(:, 1:d-1));
                z(:, d) = flows.rqSplineTransform(y(:, d), p, ...
                    'Inverse', true, 'Bound', obj.Bound, ...
                    'MinDerivative', obj.MinDerivative);
            end

            x = z .* obj.Sigma(1:m) + obj.Mu(1:m);
        end

        function p = conditioner(obj, d, zPrev)
            %CONDITIONER The spline for dimension d given the dimensions before.
            %   Inputs   D the dimension, ZPREV the standardized dimensions
            %           before it, one row per sample
            %   Outputs  P, the widths/heights/derivatives of one spline per row
            %   Utility  turn the network's raw outputs into a valid spline.
            %
            %   Two hidden layers, spec section 9, then 3K-1 raw outputs
            %   turned into a valid spline: bin widths and heights by softmax
            %   so they sum to the support 2B, derivatives by softplus so they
            %   stay positive. The knots are 2K-2 free numbers because the two
            %   end knots are pinned at -B and B, which is why the softmax
            %   over K bins is fed only K-1 outputs and a fixed zero.
            arguments
                obj (1,1) flows.RQSplineFlow
                d (1,1) double {mustBeInteger, mustBePositive}
                zPrev (:,:) {mustBeA(zPrev, ["double" "single" "dlarray"])}
            end

            q = obj.Params{d};
            K = obj.NumSplines;
            n = size(zPrev, 1);

            a = zPrev.';                       % (d-1)-by-n, empty when d = 1
            h = tanh(q.W1 * a + q.b1);
            h = tanh(q.W2 * h + q.b2);
            o = q.W3 * h + q.b3;               % (3K-1)-by-n

            span = 2*obj.Bound - K*obj.MinBin;
            zero = zeros(1, n, 'like', o);
            p.widths  = (obj.MinBin + span * localSoftmax([zero; o(1:K-1, :)])).';
            p.heights = (obj.MinBin + span * localSoftmax([zero; o(K:2*K-2, :)])).';
            p.derivatives = ...
                (obj.MinDerivative + localSoftplus(o(2*K-1:3*K-1, :))).';
        end
    end

    methods (Access = private)

        function s = conditionerShapes(obj, d)
            %CONDITIONERSHAPES What a conditioner for dimension d must look
            %   like.
            %   Inputs   D, the dimension
            %   Outputs  S, the expected size of every learnable
            %   Utility  state the shapes once, for checking and for building.
            %
            %   Kept apart from INITCONDITIONER so that validating
            %   trained parameters does not draw random numbers and move the
            %   caller's stream on every training iteration.
            K = obj.NumSplines;
            H = obj.HiddenUnits;
            s = struct('W1', [H d-1], 'b1', [H 1], ...
                       'W2', [H H],   'b2', [H 1], ...
                       'W3', [3*K-1 H], 'b3', [3*K-1 1]);
        end

        function q = initConditioner(obj, d)
            %INITCONDITIONER Glorot hidden layers, and a last layer that is
            %   exactly the identity spline.
            %   Inputs   D, the dimension
            %   Outputs  Q, the learnables for its conditioner
            %   Utility  start training from the identity map. See the class
            %           header for why that is deliberate.
            K = obj.NumSplines;
            H = obj.HiddenUnits;
            nIn  = d - 1;                       % spec section 9: input d-1
            nOut = 3*K - 1;                     % spec section 9: output 3K-1

            q.W1 = localGlorot(H, nIn);
            q.b1 = zeros(H, 1);
            q.W2 = localGlorot(H, H);
            q.b2 = zeros(H, 1);
            q.W3 = zeros(nOut, H);
            % Uniform bins fall out of equal logits; unit derivatives need the
            % softplus inverse of 1 less the floor that is added back.
            q.b3 = [zeros(2*K-2, 1); ...
                    repmat(log(exp(1 - obj.MinDerivative) - 1), K+1, 1)];
        end

        function checkWidth(obj, m)
            %CHECKWIDTH Refuse a column count the flow cannot honour.
            %   Inputs   M, how many leading columns a caller asked for
            %   Outputs  none; throws flows:RQSplineFlow:width
            %   Utility  a leading block is a flow, but a block wider than D
            %           is nothing, and silently truncating would hide it.
            if m < 1 || m > obj.Dimension
                error('flows:RQSplineFlow:width', ...
                    ['The flow has %d dimensions, so it can be used on 1 to ' ...
                     '%d leading columns; got %d.'], ...
                    obj.Dimension, obj.Dimension, m);
            end
        end
    end
end

% -------------------------------------------------------------------------
function s = localSoftmax(z)
%LOCALSOFTMAX Down the columns, shifted for overflow.
%   Inputs   Z, raw outputs, one column per sample
%   Outputs  S, columns summing to 1
%   Utility  turn raw outputs into bin fractions.
%
%   Written out rather than called from the toolbox because that one wants a
%   labelled dlarray and this has to work on plain numbers too.
e = exp(z - max(z, [], 1));
s = e ./ sum(e, 1);
end

function s = localSoftplus(z)
%LOCALSOFTPLUS log(1+exp(z)), in the form that does not overflow.
%   Inputs   Z, raw outputs
%   Outputs  S, positive
%   Utility  keep the knot derivatives positive, so the spline is monotone.
s = log(1 + exp(-abs(z))) + max(z, 0);
end

function W = localGlorot(nOut, nIn)
%LOCALGLOROT Glorot-uniform weights, and the empty matrix when nIn is 0.
%   Inputs   NOUT, NIN, the layer's widths
%   Outputs  W, nOut-by-nIn
%   Utility  initialize a hidden layer; dimension 1's zero-width input needs
%           no special case, an nOut-by-0 matrix behaves correctly.
if nIn == 0
    W = zeros(nOut, 0);
    return
end
W = randn(nOut, nIn) * sqrt(2 / (nIn + nOut));
end

function v = localFill(v, default, D, name)
%LOCALFILL Expand a standardization option to one value per dimension.
%   Inputs   V the option, DEFAULT its scalar fallback, D the width, NAME for
%           the error message
%   Outputs  V, 1-by-D
%   Utility  accept a scalar, a full vector or nothing, and refuse a length
%           that is neither.
if isempty(v)
    v = repmat(default, 1, D);
    return
end
if numel(v) ~= D
    error('flows:RQSplineFlow:standardizationWidth', ...
        '%s needs one value per dimension: %d against %d.', name, numel(v), D);
end
v = reshape(v, 1, D);
end

function z = localPromote(z, params)
%LOCALPROMOTE Track the parameters when the samples are plain data.
%   During training the samples are constants and the conditioner weights are
%   dlarray; the transform of the two has to be a dlarray or the gradient
%   stops at the first indexed assignment.
if isa(z, 'dlarray') || isempty(params)
    return
end
if isa(params{1}.W3, 'dlarray')
    z = dlarray(z);
end
end
