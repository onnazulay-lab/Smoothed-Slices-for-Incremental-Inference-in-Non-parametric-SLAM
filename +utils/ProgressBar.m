classdef ProgressBar < handle
    %PROGRESSBAR An inline progress bar and a Stop button for a uifigure.
    %
    %   Properties
    %     Grid        the uigridlayout this owns; set its Layout to place it
    %     Reporter    the utils.ProgressReporter wired to this bar
    %     StopButton  the button itself
    %     Mirror      another ProgressBar to paint in step with this one
    %
    %   Methods
    %     begin       arm Stop and clear the previous run's state
    %     finish      disarm Stop and colour the bar by how the run ended
    %     wasStopped  whether Stop was pressed
    %     state       what the strip is saying, as data rather than as pixels
    %
    %   Utility
    %     Show progress and offer cancellation inside a tab, without the modal
    %     lock uiprogressdlg would impose.
    %
    %   BAR = utils.ProgressBar(PARENT) builds a one-row strip: a message, a
    %   bar, a percentage and a red Stop button. BAR.REPORTER is the
    %   utils.ProgressReporter to hand to a run on CONFIG.PROGRESS.
    %
    %       bar.begin("running...");
    %       cfg.progress = bar.Reporter;
    %       [results, summary] = methods.runComparison(caseData, cfg);
    %       bar.finish(summaryStatus, summary.note);
    %
    %   WHY NOT UIPROGRESSDLG. MATLAB's own progress dialog is modal: it locks
    %   the whole figure for the length of the run. On a comparative run of
    %   minutes that would mean the Case Study tab, the Process Explorer and
    %   the results of a PREVIOUS run all become unreachable exactly while
    %   there is time to look at them. This strip lives in a tab and takes one
    %   row.
    %
    %   WHY THERE IS NO PROGRESS COMPONENT TO USE. uifigures have no inline
    %   bar. The bar here is a two-column uigridlayout inside a panel, with a
    %   coloured panel in the first column and the column weights set to the
    %   fraction; that is the whole trick, and it is why the fill is clamped
    %   away from zero -- a '0x' column weight is not a valid width.
    %
    %   THE DRAWNOW IS PLAIN, NOT LIMITRATE. It is the only thing that lets
    %   the Stop callback run at all, since MATLAB shares one thread between
    %   the UI and the computation. `drawnow limitrate` is allowed to return
    %   without flushing the event queue, which would make Stop unreliable in
    %   exactly the runs it is needed for. The rate limiting belongs to the
    %   reporter's MinInterval instead, where it is one decision rather than
    %   two interacting ones.

    properties (SetAccess = private)
        Grid            % the uigridlayout this owns; set its Layout to place it
        Reporter        % utils.ProgressReporter, wired to this bar
        StopButton
    end

    properties
        %MIRROR Another utils.ProgressBar showing this run read-only, or [].
        %   One run belongs to the app, not to the tab whose button started it.
        %   Two tabs carry a bar, and the one that was not pressed would
        %   otherwise sit there showing the PREVIOUS run -- a green "done: 3 of
        %   3" while a run is under way beside it, or worse, while the run that
        %   replaced it was stopped after one method. That is the misreading
        %   the colours exist to prevent, arrived at from the other direction.
        %
        %   The mirror never gets a live Stop. One run with two buttons that
        %   cancel it is a second thing to reason about and it buys nothing:
        %   whichever tab you are looking at, the bar in front of you is the
        %   run, and the tab you are not looking at cannot be pressed.
        Mirror = []
    end

    properties (Access = private)
        Track           % the two-column grid whose weights are the fraction
        Fill            % the coloured panel in column 1
        Rest            % the empty panel in column 2, for the groove colour
        Label
        Percent
        Running (1,1) logical = false
        %SHOWN The fraction the strip is currently drawn at.
        %   Kept because the fraction otherwise exists only as a pair of
        %   uigridlayout column weights, and "what does the bar say" is a
        %   question both the mirror and the tests have to be able to ask.
        Shown (1,1) double = 0
    end

    properties (Constant, Access = private)
        RunningColour   = [0.20 0.42 0.72]
        DoneColour      = [0.20 0.60 0.33]
        CancelledColour = [0.85 0.60 0.15]
        FailedColour    = [0.78 0.15 0.15]
        GrooveColour    = [0.91 0.91 0.93]
        StopColour      = [0.78 0.15 0.15]
    end

    methods
        function obj = ProgressBar(parent, opts)
            %PROGRESSBAR Build the strip and its reporter.
            %   Inputs   PARENT the container, and the appearance options
            %   Outputs  OBJ, with Grid ready to be placed
            %   Utility  construct the bar and the reporter together, so the
            %           two are always wired to each other.
            arguments
                parent
                opts.StopText (1,1) string = "Stop"
                opts.IdleText (1,1) string = "idle"
                %ONSTOP Extra callback for the owner, fired after cancelling.
                opts.OnStop = []
            end

            obj.Grid = uigridlayout(parent, [1 4]);
            obj.Grid.ColumnWidth  = {'1.3x', '2x', 46, 86};
            obj.Grid.RowHeight    = {'1x'};
            obj.Grid.Padding      = [0 0 0 0];
            obj.Grid.ColumnSpacing = 6;

            obj.Label = uilabel(obj.Grid, 'Text', char(opts.IdleText), ...
                'VerticalAlignment', 'center');

            groove = uipanel(obj.Grid, 'BorderType', 'line', ...
                'BackgroundColor', obj.GrooveColour);
            obj.Track = uigridlayout(groove, [1 2]);
            obj.Track.Padding = [1 1 1 1];
            obj.Track.ColumnSpacing = 0;
            obj.Track.RowHeight = {'1x'};
            obj.Fill = uipanel(obj.Track, 'BorderType', 'none', ...
                'BackgroundColor', obj.RunningColour);
            obj.Rest = uipanel(obj.Track, 'BorderType', 'none', ...
                'BackgroundColor', obj.GrooveColour);

            obj.Percent = uilabel(obj.Grid, 'Text', '0%', ...
                'HorizontalAlignment', 'right', 'VerticalAlignment', 'center');

            % Disabled until a run starts. A Stop that is always live invites
            % pressing it when there is nothing to stop, and then the next run
            % begins already cancelled.
            obj.StopButton = uibutton(obj.Grid, 'Text', char(opts.StopText), ...
                'BackgroundColor', obj.StopColour, 'FontColor', [1 1 1], ...
                'FontWeight', 'bold', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~,~) obj.onStop(opts.OnStop));

            obj.Reporter = utils.ProgressReporter(@(f, msg) obj.update(f, msg));
            obj.setFraction(0);
        end

        function begin(obj, message)
            %BEGIN Arm the Stop button and clear the previous run's state.
            %   Inputs   MESSAGE, the initial text
            %   Outputs  none
            %   Utility  a stale cancelled flag would stop the next run before
            %           it started, so this resets it.
            arguments
                obj (1,1) utils.ProgressBar
                message (1,1) string = "running..."
            end
            obj.Reporter.reset();
            obj.Running = true;
            obj.Fill.BackgroundColor = obj.RunningColour;
            obj.StopButton.Enable = 'on';
            if obj.hasMirror()
                % Armed for watching, not for pressing. UPDATE carries the
                % fraction and the message across from here on.
                obj.Mirror.Running = false;
                obj.Mirror.StopButton.Enable = 'off';
                obj.Mirror.Fill.BackgroundColor = obj.Mirror.RunningColour;
            end
            obj.update(0, message);
        end

        function finish(obj, status, message)
            %FINISH Disarm Stop and colour the bar by how the run ended.
            %   Inputs   STATUS how it ended, MESSAGE the text to leave
            %   Outputs  none
            %   Utility  say how the run ended, in the colour and the text.
            %   A cancelled run is NOT driven to full: the bar is left where it
            %   stopped, because a full bar reads as a finished one whatever
            %   the message beside it says.
            arguments
                obj (1,1) utils.ProgressBar
                status (1,1) string {mustBeMember(status, ["ok" "cancelled" "failed"])}
                message (1,1) string = ""
            end
            obj.settle(status, message);
            if obj.hasMirror()
                obj.Mirror.settle(status, message);
            end
            drawnow;
        end

        function tf = wasStopped(obj)
            %WASSTOPPED Whether Stop was pressed during the last run.
            %   Inputs   none
            %   Outputs  TF, logical
            %   Utility  let the caller decide what to keep from a partial run.
            tf = obj.Reporter.isCancelled();
        end

        function s = state(obj)
            %STATE What the strip is saying, as data rather than as pixels.
            %   Inputs   none
            %   Outputs  S, the message, the fraction and whether Stop is armed
            %   Utility  make the strip testable without reading pixels.
            %   The message, the fraction and whether Stop can be pressed are
            %   the three things this widget claims, and a claim that can only
            %   be checked by looking at the screen is not one the suite can
            %   hold it to. The mirror in particular is untestable without it:
            %   its whole job is to say the same thing as another bar.
            s = struct('fraction', obj.Shown, ...
                       'text', string(obj.Label.Text), ...
                       'stoppable', logical(obj.StopButton.Enable));
        end

        function delete(obj)
            %DELETE Tear down the components this object owns.
            %   Inputs   none
            %   Outputs  none
            %   Utility  a handle class holding graphics must clean them up.
            if ~isempty(obj.Grid) && isgraphics(obj.Grid)
                delete(obj.Grid);
            end
        end
    end

    methods (Access = private)

        function update(obj, f, message)
            %UPDATE Paint this bar, forward to the mirror, and yield.
            %   Inputs   F the fraction, MESSAGE the text
            %   Outputs  none
            %   Utility  the sink handed to the reporter; the yield here is what
            %           lets the Stop callback fire at all.
            obj.paint(f, message);
            if obj.hasMirror()
                obj.Mirror.paint(f, message);
            end
            % ONE drawnow for both bars. The yield is what a cancellable run
            % pays for; painting a second strip inside it is free by
            % comparison, and two yields would double the cost of the mechanism
            % to show the same run twice.
            drawnow;
        end

        function paint(obj, f, message)
            %PAINT The bar's own state, with no drawnow and no forwarding.
            %   Inputs   F the fraction, MESSAGE the text
            %   Outputs  none
            %   Utility  separate from UPDATE so a mirror can be painted without
            %           recursing back into the forwarding.
            %   Separate from UPDATE so a mirror can be painted without it
            %   painting its own mirror in turn: PAINT and SETTLE are the two
            %   ends of the forwarding, and neither of them forwards. Two bars
            %   pointed at each other therefore cannot recurse.
            if isempty(obj.Grid) || ~isgraphics(obj.Grid), return, end
            obj.setFraction(f);
            if strlength(message) > 0
                obj.Label.Text = char(message);
            end
        end

        function settle(obj, status, message)
            %SETTLE How a run ended, with no drawnow and no forwarding.
            %   Inputs   STATUS how it ended, MESSAGE the text
            %   Outputs  none
            %   Utility  the paint half of FINISH, mirrorable for the same
            %           reason PAINT is.
            if isempty(obj.Grid) || ~isgraphics(obj.Grid), return, end
            obj.Running = false;
            obj.StopButton.Enable = 'off';

            switch status
                case "ok"
                    obj.Fill.BackgroundColor = obj.DoneColour;
                    obj.setFraction(1);
                case "cancelled"
                    obj.Fill.BackgroundColor = obj.CancelledColour;
                case "failed"
                    obj.Fill.BackgroundColor = obj.FailedColour;
            end
            if strlength(message) > 0
                obj.Label.Text = char(message);
            end
        end

        function tf = hasMirror(obj)
            %HASMIRROR Whether a live mirror bar is attached.
            %   Inputs   none
            %   Outputs  TF, logical
            %   Utility  a deleted mirror must not be painted, and checking
            %           validity here keeps that test in one place.
            tf = ~isempty(obj.Mirror) && isa(obj.Mirror, 'utils.ProgressBar') ...
                 && isscalar(obj.Mirror) && isvalid(obj.Mirror) ...
                 && obj.Mirror ~= obj;
        end

        function setFraction(obj, f)
            %SETFRACTION Move the fill by reweighting the track's two columns.
            %   Inputs   F, the fraction, clamped to [0, 1]
            %   Outputs  none
            %   Utility  uifigures have no inline bar component, so the fill is
            %           a grid weight rather than a widget property.
            f = min(max(f, 0), 1);
            obj.Shown = f;
            % Neither weight may be zero: uigridlayout rejects a '0x' column,
            % so an empty bar is a hairline and a full one has a hairline of
            % groove left at the end.
            lo = 1e-3;
            obj.Track.ColumnWidth = { ...
                sprintf('%.4fx', max(f, lo)), ...
                sprintf('%.4fx', max(1 - f, lo))};
            obj.Percent.Text = sprintf('%d%%', round(100 * f));
        end

        function onStop(obj, extra)
            %ONSTOP The Stop button's callback.
            %   Inputs   EXTRA, the callback event data
            %   Outputs  none
            %   Utility  set the cancellation flag; the run notices at its next
            %           reporting boundary, since nothing can interrupt a step
            %           already in progress.
            if ~obj.Running, return, end
            obj.Reporter.cancel();
            obj.Label.Text = 'stopping at the next boundary...';
            obj.StopButton.Enable = 'off';
            drawnow;
            if ~isempty(extra) && isa(extra, 'function_handle')
                extra();
            end
        end
    end
end
