function card = collectCardinality(states, config)
%COLLECTCARDINALITY Gather the |space letter| quantities for the diagnostics.
%
%   Inputs
%     STATES  the elimination states
%     CONFIG  the method config
%
%   Outputs
%     CARD    the cardinalities, one field per space
%
%   Utility
%     Collect them in one place, so the UI and the CSV never disagree.
%
%   Specification section 16 requires every finite space to be reported as
%   |X_j|, |S_j|, |N_r|, |Phi_s| and displayed in blue. This collects them
%   from the elimination states so the UI and the CSV never disagree.

arguments
    states (1,:) core.EliminationState
    config (1,1) struct
end

card = struct( ...
    'outer',     config.numSamples, ...
    'inner',     0, ...
    'separator', 0, ...
    'pathSupport', 0, ...
    'activeSet',   0, ...
    'storage',     0);

for i = 1:numel(states)
    d = states(i).Diagnostics;
    if isfield(d, 'numInnerSamples'),  card.inner     = max(card.inner,     d.numInnerSamples);  end
    if isfield(d, 'separatorSupport'), card.separator = max(card.separator, d.separatorSupport); end
    if isfield(d, 'inner')
        if isfield(d.inner, 'supportX1'),     card.pathSupport = max(card.pathSupport, d.inner.supportX1); end
        if isfield(d.inner, 'activeSetSize'), card.activeSet   = max(card.activeSet,   d.inner.activeSetSize); end
        if isfield(d.inner, 'storage'),       card.storage     = max(card.storage,     d.inner.storage); end
    end
end

% LaTeX labels for the UI, in the mandated |space letter| notation.
card.latex = struct( ...
    'outer',       utils.cardinality("\mathcal{X}_0", card.outer), ...
    'inner',       utils.cardinality("L_n",           card.inner), ...
    'separator',   utils.cardinality("\mathcal{S}",   card.separator), ...
    'pathSupport', utils.cardinality("\mathcal{X}_1", card.pathSupport), ...
    'activeSet',   utils.cardinality("\mathcal{N}_0", card.activeSet));
end
