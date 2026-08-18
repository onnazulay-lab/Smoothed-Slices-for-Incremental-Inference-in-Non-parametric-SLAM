classdef StepCache < handle
    %STEPCACHE Reuse of elimination steps across increments.
    %
    %   Properties
    %     Fingerprint  the config digest every signature starts from
    %     Enabled      false makes every lookup a miss
    %     Hits, Misses, Stores, Evictions   the counters stats() reports
    %     MaxEntries   how many payloads to keep before evicting the oldest
    %
    %   Methods
    %     signature      the running digest described below
    %     fetch, store   the lookup and the insert
    %     stats          the counters, plus the hit rate
    %     resetCounters  zero the counters, keep the entries
    %     hash, seedFor, fingerprint (static)
    %
    %   Utility
    %     Reuse the longest UNCHANGED PREFIX of an elimination across
    %     increments, without changing the answer.
    %
    %   A handle class so one cache survives the whole k = 1..K replay while
    %   the graph, the states and the results are rebuilt for every increment.
    %
    %   WHAT IS CACHED AND WHY IT IS SOUND. An elimination step is a
    %   deterministic function of four things: the variable being eliminated,
    %   the factors adjacent to it, the separator they induce, and the random
    %   stream. Everything else the step reads -- the proposal book, the
    %   generated factors still standing in the graph -- is itself a function
    %   of the steps that came before. So the key is a running digest:
    %
    %       sig_j = hash( configFingerprint, sig_{j-1}, omega_j,
    %                     names of F_{j-1}(omega_j), S_j )
    %
    %   with sig_0 the config fingerprint alone. A step hits only when every
    %   step before it also hit, which means the cache reuses the longest
    %   UNCHANGED PREFIX of the elimination and recomputes from the first step
    %   the new measurements touched. That is conservative -- two runs whose
    %   middles happen to coincide after a divergence will not share -- and
    %   conservative is the right side to err on when the alternative is
    %   silently reusing a surface built from different data.
    %
    %   This is exactly the saving the Smoothed Slices spec describes for the
    %   conditional smoothing surfaces R_r: on the grid world a new pose at
    %   increment k adds an odometry factor and some ranges, all of which sit
    %   at the END of the elimination order, so the early poses and the
    %   beacons behind the robot are re-eliminated for nothing.
    %
    %   WHY THE STREAM IS PART OF IT. The cache would be worthless if a hit
    %   changed the answer, and it would change the answer by accident: a
    %   skipped step draws no random numbers, so every step after it would see
    %   a different stream than it would have in a fresh run. STEPSEED, below,
    %   derives each step's seed from that step's own signature, which makes a
    %   run with the cache on numerically identical to the same run with it
    %   off. tIncremental pins that.

    properties (SetAccess = private)
        Fingerprint (1,1) string    % config fields the steps actually read
        Enabled (1,1) logical = true
        Hits (1,1) double = 0
        Misses (1,1) double = 0
        Stores (1,1) double = 0
        Evictions (1,1) double = 0
        MaxEntries (1,1) double = 4096
    end

    properties (Access = private)
        Map                          % containers.Map: signature -> step payload
        Order (1,:) string           % insertion order, for eviction
    end

    methods
        function obj = StepCache(config, opts)
            %STEPCACHE Build an empty cache fingerprinted to one config.
            %   Inputs   CONFIG, then Enabled and MaxEntries
            %   Outputs  OBJ
            %   Utility  bind the cache to the settings it is valid under, so
            %           a config change cannot produce a hit.
            arguments
                config (1,1) struct
                opts.Enabled (1,1) logical = true
                opts.MaxEntries (1,1) double {mustBePositive} = 4096
            end
            obj.Fingerprint = methods.general.StepCache.fingerprint(config);
            obj.Enabled = opts.Enabled;
            obj.MaxEntries = opts.MaxEntries;
            obj.Map = containers.Map('KeyType', 'char', 'ValueType', 'any');
        end

        function sig = signature(obj, prevSig, omega, removed, separator)
            %SIGNATURE The running digest described in the class comment.
            %   Inputs   PREVSIG the previous step's signature, OMEGA the
            %           variable, REMOVED its factors, SEPARATOR the separator
            %   Outputs  SIG, this step's signature
            %   Utility  a step hits only when every step before it also hit.
            arguments
                obj (1,1) methods.general.StepCache
                prevSig (1,1) string
                omega (1,1) string
                removed (1,:) core.Factor
                separator (1,:) string
            end
            if strlength(prevSig) == 0
                prevSig = obj.Fingerprint;
            end
            if isempty(removed)
                fnames = "";
            else
                fnames = strjoin(sort([removed.Name]), "|");
            end
            if isempty(separator)
                sepStr = "";
            else
                sepStr = strjoin(sort(separator), "|");
            end
            sig = methods.general.StepCache.hash( ...
                prevSig + ">" + omega + ">" + fnames + ">" + sepStr);
        end

        function [hit, payload] = fetch(obj, sig)
            %FETCH The payload stored under a signature, if there is one.
            %   Inputs   SIG, the step signature
            %   Outputs  HIT whether it was found, PAYLOAD the stored step
            %   Utility  the lookup, and the only place Hits and Misses move.
            payload = [];
            hit = false;
            if ~obj.Enabled, obj.Misses = obj.Misses + 1; return, end
            key = char(sig);
            if obj.Map.isKey(key)
                payload = obj.Map(key);
                hit = true;
                obj.Hits = obj.Hits + 1;
            else
                obj.Misses = obj.Misses + 1;
            end
        end

        function store(obj, sig, payload)
            %STORE Keep a computed step under its signature.
            %   Inputs   SIG the signature, PAYLOAD the step's result
            %   Outputs  none
            %   Utility  the insert, evicting the oldest entry past MaxEntries.
            if ~obj.Enabled, return, end
            key = char(sig);
            if ~obj.Map.isKey(key)
                obj.Order(end+1) = sig;
            end
            obj.Map(key) = payload;
            obj.Stores = obj.Stores + 1;
            obj.evictIfNeeded();
        end

        function s = stats(obj)
            %STATS The counters, plus the hit rate and the fingerprint.
            %   Inputs   none
            %   Outputs  S, the statistics struct
            %   Utility  the number the incremental claim is measured by.
            total = obj.Hits + obj.Misses;
            rate = 0;
            if total > 0, rate = obj.Hits / total; end
            s = struct( ...
                'enabled',   obj.Enabled, ...
                'hits',      obj.Hits, ...
                'misses',    obj.Misses, ...
                'stores',    obj.Stores, ...
                'entries',   obj.Map.Count, ...
                'evictions', obj.Evictions, ...
                'hitRate',   rate, ...
                'fingerprint', obj.Fingerprint);
        end

        function resetCounters(obj)
            %RESETCOUNTERS Zero the statistics, keep the entries.
            %   Inputs   none
            %   Outputs  none
            %   Utility  report per-increment reuse rather than a cumulative
            %           one.
            %
            %   The per-increment record wants hits for THIS increment, not
            %   the running total.
            obj.Hits = 0; obj.Misses = 0; obj.Stores = 0;
        end
    end

    methods (Access = private)
        function evictIfNeeded(obj)
            %EVICTIFNEEDED Drop the oldest entries until the cache fits.
            %   Inputs   none
            %   Outputs  none
            %   Utility  bound the memory. Oldest-first, because the prefix a
            %           later increment reuses is the one most recently built.
            while obj.Map.Count > obj.MaxEntries && ~isempty(obj.Order)
                oldest = char(obj.Order(1));
                obj.Order(1) = [];
                if obj.Map.isKey(oldest)
                    obj.Map.remove(oldest);
                    obj.Evictions = obj.Evictions + 1;
                end
            end
        end
    end

    methods (Static)
        function h = hash(s)
            %HASH A short stable digest of a string.
            %   Inputs   S, the string
            %   Outputs  H, the digest
            %   Utility  keep a signature a fixed length however long the
            %           chain behind it grows.
            %
            %   A cryptographic digest would be better and MATLAB does not
            %   ship one that is callable without Java assumptions. FNV-1a is
            %   adequate here because a collision costs correctness only if
            %   two DIFFERENT prefixes collide, and the payload carries its
            %   own separator and variable name for the caller to check.
            bytes = uint32(unicode2native(char(s), 'UTF-8'));
            h32 = uint32(2166136261);
            p = uint32(16777619);
            for i = 1:numel(bytes)
                h32 = bitxor(h32, bytes(i));
                h32 = mod(double(h32) * double(p), 4294967296);
                h32 = uint32(h32);
            end
            h = string(dec2hex(h32, 8));
        end

        function seed = seedFor(sig)
            %SEEDFOR The random seed a step with this signature must use.
            %   Inputs   SIG, the step signature
            %   Outputs  SEED, a nonnegative integer
            %   Utility  this is what makes a cached run numerically identical
            %           to an uncached one: a skipped step draws no random
            %           numbers, so the stream cannot be positional.
            %
            %   rng() wants a value below 2^32; the signature is already a
            %   32-bit hash, so this is a parse rather than a hash.
            seed = mod(double(hex2dec(char(sig))), 2^32 - 1);
        end

        function fp = fingerprint(config)
            %FINGERPRINT The digest of the settings a cached step is valid under.
            %   Inputs   CONFIG, the method config
            %   Outputs  FP, the digest
            %   Utility  sig_0 is this alone, so a changed setting invalidates
            %           the whole chain rather than part of it.
            %
            %   Listed explicitly rather than hashing the whole struct: config
            %   carries a provenance block and a timestamp-bearing seed record
            %   in some callers, and a fingerprint that changed when a comment
            %   field changed would never hit.
            fields = ["numSamples", "separatorSupportSize", "supportDimGrowth", ...
                      "maxSupportSize", "supportOverdraw", "supportResample", ...
                      "supportMixtureSize", "innerEstimator", "activeSetSize", ...
                      "activeSetRule", "activeSetFraction", "defensiveWeight", ...
                      "proposalBandwidth", "exactGeneratedFactors", "seed"];
            parts = strings(1, numel(fields));
            for i = 1:numel(fields)
                if ~isfield(config, fields(i))
                    parts(i) = fields(i) + "=<absent>";
                    continue
                end
                v = config.(fields(i));
                if isstring(v) || ischar(v)
                    parts(i) = fields(i) + "=" + string(v);
                elseif islogical(v)
                    parts(i) = fields(i) + "=" + string(double(v));
                else
                    parts(i) = fields(i) + "=" + sprintf('%.12g', double(v));
                end
            end
            fp = methods.general.StepCache.hash(strjoin(parts, ";"));
        end
    end
end
