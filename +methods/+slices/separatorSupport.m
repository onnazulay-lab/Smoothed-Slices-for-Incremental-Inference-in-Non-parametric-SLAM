function S = separatorSupport(graph, sepVar, config)
%SEPARATORSUPPORT The finite separator support S, with |S| = R_s.
%
%   Inputs
%     GRAPH   the factor graph, for the variable's own range
%     SEPVAR  the separator variable
%     CONFIG  carrying separatorSupportSize, or an explicit support
%
%   Outputs
%     S       the support, 1-by-R_s
%
%   Utility
%     Give every estimator the same finite support to be compared on.
%
%   Specification section 16.2 lists three admissible choices: separator
%   particles from the backward pass, a grid in low dimension, or a
%   dictionary of representative values. Iteration 1 uses the low-dimensional
%   grid, which is the only one that lets every estimator be compared on
%   identical support -- a precondition for attributing an error difference
%   to the estimator rather than to the support.

arguments
    graph (1,1) core.FactorGraph
    sepVar (1,1) string
    config (1,1) struct
end

if isfield(config, 'separatorSupport') && ~isempty(config.separatorSupport)
    S = reshape(config.separatorSupport, 1, []);
    return
end

v = graph.variable(sepVar);
S = v.grid(config.separatorSupportSize);
end
