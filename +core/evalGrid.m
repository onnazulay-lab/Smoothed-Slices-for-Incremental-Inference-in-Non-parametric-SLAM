function M = evalGrid(factors, nameA, A, nameB, B, opts)
%EVALGRID Product of factors over the outer product of two point sets.
%
%   Inputs
%     FACTORS  core.Factor array; the product is over all of them
%     NAMEA    name of the row variable
%     A        |A|-by-dA points, one per row
%     NAMEB    name of the column variable
%     B        |B|-by-dB points, one per row
%     Fixed    struct of further assignments held constant, each 1-by-d
%                                                            default struct()
%     MaxRows  chunk bound on chunk*|B|                       default 2e6
%
%   Outputs
%     M        |A|-by-|B|, with M(i,k) = prod_f f(A(i,:), B(k,:))
%
%   Utility
%     Form the slice matrix explicitly, for variables of any dimension.
%
%   Iteration 1 got this matrix free from implicit expansion by shaping one
%   variable as a column and the other as a row, which works only while both
%   are scalar. The expansion is done here instead, so the same call produces
%   the same matrix for planar poses and landmarks. The cost is one temporary of
%   |A|*|B| rows, which is why the work is chunked over A.
%
%   See also core.evalProduct.

arguments
    factors (1,:)
    nameA (1,1) string
    A double
    nameB (1,1) string
    B double
    opts.Fixed struct = struct()
    opts.MaxRows (1,1) double {mustBePositive} = 2e6
end

keyA = matlab.lang.makeValidName(nameA);
keyB = matlab.lang.makeValidName(nameB);

na = size(A, 1);
nb = size(B, 1);
M  = zeros(na, nb);
if na == 0 || nb == 0, return, end

% One chunk of A at a time, sized so the expanded assignment stays bounded.
chunk = max(1, floor(opts.MaxRows / nb));

for lo = 1:chunk:na
    hi  = min(lo + chunk - 1, na);
    idx = lo:hi;
    m   = numel(idx);

    a = struct();
    fn = fieldnames(opts.Fixed);
    for i = 1:numel(fn)
        a.(fn{i}) = opts.Fixed.(fn{i});
    end
    % Row i of the chunk repeated nb times, against B tiled m times: the
    % (i,k) pairs come out in row-major order, so one reshape recovers the
    % matrix without a transpose of the big temporary.
    a.(keyA) = A(idx(repelem(1:m, nb)), :);
    a.(keyB) = B(repmat(1:nb, 1, m), :);

    v = core.evalProduct(factors, a);
    M(idx, :) = reshape(v, nb, m).';
end
end
