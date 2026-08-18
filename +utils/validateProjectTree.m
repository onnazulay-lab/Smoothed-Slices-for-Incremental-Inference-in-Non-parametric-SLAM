function status = validateProjectTree(projectRoot)
%VALIDATEPROJECTTREE Check the project hierarchy and create output folders.
%
%   Inputs
%     PROJECTROOT  the root to scan
%
%   Outputs
%     STATUS  which instruction documents, literature papers and source
%             folders were found, and which folders had to be created
%
%   Utility
%     Check the hierarchy specification section 2 requires, and populate the
%     Project Health panel that must be shown before any method runs.
%
%   Missing OUTPUT folders (data, results) are created; missing INPUT folders
%   are reported and never created, since inventing them would hide the
%   problem rather than surface it.
%
%   See also utils.checkFilesAndCreateOutputFolders.

arguments
    projectRoot (1,1) string = utils.projectRoot()
end

status = struct();
status.root             = char(projectRoot);
status.instructionsDir  = fullfile(status.root, 'Instructions');
status.literatureDir    = fullfile(status.root, 'Literature');
status.presentationDir  = fullfile(status.root, 'presentation');
status.dataDir          = fullfile(status.root, 'data');
status.resultsDir       = fullfile(status.root, 'results');
status.srcDir           = fullfile(status.root, 'src');

status.requiredInstructions = { ...
    'slices_perspective_exact_implementation.pdf', ...
    'nf_isam_exact_implementation.pdf', ...
    'smoothed_slices_exact_implementation.pdf', ...
    'smoothed_slices_matlab_app_spec.pdf'};

% Literature is matched by prefix because the distributed file names carry
% varying suffixes (see the '*' entries in specification section 2).
status.expectedLiteraturePrefixes = { ...
    'A Slices Perspective for Incremental Nonparametric Inference', ...
    'A_Slices_Perspective_for_Incremental_Nonparametric_Inference', ...
    'Incremental_Non-Gaussian_Inference_for_SLAM_Using_Normalizing_Flows'};

status.requiredSourcePackages = { ...
    '+core', '+datasets', '+methods', '+metrics', '+utils', '+viz'};

status = utils.checkFilesAndCreateOutputFolders(status);
end
