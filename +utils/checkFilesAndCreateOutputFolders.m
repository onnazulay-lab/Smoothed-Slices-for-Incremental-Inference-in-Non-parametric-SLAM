function status = checkFilesAndCreateOutputFolders(status)
%CHECKFILESANDCREATEOUTPUTFOLDERS Resolve project health from a status stub.
%
%   Inputs
%     STATUS  the stub from utils.validateProjectTree
%
%   Outputs
%     STATUS  with the presence flags and createdFolders filled in
%
%   Utility
%     Fill in what the Project Health panel shows. Input folders are only
%     reported; output folders (data, results) are created when missing, as
%     specification section 2 requires.

% --- Instruction documents (authoritative implementation references) ------
n = numel(status.requiredInstructions);
instructions = struct('name', {}, 'path', {}, 'found', {}, 'bytes', {});
for i = 1:n
    name = status.requiredInstructions{i};
    p    = fullfile(status.instructionsDir, name);
    d    = dir(p);
    instructions(i).name  = name;
    instructions(i).path  = p;
    instructions(i).found = ~isempty(d);
    if isempty(d)
        instructions(i).bytes = 0;
    else
        instructions(i).bytes = d(1).bytes;
    end
end
status.instructions        = instructions;
status.missingInstructions = {instructions(~[instructions.found]).name};

% --- Literature (complementary, matched by prefix) ------------------------
literature = struct('prefix', {}, 'match', {}, 'found', {});
allPapers  = dir(fullfile(status.literatureDir, '*.pdf'));
paperNames = string({allPapers.name});
for i = 1:numel(status.expectedLiteraturePrefixes)
    prefix = status.expectedLiteraturePrefixes{i};
    hit    = paperNames(startsWith(paperNames, prefix));
    literature(i).prefix = prefix;
    literature(i).found  = ~isempty(hit);
    if isempty(hit)
        literature(i).match = '';
    else
        literature(i).match = char(hit(1));
    end
end
status.literature      = literature;
status.literatureFiles = cellstr(paperNames(:));
status.missingLiterature = {literature(~[literature.found]).prefix};

% --- Source packages ------------------------------------------------------
pkgs = struct('name', {}, 'path', {}, 'found', {});
for i = 1:numel(status.requiredSourcePackages)
    name = status.requiredSourcePackages{i};
    p    = fullfile(status.srcDir, name);
    pkgs(i).name  = name;
    pkgs(i).path  = p;
    pkgs(i).found = isfolder(p);
end
status.sourcePackages        = pkgs;
status.missingSourcePackages = {pkgs(~[pkgs.found]).name};

% --- Output folders: create if missing ------------------------------------
createdFolders = {};
for f = {'dataDir', 'resultsDir'}
    p = status.(f{1});
    if ~isfolder(p)
        mkdir(p);
        createdFolders{end+1} = p; %#ok<AGROW>
    end
end
status.createdFolders = createdFolders;

% presentation is an output area too, but it is user-curated: report only.
status.presentationPresent = isfolder(status.presentationDir);

% --- Overall verdict ------------------------------------------------------
status.instructionsOk = isempty(status.missingInstructions);
status.literatureOk   = isempty(status.missingLiterature);
status.sourceOk       = isempty(status.missingSourcePackages);
status.healthy        = status.instructionsOk && status.sourceOk;

if status.healthy && status.literatureOk
    status.summary = 'Project hierarchy complete.';
elseif status.healthy
    status.summary = sprintf('Source and instructions OK; %d literature entries missing.', ...
        numel(status.missingLiterature));
else
    status.summary = sprintf('%d instruction file(s) and %d source package(s) missing.', ...
        numel(status.missingInstructions), numel(status.missingSourcePackages));
end

status.matlabVersion = string(version('-release'));
status.checkedAt     = datetime('now');
end
