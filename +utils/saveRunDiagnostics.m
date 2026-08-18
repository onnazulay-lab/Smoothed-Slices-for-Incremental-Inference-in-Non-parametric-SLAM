function report = saveRunDiagnostics(runDir, results, config, opts)
%SAVERUNDIAGNOSTICS Write the machine-readable diagnostics bundle for a run.
%
%   Inputs
%     RUNDIR   the run folder to write into
%     RESULTS  the method results
%     CONFIG   the config they were produced with
%
%   Outputs
%     REPORT   what was written, and where
%
%   Utility
%     Save the numerical part of the export specification section 14 requires:
%     a MAT file of raw results, a metrics CSV, config and process-trace JSON,
%     and a markdown summary.
%
%   Figures are exported separately by viz.exportAllFiguresAndDiagnostics, so
%   this function stays usable from a headless test run.

arguments
    runDir (1,1) string
    results (1,:) struct
    config struct = struct()
    opts.KeepStates (1,1) logical = false
end

report = struct();
report.runDir = char(runDir);

% --- Raw state ------------------------------------------------------------
% Trimmed first. The generated factors nest, so saving them whole reached
% 1.2 GB on the grid world and the write failed after every figure had
% already been exported -- an Export All that reported failure having done
% almost all of its work. See utils.trimResultsForExport.
% The saved variable keeps the name "results": a loader that already reads
% run_state.mat should not have to know that the contents got smaller.
[trimmedResults, note] = utils.trimResultsForExport(results, ...
    'KeepStates', opts.KeepStates);
bundle = struct();
bundle.results    = trimmedResults;
bundle.config     = config;
bundle.exportNote = note;

matPath = fullfile(char(runDir), 'run_state.mat');
save(matPath, '-struct', 'bundle', '-v7.3');
report.matFile = matPath;
report.matNote = note;

s = dir(matPath);
report.matBytes = s.bytes;

% --- Metrics table --------------------------------------------------------
tbl = utils.metricsTable(results);
csvPath = fullfile(char(runDir), 'metrics.csv');
writetable(tbl, csvPath);
report.metricsFile = csvPath;
report.metricsTable = tbl;

% --- Config and process traces -------------------------------------------
utils.writeJSON(fullfile(char(runDir), 'config.json'), config);
report.configFile = fullfile(char(runDir), 'config.json');

traces = struct();
for i = 1:numel(results)
    key = matlab.lang.makeValidName(results(i).methodName);
    if isfield(results(i), 'process')
        traces.(key) = results(i).process;
    end
end
utils.writeJSON(fullfile(char(runDir), 'process_trace.json'), traces);
report.processTraceFile = fullfile(char(runDir), 'process_trace.json');

% --- Markdown summary -----------------------------------------------------
report.markdownFile = viz.writeDiagnosticsMarkdown(runDir, results, config);
end
