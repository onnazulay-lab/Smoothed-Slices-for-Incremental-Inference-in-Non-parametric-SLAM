function info = setRandomSeed(seed, generator)
%SETRANDOMSEED Set a reproducible RNG state and describe it for the run log.
%
%   Inputs
%     SEED       the seed                                        default 0
%     GENERATOR  the generator name                    default "twister"
%
%   Outputs
%     INFO  struct recording the seed, generator, MATLAB release and the time
%           it was set
%
%   Utility
%     Seed the global stream AND record exactly what was set, so the saved
%     configuration satisfies the acceptance checklist's reproducibility
%     requirement rather than merely claiming to.

arguments
    seed (1,1) double {mustBeInteger, mustBeNonnegative} = 0
    generator (1,1) string = "twister"
end

rng(seed, char(generator));
s = rng();

info = struct( ...
    'seed',          seed, ...
    'generator',     string(s.Type), ...
    'matlabVersion', string(version('-release')), ...
    'setAt',         datetime('now'));
end
