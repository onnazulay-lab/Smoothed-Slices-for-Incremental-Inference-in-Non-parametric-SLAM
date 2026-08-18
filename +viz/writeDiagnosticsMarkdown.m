function path = writeDiagnosticsMarkdown(runDir, results, config)
%WRITEDIAGNOSTICSMARKDOWN Human-readable summary of one comparative run.
%
%   Inputs
%     RUNDIR   the run folder to write into
%     RESULTS  the method results
%     CONFIG   the config they were produced with
%
%   Outputs
%     PATH     the file that was written
%
%   Utility
%     Write the textual summary specification section 14 requires alongside
%     the machine bundle. It records what was run, what came out, and --
%     deliberately -- what is NOT yet implemented, so a reader of the export
%     folder is never left to infer that a missing method silently failed.

arguments
    runDir (1,1) string
    results (1,:) struct
    config struct = struct()
end

path = fullfile(char(runDir), 'diagnostics.md');
fid = fopen(path, 'w', 'n', 'UTF-8');
if fid < 0
    error('viz:writeDiagnosticsMarkdown:cannotOpen', 'Cannot write %s.', path);
end
closer = onCleanup(@() fclose(fid));

w = @(varargin) fprintf(fid, varargin{:});

w('# Smoothed Slices comparative run\n\n');
w('Generated %s  \n', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));
w('MATLAB %s  \n', version('-release'));
if isfield(config, 'seed')
    w('Random seed %d\n\n', config.seed);
end

% --- Budgets --------------------------------------------------------------
w('## Budgets\n\n');
w('| quantity | symbol | value |\n|---|---|---|\n');
budget = { ...
    'outer samples per elimination', '\|X_0\|', 'numSamples'; ...
    'nested inner samples',          '\|L_n\|', 'numInnerSamples'; ...
    'separator support',             '\|S\|',   'separatorSupportSize'; ...
    'RCS path support',              '\|X_1\|', 'surfaceSupportSize'; ...
    'active successors',             '\|N_0\|', 'activeSetSize'; ...
    'backward separator samples',    '-',       'numBackwardSamples'};
for i = 1:size(budget, 1)
    f = budget{i,3};
    if isfield(config, f)
        w('| %s | %s | %s |\n', budget{i,1}, budget{i,2}, localNum(config.(f)));
    end
end
w('\n');

% --- Results --------------------------------------------------------------
w('## Results\n\n');
tbl = utils.metricsTable(results);
w('| method | status | rel L1 | rel L2 | mass err | MMD | RMSE | ESS | runtime (s) |\n');
w('|---|---|---|---|---|---|---|---|---|\n');
for i = 1:numel(results)
    r = results(i);
    massErr = NaN;
    if isfield(r.metrics, 'massError'), massErr = r.metrics.massError; end
    w('| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n', ...
        tbl.Method(i), tbl.Status(i), ...
        localNum(tbl.RelL1Error(i)), localNum(tbl.RelL2Error(i)), localNum(massErr), ...
        localNum(tbl.MMD(i)), localNum(tbl.RMSE(i)), localNum(tbl.ESS(i)), ...
        localNum(tbl.RuntimeSec(i)));
end
w('\n');

% --- Provenance and honesty -----------------------------------------------
w('## Provenance\n\n');
for i = 1:numel(results)
    r = results(i);
    if isfield(r, 'provenance') && ~isempty(r.provenance) && isstruct(r.provenance)
        w('- **%s**: %s. %s\n', r.methodName, r.provenance.origin, r.provenance.uiNote);
    end
    % A method that returns a normalized posterior is scored on shape rather
    % than on the unnormalized f_new, and its curve on the grid is something
    % it did not itself produce. Both facts change how the table above should
    % be read, so neither is left to be inferred from a dash in a column.
    est = localEstimator(r);
    if isfield(est, 'normalized') && est.normalized
        w(['- **%s**: returns a NORMALIZED posterior. It has no unnormalized ' ...
           'f_new, so its mass error is not reported and its rel L1 is ' ...
           'measured against the reference''s normalized marginal. Its ' ...
           'curve on the grid is a %s\n'], r.methodName, ...
           localReconstruction(est));
    end
