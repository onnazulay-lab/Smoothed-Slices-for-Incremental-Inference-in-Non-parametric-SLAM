function out = jsonSanitize(in)
%JSONSANITIZE Recursively convert a value into a jsonencode-safe form.
%
%   Inputs
%     IN   any value
%
%   Outputs
%     OUT  the same value in a form jsonencode accepts
%
%   Utility
%     Function handles become their char form, datetimes become ISO strings,
%     objects become their public properties, and non-finite doubles become
%     strings so NaN and Inf survive a JSON round trip as readable markers
%     instead of failing the encode.

if isa(in, 'function_handle')
    out = string(func2str(in));

elseif isdatetime(in) || isduration(in)
    out = string(in);

elseif iscategorical(in)
    out = string(in);

elseif isa(in, 'containers.Map')
    out = struct();
    k = keys(in);
    for i = 1:numel(k)
        out.(matlab.lang.makeValidName(k{i})) = utils.jsonSanitize(in(k{i}));
    end

elseif isstruct(in)
    if numel(in) == 1
        out = struct();
        f = fieldnames(in);
        for i = 1:numel(f)
            out.(f{i}) = utils.jsonSanitize(in.(f{i}));
        end
    else
        out = arrayfun(@utils.jsonSanitize, in, 'UniformOutput', false);
    end

elseif iscell(in)
    out = cellfun(@utils.jsonSanitize, in, 'UniformOutput', false);

elseif isobject(in) && ~isstring(in)
    out = struct();
    p = properties(in);
    for i = 1:numel(p)
        out.(p{i}) = utils.jsonSanitize(in.(p{i}));
    end

elseif isnumeric(in) && ~isempty(in) && ~all(isfinite(in(:)))
    % Preserve NaN/Inf as readable markers rather than letting them become null.
    out = arrayfun(@localNumToken, in, 'UniformOutput', false);

else
    out = in;
end
end

function t = localNumToken(v)
%LOCALNUMTOKEN The readable marker for a non-finite double.
%   Inputs   V, a scalar double
%   Outputs  T, a string such as "NaN" or "-Inf"
%   Utility  keep a non-finite value legible in the JSON rather than dropped.
if isnan(v)
    t = "NaN";
elseif isinf(v)
    t = string(sign(v) * Inf);
else
    t = v;
end
end
