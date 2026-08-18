function out = budgetComparison(results)
%BUDGETCOMPARISON Did the methods actually run on the same budgets?
%
%   Inputs
%     RESULTS  the method results, each carrying the config it actually used
%
%   Outputs
%     OUT.columns       1-by-(1+M) string, "quantity" then one per method
%     OUT.data          N-by-(1+M) cellstr, ready for a uitable
%     OUT.matched       N-by-1 logical, per quantity
%     OUT.notes         string array, one per unmatched quantity
%     OUT.numCompleted  how many methods contributed a budget at all
%
%   Utility
%     Read the config each method CARRIED BACK and compare them field by
%     field, so a budget a method changed without saying so is visible.
%
%   Specification section 1 requires the comparison to be run with matched
%   budgets, and commonMethodConfig honours that by handing every method
%   literally the same struct. That is an intention, not a check: a method is
%   free to modify its copy on the way in, and one of them does. Smoothed
%   Slices sets innerEstimator to "rcs" -- which is the entire difference
%   between it and Slices -- and on a general graph it also picks a finite
%   activeSetSize, because leaving it at Inf would select the dense update of
%   Eq. (48) and make the two methods bit-for-bit identical.
%
%   So the answer this panel gives is not "yes" but "these fields agree, these
%   differ, and here is the method's own recorded reason for each difference".
%   A difference with no reason attached is the interesting case: it means a
%   method changed a budget without saying so.
%
%   READ NUMCOMPLETED BEFORE READING MATCHED. Agreement is computed over the
%   methods that finished, so with one of them MATCHED is all true and NOTES
%   is empty -- not because the budgets matched but because nothing was ever
%   compared. A caller that renders that as "every budget agreed" reports a
%   result the run did not produce, which on a stopped run is the most
%   misleading thing this panel could say.

arguments
    results (1,:) struct
end

fields = [ ...
    "numSamples"; "numInnerSamples"; "separatorSupportSize"; ...
    "surfaceSupportSize"; "activeSetSize"; "numBackwardSamples"; ...
    "marginalGridSize"; "nfisamTrainSamples"; ...
    "innerEstimator"; "incremental"; "seed"];

names = arrayfun(@(r) string(r.methodName), results);
out = struct();
out.columns = ["quantity", names];
out.data    = cell(numel(fields), 1 + numel(results));
out.matched = true(numel(fields), 1);
out.notes   = string.empty(0, 1);
out.numCompleted = sum(arrayfun(@(r) r.status == "ok", results));

for i = 1:numel(fields)
    f = fields(i);
    out.data{i,1} = char(f);

    present = {};
    for j = 1:numel(results)
        r = results(j);
        % Only a completed run says anything about the budgets it used. A
        % cancelled method's config is the one it was ASKED for, which would
        % make the panel report agreement that was never tested.
        if r.status ~= "ok" || ~isfield(r.config, f)
            out.data{i,1+j} = '-';
            continue
        end
        v = r.config.(f);
        out.data{i,1+j} = localShow(v);
        present{end+1} = v; %#ok<AGROW>
    end

    for k = 2:numel(present)
        if ~isequal(present{k}, present{1})
            out.matched(i) = false;
            break
        end
    end

    if ~out.matched(i)
        out.notes(end+1, 1) = localReason(results, f); %#ok<AGROW>
    end
end
end

% =========================================================================
function s = localReason(results, field)
%LOCALREASON The method's own recorded reason for changing one budget.
%   Inputs   RESULTS the results, FIELD the config field that differs
%   Outputs  S, the reason, or a line saying none was given
%   Utility  a difference with no reason attached is the interesting case, and
%           it has to read differently from one that was declared.
%
%   AN EXPLANATION IS A NOTE NOT EVERY METHOD CARRIES. commonMethodConfig
%   attaches provenance to most budgets -- "paper: 150 (Plaza2)" and the like
%   -- and every method carries that same string away with it. Such a note
%   describes where the DEFAULT came from and says nothing whatever about why
%   two methods ended up disagreeing, so treating it as an explanation would
%   let a silent override hide behind the paper citation it ignored.
%
%   Silence is the finding rather than a formatting problem, so it is said in
%   words instead of left as an empty cell.
who   = string.empty(1, 0);
notes = string.empty(1, 0);
nOk   = 0;

for j = 1:numel(results)
    r = results(j);
    if r.status ~= "ok", continue, end
    nOk = nOk + 1;
    if ~isfield(r.config, 'provenance') || ~isfield(r.config.provenance, field)
        continue
    end
    who(end+1)   = string(r.methodName);         %#ok<AGROW>
    notes(end+1) = string(r.config.provenance.(field)); %#ok<AGROW>
end

shared = numel(notes) == nOk && isscalar(unique(notes));

if isempty(notes) || shared
    s = field + " differs across the methods and NO method recorded why. " + ...
        "A budget that changes without a reason attached breaks the " + ...
        "matched-budget premise of the comparison.";
else
    s = field + " -- " + strjoin(who + ": " + notes, "; ");
end
end

% =========================================================================
function s = localShow(v)
%LOCALSHOW One config value as a table cell.
%   Inputs   V, any config value
%   Outputs  S, its text
%   Utility  budgets are numbers, strings, logicals and Inf, and the table
%           takes text.
if isstring(v) || ischar(v)
    s = char(string(v));
elseif islogical(v)
    if v, s = 'on'; else, s = 'off'; end
elseif isempty(v)
    s = '-';
elseif ~isscalar(v)
    s = sprintf('%d values', numel(v));
elseif isinf(v)
    s = 'dense';
elseif v == round(v)
    s = sprintf('%d', v);
else
    s = sprintf('%.4g', v);
end
end
