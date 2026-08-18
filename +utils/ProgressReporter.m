classdef ProgressReporter < handle
    %PROGRESSREPORTER Progress out of a long run, and cancellation back into it.
    %
    %   Properties
    %     Cancelled, Fraction, Message, NumReports, NumEmitted   dependent,
    %       all read through the root so a child view cannot disagree
    %     MinInterval  seconds between emissions to the sink
    %
    %   Methods
    %     sub          a child view onto a sub-range, sharing cancellation
    %     report       publish progress, then throw if Stop was pressed
    %     announce     publish WITHOUT honouring a pending cancellation
    %     check        throw if cancelled, otherwise do nothing
    %     cancel       ask the run to stop at its next boundary
    %     isCancelled, reset
    %     isCancellation (static)  is an MException the Stop button or a bug
    %
    %   Utility
    %     Carry progress out of a long run and cancellation back into it,
    %     without the engine depending on a figure existing.
    %
    %   One reporter is threaded through a comparative run on CONFIG.progress.
    %   The engine calls REPORT at the boundaries where its time actually goes;
    %   a caller that wants to see them supplies a SINK.
    %
    %   THE SINK'S DRAWNOW IS NOT INCIDENTAL, it is the whole mechanism.
    %   MATLAB runs the UI on the same thread as the computation, so a Stop
    %   button's callback cannot fire while an elimination is in progress. The
    %   only reason cancellation works at all is that the sink yields to the
    %   event queue, which means every cancellable run pays for the yield.
    %   MININTERVAL is what keeps that a rate rather than a per-iteration tax,
    %   and it is also the worst-case latency between pressing Stop and the run
    %   noticing.
    %
    %   There is no graphics code in this class, and there must not be: the
    %   engine cannot depend on a figure existing, the test suite runs headless,
    %   and a sink-less reporter is the null object every non-interactive caller
    %   gets from utils.progressOf.
    %
    %   SCOPING IS BY OBJECT, NOT BY A STACK. SUB returns a child view onto a
    %   sub-range of this reporter's range, sharing its cancellation state:
    %
    %       p = utils.ProgressReporter(@(f, msg) disp(msg));
    %       q = p.sub(0.0, 0.6);      % the forward pass owns the first 60%
    %       q.report(0.5, "eliminating x3")     % lands at 0.30 overall
    %
    %   A stack with push/pop was the obvious alternative and is quietly wrong:
    %   `guard = p.enter(...)` inside a loop constructs the new scope before it
    %   destroys the previous guard, so the pop would remove the scope that was
    %   just pushed. Child objects have no such ordering to get wrong.
    %
    %   See also utils.progressOf, methods.runComparison.

    properties (SetAccess = private)
        %LO, HI The absolute range of the whole run that this view covers.
        Lo (1,1) double = 0
        Hi (1,1) double = 1
    end

    properties (SetAccess = private, GetAccess = private)
        %PARENT The reporter that owns the state. Empty means this one does.
        %   Held rather than self-referencing, because a handle object that
        %   points at itself is a reference cycle MATLAB will not collect.
        Parent = []
    end

    properties
        %SINK function_handle taking (fraction, message), or [] for silence.
        %   Set it on the ROOT. A run has one sink; emit reads the root's, so
        %   assigning to a child's is accepted and then ignored.
        Sink = []
        %MININTERVAL Seconds between sink calls. Also the Stop-to-notice lag.
        %   The root's, for the same reason.
        MinInterval (1,1) double {mustBeNonnegative} = 0.05
    end

    properties (Dependent, SetAccess = private)
        %CANCELLED, FRACTION, MESSAGE, NUMREPORTS, NUMEMITTED The run's state.
        %   DEPENDENT, AND READ FROM THE ROOT, because there is only one run.
        %   These were plain properties and that was a bug waiting on its first
        %   caller: emit only ever runs on the root, so a child's own copies sat
        %   at 0/""/false forever while the run they describe went past them. A
        %   child is documented above as a usable view of the run, and
        %   `q = p.sub(0,0.6); q.Fraction` returning zero at the end of the
        %   forward pass would make that documentation false. isCancelled
        %   already delegated; the properties now agree with it.
        Cancelled
        %FRACTION, MESSAGE The last state emitted, for a caller that polls.
        Fraction
        Message
        %NUMREPORTS Every report reaching the root, rate-limited or not.
        NumReports
        %NUMEMITTED Those that actually reached the sink.
        NumEmitted
    end

    properties (Access = private)
        %*STATE The storage behind the dependent properties. Only the root's
        %   copies are ever written, and only through EMIT, CANCEL and RESET.
        CancelledState (1,1) logical = false
        FractionState (1,1) double = 0
        MessageState (1,1) string = ""
        NumReportsState (1,1) double = 0
        NumEmittedState (1,1) double = 0
        LastEmit (1,1) uint64 = uint64(0)
        HasEmitted (1,1) logical = false
    end

    methods
        function obj = ProgressReporter(sink, opts)
            %PROGRESSREPORTER Construct a root reporter.
            %   Inputs   SINK, a @(fraction, message) callback, and MinInterval
            %   Outputs  OBJ, a root reporter
            %   Utility  build the one reporter a run is threaded through.
            %   P = utils.ProgressReporter() is the null object: it accepts
            %   every call and does nothing, which is what the engine gets when
            %   nobody is watching.
            arguments
                sink = []
                opts.MinInterval (1,1) double {mustBeNonnegative} = 0.05
            end
            obj.Sink = sink;
            obj.MinInterval = opts.MinInterval;
        end

        function child = sub(obj, lo, hi)
            %SUB A view onto a sub-range of this one, sharing its cancellation.
            %   Inputs   LO, HI, fractions of THIS reporter's range
            %   Outputs  CHILD, a view whose 0..1 maps onto [LO, HI]
            %   Utility  let a phase report its own progress in its own terms
            %           without knowing where it sits in the whole run.
            %   LO and HI are fractions of THIS reporter's range, so ranges
            %   compose without any caller having to know its absolute
            %   position in the run.
            arguments
                obj (1,1) utils.ProgressReporter
                lo (1,1) double {mustBeInRange(lo, 0, 1)}
                hi (1,1) double {mustBeInRange(hi, 0, 1)}
            end
            if hi < lo
                error('utils:ProgressReporter:badRange', ...
                    'Sub-range [%g %g] runs backwards.', lo, hi);
            end
            span = obj.Hi - obj.Lo;
            child = utils.ProgressReporter.makeChild(obj.root(), ...
                obj.Lo + lo * span, obj.Lo + hi * span);
        end

        function report(obj, f, message)
            %REPORT Publish progress, then throw if Stop has been pressed.
            %   Inputs   F a fraction of THIS view's range, MESSAGE the text
            %   Outputs  none; throws the cancellation MException when stopped
            %   Utility  the normal reporting call, which is also the only
            %           place a run can notice it has been cancelled.
            %   F is a fraction of THIS view's range. The throw comes after the
            %   emit on purpose: the last thing the user sees should be where
            %   the run had got to when they stopped it, not the state before.
            arguments
                obj (1,1) utils.ProgressReporter
                f (1,1) double
                message (1,1) string = ""
            end
            r = obj.root();
            f = min(max(f, 0), 1);
            r.emit(obj.Lo + f * (obj.Hi - obj.Lo), message);
            r.check();
        end

        function announce(obj, f, message)
            %ANNOUNCE Publish progress WITHOUT honouring a pending cancellation.
            %   Inputs   F a fraction of THIS view's range, MESSAGE the text
            %   Outputs  none; never throws
            %   Utility  report the work that runs AFTER a Stop was caught,
            %           which must be able to finish and say so.
            %   For the work that runs after a Stop has already been caught and
            %   handled: scoring the methods that did finish, and saying how
            %   many of them there were. Using REPORT there would throw a
            %   second cancellation out of the very code that was recovering
            %   from the first, and lose the results Stop was meant to keep.
            arguments
                obj (1,1) utils.ProgressReporter
                f (1,1) double
                message (1,1) string = ""
            end
            f = min(max(f, 0), 1);
            obj.root().emit(obj.Lo + f * (obj.Hi - obj.Lo), message);
        end

        function check(obj)
            %CHECK Throw if this run has been cancelled, otherwise do nothing.
            %   Inputs   none
            %   Outputs  none; throws the cancellation MException when stopped
            %   Utility  add a cancellation point where there is no progress to
            %           report.
            r = obj.root();
            if r.CancelledState
                error('utils:progress:cancelled', ...
                    'Run cancelled at %.0f%%: %s', ...
                    100 * r.FractionState, r.MessageState);
            end
        end

        function cancel(obj)
            %CANCEL Ask the run to stop at its next reporting boundary.
            %   Inputs   none
            %   Outputs  none
            %   Utility  what the Stop button calls.
            %   Sets a flag; it does not interrupt anything. A step already in
            %   progress runs to completion, which is why the boundaries are
            %   placed where they are.
            % Through a local, not as obj.root().Cancelled: assigning into the
            % result of a method call happens to work for a handle here, but
            % it reads as though it might be setting a field on a temporary.
            r = obj.root();
            r.CancelledState = true;
        end

        function tf = isCancelled(obj)
            %ISCANCELLED Whether Stop has been pressed.
            %   Inputs   none
            %   Outputs  TF, logical
            %   Utility  test the flag without throwing, for a caller deciding
            %           what to keep.
            tf = obj.root().CancelledState;
        end

        function reset(obj)
            %RESET Clear cancellation and counters before a fresh run.
            %   Inputs   none
            %   Outputs  none
            %   Utility  reuse one reporter across runs; a stale cancelled flag
            %           would stop the next run before it started.
            r = obj.root();
            r.CancelledState  = false;
            r.FractionState   = 0;
            r.MessageState    = "";
            r.NumReportsState = 0;
            r.NumEmittedState = 0;
            r.HasEmitted      = false;
        end

        % --- Dependent property getters, all reading the root ---------------
        function v = get.Cancelled(obj),  v = obj.root().CancelledState;  end
        function v = get.Fraction(obj),   v = obj.root().FractionState;   end
        function v = get.Message(obj),    v = obj.root().MessageState;    end
        function v = get.NumReports(obj), v = obj.root().NumReportsState; end
        function v = get.NumEmitted(obj), v = obj.root().NumEmittedState; end
    end

    methods (Access = private)
        function r = root(obj)
            %ROOT The reporter that owns the shared state.
            %   Inputs   none
            %   Outputs  R, this object or the ancestor holding the state
            %   Utility  keep one copy of cancellation and progress, so a child
            %           view and its parent can never disagree.
            if isempty(obj.Parent)
                r = obj;
            else
                r = obj.Parent;
            end
        end

        function emit(obj, absFraction, message)
            %EMIT Record the state and, if the rate allows, hand it to the sink.
            %   Inputs   ABSFRACTION the whole-run fraction, MESSAGE the text
            %   Outputs  none
            %   Utility  apply MinInterval, so yielding to the event queue stays
            %           a rate rather than a per-iteration tax.
            %   Resolves the root itself rather than trusting every caller to
            %   have done so. The callers all do today; one that forgets would
            %   otherwise write state onto a child where nothing reads it, and
            %   the run would simply stop reporting with no error to notice.
            r = obj.root();
            r.NumReportsState = r.NumReportsState + 1;
            r.FractionState   = min(max(absFraction, 0), 1);
            if strlength(message) > 0
                r.MessageState = message;
            end

            if isempty(r.Sink), return, end

            % The endpoints are never dropped. A run whose last emit was rate
            % limited away would leave a bar frozen short of full while the
            % caller reported success.
            due = ~r.HasEmitted || r.FractionState >= 1 || ...
                  toc(r.LastEmit) >= r.MinInterval;
            if ~due, return, end

            r.LastEmit        = tic;
            r.HasEmitted      = true;
            r.NumEmittedState = r.NumEmittedState + 1;
            r.Sink(r.FractionState, r.MessageState);
        end
    end

    methods (Static)
        function tf = isCancellation(err)
            %ISCANCELLATION Is this MException the Stop button rather than a bug?
            %   Inputs   ERR, a caught exception
            %   Outputs  TF, logical
            %   Utility  let a catch block re-throw a real error while treating
            %           a cancellation as an ordinary early return.
            tf = isa(err, 'MException') && ...
                 string(err.identifier) == "utils:progress:cancelled";
        end
    end

    methods (Static, Access = private)
        function child = makeChild(parent, lo, hi)
            %MAKECHILD Construct a child view. Private on purpose.
            %   Inputs   PARENT, and LO/HI in the parent's own fractions
            %   Outputs  CHILD, a reporter sharing the parent's state
            %   Utility  build a sub-view through SUB only.
            %
            % A private static rather than a second public constructor form:
            % the only reporter a caller should ever build by hand is a root,
            % and every child comes from SUB with a range already composed.
            child = utils.ProgressReporter();
            child.Parent = parent;
            child.Lo = lo;
            child.Hi = hi;
        end
    end
end
