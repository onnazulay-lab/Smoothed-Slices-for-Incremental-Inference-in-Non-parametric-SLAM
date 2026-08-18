function [trimmed, note] = trimResultsForExport(results, opts)
%TRIMRESULTSFOREXPORT Drop the engine internals a saved run does not need.
%
%   Inputs
%     RESULTS  the method results
%
%   Outputs
%     TRIMMED  the same results with the heavy per-step objects replaced by a
%              small summary
%     NOTE     what was removed, so the export says so rather than appearing
%              to be complete
%
%   Utility
%     Keep a saved run to a sane size without silently losing the record of
%     what was dropped.
%
%   WHY THIS EXISTS. RESULT.states holds a core.EliminationState per
%   elimination, each carrying the core.ApproximateFactor it generated: an
%   |X|-by-|S| slice matrix plus the factors it was built from, which are
%   themselves generated factors carrying their own slice matrices. The
%   nesting is what makes the engine work and it is also what makes it
%   enormous. On the office grid world's thirteen variables at app-default budgets the
%   saved run reached 1.2 GB and the v7.3 write failed outright, taking the
%   whole Export All with it after every figure had already been written.
%
%   The export is a record of the RUN, not a resumable checkpoint. The
%   posterior samples, the metrics, the per-stage diagnostics and the
%   factorization all survive; what goes is the intermediate representation,
%   which cannot be interpreted without the case object anyway.
%
%   Set 'KeepStates' true to save them regardless. That is the flag to reach
%   for when a run is being saved in order to be debugged, and the size
%   should then be expected.

arguments
    results (1,:) struct
    opts.KeepStates (1,1) logical = false
end

note = "";
trimmed = results;
if opts.KeepStates || isempty(results)
    return
end

heavy = ["states", "book"];
dropped = strings(0,1);

% A structural summary of the elimination, small enough to keep and enough to
% read the run back: which variable went when, on what separator, and how the
% estimate behaved there.
%
% Built for every element first and attached with DEAL. Assigning a new field
% into one element of a struct array is a "dissimilar structures" error, and
% the results array is heterogeneous by method: NF-iSAM has no states at all.
summaries = cell(1, numel(trimmed));
for i = 1:numel(trimmed)
    summaries{i} = [];
    if ~isfield(trimmed, 'states'), continue, end
    s = trimmed(i).states;
    if isempty(s), continue, end
    summaries{i} = struct( ...
        'step',          num2cell([s.Step]), ...
        'eliminatedVar', num2cell([s.EliminatedVar]), ...
        'separator',     arrayfun(@(x) {x.Separator}, s), ...
        'localData',     arrayfun(@(x) {x.LocalDataNames}, s), ...
        'route',         num2cell([s.SamplingRoute]), ...
        'diagnostics',   arrayfun(@(x) {x.Diagnostics}, s));
end
[trimmed.eliminationSummary] = deal(summaries{:});

for f = heavy
    if ~isfield(trimmed, f), continue, end
    [trimmed.(f)] = deal([]);
    dropped(end+1) = f; %#ok<AGROW>
end

if ~isempty(dropped)
    note = sprintf(['Engine internals (%s) were dropped before saving; ' ...
        'eliminationSummary holds the per-step record. Pass ' ...
        'KeepStates true to utils.saveRunDiagnostics to keep them.'], ...
        strjoin(cellstr(unique(dropped)), ', '));
end
end
