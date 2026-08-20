function ref = referenceLemma1Chain(caseData, opts)
%REFERENCELEMMA1CHAIN Ground truth for the Lemma-1 chain, at any depth H.
%
%   Inputs
%     CASEDATA  a case from datasets.makeLemma1ChainCase
%     (options are listed below, under Name-value options)
%
%   Outputs
%     REF       struct carrying every surface R_r, the new factor f_new, the
%               normalized separator marginal and reference samples for MMD
%
%   Utility
%     Evaluate, by dense trapezoidal quadrature along the chain,
%
%       R_H(x_H,s) = a(x_H,s)
%       R_r(x_r,s) = int g_r(x_r,x_r+1) R_r+1(x_r+1,s) dx_r+1      (Eq. 39)
%       f_new(s)   = int f(x_0) b_0(x_0,s) R_0(x_0,s) dx_0         (Eq. 41)
%
%     so that both the SURFACE the recursion returns and the POSTERIOR it is
%     used to build have something exact to be measured against at every depth.
%
%   THE SAME SWEEP GIVES BOTH REFERENCES, and that is the point of doing it
%   this way rather than integrating the whole product at once. The recursion
%   under study returns R_0 and the study also wants the posterior error, so a
%   reference that produced only f_new would leave the surface unchecked and
%   one that produced only R_0 would leave the estimator's downstream use
%   unchecked. Here R_0 is an intermediate of the f_new computation, so the two
%   references cannot drift apart.
%
%   WHY IT IS O(H G^2 |S|) AND NOT O(G^(H+1)). The chain is a chain: level r
%   couples only to level r+1, so the (H+1)-dimensional integral factors into H
%   sequential matrix products. At H = 5 the naive product would be a
%   quadrillion grid points and this is five matrix multiplications. That is a
%   property of the CASE, not of the estimators being measured, and it is
%   exactly why a chain is the right synthetic case: the reference stays exact
%   at a depth where the nested estimator under test no longer can run.
%
%   THE QUADRATURE TOUCHES NO ESTIMATOR. It never calls core.ApproximateFactor
%   or the surface recursion, and it evaluates against counter-detached copies
%   of the factors, so neither a bug in the estimators nor the reference's own
%   work can reach the number the study reports as cost.
%
%   Name-value options:
%     NumLevel   quadrature nodes per path variable          default 801
%     NumS       evaluation points for the separator         default 401
%     NumSamples reference samples from the separator marginal  default 4000
%     TailTolerance  maximum acceptable relative edge density    default 1e-5
%
%   See also datasets.makeLemma1ChainCase, research.recursionDepthStudy.

arguments
    caseData (1,1) struct
    opts.NumLevel (1,1) double {mustBeInteger, mustBePositive} = 801
    opts.NumS (1,1) double {mustBeInteger, mustBePositive} = 401
    opts.NumSamples (1,1) double {mustBeInteger, mustBePositive} = 4000
    opts.TailTolerance (1,1) double = 1e-5
end

g       = caseData.graph;
H       = caseData.depth;
pathVar = caseData.pathVariables;
sepVar  = caseData.targetVariable;

sGrid = g.variable(sepVar).grid(opts.NumS);
sRow  = sGrid(:).';

xGrid = cell(1, H + 1);
wGrid = cell(1, H + 1);
for r = 0:H
    xGrid{r + 1} = g.variable(pathVar(r + 1)).grid(opts.NumLevel);
    wGrid{r + 1} = localTrapzWeights(xGrid{r + 1});
end

% --- R_H = a(x_H, s), then Eq. (39) backwards ----------------------------
fuse  = localUncounted(g, "a(" + pathVar(end) + "," + sepVar + ")");
prior = localUncounted(g, "f(" + pathVar(1) + ")");
R = cell(1, H + 1);
R{H + 1} = fuse.evaluate(struct( ...
    matlab.lang.makeValidName(pathVar(end)), xGrid{H + 1}(:), ...
    matlab.lang.makeValidName(sepVar), sRow));           % |X_H| x |S|

