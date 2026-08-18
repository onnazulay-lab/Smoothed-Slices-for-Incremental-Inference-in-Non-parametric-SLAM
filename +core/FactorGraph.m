classdef FactorGraph < handle
    %FACTORGRAPH Bipartite factor graph G = (F, Theta, E).
    %
    %   Properties
    %     Variables, Factors  Theta and F
    %     Counter             shared core.EvalCounter, or []
    %     VariableNames, NumVariables, NumFactors   dependent
    %
    %   Methods
    %     addVariable, addFactor, variable, copy, describe
    %     adjacentFactors          F_{j-1}(omega_j), Eq. (S2)
    %     separatorOf, neighbors   S_j, Eq. (S3)
    %     removeVariable           eliminate, structurally
    %     affectedVariables        variables new measurements touch
    %     validateEliminationOrder the Lemma 1 precondition
    %
    %   Utility
    %     Own every structural query about the graph, so no caller re-derives a
    %     separator and gets a different answer.
    %
    %   A handle class, so the elimination engine can mutate the reduced graph
    %   G_{j-1} -> G_j in place while COPY keeps the original G_0 intact.

    properties
        Variables (1,:) core.Variable
        Factors   (1,:) core.Factor
        Counter
    end

    properties (Dependent)
        VariableNames
        NumVariables
        NumFactors
    end

    methods
        function obj = FactorGraph(variables, factors, counter)
            %FACTORGRAPH Construct from variables and factors.
            %   Inputs   VARIABLES, FACTORS, and an optional shared COUNTER
            %   Outputs  OBJ
            %   Utility  assemble a case's graph in one call.
            arguments
                variables (1,:) core.Variable = core.Variable.empty(1,0)
                factors   (1,:) core.Factor   = core.Factor.empty(1,0)
                counter = []
            end
            obj.Variables = variables;
            obj.Factors   = factors;
            obj.Counter   = counter;
        end

        function n = get.VariableNames(obj)
            %GET.VARIABLENAMES Names of every variable, in order.
            %   Inputs   none
            %   Outputs  N, a string row, empty when the graph has none
            %   Utility  index variables by name without unpacking the objects.
            if isempty(obj.Variables)
                n = string.empty(1,0);
            else
                n = [obj.Variables.Name];
            end
        end

        function n = get.NumVariables(obj), n = numel(obj.Variables); end
        function n = get.NumFactors(obj),   n = numel(obj.Factors);   end

        function addVariable(obj, v)
            %ADDVARIABLE Append a variable.
            %   Inputs   V, a core.Variable
            %   Outputs  none; the graph is mutated in place
            %   Utility  grow the graph as a mission adds poses and landmarks.
            obj.Variables(end+1) = v;
        end

        function addFactor(obj, f)
            %ADDFACTOR Append a factor.
            %   Inputs   F, a core.Factor
            %   Outputs  none; the graph is mutated in place
            %   Utility  add a measurement, or a generated factor from a step.
            obj.Factors(end+1) = f;
        end

        function v = variable(obj, name)
            %VARIABLE The variable called NAME.
            %   Inputs   NAME
            %   Outputs  V, a core.Variable; errors when there is none
            %   Utility  reach a variable's dimension and domain by name.
            idx = find(obj.VariableNames == name, 1);
            if isempty(idx)
                error('core:FactorGraph:noSuchVariable', 'No variable named %s.', name);
            end
            v = obj.Variables(idx);
        end

        function f = adjacentFactors(obj, varName)
            %ADJACENTFACTORS F_{j-1}(omega_j): factors touching VARNAME (Eq. S2).
            %   Inputs   VARNAME
            %   Outputs  F, the factors whose scope contains it
            %   Utility  name the factors an elimination of VARNAME removes.
            if isempty(obj.Factors)
                f = core.Factor.empty(1,0);
                return
            end
            keep = arrayfun(@(x) x.involves(varName), obj.Factors);
            f = obj.Factors(keep);
        end

        function s = separatorOf(obj, varName)
            %SEPARATOROF S_j: neighbours through the removed factors (Eq. S3).
            %   Inputs   VARNAME
            %   Outputs  S, the other variables those factors reach
            %   Utility  give the scope of the factor an elimination generates.
            f = obj.adjacentFactors(varName);
            if isempty(f)
                s = string.empty(1,0);
                return
            end
            s = unique([f.Scope], 'stable');
            s(s == varName) = [];
        end

        function n = neighbors(obj, varName)
            %NEIGHBORS Alias of SEPARATOROF, for graph-language callers.
            %   Inputs   VARNAME
            %   Outputs  N, the neighbouring variables
            %   Utility  read as a graph query where that is the clearer word.
            n = obj.separatorOf(varName);
        end

        function removeVariable(obj, varName)
            %REMOVEVARIABLE Drop a variable and every factor adjacent to it.
            %   Inputs   VARNAME
            %   Outputs  none; the graph is mutated in place
            %   Utility  perform the structural half of an elimination. The
            %            generated factor is the caller's to add.
            if ~isempty(obj.Factors)
                drop = arrayfun(@(x) x.involves(varName), obj.Factors);
                obj.Factors(drop) = [];
            end
            obj.Variables(obj.VariableNames == varName) = [];
        end

        function names = affectedVariables(obj, newFactors)
            %AFFECTEDVARIABLES Variables touched by new measurements.
            %   Inputs   NEWFACTORS, a core.Factor array
            %   Outputs  NAMES, their combined scope, de-duplicated in order
            %   Utility  tell the incremental pass what an increment disturbs.
            %            Kept here so the graph owns all structural queries.
            names = string.empty(1,0);
            for i = 1:numel(newFactors)
                names = [names newFactors(i).Scope]; %#ok<AGROW>
            end
            names = unique(names, 'stable');
        end

        function g = copy(obj)
            %COPY A separate graph over the same variables and factors.
            %   Inputs   none
            %   Outputs  G, a new core.FactorGraph
            %   Utility  let the engine eliminate without consuming the caller's
            %            graph, which a handle class would otherwise do.
            g = core.FactorGraph(obj.Variables, obj.Factors, obj.Counter);
        end

        function ok = validateEliminationOrder(obj, order)
            %VALIDATEELIMINATIONORDER Check the Lemma 1 precondition.
            %   Inputs   ORDER, the proposed elimination order
            %   Outputs  OK, true; the failure path errors rather than returns
            %   Utility  reject an unusable order before the pass starts.
            %
            %   Every eliminated variable must either carry a unary factor or be
            %   connected to an already-eliminated variable. Violating this is
            %   the EliminationOrderError of Algorithm S2a, and catching it up
            %   front gives a far better message than failing mid-pass.
            arguments
                obj (1,1) core.FactorGraph
                order (1,:) string
            end

            eliminated = string.empty(1,0);
            ok = true;
            for j = 1:numel(order)
                w = order(j);
                adj = obj.adjacentFactors(w);
                hasUnary = any(arrayfun(@(f) numel(f.Scope) == 1 && f.Scope == w, adj));
                if ~hasUnary
                    nbrs = obj.separatorOf(w);
                    if ~any(ismember(nbrs, eliminated))
                        ok = false;
                        error('core:FactorGraph:eliminationOrderError', ...
                            ['Variable %s has no unary factor and no previously ' ...
                             'eliminated neighbour; Lemma 1 does not apply at step %d.'], w, j);
                    end
                end
                eliminated(end+1) = w; %#ok<AGROW>
            end
        end

        function s = describe(obj)
            %DESCRIBE One-line size summary.
            %   Inputs   none
            %   Outputs  S, a char row
            %   Utility  identify a graph in a log without printing it.
            s = sprintf('FactorGraph: |Theta| = %d, |F| = %d', ...
                obj.NumVariables, obj.NumFactors);
        end
    end
end
