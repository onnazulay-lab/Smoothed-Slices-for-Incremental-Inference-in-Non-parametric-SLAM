function txt = writeJSON(filePath, data)
%WRITEJSON Write a struct to pretty-printed JSON, sanitizing MATLAB-only types.
%
%   Inputs
%     FILEPATH  where to write; "" returns the text without writing
%     DATA      the value to encode
%
%   Outputs
%     TXT       the JSON text
%
%   Utility
%     Write a diagnostics bundle that cannot fail to serialize: datetime,
%     function handles, categorical and containers.Map are converted first.

arguments
    filePath (1,1) string
    data
end

txt = jsonencode(utils.jsonSanitize(data), 'PrettyPrint', true);

if strlength(filePath) > 0
    fid = fopen(filePath, 'w', 'n', 'UTF-8');
    if fid < 0
        error('utils:writeJSON:cannotOpen', 'Cannot open %s for writing.', filePath);
    end
    closer = onCleanup(@() fclose(fid));
    fwrite(fid, txt, 'char');
end
end
