classdef BayesNet
    %BAYESNET Ordered list of conditionals produced by the forward pass.
    %
    %   Properties
    %     Conditionals  the factors, in elimination order
    %     Order         their frontal variables, in the same order
    %
    %   Methods
    %     appendConditional     add one conditional and extend the order
    %     conditionalFor        look one up by frontal variable
    %     factorizationString   plain-text factorization
    %     latex                 the same, for a figure
    %     count                 number of conditionals
    %
    %   Utility
    %     Hold the factorization the forward pass produced, in the order it
    %     produced it, so it can be compared against the one the spec requires.
    %
    %   For the two-pose range benchmark with order (x1, l1, x2) the result must
    %   read P(x1 | l1, x2) P(l1 | x2) P(x2), which is the forward-exactness test
    %   of the Slices spec (section 11).

    properties
        Conditionals (1,:) core.ConditionalFactor
        Order        (1,:) string
    end

    methods
        function obj = BayesNet()
            %BAYESNET Construct an empty net.
            %   Inputs   none
            %   Outputs  OBJ with no conditionals
            %   Utility  start a net the forward pass appends to.
            obj.Conditionals = core.ConditionalFactor.empty(1,0);
            obj.Order        = string.empty(1,0);
        end

        function obj = appendConditional(obj, c)
            %APPENDCONDITIONAL Add one conditional and extend the order.
            %   Inputs   C, a core.ConditionalFactor
            %   Outputs  OBJ with C appended
            %   Utility  keep Conditionals and Order in step, so the order is
            %            never assembled separately and allowed to disagree.
            obj.Conditionals(end+1) = c;
            obj.Order(end+1)        = c.Frontal;
        end

        function c = conditionalFor(obj, varName)
            %CONDITIONALFOR The conditional whose frontal variable is VARNAME.
            %   Inputs   VARNAME, a variable name
            %   Outputs  C, the conditional; errors when there is none
            %   Utility  let the backward pass fetch the step it needs by name
            %            rather than by position.
            idx = find([obj.Conditionals.Frontal] == varName, 1);
            if isempty(idx)
                error('core:BayesNet:noConditional', ...
                    'No conditional for %s in the Bayes net.', varName);
            end
            c = obj.Conditionals(idx);
        end

        function s = factorizationString(obj)
            %FACTORIZATIONSTRING Plain-text factorization, for tests and logs.
            %   Inputs   none
            %   Outputs  S, e.g. "P(x1|l1,x2) P(l1|x2) P(x2)"
            %   Utility  make the factorization comparable against the one the
            %            spec writes down, as a string rather than by eye.
            parts = strings(1, numel(obj.Conditionals));
            for i = 1:numel(obj.Conditionals)
                c = obj.Conditionals(i);
                if isempty(c.Separator)
                    parts(i) = sprintf('P(%s)', c.Frontal);
                else
                    parts(i) = sprintf('P(%s|%s)', c.Frontal, ...
                        strjoin(cellstr(c.Separator), ','));
                end
            end
            s = strjoin(parts, ' ');
        end

        function s = latex(obj)
            %LATEX The factorization as one LaTeX math string.
            %   Inputs   none
            %   Outputs  S, a char row including the enclosing dollar signs
            %   Utility  put the factorization in a figure title.

            % c.latex() returns char, so it must be wrapped in string before
            % arrayfun can produce a uniform result.
            parts = arrayfun(@(c) erase(string(c.latex()), "$"), ...
                obj.Conditionals, 'UniformOutput', true);
            % join, not strjoin: strjoin unescapes its delimiter and would
            % turn the LaTeX thin space \, into a bare comma.
            s = char("$" + join(parts, "\,") + "$");
        end

        function n = count(obj)
            %COUNT Number of conditionals.
            %   Inputs   none
            %   Outputs  N
            %   Utility  report the size without overloading numel, which MATLAB
            %            uses internally for object indexing.
            n = numel(obj.Conditionals);
        end
    end
end
