classdef EliminationState
    %ELIMINATIONSTATE Record of one forward-pass elimination step.
    %
    %   Properties
    %     Step, EliminatedVar        j and omega_j
    %     RemovedFactors, Separator  F_{j-1}(omega_j) and S_j
    %     LocalDataNames             D_j, by factor name
    %     LocalDataIsApproximate     which of them are generated
    %     SamplingFactorName, SamplingRoute
    %     NewFactor, Conditional     f_new_hat and the conditional
    %     Timing, Diagnostics
    %
    %   Methods
    %     recordLocalData      capture D_j from the factors actually removed
    %     usesApproximateData  true when D_j contains a generated factor
    %     describe             one printable line for this step
    %
    %   Utility
    %     Keep what one elimination step did, so the bookkeeping can be checked
    %     afterwards rather than trusted at the time.
    %
    %   D_j is the field that guards the "Wrong D_j bookkeeping" failure mode of
    %   the Smoothed Slices spec (section 18): after the first elimination D_j is
    %   NOT the raw measurement set, it is {f_new_hat from the previous step, new
    %   measurements}. Storing the references explicitly makes it impossible to
    %   silently regress to raw factors at the second elimination.

    properties
        Step            (1,1) double
        EliminatedVar   (1,1) string
        RemovedFactors  (1,:) core.Factor
        Separator       (1,:) string
        LocalDataNames  (1,:) string      % D_j, by factor name
        LocalDataIsApproximate (1,:) logical
        SamplingFactorName (1,1) string
        SamplingRoute   (1,1) string = "unary"   % "unary" | "lemma1"
        NewFactor       % core.ApproximateFactor
        Conditional     % core.ConditionalFactor
        Timing          struct = struct()
        Diagnostics     struct = struct()
    end

    methods
        function obj = EliminationState(step, eliminatedVar)
            %ELIMINATIONSTATE Construct the record for step STEP.
            %   Inputs   STEP the index j, ELIMINATEDVAR the name omega_j
            %   Outputs  OBJ, with the remaining fields left to be filled in
            %   Utility  start a record the forward pass fills as it goes.
            arguments
                step (1,1) double = 0
                eliminatedVar (1,1) string = ""
            end
            obj.Step          = step;
            obj.EliminatedVar = eliminatedVar;
        end

        function obj = recordLocalData(obj, removedFactors)
            %RECORDLOCALDATA Capture D_j from the factors actually removed.
            %   Inputs   REMOVEDFACTORS, the factors this step took out
            %   Outputs  OBJ with RemovedFactors, LocalDataNames and
            %            LocalDataIsApproximate set
            %   Utility  record D_j from what happened rather than from what was
            %            expected to happen.
            obj.RemovedFactors = removedFactors;
            if isempty(removedFactors)
                obj.LocalDataNames = string.empty(1,0);
                obj.LocalDataIsApproximate = false(1,0);
                return
            end
            obj.LocalDataNames = [removedFactors.Name];
            obj.LocalDataIsApproximate = arrayfun( ...
                @(f) f.Kind == "approximate", removedFactors);
        end

        function tf = usesApproximateData(obj)
            %USESAPPROXIMATEDATA True when D_j contains a generated factor.
            %   Inputs   none
            %   Outputs  TF, logical
            %   Utility  flag a step whose input is already an approximation, so
            %            error accumulation is visible.
            tf = any(obj.LocalDataIsApproximate);
        end

        function s = describe(obj)
            %DESCRIBE One printable line summarizing this step.
            %   Inputs   none
            %   Outputs  S, a char row
            %   Utility  put the step in a log in the paper's own notation.
            s = sprintf('step %d: eliminate %s, S_%d = {%s}, D_%d = {%s}%s', ...
                obj.Step, obj.EliminatedVar, obj.Step, ...
                strjoin(cellstr(obj.Separator), ','), obj.Step, ...
                strjoin(cellstr(obj.LocalDataNames), ', '), ...
                localApproxTag(obj.usesApproximateData()));
        end
    end
end

function t = localApproxTag(tf)
%LOCALAPPROXTAG The bracketed note appended when D_j is approximate.
%   Inputs   TF, logical
%   Outputs  T, the tag or an empty char
%   Utility  keep DESCRIBE's format string readable.
if tf
    t = '  [contains approximate factor]';
else
    t = '';
end
end