end
w(['- **Reference**: dense trapezoidal quadrature over the x1 x l1 grid, ' ...
   'cross-checked against a closed-form Gaussian marginalization.\n']);
w('\n');

% --- Paper fidelity, per method AND per engine -----------------------------
% The engine matters as much as the method here and the export used to say
% neither. Slices reaches two engines through one name -- the paper-literal
% three-node route and a general importance-sampling generalization -- so a
% line naming only the method would be right about one of them and wrong about
% the other. Written from result.implementation, which the driver fills in from
% whichever engine actually ran.
w('### Paper fidelity\n\n');
w('| method | engine | fidelity | may claim paper | main deviation |\n');
w('|---|---|---|---|---|\n');
anyRecord = false;
for i = 1:numel(results)
    r = results(i);
    if ~isfield(r, 'implementation') || ~isstruct(r.implementation)
        continue
    end
    anyRecord = true;
    im = r.implementation;
    w('| %s | `%s` | `%s` | %s | %s |\n', r.methodName, im.engine, ...
      im.paperFidelity, localYesNo(im.canClaimPaperExact), im.mainDeviation);
end
if ~anyRecord
    w('No method reported an implementation record.\n');
end
w('\n');
for i = 1:numel(results)
    r = results(i);
    if ~isfield(r, 'implementation') || ~isstruct(r.implementation)
        continue
    end
    im = r.implementation;
    w('**%s** (%s). %s\n\n', r.methodName, im.paperReference, im.scopeWarning);
    for d = im.deviationList(:).'
        w('  - %s\n', d);
    end
    w('\n');
end
w(['- **MMD**: the RBF kernel and median-heuristic bandwidth are ' ...
   'implementation choices. Neither paper specifies them.\n']);
w(['- **RMSE**: compares point estimates only and can hide posterior-shape ' ...
   'errors; read it with the marginal curves.\n\n']);

% --- Not implemented ------------------------------------------------------
notDone = results(arrayfun(@(r) r.status ~= "ok", results));
if ~isempty(notDone)
    w('## Not implemented in this iteration\n\n');
    for i = 1:numel(notDone)
        w('- **%s** (%s): %s\n', notDone(i).methodName, notDone(i).status, ...
            strjoin(cellstr(string(notDone(i).logs)), ' '));
    end
    w('\n');
end

% --- Numerical checks -----------------------------------------------------
w('## Surface checks (spec section 16.3)\n\n');
any16 = false;
for i = 1:numel(results)
    r = results(i);
    if r.status ~= "ok" || numel(r.states) < 2, continue; end
    d = r.states(2).Diagnostics;
    if ~isfield(d, 'inner') || ~isfield(d.inner, 'checks'), continue; end
    c = d.inner.checks;
    any16 = true;
    w('- **%s**: nonneg=%d, rows normalized=%d, positive mass=%d, finite=%d', ...
        r.methodName, c.nonNegative, c.rowsNormalized, c.positiveMass, c.finite);
    if ~isempty(c.failures), w(' — %s', c.failures); end
    w('\n');
end
if ~any16
    w('No surface-based method ran.\n');
end
w('\n');

