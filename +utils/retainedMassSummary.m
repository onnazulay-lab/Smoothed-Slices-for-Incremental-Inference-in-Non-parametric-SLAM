function s = retainedMassSummary(retained, opts)
%RETAINEDMASSSUMMARY What a sparsification kept, summarized the same way everywhere.
%   S = RETAINEDMASSSUMMARY(RETAINED) takes a per-row kept-mass fraction -- one
%   entry per row of whatever matrix was sparsified, each the share of that
%   row's total weight that survived -- and returns the mean, median and
%   minimum, plus a warning string when the minimum is low enough that the
%   answer has measurably moved.
%
%   Inputs
%     RETAINED       column of fractions in [0, 1], one per row. A dense or
%                    untruncated update passes ones.
%     MinThreshold   minimum below which the warning fires.   default 0.75
%     IndexedOver    what the dropped entries WERE.   default "successors"
%     Renormalized   whether the kept row was rescaled to its former total
%     IsEq49         whether this really is the spec's Eq. (49)/(50)
%
%   Outputs  S with fields
%     retainedMass         the input vector, unchanged
%     retainedMassMean     mean over rows
%     retainedMassMedian   median over rows -- the one to read when a handful
%                          of rows are far worse than the rest
%     retainedMassMin      minimum over rows
%     rowsBelowThreshold   how many rows fall under MinThreshold
%     fractionBelow        that count over the number of rows
%     minThreshold         the threshold used, carried so a reader of an
%                          export can see which number produced the warning
%     indexedOver          "successors" | "separatorPoints"
%     renormalized         logical
%     isEq49               logical
%     warning              "" when nothing is wrong, else one sentence
%
%   Utility
%     Give the project one summary of "how much did the sparsification throw
%     away", with identical field names wherever it is reported, while still
%     recording that the two places it is reported from are not measuring the
%     same thing.
%
%   THE TWO ROUTES ARE NOT THE SAME APPROXIMATION, AND THIS IS WHY THE EXTRA
%   FIELDS EXIST. Both used to report a field called retainedMass and both
%   claimed Eq. (49) in their headers. They differ on two axes:
%
%     methods.smoothed.buildActiveSuccessors -- the real Eq. (49)/(50). W is
%     |X_r| x |X_{r+1}| and the dropped entries are SUCCESSOR path points b.
%     Rows are renormalized over the active set (spec section 11.1, bullet 2),
%     so no mass is lost and the retained fraction is a diagnostic of how
%     coarse the surface has become.
%
%     forwardEliminationGeneral's separator-support truncation -- NOT Eq. (49).
%     The matrix it prunes is |X_0| x |candidate separator points| and the
%     dropped entries are SEPARATOR points rho, which Eq. (49) does not index
%     over at all. Rows are not renormalized, which section 11.1 permits
%     ("unless the unnormalized form is intended"), so the dropped mass is
%     really gone: f_new(s) becomes exactly zero at any separator point no
%     outer sample ranked in its top K. That truncates the support of the
%     answer rather than coarsening a surface.
%
%   So a reader comparing two retained-mass numbers across routes is comparing
%   different quantities, and indexedOver/renormalized/isEq49 are what let them
%   notice. The alternative -- one number, two meanings -- is what this item
%   was raised to fix, and renaming one of them to hide the collision would
%   have kept the collision and lost the comparison.
%
%   AND THE THRESHOLD BELOW WAS MEASURED ON ONE OF THEM ONLY. The sweep is on
%   the two-pose route, where the dropped entries are successors. It does not
%   transfer to the separator-truncation route unqualified, because there a low
%   retained fraction means part of the separator support has been zeroed
%   rather than that a surface is coarse, and nothing has measured what that
%   costs. The warning still fires there -- a run that has zeroed most of a row
%   deserves saying so -- but it names indexedOver, so the sentence cannot be
%   read as a claim that this route was the one characterized.
%
%   WHERE 0.75 COMES FROM, AND WHY IT IS A BRACKET RATHER THAN A PREFERENCE.
%   research.activeSetProfile sweeps K on the multimodal two-pose case at
%   |X_1| = 120 and scores every run against the dense Eq. (48) surface and
%   against quadrature. Measured, with the dense run's own posterior error as
%   the floor (0.0760):
%
%     K     min retained    surface err    posterior err    x floor
%     48        0.831           0.064          0.069          0.91
%     32        0.646           0.114          0.084          1.10
%     24        0.524           0.152          0.106          1.39
%      8        0.213           0.271          0.154          2.03
%      2        0.058           0.408          0.183          2.40
%
%   K = 48 is the smallest active set whose posterior error is still inside
%   the dense band; at K = 32 it clears the floor for the first time and then
%   climbs monotonically. So the boundary lies in (0.646, 0.831) and 0.75 is
%   inside it, on neither edge. A reader who wants a different number has the
%   whole curve to argue from without rerunning anything.
%
%   AND THE WARNING FOLLOWS THE POSTERIOR, NOT THE SURFACE. At K = 48 the
%   surface has already moved 6.4 per cent while the answer has not moved at
%   all, so a warning keyed to surface fidelity would fire on runs that are
%   fine. This one fires when the answer is affected. The consequence is
%   deliberate and has to be stated rather than hidden: a run that draws no
%   warning may still have a visibly different surface, which is why the
%   surface error is reported separately and not folded in here.
%
%   THE MINIMUM IS THE TRIGGER, NOT THE MEAN. The mean hides the case this
%   diagnostic exists for -- most rows keeping nearly everything while a few
%   keep almost nothing -- and those few rows are outer samples whose
%   contribution to f_new has been mostly discarded. The median is reported
%   beside the mean for the same reason: when the two disagree, the
%   distribution is skewed and the mean is the misleading one.
%
%   See also research.activeSetProfile, methods.smoothed.buildActiveSuccessors.

