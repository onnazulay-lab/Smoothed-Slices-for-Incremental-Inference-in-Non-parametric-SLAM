function out = serializableConfig(config)
%SERIALIZABLECONFIG The config with its live UI handles removed.
%
%   Inputs
%     CONFIG  a method config
%
%   Outputs
%     OUT     the same config without the fields that exist only for the
%             duration of a run
%
%   Utility
%     Make a config safe to STORE. Never use it on the way in: the engine
%     needs those fields.
%
%   Every result carries a copy of the config it was produced with, and those
%   copies are saved to run_state.mat and encoded into config.json. A progress
%   reporter in there would be a live handle object written into an export
%   bundle: it would round-trip as a dead handle, appear in the JSON as a
%   function-handle string and a stale cancellation flag, and quietly imply
%   that the reporter was part of the method's settings rather than of the
%   session that ran it.
%
%   Use this wherever a config is STORED. Never on the way in: the engine
%   needs the reporter it strips.

arguments
    config (1,1) struct
end

out = config;
transient = "progress";
for f = transient
    if isfield(out, f)
        out = rmfield(out, f);
    end
end
end
