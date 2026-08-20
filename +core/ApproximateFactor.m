classdef ApproximateFactor
    %APPROXIMATEFACTOR The generated separator factor f_new_hat(S_j | D_j).
    %
    %   Inputs   SCOPE, ELIMINATEDVAR, SAMPLES and REMAINING, with options;
    %            the static TABULATED builds the finite mode instead
    %   Outputs  one factor, evaluable at query points and samplable slice
    %            by slice, never a fitted density
    %
    %   Properties
    %     Mode                      "mixture" (lazy) or "tabulated" (finite)
    %     Scope, ScopeDims          the separator S_j and each variable's dim
    %     EliminatedVar             omega_j
    %     Samples                   |X|-by-d outer support
    %     Remaining                 the removed factors other than f'
    %     Support, SliceMatrix      tabulated mode only
    %     Diagnostics               includes which off-support rule was used
    %     NumSamples, SampleDim, SeparatorDim   dependent
    %
    %   Methods
    %     evaluate            f_new_hat at query points
    %     evaluateSlices      the per-slice values, unaveraged
    %     sampleSlices        draw the outer variable from a slice factor
    %     findSliceSampler, canSampleSlices
    %     sliceFactorsInvolving, sliceFactorsExcluding
    %     toFactor            wrap as a plain core.Factor
    %     describe, latex
    %     tabulated (static)  build in tabulated mode
    %
    %   Utility
    %     Represent the factor an elimination generates WITHOUT fitting a
    %     density to it, which is the whole point of the Slices perspective.
    %
    %   Never a KDE and never a reconstructed density: this object is always a
    %   MIXTURE OF SLICES. It supports two storage modes.
    %
    %   Mode "mixture" (lazy). Each slice n is the product of the removed
    %   factors other than the sampling factor f', evaluated at the sampled
    %   value omega_j^(n):
    %
    %       f_new_hat(s) = (c / N) * sum_n prod_{f in Remaining} f(omega^(n), s)
    %
    %   with c = eta_j^{-1} * Z_{f'} (Eq. S8; Eq. 7 of the Smoothed Slices
    %   spec). eta_j^{-1} is carried as 1, and ScaleIsRelative records that
    %   the absolute scale is unknown, because it cancels in the conditional
    %   estimator (Eq. S15). Mixture mode is dimension-agnostic and is the
    %   only mode the grid-world case uses: a planar separator of three or
    %   four variables cannot be tabulated, but it can always be sliced.
    %
    %   Mode "tabulated" (finite support). The slices are already evaluated
    %   on a finite separator support S with |S| = R_s, and stored as an
    %   |X| x |S| matrix. This is the representation the second elimination
    %   needs, because that is exactly where the paper's nested estimator and
    %   the RCS surface recursion produce their answers: both hand back an
    %   |X_0| x |S| slice matrix, computed differently.
    %
    %   SHAPE CONVENTION. Samples are |X|-by-SampleDim and the separator
    %   support is |S|-by-sum(ScopeDims): points down the rows, coordinates
    %   across the columns, as documented on core.Variable. When every scope
    %   variable is scalar the legacy broadcast query of iteration 1 is still
    %   accepted and the result keeps the query's shape, so a column-oriented
    %   root query and a row-oriented denominator query both work.
    %
    %   OFF-SUPPORT QUERIES. A scalar separator interpolates linearly. A
    %   vector separator falls back to nearest neighbour on the support point
    %   cloud, because a scattered interpolant per slice is not affordable at
    %   |X| slices. Which rule was used is written into Diagnostics rather
    %   than left implicit, since it is an approximation the reader must be
    %   able to see.

    properties
        Mode           (1,1) string {mustBeMember(Mode, ["mixture","tabulated"])} = "mixture"
        Scope          (1,:) string      % separator variables S_j
        ScopeDims      (1,:) double = [] % dimension of each scope variable
        EliminatedVar  (1,1) string      % omega_j
        Samples        (:,:) double      % support of the outer variable, |X| x d
        SampleWeights  (:,1) double = [] % importance weight of each sample
        LogScale       (1,1) double = 0  % log c
        ScaleIsRelative (1,1) logical = true
        Diagnostics    struct = struct()
        Counter                          % core.EvalCounter handle or []
        % Tabulated factors keep their mixture, so they can answer either by
        % lookup or exactly. Exact costs |X| factor evaluations per query and
        % is what a separator of four or more dimensions needs.
        ExactEvaluation (1,1) logical = false
        MaxExpandedRows (1,1) double = 2e6

        % --- mixture mode -------------------------------------------------
        RemainingFactors (1,:) core.Factor
        SourceFactorName (1,1) string

        % --- tabulated mode -----------------------------------------------
        SeparatorSupport (:,:) double    % S, |S| x d_s
        SliceMatrix      (:,:) double    % |X| x |S|
    end

    properties (Dependent)
        NumSamples
        SampleDim
        SeparatorDim
    end

    methods
        function obj = ApproximateFactor(scope, eliminatedVar, samples, remaining, opts)
            %APPROXIMATEFACTOR Construct in mixture mode.
            %   Inputs   SCOPE, ELIMINATEDVAR, SAMPLES, REMAINING, and options
            %            including ScopeDims, SourceFactorName and Counter
            %   Outputs  OBJ
            %   Utility  hold the slices lazily, for a separator too large to
            %            tabulate.
            arguments
                scope (1,:) string
                eliminatedVar (1,1) string
                samples (:,:) double
                remaining (1,:) core.Factor
                opts.SourceFactorName (1,1) string = ""
                opts.LogScale (1,1) double = 0
                opts.Diagnostics struct = struct()
                opts.Counter = []
                opts.ScopeDims (1,:) double = []
            end
            obj.Mode             = "mixture";
            obj.Scope            = scope;
            obj.EliminatedVar    = eliminatedVar;
            obj.Samples          = samples;
            obj.RemainingFactors = remaining;
            obj.SourceFactorName = opts.SourceFactorName;
            obj.LogScale         = opts.LogScale;
            obj.Diagnostics      = opts.Diagnostics;
            obj.Counter          = opts.Counter;

            dims = opts.ScopeDims;
            if isempty(dims), dims = ones(1, numel(scope)); end
            if numel(dims) ~= numel(scope)
                error('core:ApproximateFactor:scopeDimMismatch', ...
                    'ScopeDims has %d entries for a scope of %d variable(s).', ...
                    numel(dims), numel(scope));
            end
            obj.ScopeDims = dims;
        end

        function n = get.NumSamples(obj),   n = size(obj.Samples, 1); end
        function d = get.SampleDim(obj),    d = max(1, size(obj.Samples, 2)); end
        function d = get.SeparatorDim(obj), d = sum(obj.ScopeDims); end

        function tf = isScalarSeparator(obj)
            %ISSCALARSEPARATOR True when the whole separator is one scalar.
            %   Inputs   none
            %   Outputs  TF, logical
            %   Utility  decide whether linear interpolation is available, since
            %            it is only defined on a line.
            tf = all(obj.ScopeDims == 1);
        end

        function v = evaluate(obj, assignment)
            %EVALUATE f_new_hat at the assignment's separator points.
            %   Inputs   ASSIGNMENT, a struct of separator values
            %   Outputs  V, the slice average, keeping the query's shape
            %   Utility  use the generated factor like any other factor.
            %
            %   Returns a value shaped like the query, exactly as an ordinary
            %   core.Factor does, so the two are interchangeable inside a
            %   product. This matters because a generated factor is queried
            %   in two different orientations: as a ROW of separator samples
            %   when it is the denominator of a conditional, and as a COLUMN
            %   grid when it is the numerator of the root conditional, the
            %   last eliminated variable being its own scope.
            [pts, shp] = obj.queryPoints(assignment);

            if obj.Mode == "mixture" || obj.ExactEvaluation
                % Exact: re-form the slices from the retained mixture. In one
                % dimension this is merely tidier than interpolating, but in
                % four or more it is the difference between an answer and a
                % plausible one. Nearest-neighbour lookup of a sharply peaked
                % function on a scattered support is biased, not just noisy,
                % and seventeen eliminations compound that bias into a
                % confident wrong answer -- small posterior variance around a
                % mean ten metres from the truth.
                slices = obj.evaluateSlicesAt(pts);          % |X| x Q
                v = exp(obj.LogScale) * mean(slices, 1);     % 1 x Q
            else
                vals = mean(obj.SliceMatrix, 1);             % 1 x |S|
                v = exp(obj.LogScale) * obj.interpolate(vals.', pts).';
            end
            v = reshape(v, shp);
        end

        function slices = evaluateSlices(obj, assignment)
            %EVALUATESLICES The per-slice values, before averaging.
            %   Inputs   ASSIGNMENT, a struct of separator values
            %   Outputs  SLICES, |X|-by-(number of query points)
            %   Utility  give the conditional estimator the matrix it needs; the
            %            average alone would discard the per-sample structure.
            %
            %   Returns an |X| x Q array over the Q query points. The Slices
            %   method's whole point is that this object stays a set of
            %   slices, so the backward pass and the conditional estimator can
            %   reuse them. The query is flattened: per-slice values are only
            %   ever wanted as a matrix, and flattening avoids inventing a
            %   shape convention that collides with the column-oriented root
            %   query.
            pts = obj.queryPoints(assignment);

            if obj.Mode == "mixture" || obj.ExactEvaluation
                slices = obj.evaluateSlicesAt(pts);
            else
                slices = obj.interpolate(obj.SliceMatrix.', pts).';
            end
        end

        function [smp, logZ] = sampleSlices(obj, targetVar, m)
            %SAMPLESLICES Draw TARGETVAR from a slice factor that can sample it.
            %   Inputs   TARGETVAR the variable to draw, M draws per slice
            %   Outputs  SMP the draws, LOGZ the sampling factor's log mass
            %   Utility  continue the Lemma 1 chain through a generated factor.
            %
            %   [SMP, LOGZ] = SAMPLESLICES(OBJ, TARGETVAR, M) draws M samples
            %   of TARGETVAR from each stored slice, returning an |X| x M
            %   array (scalar target) or an |X| x M x d array (vector target)
            %   and the per-slice log normalizers log Z(omega^(n)).
            %
            %   This is the structural route of Lemma 1: TARGETVAR has no
            %   unary factor of its own, but inside this approximate factor it
            %   is conditionally sampleable given the already-sampled
            %   eliminated variable. Nothing is ever drawn from f_new_hat
            %   itself, which is not a density in TARGETVAR alone.
            arguments
                obj (1,1) core.ApproximateFactor
                targetVar (1,1) string
                m (1,1) double {mustBeInteger, mustBePositive}
            end
            obj.assertMixtureMode('sampleSlices');

            src   = obj.findSliceSampler(targetVar);
            given = struct(matlab.lang.makeValidName(obj.EliminatedVar), obj.Samples);

            smp  = src.sample(targetVar, given, m);
            logZ = reshape(src.logNormalizer(targetVar, given), [], 1);
            if isscalar(logZ)
                logZ = repmat(logZ, obj.NumSamples, 1);
            end
        end

        function f = findSliceSampler(obj, targetVar)
            %FINDSLICESAMPLER A remaining factor that can sample TARGETVAR.
            %   Inputs   TARGETVAR
            %   Outputs  F, the factor; empty when none can
            %   Utility  locate the proposal Lemma 1 promises exists.
            obj.assertMixtureMode('findSliceSampler');
            for i = 1:numel(obj.RemainingFactors)
                f = obj.RemainingFactors(i);
                if f.involves(targetVar) && f.involves(obj.EliminatedVar) ...
                        && f.canSample(targetVar)
                    return
                end
            end
            error('core:ApproximateFactor:noSliceSampler', ...
                ['No slice of %s makes %s sampleable. The elimination order ' ...
                 'violates the Lemma 1 condition.'], obj.describe(), targetVar);
        end

        function tf = canSampleSlices(obj, targetVar)
            %CANSAMPLESLICES True when some remaining factor samples TARGETVAR.
            %   Inputs   TARGETVAR
            %   Outputs  TF, logical
            %   Utility  test the Lemma 1 condition without drawing anything.
            tf = obj.Mode == "mixture";
            if tf
                try
                    obj.findSliceSampler(targetVar);
                catch
                    tf = false;
                end
            end
        end

        function fk = sliceFactorsInvolving(obj, varName)
            %SLICEFACTORSINVOLVING The remaining factors whose scope has VARNAME.
            %   Inputs   VARNAME
            %   Outputs  FK, a core.Factor array
            %   Utility  split the slice product around one variable.
            obj.assertMixtureMode('sliceFactorsInvolving');
            keep = arrayfun(@(f) f.involves(varName), obj.RemainingFactors);
            fk = obj.RemainingFactors(keep);
        end

        function fk = sliceFactorsExcluding(obj, varName)
            %SLICEFACTORSEXCLUDING The remaining factors without VARNAME.
            %   Inputs   VARNAME
            %   Outputs  FK, a core.Factor array
            %   Utility  the other half of the split, so the two together are
            %            the whole product and neither is counted twice.
            %
            %   At the second elimination these are the front factors b_0 of
            %   Eq. (41): they connect the outer sampled variable straight to
            %   the final separator and must stay in the product.
            obj.assertMixtureMode('sliceFactorsExcluding');
            keep = arrayfun(@(f) ~f.involves(varName), obj.RemainingFactors);
            fk = obj.RemainingFactors(keep);
        end

        function s = describe(obj)
            %DESCRIBE One-line summary of scope, mode and support sizes.
            %   Inputs   none
            %   Outputs  S, a char row
            %   Utility  identify the factor in a log.
            s = sprintf('f_new_hat(%s | D) [omega=%s, |X|=%d, mode=%s, source=%s]', ...
                strjoin(cellstr(obj.Scope), ','), obj.EliminatedVar, ...
                obj.NumSamples, obj.Mode, obj.SourceFactorName);
        end

        function s = latex(obj)
            %LATEX The factor in the paper's notation.
            %   Inputs   none
            %   Outputs  S, a char row of LaTeX math
            %   Utility  label a figure panel.
            scope = arrayfun(@(v) regexprep(v, '^([a-zA-Z]+)(\d+)$', '$1_{$2}'), obj.Scope);
            s = sprintf('$\\hat f_{\\mathrm{new}}(%s \\mid D)$', strjoin(cellstr(scope), ','));
        end

        function f = toFactor(obj)
            %TOFACTOR Wrap as a plain core.Factor for the reduced graph.
            %   Inputs   none
            %   Outputs  F, a core.Factor of Kind "approximate"
            %   Utility  let the next elimination treat the generated factor
            %            exactly like a measurement, which is what makes the
            %            D_j bookkeeping uniform.
            %
            %   The wrapper keeps this mixture in Meta, which is what makes
            %   the D_j bookkeeping correct: the next elimination sees the
            %   approximate factor and can reach its slices, rather than
            %   silently falling back on the raw factors it came from.
            f = core.Factor(sprintf("fnew(%s)", strjoin(cellstr(obj.Scope), ",")), ...
                obj.Scope, @(a) obj.evaluate(a), ...
                'Kind', "approximate", ...
                'Meta', struct('approximateFactor', obj), ...
                'Counter', obj.Counter);
        end
    end

    methods (Access = private)
        function slices = evaluateSlicesAt(obj, pts)
            %EVALUATESLICESAT Slice values at explicit separator points.
            %   Inputs   PTS, N-by-SeparatorDim points, one per row
            %   Outputs  SLICES, |X|-by-N
            %   Utility  the shape-free core both public evaluators go through.
            %
            %   PTS is Q-by-SeparatorDim. The outer product of the |X| stored
            %   samples with the Q query points is formed explicitly: row i of
            %   the samples repeated Q times against the query tiled |X| times,
            %   so the result reshapes to |X| x Q without transposing the big
            %   temporary.
            nx = obj.NumSamples;
            q  = size(pts, 1);
            if nx == 0 || q == 0
                slices = zeros(nx, q);
                return
            end

            slices = zeros(nx, q);
            okey = matlab.lang.makeValidName(obj.EliminatedVar);

            % Chunked over the outer samples. The expansion is nx-by-q rows,
            % and on the grid world a nested exact evaluation can make q tens
            % of thousands, so an unchunked expansion runs the machine out of
            % memory rather than merely being slow.
            chunk = max(1, floor(obj.MaxExpandedRows / q));
            for a0 = 1:chunk:nx
                b0 = min(a0 + chunk - 1, nx);
                m  = b0 - a0 + 1;

                a = struct();
                a.(okey) = obj.Samples(a0 - 1 + repelem(1:m, q), :);
                tiled = pts(repmat(1:q, 1, m), :);
                col = 0;
                for i = 1:numel(obj.Scope)
                    d = obj.ScopeDims(i);
                    a.(matlab.lang.makeValidName(obj.Scope(i))) = tiled(:, col + (1:d));
                    col = col + d;
                end

                v = core.evalProduct(obj.RemainingFactors, a);
                slices(a0:b0, :) = reshape(v, q, m).';
            end
        end

        function [pts, shp] = queryPoints(obj, assignment)
            %QUERYPOINTS Turn an assignment struct into a point list and a shape.
            %   Inputs   ASSIGNMENT, a struct of separator values
            %   Outputs  PTS the N-by-SeparatorDim points, SHP the shape to
            %            restore so the result matches the query
            %   Utility  accept both the row-oriented and column-oriented query
            %            conventions without either caller changing.
            %
            %   Returns the shape SHP a scalar-separator result must be
            %   restored to. For a scalar separator the legacy broadcast rule
            %   of iteration 1 applies, so a column query, a row query and an
            %   implicitly expanded grid all still work and all still come
            %   back in the shape they were asked in. For a vector separator
            %   every scope variable must already be Q-by-d, because there is
            %   no broadcast rule that can tell a coordinate from a query.
            vals = cell(1, numel(obj.Scope));
            for i = 1:numel(obj.Scope)
                key = matlab.lang.makeValidName(obj.Scope(i));
                if ~isfield(assignment, key)
                    error('core:ApproximateFactor:missingScope', ...
                        'Assignment has no value for %s.', obj.Scope(i));
                end
                vals{i} = assignment.(key);
            end

            if obj.isScalarSeparator()
                shp = obj.broadcastShape(vals);
                filler = zeros(shp);
                pts = zeros(prod(shp), numel(obj.Scope));
                for i = 1:numel(obj.Scope)
                    expanded = vals{i} + filler;
                    pts(:,i) = expanded(:);
                end
                return
            end

            q = 1;
            for i = 1:numel(vals)
                q = max(q, size(vals{i}, 1));
            end
            pts = zeros(q, obj.SeparatorDim);
            col = 0;
            for i = 1:numel(obj.Scope)
                d = obj.ScopeDims(i);
                vi = vals{i};
                if size(vi, 2) ~= d
                    error('core:ApproximateFactor:badScopeWidth', ...
                        'Scope variable %s has dimension %d but %d column(s) were given.', ...
                        obj.Scope(i), d, size(vi, 2));
                end
                if size(vi, 1) == 1, vi = repmat(vi, q, 1); end
                if size(vi, 1) ~= q
                    error('core:ApproximateFactor:incompatibleQuery', ...
                        'Scope variable %s has %d row(s); the query has %d.', ...
                        obj.Scope(i), size(vi, 1), q);
                end
                pts(:, col + (1:d)) = vi;
                col = col + d;
            end
            shp = [q 1];
        end

        function shp = broadcastShape(obj, vals)
            %BROADCASTSHAPE The output shape implied by a legacy scalar query.
            %   Inputs   VALS, the per-variable query values
            %   Outputs  SHP, the shape to reshape the result to
            %   Utility  preserve iteration 1's implicit-expansion behaviour for
            %            scalar separators, so old callers keep working.
            nd  = max(cellfun(@ndims, vals));
            shp = ones(1, nd);
            for i = 1:numel(vals)
                sz = size(vals{i});
                sz(end+1:nd) = 1; %#ok<AGROW>
                bad = sz ~= 1 & shp ~= 1 & sz ~= shp;
                if any(bad)
                    error('core:ApproximateFactor:incompatibleQuery', ...
                        'Scope variable %s has size incompatible with the query.', ...
                        obj.Scope(i));
                end
                shp = max(shp, sz);
            end
        end

        function out = interpolate(obj, values, pts)
            %INTERPOLATE Values at off-support points.
            %   Inputs   VALUES the per-support values, PTS the query points
            %   Outputs  OUT, one value per query point
            %   Utility  answer away from the support: linear on a scalar
            %            separator, nearest neighbour otherwise. Which rule ran
            %            is recorded in Diagnostics rather than left implicit.
            %
            %   VALUES is |S|-by-C, PTS is Q-by-d_s, OUT is Q-by-C. One call
            %   covers every column, which is what keeps interpolating all
            %   |X| slices affordable.
            if size(obj.SeparatorSupport, 1) < 2
                error('core:ApproximateFactor:degenerateSupport', ...
                    'Tabulated factor needs at least two support points.');
            end

            if size(obj.SeparatorSupport, 2) == 1
                % interp1 treats the columns of V as independent datasets, so
                % one call interpolates every slice at every query. Outside
                % the support the factor is zero, not extrapolated.
                out = interp1(obj.SeparatorSupport(:), values, pts(:), 'linear', 0);
                if size(values, 2) == 1, out = out(:); end
            else
                % Nearest neighbour on the support point cloud. Recorded in
                % Diagnostics by the estimator that built this factor.
                %
                % knnsearch, not pdist2. pdist2 with 'Smallest' is exhaustive,
                % so the cost is |S| times the query count; with a few
                % thousand of each, and one such lookup per nested generated
                % factor per elimination, that reaches billions of distance
                % computations and the app simply stops responding. knnsearch
                % builds a KD-tree for these dimensions and the same lookup
                % takes seconds.
                idx = knnsearch(obj.SeparatorSupport, pts);
                out = values(idx(:), :);
            end
        end

        function assertMixtureMode(obj, what)
            %ASSERTMIXTUREMODE Refuse an operation tabulated mode cannot do.
            %   Inputs   WHAT, the operation name for the message
            %   Outputs  none; errors in tabulated mode
            %   Utility  a tabulated factor has no Remaining factors left to
            %            sample from, so say that rather than failing on an
            %            empty array.
            if obj.Mode ~= "mixture"
                error('core:ApproximateFactor:wrongMode', ...
                    '%s requires mixture mode; this factor is %s.', what, obj.Mode);
            end
        end
    end

    methods (Static)
        function obj = tabulated(scope, eliminatedVar, support, sliceMatrix, opts)
            %TABULATED Construct in tabulated mode from an evaluated matrix.
            %   Inputs   SCOPE, ELIMINATEDVAR, SUPPORT, SLICEMATRIX, options
            %   Outputs  OBJ, in Mode "tabulated"
            %   Utility  hold the |X|-by-|S| matrix the nested estimator and the
            %            surface recursion both produce, so the next step reads
            %            one representation whichever computed it.
            %
            %   SUPPORT is the separator support S, given either as a 1-by-|S|
            %   row (scalar separator, the iteration 1 form) or as an
            %   |S|-by-d_s point list. SLICEMATRIX is |X| x |S|. OUTERSAMPLES
            %   records the support of the outer variable that indexes the
            %   slices, for ESS and cardinality diagnostics.
            arguments
                scope (1,:) string
                eliminatedVar (1,1) string
                support (:,:) double
                sliceMatrix (:,:) double
                opts.OuterSamples (:,:) double = zeros(0,1)
                opts.LogScale (1,1) double = 0
                opts.SourceFactorName (1,1) string = ""
                opts.Diagnostics struct = struct()
                opts.Counter = []
                opts.ScopeDims (1,:) double = []
                % Kept even in tabulated mode. Discarding them would save
                % memory and would also destroy the Lemma 1 route: the next
                % elimination reaches THROUGH this factor to find a raw
                % factor that can sample its own frontal variable given the
                % variable this step eliminated. Without them every later
                % proposal degrades to a defensive kernel over the marginal.
                opts.MixtureFactors (1,:) core.Factor = core.Factor.empty(1,0)
                opts.SampleWeights (:,1) double = []
                opts.ExactEvaluation (1,1) logical = false
            end
            dims = opts.ScopeDims;
            if isempty(dims), dims = ones(1, numel(scope)); end

            % A scalar separator may be handed in as a row; that is the shape
            % iteration 1 produced and the shape a linspace naturally has.
            if sum(dims) == 1 && isrow(support)
                support = support(:);
            end
            if size(support, 2) ~= sum(dims)
                error('core:ApproximateFactor:supportWidthMismatch', ...
                    'Support has %d column(s) but the scope has total dimension %d.', ...
                    size(support, 2), sum(dims));
            end
            if size(sliceMatrix, 2) ~= size(support, 1)
                error('core:ApproximateFactor:supportMismatch', ...
                    'Slice matrix has %d columns but |S| = %d.', ...
                    size(sliceMatrix, 2), size(support, 1));
            end

            outer = opts.OuterSamples;
            if isempty(outer)
                outer = (1:size(sliceMatrix, 1)).';
            end

            diag = opts.Diagnostics;
            if opts.ExactEvaluation && ~isempty(opts.MixtureFactors)
                diag.interpolation = "exact";
            elseif sum(dims) == 1
                diag.interpolation = "linear";
            else
                diag.interpolation = "nearest";
            end

            obj = core.ApproximateFactor(scope, eliminatedVar, outer, ...
                core.Factor.empty(1,0), ...
                'LogScale', opts.LogScale, ...
                'SourceFactorName', opts.SourceFactorName, ...
                'Diagnostics', diag, ...
                'Counter', opts.Counter, ...
                'ScopeDims', dims);

            obj.Mode             = "tabulated";
            obj.SeparatorSupport = support;
            obj.SliceMatrix      = sliceMatrix;
            obj.RemainingFactors = opts.MixtureFactors;
            obj.SampleWeights    = opts.SampleWeights;
            obj.ExactEvaluation  = opts.ExactEvaluation && ~isempty(opts.MixtureFactors);
        end
    end
end
