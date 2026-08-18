classdef SliceConditional
    %SLICECONDITIONAL A Bayes-net conditional p(omega | S) held as slices.
    %
    %   Properties
    %     FrontalVar, FrontalSamples   omega and its |X|-by-d outer samples
    %     Separator, SeparatorDims, SeparatorSupport   S and its |S|-by-d_s cloud
    %     SliceMatrix                  |X|-by-|S| slice values
    %     Step, Diagnostics
    %     NumSamples, NumSupport, FrontalDim   dependent
    %
    %   Methods
    %     sample               draw omega given separator values
    %     columnFor            the normalized slice at one separator value
    %     effectiveSampleSize  per-column ESS
    %     describe, latex
    %
    %   Utility
    %     Hold one step's conditional in the only form the Slices perspective
    %     allows -- slice values, never a fitted density.
    %
    %       SliceMatrix(n, i)  proportional to  p(omega^(n) | s_i)
    %
    %   Column i is the conditional at separator support point s_i, evaluated
    %   at the |X| outer samples. Sampling omega given s means picking a
    %   column and then drawing a row index in proportion to that column,
    %   which is Eq. (S15) with the normalizer eta_j cancelling column by
    %   column instead of being estimated.
    %
    %   OFF-SUPPORT CONDITIONING is a nearest-neighbour lookup on the support
    %   point cloud. That is the approximation of a finite support in more
    %   than one dimension, it is the same one core.ApproximateFactor makes,
    %   and NEARESTDISTANCE reports how far the lookup had to travel so the
    %   cost of it is measurable rather than assumed.

    properties
        FrontalVar      (1,1) string
        FrontalSamples  (:,:) double     % |X| x d_omega
        Separator       (1,:) string
        SeparatorDims   (1,:) double
        SeparatorSupport (:,:) double    % |S| x d_s
        SliceMatrix     (:,:) double     % |X| x |S|
        Step            (1,1) double = 0
        Diagnostics     struct = struct()
    end

    properties (Dependent)
        NumSamples
        NumSupport
        FrontalDim
    end

    methods
        function obj = SliceConditional(frontalVar, frontalSamples, separator, ...
                                        sepDims, support, sliceMatrix, opts)
            %SLICECONDITIONAL Construct from a slice matrix and its two supports.
            %   Inputs   FRONTALVAR, FRONTALSAMPLES, SEPARATOR, SEPDIMS,
            %            SUPPORT, SLICEMATRIX, and Step/Diagnostics as pairs
            %   Outputs  OBJ
            %   Utility  bind the matrix to the two supports it is indexed by,
            %            and refuse a matrix whose shape disagrees with them.
            arguments
                frontalVar (1,1) string
                frontalSamples (:,:) double
                separator (1,:) string
                sepDims (1,:) double
                support (:,:) double
                sliceMatrix (:,:) double
                opts.Step (1,1) double = 0
                opts.Diagnostics struct = struct()
            end
            if size(sliceMatrix, 1) ~= size(frontalSamples, 1)
                error('core:SliceConditional:rowMismatch', ...
                    'Slice matrix has %d rows but %d outer samples were given.', ...
                    size(sliceMatrix, 1), size(frontalSamples, 1));
            end
            if size(sliceMatrix, 2) ~= size(support, 1)
                error('core:SliceConditional:columnMismatch', ...
                    'Slice matrix has %d columns but |S| = %d.', ...
                    size(sliceMatrix, 2), size(support, 1));
            end
            obj.FrontalVar       = frontalVar;
            obj.FrontalSamples   = frontalSamples;
            obj.Separator        = separator;
            obj.SeparatorDims    = sepDims;
            obj.SeparatorSupport = support;
            obj.SliceMatrix      = sliceMatrix;
            obj.Step             = opts.Step;
            obj.Diagnostics      = opts.Diagnostics;
        end

        function n = get.NumSamples(obj), n = size(obj.FrontalSamples, 1); end
        function n = get.NumSupport(obj), n = size(obj.SeparatorSupport, 1); end
        function d = get.FrontalDim(obj), d = size(obj.FrontalSamples, 2); end

        function [vals, idx, dist] = sample(obj, sepValues)
            %SAMPLE Draw the frontal variable given separator values.
            %   Inputs   SEPVALUES, N-by-d_s separator values, one per row
            %   Outputs  VALS  N draws of the frontal variable
            %            IDX   the outer-sample row indices drawn
            %            DIST  how far each query sat from its nearest support
            %                  point, so the lookup's cost is measurable
            %   Utility  sample the conditional by picking a column and then a
            %            row in proportion to it, which is Eq. (S15) with eta_j
            %            cancelling column by column instead of being estimated.
            arguments
                obj (1,1) core.SliceConditional
                sepValues (:,:) double
            end
            n = size(sepValues, 1);
            % knnsearch rather than an exhaustive pdist2: see the note in
            % core.ApproximateFactor.interpolate.
            [col, dist] = knnsearch(obj.SeparatorSupport, sepValues);
            col = col(:);
            dist = dist(:);

            % Group the queries by the support column they landed on. Many
            % traversal particles snap to the same support point, and the
            % cumulative sum of a column is the expensive part, so it is
            % worth doing once per distinct column rather than once per
            % particle.
            idx = zeros(n, 1);
            [uCol, ~, back] = unique(col);
            for c = 1:numel(uCol)
                rows = find(back == c);
                idx(rows) = core.categoricalSample( ...
                    obj.SliceMatrix(:, uCol(c)), numel(rows));
            end
            vals = obj.FrontalSamples(idx, :);
        end

        function w = columnFor(obj, sepValue)
            %COLUMNFOR The conditional slice at one separator value.
            %   Inputs   SEPVALUE, a single 1-by-d_s separator point
            %   Outputs  W, the normalized column; all zeros stay all zeros
            %   Utility  read out one conditional for plotting or comparison.
            col = knnsearch(obj.SeparatorSupport, sepValue);
            w = obj.SliceMatrix(:, col);
            s = sum(w);
            if s > 0, w = w / s; end
        end

        function e = effectiveSampleSize(obj)
            %EFFECTIVESAMPLESIZE Per-column ESS of the conditional weights.
            %   Inputs   none
            %   Outputs  E, 1-by-|S|
            %   Utility  find the separator points where the representation has
            %            collapsed.
            %
            %   A column with an ESS near one is a conditional carried by a
            %   single outer sample, and no amount of downstream sampling
            %   recovers it.
            s1 = sum(obj.SliceMatrix, 1);
            s2 = sum(obj.SliceMatrix.^2, 1);
            e = (s1.^2) ./ max(s2, realmin);
            e(s1 <= 0) = 0;
        end

        function s = describe(obj)
            %DESCRIBE One-line summary with both support sizes.
            %   Inputs   none
            %   Outputs  S, a char row
            %   Utility  identify the conditional in a log.
            s = sprintf('p(%s | %s) [|X|=%d, |S|=%d, d_s=%d]', ...
                obj.FrontalVar, strjoin(cellstr(obj.Separator), ','), ...
                obj.NumSamples, obj.NumSupport, sum(obj.SeparatorDims));
        end

        function s = latex(obj)
            %LATEX The conditional in the paper's notation.
            %   Inputs   none
            %   Outputs  S, a char row of LaTeX math
            %   Utility  title a panel with the conditional it draws.
            frontal = regexprep(obj.FrontalVar, '^([a-zA-Z]+)(\d+)$', '$1_{$2}');
            sep = arrayfun(@(v) regexprep(v, '^([a-zA-Z]+)(\d+)$', '$1_{$2}'), ...
                obj.Separator);
            s = sprintf('$p(%s \\mid %s)$', frontal, strjoin(cellstr(sep), ','));
        end
    end

    methods (Static)
        function i = drawIndex(w)
            %DRAWINDEX One categorical draw from unnormalized weights.
            %   Inputs   W, a column of unnormalized weights
            %   Outputs  I, one index into W
            %   Utility  draw a row of a slice column.
            %
            %   A column of all zeros means the support point sits where no outer
            %   sample has any mass. core.categoricalSample falls back to uniform
            %   there, which keeps the backward pass running and surfaces in the
            %   caller's ESS, the honest place for it.
            i = core.categoricalSample(w(:), 1);
        end
    end
end
