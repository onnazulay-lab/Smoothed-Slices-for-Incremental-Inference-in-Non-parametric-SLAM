function report = exportAllFiguresAndDiagnostics(registry, results, config, opts)
%EXPORTALLFIGURESANDDIAGNOSTICS The Export All button of specification 14.
%
%   Inputs
%     REGISTRY     the registered axes, from the app
%     RESULTS      the method results
%     CONFIG       the config they were produced with
%     UIFigure     handle for the whole-app snapshot (optional)
%     ProjectRoot  where results/ lives
%     RunDir       export into an existing folder instead of creating one
%     Progress     a utils.ProgressReporter, for the figure loop
%
%   Outputs
%     REPORT       the run folder, the per-figure records, numExported,
%                  cancelled, and a summary line
%
%   Utility
%     Write a run folder containing:
%
%       figures/<name>.png   300 dpi raster of every REGISTERED axes
%       figures/<name>.pdf   vector version of the same
%       app_snapshot.png/pdf the whole UI, when a figure handle is supplied
%       run_state.mat        raw results and config
%       metrics.csv          the comparison table
%       config.json          settings, seed and MATLAB version
%       process_trace.json   per-stage traces for the Process Explorer
%       diagnostics.md       readable summary
%
%   Only registered axes are exported, which is the point of section 21: a
%   panel that was never registered is a panel nobody will notice is missing
%   from the export.
%
%   A STOPPED EXPORT STILL WRITES THE BUNDLE. Cancellation abandons the
%   remaining figures and goes straight to the numerical part: metrics.csv,
%   config.json, process_trace.json, diagnostics.md and run_state.mat are
%   seconds of work carrying minutes of run, while the figures are the slow
%   part and can be produced again from the saved state. REPORT.CANCELLED and
%   the per-figure records say exactly which images are missing, so nobody has
%   to infer it from a short folder listing.

arguments
    registry (1,:) struct
    results (1,:) struct
    config struct = struct()
    opts.UIFigure = []
    opts.ProjectRoot (1,1) string = utils.projectRoot()
    opts.RunDir (1,1) string = ""
    opts.KeepStates (1,1) logical = false
    % Both by default, because that is what every existing caller got before
    % this option existed and a default that silently drops a format would
    % change what old bundles contain. The Figure Generator tab offers the
    % other two: the PDF is what goes in the report and the PNG is what goes
    % in a message, and a run that only ever needs one was paying for both.
    opts.Formats (1,1) string {mustBeMember(opts.Formats, ...
        ["both", "png", "pdf"])} = "both"
    opts.Progress = []
end

wantPng = opts.Formats ~= "pdf";
wantPdf = opts.Formats ~= "png";

if strlength(opts.RunDir) > 0
    runDir = char(opts.RunDir);
    if ~isfolder(fullfile(runDir, 'figures')), mkdir(fullfile(runDir, 'figures')); end
else
    runDir = utils.createRunFolder(opts.ProjectRoot, config);
end

report = struct();
report.runDir = runDir;
report.cancelled = false;
report.figures = struct('name', {}, 'png', {}, 'pdf', {}, 'ok', {}, 'message', {});

p = utils.progressOf(struct('progress', opts.Progress));
nFig = numel(registry);

% --- 1. Every registered axes --------------------------------------------
for i = 1:nFig
    entry = registry(i);
    name  = char(entry.name);
    rec   = struct('name', name, 'png', '', 'pdf', '', 'ok', false, 'message', '');

    try
        % 0.85 rather than 1: the bundle below is the rest of the bar, and a
        % bar that reaches full before the last file is written is the exact
        % moment a user closes the app.
        p.report(0.85 * (i-1) / nFig, sprintf("exporting %s (%d of %d)", ...
            string(name), i, nFig));
    catch err
        if ~utils.ProgressReporter.isCancellation(err), rethrow(err), end
        report.cancelled = true;
        for j = i:nFig
            report.figures(end+1) = struct('name', char(registry(j).name), ...
                'png', '', 'pdf', '', 'ok', false, ...
                'message', 'export stopped before this figure'); %#ok<AGROW>
        end
        break
    end

    if ~isgraphics(entry.handle)
        rec.message = 'handle is no longer valid';
        report.figures(end+1) = rec; %#ok<AGROW>
        continue
    end

    pngPath = fullfile(runDir, 'figures', [name '.png']);
    pdfPath = fullfile(runDir, 'figures', [name '.pdf']);
    try
        if wantPng
            exportgraphics(entry.handle, pngPath, 'Resolution', 300);
            rec.png = pngPath;
        end
        if wantPdf
            exportgraphics(entry.handle, pdfPath, 'ContentType', 'vector');
            rec.pdf = pdfPath;
        end
        rec.ok = true;
    catch err
        rec.message = err.message;
    end
    report.figures(end+1) = rec; %#ok<AGROW>
end

report.numExported = sum([report.figures.ok]);
report.numFailed   = sum(~[report.figures.ok]);

% --- 2. Whole-app snapshot ------------------------------------------------
if ~isempty(opts.UIFigure) && isgraphics(opts.UIFigure) && ~report.cancelled
    try
        exportapp(opts.UIFigure, fullfile(runDir, 'app_snapshot.png'));
        exportapp(opts.UIFigure, fullfile(runDir, 'app_snapshot.pdf'));
        report.snapshot = fullfile(runDir, 'app_snapshot.png');
    catch err
        report.snapshotError = err.message;
    end
end

% --- 3-4. Numerical bundle and markdown summary ---------------------------
% Reached whether or not the figure loop was stopped: see the header.
p.announce(0.90, "writing the numerical bundle");
diag = utils.saveRunDiagnostics(string(runDir), results, config, ...
    'KeepStates', opts.KeepStates);
report.diagnostics = diag;
report.markdown    = diag.markdownFile;

if report.cancelled
    report.summary = sprintf( ...
        ['export stopped: %d of %d figure(s) written, bundle complete, ' ...
         '%.1f MB state, in %s'], ...
        report.numExported, numel(report.figures), diag.matBytes / 1e6, runDir);
    % NOT full, and not the word "complete". The bundle was written and the
    % figures were not, so the bar holds where the bundle left it. Driving it
    % to 100% under the word complete is what a glance takes in, whatever the
    % summary beside it goes on to say -- the same mistake runComparison used
    % to make on the way out of a Stop.
    p.announce(0.90, sprintf("export stopped: %d of %d figure(s) written", ...
        report.numExported, numel(report.figures)));
else
    report.summary = sprintf( ...
        '%d figure(s) exported, %d failed, %.1f MB state, bundle written to %s', ...
        report.numExported, report.numFailed, diag.matBytes / 1e6, runDir);
    p.announce(1, "export complete");
end
end
