function app = runSmoothedSlicesApp()
%RUNSMOOTHEDSLICESAPP Launch the comparative posterior-recovery demonstrator.
%
%   Inputs
%     none
%
%   Outputs
%     APP  the SmoothedSlicesAppProgrammatic, already open
%
%   Utility
%     Put src/ on the path and open the app. Run it from anywhere: the path is
%     resolved from this file's location, so the working directory does not
%     matter.

thisDir = fileparts(mfilename('fullpath'));
if ~contains(path, thisDir)
    addpath(thisDir);
end

app = SmoothedSlicesAppProgrammatic();
end
