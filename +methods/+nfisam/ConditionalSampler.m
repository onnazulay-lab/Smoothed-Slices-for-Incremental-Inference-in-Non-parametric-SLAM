classdef ConditionalSampler
    %CONDITIONALSAMPLER What Algorithm N2 returns: the clique's two samplers.
    %
    %   Properties
    %     Flow              the trained flows.FlowModel
    %     Observations, Separator, Frontal   the clique's variables, by block
    %     Names, Widths     [O S F] and the columns each name occupies
    %     ObservationValue  o_C, raw units, one row
    %     Columns           which column indices are which block
    %
    %   Methods
    %     sampleSeparator    p(S_C | z_C)         passed up in Algorithm N3
    %     separatorLogProb   log p(S_C | z_C)     the density half of the same
    %     sampleFrontal      p(F_C | S_C, z_C)    cached for the downward pass
    %     sampleClique       S_C and F_C together, as a dictionary
    %     separatorWidth, separatorWidths, frontalWidth, frontalWidths
    %
    %   Utility
    %     Hold the one trained flow per clique, and offer it as the two
    %     samplers the algorithm names.
    %
    %   Spec section 1 names two objects, a ConditionalSampler wrapping
    %   p(F_C|S_C,z_C) and a SeparatorDensity wrapping T_S. They are one class
    %   here because after step 3 of Algorithm N2 they are one flow:
    %
    %       T_C(S_C,F_C) = [ T~_S(O_C=o_C, S_C) , T~_F(O_C=o_C, S_C, F_C) ]'
    %
    %   which is Eq. N10. The partition of Eq. N8 is a partition of COLUMNS,
    %   not a pair of trained models, so splitting it into two objects would
    %   store the same flow twice and let the two copies drift apart. What the
    %   spec asks for is that both operations be available, and they are:
    %
    %     SAMPLESEPARATOR    p(S_C | z_C)         passed up in Algorithm N3
    %     SEPARATORLOGPROB   log p(S_C | z_C)     the density half of the same
    %     SAMPLEFRONTAL      p(F_C | S_C, z_C)    cached for the downward pass
    %
    %   FIXING THE OBSERVATIONS IS A PREFIX. Every one of those calls hands
    %   the measured values o_C to the flow as the leading, already-known
    %   block. Nothing is retrained and no parameter is touched: because the
    %   map is triangular, conditioning on the first columns is exactly what
    %   the inverse of Eq. N6 does when it is not asked to solve them. That is
    %   why step 3 of Algorithm N2 is an assignment in the paper and a
    %   function argument here.
    %
    %   WHAT THE COLUMNS MEAN. The flow sees a matrix; this object holds the
    %   layout that says which columns are which variable, so callers work in
    %   variable names and the flow never has to know any. Widths are per
    %   variable, so a planar landmark is one name over two columns.
    %
    %   A value class. A clique caches its sampler and Algorithm N3 reuses it
    %   for every clique outside the changed subtree, so it must not be
    %   possible to modify one through a handle held somewhere else.

    properties (SetAccess = immutable)
        Flow                                % flows.FlowModel, trained, with O first
        Observations     (1,:) string        % O_C, in the order N1 created them
        Separator        (1,:) string        % S_C
        Frontal          (1,:) string        % F_C
        Names            (1,:) string        % [O S F], the flow's column order
        Widths           (1,:) double        % columns per name
        ObservationValue (1,:) double        % o_C, raw units, one row
        Columns          (1,1) struct        % .observations .separator .frontal
    end

    methods

        function obj = ConditionalSampler(flow, opts)
            %CONDITIONALSAMPLER Wrap a trained flow with its clique layout.
            %   Inputs   FLOW, then the O/S/F names, their Widths, and the
            %           measured ObservationValue
            %   Outputs  OBJ
            %   Utility  attach the layout, so callers work in variable names
            %           and the flow never has to know any.
            arguments
                flow (1,1) {mustBeA(flow, 'flows.FlowModel')}
                opts.Observations (1,:) string = string.empty(1,0)
                opts.Separator (1,:) string = string.empty(1,0)
                opts.Frontal (1,:) string = string.empty(1,0)
                opts.Widths (1,:) double {mustBeInteger, mustBePositive}
                opts.ObservationValue (1,:) double = zeros(1,0)
            end

            obj.Flow         = flow;
            obj.Observations = opts.Observations;
            obj.Separator    = opts.Separator;
            obj.Frontal      = opts.Frontal;
            obj.Names        = [opts.Observations opts.Separator opts.Frontal];
            obj.Widths       = opts.Widths;

            if numel(obj.Widths) ~= numel(obj.Names)
                error('methods:nfisam:ConditionalSampler:widthCount', ...
                    '%d variable(s) against %d width(s).', ...
                    numel(obj.Names), numel(obj.Widths));
            end
            if sum(obj.Widths) ~= flow.Dimension
                error('methods:nfisam:ConditionalSampler:flowWidth', ...
                    ['The layout accounts for %d column(s) but the flow has ' ...
                     '%d dimension(s).'], sum(obj.Widths), flow.Dimension);
            end

            nO = numel(opts.Observations);
            nS = numel(opts.Separator);
            ends = cumsum([0 obj.Widths]);
            obj.Columns = struct( ...
                'observations', 1:ends(nO+1), ...
                'separator',    ends(nO+1)+1 : ends(nO+nS+1), ...
                'frontal',      ends(nO+nS+1)+1 : ends(end));

            obj.ObservationValue = opts.ObservationValue;
            if numel(obj.ObservationValue) ~= numel(obj.Columns.observations)
                error('methods:nfisam:ConditionalSampler:observationWidth', ...
                    ['%d observation column(s) but %d measured value(s). ' ...
                     'Fixing O_C = o_C needs one value per column.'], ...
                    numel(obj.Columns.observations), numel(obj.ObservationValue));
            end
        end

        function s = sampleSeparator(obj, n)
            %SAMPLESEPARATOR Draw from p(S_C | z_C), Eq. N6 through T_S.
            %   Inputs   N, how many draws
            %   Outputs  S, N-by-separatorWidth
            %   Utility  what a clique passes up to its parent.
            %
            %   Only the leading O and S columns are solved. The frontals are
            %   not drawn and not needed: the leading block of a triangular
            %   map is a flow in its own right, which is the whole content of
            %   the Eq. N8 partition.
            arguments
                obj (1,1) methods.nfisam.ConditionalSampler
                n (1,1) double {mustBeInteger, mustBePositive}
            end

            if isempty(obj.Separator)
                s = zeros(n, 0);        % a root clique has nothing to pass up
                return
            end
            m = obj.Columns.separator(end);
            x = obj.Flow.invert(randn(n, m), obj.fixedPrefix(n));
            s = x(:, obj.Columns.separator);
        end

        function lp = separatorLogProb(obj, s)
            %SEPARATORLOGPROB log p(S_C = s | z_C), the density half of T_S.
            %   Inputs   S, separator values, one per row
            %   Outputs  LP, one log density per row
            %   Utility  weight a parent's existing draws by this child's
            %           separator density, in combineChildSeparators.
            %
            %   Eq. N5 chained over the separator columns only. Summing the
            %   observation columns as well would give log p(o, s), which is
            %   not what the parent clique is owed: the measurement is fixed,
            %   not a random variable to be scored again.
            arguments
                obj (1,1) methods.nfisam.ConditionalSampler
                s (:,:) double
            end

            n = size(s, 1);
            if isempty(obj.Separator)
                lp = zeros(n, 1);       % the empty product, at the root
                return
            end
            obj.checkSeparator(s);

            [y, logDeriv] = obj.Flow.transform([obj.fixedPrefix(n) s]);
            c = obj.Columns.separator;
            lp = sum(-0.5*y(:,c).^2 - 0.5*log(2*pi) + logDeriv(:,c), 2);
        end

        function f = sampleFrontal(obj, s)
            %SAMPLEFRONTAL Draw from p(F_C | S_C = s, z_C), one row per row of s.
            %   Inputs   S, the separator values the parent drew
            %   Outputs  F, one frontal draw per row of S
            %   Utility  the downward pass of Algorithm N3.
            %
            %   The cached conditional sampler of Algorithm N3 step 5: the
            %   separator values arrive from the parent's own draw, so each
            %   row is conditioned on a different separator sample.
            arguments
                obj (1,1) methods.nfisam.ConditionalSampler
                s (:,:) double
            end

            n = size(s, 1);
            obj.checkSeparator(s);
            if n == 0
                f = zeros(0, numel(obj.Columns.frontal));
                return
            end

            prefix = [obj.fixedPrefix(n) s];
            x = obj.Flow.invert(randn(n, obj.Flow.Dimension), prefix);
            f = x(:, obj.Columns.frontal);
        end

        function [D, X] = sampleClique(obj, n)
            %SAMPLECLIQUE Draw S_C and F_C together, as a sample dictionary.
            %   Inputs   N, how many draws
            %   Outputs  D the dictionary, X the same draws as a matrix
            %   Utility  what a root clique needs, and what a test needs to
            %           look at the clique posterior as a whole.
            %
            %   The separator and its frontals from one pass of Eq. N6, which
            %   is what a root clique needs and what a test needs to look at
            %   the clique posterior as a whole. The observation columns are
            %   dropped: they are the measurement, held at o_C in every row,
            %   and returning them would put a constant in among the samples.
            arguments
                obj (1,1) methods.nfisam.ConditionalSampler
                n (1,1) double {mustBeInteger, mustBePositive}
            end

            x = obj.Flow.invert(randn(n, obj.Flow.Dimension), obj.fixedPrefix(n));
            X = x(:, [obj.Columns.separator obj.Columns.frontal]);
            nO = numel(obj.Observations);
            D = methods.nfisam.unpackSamples(X, ...
                obj.Names(nO+1:end), obj.Widths(nO+1:end));
        end

        function d = separatorWidth(obj)
            %SEPARATORWIDTH How many columns the separator occupies in total.
            %   Inputs   none
            %   Outputs  D, the column count
            %   Utility  check a separator matrix handed in from outside.
            d = numel(obj.Columns.separator);
        end

        function w = separatorWidths(obj)
            %SEPARATORWIDTHS Columns per separator VARIABLE, not in total.
            %   Inputs   none
            %   Outputs  W, one width per separator variable
            %   Utility  cut a block of separator draws back into named
            %           variables.
            %
            %   What METHODS.NFISAM.UNPACKSAMPLES needs to turn a block of
            %   separator draws back into named variables for the parent
            %   clique, and the one thing the matrix itself cannot say.
            nO = numel(obj.Observations);
            w = obj.Widths(nO + (1:numel(obj.Separator)));
        end

        function d = frontalWidth(obj)
            %FRONTALWIDTH How many columns the frontals occupy in total.
            %   Inputs   none
            %   Outputs  D, the column count
            %   Utility  size the block the downward pass draws.
            d = numel(obj.Columns.frontal);
        end

        function w = frontalWidths(obj)
            %FRONTALWIDTHS Columns per frontal VARIABLE, not in total.
            %   Inputs   none
            %   Outputs  W, one width per frontal variable
            %   Utility  cut a block of drawn frontals back into named
            %           variables.
            %
            %   The counterpart of SEPARATORWIDTHS, and what the root-to-leaf
            %   pass of METHODS.NFISAM.SAMPLEJOINTPOSTERIOR needs to cut a
            %   block of drawn frontals back into named variables.
            nO = numel(obj.Observations);
            nS = numel(obj.Separator);
            w = obj.Widths(nO + nS + (1:numel(obj.Frontal)));
        end
    end

    methods (Access = private)

        function p = fixedPrefix(obj, n)
            %FIXEDPREFIX o_C repeated, the leading block of every call.
            %   Inputs   N, how many rows
            %   Outputs  P, o_C repeated N times
            %   Utility  step 3 of Algorithm N2 is this prefix and nothing
            %           else; no parameter is touched to apply it.
            p = repmat(obj.ObservationValue, n, 1);
        end

        function checkSeparator(obj, s)
            %CHECKSEPARATOR Refuse a separator matrix of the wrong width.
            %   Inputs   S, the separator values
            %   Outputs  none; throws
            %   Utility  a mismatched width would be read as a prefix over the
            %           wrong variables and would sample silently wrong.
            if size(s, 2) ~= numel(obj.Columns.separator)
                error('methods:nfisam:ConditionalSampler:separatorWidth', ...
                    ['The separator of this clique is %d column(s) wide; %d ' ...
                     'were given. The parent draws S_C, so a mismatch means ' ...
                     'the two cliques disagree about what they share.'], ...
                    numel(obj.Columns.separator), size(s, 2));
            end
        end
    end
end
