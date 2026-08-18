function [results, summary] = runComparison(caseData, config, whichMethods)
%RUNCOMPARISON Run the selected methods on one case and score them.
%
%   Inputs
%     CASEDATA      the case
%     CONFIG        the method config, handed to every method unchanged
%     WHICHMETHODS  which to run                        default all three
%
%   Outputs
%     RESULTS  a harmonized struct array, one element per method
%     SUMMARY  the reference, the per-method errors and the metrics table
%
%   Utility
%     Run the methods on the SAME case, with the SAME config and the SAME
%     seed, which is what specification section 1 means by a comparative run.
%
%   Scoring is against the quadrature reference, not against each other. Two
%   methods that agree can still both be wrong, and on the two-pose range
%   benchmark there is no reason to accept that risk when ground truth is
%   computable.

arguments
    caseData (1,1) struct
    config (1,1) struct = methods.commonMethodConfig()
    whichMethods (1,:) string = ["Slices", "NF-iSAM", "Smoothed Slices"]
end

% --- Reference ------------------------------------------------------------
% Each case brings the strongest ground truth it admits, and says which:
%
%   two-pose    dense quadrature, cross-checked against a closed form
%   Four Doors  exact discrete forward-backward on the chain
%   grid world  none. A planar SLAM posterior over eighteen variables has no
%               tractable exact answer, so the methods are scored against the
%               known TRUE poses and landmarks, and the engine's own health
%               diagnostics carry the weight that a reference otherwise
%               would. Reporting an RMSE here without saying that would
%               imply a certainty that does not exist.
p = utils.progressOf(config);
p.report(0, "building the reference");

ref = struct('kind', "none");

switch localReferenceKind(caseData)
    case "quadrature"
        ref = datasets.referenceTwoPoseQuadrature(caseData, ...
                  'NumX2', config.separatorSupportSize);
        ref.kind = "quadrature";
        % Every method is evaluated on the reference's own support, so no
        % interpolation stands between an estimate and the truth.
        config.separatorSupport = ref.x2;

    case "chainExact"
        ref = datasets.referenceFourDoorsGrid(caseData);
        ref.kind = "chainExact";

    case "truthOnly"
        ref.kind = "truthOnly";
        ref.note = "no tractable exact posterior; scored against known truth";
        ref.groundTruth = caseData.groundTruth;
end

% --- Run ------------------------------------------------------------------
% The methods get equal shares of the bar between the reference and the
% scoring. Equal is a lie -- on the two-pose benchmark with the shipped
% budgets NF-iSAM takes roughly twice what Smoothed Slices does -- but it is
% an honest lie: weighting the shares by measured runtimes would make the
% bar's pace depend on the case, the budgets and the hardware, and a bar
% that predicts wrongly is worse than one that is only ever ordinal.
nM  = numel(whichMethods);
raw = {};
cancelledFrom = 0;

for i = 1:nM
    m = whichMethods(i);
    pm = p.sub(0.05 + 0.90 * (i-1)/nM, 0.05 + 0.90 * i/nM);

    try
        % INSIDE the try, and it has to be. report() is where a pending Stop
        % is noticed, so this announcement is itself a cancellation point --
        % and it was the one point in the run where Stop was not survivable.
        % Cancelling as method i announced itself threw from outside the
        % handler, unwound past every method that had already FINISHED, and
        % the sweep above caught it and kept nothing. Press Stop while
        % Smoothed Slices was starting and you lost the Slices result that
        % was already sitting in raw{1}, complete and scored.
        pm.report(0, sprintf("running %s (%d of %d)", m, i, nM));

        switch m
            case "Slices"
                raw{end+1} = methods.runSlicesMethod(caseData, localWith(config, pm)); %#ok<AGROW>
            case "Smoothed Slices"
                raw{end+1} = methods.runSmoothedSlicesMethod(caseData, localWith(config, pm)); %#ok<AGROW>
            case "NF-iSAM"
                raw{end+1} = methods.runNFISAMMethod(caseData, localWith(config, pm)); %#ok<AGROW>
            otherwise
                error('methods:runComparison:unknownMethod', 'Unknown method "%s".', m);
        end
        % Sampled here because it can only be sampled here: it is a reading of
        % the process at the instant a method returned. utils.processMemoryBytes
        % says at length what it is and is not.
        raw{end}.metrics.processMemoryAfter = utils.processMemoryBytes();
    catch err
        if ~utils.ProgressReporter.isCancellation(err), rethrow(err), end
        % Stop keeps what finished. The method that was interrupted and the
        % ones that never started are all reported as cancelled rather than
        % silently absent, so the table has the same number of rows either way
        % and nobody has to notice a method is missing.
        cancelledFrom = i;
        break
    end
