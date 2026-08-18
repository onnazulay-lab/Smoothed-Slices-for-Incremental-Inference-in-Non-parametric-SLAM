function [given, info] = combineChildSeparators(samplers, n)
%COMBINECHILDSEPARATORS Algorithm N3's "append p(S_C) to the parent clique".
%
%   Inputs
%     SAMPLERS  the children's trained conditional samplers
%     N         how many samples to draw from each
%
%   Outputs
%     GIVEN     the dictionary methods.nfisam.trainingSampleSimulator
%               conditions on
%     INFO      which of the three overlap cases each child took, the
%               effective sample size where a product was formed, and any
%               approximation that was made
%
%   Utility
%     Draw N samples from each child's separator density and hand them to the
%     parent.
%
%   WHY SAMPLES AND NOT A CORE.FACTOR. Spec section 7 says to append p(S_C) to
%   the parent as a factor, and Algorithm N1 does not evaluate factors -- it
%   simulates from them. So what the parent needs from a separator density is
%   draws, which is exactly what the appended factor would have been asked for.
%   Passing it as a CORE.FACTOR instead would be worse in two ways that matter:
%   a separator wider than two variables is refused by METHODS.NFISAM.FACTORROLE,
%   and Algorithm N1 samples a factor one variable at a time, which would throw
%   away the correlation between separator variables -- the one thing the child
%   learned that the parent cannot rederive.
%
%   TWO CHILDREN THAT SHARE SEPARATOR VARIABLES are the only hard case, and
%   there are three of them:
%
%     disjoint    the separators do not meet. The two densities are separate
%                 factors over separate variables, so drawing from each
%                 independently is exact.
%     contained   a later child's separator is entirely among variables already
%                 drawn. Its density is then a second factor over the same
%                 variables, and the product is formed by weighting the
%                 existing draws by that density and resampling. Exact in the
%                 Monte Carlo limit, and the effective sample size is reported
%                 so that a product too sharp for N draws is visible rather
%                 than merely quiet.
%     partial     a later child's separator meets the drawn variables without
%                 being contained in them. The product would need the child's
%                 density marginalized onto the overlap, which a flow does not
%                 give in closed form. The overlap keeps the earlier child's
%                 draws and the rest is taken from this one; the approximation
%                 is warned about, named, and recorded in INFO.
%
%   RESAMPLING APPLIES TO EVERY VARIABLE DRAWN SO FAR, not only the ones being
%   weighted. The draws are one joint sample set; reindexing part of it would
%   break exactly the correlation this function exists to carry upward.

arguments
    samplers (1,:) cell
    n (1,1) double {mustBeInteger, mustBePositive}
end

given = struct();
names = string.empty(1, 0);

info = struct('names', string.empty(1,0), 'numChildren', numel(samplers), ...
              'combined', string.empty(1,0), 'effectiveSampleSize', [], ...
              'approximated', string.empty(1,0));

for k = 1:numel(samplers)
    s = samplers{k};
    if ~isa(s, 'methods.nfisam.ConditionalSampler')
        error('methods:nfisam:combineChildSeparators:notASampler', ...
            ['Child %d is a %s. Algorithm N3 trains leaf to root, so every ' ...
             'child already has its sampler by the time the parent asks.'], ...
            k, class(s));
    end

    sep = s.Separator;
    if isempty(sep)
        continue    % a child with no separator shares nothing with this parent
    end

    known = ismember(sep, names);

    if ~any(known)
        % --- disjoint: an independent factor over new variables ----------
        D = methods.nfisam.unpackSamples(s.sampleSeparator(n), sep, s.separatorWidths());
        for v = sep
            key = matlab.lang.makeValidName(v);
            given.(key) = D.(key);
        end
        names = [names sep]; %#ok<AGROW>

    elseif all(known)
        % --- contained: form the product by weighting and resampling -----
        X = methods.nfisam.packSamples(given, sep);
        lw = s.separatorLogProb(X);
        w = exp(lw - max(lw));
        w = w / sum(w);

        info.combined(end+1) = strjoin(sep, ",");
        info.effectiveSampleSize(end+1) = 1 / sum(w.^2);

        idx = localSystematicResample(w);
        for f = string(fieldnames(given)).'
            given.(f) = given.(f)(idx, :);
        end

    else
        % --- partial: the overlap cannot be multiplied, so say so --------
        shared = sep(known);
        warning('methods:nfisam:combineChildSeparators:partialOverlap', ...
            ['Two children of this clique share %s but not their whole ' ...
             'separators, so their densities cannot be multiplied by ' ...
             'reweighting. The shared variables keep the first child''s ' ...
             'draws and the correlation the second learned across %s is ' ...
             'lost.'], strjoin(shared, ', '), strjoin(sep, ', '));
        info.approximated(end+1) = strjoin(shared, ",");

        D = methods.nfisam.unpackSamples(s.sampleSeparator(n), sep, s.separatorWidths());
        for v = sep(~known)
            key = matlab.lang.makeValidName(v);
            given.(key) = D.(key);
        end
        names = [names sep(~known)]; %#ok<AGROW>
    end
end

info.names = names;
end

% -------------------------------------------------------------------------
function idx = localSystematicResample(w)
%LOCALSYSTEMATICRESAMPLE Resampling indices, one stratified pass.
%   Inputs   W, the weights
%   Outputs  IDX, one index per draw
%   Utility  systematic rather than multinomial: same expectation, lower
%           variance, and it cannot drop a heavy particle by chance.
%
%   Systematic rather than multinomial: it draws one uniform instead of N and
%   has strictly lower variance, which is the difference between a product
%   density that survives being formed and one that collapses onto a handful
%   of distinct rows.
n = numel(w);
edges = [0; cumsum(w(:))];
edges(end) = 1;                       % against rounding, so DISCRETIZE covers 1
u = ((0:n-1)' + rand) / n;
idx = discretize(u, edges);
idx(isnan(idx)) = n;                  % u == 1 exactly
end
