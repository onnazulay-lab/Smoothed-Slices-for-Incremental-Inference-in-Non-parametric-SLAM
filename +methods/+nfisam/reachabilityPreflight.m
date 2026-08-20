function report = reachabilityPreflight(factors, opts)
%REACHABILITYPREFLIGHT Can Algorithm N1 reach this clique's variables?
%
%   Inputs
%     FACTORS     the clique's factors
%     Given       variables already supplied: separator draws handed down, or
%                 a child's separator density. Only the field NAMES are read
%     Frontal     F_C, every one of which must end up reachable
%     Separator   S_C, recorded in the report for the failure packet
%
%   Outputs
%     REPORT  ok, the reachable and unreachable variable names, the factors
%             whose virtual measurement is constructible, a failure struct
%             array naming factor, role, reason and missing variables, and a
%             one-line summary
%
%   Utility
%     Decide, deterministically and without sampling anything, whether
%     METHODS.NFISAM.TRAININGSAMPLESIMULATOR can reach every variable this
%     clique needs -- before a flow fit is spent finding out.
%
%   THIS IS A VALIDATOR, NOT A SECOND INFERENCE PATH. It mirrors the
%   reachability logic of Algorithm N1 and nothing else: which variables the
%   generative construction can arrive at, in what order. It draws no samples,
%   evaluates no factor, and must never be used to supply a variable the
%   simulator could not have supplied itself. If the two ever disagree, the
%   simulator is right and this is the bug.
%
%   WHY IT EARNS ITS PLACE. A clique that cannot be reached fails inside the
%   simulator, tens of seconds into an increment, with one variable named and
%   no record of what the clique was or what it already had. Run first, the
%   same failure is a packet: the increment, the clique, the factor, what was
%   reachable, and what was not. That is the difference between "l2 was not
%   reached" and knowing which generative route is missing.
%
%   See also methods.nfisam.trainingSampleSimulator, methods.nfisam.factorRole.

arguments
    factors (1,:) core.Factor
    opts.Given (1,1) struct = struct()
    opts.Frontal (1,:) string = string.empty(1,0)
    opts.Separator (1,:) string = string.empty(1,0)
end

roles = arrayfun(@(f) methods.nfisam.factorRole(f), factors);
% A clique holds more than its local factors mention. A variable handed down
% as a child's separator density is exactly what GIVEN carries, and leaving
% it out here made it invisible to the reachable mask below -- so a variable
% the clique already had was reported as unreached. The simulator seeds from
% GIVEN directly, and when the two disagree the simulator is right.
allVars = unique([[factors.Scope] opts.Frontal opts.Separator], 'stable');

% Step 2's inputs: what the clique starts holding. GIVEN arrives keyed by
% makeValidName, so the comparison is made in that space throughout and the
% report is translated back to variable names at the end.
givenKeys = string(fieldnames(opts.Given)).';
reachable = false(1, numel(allVars));
keyOf     = arrayfun(@(v) string(matlab.lang.makeValidName(v)), allVars);
reachable(ismember(keyOf, givenKeys)) = true;

for f = factors(roles == "prior")
    reachable(ismember(allVars, f.Scope)) = true;
end

% Step 3, as a fixed point rather than a queue. The queue in the simulator
% exists to decide an ORDER; here only the reached set matters, so iterating
% to no-change answers the same question without one.
B = factors(roles == "binary");
constructible = string.empty(1, 0);
notInvertible = struct('factor', {}, 'role', {}, 'reason', {}, 'missing', {});

changedAny = true;
while changedAny
    changedAny = false;
    for f = B
        in = ismember(allVars, f.Scope);
        known = reachable & in;
        if nnz(known) == nnz(in)
            name = string(f.Name);
            if ~ismember(name, constructible), constructible(end+1) = name; end %#ok<AGROW>
        elseif nnz(known) == nnz(in) - 1
            target = allVars(in & ~reachable);
            if f.canSample(target)
                reachable(ismember(allVars, target)) = true;
                changedAny = true;
            elseif ~any(strcmp({notInvertible.factor}, f.Name))
                % Reached from one side and refuses to simulate the other:
                % a different failure from an unreached variable, and the
                % packet must not report it as the same thing.
                notInvertible(end+1) = struct('factor', string(f.Name), ...
                    'role', "binary", 'reason', "notInvertible", ...
                    'missing', target); %#ok<AGROW>
            end
        end
    end
end

% Step 4. Every latent variable of a data-association factor must already be
% reachable; the factor is never allowed to be the thing that introduces one.
failures = notInvertible;
for f = factors(roles == "multimodal")
    missing = f.Scope(~reachable(ismember(allVars, f.Scope)));
    if ~isempty(missing)
        failures(end+1) = struct('factor', string(f.Name), ...
            'role', "multimodal", 'reason', "associationUnreached", ...
            'missing', missing); %#ok<AGROW>
    end
end

unreachedFrontal = opts.Frontal(~ismember(opts.Frontal, allVars(reachable)));
if ~isempty(unreachedFrontal)
    failures(end+1) = struct('factor', "", 'role', "frontal", ...
        'reason', "frontalUnreached", 'missing', unreachedFrontal);
end

report = struct( ...
    'ok',            isempty(failures), ...
    'reachable',     allVars(reachable), ...
    'unreachable',   allVars(~reachable), ...
    'constructible', constructible, ...
    'frontal',       opts.Frontal, ...
    'separator',     opts.Separator, ...
    'given',         givenKeys, ...
    'failures',      failures);

if report.ok
    report.summary = sprintf('reachable: %d of %d variable(s)', ...
        numel(report.reachable), numel(allVars));
else
    report.summary = sprintf('unreachable: %s', ...
        strjoin(unique([failures.missing]), ', '));
end
end
