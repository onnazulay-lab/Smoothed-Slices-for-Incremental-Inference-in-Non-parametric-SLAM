classdef ConditionalFactor
    %CONDITIONALFACTOR The Bayes-net conditional P_hat(omega_j | S_j, D_j).
    %   Implements Eq. (S15) / paper Eq. (17):
    %
    %       P_hat(omega | s) = prod_{f in F_{j-1}(omega)} f(omega, s)
    %                          -------------------------------------
    %                                  f_new_hat(s)
    %
    %   Properties
    %     Frontal, Separator  omega_j and S_j
    %     NumeratorFactors    every removed factor F_{j-1}(omega_j)
    %     Denominator         the stored f_new_hat, or [] at the root
    %     Step, Counter
    %
    %   Methods
    %     evaluate      the ratio, with denominator diagnostics
    %     sampleGiven   draw the frontal variable given separator values
    %     latex         the conditional in the paper's notation
    %
    %   Utility
    %     Represent one Bayes-net conditional as the ratio the spec defines,
    %     without ever forming the normalizer that cancels.
    %
    %   The numerator uses ALL removed factors, including the one that served as
    %   the sampling source; the denominator is the stored mixture of slices.
    %   eta_j^{-1} appears in both and cancels, so it is never computed. The
    %   diagnostics track how close the denominator comes to zero, since that is
    %   this estimator's failure mode.

    properties
        Frontal   (1,1) string
        Separator (1,:) string
        NumeratorFactors (1,:) core.Factor
        % core.ApproximateFactor, or empty for the ROOT conditional. The last
        % eliminated variable has an empty separator, so its "denominator" is
        % the scalar mass; leaving it empty and normalizing numerically over
        % the display grid is both simpler and less lossy than fabricating a
        % zero-dimensional approximate factor.
        Denominator = []
        Step      (1,1) double = 0
        Counter
    end

    methods
        function obj = ConditionalFactor(frontal, separator, numeratorFactors, denominator, opts)
            %CONDITIONALFACTOR Construct the conditional for one step.
            %   Inputs   FRONTAL, SEPARATOR, NUMERATORFACTORS, DENOMINATOR
            %            ([] at the root), and Step/Counter as name-value pairs
            %   Outputs  OBJ
            %   Utility  bind the numerator and denominator together so they
            %            cannot be paired wrongly later.
            arguments
                frontal (1,1) string
                separator (1,:) string
                numeratorFactors (1,:) core.Factor
                denominator = []
                opts.Step (1,1) double = 0
                opts.Counter = []
            end
            if ~isempty(denominator) && ~isa(denominator, 'core.ApproximateFactor')
                error('core:ConditionalFactor:badDenominator', ...
                    'Denominator must be a core.ApproximateFactor or empty.');
            end
            obj.Frontal          = frontal;
            obj.Separator        = separator;
            obj.NumeratorFactors = numeratorFactors;
            obj.Denominator      = denominator;
            obj.Step             = opts.Step;
            obj.Counter          = opts.Counter;
        end

        function [v, diag] = evaluate(obj, assignment)
            %EVALUATE Conditional value at (omega, separator).
            %   Inputs   ASSIGNMENT, containing the frontal variable and every
            %            separator variable, shaped so they broadcast
            %   Outputs  V     the conditional value, zero where unsupported
            %            DIAG  min/median denominator, zero fraction, non-finite
            %                  count -- requested only if asked for
            %   Utility  evaluate the ratio and report how near the denominator
            %            came to zero, which is where this estimator fails.
            num = ones(1);
            for i = 1:numel(obj.NumeratorFactors)
                num = num .* obj.NumeratorFactors(i).evaluate(assignment);
            end

            if isempty(obj.Denominator)
                % Root conditional: the numerator IS the unnormalized
                % marginal. Normalization happens once, numerically, in the
                % backward pass.
                den = 1;
            else
                frontalKey = matlab.lang.makeValidName(obj.Frontal);
                sepAssign  = assignment;
                if isfield(sepAssign, frontalKey)
                    sepAssign = rmfield(sepAssign, frontalKey);
                end
                den = obj.Denominator.evaluate(sepAssign);
            end

            % Implicit expansion keeps this valid when num is |grid| x |S|
            % and den is 1 x |S|: unsupported separator values are zeroed
            % rather than producing Inf/NaN.
            v = num ./ den;
            v = v .* (den > 0);
            v(~isfinite(v)) = 0;

            if nargout > 1
                diag = struct( ...
                    'minDenominator',  min(den(:)), ...
                    'medDenominator',  median(den(:)), ...
                    'zeroFraction',    mean(den(:) <= 0), ...
                    'nonFinite',       sum(~isfinite(v(:))));
            end
        end

        function s = sampleGiven(obj, separatorValues, n, grid)
            %SAMPLEGIVEN Draw N samples of the frontal variable.
            %   Inputs   SEPARATORVALUES a struct of separator assignments,
            %            N the number of draws, GRID the 1-D sampling grid
            %   Outputs  S, N-by-1 draws
            %   Utility  sample a conditional available only as a pointwise
            %            ratio.
            %
            %   Inverse-CDF on the supplied grid, which is a deliberate choice
            %   for the low-dimensional demonstrator and is flagged as such in
            %   the diagnostics rather than presented as general.
            arguments
                obj (1,1) core.ConditionalFactor
                separatorValues struct
                n (1,1) double {mustBeInteger, mustBePositive}
                grid (1,:) double
            end

            a = separatorValues;
            a.(matlab.lang.makeValidName(obj.Frontal)) = grid(:);
            w = obj.evaluate(a);
            w = reshape(w, numel(grid), []);
            w = sum(w, 2);

            s = core.ConditionalFactor.inverseCdfSample(grid(:), w, n);
        end

        function s = latex(obj)
            %LATEX The conditional in the paper's notation.
            %   Inputs   none
            %   Outputs  S, a char row of LaTeX math
            %   Utility  title a panel with the conditional it is drawing.
            fr  = regexprep(obj.Frontal, '^([a-zA-Z]+)(\d+)$', '$1_{$2}');
            sep = arrayfun(@(v) regexprep(v, '^([a-zA-Z]+)(\d+)$', '$1_{$2}'), obj.Separator);
            if isempty(sep)
                s = sprintf('$\\hat P(%s \\mid D)$', fr);
            else
                s = sprintf('$\\hat P(%s \\mid %s, D)$', fr, strjoin(cellstr(sep), ','));
            end
        end
    end

    methods (Static)
        function s = inverseCdfSample(grid, weights, n)
            %INVERSECDFSAMPLE Sample a 1-D grid density by inverse CDF.
            %   Inputs   GRID the points, WEIGHTS their unnormalized density,
            %            N the number of draws
            %   Outputs  S, N-by-1 draws
            %   Utility  turn a tabulated density into samples; errors on zero
            %            mass rather than returning arbitrary points.
            w = max(weights(:), 0);
            if ~any(w > 0)
                error('core:ConditionalFactor:degenerate', ...
                    'Conditional has zero mass on the supplied grid.');
            end
            cdf = cumsum(w) / sum(w);
            [cdf, keep] = unique(cdf, 'stable');
            s = interp1(cdf, grid(keep), rand(n, 1), 'linear', 'extrap');
        end
    end
end
