function reg = figureRegistryFor(methodName)
%FIGUREREGISTRYFOR Names of the figures a method contributes to the export.
%
%   Inputs
%     METHODNAME  which method
%
%   Outputs
%     REG         the figure names it contributes
%
%   Utility
%     Supply the per-method half of the figure registry; the app owns the
%     handles.
%
%   Specification section 21 requires every axes to be registered once, and
%   section 14 requires the exporter to write only registered axes so that no
%   figure is silently forgotten. This is the per-method half of that
%   registry; the app owns the handles.

arguments
    methodName (1,1) string
end

common = ["posterior_samples_compare", "marginal_x_compare", ...
          "estimator_vs_reference", "runtime_per_increment", ...
          "cardinality_diagnostics"];

switch methodName
    case "Slices"
        specific = ["slices_factor_graph_step", "slices_nested_samples"];
    case "Smoothed Slices"
        specific = ["smoothed_surface_step", "smoothed_active_set"];
    case "NF-iSAM"
        specific = "nfisam_bayes_tree_step";
    otherwise
        specific = string.empty(1,0);
end

reg = struct('names', [common specific], 'method', methodName);
end
