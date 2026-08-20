classdef Factor
    %FACTOR A unary or pairwise factor of the graph.
    %
    %   Properties
    %     Name, Scope  identity and the variables it is over
    %     Kind         factor family, e.g. "range", "gaussianRelative"
    %     EvalFcn      @(assignment) -> nonnegative array
    %     Samplers     per-target struct of .draw and .logZ handles
    %     Meta         measurement, noise and provenance
    %     Counter      shared core.EvalCounter, or []
    %
    %   Methods
    %     evaluate, logEvaluate   the value, and its log
    %     canSample, sample       draw one scope variable given the others
    %     logNormalizer           log Z in the free argument
    %     involves, latex
    %
    %   Static constructors
    %     gaussianUnary, gaussianRelative, mixtureRelative
    %     gaussianVectorUnary, gaussianVectorRelative
    %     rangeFactor, ambiguousRangeFactor, fromHandle
    %
    %   Utility
    %     Carry one factor's value, its sampler and its mass, so the estimators
    %     can evaluate it, draw from it, and account for its normalizer
    %     separately.
    %
    %   Factors are evaluated on structs whose fields are variable names and
    %   whose values are numeric arrays. For SCALAR variables, evaluation uses
    %   MATLAB implicit expansion, so shaping x1 as a column and x2 as a row
    %   yields the whole |X_1| x |S| slice matrix in one call. Above one
    %   dimension that reading breaks down -- the second dimension already means
    %   "coordinate" -- so vector callers enumerate pairs through core.evalGrid
    %   or methods.smoothed.pairwiseFactorMatrix instead.
    %
    %   Factors are stored UNNORMALIZED. Normalizers are exposed separately
    %   through logNormalizer, because the Slices estimator needs Z_{f'} for
    %   the sampled factor (Eq. 6-7 of the Smoothed Slices spec) while the
    %   conditional estimator needs eta_j to cancel (Eq. S15).

    properties
        Name    (1,1) string
        Scope   (1,:) string
        Kind    (1,1) string = "generic"
        EvalFcn                         % @(assignment) -> nonnegative array
        Samplers struct = struct()      % per-target: .draw, .logZ
        Meta    struct = struct()       % measurement, noise, provenance
        Counter                         % core.EvalCounter handle or []
    end

    methods
        function obj = Factor(name, scope, evalFcn, opts)
            %FACTOR Construct from a name, a scope and an evaluation handle.
            %   Inputs   NAME, SCOPE, EVALFCN, and Kind/Samplers/Meta/Counter
            %            as name-value pairs
            %   Outputs  OBJ
            %   Utility  the general path; the static constructors below cover
            %            the families this project actually uses.
            arguments
                name    (1,1) string
                scope   (1,:) string
                evalFcn (1,1) function_handle
                opts.Kind (1,1) string = "generic"
                opts.Samplers struct = struct()
                opts.Meta struct = struct()
                opts.Counter = []
            end
            obj.Name     = name;
            obj.Scope    = scope;
            obj.EvalFcn  = evalFcn;
            obj.Kind     = opts.Kind;
            obj.Samplers = opts.Samplers;
            obj.Meta     = opts.Meta;
            obj.Counter  = opts.Counter;
        end

        function v = evaluate(obj, assignment)
            %EVALUATE Nonnegative factor value at the given assignment.
            %   Inputs   ASSIGNMENT, struct of variable values
            %   Outputs  V, nonnegative, shaped by the assignment
            %   Utility  evaluate the factor and tally the work on Counter, so
            %            cost claims are measured rather than asserted.
            v = obj.EvalFcn(assignment);
            if ~isempty(obj.Counter)
                obj.Counter.add(numel(v));
            end
        end

        function v = logEvaluate(obj, assignment)
            %LOGEVALUATE Log of the factor value, -Inf where it vanishes.
            %   Inputs   ASSIGNMENT, struct of variable values
            %   Outputs  V, the log value
            %   Utility  keep products of many factors in range.
            v = log(obj.evaluate(assignment));
        end

        function tf = canSample(obj, targetVar)
            %CANSAMPLE True when this factor can draw TARGETVAR.
            %   Inputs   TARGETVAR
            %   Outputs  TF, logical
            %   Utility  test the Lemma 1 route without drawing anything.
            tf = isfield(obj.Samplers, matlab.lang.makeValidName(targetVar));
        end

        function s = sample(obj, targetVar, given, n)
            %SAMPLE Draw N samples of TARGETVAR from this factor.
            %   Inputs   TARGETVAR the variable to draw, GIVEN a struct holding
            %            the other scope variables (may be empty for a unary
            %            factor), N the number of draws
            %   Outputs  S, an N-element column, or SIZE(GIVEN)-by-N when the
            %            given values are vectors -- one independent slice per
            %            given value, and m-by-N-by-d for a d-dimensional target
            %   Utility  provide the structural proposal Lemma 1 relies on.
            arguments
                obj (1,1) core.Factor
                targetVar (1,1) string
                given struct
                n (1,1) double {mustBeInteger, mustBePositive}
            end
            key = matlab.lang.makeValidName(targetVar);
            if ~isfield(obj.Samplers, key)
                error('core:Factor:notSampleable', ...
                    'Factor %s cannot sample %s.', obj.Name, targetVar);
            end
            s = obj.Samplers.(key).draw(given, n);
        end

        function lz = logNormalizer(obj, targetVar, given)
            %LOGNORMALIZER log Z(given) = log int f(target, given) d target.
            %   Inputs   TARGETVAR the free argument, GIVEN the others
            %   Outputs  LZ, the log mass, one value per given row
            %   Utility  carry the mass of a factor that left the product.
            %
            %   Required by Eq. (6)-(7): the sampled factor leaves the product
            %   but its mass Z_{f'} must be accounted for explicitly, which is
            %   why factors are stored unnormalized and the normalizer is a
            %   separate query rather than folded into the value.
            arguments
                obj (1,1) core.Factor
                targetVar (1,1) string
                given struct = struct()
            end
            key = matlab.lang.makeValidName(targetVar);
            if ~isfield(obj.Samplers, key)
                error('core:Factor:noNormalizer', ...
                    'Factor %s has no normalizer for %s.', obj.Name, targetVar);
            end
            lz = obj.Samplers.(key).logZ(given);
        end

        function tf = involves(obj, varName)
            %INVOLVES True when VARNAME is in this factor's scope.
            %   Inputs   VARNAME
            %   Outputs  TF, logical
            %   Utility  the adjacency test every structural graph query uses.
            tf = any(obj.Scope == varName);
        end

        function s = latex(obj)
            %LATEX Paper-style rendering, e.g. "$f(x_1,l_1)$".
            %   Inputs   none
            %   Outputs  S, a char row of LaTeX math
            %   Utility  label a factor in a figure the way the paper writes it.
            parts = arrayfun(@(v) regexprep(v, '^([a-zA-Z]+)(\d+)$', '$1_{$2}'), ...
                obj.Scope);
            s = sprintf('$f(%s)$', strjoin(cellstr(parts), ','));
        end
    end

    % ---------------------------------------------------------------------
    % Constructors for the factor types used by the two-pose range benchmark.
    % ---------------------------------------------------------------------
    methods (Static)
        function f = gaussianUnary(varName, mu, sigma, opts)
            %GAUSSIANUNARY Normalized Gaussian prior f(v) = N(v; mu, sigma^2).
            %   Inputs   VARNAME, MU, SIGMA, and Name/Counter as pairs
            %   Outputs  F, a core.Factor of Kind "gaussianUnary"
            %   Utility  the unary factor that makes a variable sampleable on
            %            its own, which is Lemma 1's base case.
            arguments
                varName (1,1) string
                mu (1,1) double
                sigma (1,1) double {mustBePositive}
                opts.Name (1,1) string = ""
                opts.Counter = []
            end
            name = opts.Name;
            if strlength(name) == 0, name = sprintf("f(%s)", varName); end

            key = matlab.lang.makeValidName(varName);
            evalFcn = @(a) exp(-0.5 * ((a.(key) - mu) ./ sigma).^2) ./ (sigma * sqrt(2*pi));

            samplers = struct();
            samplers.(key) = struct( ...
                'draw', @(~, n) mu + sigma * randn(n, 1), ...
                'logZ', @(~) 0);   % already normalized in v

            f = core.Factor(name, varName, evalFcn, ...
                'Kind', "gaussianUnary", 'Samplers', samplers, ...
                'Meta', struct('mu', mu, 'sigma', sigma), 'Counter', opts.Counter);
        end

        function f = gaussianRelative(varA, varB, delta, sigma, opts)
            %GAUSSIANRELATIVE f(a,b) = N(b - a; delta, sigma^2).
            %   Inputs   VARA, VARB, DELTA, SIGMA, and Name/Counter as pairs
            %   Outputs  F, a core.Factor of Kind "gaussianRelative"
            %   Utility  odometry, and 1-D range; sampleable in either argument.
            %   Models odometry (pose-to-pose) and 1-D range (pose-to-landmark)
            %   measurements. The factor is normalized in EITHER argument given
            %   the other, so Z = 1 both ways; that is exactly the condition
            %   under which the Slices spec Eq. (S14) and the Smoothed Slices
            %   spec Eq. (23) coincide, since the latter's Z_l(x_1) is then
            %   constant.
            arguments
                varA (1,1) string
                varB (1,1) string
                delta (1,1) double
                sigma (1,1) double {mustBePositive}
                opts.Name (1,1) string = ""
                opts.Counter = []
            end
            name = opts.Name;
            if strlength(name) == 0, name = sprintf("f(%s,%s)", varA, varB); end

            ka = matlab.lang.makeValidName(varA);
            kb = matlab.lang.makeValidName(varB);
            evalFcn = @(s) exp(-0.5 * ((s.(kb) - s.(ka) - delta) ./ sigma).^2) ./ (sigma * sqrt(2*pi));

            samplers = struct();
            % Sample b given a:  b = a + delta + sigma*eps
            samplers.(kb) = struct( ...
                'draw', @(g, n) g.(ka)(:) + delta + sigma * randn(numel(g.(ka)), n), ...
                'logZ', @(g) zeros(size(g.(ka))));
            % Sample a given b:  a = b - delta + sigma*eps
            samplers.(ka) = struct( ...
                'draw', @(g, n) g.(kb)(:) - delta + sigma * randn(numel(g.(kb)), n), ...
                'logZ', @(g) zeros(size(g.(kb))));

            f = core.Factor(name, [varA varB], evalFcn, ...
                'Kind', "gaussianRelative", 'Samplers', samplers, ...
                'Meta', struct('delta', delta, 'sigma', sigma), 'Counter', opts.Counter);
        end

        function f = mixtureRelative(varA, varB, deltas, sigmas, weights, opts)
            %MIXTURERELATIVE Multimodal f(a,b) = sum_k w_k N(b-a; d_k, s_k^2).
            %   Inputs   VARA, VARB, DELTAS, SIGMAS, WEIGHTS, and Name/Counter
            %   Outputs  F, a core.Factor of Kind "mixtureRelative"
            %   Utility  a genuinely multimodal relative factor, which is the
            %            shape RMSE cannot see and the comparison exists for.
            %   Used for the multimodal-support test (T4) and, later, for
            %   ambiguous data association. Normalized in b given a, so its
            %   normalizer is again 1 and mass bookkeeping stays simple.
            arguments
                varA (1,1) string
                varB (1,1) string
                deltas (1,:) double
                sigmas (1,:) double {mustBePositive}
                weights (1,:) double {mustBeNonnegative}
                opts.Name (1,1) string = ""
                opts.Counter = []
            end
            if ~isequal(numel(deltas), numel(sigmas), numel(weights))
                error('core:Factor:mixtureSizeMismatch', ...
                    'deltas, sigmas and weights must have equal length.');
            end
            w = weights(:).' / sum(weights);

            name = opts.Name;
            if strlength(name) == 0, name = sprintf("f(%s,%s)", varA, varB); end

            ka = matlab.lang.makeValidName(varA);
            kb = matlab.lang.makeValidName(varB);

            evalFcn = @(s) localMixtureEval(s.(ka), s.(kb), deltas, sigmas, w);

            samplers = struct();
            samplers.(kb) = struct( ...
                'draw', @(g, n) localMixtureDraw(g.(ka)(:),  1, deltas, sigmas, w, n), ...
                'logZ', @(g) zeros(size(g.(ka))));
            samplers.(ka) = struct( ...
                'draw', @(g, n) localMixtureDraw(g.(kb)(:), -1, deltas, sigmas, w, n), ...
                'logZ', @(g) zeros(size(g.(kb))));

            f = core.Factor(name, [varA varB], evalFcn, ...
                'Kind', "mixtureRelative", 'Samplers', samplers, ...
                'Meta', struct('deltas', deltas, 'sigmas', sigmas, 'weights', w), ...
                'Counter', opts.Counter);
        end

        function f = gaussianVectorUnary(varName, mu, sigma, opts)
            %GAUSSIANVECTORUNARY Normalized Gaussian prior on a d-vector.
            %   Inputs   VARNAME, MU, SIGMA (scalar, diagonal or full), and
            %            Name/Counter as pairs
            %   Outputs  F, a core.Factor of Kind "gaussianVectorUnary"
            %   Utility  the planar prior, the base case of the vector cases.
            %   MU is 1-by-d. SIGMA is a scalar (isotropic), a 1-by-d row
            %   (diagonal), or a d-by-d covariance.
            arguments
                varName (1,1) string
                mu (1,:) double
                sigma double
                opts.Name (1,1) string = ""
                opts.Counter = []
            end
            d = numel(mu);
            [L, logDet] = core.Factor.cholOf(sigma, d);

            name = opts.Name;
            if strlength(name) == 0, name = sprintf("f(%s)", varName); end
            key = matlab.lang.makeValidName(varName);

            logNorm = -0.5 * (d * log(2*pi) + logDet);
            evalFcn = @(a) exp(logNorm - 0.5 * sum(((a.(key) - mu) / L).^2, 2));

            samplers = struct();
            samplers.(key) = struct( ...
                'draw', @(~, n) mu + randn(n, d) * L, ...
                'logZ', @(~) 0);   % already normalized in v

            f = core.Factor(name, varName, evalFcn, ...
                'Kind', "gaussianVectorUnary", 'Samplers', samplers, ...
                'Meta', struct('mu', mu, 'sigma', sigma, 'dim', d), ...
                'Counter', opts.Counter);
        end

        function f = gaussianVectorRelative(varA, varB, delta, sigma, opts)
            %GAUSSIANVECTORRELATIVE f(a,b) = N(b - a; delta, Sigma) on d-vectors.
            %   Inputs   VARA, VARB, DELTA, SIGMA, and Name/Counter as pairs
            %   Outputs  F, a core.Factor of Kind "gaussianVectorRelative"
            %   Utility  planar odometry; sampleable in either argument.
            %   Planar odometry. As in the scalar case the factor is
            %   normalized in either argument given the other, so Z = 1 both
            %   ways and the mass bookkeeping of Eq. (S14)/(23) stays simple.
            arguments
                varA (1,1) string
                varB (1,1) string
                delta (1,:) double
                sigma double
                opts.Name (1,1) string = ""
                opts.Counter = []
            end
            d = numel(delta);
            [L, logDet] = core.Factor.cholOf(sigma, d);

            name = opts.Name;
            if strlength(name) == 0, name = sprintf("f(%s,%s)", varA, varB); end
            ka = matlab.lang.makeValidName(varA);
            kb = matlab.lang.makeValidName(varB);

            logNorm = -0.5 * (d * log(2*pi) + logDet);
            evalFcn = @(s) exp(logNorm - 0.5 * sum(((s.(kb) - s.(ka) - delta) / L).^2, 2));

            samplers = struct();
            samplers.(kb) = struct( ...
                'draw', @(g, n) core.Factor.vectorShift(g.(ka),  delta, L, n), ...
                'logZ', @(g) zeros(size(g.(ka), 1), 1));
            samplers.(ka) = struct( ...
                'draw', @(g, n) core.Factor.vectorShift(g.(kb), -delta, L, n), ...
                'logZ', @(g) zeros(size(g.(kb), 1), 1));

            f = core.Factor(name, [varA varB], evalFcn, ...
                'Kind', "gaussianVectorRelative", 'Samplers', samplers, ...
                'Meta', struct('delta', delta, 'sigma', sigma, 'dim', d), ...
                'Counter', opts.Counter);
        end

        function f = rangeFactor(poseVar, lmVar, r, sigma, opts)
            %RANGEFACTOR f(x,l) = N(||l - x||; r, sigma^2), the donut.
            %   Inputs   POSEVAR, LMVAR, R, SIGMA, and Name/Counter as pairs
            %   Outputs  F, a core.Factor of Kind "range"
            %   Utility  the range measurement, whose posterior is an annulus.
            %   The classical non-Gaussian SLAM factor: a range measurement
            %   with no bearing leaves the landmark on an annulus, which is
            %   exactly the posterior shape RMSE cannot see and the whole app
            %   exists to compare.
            %
            %   The factor is NOT normalized in either argument. Its mass in
            %   the free argument is
            %
            %       Z = 2*pi*( r*Phi(r/sigma) + sigma*phi(r/sigma) )
            %
            %   the polar Jacobian included, and that mass is carried through
            %   logNormalizer rather than folded into the value, because the
            %   Slices estimator needs Z_{f'} explicitly.
            %
            %   Sampling the free argument uses ANGLE uniform and RADIUS drawn
            %   from p(rho) proportional to rho*N(rho; r, sigma^2) on rho > 0.
            %   The rho weight is the polar Jacobian: drawing rho from the
            %   measurement density directly would over-weight the centre of
            %   the annulus, which is a bias that hides as a plausible picture.
            arguments
                poseVar (1,1) string
                lmVar (1,1) string
                r (1,1) double {mustBeNonnegative}
                sigma (1,1) double {mustBePositive}
                opts.Name (1,1) string = ""
                opts.Counter = []
            end
            name = opts.Name;
            if strlength(name) == 0, name = sprintf("f(%s,%s)", poseVar, lmVar); end
            kx = matlab.lang.makeValidName(poseVar);
            kl = matlab.lang.makeValidName(lmVar);

            evalFcn = @(s) exp(-0.5 * ((sqrt(sum((s.(kl) - s.(kx)).^2, 2)) - r) ./ sigma).^2) ...
                           ./ (sigma * sqrt(2*pi));

            z = r/sigma;
            logZ = log(2*pi) + log(r * normcdf(z) + sigma * normpdf(z));

            samplers = struct();
            samplers.(kl) = struct( ...
                'draw', @(g, n) core.Factor.annulusDraw(g.(kx), r, sigma, n), ...
                'logZ', @(g) repmat(logZ, size(g.(kx), 1), 1));
            samplers.(kx) = struct( ...
                'draw', @(g, n) core.Factor.annulusDraw(g.(kl), r, sigma, n), ...
                'logZ', @(g) repmat(logZ, size(g.(kl), 1), 1));

            f = core.Factor(name, [poseVar lmVar], evalFcn, ...
                'Kind', "range", 'Samplers', samplers, ...
                'Meta', struct('range', r, 'sigma', sigma, 'logZ', logZ), ...
                'Counter', opts.Counter);
        end

        function f = ambiguousRangeFactor(poseVar, lmVars, r, sigma, weights, opts)
            %AMBIGUOUSRANGEFACTOR One range reading, unknown which landmark.
            %   Inputs   POSEVAR, LMVARS, R, SIGMA, WEIGHTS, Name/Counter
            %   Outputs  F, a core.Factor of Kind "ambiguousRange"
            %   Utility  unresolved data association, deliberately NOT
            %            sampleable, so no elimination order can rely on it.
            %   f(x, l_1, ..., l_K) = sum_k w_k N(||l_k - x||; r, sigma^2).
            %
            %   This is the "ambiguous data association" case of spec section
            %   6, and it is a genuinely multimodal factor over a scope of
            %   more than two variables. It is deliberately NOT sampleable:
            %   the elimination order must reach these landmarks through a
            %   factor that is, which is the Lemma 1 precondition doing its
            %   job rather than being worked around.
            arguments
                poseVar (1,1) string
                lmVars (1,:) string
                r (1,1) double {mustBeNonnegative}
                sigma (1,1) double {mustBePositive}
                weights (1,:) double {mustBeNonnegative} = []
                opts.Name (1,1) string = ""
                opts.Counter = []
            end
            k = numel(lmVars);
            if isempty(weights), weights = ones(1, k); end
            if numel(weights) ~= k
                error('core:Factor:ambiguousWeightMismatch', ...
                    '%d landmark(s) but %d weight(s).', k, numel(weights));
            end
            w = weights / sum(weights);

            name = opts.Name;
            if strlength(name) == 0
                name = sprintf("f(%s;%s)", poseVar, strjoin(cellstr(lmVars), "|"));
            end
            kx  = matlab.lang.makeValidName(poseVar);
            kls = arrayfun(@matlab.lang.makeValidName, lmVars);

            evalFcn = @(s) localAmbiguousEval(s, kx, kls, r, sigma, w);

            f = core.Factor(name, [poseVar lmVars], evalFcn, ...
                'Kind', "ambiguousRange", ...
                'Meta', struct('range', r, 'sigma', sigma, 'weights', w, ...
                               'candidates', lmVars), ...
                'Counter', opts.Counter);
        end

        function f = fromHandle(name, scope, evalFcn, opts)
            %FROMHANDLE Escape hatch for arbitrary user-defined factors.
            %   Inputs   NAME, SCOPE, EVALFCN, and Kind/Samplers/Meta/Counter
            %   Outputs  F, a core.Factor
            %   Utility  build a factor with no family behind it, for a test.
            arguments
                name (1,1) string
                scope (1,:) string
                evalFcn (1,1) function_handle
                opts.Samplers struct = struct()
                opts.Meta struct = struct()
                opts.Counter = []
            end
            f = core.Factor(name, scope, evalFcn, 'Kind', "custom", ...
                'Samplers', opts.Samplers, 'Meta', opts.Meta, 'Counter', opts.Counter);
        end
    end

    % ---------------------------------------------------------------------
    % Shared numerics for the vector-valued factors. Public because the
    % sampler closures above outlive this class body and are invoked from the
    % elimination engine.
    % ---------------------------------------------------------------------
    methods (Static)
        function [L, logDet] = cholOf(sigma, d)
            %CHOLOF Cholesky factor and log determinant of a covariance.
            %   Inputs   SIGMA a scalar variance, a diagonal, or a full matrix;
            %            D the dimension
            %   Outputs  L the upper factor, LOGDET the log determinant
            %   Utility  accept the three ways a covariance gets written in this
            %            project and reduce them to one form.
            %
            %   SIGMA is read as a standard deviation when scalar or a row,
            %   and as a covariance when square. Whitening is then the right
            %   division v/L, and drawing is randn*L.
            if isscalar(sigma)
                L = sigma * eye(d);
                logDet = 2 * d * log(sigma);
            elseif isvector(sigma) && numel(sigma) == d
                L = diag(sigma(:).');
                logDet = 2 * sum(log(sigma(:)));
            elseif isequal(size(sigma), [d d])
                [L, p] = chol(sigma);
                if p > 0
                    error('core:Factor:notPositiveDefinite', ...
                        'The %dx%d covariance is not positive definite.', d, d);
                end
                logDet = 2 * sum(log(diag(L)));
            else
                error('core:Factor:badCovariance', ...
                    ['Sigma must be a scalar standard deviation, a 1-by-%d row ' ...
                     'of standard deviations, or a %dx%d covariance.'], d, d, d);
            end
        end

        function s = vectorShift(given, delta, L, n)
            %VECTORSHIFT N Gaussian draws around each given point, shifted.
            %   Inputs   GIVEN the m-by-d centres, DELTA the offset, L the
            %            Cholesky factor, N draws per centre
            %   Outputs  S, m-by-N-by-d
            %   Utility  sample a vector relative factor in either direction.
            m = size(given, 1);
            d = numel(delta);
            base = repelem(given, n, 1) + delta;
            tmp  = base + randn(m*n, d) * L;
            % Row (i-1)*n + j holds draw j of given i, so the reshape is
            % (n, m, d) and the permute puts the given index back in front.
            s = permute(reshape(tmp, n, m, d), [2 1 3]);
        end

        function s = annulusDraw(centre, r, sigma, n)
            %ANNULUSDRAW N draws on the range annulus around each centre.
            %   Inputs   CENTRE the m-by-2 centres, R the range, SIGMA its
            %            noise, N draws per centre
            %   Outputs  S, m-by-N-by-2
            %   Utility  sample the free argument of a range factor correctly.
            %   Returns m-by-n-by-2. The radius is drawn from
            %   p(rho) proportional to rho*N(rho; r, sigma^2) on rho > 0, the
            %   polar Jacobian included, so that the resulting planar density
            %   is proportional to N(||l - x||; r, sigma^2) as the factor
            %   claims. The angle is uniform.
            if size(centre, 2) ~= 2
                error('core:Factor:annulusNotPlanar', ...
                    'Range sampling needs a 2-D centre; got %d column(s).', ...
                    size(centre, 2));
            end
            m = size(centre, 1);

            lo  = max(0, r - 6*sigma);
            hi  = r + 6*sigma;
            rho = linspace(lo, hi, 2001).';
            pdf = rho .* normpdf(rho, r, sigma);
            cdf = cumtrapz(rho, pdf);
            if cdf(end) <= 0
                error('core:Factor:degenerateAnnulus', ...
                    'Range factor has no mass at r = %g, sigma = %g.', r, sigma);
            end
            cdf = cdf / cdf(end);

            % Strictly increasing knots so interp1 accepts the inversion.
            [c, keep] = unique(cdf, 'stable');
            draws = interp1(c, rho(keep), rand(m*n, 1), 'linear', 'extrap');
            theta = 2*pi * rand(m*n, 1);

            offset = [draws .* cos(theta), draws .* sin(theta)];
            tmp    = repelem(centre, n, 1) + offset;
            s      = permute(reshape(tmp, n, m, 2), [2 1 3]);
        end
    end
end

% -------------------------------------------------------------------------
function v = localAmbiguousEval(s, kx, kls, r, sigma, w)
%LOCALAMBIGUOUSEVAL A range reading whose landmark is not known.
%   Inputs   S the query struct, KX the pose key, KLS the candidate landmark
%            keys, R the measured range, SIGMA its noise, W the candidate weights
%   Outputs  V, one density value per row of S
%   Utility  sum the per-candidate range likelihoods, which is what makes the
%            factor a mixture rather than a choice.
x = s.(kx);
v = zeros(size(x, 1), 1);
for k = 1:numel(kls)
    rho = sqrt(sum((s.(kls(k)) - x).^2, 2));
    v = v + w(k) * exp(-0.5 * ((rho - r) ./ sigma).^2) ./ (sigma * sqrt(2*pi));
end
end

% -------------------------------------------------------------------------
function v = localMixtureEval(a, b, deltas, sigmas, w)
%LOCALMIXTUREEVAL A relative measurement with several possible offsets.
%   Inputs   A and B the two variables, DELTAS the offsets, SIGMAS their
%            noises, W the component weights
%   Outputs  V, one density value per element of B - A
%   Utility  evaluate the mixture on the difference, so the factor stays a
%            function of the relative quantity alone.
d = b - a;
v = zeros(size(d));
for k = 1:numel(deltas)
    v = v + w(k) * exp(-0.5 * ((d - deltas(k)) ./ sigmas(k)).^2) ./ (sigmas(k) * sqrt(2*pi));
end
end

function s = localMixtureDraw(given, sgn, deltas, sigmas, w, n)
%LOCALMIXTUREDRAW Sample the other end of a mixture relative factor.
%   Inputs   GIVEN the conditioned end, SGN +1 or -1 for which end is drawn,
%            DELTAS, SIGMAS, W the mixture, N draws per given value
%   Outputs  S, numel(GIVEN)-by-N
%   Utility  draw a component first and then within it, giving one
%            independent row of N draws per given value.
m    = numel(given);
comp = localCategorical(w, m, n);
d    = reshape(deltas(comp), m, n);
sg   = reshape(sigmas(comp), m, n);
s    = given + sgn * d + sg .* randn(m, n);
end

function idx = localCategorical(w, m, n)
%LOCALCATEGORICAL M-by-N component indices from the weights W.
%   Inputs   W the weights, M rows, N draws per row
%   Outputs  IDX, M-by-N indices into W
%   Utility  the last edge is pinned to 1 and NaNs fall to the last
%            component, so a rounding error cannot produce a missing draw.
edges = [0 cumsum(w(:).')];
edges(end) = 1;
u = rand(m, n);
idx = discretize(u, edges);
idx(isnan(idx)) = numel(w);
end