% Each g_r matrix is kept so the forward pass below can reuse it. That pass
% is the domain check, and rebuilding H dense kernels for it would double the
% cost of the reference to measure the reference.
Gmat = cell(1, H);
for r = (H - 1):-1:0
    gr = localUncounted(g, sprintf("g%d(%s,%s)", r, pathVar(r + 1), pathVar(r + 2)));
    % |X_r| x |X_r+1| times |X_r+1| x |S|; the weights turn the sum over the
    % column grid into the integral of Eq. (39).
    Gmat{r + 1} = gr.evaluate(struct( ...
        matlab.lang.makeValidName(pathVar(r + 1)), xGrid{r + 1}(:), ...
        matlab.lang.makeValidName(pathVar(r + 2)), xGrid{r + 2}(:).'));
    R{r + 1} = Gmat{r + 1} * (wGrid{r + 2} .* R{r + 2});
end

% --- f_new(s) = int f(x_0) b_0(x_0,s) R_0(x_0,s) dx_0 --------------------
front = localUncounted(g, "b0(" + pathVar(1) + "," + sepVar + ")");

p0 = prior.evaluate(struct(matlab.lang.makeValidName(pathVar(1)), xGrid{1}(:)));
B0 = front.evaluate(struct( ...
    matlab.lang.makeValidName(pathVar(1)), xGrid{1}(:), ...
    matlab.lang.makeValidName(sepVar), sRow));           % |X_0| x |S|

fnew = (wGrid{1} .* p0).' * (B0 .* R{1});                % 1 x |S|

mass = trapz(sGrid, fnew);
if ~(mass > 0)
    error('datasets:referenceLemma1Chain:zeroMass', ...
        'Quadrature returned zero mass at H = %d; check the factor domains.', H);
end
pdfS = fnew / mass;

samples = core.ConditionalFactor.inverseCdfSample(sGrid(:), pdfS(:), opts.NumSamples);

% --- Domain adequacy ------------------------------------------------------
% Checked at every level, not only at the separator, because the chain's
% intermediate domains are what the surface is integrated over: a truncated
% level-3 domain corrupts R_0 while leaving the separator marginal looking
% perfectly well contained.
edgeDensity = max(pdfS(1), pdfS(end)) / max(pdfS);
if edgeDensity > opts.TailTolerance
    warning('datasets:referenceLemma1Chain:truncated', ...
        ['Reference density at the %s domain edge is %.2e of its peak ' ...
         '(tolerance %.1e) at H = %d. Widen the domain or the reference is ' ...
         'truncated.'], sepVar, edgeDensity, opts.TailTolerance, H);
end

% THE PER-LEVEL CHECK IS ON THE FORWARD MARGINAL, NOT ON R_r, and the
% distinction matters enough to state. R_r is a CONDITIONAL surface: for a
% chain of relative factors it is very nearly phi(s - x_r), so its maximum over
% s is flat in x_r and stays flat right up to the domain edge. Reading a
% truncation off R_r would therefore report one on every well-sized case. What
% can actually be truncated is the integral, and that is governed by where the
% level's own mass sits -- so the forward marginal is swept and each level is
% asked whether it still integrates to the one a normalized chain owes.
levelMass = zeros(1, H + 1);
pf = prior.evaluate(struct(matlab.lang.makeValidName(pathVar(1)), xGrid{1}(:)));
levelMass(1) = trapz(xGrid{1}(:), pf);
for r = 0:(H - 1)
    pf = (Gmat{r + 1}).' * (wGrid{r + 1} .* pf);
    levelMass(r + 2) = trapz(xGrid{r + 2}(:), pf);
end
lost = 1 - levelMass;
if any(lost > 1e-4)
    [worst, at] = max(lost);
    warning('datasets:referenceLemma1Chain:levelTruncated', ...
        ['Level %s holds only %.6f of its forward marginal (%.2e lost past ' ...
         'the domain edge) at H = %d. The intermediate integrals are ' ...
         'truncated even where the separator marginal is not.'], ...
        pathVar(at), levelMass(at), worst, H);
end

ref = struct();
ref.depth       = H;
ref.s           = sGrid;
ref.fnew        = fnew;         % unnormalized, directly comparable to estimators
ref.pdf         = pdfS;         % normalized separator marginal
ref.mass        = mass;
ref.samples     = samples;
ref.x0          = xGrid{1};
ref.levels      = xGrid;        % every path grid, innermost last
ref.R0          = R{1};         % |X_0| x |S|, the object the recursion returns
ref.R           = R;            % every R_r, for checking the tower level by level
ref.mean        = trapz(sGrid, sGrid .* pdfS);
ref.std         = sqrt(trapz(sGrid, (sGrid - trapz(sGrid, sGrid .* pdfS)).^2 .* pdfS));
ref.grid        = struct('numLevel', opts.NumLevel, 'numS', opts.NumS);
ref.method      = "dense trapezoidal quadrature along the chain";
ref.edgeDensity = edgeDensity;
ref.levelMass   = levelMass;   % forward mass held by each level's domain

ref.R0Interp = @(xq, kq) interp1(xGrid{1}(:), R{1}(:, kq), xq, 'linear', 0);
end

% -------------------------------------------------------------------------
function f = localUncounted(graph, name)
%LOCALUNCOUNTED Fetch a factor with its evaluation counter detached.
%   Inputs   GRAPH, and NAME of the factor
%   Outputs  F, the factor with Counter emptied
%   Utility  keep the reference's own evaluations out of the shared cost tally,
%           so the reference cannot inflate the number it exists to check.
idx = find([graph.Factors.Name] == name, 1);
if isempty(idx)
    error('datasets:referenceLemma1Chain:missingFactor', ...
        'Case has no factor named %s.', name);
end
f = graph.Factors(idx);
f.Counter = [];
end

function w = localTrapzWeights(gridVec)
%LOCALTRAPZWEIGHTS Composite trapezoidal weights for a uniform grid.
%   Inputs   GRIDVEC, the grid points
%   Outputs  W, one weight per point, as a column
%   Utility  turn a sum over grid points into an integral.
h = gridVec(2) - gridVec(1);
w = h * ones(numel(gridVec), 1);
w(1)   = 0.5 * h;
w(end) = 0.5 * h;
end