% --- Surface complexity, research sheet E2 --------------------------------
% The sheet requires rank_eps, nnz_eps and the singular spectrum to be SAVED
% TO DIAGNOSTICS, not only shown. Both surfaces are listed: R_0 = diag(Z) P_0
% R_1 caps rank(R_0) at rank(R_1), so a compactness claim about R_0 that does
% not show R_1 beside it cannot say whether the recursion earned it.
w('## Surface complexity (research sheet E2)\n\n');
anyE2 = false;
for i = 1:numel(results)
    r = results(i);
    if r.status ~= "ok" || numel(r.states) < 2, continue; end
    d = r.states(2).Diagnostics;
    if ~isfield(d, 'inner') || ~isfield(d.inner, 'surface'), continue; end
    s = d.inner.surface;
    if ~isfield(s, 'rank')
        w('- **%s**: not measured (surfaceDiagnostics off)\n', r.methodName);
        anyE2 = true;
        continue
    end
    t = d.inner.terminalSurface;
    anyE2 = true;
    w(['- **%s**: R_0 is %dx%d, rank_eps=%d (tol %g), 99%%-energy rank=%d, ' ...
       'effective rank=%.2f, sigma_2/sigma_1=%.3g, nnz_eps=%d, ' ...
       'sparsity=%.3f — **%s**\n'], ...
        r.methodName, s.size(1), s.size(2), s.rank, s.rankTol, ...
        s.energyRankAtLevel, s.effectiveRank, s.spectralGap, s.nnz, ...
        s.sparsity, s.verdict);
    if isfield(t, 'rank')
        w('  - terminal R_1: rank_eps=%d, 99%%-energy rank=%d — %s\n', ...
            t.rank, t.energyRankAtLevel, t.verdict);
    end
    w('  - %s\n', s.reason);
end
if ~anyE2
    w(['No surface was built, so there is no complexity to report. Only the ' ...
       'Lemma 1 structural route builds one; the general engine never ' ...
       'consults the inner estimator.\n']);
end
w('\n');

w('## Files\n\n');
w('- `run_state.mat` raw results and config\n');
w('- `metrics.csv` the table above\n');
w('- `config.json`, `process_trace.json` machine-readable settings and stage traces\n');
w('- `figures/` PNG and PDF of every registered axes\n');
end

% -------------------------------------------------------------------------
function s = localYesNo(tf)
%LOCALYESNO A logical as "yes" or "no".
%   Inputs   TF, logical
%   Outputs  S, the word
%   Utility  the summary is prose, and "1" in a sentence is not.
%
%   Inputs   tf  logical
%   Outputs  s   "yes" or "NO"
%   Utility  A 0 in a "may claim paper" column reads as missing data. The
%            capitalised NO is deliberate: it is the answer for four of the
%            five routes and the one a reader must not skim past.
if tf
    s = "yes";
else
    s = "**NO**";
end
end

% -------------------------------------------------------------------------
function est = localEstimator(r)
%LOCALESTIMATOR A result's estimator record, or an empty struct.
%   Inputs   R, a method result
%   Outputs  EST, the record or struct()
%   Utility  let a failed or partial run still be described.
est = struct();
if ~isfield(r, 'posterior') || ~isstruct(r.posterior) || ~isscalar(r.posterior)
    return
end
if ~isfield(r.posterior, 'estimator') || ~isstruct(r.posterior.estimator)
    return
end
est = r.posterior.estimator;
end

function s = localReconstruction(est)
%LOCALRECONSTRUCTION How the estimator turned samples back into a density.
%   Inputs   EST, the estimator record
%   Outputs  S, the description
%   Utility  both papers avoid intermediate density reconstruction, so which
%           route was taken is worth stating rather than assuming.
if isfield(est, 'reconstruction')
    s = char(string(est.reconstruction));
else
    s = 'reconstruction from samples.';
end
end

% -------------------------------------------------------------------------
function s = localNum(v)
%LOCALNUM A number as text, with NaN and Inf left readable.
%   Inputs   V, a scalar
%   Outputs  S, the text
%   Utility  a missing metric should read as "NaN" in the summary rather than
%           as a blank cell.
if isempty(v)
    s = '-';
elseif ischar(v) || isstring(v)
    s = char(v);
elseif ~isscalar(v)
    s = mat2str(v);
elseif isnan(v)
    s = '-';
elseif isinf(v)
    s = 'dense';
elseif v == round(v) && abs(v) < 1e6
    s = sprintf('%d', v);
else
    s = sprintf('%.4g', v);
end
end
