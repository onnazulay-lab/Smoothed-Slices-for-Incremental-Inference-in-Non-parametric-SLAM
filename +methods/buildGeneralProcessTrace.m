function trace = buildGeneralProcessTrace(methodName, states, config)
%BUILDGENERALPROCESSTRACE Process trace for the general-graph engine.
%
%   Inputs
%     METHODNAME  which method produced the states
%     STATES      the elimination states
%     CONFIG      the method config
%
%   Outputs
%     TRACE       an ordered dense stage list, the same contract
%                 methods.buildProcessTrace returns
%
%   Utility
%     Give the Process Explorer slider something to index on the general
%     engine.
%
%   Same contract as methods.buildProcessTrace, specification section 8: an
%   ordered dense list of stages that the process stage slider indexes. The
%   vocabulary differs because the general engine has no separate backward
%   stage list; the traversal is one pass over the conditionals in reverse,
%   so the stages are the eliminations and the diagnostics that matter are
%   the two effective sample sizes and the separator dimension.

arguments
    methodName (1,1) string
    states (1,:) core.EliminationState
    config (1,1) struct
end

stages = struct('stageType', {}, 'nodeLabel', {}, 'latex', {}, ...
                'cardinality', {}, 'diagnostics', {}, 'step', {});

for i = 1:numel(states)
    st = states(i);
    d = st.Diagnostics;

    if isfield(d, 'terminal')
        stageType = "rootMarginal";
        card = struct('outer', 0, 'separator', 0, 'separatorDim', 0);
    elseif methodName == "Smoothed Slices"
        stageType = "surfaceRecursion";
        card = struct('outer', d.numOuter, 'separator', d.numSupport, ...
                      'separatorDim', d.separatorDim);
    else
        stageType = "elimination";
        card = struct('outer', d.numOuter, 'separator', d.numSupport, ...
                      'separatorDim', d.separatorDim);
    end

    stages(end+1) = struct( ...
        'stageType',   stageType, ...
        'nodeLabel',   sprintf('omega_%d = %s, S_%d = {%s}', ...
                          st.Step, st.EliminatedVar, st.Step, ...
                          strjoin(cellstr(st.Separator), ',')), ...
        'latex',       localStageLatex(st), ...
        'cardinality', card, ...
        'diagnostics', d, ...
        'step',        st.Step); %#ok<AGROW>
end

trace = struct();
trace.method     = methodName;
trace.stages     = stages;
trace.numStages  = numel(stages);
trace.stageTypes = unique(string({stages.stageType}), 'stable');
trace.budgets    = struct('numSamples', config.numSamples, ...
                          'separatorSupportSize', config.separatorSupportSize);
end

% -------------------------------------------------------------------------
function s = localStageLatex(st)
%LOCALSTAGELATEX The LaTeX line the Process Explorer shows for one stage.
%   Inputs   ST, one stage of the trace
%   Outputs  S, its equation line
%   Utility  specification section 4 requires every mathematical string in the
%           UI to be rendered as LaTeX, and the stage caption is one.
% Braced subscripts throughout: D_10 renders as D sub-one followed by a
% literal zero, and the grid world reaches step 13.
w = utils.mathName(st.EliminatedVar);
if isempty(st.Separator)
    s = sprintf('$\\hat P(%s \\mid D)$', w);
else
    sepStr = strjoin(cellstr(utils.mathName(st.Separator)), ',');
    s = sprintf(['$\\hat f_{\\mathrm{new}}(%s \\mid D_{%d}) = \\frac{1}{N}\\sum_n ' ...
                 '\\frac{\\prod_{f \\in F(%s)} f(%s^{(n)}, %s)}{q(%s^{(n)})}$'], ...
        sepStr, st.Step, w, w, sepStr, w);
end
end
