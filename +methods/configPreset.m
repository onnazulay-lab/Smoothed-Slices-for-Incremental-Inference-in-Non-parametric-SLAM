function config = configPreset(name, opts)
%CONFIGPRESET A named budget, so a cheap run cannot be mistaken for a paper run.
%   CONFIG = CONFIGPRESET(NAME) returns a commonMethodConfig whose sampling and
%   training budgets are set as a group, and which carries the preset's name in
%   CONFIG.budgetPreset so that every export says which budget produced it.
%
%   CONFIG = CONFIGPRESET(NAME, 'seed', 3, ...) forwards any further name/value
%   pairs to commonMethodConfig, applied AFTER the preset, so a caller can
%   override one knob without restating the rest.
%
%   Inputs
%     NAME    "paperLike" | "appFast"
%     opts    any commonMethodConfig name/value pair; overrides the preset
%
%   Outputs
%     CONFIG  a commonMethodConfig struct, plus the field budgetPreset
%
%   Utility
%     Collect the budget knobs that have to move together into one named
%     choice, and record which choice was made.
%
%   WHY A NAME AND NOT JUST SMALLER NUMBERS. The knobs below do not move
%   independently: dropping numSamples without dropping numBackwardSamples
%   leaves the backward pass dominating a run whose forward pass is now cheap,
%   and dropping either without touching nfisamTrainSamples leaves NF-iSAM's
%   flow training as most of the wall clock regardless. A caller reducing one
%   field at a time gets a run that is slower than it looks and less accurate
%   than it looks, in no fixed ratio. Reducing them as a set is the only
%   version of "make it fast" that has a defined meaning.
%
%   AND THE NAME IS THE POINT, NOT A LABEL. An appFast posterior is a posterior:
%   it plots, it exports, it scores, and nothing about the figure says the
%   budget was a fraction of the paper's. budgetPreset rides in result.config
%   into config.json and run_state.mat, so a bundle or a screenshot taken from a
%   fast run can be identified as one afterwards. This is the same problem as
%   a method name that claims a paper it only partly implements, and it gets
%   the same treatment: attach the qualification to the artifact.
%
%   "paperLike" is commonMethodConfig's own defaults, restated here under a
%   name rather than re-chosen. It exists so that the fast budget has something
%   to be the counterpart OF, and so that a caller who wants the paper budget
%   can say so instead of relying on a default staying put.
%
%   WHAT appFast IS FOR, AND WHAT IT IS NOT FOR. It is for the UI tests and for
%   a user clicking through the app to see what a panel looks like. It is NOT
%   for any number that gets reported: the accuracy at this budget has not been
%   characterized, and reducing nfisamTrainSamples in particular is known to be
%   consequential rather than merely coarse -- flows.trainFlow documents a 4-D
%   clique fitted from 2000 samples already overfitting badly enough to shrink
%   a unit-variance marginal, and this preset asks for a quarter of that.
%
%   See also methods.commonMethodConfig, methods.implementationRecord.

arguments
    name (1,1) string {mustBeMember(name, ["paperLike", "appFast"])}
end
arguments (Repeating)
    % Forwarded to commonMethodConfig verbatim, which is also what validates
    % them. Repeating rather than an opts struct because the target is a
    % function and not a class, so options.?target is not available here.
    opts
end

switch name
    case "paperLike"
        preset = {};

    case "appFast"
        % nfisamTrainSamples and the iteration cap are the single largest
        % saving, and the reason the preset has to reach past the sampling
        % budgets. One flow per clique at the paper's n_train = 2000 under a
        % 200-iteration cap is about twenty seconds of the run each; cutting
        % the outer samples alone leaves all of that in place and barely moves
        % the total.
        preset = { ...
            'numSamples',           60, ...
            'numInnerSamples',      20, ...
            'numBackwardSamples',   60, ...
            'separatorSupportSize', 61, ...
            'surfaceSupportSize',   60, ...
            'marginalGridSize',     101, ...
            'mmdEvalSamples',       200, ...
            'nfisamTrainSamples',   500, ...
            'nfisamTraining',       struct('MaxIterations', 60)};
end

% Overrides last, so a caller's explicit value wins over the preset's.
config = methods.commonMethodConfig(preset{:}, opts{:});

config.budgetPreset = name;
end
