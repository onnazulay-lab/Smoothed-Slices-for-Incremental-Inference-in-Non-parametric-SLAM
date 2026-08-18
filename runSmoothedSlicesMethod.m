function result = runSmoothedSlicesMethod(caseData, config)
%RUNSMOOTHEDSLICESMETHOD Recursive Conditional-Smoothing Slices (RCS).
%
%   Inputs
%     CASEDATA  the case; its engine tag selects the route
%     CONFIG    the method config
%
%   Outputs
%     RESULT    the unified result contract, tagged as a proposed extension
%
%   Utility
%     Run the same elimination machinery as the Slices method, with the nested
%     inner sampling of Eq. (23) replaced by the cached conditional smoothing
%     surface of Eq. (50).
%
%   PROVENANCE. This is a PROPOSED EXTENSION, not part of the Slices paper.
%   The result is tagged accordingly so the UI can mark it, as specification
%   section 17 requires: the distinction between what the authors published
%   and what we are adding must be visible wherever a number from this method
%   is displayed.
%
%   The object cached here is a conditional smoothing SURFACE -- an expected
%   future factor contribution -- and never a posterior density. Training a
%   density model here would turn the method into NF-iSAM, which section 1 of
%   the spec calls out as the implementation mistake to avoid.

arguments
    caseData (1,1) struct
    config (1,1) struct = methods.commonMethodConfig()
end

config.innerEstimator = "rcs";
% Recorded, not just done. The Compare Methods tab reads the budgets back off
% each result and flags any that disagree; this one is MEANT to disagree, and
% a difference with no reason attached is exactly the case that panel exists
% to catch.
config.provenance.innerEstimator = ...
    "set to rcs by runSmoothedSlicesMethod: Eq. (50) in place of the nested " + ...
    "Eq. (23). This single field is the whole difference between this method " + ...
    "and Slices, which is why both run through one driver.";

% On a general graph there is no nested inner sampling left to remove: the
% general engine already does the inner integral as one slice average. Leaving
% activeSetSize at Inf there would make this method bit-for-bit identical to
% Slices -- two robots drawn on top of each other and a comparison with nothing
% in it. A default is therefore chosen from the support budget, and it is
% recorded in the result so the number is never mistaken for something the user
% asked for.
%
% AND IT IS A FRACTION OF |S|, WHICH IS WHAT IT PRUNES. This comment used to
% say the gain comes from "the active successor sets" and that Inf selects the
% dense update of Eq. (48). Neither is true on this engine: the general engine
% truncates SEPARATOR support points, and the successor sets N_r(a) of
% Eq. (49) exist only on the two-pose route, in
% methods.smoothed.buildActiveSuccessors. That the field is scaled by
% separatorSupportSize rather than by surfaceSupportSize is the tell, and it
% was always the honest half of the arrangement.
%
% So on a general graph this method is Slices with a truncated separator
% support, and the difference between the two robots is that truncation and
% nothing else. result.implementation says so; see implementationRecord.
if isfield(caseData, 'engine') && caseData.engine == "general" ...
        && ~isfinite(config.activeSetSize)
    % LEFT AT Inf ON PURPOSE, so the engine can size it against the matrix it
    % actually prunes. This used to be resolved here as
    % activeSetFraction * separatorSupportSize, which was the wrong width: the
    % pruned matrix has nCand = nSj * supportOverdraw columns, four times |S|
    % at the shipped overdraw, so the default 0.25 kept about a sixteenth and
    % a fraction of 1.0 still threw away three quarters. The width is not
    % knowable here -- nSj grows with separator dimension, per step -- so the
    % decision belongs in forwardEliminationGeneral and the fraction travels
    % instead of a number computed from the wrong denominator.
    config.provenance.activeSetSize = sprintf( ...
        "left Inf by runSmoothedSlicesMethod; the general engine truncates " + ...
        "to %g of the candidate separator points it actually formed", ...
        config.activeSetFraction);
end

result = methods.runInferenceCore("Smoothed Slices", caseData, config);

result.provenance = struct( ...
    'origin',      "proposed extension", ...
    'basedOn',     "Slices Perspective (Shienman et al., IROS 2024)", ...
    'newContent',  "tower-property reinterpretation; cached conditional smoothing surfaces R_r; finite-cardinality recursion with active successor sets", ...
    'notInPaper',  true, ...
    'uiNote',      "Smoothed Slices is our proposed extension, not an algorithm published by the Slices authors");
end
