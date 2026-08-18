classdef Variable
    %VARIABLE A latent variable in the factor graph.
    %
    %   Properties
    %     Name    identity; two variables are equal when their names are
    %     Dim     1 for the two-pose and Four Doors cases, 2 for planar poses
    %             and landmarks
    %     Type    "pose" | "landmark" | "observation"
    %     Domain  bounded box, one [lo hi] row per dimension
    %
    %   Methods
    %     displayName   LaTeX form of the name, e.g. "x_1"
    %     grid          uniform grid, scalar variables only
    %     gridPoints    lattice over the box, any dimension
    %     randomPoints  uniform draws from the box
    %     boxWidth      per-axis extent
    %     eq            equality by name
    %
    %   Utility
    %     Identify a variable and say where it lives, so quadrature references
    %     and finite supports can be built for it.
    %
    %   Domain bounds the quadrature references and support grids. It is NOT a
    %   hard constraint on samples, which may leave it.
    %
    %   SHAPE CONVENTION, used everywhere downstream. A set of N values of a
    %   variable of dimension d is an N-by-d array: points down the rows,
    %   coordinates across the columns. A scalar variable is therefore an
    %   N-by-1 column, which is what iteration 1 already produced, so the
    %   1-D code paths are unchanged by the generalization.

    properties
        Name   (1,1) string
        Dim    (1,1) double {mustBeInteger, mustBePositive} = 1
        Type   (1,1) string {mustBeMember(Type, ["pose", "landmark", "observation"])} = "pose"
        Domain (:,2) double = [-Inf Inf]      % one [lo hi] row per dimension
    end

    methods
        function obj = Variable(name, opts)
            %VARIABLE Construct a variable.
            %   Inputs   NAME, and Dim, Type, Domain as name-value pairs
            %   Outputs  OBJ, with Domain expanded to one row per dimension
            %   Utility  build a variable and reject a domain that cannot hold
            %            it, rather than failing later inside a grid.
            arguments
                name (1,1) string
                opts.Dim (1,1) double = 1
                opts.Type (1,1) string = "pose"
                opts.Domain (:,2) double = [-Inf Inf]
            end
            obj.Name   = name;
            obj.Dim    = opts.Dim;
            obj.Type   = opts.Type;

            dom = opts.Domain;
            if size(dom, 1) == 1 && opts.Dim > 1
                % One [lo hi] row is read as a cube: the common case for a
                % square map is written once rather than repeated per axis.
                dom = repmat(dom, opts.Dim, 1);
            end
            if size(dom, 1) ~= opts.Dim
                error('core:Variable:domainDimMismatch', ...
                    'Variable %s has Dim %d but a Domain with %d row(s).', ...
                    name, opts.Dim, size(dom, 1));
            end
            if any(dom(:,2) <= dom(:,1))
                error('core:Variable:emptyDomain', ...
                    'Variable %s has a non-increasing domain row.', name);
            end
            obj.Domain = dom;
        end

        function s = displayName(obj)
            %DISPLAYNAME LaTeX form of the variable name, e.g. "x_1", "l_1".
            %   Inputs   none
            %   Outputs  S, the subscripted name
            %   Utility  label a figure in the paper's notation.
            s = regexprep(obj.Name, '^([a-zA-Z]+)(\d+)$', '$1_{$2}');
        end

        function g = grid(obj, n)
            %GRID Uniform grid over a scalar variable's domain, for quadrature.
            %   Inputs   N, points along the axis
            %   Outputs  G, a 1-by-N row
            %   Utility  build the 1-D quadrature reference.
            %
            %   A row, not a column, because that is the shape the 1-D reference
            %   paths already expect. Use GRIDPOINTS above one dimension.
            arguments
                obj (1,1) core.Variable
                n (1,1) double {mustBeInteger, mustBePositive}
            end
            if obj.Dim ~= 1
                error('core:Variable:notScalar', ...
                    ['Variable %s has dimension %d; use gridPoints to build ' ...
                     'a lattice over a vector domain.'], obj.Name, obj.Dim);
            end
            obj.assertBounded();
            g = linspace(obj.Domain(1), obj.Domain(2), n);
        end

        function [P, shape, axes_] = gridPoints(obj, n)
            %GRIDPOINTS Lattice over the full domain box as an N-by-Dim list.
            %   Inputs   N, points per axis; a scalar is used on every axis
            %   Outputs  P      prod(SHAPE)-by-Dim points, one per row
            %            SHAPE  the reshape that turns a column back into an image
            %            AXES   per-axis coordinate vectors
            %   Utility  build a reference lattice in any dimension.
            %
            %   Only ever called for Dim <= 2 in practice: a lattice is a
            %   reference tool, not an estimator.
            arguments
                obj (1,1) core.Variable
                n (1,:) double {mustBeInteger, mustBePositive}
            end
            obj.assertBounded();
            if isscalar(n), n = repmat(n, 1, obj.Dim); end
            if numel(n) ~= obj.Dim
                error('core:Variable:gridSizeMismatch', ...
                    'Variable %s has dimension %d but %d grid size(s) were given.', ...
                    obj.Name, obj.Dim, numel(n));
            end

            axes_ = cell(1, obj.Dim);
            for d = 1:obj.Dim
                axes_{d} = linspace(obj.Domain(d,1), obj.Domain(d,2), n(d));
            end
            if obj.Dim == 1
                P = axes_{1}(:);
            else
                out = cell(1, obj.Dim);
                [out{:}] = ndgrid(axes_{:});
                P = zeros(numel(out{1}), obj.Dim);
                for d = 1:obj.Dim
                    P(:,d) = out{d}(:);
                end
            end
            shape = n;
        end

        function P = randomPoints(obj, n)
            %RANDOMPOINTS N uniform draws from the domain box.
            %   Inputs   N, number of points
            %   Outputs  P, N-by-Dim
            %   Utility  seed a support where no proposal is available yet.
            obj.assertBounded();
            lo = obj.Domain(:,1).';
            hi = obj.Domain(:,2).';
            P  = lo + rand(n, obj.Dim) .* (hi - lo);
        end

        function w = boxWidth(obj)
            %BOXWIDTH Per-axis extent of the domain.
            %   Inputs   none
            %   Outputs  W, a 1-by-Dim row
            %   Utility  give a length scale for tolerances and plot limits.
            w = obj.Domain(:,2).' - obj.Domain(:,1).';
        end

        function tf = eq(a, b)
            %EQ Equality by name.
            %   Inputs   A, B, variables
            %   Outputs  TF, logical
            %   Utility  identity is the name, so two objects describing the
            %            same variable compare equal whatever else differs.
            tf = string(a.Name) == string(b.Name);
        end
    end

    methods (Access = private)
        function assertBounded(obj)
            %ASSERTBOUNDED Refuse an infinite domain.
            %   Inputs   none
            %   Outputs  none; errors when any bound is not finite
            %   Utility  a grid over an unbounded box is not a grid, and the
            %            failure is clearer here than as NaNs downstream.
            if any(~isfinite(obj.Domain(:)))
                error('core:Variable:unboundedDomain', ...
                    'Variable %s has an unbounded domain; set Domain before gridding.', ...
                    obj.Name);
            end
        end
    end
end
