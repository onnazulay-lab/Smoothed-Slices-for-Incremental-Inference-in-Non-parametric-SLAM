function root = projectRoot()
%PROJECTROOT Absolute path of the project root, derived from this file.
%
%   Inputs
%     none
%
%   Outputs
%     ROOT  the folder holding Instructions/, Literature/, src/ and results/
%
%   Utility
%     Resolve paths from this file's location, so nothing depends on the
%     current working directory.

thisFile = mfilename('fullpath');          % .../src/+utils/projectRoot
utilsDir = fileparts(thisFile);            % .../src/+utils
srcDir   = fileparts(utilsDir);            % .../src
root     = string(fileparts(srcDir));      % .../Project
end
