classdef EvalCounter < handle
    %EVALCOUNTER Shared tally of scalar factor evaluations.
    %
    %   Properties
    %     Count  evaluations tallied so far, read-only from outside
    %
    %   Methods
    %     add       add N to the tally
    %     reset     set the tally back to zero
    %     snapshot  read the tally without stopping it
    %
    %   Utility
    %     Count factor evaluations for real so a cost claim can be checked
    %     instead of asserted.
    %
    %   The cost claims of Smoothed Slices are stated in factor evaluations
    %   (paper cost ~ |X_1||L_n||S_2| versus sparse RCS cost ~ |X_r||N_r||S|),
    %   and counting them is what makes test T3 meaningful rather than a
    %   restatement of the formula. A handle class, and a single counter attached
    %   to every factor of a case, so the tally is graph-wide.

    properties (SetAccess = private)
        Count (1,1) double = 0
    end

    methods
        function add(obj, n)
            %ADD Add N evaluations to the tally.
            %   Inputs   N, a count
            %   Outputs  none; COUNT rises by N
            %   Utility  let a factor report the work it just did.
            obj.Count = obj.Count + n;
        end

        function reset(obj)
            %RESET Set the tally back to zero.
            %   Inputs   none
            %   Outputs  none
            %   Utility  start a fresh measurement without rebuilding the graph.
            obj.Count = 0;
        end

        function c = snapshot(obj)
            %SNAPSHOT Read the tally.
            %   Inputs   none
            %   Outputs  C, the evaluations counted so far
            %   Utility  take a before-and-after pair around a step.
            c = obj.Count;
        end
    end
end
