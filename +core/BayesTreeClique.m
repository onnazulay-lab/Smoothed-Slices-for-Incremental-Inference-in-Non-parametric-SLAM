classdef BayesTreeClique
    %BAYESTREECLIQUE One clique of a Bayes tree.
    %
    %   Properties
    %     Index      position in the tree's clique array
    %     Frontal    F_C, in elimination order
    %     Separator  S_C, the intersection with the parent, empty at the root
    %     Factors    z_C, the graph factors consumed here
    %     Parent     index of the parent, 0 at the root
    %     Children   indices of the children
    %
    %   Methods
    %     variables  F_C followed by S_C
    %     isRoot, isLeaf
    %     label      "x2 x3 : x4", frontals, colon, separator
    %
    %   Utility
    %     Carry one clique's structure, so a tree can be built and drawn without
    %     anything being trained.
    %
    %   Eq. N1 is the reason the object exists:
    %
    %       p(Theta | z) = prod_C p(F_C | S_C, z_C)
    %
    %   so every clique is one factor of the posterior and, later, one
    %   normalizing flow. Nothing here evaluates or trains anything: a clique
    %   is structure, exactly as a Bayes net conditional is structure in
    %   core.eliminationSchedule. That separation is what lets the app draw a
    %   tree for a freshly loaded case with no run behind it.
    %
    %   A value class, like core.Factor and core.SliceConditional. The tree
    %   that owns these is a plain struct from core.bayesTree.

    properties
        Index     (1,1) double = 0                     % position in the tree's clique array
        Frontal   (1,:) string = string.empty(1,0)     % F_C, in elimination order
        Separator (1,:) string = string.empty(1,0)     % S_C, empty at the root
        Factors   (1,:) string = string.empty(1,0)     % z_C, graph factors consumed here
        Parent    (1,1) double = 0                     % 0 at the root
        Children  (1,:) double = zeros(1,0)
    end

    methods
        function obj = BayesTreeClique(varargin)
            %BAYESTREECLIQUE Construct from name-value pairs.
            %   Inputs   VARARGIN, property name and value pairs
            %   Outputs  OBJ
            %   Utility  build a clique field by field as the tree is assembled.
            if nargin == 0, return, end
            for i = 1:2:numel(varargin)
                obj.(varargin{i}) = varargin{i+1};
            end
        end

        function v = variables(obj)
            %VARIABLES The clique itself: F_C followed by S_C.
            %   Inputs   none
            %   Outputs  V, the variable names
            %   Utility  give the full scope of the clique's conditional.
            v = [obj.Frontal obj.Separator];
        end

        function tf = isRoot(obj)
            %ISROOT True when this clique has no parent.
            %   Inputs   none
            %   Outputs  TF, logical
            %   Utility  the root's conditional is a marginal, S_C being empty.
            tf = obj.Parent == 0;
        end

        function tf = isLeaf(obj)
            %ISLEAF True when this clique has no children.
            %   Inputs   none
            %   Outputs  TF, logical
            %   Utility  a leaf's z_C is its own factors and nothing below.
            tf = isempty(obj.Children);
        end

        function s = label(obj)
            %LABEL "x2 x3 : x4" -- frontals, colon, separator.
            %   Inputs   none
            %   Outputs  S, a string
            %   Utility  name the clique the way the NF-iSAM paper draws it.
            s = strjoin(obj.Frontal, " ");
            if ~isempty(obj.Separator)
                s = s + " : " + strjoin(obj.Separator, " ");
            end
        end
    end
end
