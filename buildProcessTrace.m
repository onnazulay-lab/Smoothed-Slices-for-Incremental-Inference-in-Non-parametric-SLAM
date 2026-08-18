function trace = buildProcessTrace(methodName, states, back, config)
%BUILDPROCESSTRACE Per-stage record consumed by the Process Explorer slider.
%
%   Inputs
%     METHODNAME  which method produced the states
%     STATES      the forward pass's elimination states
%     BACK        the backward pass's record
%     CONFIG      the method config
%
%   Outputs
%     TRACE       an ordered dense stage list
%
%   Utility
%     Give the Process Explorer slider something to index.
%
%   Specification section 8 fixes the shape of this trace: each stage carries
%   a stageType, a nodeLabel, a cardinality block and a diagnostics block,
%   with method-specific vocabularies. The stage list is what the process
%   stage slider indexes, so it must be dense and ordered.

arguments
    methodName (1,1) string
    states (1,:) core.EliminationState
    back (1,1) struct
    config (1,1) struct
end

stages = struct('stageType', {}, 'nodeLabel', {}, 'latex', {}, ...
                'cardinality', {}, 'diagnostics', {}, 'step', {});

% --- Forward stages -------------------------------------------------------
for i = 1:numel(states)
    st = states(i);

    if methodName == "Smoothed Slices" && isfield(st.Diagnostics, 'innerEstimator') ...
            && st.Diagnostics.innerEstimator == "rcs"
        stageType = "surfaceRecursion";
    elseif st.SamplingRoute == "terminal"
        stageType = "elimination";
    else
        stageType = "elimination";
    end

    card = struct();
    if isfield(st.Diagnostics, 'numOuterSamples')
        card.outer = st.Diagnostics.numOuterSamples;
    end
    if isfield(st.Diagnostics, 'numInnerSamples')
        card.inner = st.Diagnostics.numInnerSamples;
    end
    if isfield(st.Diagnostics, 'separatorSupport')
        card.separator = st.Diagnostics.separatorSupport;
    end
    if isfield(st.Diagnostics, 'inner') && isfield(st.Diagnostics.inner, 'supportX1')
        card.pathSupport = st.Diagnostics.inner.supportX1;
        card.activeSet   = st.Diagnostics.inner.activeSetSize;
    end

    stages(end+1) = struct( ...
        'stageType',   stageType, ...
        'nodeLabel',   sprintf('omega_%d = %s, S_%d = {%s}', ...
                          st.Step, st.EliminatedVar, st.Step, ...
                          strjoin(cellstr(st.Separator), ',')), ...
        'latex',       localStageLatex(st), ...
        'cardinality', card, ...
        'diagnostics', st.Diagnostics, ...
        'step',        st.Step); %#ok<AGROW>
end

% --- Backward stages ------------------------------------------------------
for i = 1:numel(back.order)
    v   = back.order(i);
    key = matlab.lang.makeValidName(v);
    stages(end+1) = struct( ...
        'stageType',   "backward", ...
        'nodeLabel',   sprintf('marginal of %s', v), ...
        'latex',       sprintf('$\\hat P(%s \\mid D)$', ...
                          regexprep(v, '^([a-zA-Z]+)(\d+)$', '$1_{$2}')), ...
        'cardinality', struct('backwardSamples', config.numBackwardSamples, ...
                              'grid', numel(back.grids.(key))), ...
        'diagnostics', back.diagnostics.(key), ...
        'step',        numel(states) + i); %#ok<AGROW>
end

trace = struct();
trace.method    = methodName;
trace.stages    = stages;
trace.numStages = numel(stages);
trace.stageTypes = unique(string({stages.stageType}), 'stable');
end

% -------------------------------------------------------------------------
function s = localStageLatex(st)
%LOCALSTAGELATEX The LaTeX line the Process Explorer shows for one stage.
%   Inputs   ST, one stage of the trace
%   Outputs  S, its equation line
%   Utility  specification section 4 requires every mathematical string in the
%           UI to be rendered as LaTeX, and the stage caption is one.
w = regexprep(st.EliminatedVar, '^([a-zA-Z]+)(\d+)$', '$1_{$2}');
if isempty(st.Separator)
    s = sprintf('$\\hat P(%s \\mid D)$', w);
else
    sep = arrayfun(@(v) regexprep(v, '^([a-zA-Z]+)(\d+)$', '$1_{$2}'), st.Separator);
    sepStr = strjoin(cellstr(sep), ',');
    s = sprintf('$P_{\\mathrm{joint}}(%s,%s \\mid D_%d) = \\hat P(%s \\mid %s, D_%d)\\,\\hat f_{\\mathrm{new}}(%s \\mid D_%d)$', ...
        w, sepStr, st.Step, w, sepStr, st.Step, sepStr, st.Step);
end
end
