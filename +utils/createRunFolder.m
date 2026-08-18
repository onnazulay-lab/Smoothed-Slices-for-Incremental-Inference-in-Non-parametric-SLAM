function runDir = createRunFolder(projectRoot, config)
%CREATERUNFOLDER Create results/run_YYYYMMDD_HHMMSS_methodCompare.
%
%   Inputs
%     PROJECTROOT  where results/ lives           default utils.projectRoot()
%     CONFIG       the config to write alongside          default struct()
%
%   Outputs
%     RUNDIR       the created folder
%
%   Utility
%     Create the run folder mandated by specification section 2, with its
%     figures/ and animation/ subfolders, and write the config into it so the
%     run is self-describing.

arguments
    projectRoot (1,1) string = utils.projectRoot()
    config struct = struct()
end

stamp  = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
runDir = fullfile(char(projectRoot), 'results', ['run_' stamp '_methodCompare']);

% Guard against two runs starting inside the same second.
suffix = 0;
base   = runDir;
while isfolder(runDir)
    suffix = suffix + 1;
    runDir = sprintf('%s_%02d', base, suffix);
end

mkdir(runDir);
mkdir(fullfile(runDir, 'figures'));
mkdir(fullfile(runDir, 'animation'));

if ~isempty(fieldnames(config))
    utils.writeJSON(fullfile(runDir, 'config.json'), config);
end
end
