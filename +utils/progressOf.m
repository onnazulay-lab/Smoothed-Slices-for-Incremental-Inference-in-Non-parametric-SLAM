function p = progressOf(config)
%PROGRESSOF The reporter a config carries, or the null one.
%
%   Inputs
%     CONFIG  a method config, possibly carrying a progress reporter
%
%   Outputs
%     P       CONFIG.progress when it is a live utils.ProgressReporter, and a
%             fresh sink-less reporter otherwise
%
%   Utility
%     Let every engine call site report unconditionally.
%
%   This is what lets every engine call site report unconditionally. The
%   alternative -- guarding each report with an isfield test -- puts the same
%   four-line check at a dozen sites and leaves the engine's behaviour
%   depending on whether a UI happens to be attached, which is exactly the
%   difference a test suite cannot see.
%
%   Call it once per function, not once per loop iteration: the null object
%   is cheap to use but not free to build.

arguments
    config struct = struct()
end

if isscalar(config) && isfield(config, 'progress') && ...
        isa(config.progress, 'utils.ProgressReporter') && ...
        isscalar(config.progress) && isvalid(config.progress)
    p = config.progress;
else
    p = utils.ProgressReporter();
end
end
