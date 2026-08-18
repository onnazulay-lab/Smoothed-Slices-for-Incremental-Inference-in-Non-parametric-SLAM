function txt = createdFolderText(status)
%CREATEDFOLDERTEXT One line naming the output folders created this session.
%
%   Inputs
%     STATUS  from utils.checkFilesAndCreateOutputFolders
%
%   Outputs
%     TXT     one line for the Reproducibility tab; "none" when nothing was
%             created, because a blank field next to a label reads as a
%             rendering failure
%
%   Utility
%     Report what had to be created, testably.
%
%   This lives outside the app class so the fresh-clone case can be tested
%   without building a figure: on a clone, results/ and data/ do not exist
%   (their contents are gitignored), so checkFilesAndCreateOutputFolders
%   creates them and STATUS.createdFolders is non-empty -- the one branch
%   that otherwise runs only on someone else's machine. Its predecessor,
%   utils.healthText, crashed on exactly that branch.
%
%   The empty case says "none" rather than returning an empty string: a
%   blank field next to a label reads as a rendering failure, and the
%   distinction between "nothing was created" and "the label did not draw"
%   is the whole reason the row is on the tab.

arguments
    status (1,1) struct
end

if isempty(status.createdFolders)
    txt = "none (all output folders already existed)";
    return
end

% string(), not sprintf() alone: sprintf returns a char row vector, and
% char + char is numeric addition with implicit expansion rather than
% concatenation, which is what broke healthText whenever the two pieces
% differed in length -- that is, every time.
folders = cellstr(string(status.createdFolders));
folders = cellfun(@(p) strrep(p, '\', '/'), folders, 'UniformOutput', false);
txt = "created: " + string(strjoin(folders, ', '));
end