arguments
    retained (:,1) double {mustBeNonnegative}
    opts.MinThreshold (1,1) double {mustBeInRange(opts.MinThreshold, 0, 1)} = 0.75
    opts.IndexedOver (1,1) string ...
        {mustBeMember(opts.IndexedOver, ["successors", "separatorPoints"])} = "successors"
    opts.Renormalized (1,1) logical = true
    opts.IsEq49 (1,1) logical = true
end

s = struct();
s.retainedMass = retained;
s.minThreshold = opts.MinThreshold;
s.indexedOver  = opts.IndexedOver;
s.renormalized = opts.Renormalized;
s.isEq49       = opts.IsEq49;

if isempty(retained)
    % No rows is not the same as no loss, and reporting 1 here would claim a
    % dense update ran. NaN says "nothing was measured" and the warning says
    % why, so an empty transition cannot be read as a clean one.
    s.retainedMassMean   = NaN;
    s.retainedMassMedian = NaN;
    s.retainedMassMin    = NaN;
    s.rowsBelowThreshold = 0;
    s.fractionBelow      = NaN;
    s.warning = "The active set summary had no rows to summarize, so " + ...
        "retained mass is unmeasured rather than complete.";
    return
end

s.retainedMassMean   = mean(retained);
s.retainedMassMedian = median(retained);
s.retainedMassMin    = min(retained);

below = retained < opts.MinThreshold;
s.rowsBelowThreshold = sum(below);
s.fractionBelow      = s.rowsBelowThreshold / numel(retained);

if s.retainedMassMin >= opts.MinThreshold
    s.warning = "";
    return
end

% The sentence names what was dropped, because the consequence differs. On the
% successor route the measured sweep says the posterior has moved off the dense
% floor. On the separator route nothing has been measured, and saying so is
% more useful than borrowing a number from a case this one is not.
if opts.IndexedOver == "successors"
    consequence = ['On the measured two-pose sweep a minimum this low moved ' ...
        'the posterior off the dense floor rather than only coarsening the ' ...
        'surface, so the answer is affected and not merely approximate.'];
else
    consequence = ['These are separator support points and not the ' ...
        'successors of Eq. (49), and the rows are not renormalized, so ' ...
        'f_new is exactly zero wherever the truncation bit. The two-pose ' ...
        'sweep does not characterize this route, so the size of the error ' ...
        'here is unmeasured rather than known to be small.'];
end

s.warning = sprintf([ ...
    'The sparsification discarded most of the mass on %d of %d row(s), ' ...
    'indexed over %s: minimum retained mass %.3f, median %.3f, against a ' ...
    'threshold of %.2f. %s'], ...
    s.rowsBelowThreshold, numel(retained), s.indexedOver, s.retainedMassMin, ...
    s.retainedMassMedian, opts.MinThreshold, consequence);
end
