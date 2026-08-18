function [X, widths] = packSamples(S, names)
%PACKSAMPLES Lay a sample dictionary out as a matrix, in a given order.
%
%   Inputs
%     S       the sample dictionary
%     NAMES   the variables, in the order the flow is to see them
%
%   Outputs
%     X       one matrix, one row per training sample
%     WIDTHS  how many columns each variable occupies -- NOT recoverable from
%             X, since two 1-D variables and one 2-D variable both make two
%             columns
%
%   Utility
%     Run step 1 of Algorithm N2, "rearrange training samples to the order
%     O, S, F".
%
%   This is step 1 of Algorithm N2, "rearrange training samples to the order
%   O, S, F", and it is a separate function because the ordering is the whole
%   point of it. Spec section 17: the order inside the flow is not cosmetic,
%   it is what lets the triangular map expose the separator density and the
%   conditional sampler. A variable that occupies several columns -- a planar
%   position, a pose -- keeps its columns adjacent and in its own order, so
%   the block boundaries are the only thing the partition of Eq. N8 has to
%   respect.
%
%   The widths come back because they are not recoverable from the matrix:
%   two 1-D variables and one 2-D variable both make two columns, and
%   UNPACKSAMPLES needs to know which it was.

arguments
    S (1,1) struct
    names (1,:) string
end

widths = zeros(1, numel(names));
blocks = cell(1, numel(names));
n = 0;

for i = 1:numel(names)
    key = matlab.lang.makeValidName(names(i));
    if ~isfield(S, key)
        error('methods:nfisam:packSamples:missing', ...
            ['%s is named in the clique layout but is not in the sample ' ...
             'dictionary. Algorithm N1 returns what it managed to reach; ' ...
             'the layout must not name more than that.'], names(i));
    end

    b = S.(key);
    if ~ismatrix(b)
        error('methods:nfisam:packSamples:shape', ...
            ['%s arrived as a %s block. Training samples are one row per ' ...
             'sample and one column per dimension.'], ...
            names(i), mat2str(size(b)));
    end

    if i == 1
        n = size(b, 1);
    elseif size(b, 1) ~= n
        error('methods:nfisam:packSamples:rows', ...
            ['%s has %d samples but %s has %d. Every variable in a clique ' ...
             'is simulated jointly, so the rows must correspond.'], ...
            names(i), size(b, 1), names(1), n);
    end

    widths(i) = size(b, 2);
    blocks{i} = b;
end

X = [blocks{:}];
if isempty(names)
    X = zeros(0, 0);
end
end
