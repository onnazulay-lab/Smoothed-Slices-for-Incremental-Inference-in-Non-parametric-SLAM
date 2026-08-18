function s = computeRuntimeSummary(timings)
%COMPUTERUNTIMESUMMARY Split total runtime into the phases the spec names.
%
%   Inputs
%     TIMINGS  struct of named durations in seconds
%
%   Outputs
%     S        the total and each phase's share of it
%
%   Utility
%     Report total, forward/upward, backward/downward, training and sampling
%     time separately, as specification section 16 asks, because a method can
%     win on total runtime while being far worse in the phase that has to run
%     online.

arguments
    timings (1,1) struct
end

s = struct();
fn = fieldnames(timings);
total = 0;
for i = 1:numel(fn)
    v = timings.(fn{i});
    if isnumeric(v) && isscalar(v)
        s.(fn{i}) = v;
        total = total + v;
    end
end

s.total = total;
for i = 1:numel(fn)
    if isfield(s, fn{i}) && total > 0
        s.([fn{i} 'Share']) = s.(fn{i}) / total;
    end
end
end
