function role = factorRole(f)
%FACTORROLE Sort a factor into Algorithm N1's three inputs.
%
%   Inputs
%     F     one core.Factor
%
%   Outputs
%     ROLE  "prior", "binary" or "multimodal", the partition P / B / M that
%           trainingSampleSimulator takes as input
%
%   Utility
%     Decide which of Algorithm N1's three cases a factor belongs to.
%
%   The split is by Kind rather than by counting the scope, because scope
%   size does not separate the two cases that matter: an ambiguous range
%   factor reaches one pose and several candidate landmarks, so it is wider
%   than a binary factor while being exactly the data-association case
%   Algorithm N1 step 4 handles separately. Anything with an unrecognised
%   Kind falls back to its scope size, and a factor over more than two
%   variables that is not a known association factor is refused by name
%   rather than quietly simulated as if it were binary.

arguments
    f (1,1) core.Factor
end

switch f.Kind
    case {"gaussianUnary", "gaussianVectorUnary"}
        role = "prior";
    case {"gaussianRelative", "gaussianVectorRelative", "range"}
        role = "binary";
    case {"mixtureRelative", "ambiguousRange"}
        role = "multimodal";
    otherwise
        switch numel(f.Scope)
            case 1
                role = "prior";
            case 2
                role = "binary";
            otherwise
                error('methods:nfisam:factorRole:unsupported', ...
                    ['Factor %s has kind "%s" over %d variables. Algorithm N1 ' ...
                     'knows priors, binary measurements and data-association ' ...
                     'factors; say which this is before it can be simulated.'], ...
                    f.Name, f.Kind, numel(f.Scope));
        end
end
end