end

if cancelledFrom > 0
    for i = cancelledFrom:nM
        note = "cancelled before this method started";
        if i == cancelledFrom
            note = "cancelled while this method was running; no partial " + ...
                   "posterior is reported because a half-finished elimination " + ...
                   "is not a posterior";
        end
        raw{end+1} = methods.cancelledResult(whichMethods(i), caseData, config, note); %#ok<AGROW>
    end
end

% --- Score ----------------------------------------------------------------
% Deliberately not cancellable. Scoring is seconds against a run of minutes,
% and a Stop landing here would throw away the results it was pressed to
% preserve. Both scorers return untouched for a status that is not "ok", so
% the cancelled stubs pass through.
%
% A STOPPED RUN'S BAR DOES NOT MOVE AGAIN. Announcing 95% here after a Stop
% would walk the bar most of the way to full while the run wound down, which
% reads as a run that nearly finished. It is held at wherever the cancellation
% landed instead, and the message says what happened.
%
% Captured here rather than read again at the end, so that the bar's resting
% place is decided at the moment the run stopped. Nothing between the two
% points moves it today; reading it again would make that an assumption the
% next edit to the scoring pass could silently break.
heldAt = p.Fraction;
if cancelledFrom == 0
    p.announce(0.95, "scoring against the reference");
end
for i = 1:numel(raw)
    switch ref.kind
        case "quadrature"
            raw{i} = methods.scoreAgainstReference(raw{i}, ref, config);
        case "chainExact"
            raw{i} = methods.scoreAgainstChainReference(raw{i}, ref, caseData);
        otherwise
            % Nothing to add: runGeneralCore already scored against the
            % known truth and attached its health warnings.
    end
end

results = methods.harmonizeResults(raw);

summary = struct();
summary.reference    = ref;
summary.referenceKind = ref.kind;
summary.case         = caseData.name;
summary.config       = utils.serializableConfig(config);
summary.metricsTable = utils.metricsTable(results);
summary.methods      = whichMethods;
summary.cancelled    = cancelledFrom > 0;
summary.numCompleted = sum(arrayfun(@(r) r.status == "ok", results));
summary.ranAt        = datetime('now');

if summary.cancelled
    % The bar is left where it stopped rather than driven to full. A cancelled
    % run is over, but a full bar reads as a finished one, and the message
    % underneath it is not what a glance takes in first.
    p.announce(heldAt, sprintf("cancelled: %d of %d method(s) completed", ...
        summary.numCompleted, nM));
else
    p.announce(1, sprintf("done: %d of %d method(s) completed", ...
        summary.numCompleted, nM));
end
end

% =========================================================================
function config = localWith(config, p)
%LOCALWITH A copy of the config carrying one method's sub-reporter.
%   Inputs   CONFIG the base, P the sub-reporter
%   Outputs  CONFIG, the copy
%   Utility  each method reports its own 0..1 into its share of the run's bar,
%           without mutating the struct the others receive.
config.progress = p;
end

% =========================================================================
function kind = localReferenceKind(caseData)
%LOCALREFERENCEKIND Which exact reference, if any, this case admits.
%   Inputs   CASEDATA, the case
%   Outputs  KIND, the reference to score against, or "none"
%   Utility  three of the four cases have no exact posterior, and scoring them
%           against one another would let two methods be wrong together.
%
%   A case may SAY which it is. The field-sniffing below is how the first
%   three cases were told apart, and it works only because each happens to
%   carry a field the others do not. A fourth case with neither `doors` nor
%   `map` falls through to quadrature -- which does not fail, it silently
%   scores against a reference built for the two-pose benchmark. So a case
%   that states its kind is believed, and the sniffing is the fallback for
%   the three that predate the field.
if isfield(caseData, 'referenceKind') && strlength(caseData.referenceKind) > 0
    kind = string(caseData.referenceKind);
elseif isfield(caseData, 'doors')
    kind = "chainExact";
elseif isfield(caseData, 'map')
    kind = "truthOnly";
else
    kind = "quadrature";
end
end
