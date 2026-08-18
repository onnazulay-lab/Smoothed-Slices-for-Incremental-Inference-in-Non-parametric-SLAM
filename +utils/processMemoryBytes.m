function b = processMemoryBytes()
%PROCESSMEMORYBYTES What MATLAB's process is holding right now, or NaN.
%
%   Inputs
%     none
%
%   Outputs
%     B  MemUsedMATLAB from the MEMORY function, or NaN off Windows
%
%   Utility
%     Report a memory reading, with its limits stated so it is not mistaken
%     for a method's memory use.
%
%   READ THIS BEFORE REPORTING IT AS A METHOD'S MEMORY, because it is not.
%   It is a reading of the whole MATLAB process at one instant, taken after a
%   method returned. It includes everything else the session is holding, it
%   does not fall when a method's intermediates are freed until MATLAB
%   actually returns the pages, and it is not a peak. MATLAB offers no way to
%   measure the high-water mark of an arbitrary block of code, so this project
%   does not claim one: the deterministic, comparable number is the size of
%   what each method HANDED BACK, and that is measured separately.
%
%   MEMORY exists only on Windows. Everywhere else this is NaN, which the
%   diagnostics table shows as a dash rather than as zero.

b = NaN;
if ~ispc
    return
end
try
    m = memory;
    b = m.MemUsedMATLAB;
catch
    % Left as NaN. A memory reading that cannot be taken is not an error
    % worth failing a run over.
end
end
