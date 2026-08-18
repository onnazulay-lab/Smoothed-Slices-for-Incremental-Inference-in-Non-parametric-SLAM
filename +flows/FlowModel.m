classdef (Abstract) FlowModel
    %FLOWMODEL The triangular normalizing flow of NF-iSAM spec section 3.
    %
    %   Properties
    %     Dimension   abstract; D, the number of variables the flow maps
    %
    %   Methods
    %     transform   abstract; Y = T(X) and the per-dimension log derivative
    %     invert      abstract; solve T(X) = Y by forward substitution
    %     logProb     Eq. N4, or Eq. N5 on a leading block
    %     sample      Eq. N6, optionally conditioned on a prefix
    %
    %   Utility
    %     Fix the interface Algorithms N2 and N3 talk to, and derive density
    %     and sampling from the two maps a subclass supplies.
    %
    %   A flow is the map T of Eq. N3, which is triangular by construction:
    %
    %       T(x) = [T_1(x_1), T_2(x_1,x_2), ..., T_D(x_1,...,x_D)]'
    %
    %   Triangularity is not a convenience. It is the single property the rest
    %   of NF-iSAM is built on. Because T_d sees only x_1..x_d:
    %
    %     * the density factors dimension by dimension, Eq. N4/N5, so a
    %       conditional can be read off without retraining anything;
    %     * the leading block of T is itself a flow over the leading block of
    %       x, which is exactly the partition T_C = [T_S; T_F] of Eq. N8;
    %     * the inverse is solved by forward substitution, Eq. N6, one
    %       dimension at a time, which is what makes sampling cheap.
    %
    %   So the subclass supplies two things and this class derives the rest.
    %
    %   TRANSFORM(X) returns Y and the per-dimension log derivative rather
    %   than one log-determinant. Summing the rows gives the determinant of
    %   Eq. N4; summing a subset gives Eq. N5, which is how the separator
    %   density p(S_C|z_C) is evaluated without a second model. X may have
    %   fewer columns than DIMENSION, meaning the leading block only -- again
    %   legitimate only because the map is triangular.
    %
    %   INVERT(Y, PREFIX) solves T(X) = Y for X, with the first columns of X
    %   pinned to PREFIX instead of being solved. That one argument covers all
    %   three things NF-iSAM asks of a flow: no prefix is Eq. N6 sampling; a
    %   prefix of measured values is the observation fixing O_C = o_C of
    %   Eq. N10; a prefix of separator draws is sampling p(F_C | S_C = s).
    %
    %   WHY A SEAM AT ALL. The authors train these in PyTorch. The subclass
    %   here is MATLAB-native on Deep Learning Toolbox so the method stays in
    %   one process and inside this test suite, but nothing above this class
    %   knows that. Algorithms N2 and N3 talk to the four methods below.
    %
    %   A value class, like core.Factor and core.BayesTreeClique: training
    %   returns a new flow rather than mutating one, so a clique's cached
    %   sampler cannot be changed underneath the tree that stored it.

    properties (Abstract, SetAccess = protected)
        % D, the number of variables the flow maps. Declared without size or
        % validation: MATLAB does not allow a subclass to restate those on an
        % inherited property, so the concrete class validates D where it is
        % actually set, in its constructor.
        Dimension
    end

    methods (Abstract)
        %TRANSFORM Y = T(X) and log dT_d/dX_d, per dimension.
        [y, logDeriv] = transform(obj, x)

        %INVERT Solve T(X) = Y for X by forward substitution, Eq. N6.
        x = invert(obj, y, prefix)
    end

    methods

        function lp = logProb(obj, x)
            %LOGPROB Eq. N4: log p(x; T) = log q(T(x)) + sum_d log dT_d/dx_d.
            %   Inputs   X, samples down the rows; may be narrower than D
            %   Outputs  LP, one log density per row
            %   Utility  evaluate the flow's density, which for a leading
            %           block is Eq. N5 rather than a second model.
            %
            %   With q the standard normal of Eq. N6. Passing the leading m
            %   columns of x returns log p(x_1..x_m), which for m = |S_C| is
            %   the separator density passed up the tree.
            [y, logDeriv] = obj.transform(x);
            lp = sum(-0.5*y.^2 - 0.5*log(2*pi) + logDeriv, 2);
        end

        function x = sample(obj, n, prefix, opts)
            %SAMPLE Eq. N6: draw y ~ N(0,I) and invert.
            %   Inputs   N how many rows, PREFIX values pinning the leading
            %           dimensions, NumDimensions how wide a block to sample
            %   Outputs  X, N samples in raw units
            %   Utility  draw from the flow, jointly or conditionally.
            %
            %   SAMPLE(N) draws N joint samples. SAMPLE(N, PREFIX) holds the
            %   leading variables at PREFIX and draws the rest given them,
            %   which is the conditional sampler p(F_C | S_C) of Algorithm N2.
            %   NumDimensions stops early: the first m columns are a flow in
            %   their own right, so this samples p(x_1..x_m) exactly.
            arguments
                obj (1,1) flows.FlowModel
                n (1,1) double {mustBeInteger, mustBePositive}
                prefix double = zeros(n, 0)
                opts.NumDimensions double {mustBeScalarOrEmpty} = []
            end

            d = opts.NumDimensions;
            if isempty(d)
                d = obj.Dimension;
            end
            if d > obj.Dimension
                error('flows:FlowModel:tooManyDimensions', ...
                    'The flow has %d dimensions; %d were asked for.', ...
                    obj.Dimension, d);
            end
            if ~isempty(prefix) && size(prefix, 1) ~= n
                error('flows:FlowModel:prefixRows', ...
                    ['The prefix must have one row per sample: %d samples ' ...
                     'were asked for but the prefix has %d rows.'], ...
                    n, size(prefix, 1));
            end
            if size(prefix, 2) > d
                error('flows:FlowModel:prefixWidth', ...
                    ['The prefix fixes %d leading variables but only %d are ' ...
                     'being sampled.'], size(prefix, 2), d);
            end

            % The prefix columns overwrite their own draws, so drawing the
            % full width and discarding is simpler than special-casing it.
            x = obj.invert(randn(n, d), prefix);
        end
    end
end
