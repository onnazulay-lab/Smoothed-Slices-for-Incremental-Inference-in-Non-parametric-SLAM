function logs = sparsificationLogs(states)
%SPARSIFICATIONLOGS Warnings about discarded mass, lifted out of the diagnostics.
%   LOGS = SPARSIFICATIONLOGS(STATES) walks an elimination and returns one
%   string per step whose sparsification dropped enough mass to warrant saying
%   so, already prefixed with the step number and the variable eliminated.
%
%   Inputs
%     STATES   core.EliminationState array from either engine
%
%   Outputs
%     LOGS     string column, empty when every step kept enough
%
%   Utility
%     Put the warning somewhere a reader will meet it. A run whose answer has
%     measurably moved should not depend on someone opening
%     states(i).Diagnostics to find that out.
%
%   TWO ENGINES, TWO PLACES, ONE MESSAGE. The two-pose route stores its Eq. (49)
%   active set under Diagnostics.inner.transition; the general engine stores its
%   separator truncation under Diagnostics.sparsification. Both structs come
%   from utils.retainedMassSummary, so both carry the same warning field and the
%   same indexedOver, and this function only has to know where to look. It
%   deliberately does not reword them: the summary already says what was dropped
%   and whether the two-pose sweep characterizes that route, and restating it
%   here would be a second copy to keep in step.
%
%   See also utils.retainedMassSummary, methods.smoothed.buildActiveSuccessors.

arguments
    states
end

logs = strings(0, 1);

for i = 1:numel(states)
    d = states(i).Diagnostics;
    if ~isstruct(d)
        continue
    end

    info = struct.empty;
    if isfield(d, 'sparsification') && isstruct(d.sparsification)
        info = d.sparsification;
    elseif isfield(d, 'inner') && isstruct(d.inner) ...
            && isfield(d.inner, 'transition') && isstruct(d.inner.transition)
        info = d.inner.transition;
    end

    if isempty(info) || ~isfield(info, 'warning') || info.warning == ""
        continue
    end

    % A dense or untruncated step reports ones and never warns, so reaching
    % here means something really was discarded.
    logs(end+1, 1) = sprintf('step %d (%s): %s', ...
        i, states(i).EliminatedVar, info.warning); %#ok<AGROW>
end
end
