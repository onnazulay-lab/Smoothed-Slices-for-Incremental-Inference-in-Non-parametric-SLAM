classdef SmoothedSlicesAppProgrammatic < handle
    %SMOOTHEDSLICESAPPPROGRAMMATIC Comparative posterior-recovery demonstrator.
    %
    %   Properties
    %     UIFigure, TabGroup      the window and its tabs
    %     Config, CaseData, Reference, Results, Status   what a run needs and
    %                             what it produced
    %     FigureRegistry          every axes the exporter will write
    %     the rest are the controls, grouped below by the tab they live on
    %
    %   Methods
    %     buildUI and its buildXxxTab helpers   construct the frontend
    %     loadCase, collectConfig, configForRun, selectedMethods
    %                             read the controls into a runnable state
    %     onRun, onRunSelected, executeRun      start a comparative run
    %     onRunSweep, onRunResearch, onRunSurfaceStudy, onRunActiveSetProfile,
    %     onRunPlazaLadder        start the longer studies
    %     refreshXxxTab, refreshMapViews        draw what a run produced
    %     onXxxChanged, onXxxToggled            control callbacks
    %     register, onExport, onExportFrame     the export path
    %     startTimer, stopTimer, advanceOneFrame, onPlayToggled
    %                             the increment animation
    %
    %   Utility
    %     Put the three methods side by side on one case, at matched budgets,
    %     and show what each recovered -- which is a thing no table can do.
    %
    %   The programmatic frontend preferred by specification section 7,
    %   because it is source-controllable and reviewable in a way a binary
    %   .mlapp is not.
    %
    %   TAB SCOPE. Seven of the specification's eight tabs are built:
    %   Reproducibility, Case Study, Compare Methods, Posterior Recovery,
    %   Process Explorer, Figure Generator and Diagnostics. There are no
    %   placeholders left. IMPLEMENTATION NOTES IS DROPPED rather than
    %   deferred: it was to carry equations, file provenance and per-method
    %   checklists, and each of those now lives where it cannot drift out of
    %   step with what it describes -- the equations in the function headers
    %   beside their code, the provenance in data/PROVENANCE.md, and the
    %   checklists in the test suite.
    %
    %   Two tabs are beyond the specification's eight. SWEEP, because every
    %   one of the eight shows a single run, and a single run cannot tell a
    %   method that loses to sampling noise from one that is biased -- only
    %   the trend across a grid can. PLAZA, because the real datasets are
    %   solved on a window rather than whole, and a panel that does not show
    %   which window would leave the numbers unreadable.
    %
    %   Reproducibility is section 5's "Project Setup" tab with its inventory
    %   panels removed. A health card, a table of the instruction documents
    %   and a table of the papers in Literature/ are all facts about the
    %   repository, shown to somebody who has the repository open, and none
    %   of them is a control. What the tab carries now is what a figure has
    %   to be reproduced from: the seed, the environment and the outputs.
    %
    %   All algorithm code lives under +methods, +metrics, +datasets and
    %   +viz. The callbacks here dispatch and plot; they contain no
    %   mathematics, as section 7 requires. That line is why the Compare
    %   Methods and Diagnostics tabs are thin: the cards, the budget check and
    %   the four diagnostic tables are methods.methodCard,
    %   methods.budgetComparison and methods.diagnosticsReport, which are
    %   testable without a display and are tested that way.
    %
    %   A RUN CAN BE WATCHED AND STOPPED. Both Run buttons drive a
    %   utils.ProgressBar, whose reporter is handed to the engine on
    %   config.progress; Stop cancels at the next reporting boundary and keeps
    %   whatever methods had already finished. See utils.ProgressReporter for
    %   why the bar's drawnow is the mechanism rather than a decoration.

    properties
        UIFigure
        TabGroup
        Config
        CaseData
        Reference
        Results
        Status
        FigureRegistry = struct('name', {}, 'handle', {})

        % Reproducibility
        SeedField
        VersionLabel
        FolderNoteLabel

        % Case Study
        CaseDropdown
        LayoutDropdown
        VariantDropdown
        PoseSpinner
        AxGraph
        AxBayesNet
        AxMap
        BudgetGrid
        BudgetFields = struct()
        BudgetPresetDropdown
        CaseNoteLabel
        IncrementalCheck
        SurfaceCacheCheck
        EarlyStopCheck

        % Plaza
        AxPlazaContext
        AxPlazaMarginal = gobjects(2, 3)
        PlazaLandmarkSpinner
        PlazaLadderButton
        PlazaStatusLabel
        PlazaTable
        PlazaLadder = []

        % Process Explorer
        IncrementSlider
        IncrementLabel
        StageSlider
        StageLabel
        MethodSelector
        PlayButton
        FrameButton
        AxProcessMap
        AxProcessGraph
        AxProcessBayes
        AxProcessStage
        ProcessEquation
        ProcessCard
        Timer
        IsBusy = false

        % Posterior Recovery
        AxEstimator
        AxMarginal
        AxSurface
        AxSamples
        AxCardinality
        MetricsTable
        RunButton
        ExportButton
        StatusLabel
        RunProgress

        % Compare Methods
        MethodChecks = struct()
        MethodStatusLabels = struct()
        CompareRunButton
        CompareProgress
        CompareStatusLabel
        BudgetTable
        BudgetNoteLabel
        RuntimeTable

        % Diagnostics
        DiagRuntimeTable
        DiagAccuracyTable
        DiagReplayTable
        DiagWarnings
        DiagNoteLabel

        % Sweep
        %SWEEPRESULT The last sweep, kept apart from app.Results on purpose.
        %   A sweep runs two dozen cases; app.Results is ONE case's methods and
        %   every panel on every other tab reads it. Writing a sweep into it
        %   would leave the Posterior Recovery tab drawing the last cell of the
        %   grid as though it were the case the user had selected.
        SweepResult = struct('rows', struct([]))
        SweepRunButton
        SweepProgress
        SweepStatusLabel
        SweepTable
        SweepAxes = struct()
        SweepPanels = struct()
        SweepNoteLabel
        SweepPlanDropdown
        %SWEEPKIND Which plan produced app.SweepResult, not which is selected.
        %   The panels are drawn from the RESULT, so they have to follow the
        %   plan that was run. Reading the dropdown instead would relabel a
        %   drawn sweep the moment the selection changed, leaving two-pose
        %   curves under grid-world axis titles.
        SweepKind = "two-pose"

        % Research Question
        ResearchResult = struct('rows', struct([]))
        ResearchRunButton
        ResearchProgress
        ResearchStatusLabel
        ResearchScenarioDropdown
        ResearchTable
        ResearchNoteLabel
        AxResearchCost
        AxResearchGrowth

        % Surface Complexity -- the research sheet's E2. The tab above asks
        % whether the method saved anything; this one asks whether the reason
        % it would is true, which is the "if" of the sheet's own hypothesis.
        SurfaceStudy = []
        SurfaceProfile = []
        SurfaceStudyButton
        SurfaceProfileButton
        SurfaceProgress
        SurfaceStatusLabel
        SurfaceAxisDropdown
        SurfaceTable
        SurfaceNoteLabel
        AxSurfaceSpectrum
        AxSurfaceRank
        AxSurfaceActiveSet

        % Figure Generator. The export machinery already existed and was
        % reachable only from one toolbar button, so what this tab adds is
        % not the ability to export but the ability to SEE what an export
        % would contain before spending minutes on it.
        FigGenTable
        FigGenFormat
        FigGenBundleList
        FigGenExportButton
        FigGenRefreshButton
        FigGenStatusLabel
    end

    properties (Constant, Access = private)
        %ITERATIONLABEL What this build is, in ONE place.
        %   Three run bars carry this label and two of them still said
        %   "iteration 3" while the third said 4 -- each was typed where its
        %   tab was built and none was revisited. A label a reader takes as
        %   the app's version cannot be maintained in three places.
        IterationLabel = "iteration 5"
    end

    methods
        function app = SmoothedSlicesAppProgrammatic()
            %SMOOTHEDSLICESAPPPROGRAMMATIC Build the window; load a case.
            %   Inputs   none
            %   Outputs  APP, with every tab built and a case loaded
            %   Utility  open the app in a state that can be run without
            %           touching a control first.
            app.Config = methods.commonMethodConfig();
            app.Status = utils.validateProjectTree();
            app.buildUI();
            app.loadCase();
        end

        function delete(app)
            %DELETE Tear down the timer and the figure this object owns.
            %   Inputs   none
            %   Outputs  none
            %   Utility  a handle class holding a timer must stop it, or the
            %           callback outlives the window.
            %
            % The timer holds a reference to the app and keeps firing at a
            % deleted figure otherwise, which is the classic way a closed
            % App Designer app goes on throwing errors into the console.
            app.stopTimer();
            if ~isempty(app.UIFigure) && isgraphics(app.UIFigure)
                delete(app.UIFigure);
            end
        end

        function sel = selectedMethods(app)
            %SELECTEDMETHODS The methods ticked on the Compare Methods tab.
            %   Inputs   none
            %   Outputs  SEL, the method names, in the run order
            %   Utility  read the tick boxes once, so no two callers disagree
            %           about what was asked for.
            %
            %   Public because it is a question the app can be asked, with no
            %   side effects, and because a test that has to press Run Selected
            %   to find out which methods were selected has to run them.
            %
            %   Returned in runComparison's own order rather than in the order
            %   of the cards, so that a partial selection produces the same
            %   rows in the same sequence as the full run it is a subset of.
            sel = string.empty(1, 0);
            for m = ["Slices", "NF-iSAM", "Smoothed Slices"]
                key = matlab.lang.makeValidName(m);
                if isfield(app.MethodChecks, key) && app.MethodChecks.(key).Value
                    sel(end+1) = m; %#ok<AGROW>
                end
            end
        end

        function cfg = configForRun(app)
            %CONFIGFORRUN The config a run started now would receive.
            %   Inputs   none
            %   Outputs  CFG, the config a run started now would receive
            %   Utility  let a panel show the settings without starting
            %           anything.
            %
            %   Inputs   none
            %   Outputs  CFG, the collected config including budgetPreset
            %   Utility  answer what the panel currently amounts to, without
            %
            %            running anything.
            %
            %   Public for the same reason selectedMethods is: it is a question
            %   with no side effects, and the alternative is a test that has to
            %   press Run and wait out three methods to find out which budget
            %   the run would have used.
            cfg = app.collectConfig();
        end

        function applyBudgetPreset(app, name)
            %APPLYBUDGETPRESET Set every budget field from a named preset.
            %   Inputs   NAME, the preset
            %   Outputs  none
            %   Utility  move every budget field together, since a half-applied
            %           preset is not a preset.
            %
            %   Inputs   NAME  "paperLike" | "appFast"
            %   Outputs  none; the dropdown and the seven fields are rewritten
            %   Utility  the dropdown's own callback, and the way a caller asks
            %
            %            for a whole budget instead of seven numbers.
            %
            %   THE FIELDS ARE REWRITTEN RATHER THAN BYPASSED, and that is the
            %   point. collectConfig layers the fields on top of the preset, so
            %   leaving them showing the paper's numbers while the preset said
            %   appFast would have the fields silently win and the dropdown
            %   would do nothing. Rewriting them also means the reduction is on
            %   screen: picking appFast visibly changes |X_0| from 200 to 60
            %   rather than changing the run in a way the panel denies.
            %
            %   Public because it is how a test asks for a cheap run without
            %   reaching into a private callback, and because it is a coherent
            %   thing to ask the app to do.
            arguments
                app
                name (1,1) string {mustBeMember(name, ["paperLike", "appFast"])}
            end

            cfg = methods.configPreset(name);
            app.BudgetPresetDropdown.Value = char(name);

            for f = string(fieldnames(app.BudgetFields))'
                v = cfg.(f);
                % activeSetSize is Inf by default and the field is numeric with
                % a finite limit, so it is shown as the full path support --
                % which selects the same dense update, because K >= B_1 takes
                % buildActiveSuccessors' dense branch.
                if isinf(v), v = cfg.surfaceSupportSize; end
                app.BudgetFields.(f).Value = v;
            end
        end
    end

    % =====================================================================
    % Construction
    % =====================================================================
    methods (Access = private)

        function buildUI(app)
            %BUILDUI The window, the tab group and every tab in it.
            %   Inputs   none
            %   Outputs  none
            %   Utility  assemble the frontend in one place, in tab order.
            app.UIFigure = uifigure('Name', 'Smoothed Slices - comparative posterior recovery', ...
                'Position', [80 60 1360 860], 'Color', [1 1 1]);

            outer = uigridlayout(app.UIFigure, [1 1]);
            outer.Padding = [8 8 8 8];

            app.TabGroup = uitabgroup(outer);
            app.buildProjectSetupTab();
            app.buildCaseStudyTab();
            app.buildCompareMethodsTab();
            app.buildPosteriorRecoveryTab();
            app.buildProcessExplorerTab();
            app.buildPlazaTab();
            app.buildSweepTab();
            app.buildResearchTab();
            app.buildSurfaceComplexityTab();
            app.buildFigureGeneratorTab();
            app.buildDiagnosticsTab();
        end

        % -----------------------------------------------------------------
        function buildProjectSetupTab(app)
            %BUILDPROJECTSETUPTAB Everything a run needs to be reproduced.
            %   Inputs   none
            %   Outputs  none
            %   Utility  show what a figure has to be reproduced from: the seed,
            %           the environment and the outputs.
            %
            %   This tab used to be a project inventory: a health card, a
            %   table of the instruction documents and a table of the papers
            %   in Literature/. None of that is a control and none of it
            %   changes between sessions -- it restated the repository layout
            %   to someone who already has the repository open. What is left
            %   is the part a reader of a figure actually needs in order to
            %   get the same figure back: the seed, the environment the
            %   numbers were produced in, and where the outputs land.
            tab = uitab(app.TabGroup, 'Title', 'Reproducibility');
            g = uigridlayout(tab, [3 1]);
            g.RowHeight   = {150, 150, '1x'};
            g.ColumnWidth = {'1x'};

            % --- Run identity ---------------------------------------------
            runPanel = uipanel(g, 'Title', 'Run identity');
            runPanel.Layout.Row = 1;
            rg = uigridlayout(runPanel, [4 2]);
            rg.ColumnWidth = {200, '1x'};
            rg.RowHeight   = {26, 26, 26, 26};

            % The seed is the only editable field on the tab, and it is the
            % one that matters: every case draws its measurement noise from
            % a stream seeded here, so two runs at the same seed are the
            % same experiment and two runs at different seeds are not.
            uilabel(rg, 'Text', 'random seed');
            app.SeedField = uieditfield(rg, 'numeric', 'Value', app.Config.seed, ...
                'Limits', [0 Inf], 'RoundFractionalValues', 'on');

            uilabel(rg, 'Text', 'MATLAB release');
            app.VersionLabel = uilabel(rg, 'Text', version('-release'));

            uilabel(rg, 'Text', 'platform');
            uilabel(rg, 'Text', sprintf('%s (%s)', computer('arch'), computer));

            uilabel(rg, 'Text', 'RNG for measurement noise');
            uilabel(rg, 'Text', 'threefry, one stream per case');

            % --- Output folders -------------------------------------------
            outPanel = uipanel(g, 'Title', 'Output folders');
            outPanel.Layout.Row = 2;
            og = uigridlayout(outPanel, [3 2]);
            og.ColumnWidth = {200, '1x'};
            og.RowHeight   = {26, 26, 26};

            uilabel(og, 'Text', 'results');
            uilabel(og, 'Text', app.Status.resultsDir);

            uilabel(og, 'Text', 'presentation');
            uilabel(og, 'Text', app.Status.presentationDir);

            % Reported rather than assumed: on a fresh clone results/ and
            % data/ do not exist and were created a moment ago, and knowing
            % that is the difference between an empty folder and a bug.
            uilabel(og, 'Text', 'created this session');
            app.FolderNoteLabel = uilabel(og, ...
                'Text', utils.createdFolderText(app.Status));

            % --- Note ------------------------------------------------------
            notePanel = uipanel(g, 'Title', 'What a reproduction needs');
            notePanel.Layout.Row = 3;
            ng = uigridlayout(notePanel, [1 1]);
            % No \texttt here: MATLAB's LaTeX interpreter swallows the space
            % that follows a closing brace, so mid-sentence macros run their
            % neighbouring words together.
            utils.latexLabel(ng, ...
                "A figure is reproducible from the seed above plus the case " + ...
                "settings and method budgets shown on the Case Study tab. " + ...
                "Method budgets are \textbf{not} shared with the noise " + ...
                "stream, so changing a sample count changes the estimate " + ...
                "and never the data it is estimating from.");
        end

        % -----------------------------------------------------------------
        function buildCaseStudyTab(app)
            %BUILDCASESTUDYTAB The case, its controls and the two map views.
            %   Inputs   none
            %   Outputs  none
            %   Utility  let a case be chosen, configured and looked at before
            %           it is run.
            tab = uitab(app.TabGroup, 'Title', 'Case Study');
            g = uigridlayout(tab, [1 2]);
            g.ColumnWidth = {380, '1x'};

            % --- Left: selector and budgets -------------------------------
            % The Dataset panel gained a fourth row when the pose spinner
            % arrived and kept its old height, which clipped the case note off
            % the bottom. 196 is what four 26-pixel rows, a title and the two
            % lines the grid world's note wraps to actually need.
            left = uigridlayout(g, [4 1]);
            left.RowHeight = {226, '1x', 92, 120};

            selPanel = uipanel(left, 'Title', 'Dataset');
            sg = uigridlayout(selPanel, [5 2]);
            sg.ColumnWidth = {110, '1x'};
            sg.RowHeight = {26, 26, 26, 26, '1x'};

            uilabel(sg, 'Text', 'case');
            app.CaseDropdown = uidropdown(sg, ...
                'Items', {'Two-pose range', 'Four Doors', 'Grid world', ...
                          'Plaza1', 'Plaza2'}, ...
                'Value', 'Two-pose range', ...
                'ValueChangedFcn', @(~,~) app.onCaseChanged());

            uilabel(sg, 'Text', 'variant');
            app.VariantDropdown = uidropdown(sg, ...
                'Items', {'gaussian', 'multimodal'}, 'Value', 'gaussian', ...
                'ValueChangedFcn', @(~,~) app.onVariantChanged());

            % The layout is a grid-world control and is disabled elsewhere,
            % like the pose spinner beside it. It changes the map, the route
            % AND the sensor range together, because those three are one
            % decision: see datasets.gridWorldDefaults.
            uilabel(sg, 'Text', 'layout');
            app.LayoutDropdown = uidropdown(sg, ...
                'Items', {'office', 'corridor', 'warehouse'}, ...
                'Value', 'office', 'Enable', 'off', ...
                'ValueChangedFcn', @(~,~) app.onLayoutChanged());

            uilabel(sg, 'Text', 'poses');
            app.PoseSpinner = uispinner(sg, 'Value', 5, 'Limits', [3 16], ...
                'Step', 1, 'RoundFractionalValues', 'on', 'Enable', 'off', ...
                'ValueChangedFcn', @(~,~) app.onVariantChanged());

            app.CaseNoteLabel = utils.latexLabel(sg, ...
                "$x_1 \rightarrow l_1 \rightarrow x_2$, order $(x_1, l_1, x_2)$");
            app.CaseNoteLabel.Layout.Row = 5;
            app.CaseNoteLabel.Layout.Column = [1 2];

            budgetPanel = uipanel(left, 'Title', 'Budgets (matched across methods)');
            app.BudgetGrid = uigridlayout(budgetPanel, [8 2]);
            app.BudgetGrid.ColumnWidth = {'1x', 90};
            app.buildBudgetFields();

            % --- Incremental replay ---------------------------------------
            % Off by default, because every number this project has reported
            % was measured on the batch pass and a checkbox that silently
            % changed the reference would make two runs incomparable without
            % saying so. The two reuse rules are separate boxes: they cut
            % opposite ends of the pass and each is worth being able to turn
            % off on its own when reading what the other did.
            replayPanel = uipanel(left, 'Title', 'Incremental replay');
            rg = uigridlayout(replayPanel, [3 1]);
            rg.RowHeight = {22, 22, 22};
            rg.Padding = [8 2 4 2];
            rg.RowSpacing = 2;
            app.IncrementalCheck = uicheckbox(rg, 'Value', false, ...
                'Text', 'replay increment by increment', ...
                'ValueChangedFcn', @(~,~) app.onReplayToggled());
            app.SurfaceCacheCheck = uicheckbox(rg, 'Value', true, ...
                'Text', 'reuse surfaces across increments', 'Enable', 'off');
            app.EarlyStopCheck = uicheckbox(rg, 'Value', true, ...
                'Text', 'MMD early stopping (Alg. S5)', 'Enable', 'off');

            eqPanel = uipanel(left, 'Title', 'Target');
            eg = uigridlayout(eqPanel, [1 1]);
            utils.latexLabel(eg, ...
                "$f_{\mathrm{new}}(x_2 \mid D_2) = \int\!\!\int f(x_1) f(x_1,x_2) f(x_1,l_1) f(l_1,x_2)\, dl_1\, dx_1$", ...
                [], 'FontSize', 13);

            % --- Right: the world, and the graph it induces ---------------
            right = uigridlayout(g, [2 1]);
            right.RowHeight = {'1.4x', '1x'};

            mp = uipanel(right, 'Title', 'Map: blocks, beacons, mission, explored grid');
            app.AxMap = uiaxes(uigridlayout(mp, [1 1]));
            app.register('map_current_increment', app.AxMap);

            % The factor graph and the Bayes net side by side, on the same
            % layout. Elimination is a translation between the two and the
            % pair is what shows it: what is deleted on the left is what is
            % created on the right.
            gg = uigridlayout(right, [1 2]);
            gg.Padding = [0 0 0 0];
            gg.ColumnSpacing = 4;

            gp = uipanel(gg, 'Title', 'Factor graph, reduced to this step');
            app.AxGraph = uiaxes(uigridlayout(gp, [1 1]));
            app.register('case_factor_graph', app.AxGraph);

            bp = uipanel(gg, 'Title', 'Bayes net (variable elimination)');
            app.AxBayesNet = uiaxes(uigridlayout(bp, [1 1]));
            app.register('case_bayes_net', app.AxBayesNet);
        end

        function buildBudgetFields(app)
            %BUILDBUDGETFIELDS The budget spinners and their preset.
            %   Inputs   none
            %   Outputs  none
            %   Utility  keep every budget in one panel, because the comparison
            %           is only meaningful when they match.
            %
            % The preset comes FIRST because it moves the seven fields below
            % it. Two of the knobs that matter most to the wall clock --
            % nfisamTrainSamples and the flow iteration cap -- have no field
            % here and never did, so before the preset existed there was no
            % way at all to make a run in this app cheap: turning the outer
            % samples down left one flow per clique training at the paper's
            % n_train = 2000 regardless, which is most of the time a Run All
            % takes. That is what the preset reaches and the fields cannot.
            lbl = uilabel(app.BudgetGrid, 'Text', 'budget preset');
            lbl.Layout.Row = 1; lbl.Layout.Column = 1;
            app.BudgetPresetDropdown = uidropdown(app.BudgetGrid, ...
                'Items', {'paperLike', 'appFast'}, 'Value', 'paperLike', ...
                'ValueChangedFcn', @(~,~) app.applyBudgetPreset( ...
                                        string(app.BudgetPresetDropdown.Value)));
            app.BudgetPresetDropdown.Layout.Row = 1;
            app.BudgetPresetDropdown.Layout.Column = 2;

            specs = { ...
                'numSamples',           "$|\mathcal{X}_0|$ outer samples"; ...
                'numInnerSamples',      "$|L_n|$ nested inner samples"; ...
                'separatorSupportSize', "$|\mathcal{S}|$ separator support"; ...
                'surfaceSupportSize',   "$|\mathcal{X}_1|$ RCS path support"; ...
                'activeSetSize',        "$|\mathcal{N}_0|$ active successors"; ...
                'numBackwardSamples',   "backward separator samples"; ...
                'marginalGridSize',     "marginal grid"};

            blue = utils.cardinalityColor();
            for i = 1:size(specs, 1)
                f = specs{i,1};
                row = i + 1;
                utils.latexLabel(app.BudgetGrid, specs{i,2}, ...
                    struct('Row', row, 'Column', 1), 'FontColor', blue, 'FontSize', 12);
                v = app.Config.(f);
                if isinf(v), v = app.Config.surfaceSupportSize; end
                fld = uieditfield(app.BudgetGrid, 'numeric', 'Value', v, ...
                    'Limits', [1 Inf], 'RoundFractionalValues', 'on');
                fld.Layout.Row = row; fld.Layout.Column = 2;
                app.BudgetFields.(f) = fld;
            end
        end

        % -----------------------------------------------------------------
        function buildCompareMethodsTab(app)
            %BUILDCOMPAREMETHODSTAB Cards, budget check, metrics table.
            %   Inputs   none
            %   Outputs  none
            %   Utility  say what the methods are before the run, and how they
            %           did after it.
            %
            % Specification section 5's third tab: what the three methods ARE,
            % which of them to run, and whether the run they just did was
            % actually comparable.
            %
            % The cards are filled from methods.methodCard before anything has
            % run, because the one moment this tab exists for is the moment
            % somebody is deciding which methods to spend minutes on.
            tab = uitab(app.TabGroup, 'Title', 'Compare Methods');
            g = uigridlayout(tab, [2 2]);
            g.RowHeight   = {92, '1x'};
            g.ColumnWidth = {440, '1x'};

            ctrl = uigridlayout(g, [2 3]);
            ctrl.Layout.Row = 1; ctrl.Layout.Column = [1 2];
            ctrl.ColumnWidth = {170, '1x', 120};
            ctrl.RowHeight = {26, 26};
            ctrl.Padding = [0 0 0 0];
            ctrl.RowSpacing = 6;

            app.CompareRunButton = uibutton(ctrl, 'Text', 'Run Selected', ...
                'ButtonPushedFcn', @(~,~) app.onRunSelected());
            app.CompareRunButton.Layout.Row = 1;
            app.CompareRunButton.Layout.Column = 1;

            app.CompareStatusLabel = uilabel(ctrl, ...
                'Text', 'tick the methods to run, then press Run Selected');
            app.CompareStatusLabel.Layout.Row = 1;
            app.CompareStatusLabel.Layout.Column = 2;

            it = uilabel(ctrl, 'Text', char(app.IterationLabel), 'FontAngle', 'italic', ...
                'HorizontalAlignment', 'right');
            it.Layout.Row = 1; it.Layout.Column = 3;

            app.CompareProgress = utils.ProgressBar(ctrl, 'IdleText', "ready");
            app.CompareProgress.Grid.Layout.Row = 2;
            app.CompareProgress.Grid.Layout.Column = [1 3];

            % --- The cards -------------------------------------------------
            cards = uigridlayout(g, [3 1]);
            cards.Layout.Row = 2; cards.Layout.Column = 1;
            cards.RowHeight = {'1x', '1x', '1x'};
            cards.Padding = [0 0 0 0];

            names = ["Slices", "Smoothed Slices", "NF-iSAM"];
            for i = 1:numel(names)
                app.buildMethodCard(cards, names(i), i);
            end

            % --- Budgets and runtime ---------------------------------------
            right = uigridlayout(g, [2 1]);
            right.Layout.Row = 2; right.Layout.Column = 2;
            right.RowHeight = {'1.4x', '1x'};
            right.Padding = [0 0 0 0];

            bp = uipanel(right, 'Title', 'Budgets, as each method actually used them');
            bg = uigridlayout(bp, [2 1]);
            bg.RowHeight = {'1x', 72};
            app.BudgetTable = uitable(bg, 'RowName', {}, ...
                'ColumnName', {'quantity'}, 'Data', cell(0, 1));
            app.BudgetNoteLabel = uilabel(bg, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', ...
                'Text', ['These are read back off each result, not off the ' ...
                         'config that was sent in: a method is free to change ' ...
                         'its copy, and one of them does.']);

            rp = uipanel(right, 'Title', 'Runtime and what it was spent on');
            rg = uigridlayout(rp, [1 1]);
            app.RuntimeTable = uitable(rg, 'RowName', {}, 'Data', cell(0, 1));
        end

        function buildMethodCard(app, parent, name, row)
            %BUILDMETHODCARD One method, described before it has run.
            %   Inputs   PARENT the container, NAME the method, ROW where to
            %           place it
            %   Outputs  none
            %   Utility  draw one card from methods.methodCard, which holds the
            %           text.
            card = methods.methodCard(name);
            key = matlab.lang.makeValidName(name);

            panel = uipanel(parent, 'Title', char(name));
            panel.Layout.Row = row; panel.Layout.Column = 1;
            cg = uigridlayout(panel, [4 1]);
            cg.RowHeight = {24, 32, '1x', 20};
            cg.Padding = [8 4 8 4];
            cg.RowSpacing = 2;

            app.MethodChecks.(key) = uicheckbox(cg, 'Value', true, ...
                'Text', sprintf('include  (%s)', card.spec));

            % Our extension is marked wherever a number from it is shown, per
            % specification section 17, and the card is the first such place.
            origin = uilabel(cg, 'WordWrap', 'on', 'FontAngle', 'italic', ...
                'VerticalAlignment', 'top', ...
                'Text', char(card.origin + " -- " + card.basedOn));
            if card.notInPaper
                origin.FontColor = [0.65 0.33 0.00];
            end

            uilabel(cg, 'WordWrap', 'on', 'VerticalAlignment', 'top', ...
                'Text', char(card.produces + " " + card.innerCost));

            app.MethodStatusLabels.(key) = uilabel(cg, 'Text', 'not run', ...
                'FontColor', [0.40 0.40 0.40]);
        end

        % -----------------------------------------------------------------
        function buildPosteriorRecoveryTab(app)
            %BUILDPOSTERIORRECOVERYTAB The estimators, marginals and samples.
            %   Inputs   none
            %   Outputs  none
            %   Utility  show whether each method recovered the posterior, which
            %           is the whole question.
            tab = uitab(app.TabGroup, 'Title', 'Posterior Recovery');
            g = uigridlayout(tab, [3 3]);
            g.RowHeight   = {92, '1x', '1x'};
            g.ColumnWidth = {'1x', '1x', '1x'};

            % --- Controls --------------------------------------------------
            % Two rows: the buttons, and under them the progress strip. The
            % strip is not hidden between runs -- a control that appears only
            % while it is needed cannot be found before it is needed, and Stop
            % is the one control a user looks for having already started.
            ctrl = uigridlayout(g, [2 4]);
            ctrl.Layout.Row = 1; ctrl.Layout.Column = [1 3];
            ctrl.ColumnWidth = {150, 240, '1x', 120};
            ctrl.RowHeight = {26, 26};
            ctrl.Padding = [0 0 0 0];
            ctrl.RowSpacing = 6;

            app.RunButton = uibutton(ctrl, 'Text', 'Run All', ...
                'ButtonPushedFcn', @(~,~) app.onRun());
            app.ExportButton = uibutton(ctrl, ...
                'Text', 'Export All Figures + Diagnostics', ...
                'ButtonPushedFcn', @(~,~) app.onExport(), 'Enable', 'off');
            app.StatusLabel = uilabel(ctrl, 'Text', 'ready');
            uilabel(ctrl, 'Text', char(app.IterationLabel), 'FontAngle', 'italic', ...
                'HorizontalAlignment', 'right');

            app.RunProgress = utils.ProgressBar(ctrl, 'IdleText', "ready");
            app.RunProgress.Grid.Layout.Row = 2;
            app.RunProgress.Grid.Layout.Column = [1 4];

            % --- Figures ---------------------------------------------------
            p1 = uipanel(g, 'Title', 'Generated factor versus exact quadrature');
            p1.Layout.Row = 2; p1.Layout.Column = [1 2];
            app.AxEstimator = uiaxes(uigridlayout(p1, [1 1]));
            app.register('estimator_vs_reference', app.AxEstimator);

            p2 = uipanel(g, 'Title', 'Marginal');
            p2.Layout.Row = 2; p2.Layout.Column = 3;
            app.AxMarginal = uiaxes(uigridlayout(p2, [1 1]));
            app.register('marginal_x_compare', app.AxMarginal);

            p3 = uipanel(g, 'Title', 'Conditional smoothing surface (Smoothed Slices)');
            p3.Layout.Row = 3; p3.Layout.Column = 1;
            app.AxSurface = uiaxes(uigridlayout(p3, [1 1]));
            app.register('smoothed_surface_step', app.AxSurface);

            p4 = uipanel(g, 'Title', 'Joint posterior samples');
            p4.Layout.Row = 3; p4.Layout.Column = 2;
            app.AxSamples = uiaxes(uigridlayout(p4, [1 1]));
            app.register('posterior_samples_compare', app.AxSamples);

            p5 = uipanel(g, 'Title', 'Metrics and cardinalities');
            p5.Layout.Row = 3; p5.Layout.Column = 3;
            pg = uigridlayout(p5, [2 1]);
            pg.RowHeight = {'1x', '1x'};
            app.MetricsTable = uitable(pg, 'RowName', {}, ...
                'ColumnWidth', {110, 100, 80, 80, 80});
            app.AxCardinality = uiaxes(pg);
            app.register('cardinality_diagnostics', app.AxCardinality);
        end

        % -----------------------------------------------------------------
        function buildProcessExplorerTab(app)
            %BUILDPROCESSEXPLORERTAB The stage slider, graphs and card.
            %   Inputs   none
            %   Outputs  none
            %   Utility  let the elimination be stepped through rather than
            %           described.
            %
            % Specification section 10. The educational panel: the user drags
            % through the internal computation rather than viewing the final
            % output. Two sliders, because the process has two independent
            % axes -- which increment of data has arrived, and how far the
            % elimination has got within it.
            tab = uitab(app.TabGroup, 'Title', 'Process Explorer');
            g = uigridlayout(tab, [3 3]);
            g.RowHeight   = {96, '1x', '1x'};
            g.ColumnWidth = {'1x', '1x', '1x'};

            ctrl = uipanel(g, 'Title', 'Timeline');
            ctrl.Layout.Row = 1; ctrl.Layout.Column = [1 3];
            cg = uigridlayout(ctrl, [2 6]);
            cg.ColumnWidth = {150, '1x', 150, '1x', 90, 110};
            cg.RowHeight = {'1x', '1x'};

            app.IncrementLabel = uilabel(cg, 'Text', 'increment k = 1');
            app.IncrementSlider = uislider(cg, 'Limits', [1 2], 'Value', 1, ...
                'MajorTicks', [1 2], ...
                'ValueChangedFcn', @(~,~) app.onProcessChanged(), ...
                'ValueChangingFcn', @(~,e) app.onIncrementChanging(e));

            app.StageLabel = uilabel(cg, 'Text', 'stage 1');
            app.StageSlider = uislider(cg, 'Limits', [1 2], 'Value', 1, ...
                'MajorTicks', [1 2], ...
                'ValueChangedFcn', @(~,~) app.onProcessChanged());

            app.PlayButton = uibutton(cg, 'state', 'Text', 'Play', ...
                'ValueChangedFcn', @(src,~) app.onPlayToggled(src));
            app.FrameButton = uibutton(cg, 'Text', 'Export frame', ...
                'ButtonPushedFcn', @(~,~) app.onExportFrame());

            app.MethodSelector = uidropdown(cg, ...
                'Items', {'Compare', 'Slices', 'Smoothed Slices', 'NF-iSAM'}, ...
                'Value', 'Compare', ...
                'ValueChangedFcn', @(~,~) app.onProcessChanged());
            app.MethodSelector.Layout.Row = 2;
            app.MethodSelector.Layout.Column = 5;

            % --- Panels ----------------------------------------------------
            p1 = uipanel(g, 'Title', 'Map at this increment');
            p1.Layout.Row = 2; p1.Layout.Column = [1 2];
            app.AxProcessMap = uiaxes(uigridlayout(p1, [1 1]));
            app.register('process_map_step', app.AxProcessMap);

            p2 = uipanel(g, 'Title', 'Factor graph at this elimination step');
            p2.Layout.Row = 2; p2.Layout.Column = 3;
            app.AxProcessGraph = uiaxes(uigridlayout(p2, [1 1]));
            app.register('process_factor_graph_step', app.AxProcessGraph);

            p3 = uipanel(g, 'Title', 'Stage diagnostics');
            p3.Layout.Row = 3; p3.Layout.Column = 1;
            app.AxProcessStage = uiaxes(uigridlayout(p3, [1 1]));
            app.register('process_stage_diagnostics', app.AxProcessStage);

            p3b = uipanel(g, 'Title', 'Bayes net built so far');
            p3b.Layout.Row = 3; p3b.Layout.Column = 2;
            app.AxProcessBayes = uiaxes(uigridlayout(p3b, [1 1]));
            app.register('process_bayes_net_step', app.AxProcessBayes);

            p4 = uipanel(g, 'Title', 'What this stage computes');
            p4.Layout.Row = 3; p4.Layout.Column = 3;
            eg = uigridlayout(p4, [2 1]);
            eg.RowHeight = {'1x', '1x'};
            app.ProcessEquation = utils.latexLabel(eg, ...
                "press \textbf{Run All} on the Posterior Recovery tab", ...
                [], 'FontSize', 12);
            app.ProcessCard = utils.latexLabel(eg, "", [], 'FontSize', 11);
        end

        % -----------------------------------------------------------------
        function buildSweepTab(app)
            %BUILDSWEEPTAB The trend, rather than the single comparison.
            %   Inputs   none
            %   Outputs  none
            %   Utility  a single run cannot tell sampling noise from bias; only
            %           the trend across a grid can.
            %
            %   Every other tab in this app shows ONE run: one case, one set
            %   of budgets, three methods. That answers "which method won
            %   here", which is a fact about the cell and not about the
            %   methods. This tab runs the grid and plots the curves, which
            %   is where the difference between "loses to sampling noise"
            %   and "is biased" actually becomes visible.
            %
            %   IT IS A SEPARATE RUN PATH, not a Run All in a loop. The
            %   sweep's results live in app.SweepResult and touch nothing
            %   else, because the panels on every other tab read app.Results
            %   and a sweep would leave them drawing the last cell of the
            %   grid as though the user had selected it.
            tab = uitab(app.TabGroup, 'Title', 'Sweep');
            g = uigridlayout(tab, [3 1]);
            g.RowHeight   = {76, '1x', 150};
            g.ColumnWidth = {'1x'};

            % --- Controls --------------------------------------------------
            ctrl = uigridlayout(g, [2 4]);
            ctrl.Layout.Row = 1;
            ctrl.ColumnWidth = {150, 210, '1x', 120};
            ctrl.RowHeight   = {26, 26};
            ctrl.Padding     = [0 0 0 0];
            ctrl.RowSpacing  = 6;

            app.SweepRunButton = uibutton(ctrl, 'Text', 'Run Sweep', ...
                'ButtonPushedFcn', @(~,~) app.onRunSweep());
            app.SweepRunButton.Layout.Row = 1;
            app.SweepRunButton.Layout.Column = 1;

            % ONE TAB, THREE GRIDS. Each case study asks a different question
            % of a sweep and so sweeps a different axis: the two-pose grid
            % varies the budget and the mixture separation, Four Doors varies
            % the door spacing and the odometry, the grid world varies the
            % problem SIZE at a fixed budget. Three tabs would have triplicated
            % the run path, the table and the progress bar to vary a plan.
            app.SweepPlanDropdown = uidropdown(ctrl, ...
                'Items', {'Two-pose range: budget and ambiguity', ...
                          'Four Doors: spacing and odometry', ...
                          'Grid world: problem size'}, ...
                'ItemsData', {'two-pose', 'four-doors', 'grid-world'}, ...
                'Value', 'two-pose', ...
                'ValueChangedFcn', @(~,~) app.onSweepPlanChanged());
            app.SweepPlanDropdown.Layout.Row = 1;
            app.SweepPlanDropdown.Layout.Column = 2;

            app.SweepStatusLabel = uilabel(ctrl, 'Text', '');
            app.SweepStatusLabel.Layout.Row = 1;
            app.SweepStatusLabel.Layout.Column = 3;

            it = uilabel(ctrl, 'Text', char(app.IterationLabel), 'FontAngle', 'italic', ...
                'HorizontalAlignment', 'right');
            it.Layout.Row = 1; it.Layout.Column = 4;

            app.SweepProgress = utils.ProgressBar(ctrl, 'IdleText', "not run");
            app.SweepProgress.Grid.Layout.Row = 2;
            app.SweepProgress.Grid.Layout.Column = [1 4];

            % --- The curves ------------------------------------------------
            % Six panels, titled and filled by the plan that ran. They are
            % created once and RETITLED rather than rebuilt, because rebuilding
            % would invalidate every registered axes handle and the figure
            % export registry with them.
            panels = uigridlayout(g, [2 3]);
            panels.Layout.Row = 2;
            panels.Padding = [0 0 0 0];

            for i = 1:6
                key = "p" + i;
                p = uipanel(panels, 'Title', '');
                ax = uiaxes(uigridlayout(p, [1 1]));
                app.SweepPanels.(key) = p;
                app.SweepAxes.(key) = ax;
                app.register("sweep_" + key, ax);
            end

            % --- The rows --------------------------------------------------
            bottom = uigridlayout(g, [1 2]);
            bottom.Layout.Row = 3;
            bottom.ColumnWidth = {'2.2x', '1x'};
            bottom.Padding = [0 0 0 0];

            tp = uipanel(bottom, 'Title', 'Every measurement, one row per cell and method');
            app.SweepTable = uitable(uigridlayout(tp, [1 1]), ...
                'RowName', {}, 'Data', cell(0, 1));

            np = uipanel(bottom, 'Title', 'How to read these curves');
            app.SweepNoteLabel = uilabel(uigridlayout(np, [1 1]), ...
                'WordWrap', 'on', 'VerticalAlignment', 'top', 'Text', '');

            app.onSweepPlanChanged();
        end

        % -----------------------------------------------------------------
        function onSweepPlanChanged(app)
            %ONSWEEPPLANCHANGED Retitle for the selected plan; draw nothing.
            %   Inputs   none
            %   Outputs  none
            %   Utility  retitle without drawing, since changing the plan does
            %           not run it.
            %
            %   Changing the selection states what the NEXT run will cost and
            %   what it will measure. It deliberately does not touch the
            %   panels: they belong to the sweep that ran, and clearing them
            %   on a selection change would throw away a twenty-minute result
            %   because somebody read the dropdown.
            kind = app.selectedSweepKind();
            spec = app.sweepPlanSpec(kind);

            app.SweepStatusLabel.Text = sprintf( ...
                '%d cells x 3 methods, roughly %d min. Stop keeps the cells that finished.', ...
                spec.numCells, round(spec.numCells * spec.secondsPerCell / 60));
            app.SweepNoteLabel.Text = spec.note;
        end

        function kind = selectedSweepKind(app)
            %SELECTEDSWEEPKIND Which sweep plan the dropdown is on.
            %   Inputs   none
            %   Outputs  KIND, the plan name
            %   Utility  read the dropdown in one place.
            kind = "two-pose";
            if ~isempty(app.SweepPlanDropdown) && isgraphics(app.SweepPlanDropdown)
                kind = string(app.SweepPlanDropdown.Value);
            end
        end

        function spec = sweepPlanSpec(~, kind)
            %SWEEPPLANSPEC What a plan costs, what it measures, and its panels.
            %   Inputs   KIND, the plan name
            %   Outputs  SPEC, its cost, its metric and its panels
            %   Utility  let the tab describe a plan before anyone spends an
            %           hour running it.
            %
            %   One place, so the label, the note, the panel titles and the
            %   plan the button builds cannot drift apart. The per-cell
            %   seconds are MEASURED, not estimated: a cost stated before the
            %   button is pressed is only worth stating if it is true.
            switch string(kind)
                case "four-doors"
                    spec.plan = @() methods.fourDoorsSweepPlan();
                    spec.secondsPerCell = 24;
                    spec.note = ['Six corridors x four budgets. The metric ' ...
                        'that matters here is not RMSE -- a method that ' ...
                        'throws away one of two live modes gets a BETTER ' ...
                        'RMSE for doing it, because the surviving mode is ' ...
                        'closer to the truth than the average of both. Read ' ...
                        'the mode-weight panels instead, and read the ' ...
                        'irregular-corridor cells first: every evenly ' ...
                        'spaced corridor is symmetric, and on a symmetric ' ...
                        'posterior a collapsed estimate lands near the ' ...
                        'truth by construction.'];
                    spec.panels = { ...
                        'maxModeWeightL1', 'budget',  "log", struct(), ...
                            'worst mode-weight $L_1$ vs budget'; ...
                        'meanMarginalL1',  'budget',  "log", struct(), ...
                            'mean marginal $L_1$ vs budget'; ...
                        'collapsedModes',  'budget',  "linear", struct(), ...
                            'modes collapsed vs budget'; ...
                        'rmse',            'budget',  "log", struct(), ...
                            'RMSE vs budget (the flattering metric)'; ...
                        'runtimeTotal',    'budget',  "linear", struct(), ...
                            'runtime vs budget'; ...
                        ... % The spacing curve keeps ONLY the evenly spaced
                        ... % corridors at weak odometry. The irregular cell
                        ... % has no spacing to plot at, and the six-door one
                        ... % is a different corridor length -- either would
                        ... % put a point on a curve that is not about them.
                        'maxModeWeightL1', 'spacing', "log", ...
                            struct('odometryName', "weak", 'family', "even"), ...
                            'mode-weight $L_1$ vs door spacing, even corridors'};

                case "grid-world"
                    spec.plan = @() methods.gridWorldSweepPlan();
                    % 260 s per cell, measured over the full eighteen-cell run
                    % (4683 s). The number this replaced was 26 -- an order of
                    % magnitude out, because it was carried over from the
                    % two-pose grid without asking what had changed. What
                    % changed is the problem: NF-iSAM trains a flow per
                    % variable, so at thirteen variables its 150-425 s IS the
                    % cell, and the two sampling methods take 2-5 s each
                    % beside it. A cost label that is ten times optimistic is
                    % worse than none, because the user budgets against it.
                    spec.secondsPerCell = 260;
                    spec.note = ['Eighteen cells at ONE budget: this grid ' ...
                        'sweeps problem size, not spending. The first panel ' ...
                        'is the result -- every cell as a marker, colour by ' ...
                        'method, shape by layout. The dashed line is where ' ...
                        'the OFFICE turns, at thirteen variables, and the ' ...
                        'warehouse markers are the reason it is labelled ' ...
                        'that way rather than as the engine''s: they sit ' ...
                        'high at TEN, to the left of it. There is no one ' ...
                        'variable count that separates the good runs from ' ...
                        'the bad across layouts. Read this grid as "where ' ...
                        'does this map turn", not as a number for the ' ...
                        'engine. The scatter is deliberately not averaged: ' ...
                        'the same medians with the seeds interleaved would ' ...
                        'plot identically and mean nothing.'];
                    spec.panels = { ...
                        'cliff',           '',             "log", struct(), ...
                            'pose RMSE vs variables, all cells'; ...
                        'landmarkRMSE',    'numVariables', "log", struct(), ...
                            'landmark RMSE vs variables'; ...
                        'minEssSupport',   'numVariables', "log", struct(), ...
                            'support ESS vs variables'; ...
                        'lookupMean',      'numVariables', "log", struct(), ...
                            'nearest-support lookup vs variables'; ...
                        'poseRMSE',        'numPoses',     "log", struct(), ...
                            'pose RMSE vs mission length'; ...
                        'runtimeTotal',    'numVariables', "linear", struct(), ...
                            'runtime vs variables'};

                otherwise
                    spec.plan = @() methods.twoPoseSweepPlan();
                    % 22 s per cell, most of it NF-iSAM flow training:
                    % measured over a full twenty-four cell grid (528 s), not
                    % extrapolated from two cells as an earlier version of
                    % this label was.
                    spec.secondsPerCell = 22;
                    spec.note = ['Each budget point is the median over the ' ...
                        'six scenarios, which are six different problems ' ...
                        'rather than six repeats -- so the line is typical ' ...
                        'behaviour, not an estimate with an error bar. One ' ...
                        'seed throughout: the curves are one realisation, ' ...
                        'and that is why the seed is reported beside them.'];
                    spec.panels = { ...
                        'relL1Error',   'budget',     "log", struct(), ...
                            'relative $L_1$ error vs budget'; ...
                        'rmse',         'budget',     "log", struct(), ...
                            'posterior-mean RMSE vs budget'; ...
                        'mmd',          'budget',     "log", struct(), ...
                            'MMD to the reference vs budget'; ...
                        'massError',    'budget',     "log", struct(), ...
                            'mass error vs budget'; ...
                        'runtimeTotal', 'budget',     "linear", struct(), ...
                            'runtime vs budget'; ...
                        'relL1Error',   'separation', "log", struct('largestBudget', true, 'odometryName', "weak"), ...
                            'error vs ambiguity, at the largest budget'};
            end
            spec.numCells = numel(spec.plan());
        end

        % -----------------------------------------------------------------
        function buildDiagnosticsTab(app)
            %BUILDDIAGNOSTICSTAB The four tables and the engine warnings.
            %   Inputs   none
            %   Outputs  none
            %   Utility  show the health numbers beside the results, since the
            %           error alone does not say what went wrong.
            %
            % Specification section 5's seventh tab: runtime, memory, ESS, MMD
            % and the early-stopping report. Every number here is one the
            % export bundle also writes, read from methods.diagnosticsReport
            % so that the tab and diagnostics.md cannot disagree.
            tab = uitab(app.TabGroup, 'Title', 'Diagnostics');
            g = uigridlayout(tab, [3 2]);
            g.RowHeight   = {'1x', '1x', 96};
            g.ColumnWidth = {'1x', '1x'};

            p1 = uipanel(g, 'Title', 'Runtime and memory');
            p1.Layout.Row = 1; p1.Layout.Column = 1;
            app.DiagRuntimeTable = uitable(uigridlayout(p1, [1 1]), ...
                'RowName', {}, 'Data', cell(0, 1));

            p2 = uipanel(g, 'Title', 'Accuracy, effective sample size and MMD');
            p2.Layout.Row = 1; p2.Layout.Column = 2;
            app.DiagAccuracyTable = uitable(uigridlayout(p2, [1 1]), ...
                'RowName', {}, 'Data', cell(0, 1));

            p3 = uipanel(g, 'Title', 'Incremental replay and early stopping');
            p3.Layout.Row = 2; p3.Layout.Column = 1;
            app.DiagReplayTable = uitable(uigridlayout(p3, [1 1]), ...
                'RowName', {}, 'Data', cell(0, 1));

            % A text area rather than a table: these are sentences, and a
            % warning truncated to a column width is a warning nobody reads.
            p4 = uipanel(g, 'Title', 'Engine warnings, as the methods raised them');
            p4.Layout.Row = 2; p4.Layout.Column = 2;
            app.DiagWarnings = uitextarea(uigridlayout(p4, [1 1]), ...
                'Editable', 'off', 'Value', {'press Run All'});

            np = uipanel(g, 'Title', 'How to read the memory columns');
            np.Layout.Row = 3; np.Layout.Column = [1 2];
            app.DiagNoteLabel = uilabel(uigridlayout(np, [1 1]), ...
                'WordWrap', 'on', 'VerticalAlignment', 'top', 'Text', '');
        end

        % -----------------------------------------------------------------
        function buildResearchTab(app)
            %BUILDRESEARCHTAB The open question, and where it cannot be asked.
            %   Inputs   none
            %   Outputs  none
            %   Utility  put the open question on screen together with the cases
            %           that cannot answer it.
            %
            %   The research instruction sheet asks one quantitative question:
            %   when does Smoothed Slices reduce computation relative to
            %   Slices nested sampling, and by how much. Everything needed to
            %   answer it was in research.costQualityFrontier and
            %   viz.plotCostQuality and reachable only from a script, which
            %   for an app is the same as not being answered.
            %
            %   TWO METHODS, NOT THREE, and the tab says so rather than
            %   quietly dropping one. NF-iSAM's Algorithm N1 SIMULATES from
            %   its factors rather than evaluating them, so its evaluation
            %   count is zero -- on a cost axis measured in evaluations that
            %   is an infinitely cheap method, which is a units error and not
            %   a result.
            %
            %   THE VERDICT TABLE HAS A ROW PER SCENARIO because the answer
            %   is not the same in all of them, and a single headline number
            %   would be a median over scenarios that disagree. Most usefully
            %   it can report "mechanism not exercised": innerEstimator is
            %   consulted only on the Lemma 1 structural route, and on the
            %   grid world, Four Doors and Plaza the two methods are
            %   literally the same computation.
            tab = uitab(app.TabGroup, 'Title', 'Research Question');
            g = uigridlayout(tab, [3 1]);
            g.RowHeight = {70, '1.25x', '1x'};

            % --- Controls --------------------------------------------------
            ctrl = uigridlayout(g, [2 4]);
            ctrl.ColumnWidth = {210, 190, '1x', 110};
            ctrl.RowHeight = {26, 26};
            ctrl.Padding = [0 0 0 0];
            ctrl.RowSpacing = 6;

            app.ResearchRunButton = uibutton(ctrl, ...
                'Text', 'Measure cost vs quality', ...
                'ButtonPushedFcn', @(~,~) app.onRunResearch());

            app.ResearchScenarioDropdown = uidropdown(ctrl, ...
                'Items', {'(run first)'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~,~) app.refreshResearchTab());

            app.ResearchStatusLabel = uilabel(ctrl, 'Text', ...
                'the two-pose benchmark is the only case whose elimination takes the Lemma 1 route');

            uilabel(ctrl, 'Text', char(app.IterationLabel), ...
                'FontAngle', 'italic', 'HorizontalAlignment', 'right');

            app.ResearchProgress = utils.ProgressBar(ctrl, 'IdleText', "not run");
            app.ResearchProgress.Grid.Layout.Row = 2;
            app.ResearchProgress.Grid.Layout.Column = [1 4];

            % --- The two figures -------------------------------------------
            figs = uigridlayout(g, [1 2]);
            figs.Padding = [0 0 0 0];

            fp = uipanel(figs, 'Title', ...
                'Posterior error vs MEASURED factor evaluations (down and left is better)');
            app.AxResearchCost = uiaxes(uigridlayout(fp, [1 1]));
            app.register('research_cost_quality', app.AxResearchCost);

            gp = uipanel(figs, 'Title', 'Work vs budget: the growth rate itself');
            app.AxResearchGrowth = uiaxes(uigridlayout(gp, [1 1]));
            app.register('research_growth', app.AxResearchGrowth);

            % --- Verdicts ---------------------------------------------------
            lower = uigridlayout(g, [1 2]);
            lower.ColumnWidth = {'1.7x', '1x'};
            lower.Padding = [0 0 0 0];

            tp = uipanel(lower, 'Title', 'One verdict per scenario');
            app.ResearchTable = uitable(uigridlayout(tp, [1 1]), ...
                'RowName', {}, 'Data', cell(0, 1));

            np = uipanel(lower, 'Title', 'What the axes mean');
            app.ResearchNoteLabel = uilabel(uigridlayout(np, [1 1]), ...
                'WordWrap', 'on', 'VerticalAlignment', 'top', 'Text', ...
                ['Factor evaluations, not wall time. Wall time confounds ' ...
                 'the algorithm with the machine, and Smoothed Slices is ' ...
                 'precisely the method a wall-time axis would flatter, ' ...
                 'because it turns a sample tree into a matrix product that ' ...
                 'MATLAB happens to run fast. Slices and Smoothed Slices ' ...
                 'only: NF-iSAM simulates from its factors rather than ' ...
                 'evaluating them, so it has no honest point on this axis. ' ...
                 'A curve that is merely lower is not a result -- it may ' ...
                 'have bought that quality with more evaluations, which is ' ...
                 'what the horizontal axis exists to reveal.']);
        end

        % -----------------------------------------------------------------
        function buildSurfaceComplexityTab(app)
            %BUILDSURFACECOMPLEXITYTAB Research sheet E2, and the "if" it tests.
            %   Inputs   none
            %   Outputs  none
            %   Utility  measure the "if" the whole cost claim is conditional
            %           on.
            %
            %   The Research Question tab measures whether Smoothed Slices
            %   saved evaluations. This one measures whether the REASON it
            %   would is true. The sheet states the idea as a conditional --
            %   if the surfaces R_r are lower-rank, sparse or well
            %   approximated by small active successor sets, then the cost can
            %   move -- and everything to the left of that "then" lives here.
            %
            %   TWO BUTTONS BECAUSE THEY ARE TWO EXPERIMENTS. The screening
            %   study varies the case and watches the spectrum; the active-set
            %   profile holds the case still and varies K. They answer
            %   different halves of E2 and cost different amounts, so binding
            %   them to one button would make the cheap half wait for the
            %   expensive one.
            %
            %   THE CONTROL IS ON THE FACE OF THE TAB, not buried in a
            %   struct. One of the swept knobs -- the odometry sigma -- CANNOT
            %   reach the surface: it belongs to a front factor that
            %   multiplies the result after R_0 is built. If it ever moves the
            %   spectrum, every other number on this tab is being read off the
            %   wrong matrix, so the status line says whether it stayed flat.
            tab = uitab(app.TabGroup, 'Title', 'Surface Complexity');
            g = uigridlayout(tab, [3 1]);
            g.RowHeight = {70, '1.25x', '1x'};

            % --- Controls --------------------------------------------------
            ctrl = uigridlayout(g, [2 5]);
            ctrl.ColumnWidth = {210, 190, 150, '1x', 110};
            ctrl.RowHeight = {26, 26};
            ctrl.Padding = [0 0 0 0];
            ctrl.RowSpacing = 6;

            app.SurfaceStudyButton = uibutton(ctrl, ...
                'Text', 'Measure surface complexity', ...
                'ButtonPushedFcn', @(~,~) app.onRunSurfaceStudy());

            app.SurfaceProfileButton = uibutton(ctrl, ...
                'Text', 'Profile the active set', ...
                'ButtonPushedFcn', @(~,~) app.onRunActiveSetProfile());

            app.SurfaceAxisDropdown = uidropdown(ctrl, ...
                'Items', {'(run first)'}, 'Enable', 'off', ...
                'ValueChangedFcn', @(~,~) app.refreshSurfaceTab());

            app.SurfaceStatusLabel = uilabel(ctrl, 'Text', ...
                'the two-pose benchmark is the only case that builds a surface at all');

            uilabel(ctrl, 'Text', char(app.IterationLabel), ...
                'FontAngle', 'italic', 'HorizontalAlignment', 'right');

            app.SurfaceProgress = utils.ProgressBar(ctrl, 'IdleText', "not run");
            app.SurfaceProgress.Grid.Layout.Row = 2;
            app.SurfaceProgress.Grid.Layout.Column = [1 5];

            % --- The three figures -----------------------------------------
            figs = uigridlayout(g, [1 3]);
            figs.Padding = [0 0 0 0];

            sp = uipanel(figs, 'Title', ...
                'Singular-value decay: a plunge is a compact surface');
            app.AxSurfaceSpectrum = uiaxes(uigridlayout(sp, [1 1]));
            app.register('surface_spectrum', app.AxSurfaceSpectrum);

            rp = uipanel(figs, 'Title', ...
                'Rank and sparsity as the case gets harder');
            app.AxSurfaceRank = uiaxes(uigridlayout(rp, [1 1]));
            app.register('surface_rank', app.AxSurfaceRank);

            ap = uipanel(figs, 'Title', ...
                'Active set: how far left of |X_1| the error is met');
            app.AxSurfaceActiveSet = uiaxes(uigridlayout(ap, [1 1]));
            app.register('surface_active_set', app.AxSurfaceActiveSet);

            % --- Verdicts ---------------------------------------------------
            lower = uigridlayout(g, [1 2]);
            lower.ColumnWidth = {'1.7x', '1x'};
            lower.Padding = [0 0 0 0];

            tp = uipanel(lower, 'Title', 'One row per swept configuration');
            app.SurfaceTable = uitable(uigridlayout(tp, [1 1]), ...
                'RowName', {}, 'Data', cell(0, 1));

            np = uipanel(lower, 'Title', 'What these numbers can and cannot say');
            app.SurfaceNoteLabel = uilabel(uigridlayout(np, [1 1]), ...
                'WordWrap', 'on', 'VerticalAlignment', 'top', 'Text', ...
                ['rank_eps has no meaning in absolute units: a surface is a ' ...
                 'product of unnormalized factors, so the tolerance is ' ...
                 'relative to sigma_1. Sparse and low-rank are DIFFERENT ' ...
                 'claims and both are reported -- a dense surface can be ' ...
                 'compressible and a sparse one can be full rank. Rank 1 is ' ...
                 'not good news: it means the surface separates, so the ' ...
                 'conditioning carried no information, and it is labelled ' ...
                 '"separable" rather than counted as a result. And R_0 = ' ...
                 'diag(Z) P_0 R_1 caps rank(R_0) at rank(R_1), so the ' ...
                 'terminal surface is measured beside it: where the two ' ...
                 'agree, the compactness belongs to the fusion factors and ' ...
                 'not to the smoothing.']);
        end

        % -----------------------------------------------------------------
        function buildPlazaTab(app)
            %BUILDPLAZATAB The real data: the window in its run, and L2.
            %   Inputs   none
            %   Outputs  none
            %   Utility  the real datasets are solved on a window, and a panel
            %           that hid which window would leave the numbers
            %           unreadable.
            %
            %   Two things live here that no other tab can show.
            %
            %   The CONTEXT figure exists to prevent a specific misreading.
            %   Every other Plaza panel shows one window of a 1400 m run,
            %   and shown alone that looks like a trajectory estimate next to
            %   the papers' figures. Drawing the window and the whole run at
            %   the same scale is the honest way to say which is which.
            %
            %   The LADDER is the showcase manual's landmark-L2 requirement.
            %   The manual asks for marginals at Plaza2 time steps 0, 8 and
            %   22; those are the paper's step numbers and do not map onto
            %   keyframes cut every 6 m -- L2 is ranged at one of the three
            %   and no other node is ranged at all three, so the literal
            %   figure would have two panels showing a landmark that had
            %   received no measurement. The button instead runs
            %   experiments.plazaLandmarkWindows, which reads the windows off
            %   the data: fewest, middling and most observing poses. Same
            %   narrative, steps that are true of this dataset.
            tab = uitab(app.TabGroup, 'Title', 'Plaza');
            g = uigridlayout(tab, [3 1]);
            g.RowHeight = {64, '1.15x', '1x'};

            % --- Controls --------------------------------------------------
            ctrl = uigridlayout(g, [2 5]);
            ctrl.ColumnWidth = {150, 70, 210, '1x', 150};
            ctrl.RowHeight = {26, 24};
            ctrl.Padding = [0 0 0 0];

            uilabel(ctrl, 'Text', 'landmark ordinal L');
            app.PlazaLandmarkSpinner = uispinner(ctrl, 'Value', 2, ...
                'Limits', [1 4], 'Step', 1, 'RoundFractionalValues', 'on');

            app.PlazaLadderButton = uibutton(ctrl, ...
                'Text', 'Run evidence ladder (P2-A)', ...
                'ButtonPushedFcn', @(~,~) app.onRunPlazaLadder());

            app.PlazaStatusLabel = uilabel(ctrl, 'Text', ...
                'load Plaza1 or Plaza2 on the Case Study tab');

            uilabel(ctrl, 'Text', 'real data', 'FontAngle', 'italic', ...
                'HorizontalAlignment', 'right');

            % The cost warning is a control, not decoration: the ladder runs
            % three configurations, and with NF-iSAM selected each costs
            % minutes rather than seconds. A user who learns that after
            % pressing the button has already spent the time.
            note = utils.latexLabel(ctrl, ...
                "Three independent windows, not one filter. " + ...
                "With NF-iSAM selected this is minutes per rung.");
            note.Layout.Row = 2; note.Layout.Column = [1 5];

            % --- The window in its run -------------------------------------
            cp = uipanel(g, 'Title', 'The solved window, inside the run it was cut from');
            app.AxPlazaContext = uiaxes(uigridlayout(cp, [1 1]));
            app.register('plaza_context', app.AxPlazaContext);

            % --- The ladder ------------------------------------------------
            lower = uigridlayout(g, [1 2]);
            lower.ColumnWidth = {'2.6x', '1x'};
            lower.Padding = [0 0 0 0];

            mp = uipanel(lower, 'Title', ...
                'Landmark marginals: x above, y below, evidence increasing left to right');
            mg = uigridlayout(mp, [2 3]);
            for r = 1:2
                for c = 1:3
                    ax = uiaxes(mg);
                    ax.Layout.Row = r; ax.Layout.Column = c;
                    app.AxPlazaMarginal(r, c) = ax;
                    app.register(sprintf('plaza_marginal_%d_%d', r, c), ax);
                end
            end

            tp = uipanel(lower, 'Title', 'Ladder metrics');
            app.PlazaTable = uitable(uigridlayout(tp, [1 1]), 'RowName', {}, ...
                'ColumnWidth', {140, 90, 70, 70, 80});
        end

        % -----------------------------------------------------------------
        function buildPlaceholderTabs(app)
            %BUILDPLACEHOLDERTABS Nothing: every tab is built, and this says so.
            %   Inputs   none
            %   Outputs  none
            %   Utility  kept as the one place a reader looks for what is
            %           missing, and finding it empty is the answer.
            %
            % Specification section 5 listed eight tabs, and this build has
            % seven of them. IMPLEMENTATION NOTES IS DROPPED, not deferred:
            % it was to carry equations, file provenance and per-method
            % checklists, and every one of those now has a better home --
            % the equations are in the function headers beside the code that
            % implements them, the provenance is in data/PROVENANCE.md where
            % it survives the app being rewritten, and the checklists are the
            % test suite. A tab restating them would be a fourth copy to keep
            % in step with the other three, which is how they drift.
        end

        % -----------------------------------------------------------------
        function buildFigureGeneratorTab(app)
            %BUILDFIGUREGENERATORTAB Specification section 5's sixth tab.
            %   Inputs   none
            %   Outputs  none
            %   Utility  export every registered axes, and show which ones exist
            %           to be exported.
            %
            %   The export itself already worked from the toolbar. What was
            %   missing was any way to see WHAT would be written before
            %   committing to it: which axes are registered, which are still
            %   empty because their tab has not been run, and which files the
            %   bundle carries besides the images. An export whose contents
            %   are only discoverable afterwards is one nobody checks.
            tab = uitab(app.TabGroup, 'Title', 'Figure Generator');
            g = uigridlayout(tab, [3 2]);
            g.RowHeight   = {'1x', 150, 40};
            g.ColumnWidth = {'2x', '1x'};

            % --- the checklist ------------------------------------------
            p1 = uipanel(g, 'Title', 'Registered axes, and whether they hold a drawn figure');
            p1.Layout.Row = 1; p1.Layout.Column = 1;
            app.FigGenTable = uitable(uigridlayout(p1, [1 1]), ...
                'RowName', {}, ...
                'ColumnName', {'figure', 'tab', 'state'}, ...
                'Data', cell(0, 3));

            % --- format, and what the bundle carries ---------------------
            p2 = uipanel(g, 'Title', 'Image format');
            p2.Layout.Row = 1; p2.Layout.Column = 2;
            g2 = uigridlayout(p2, [2 1]);
            g2.RowHeight = {28, '1x'};
            % Both, by default, and the option exists because the two are
            % for different readers: the PDF is what goes in the report and
            % the PNG is what goes in a message. Offering only "both" made
            % every export pay for a vector pass nobody opened.
            app.FigGenFormat = uidropdown(g2, ...
                'Items', {'PNG and PDF', 'PNG only', 'PDF only'}, ...
                'Value', 'PNG and PDF');
            app.FigGenStatusLabel = uilabel(g2, 'WordWrap', 'on', ...
                'VerticalAlignment', 'top', ...
                'Text', 'press Refresh to read the registry');

            p3 = uipanel(g, 'Title', 'The bundle also writes');
            p3.Layout.Row = 2; p3.Layout.Column = [1 2];
            app.FigGenBundleList = uitextarea(uigridlayout(p3, [1 1]), ...
                'Editable', 'off', 'Value', { ...
                    'run_state.mat      raw results and config', ...
                    'metrics.csv        the comparison table', ...
                    'config.json        settings, seed, MATLAB version', ...
                    'process_trace.json per-stage traces', ...
                    'diagnostics.md     readable summary', ...
                    'app_snapshot.png   the whole UI'});

            ctrl = uigridlayout(g, [1 3]);
            ctrl.Layout.Row = 3; ctrl.Layout.Column = [1 2];
            ctrl.ColumnWidth = {140, 160, '1x'};
            app.FigGenRefreshButton = uibutton(ctrl, 'Text', 'Refresh checklist', ...
                'ButtonPushedFcn', @(~,~) app.refreshFigureChecklist());
            app.FigGenExportButton = uibutton(ctrl, 'Text', 'Export bundle', ...
                'ButtonPushedFcn', @(~,~) app.onExportRequested());
            uilabel(ctrl, 'Text', '');

            app.refreshFigureChecklist();
        end

        % -----------------------------------------------------------------
        function fmt = selectedExportFormat(app)
            %SELECTEDEXPORTFORMAT The dropdown, as the exporter's option.
            %   Inputs   none
            %   Outputs  FMT, the exporter option
            %   Utility  read the dropdown in one place.
            %
            %   Guarded because the toolbar Export button predates this tab
            %   and must keep working if the tab is ever not built.
            fmt = "both";
            if ~isempty(app.FigGenFormat) && isgraphics(app.FigGenFormat)
                switch app.FigGenFormat.Value
                    case 'PNG only', fmt = "png";
                    case 'PDF only', fmt = "pdf";
                end
            end
        end

        % -----------------------------------------------------------------
        function refreshFigureChecklist(app)
            %REFRESHFIGURECHECKLIST Read the registry into the table.
            %   Inputs   none
            %   Outputs  none
            %   Utility  an unregistered panel is one nobody will notice is
            %           missing from the export.
            %
            %   "empty" is the state worth naming. An axes that was
            %   registered but never drawn exports as a blank image, which in
            %   a folder of thirty PNGs looks exactly like one that failed.
            reg = app.FigureRegistry;
            n = numel(reg);
            data = cell(n, 3);
            nEmpty = 0;
            for i = 1:n
                h = reg(i).handle;
                data{i,1} = char(reg(i).name);
                if isgraphics(h)
                    par = ancestor(h, 'uitab');
                    if isempty(par), data{i,2} = '-'; else, data{i,2} = char(par.Title); end
                    if isempty(findobj(h, '-not', 'Type', 'axes'))
                        data{i,3} = 'empty, not yet run';
                        nEmpty = nEmpty + 1;
                    else
                        data{i,3} = 'drawn';
                    end
                else
                    data{i,2} = '-';
                    data{i,3} = 'INVALID HANDLE';
                end
            end
            app.FigGenTable.Data = data;
            app.FigGenStatusLabel.Text = sprintf( ...
                '%d registered, %d still empty. Empty axes still export, as blank images.', ...
                n, nEmpty);
        end

        function register(app, name, ax)
            %REGISTER Record one axes under a name, for the exporter.
            %   Inputs   NAME the figure name, AX the axes
            %   Outputs  none
            %   Utility  specification section 21 requires every axes to be
            %           registered exactly once.
            utils.applyLatexToAxes(ax);
            app.FigureRegistry(end+1) = struct('name', string(name), 'handle', ax);
        end
    end

    % =====================================================================
    % Callbacks
    % =====================================================================
    methods (Access = private)

        function loadCase(app)
            %LOADCASE Build the selected case and draw what needs no run.
            %   Inputs   none
            %   Outputs  none
            %   Utility  let the case be seen before it is solved.
            variant = "gaussian";
            if ~isempty(app.VariantDropdown)
                variant = string(app.VariantDropdown.Value);
            end
            which = "Two-pose range";
            if ~isempty(app.CaseDropdown)
                which = string(app.CaseDropdown.Value);
            end

            switch which
                case "Four Doors"
                    app.CaseData = datasets.makeFourDoorsCase();
                    note = "$f(x_1)\prod_k f(x_k,x_{k+1})\prod_{k \in \mathcal{D}} " + ...
                           "f_{\mathrm{door}}(x_k)$, four identical doors";
                case "Grid world"
                    assoc = "known";
                    if variant == "multimodal", assoc = "ambiguous"; end
                    app.CaseData = datasets.makeGridWorldCase( ...
                        'Layout', string(app.LayoutDropdown.Value), ...
                        'NumPoses', app.PoseSpinner.Value, 'Association', assoc);
                    s = app.CaseData.settings;
                    % The variable count is the number shown, with the poses
                    % and beacons that produced it, because the note used to
                    % give poses and beacons alone and leave the reader to
                    % add them up against a limit stated in a third unit.
                    %
                    % What it no longer does is quote a limit. It said
                    % "validated to about 13", which is the OFFICE's number:
                    % the eighteen-cell sweep has the warehouse failing at
                    % ten variables and the office fine at thirteen, so a
                    % single figure printed beside every layout would be
                    % wrong for two of the three. Where a layout's own turn
                    % has been measured, that is what is quoted.
                    turn = "";
                    if s.layout == "office"
                        turn = "; this layout turns at about 13";
                    elseif s.layout == "warehouse"
                        turn = "; this layout is already unreliable at 10";
                    end
                    note = sprintf("%s: %d poses, %d of %d beacons seen, " + ...
                        "\\textbf{%d variables}, max separator $d_S = %d$%s", ...
                        s.layout, s.numPoses, s.numObservedLandmarks, ...
                        s.numLandmarks, s.numVariables, s.maxSeparatorDim, turn);
                case {"Plaza1", "Plaza2"}
                    % The only real data in the app, and the only case whose
                    % pose count is not the user's to choose: the window is
                    % searched for under a cap on VARIABLES, and how many
                    % landmarks it ends up ranging is a property of where the
                    % robot was. Its landmarks are eliminated last because
                    % their posteriors are bimodal. The cap is a budget and
                    % not a safety margin -- there is no longer a count to be
                    % safely under, the grid world's limit having turned out
                    % to be per-layout and not predicted by the count at all.
                    assoc = "known";
                    if variant == "multimodal", assoc = "ambiguous"; end
                    app.CaseData = datasets.makePlazaCase( ...
                        'Dataset', which, 'Association', assoc);
                    s = app.CaseData.settings;
                    note = sprintf("%d keyframes, %d landmarks, %d readings, " + ...
                        "%d variables, landmarks eliminated last; " + ...
                        "$\\sigma_r = %.2f$ m after calibration, " + ...
                        "ranges beyond %d m dropped", ...
                        s.numPoses, s.numLandmarks, s.numReadings, ...
                        s.numVariables, s.rangeSigma, s.sensorRange);
                otherwise
                    app.CaseData = datasets.makeTwoPoseRangeCase('Variant', variant);
                    note = "$x_1 \rightarrow l_1 \rightarrow x_2$, order $(x_1, l_1, x_2)$";
            end

            app.Results = [];
            app.Reference = [];
            if ~isempty(app.CaseNoteLabel) && isgraphics(app.CaseNoteLabel)
                app.CaseNoteLabel.Text = note;
            end

            viz.plotFactorGraphStep(app.AxGraph, app.CaseData, []);
            viz.plotBayesNetStep(app.AxBayesNet, app.CaseData, 0);
            app.refreshMapViews(1);
            app.refreshPlazaContext();
            app.configureSliders();

            % The ladder belongs to the case it was run on. Leaving it drawn
            % across a case change would put Plaza2's L2 panels above a
            % Plaza1 context figure, with nothing on screen saying so.
            app.PlazaLadder = [];
            app.refreshPlazaLadder();
        end

        function refreshPlazaContext(app)
            %REFRESHPLAZACONTEXT The window drawn in its run, or a note.
            %   Inputs   none
            %   Outputs  none
            %   Utility  draw the solved window inside the run it was cut from,
            %           at one scale.
            %
            %   Called on every case load and after every run, because the
            %   figure shows the window AND the estimates and either can
            %   change without the other.
            if isempty(app.AxPlazaContext) || ~isgraphics(app.AxPlazaContext)
                return
            end

            res = app.Results;
            if isempty(res), res = struct([]); end
            viz.plotPlazaContext(app.AxPlazaContext, app.CaseData, res);

            if isfield(app.CaseData, 'plaza')
                app.PlazaStatusLabel.Text = sprintf( ...
                    '%s, keyframes %d-%d, %d variables', ...
                    app.CaseData.plaza.dataset, ...
                    app.CaseData.plaza.windowKeyframes(1), ...
                    app.CaseData.plaza.windowKeyframes(end), ...
                    app.CaseData.plaza.numVariables);
            else
                app.PlazaStatusLabel.Text = ...
                    'load Plaza1 or Plaza2 on the Case Study tab';
            end
        end

        function onRunPlazaLadder(app)
            %ONRUNPLAZALADDER Protocol P2-A, drawn as six marginal panels.
            %   Inputs   none
            %   Outputs  none
            %   Utility  run the evidence ladder, which is three separate
            %           posteriors and never a filter.
            if ~isfield(app.CaseData, 'plaza')
                uialert(app.UIFigure, ...
                    ['The ladder runs on Plaza data. Choose Plaza1 or ' ...
                     'Plaza2 on the Case Study tab first.'], 'Not a Plaza case');
                return
            end

            % Gated for the reason onRunSweep documents: the progress sink
            % yields to the event queue, so every other run button is live
            % during this one unless it is turned off.
            gate = app.runGate();
            set(gate, 'Enable', 'off');
            restore = onCleanup(@() set(gate, 'Enable', 'on'));

            app.PlazaStatusLabel.Text = 'running the ladder...';
            drawnow;

            try
                out = experiments.runPlazaProtocol("P2-A", ...
                    'Dataset', string(app.CaseData.plaza.dataset), ...
                    'Landmark', app.PlazaLandmarkSpinner.Value, ...
                    'Methods', app.selectedMethods(), ...
                    'Config', app.collectConfig(), ...
                    'Verbose', false);
                app.PlazaLadder = out;
                app.refreshPlazaLadder();
                app.PlazaStatusLabel.Text = sprintf( ...
                    'L%d: %d rungs, %.0f s total', ...
                    app.PlazaLandmarkSpinner.Value, numel(out.runs), ...
                    sum(out.metrics.runtime, 'omitnan'));
            catch err
                app.PlazaStatusLabel.Text = ['error: ' err.message];
                uialert(app.UIFigure, getReport(err, 'basic'), 'Ladder failed');
            end
        end

        function refreshPlazaLadder(app)
            %REFRESHPLAZALADDER Six panels: x and y, one column per rung.
            %   Inputs   none
            %   Outputs  none
            %   Utility  draw the ladder that was run, one column per rung.
            out = app.PlazaLadder;
            for ax = app.AxPlazaMarginal(:).'
                cla(ax, 'reset');
            end
            if isempty(out), return, end

            for i = 1:min(numel(out.runs), size(app.AxPlazaMarginal, 2))
                run = out.runs(i);
                if isempty(run.results), continue, end

                % The id selects the row, the name selects the variable, and
                % they are no longer the same number: the window numbers its
                % landmarks l1..lN and carries the survey node id alongside.
                lname = run.settings.landmarkName;
                row = find(run.caseData.landmarks.ids == ...
                           run.settings.landmarkId, 1);
                truth = [NaN NaN];
                if ~isempty(row)
                    truth = run.caseData.landmarks.truePositions(row, :);
                end

                for ci = 1:2
                    coord = "x";
                    if ci == 2, coord = "y"; end
                    viz.plotPlazaMarginal(app.AxPlazaMarginal(ci, i), ...
                        run.results, lname, coord, 'TrueValue', truth(ci));
                    % The rung's evidence belongs in the title, not the
                    % legend: it is what distinguishes the columns.
                    utils.setLatexTitle(app.AxPlazaMarginal(ci, i), ...
                        sprintf("%s in %s, %d observing pose(s)", ...
                                lname, coord, run.settings.observingPoses));
                end
            end

            % Both pose columns, because the gap between them is the
            % information: aligned-only would hide a rigid drift, and
            % unaligned-only is not what the papers report.
            T = out.metrics;
            app.PlazaTable.Data = table(T.run, T.method, T.poseRMSE, ...
                T.poseRMSEaligned, T.landmarkRMSE, 'VariableNames', ...
                {'window', 'method', 'poseRMSE', 'aligned', 'landmarkRMSE'});
        end

        function onCaseChanged(app)
            %ONCASECHANGED The case dropdown moved: reconfigure and reload.
            %   Inputs   none
            %   Outputs  none
            %   Utility  a stale control from the previous case would run the
            %           new one at settings nobody chose.
            %
            % The pose count and the layout only mean something for the grid
            % world, and a live control that does nothing is worse than a
            % disabled one.
            isGrid = string(app.CaseDropdown.Value) == "Grid world";
            app.PoseSpinner.Enable = matlab.lang.OnOffSwitchState(isGrid);
            app.LayoutDropdown.Enable = matlab.lang.OnOffSwitchState(isGrid);
            if isGrid
                app.syncPoseSpinnerToLayout();
            end

            hasVariant = string(app.CaseDropdown.Value) ~= "Four Doors";
            app.VariantDropdown.Enable = matlab.lang.OnOffSwitchState(hasVariant);

            app.loadCase();
            app.setStatus(sprintf('loaded %s; press Run All', app.CaseDropdown.Value));
        end

        function onLayoutChanged(app)
            %ONLAYOUTCHANGED A new map, and the pose count that map is for.
            %   Inputs   none
            %   Outputs  none
            %   Utility  the pose count is a property of the map, so the two
            %           move together.
            %
            %   The spinner FOLLOWS the layout rather than persisting across
            %   it. Five poses is the office's complete mission and two
            %   thirds of the warehouse's; carrying a number over from the
            %   previous layout would silently change what the mission is
            %   while the label said only the layout had changed.
            app.syncPoseSpinnerToLayout();
            app.loadCase();
            app.setStatus(sprintf('loaded the %s layout, %d poses; press Run All', ...
                app.LayoutDropdown.Value, app.PoseSpinner.Value));
        end

        function syncPoseSpinnerToLayout(app)
            %SYNCPOSESPINNERTOLAYOUT Clamp the spinner to what the layout holds.
            %   Inputs   none
            %   Outputs  none
            %   Utility  a pose count the map cannot hold would fail at build
            %           time instead of here.
            d = datasets.gridWorldDefaults(string(app.LayoutDropdown.Value));
            app.PoseSpinner.Value = d.numPoses;
        end

        function onVariantChanged(app)
            %ONVARIANTCHANGED The variant dropdown moved: reload the case.
            %   Inputs   none
            %   Outputs  none
            %   Utility  the variant changes the factors, so nothing drawn
            %           survives it.
            app.loadCase();
            app.setStatus('case reloaded; press Run All');
        end

        function configureSliders(app)
            %CONFIGURESLIDERS Match the sliders to the case that is loaded.
            %   Inputs   none
            %   Outputs  none
            %   Utility  the increment and stage sliders index this case, and a
            %           stale range indexes nothing.
            %
            %   A slider whose range does not match its data is worse than no
            %   slider: it silently clamps and the user reads the wrong frame.
            nInc = max(2, app.CaseData.numIncrements);
            app.IncrementSlider.Limits = [1 nInc];
            app.IncrementSlider.MajorTicks = 1:max(1, round(nInc/8)):nInc;
            app.IncrementSlider.Value = min(app.IncrementSlider.Value, nInc);

            % Before a run the stage count is the number of eliminations the
            % order prescribes: the two graph panels are structural and can
            % be stepped through with no result in hand.
            nStage = max(2, numel(app.CaseData.eliminationOrder));
            if ~isempty(app.Results)
                ok = app.Results(arrayfun(@(r) r.status == "ok", app.Results));
                if ~isempty(ok)
                    nStage = max(2, ok(1).process.numStages);
                end
            end
            app.StageSlider.Limits = [1 nStage];
            app.StageSlider.MajorTicks = 1:max(1, round(nStage/8)):nStage;
            app.StageSlider.Value = min(app.StageSlider.Value, nStage);
        end

        function cfg = collectConfig(app)
            %COLLECTCONFIG Read every control into the config a run will use.
            %   Inputs   none
            %   Outputs  CFG, the method config
            %   Utility  one function reads the UI, so the config a run receives
            %           is the config the screen shows.
            args = {};
            fn = fieldnames(app.BudgetFields);
            for i = 1:numel(fn)
                args = [args, {fn{i}, app.BudgetFields.(fn{i}).Value}]; %#ok<AGROW>
            end
            args = [args, {'seed', app.SeedField.Value}];
            args = [args, { ...
                'incremental',      app.IncrementalCheck.Value, ...
                'surfaceCache',     app.SurfaceCacheCheck.Value, ...
                'mmdEarlyStopping', app.EarlyStopCheck.Value}];
            % Stripped, not merely left empty. APP.CONFIG is what the export
            % bundle records as the settings of the run, and a progress field
            % in there -- even an empty one -- claims the reporter was one.
            % onRun attaches it to its own copy for the length of the run.
            %
            % Built from the PRESET and not from commonMethodConfig, so that the
            % budget knobs with no field in the panel -- nfisamTrainSamples and
            % the flow iteration cap, which are most of a Run All's wall clock
            % -- follow the dropdown too. The fields are layered on top; they
            % agree with the preset because applyBudgetPreset rewrites them.
            % The preset's name rides along in cfg.budgetPreset, so the export
            % bundle says which budget produced it and a fast run cannot be
            % read afterwards as a paper one.
            preset = "paperLike";
            if ~isempty(app.BudgetPresetDropdown) && isvalid(app.BudgetPresetDropdown)
                preset = string(app.BudgetPresetDropdown.Value);
            end
            cfg = utils.serializableConfig(methods.configPreset(preset, args{:}));
        end

        function onReplayToggled(app)
            %ONREPLAYTOGGLED The two reuse rules only mean something in replay.
            %   Inputs   none
            %   Outputs  none
            %   Utility  the reuse rules only mean something in replay, so the
            %           fields follow the switch.
            on = matlab.lang.OnOffSwitchState(app.IncrementalCheck.Value);
            app.SurfaceCacheCheck.Enable = on;
            app.EarlyStopCheck.Enable = on;
        end

        function onRun(app)
            %ONRUN Run All, from the Posterior Recovery tab.
            %   Inputs   none
            %   Outputs  none
            %   Utility  start a run of every method from this tab.
            app.executeRun(["Slices", "NF-iSAM", "Smoothed Slices"], ...
                app.RunProgress, @(m) app.setStatus(m));
        end

        function onRunSelected(app)
            %ONRUNSELECTED Run All's counterpart on the Compare Methods tab.
            %   Inputs   none
            %   Outputs  none
            %   Utility  start a run of the ticked methods from the other tab.
            %
            %   Selection is real work avoided, not a filter over a full run:
            %   runComparison has taken a method list since it was written.
            sel = app.selectedMethods();
            if isempty(sel)
                uialert(app.UIFigure, ...
                    'Tick at least one method to run.', 'Nothing selected');
                return
            end
            app.executeRun(sel, app.CompareProgress, @(m) app.setCompareStatus(m));
        end

        function executeRun(app, whichMethods, bar, say)
            %EXECUTERUN The one run path, shared by both buttons.
            %   Inputs   WHICHMETHODS the methods to run, BAR the progress bar,
            %           SAY the status sink
            %   Outputs  none
            %   Utility  both Run buttons come here, so a run cannot behave
            %           differently depending on which was pressed.
            %
            %   Two buttons that each rendered their own results would be two
            %   places for the panels to fall out of step with the numbers, and
            %   the tab you were not looking at would be the one showing the
            %   previous run.
            say('running...');

            % BOTH run buttons, not just the one that was pressed. The sink's
            % drawnow is what lets the Stop callback fire, and it lets every
            % other callback fire too -- so an enabled Run Selected on the tab
            % you switched to mid-run starts a SECOND runComparison inside the
            % first, on the same app.Results, with the inner one's answer
            % overwritten by the outer one when it resumes. Disabling the
            % button that cannot start a run is what stops that.
            gate = app.runGate();
            set(gate, 'Enable', 'off');
            restore = onCleanup(@() set(gate, 'Enable', 'on'));

            % Export is gated too, but restored by hand rather than by the
            % cleanup: the success path below turns it on, and a cleanup that
            % ran afterwards would turn it straight back off.
            wasExport = app.ExportButton.Enable;
            app.ExportButton.Enable = 'off';

            % The other tab's bar follows this one. Results belong to the app,
            % so a bar showing the last run while this one is under way is a
            % lie the tab strip tells whenever you switch tabs.
            bar.Mirror = app.otherBar(bar);
            clearMirror = onCleanup(@() app.clearBarMirrors());

            bar.begin("preparing the run");
            drawnow;

            try
                app.Config = app.collectConfig();
                % The reporter goes on a COPY. app.Config is the record of
                % what was configured; the reporter belongs to this press of
                % the button and to nothing that outlives it.
                runConfig = app.Config;
                runConfig.progress = bar.Reporter;

                [app.Results, summary] = methods.runComparison( ...
                    app.CaseData, runConfig, whichMethods);
                app.Reference = summary.reference;

                % The Posterior Recovery panels are case-dependent: the
                % two-pose range benchmark has a generated factor to draw
                % against quadrature, and the others do not. An empty axes
                % with a reason on it beats drawing a wrong one.
                switch summary.referenceKind
                    case "quadrature"
                        viz.plotEstimatorComparison(app.AxEstimator, app.Results, app.Reference);
                        viz.plotMarginalKDE(app.AxMarginal, app.Results, "x2", app.Reference);
                        viz.plotPosteriorSamples(app.AxSamples, app.Results, "x1", "l1");
                        sm = app.Results(arrayfun(@(r) r.methodName == "Smoothed Slices", app.Results));
                        if ~isempty(sm)
                            viz.plotSmoothingSurfaceStep(app.AxSurface, sm(1), app.Reference);
                        end
                    case "chainExact"
                        viz.plotModeWeights(app.AxEstimator, app.Results, app.CaseData, app.Reference);
                        viz.plotChainMarginals(app.AxMarginal, app.Results, app.CaseData, app.Reference);
                        viz.plotPosteriorSamples(app.AxSamples, app.Results, "x1", "x2");
                        viz.plotStageDiagnostics(app.AxSurface, app.Results, 1);
                    otherwise
                        viz.plotMapStep(app.AxEstimator, app.CaseData, app.Results, Inf);
                        viz.plotEngineHealth(app.AxMarginal, app.Results);
                        viz.plotPosteriorSamples(app.AxSamples, app.Results, ...
                            app.CaseData.mission.poseNames(1), ...
                            app.CaseData.mission.poseNames(min(2, end)));
                        viz.plotStageDiagnostics(app.AxSurface, app.Results, 1);
                end
                viz.plotCardinalityDiagnostics(app.AxCardinality, app.Results);

                t = summary.metricsTable;
                app.MetricsTable.Data = t(:, {'Method','Status','RelL1Error','MMD','RuntimeSec'});

                % Refresh the elimination step drawn on the Case Study tab.
                ok = app.Results(arrayfun(@(r) r.status == "ok", app.Results));
                if ~isempty(ok) && numel(ok(1).states) >= 2
                    viz.plotFactorGraphStep(app.AxGraph, app.CaseData, ok(1).states(2));
                end
                % The Bayes net on this tab shows the finished factorization;
                % the Process Explorer copy is the one that steps through it.
                viz.plotBayesNetStep(app.AxBayesNet, app.CaseData, Inf);

                app.configureSliders();
                app.onProcessChanged();
                app.refreshCompareTab(summary);
                app.refreshDiagnosticsTab();
                % The context figure draws the estimates as well as the
                % window, so it is stale until a run has finished.
                app.refreshPlazaContext();

                % Export stays available after a cancelled run. What finished
                % is a real comparison of fewer methods, and the bundle says
                % which ones were stopped.
                app.ExportButton.Enable = 'on';
                verb = 'done';
                if summary.cancelled, verb = 'stopped'; end
                msg = sprintf('%s: %d of %d method(s) completed', ...
                    verb, numel(ok), numel(summary.methods));
                warnings = [];
                for i = 1:numel(ok)
                    if ~isempty(ok(i).logs), warnings = [warnings; ok(i).logs(:)]; end %#ok<AGROW>
                end
                if ~isempty(warnings)
                    msg = sprintf('%s -- %d engine warning(s)', msg, numel(warnings));
                end
                % Both status lines, not only the one whose button was
                % pressed: the results are the app's, not the tab's.
                app.setStatus(msg);
                app.setCompareStatus(msg);
                if summary.cancelled
                    bar.finish("cancelled", string(msg));
                else
                    bar.finish("ok", string(msg));
                end
            catch err
                % A STOP IS NOT A FAILURE, wherever it lands. runComparison
                % catches cancellations raised inside a method, but the ones
                % raised before the first method starts -- while the reference
                % is being built -- come out of it, and a Stop pressed in that
                % window used to arrive here and be reported as a crashed run:
                % red bar, modal alert, "run failed: Run cancelled at 0%". The
                % window is small and entirely reachable, because bar.begin
                % yields to the event queue before anything else happens.
                if utils.ProgressReporter.isCancellation(err)
                    msg = 'stopped before any method started';
                    app.setStatus(msg);
                    app.setCompareStatus(msg);
                    app.ExportButton.Enable = wasExport;
                    bar.finish("cancelled", string(msg));
                    return
                end
                app.setStatus(['error: ' err.message]);
                app.setCompareStatus(['error: ' err.message]);
                % Whatever was exportable before a failed run still is: the
                % previous run's results are untouched by one that threw.
                app.ExportButton.Enable = wasExport;
                bar.finish("failed", "run failed: " + string(err.message));
                uialert(app.UIFigure, getReport(err, 'basic'), 'Run failed');
            end
        end

        function onRunSweep(app)
            %ONRUNSWEEP Run the whole grid, and draw the curves.
            %   Inputs   none
            %   Outputs  none
            %   Utility  run the whole grid, which is the only thing that
            %           separates noise from bias.
            %
            %   Deliberately NOT routed through executeRun. That function's
            %   job is to run one case and refresh every panel that reads
            %   app.Results; a sweep runs two dozen cases and must refresh
            %   none of them.
            %
            %   The same button gating applies for the same reason: the
            %   progress sink's drawnow yields to the event queue, so every
            %   other run button is live during the sweep unless it is
            %   turned off, and pressing one would start a second run inside
            %   this one.
            gate = app.runGate();
            set(gate, 'Enable', 'off');
            restore = onCleanup(@() set(gate, 'Enable', 'on'));

            app.SweepProgress.begin("building the plan");
            drawnow;

            try
                % The kind is FROZEN here, before the run, and the panels
                % are drawn from it afterwards. Reading the dropdown after a
                % twenty-minute sweep would draw whatever was selected in the
                % meantime over results from a different plan.
                app.SweepKind = app.selectedSweepKind();
                spec = app.sweepPlanSpec(app.SweepKind);
                plan = spec.plan();

                % The sweep sets its own budgets per cell, so the seed is
                % the only thing it takes from the tab. Sending the tab's
                % numSamples as well would have the first cell silently
                % overriding it and the label claiming otherwise.
                cfg = app.collectConfig();
                cfg.progress = app.SweepProgress.Reporter;

                app.SweepResult = methods.parameterSweep(plan, cfg);
                app.refreshSweepTab();

                s = app.SweepResult;
                msg = sprintf('%d of %d cells, %d rows, %.0f s, seed %d', ...
                    s.numCompleted, s.numCells, numel(s.rows), ...
                    s.elapsedSeconds, s.seed);
                app.SweepStatusLabel.Text = msg;
                if s.cancelled
                    app.SweepProgress.finish("cancelled", string(msg));
                else
                    app.SweepProgress.finish("ok", string(msg));
                end
            catch err
                % A Stop raised before the first cell finished arrives here
                % rather than as a cancelled sweep, for the reason
                % executeRun documents at its own catch.
                if utils.ProgressReporter.isCancellation(err)
                    app.SweepStatusLabel.Text = 'stopped before any cell finished';
                    app.SweepProgress.finish("cancelled", "stopped");
                    return
                end
                app.SweepStatusLabel.Text = ['error: ' err.message];
                app.SweepProgress.finish("failed", "sweep failed: " + string(err.message));
                uialert(app.UIFigure, getReport(err, 'basic'), 'Sweep failed');
            end
        end

    end

    methods
        function refreshSweepTab(app)
            %REFRESHSWEEPTAB The six panels of the plan that ran, and the rows.
            %   Inputs   none
            %   Outputs  none
            %   Utility  draw the plan that ran, not the plan selected.
            %
            %   PUBLIC, unlike the other refresh methods, and only for one
            %   reason: it is the panel set whose contents depend on WHICH
            %   plan produced them, and a test of that dependence would
            %   otherwise have to run an eighteen-cell sweep inside a UI test
            %   to get a result to draw. A test that expensive is a test that
            %   gets skipped.
            %   Panel titles come from the same spec that chose the metrics,
            %   so a panel cannot be labelled as one quantity and drawn from
            %   another. Runtime is on a linear axis wherever it appears: it
            %   spans one decade, not four, and a log axis on a quantity a
            %   reader compares by ratio only makes the NF-iSAM gap look
            %   smaller than it is.
            s = app.SweepResult;
            spec = app.sweepPlanSpec(app.SweepKind);

            for i = 1:size(spec.panels, 1)
                key = "p" + i;
                ax = app.SweepAxes.(key);
                app.SweepPanels.(key).Title = spec.panels{i, 5};

                metric = string(spec.panels{i, 1});
                if metric == "cliff"
                    viz.plotGridWorldCliff(ax, s);
                    continue
                end

                xAxis = string(spec.panels{i, 2});
                filt = spec.panels{i, 4};

                % "at the largest budget" can only be resolved against the
                % rows that actually ran: a cancelled sweep's largest
                % completed budget is not the plan's largest.
                if isfield(filt, 'largestBudget')
                    filt = rmfield(filt, 'largestBudget');
                    if ~isempty(s.rows) && isfield(s.rows, 'budget')
                        filt.budget = max([s.rows.budget]);
                    end
                end

                if ~isempty(s.rows) && ...
                        (~isfield(s.rows, metric) || ~isfield(s.rows, xAxis))
                    % A sweep from a different plan: say so rather than
                    % throwing out of a refresh that has panels left to draw.
                    cla(ax, 'reset');
                    text(ax, 0.5, 0.5, 'not measured by this plan', ...
                        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                        'FontAngle', 'italic', 'Color', [0.45 0.45 0.45]);
                    axis(ax, 'off');
                    continue
                end

                viz.plotSweepCurve(ax, s, 'Metric', metric, ...
                    'XAxis', xAxis, 'YScale', spec.panels{i, 3}, ...
                    'Filter', filt);
            end

            app.SweepTable.Data = app.sweepTableData();
        end
    end

    methods (Access = private)

        function gate = runGate(app)
            %RUNGATE Every button that starts a run, in ONE list.
            %   Inputs   none
            %   Outputs  GATE, every control that starts a run
            %   Utility  one list, so a second run cannot be started while the
            %           first is going.
            %
            %   Six run paths each disable the others while they work,
            %   because the progress sink's drawnow yields to the event queue
            %   and an enabled button is a run started inside a run. Each
            %   path used to carry its own list, and the lists had already
            %   drifted: three of the four did not know about the Plaza
            %   ladder, and none would have known about the research
            %   measurement. A gate that is missing a button fails silently
            %   and only under a race.
            gate = [app.RunButton, app.CompareRunButton, app.SweepRunButton, ...
                    app.PlazaLadderButton, app.ResearchRunButton, ...
                    app.SurfaceStudyButton, app.SurfaceProfileButton];
            gate = gate(arrayfun(@isgraphics, gate));
        end

        function onRunResearch(app)
            %ONRUNRESEARCH Measure the cost axis, then read the verdicts off it.
            %   Inputs   none
            %   Outputs  none
            %   Utility  measure the cost axis first, then read the verdicts off
            %           what was measured.
            %
            %   ONE SEPARATION, not the full two-pose grid. The question is
            %   about cost against quality across BUDGETS; the extra
            %   separations multiply the run without adding a budget point,
            %   and the four scenarios this leaves already disagree with each
            %   other, which is the fact the verdict table exists to show.
            gate = app.runGate();
            set(gate, 'Enable', 'off');
            restore = onCleanup(@() set(gate, 'Enable', 'on'));

            app.ResearchProgress.begin("building the plan");
            drawnow;

            try
                plan = methods.twoPoseSweepPlan('Separations', 2.2);

                cfg = app.collectConfig();
                cfg.progress = app.ResearchProgress.Reporter;

                % Slices and Smoothed Slices only. Running NF-iSAM here would
                % triple the cost to produce rows that cannot go on either
                % axis of either figure.
                app.ResearchResult = methods.parameterSweep(plan, cfg, ...
                    ["Slices", "Smoothed Slices"]);

                app.populateResearchScenarios();
                app.refreshResearchTab();

                s = app.ResearchResult;
                msg = sprintf('%d of %d cells, %d rows, %.0f s, seed %d', ...
                    s.numCompleted, s.numCells, numel(s.rows), ...
                    s.elapsedSeconds, s.seed);
                if s.cancelled
                    app.ResearchProgress.finish("cancelled", string(msg));
                else
                    app.ResearchProgress.finish("ok", string(msg));
                end
            catch err
                if utils.ProgressReporter.isCancellation(err)
                    app.ResearchStatusLabel.Text = 'stopped before any cell finished';
                    app.ResearchProgress.finish("cancelled", "stopped");
                    return
                end
                app.ResearchStatusLabel.Text = ['error: ' err.message];
                app.ResearchProgress.finish("failed", ...
                    "measurement failed: " + string(err.message));
                uialert(app.UIFigure, getReport(err, 'basic'), 'Measurement failed');
            end
        end

        function onRunSurfaceStudy(app)
            %ONRUNSURFACESTUDY Sweep the case, watch the spectrum. Sheet E2.
            %   Inputs   none
            %   Outputs  none
            %   Utility  sweep the case and watch the spectrum, which is sheet
            %           E2 asked directly.
            %
            %   The app's own budgets are NOT used. This study's measurement
            %   is the SHAPE of a matrix whose dimensions are |X_0| by |S|, so
            %   the budgets that matter to it are the two that set those, and
            %   the ones that do not enter it at all -- the backward pass, the
            %   MMD evaluation -- would only make ten runs slower. The
            %   defaults are the study's own and are reported with the result.
            gate = app.runGate();
            set(gate, 'Enable', 'off');
            restore = onCleanup(@() set(gate, 'Enable', 'on'));

            app.SurfaceProgress.begin("sweeping the case");
            drawnow;

            try
                app.SurfaceStudy = research.surfaceComplexityStudy( ...
                    'Progress', app.SurfaceProgress.Reporter);

                app.populateSurfaceAxes();
                app.refreshSurfaceTab();

                st = app.SurfaceStudy;
                app.SurfaceProgress.finish("ok", sprintf( ...
                    "%d configurations: %s", height(st.rows), st.verdict));
            catch err
                app.onSurfaceError(err);
            end
        end

        function onRunActiveSetProfile(app)
            %ONRUNACTIVESETPROFILE Vary K, and see how small it can get.
            %   Inputs   none
            %   Outputs  none
            %   Utility  vary K, and find out how small the active set can be.
            %
            %   The other half of E2, and the half that carries the sheet's
            %   failure signal: "K must approach |X_{r+1}|". Kept on its own
            %   button because it runs the method once per K and the screening
            %   study does not need to wait for it.
            gate = app.runGate();
            set(gate, 'Enable', 'off');
            restore = onCleanup(@() set(gate, 'Enable', 'on'));

            app.SurfaceProgress.begin("profiling the active set");
            drawnow;

            try
                app.SurfaceProfile = research.activeSetProfile( ...
                    'Progress', app.SurfaceProgress.Reporter);

                viz.plotActiveSetError(app.AxSurfaceActiveSet, app.SurfaceProfile);

                pr = app.SurfaceProfile;
                app.SurfaceStatusLabel.Text = char(pr.headline);
                app.SurfaceProgress.finish("ok", sprintf( ...
                    "%d active set sizes: %s", height(pr.rows), pr.verdict));
            catch err
                app.onSurfaceError(err);
            end
        end

        function onSurfaceError(app, err)
            %ONSURFACEERROR One handler, because the two buttons fail alike.
            %   Inputs   ERR, the caught exception
            %   Outputs  none
            %   Utility  the two research buttons fail in the same ways, so they
            %           report through one handler.
            if utils.ProgressReporter.isCancellation(err)
                app.SurfaceStatusLabel.Text = 'stopped before any configuration finished';
                app.SurfaceProgress.finish("cancelled", "stopped");
                return
            end
            app.SurfaceStatusLabel.Text = ['error: ' err.message];
            app.SurfaceProgress.finish("failed", ...
                "measurement failed: " + string(err.message));
            uialert(app.UIFigure, getReport(err, 'basic'), 'Measurement failed');
        end

        function populateSurfaceAxes(app)
            %POPULATESURFACEAXES The swept axes that have levels to plot.
            %   Inputs   none
            %   Outputs  none
            %   Utility  offer only the axes the study actually swept to more
            %           than one level.
            %
            %   The variant axis is categorical and the control axis is there
            %   to NOT move, so neither makes a curve. Offering them would
            %   produce an empty panel and leave the reader to work out why.
            T = app.SurfaceStudy.rows;
            items = {'(run first)'};
            names = unique(T.axis, 'stable');
            keep = strings(1, 0);
            for i = 1:numel(names)
                lv = T.level(T.axis == names(i));
                if sum(isfinite(lv)) >= 2
                    keep(end+1) = names(i); %#ok<AGROW>
                end
            end
            if ~isempty(keep)
                items = cellstr(keep);
            end
            app.SurfaceAxisDropdown.Items = items;
            app.SurfaceAxisDropdown.Value = items{1};
            app.SurfaceAxisDropdown.Enable = ...
                matlab.lang.OnOffSwitchState(~isempty(keep));
        end

        function refreshSurfaceTab(app)
            %REFRESHSURFACETAB The spectra, one axis of the sweep, and the rows.
            %   Inputs   none
            %   Outputs  none
            %   Utility  draw the study that ran.
            st = app.SurfaceStudy;
            if isempty(st)
                return
            end

            viz.plotSurfaceSpectrum(app.AxSurfaceSpectrum, st);

            which_ = string(app.SurfaceAxisDropdown.Value);
            if which_ == "(run first)", which_ = ""; end
            viz.plotSurfaceRankVsAxis(app.AxSurfaceRank, st, 'Axis', which_);

            app.SurfaceTable.Data = app.surfaceTableData();

            % The control's result leads, because it decides whether the rest
            % of the tab means anything.
            if islogical(st.control.flat) && ~st.control.flat
                app.SurfaceStatusLabel.Text = ['CONTROL FAILED: ' char(st.control.note)];
            else
                app.SurfaceStatusLabel.Text = sprintf('%s -- %s', ...
                    st.verdict, st.evidence);
            end
        end

        function t = surfaceTableData(app)
            %SURFACETABLEDATA One row per configuration, both ranks together.
            %   Inputs   none
            %   Outputs  T, one row per configuration
            %   Utility  show rank and sparsity together, because they are
            %           different claims.
            %
            %   rank_eps and the energy rank are adjacent columns on purpose.
            %   The verdict is taken on the second, which is the smaller and
            %   more flattering of the two, so a table that showed only the
            %   verdict's own number would be showing the answer's evidence
            %   and not its cost.
            st = app.SurfaceStudy;
            if isempty(st) || height(st.rows) == 0
                t = cell(0, 1);
                return
            end
            T = st.rows;
            t = table(T.label, T.rank, T.energyRank99, T.terminalEnergyRank99, ...
                round(T.sparsity, 3), round(T.spectralGap, 3), T.verdict, ...
                'VariableNames', {'configuration', 'rank_eps', 'energy99', ...
                                  'R1_energy99', 'sparsity', 'sigma2_sigma1', ...
                                  'verdict'});
        end

        function populateResearchScenarios(app)
            %POPULATERESEARCHSCENARIOS The scenarios that actually produced rows.
            %   Inputs   none
            %   Outputs  none
            %   Utility  offer only the scenarios that produced rows.
            %
            %   A cancelled run leaves cells that never ran, and offering
            %   those in the dropdown would give a figure that says nothing
            %   was measured when the truth is that nothing was attempted.
            rows = app.ResearchResult.rows;
            items = {'(run first)'};
            if ~isempty(rows) && isfield(rows, 'scenario')
                items = cellstr(unique(string({rows.scenario}), 'stable'));
            end
            app.ResearchScenarioDropdown.Items = items;
            app.ResearchScenarioDropdown.Value = items{1};
            app.ResearchScenarioDropdown.Enable = ...
                matlab.lang.OnOffSwitchState(~isempty(rows));
        end

        function refreshResearchTab(app)
            %REFRESHRESEARCHTAB The figure for one scenario, the verdicts for all.
            %   Inputs   none
            %   Outputs  none
            %   Utility  draw one scenario and every verdict.
            s = app.ResearchResult;
            if isempty(s.rows)
                return
            end

            scenario = string(app.ResearchScenarioDropdown.Value);
            fr = research.costQualityFrontier(s, 'Scenario', scenario);
            viz.plotCostQuality(app.AxResearchCost, fr);

            % The growth panel is the same measurement on different axes, and
            % it is the one that answers the sheet's actual hypothesis: a
            % constant-factor discount and a change in growth class look
            % identical on the cost-quality plot and completely different
            % here.
            viz.plotSweepCurve(app.AxResearchGrowth, s, ...
                'Metric', "factorEvaluations", 'XAxis', "budget", ...
                'Filter', struct('scenario', scenario), ...
                'Label', "factor evaluations");

            ex = research.complexityExponent(s, 'Scenario', scenario);
            alphas = strings(1, 0);
            for i = 1:numel(ex.methods)
                m = ex.methods(i);
                if m.usable
                    alphas(end+1) = sprintf('%s %.2f (r2 %.3f)', ...
                        m.method, m.alpha, m.r2); %#ok<AGROW>
                else
                    alphas(end+1) = sprintf('%s unusable', m.method); %#ok<AGROW>
                end
            end
            utils.setLatexTitle(app.AxResearchGrowth, sprintf( ...
                "work $\\sim N^{\\alpha}$: %s", ...
                strrep(strjoin(alphas, ', '), '_', '\_')));

            app.ResearchStatusLabel.Text = sprintf('%s: %s (%s)', ...
                scenario, fr.verdict, fr.metric);
            app.ResearchTable.Data = app.researchTableData();
        end

        function t = researchTableData(app)
            %RESEARCHTABLEDATA One verdict per scenario, with its evidence.
            %   Inputs   none
            %   Outputs  T, one verdict per scenario
            %   Utility  a verdict without its evidence is an opinion, so both
            %           columns are here.
            %
            %   The evidence string travels WITH the verdict. "reduces" on
            %   its own invites the reader to supply their own reason for it,
            %   and the reason is the part that can be wrong.
            s = app.ResearchResult;
            rows = s.rows;
            if isempty(rows) || ~isfield(rows, 'scenario')
                t = cell(0, 1);
                return
            end

            scen = unique(string({rows.scenario}), 'stable');
            verdict = strings(numel(scen), 1);
            metric = strings(numel(scen), 1);
            evidence = strings(numel(scen), 1);
            for i = 1:numel(scen)
                fr = research.costQualityFrontier(s, 'Scenario', scen(i));
                verdict(i) = fr.verdict;
                metric(i) = fr.metric;
                evidence(i) = fr.evidence;
            end
            t = table(scen(:), verdict, metric, evidence, 'VariableNames', ...
                {'Scenario', 'Verdict', 'Metric', 'Evidence'});
        end

        function t = sweepTableData(app)
            %SWEEPTABLEDATA The rows, in the columns this plan measured.
            %   Inputs   none
            %   Outputs  T, the sweep rows
            %   Utility  show the columns this plan measured, and not the ones
            %           it did not.
            %
            %   The two-pose columns were shown for every plan until the grid
            %   world arrived with no exact reference: relative L1 and MMD are
            %   NaN on every one of its rows, and a table of NaN reads as a
            %   broken run rather than as a metric that does not apply here.
            s = app.SweepResult;
            if isempty(s.rows)
                t = cell(0, 1);
                return
            end

            switch app.SweepKind
                case "grid-world"
                    % NOT 'Variables'. That is a reserved dot-reference on a
                    % table -- t.Variables is the whole contents as a matrix
                    % -- so assigning a column under that name tries to
                    % replace every column at once and fails complaining
                    % about a width, with nothing pointing at the name.
                    want = {'numVariables', 'NumVars'; ...
                            'poseRMSE',     'PoseRMSE'; ...
                            'landmarkRMSE', 'LandmarkRMSE'; ...
                            'minEssSupport','SupportESS'; ...
                            'runtimeTotal', 'RuntimeSec'};
                case "four-doors"
                    want = {'maxModeWeightL1', 'MaxModeL1'; ...
                            'meanMarginalL1',  'MeanMargL1'; ...
                            'collapsedModes',  'Collapsed'; ...
                            'rmse',            'RMSE'; ...
                            'runtimeTotal',    'RuntimeSec'};
                otherwise
                    want = {'relL1Error',   'RelL1Error'; ...
                            'mmd',          'MMD'; ...
                            'rmse',         'RMSE'; ...
                            'runtimeTotal', 'RuntimeSec'};
            end

            t = table(string({s.rows.cellName}).', string({s.rows.method}).', ...
                string({s.rows.status}).', ...
                'VariableNames', {'Cell', 'Method', 'Status'});
            for i = 1:size(want, 1)
                f = want{i, 1};
                if ~isfield(s.rows, f), continue, end
                t.(want{i, 2}) = [s.rows.(f)].';
            end
        end

        function other = otherBar(app, bar)
            %OTHERBAR The run bar on the tab whose button was not pressed.
            %   Inputs   BAR, the bar whose button was pressed
            %   Outputs  OTHER, the bar on the other tab
            %   Utility  a run started on one tab has to be visible and
            %           stoppable from the other.
            if bar == app.RunProgress
                other = app.CompareProgress;
            else
                other = app.RunProgress;
            end
        end

        function clearBarMirrors(app)
            %CLEARBARMIRRORS Unlink the bars once the run that linked them ends.
            %   Inputs   none
            %   Outputs  none
            %   Utility  a mirror outliving its run would paint the next one
            %           onto a dead bar.
            %
            %   Mirroring is a property of a run in flight, not of the app. Left
            %   set, the next run's begin would repaint a bar it was never asked
            %   to drive, and a bar deleted with the figure would be repainted
            %   through a stale handle.
            for b = [app.RunProgress, app.CompareProgress]
                if ~isempty(b) && isvalid(b), b.Mirror = []; end
            end
        end

        function refreshCompareTab(app, summary)
            %REFRESHCOMPARETAB The cards' status lines and the two tables.
            %   Inputs   SUMMARY, the comparison summary
            %   Outputs  none
            %   Utility  fill in the half of each card that only exists after a
            %           run.
            names = ["Slices", "Smoothed Slices", "NF-iSAM"];
            for m = names
                key = matlab.lang.makeValidName(m);
                if ~isfield(app.MethodStatusLabels, key), continue, end
                lbl = app.MethodStatusLabels.(key);
                r = app.resultFor(m);
                if isempty(r)
                    lbl.Text = 'not selected in the last run';
                    lbl.FontColor = [0.40 0.40 0.40];
                elseif r.status == "ok"
                    lbl.Text = sprintf('ok -- %.1f s', r.metrics.runtimeTotal);
                    lbl.FontColor = [0.15 0.45 0.20];
                else
                    lbl.Text = sprintf('%s', r.status);
                    lbl.FontColor = [0.70 0.45 0.10];
                end
            end

            cmp = methods.budgetComparison(app.Results);
            app.BudgetTable.ColumnName = cellstr(cmp.columns);
            app.BudgetTable.Data = cmp.data;
            if cmp.numCompleted < 2
                % Nothing was compared, so nothing agreed. Saying "every budget
                % agreed" here would turn a stopped run into a green tick for a
                % check that never ran -- and this panel exists to catch
                % unstated differences, so a false pass is its worst failure.
                app.BudgetNoteLabel.Text = sprintf( ...
                    ['%d method(s) completed, so the budgets were not ' ...
                     'compared: matching takes two runs to match.'], ...
                    cmp.numCompleted);
                app.BudgetNoteLabel.FontColor = [0.60 0.42 0.10];
            elseif isempty(cmp.notes)
                app.BudgetNoteLabel.Text = ['Every budget above agreed across ' ...
                    'the methods that completed.'];
                app.BudgetNoteLabel.FontColor = [0.15 0.45 0.20];
            else
                app.BudgetNoteLabel.Text = char(strjoin(cmp.notes, '  |  '));
                app.BudgetNoteLabel.FontColor = [0.35 0.35 0.35];
            end

            t = summary.metricsTable;
            keep = intersect({'Method','Status','RuntimeSec','FactorEvals', ...
                              'OuterSamples','SeparatorPts'}, ...
                             t.Properties.VariableNames, 'stable');
            app.RuntimeTable.Data = t(:, keep);
        end

        function r = resultFor(app, methodName)
            %RESULTFOR One method result by name, or empty.
            %   Inputs   METHODNAME, the method
            %   Outputs  R, the result or []
            %   Utility  a method that was not run has no result, and the panels
            %           have to survive that.
            r = [];
            if isempty(app.Results), return, end
            hit = app.Results(arrayfun(@(x) string(x.methodName) == methodName, ...
                app.Results));
            if ~isempty(hit), r = hit(1); end
        end

        function refreshDiagnosticsTab(app)
            %REFRESHDIAGNOSTICSTAB The four tables, from the run just finished.
            %   Inputs   none
            %   Outputs  none
            %   Utility  draw the four tables from methods.diagnosticsReport,
            %           which computed them without a display.
            rep = methods.diagnosticsReport(app.Results);

            app.DiagRuntimeTable.Data  = rep.runtime;
            app.DiagAccuracyTable.Data = rep.accuracy;
            app.DiagReplayTable.Data   = rep.replay;

            % A run with no warnings says so. An empty box is indistinguishable
            % from a box that failed to fill.
            if isempty(rep.warnings)
                app.DiagWarnings.Value = {'no engine warnings were raised'};
            else
                app.DiagWarnings.Value = cellstr(rep.warnings);
            end

            note = rep.memoryNote;
            if ~isempty(rep.notes)
                note = note + newline + newline + strjoin(rep.notes, newline);
            end
            app.DiagNoteLabel.Text = char(note);
        end

        function setCompareStatus(app, msg)
            %SETCOMPARESTATUS Write one line into the Compare Methods status.
            %   Inputs   MSG, the text
            %   Outputs  none
            %   Utility  one place writes it, so it cannot be left saying
            %           something stale.
            if ~isempty(app.CompareStatusLabel) && isgraphics(app.CompareStatusLabel)
                app.CompareStatusLabel.Text = msg;
            end
        end

        function onExport(app)
            %ONEXPORT Export All: every registered axes, plus the bundle.
            %   Inputs   none
            %   Outputs  none
            %   Utility  specification section 14, and the one action that
            %           writes a run to disk.
            %
            % Seventeen axes at 300 dpi in two formats each is not instant, so
            % the export drives the same bar and the same Stop. A stopped
            % export still writes the numerical bundle: metrics.csv and
            % diagnostics.md are the part that took the run to produce, and
            % abandoning them to save a few PNGs would be the wrong way round.
            app.setStatus('exporting...');

            % An export yields to the event queue on every figure, exactly as a
            % run does, so it is reentrant in exactly the same way: Run All
            % pressed during an export would start a run whose results replace
            % the ones being written out underneath it.
            gate = [app.RunButton, app.CompareRunButton, app.ExportButton];
            set(gate, 'Enable', 'off');
            restore = onCleanup(@() set(gate, 'Enable', 'on'));

            app.RunProgress.Mirror = app.otherBar(app.RunProgress);
            clearMirror = onCleanup(@() app.clearBarMirrors());

            app.RunProgress.begin("exporting figures");
            drawnow;
            try
                report = viz.exportAllFiguresAndDiagnostics( ...
                    app.FigureRegistry, app.Results, app.Config, ...
                    'UIFigure', app.UIFigure, ...
                    'Formats', app.selectedExportFormat(), ...
                    'Progress', app.RunProgress.Reporter);
                app.setStatus(report.summary);
                % The dialog says which of the two happened. It used to be
                % headed "Export complete" with a success icon whether or not
                % the user had just stopped it, which makes Stop look like it
                % did nothing and the report beside it look wrong.
                if report.cancelled
                    app.RunProgress.finish("cancelled", string(report.summary));
                    uialert(app.UIFigure, report.summary, 'Export stopped', ...
                        'Icon', 'warning');
                else
                    app.RunProgress.finish("ok", string(report.summary));
                    uialert(app.UIFigure, report.summary, 'Export complete', ...
                        'Icon', 'success');
                end
            catch err
                % No cancellation branch here, unlike executeRun: the exporter
                % reports only from inside its figure loop, and that loop
                % catches its own Stop and returns a report rather than
                % throwing. Nothing reaches this catch except a real failure.
                app.setStatus(['export failed: ' err.message]);
                app.RunProgress.finish("failed", "export failed: " + string(err.message));
                uialert(app.UIFigure, getReport(err, 'basic'), 'Export failed');
            end
        end

        function setStatus(app, msg)
            %SETSTATUS Write one line into the main status label.
            %   Inputs   MSG, the text
            %   Outputs  none
            %   Utility  the same, for the other status line.
            if ~isempty(app.StatusLabel) && isgraphics(app.StatusLabel)
                app.StatusLabel.Text = msg;
            end
        end

        % -----------------------------------------------------------------
        % Process Explorer
        % -----------------------------------------------------------------
        function refreshMapViews(app, k)
            %REFRESHMAPVIEWS Draw the world on both map axes.
            %   Inputs   K, the increment to draw
            %   Outputs  none
            %   Utility  the Case Study and Posterior Recovery tabs show the
            %           same world, and must agree.
            if ~isfield(app.CaseData, 'map')
                for ax = [app.AxMap app.AxProcessMap]
                    if isempty(ax) || ~isgraphics(ax), continue, end
                    cla(ax, 'reset');
                    text(ax, 0.5, 0.5, 'this case has no map', ...
                        'Units', 'normalized', 'HorizontalAlignment', 'center', ...
                        'Interpreter', 'latex');
                    utils.applyLatexToAxes(ax);
                end
                return
            end

            res = app.Results;
            if isempty(res), res = struct([]); end
            for ax = [app.AxMap app.AxProcessMap]
                if isempty(ax) || ~isgraphics(ax), continue, end
                viz.plotMapStep(ax, app.CaseData, res, k);
            end
        end

        function onIncrementChanging(app, evt)
            %ONINCREMENTCHANGING The increment slider moved: redraw the maps.
            %   Inputs   EVT, the slider event
            %   Outputs  none
            %   Utility  redraw while dragging rather than on release, since the
            %           point is to watch it move.
            %
            % Live label while dragging, but no replot until the drag ends:
            % redrawing a full map per pixel of slider travel makes the
            % control feel broken.
            app.IncrementLabel.Text = sprintf('increment k = %d', round(evt.Value));
        end

        function onProcessChanged(app)
            %ONPROCESSCHANGED The stage slider moved: redraw everything.
            %   Inputs   none
            %   Outputs  none
            %   Utility  step through the elimination one stage at a time.
            if app.IsBusy, return, end
            app.IsBusy = true;
            restore = onCleanup(@() app.clearBusy());

            k = round(app.IncrementSlider.Value);
            s = round(app.StageSlider.Value);
            app.IncrementLabel.Text = sprintf('increment k = %d', k);
            app.StageLabel.Text = sprintf('stage %d', s);

            app.refreshMapViews(k);

            % Both graph panels are structural: they replay the elimination
            % from G_0 and need no run at all. Drawing them before Run All is
            % what makes the stage slider useful for reading the procedure
            % rather than only for inspecting a result.
            viz.plotFactorGraphStep(app.AxProcessGraph, app.CaseData, ...
                localSyntheticState(app.CaseData, s));
            viz.plotBayesNetStep(app.AxProcessBayes, app.CaseData, s);

            sel = app.selectedResults();
            if isempty(sel)
                app.ProcessEquation.Text = ...
                    "press \textbf{Run All} on the Posterior Recovery tab";
                app.ProcessCard.Text = "";
                return
            end

            r = sel(1);
            s = min(s, r.process.numStages);
            stage = r.process.stages(s);

            % Once a run exists, prefer its own state: the separator it
            % actually formed is the one worth showing, and a disagreement
            % with the structural replay is a bug that should be visible.
            %
            % One disagreement is not a bug and has to be told apart from the
            % ones that are: an incremental replay eliminates in the order it
            % accumulated, which the case does not carry. Both panels are
            % redrawn against that order so the run and the picture of it are
            % the same elimination.
            ord = localRunOrder(r);
            if ~isempty(ord)
                viz.plotBayesNetStep(app.AxProcessBayes, app.CaseData, s, 'Order', ord);
            end
            if s <= numel(r.states)
                viz.plotFactorGraphStep(app.AxProcessGraph, app.CaseData, ...
                    r.states(s), 'Order', ord);
            end

            viz.plotStageDiagnostics(app.AxProcessStage, sel, s);

            app.ProcessEquation.Text = stage.latex;
            app.ProcessCard.Text = app.stageCardText(r, stage);
        end

        function sel = selectedResults(app)
            %SELECTEDRESULTS The results for the methods currently ticked.
            %   Inputs   none
            %   Outputs  SEL, the results
            %   Utility  the panels draw what is ticked, which need not be
            %           everything that was run.
            sel = [];
            if isempty(app.Results), return, end
            ok = app.Results(arrayfun(@(r) r.status == "ok", app.Results));
            if isempty(ok), return, end

            want = string(app.MethodSelector.Value);
            if want == "Compare"
                sel = ok;
            else
                sel = ok(arrayfun(@(r) string(r.methodName) == want, ok));
                if isempty(sel), sel = ok; end
            end
        end

        function txt = stageCardText(~, r, stage)
            %STAGECARDTEXT Cardinalities in blue, per specification section 16.
            %   Inputs   R the result, STAGE the stage index
            %   Outputs  TXT, the card text
            %   Utility  show the cardinalities in blue, as specification
            %           section 16 requires.
            c = stage.cardinality;
            parts = string.empty(1,0);
            if isfield(c, 'outer') && c.outer > 0
                parts(end+1) = sprintf("$|\\mathcal{X}| = %d$", c.outer);
            end
            if isfield(c, 'separator') && c.separator > 0
                parts(end+1) = sprintf("$|\\mathcal{S}| = %d$", c.separator);
            end
            if isfield(c, 'separatorDim') && c.separatorDim > 0
                parts(end+1) = sprintf("$d_S = %d$", c.separatorDim);
            end

            d = stage.diagnostics;
            if isfield(d, 'essOuter')
                parts(end+1) = sprintf("ESS$_{\\mathrm{outer}} = %.1f$", d.essOuter);
            end
            if isfield(d, 'essSupport')
                parts(end+1) = sprintf("ESS$_{\\mathrm{support}} = %.1f$", d.essSupport);
            end
            if isfield(d, 'sparsification') && isstruct(d.sparsification) ...
                    && d.sparsification.applied
                sp = d.sparsification;
                % retainedMass is a per-row VECTOR on both routes now, so the
                % card reads the summary. It used to print retainedMass with
                % %.2f, which was a scalar mean here and a whole column on the
                % two-pose route -- correct only because this card is reached
                % by the route where it happened to be scalar.
                %
                % The minimum is shown beside the median because the mean hides
                % the case the diagnostic exists for: most rows keeping nearly
                % everything while a few keep almost nothing.
                if sp.isEq49
                    sym = "\\mathcal{N}";
                else
                    % Not the Eq. (49) active set: these are separator points.
                    sym = "\\mathcal{S}_{\\mathrm{kept}}";
                end
                parts(end+1) = sprintf( ...
                    "$|%s| = %d$, mass kept: median $%.2f$, min $%.2f$", ...
                    sym, sp.activeSetSize, sp.retainedMassMedian, sp.retainedMassMin);
            end
            if isfield(d, 'route')
                parts(end+1) = "route: " + string(d.route);
            end

            % The terminal stage has no separator and no support, so every
            % cardinality is zero and the card came out as a method name and
            % a dash. Say what the stage is instead of showing nothing.
            if isempty(parts)
                parts(end+1) = "root marginal: no separator, nothing left to condition on";
            end

            txt = sprintf("%s -- %s", string(r.methodName), ...
                strjoin(cellstr(parts), ", "));
        end

        function onPlayToggled(app, src)
            %ONPLAYTOGGLED The Play button: start or stop the animation timer.
            %   Inputs   SRC, the button
            %   Outputs  none
            %   Utility  animate the increments without blocking the UI.
            if src.Value
                src.Text = 'Pause';
                app.startTimer();
            else
                src.Text = 'Play';
                app.stopTimer();
            end
        end

        function startTimer(app)
            %STARTTIMER Start the animation timer, replacing any previous one.
            %   Inputs   none
            %   Outputs  none
            %   Utility  a second timer would advance the slider twice per tick.
            app.stopTimer();
            % Specification section 20: the timer advances ONE frame and does
            % no algorithm work. Everything it shows was computed by Run All.
            app.Timer = timer('ExecutionMode', 'fixedSpacing', ...
                'Period', 0.4, 'TimerFcn', @(~,~) app.advanceOneFrame());
            start(app.Timer);
        end

        function stopTimer(app)
            %STOPTIMER Stop and delete the animation timer.
            %   Inputs   none
            %   Outputs  none
            %   Utility  a timer left running holds the app alive after the
            %           window closes.
            if ~isempty(app.Timer) && isvalid(app.Timer)
                stop(app.Timer);
                delete(app.Timer);
            end
            app.Timer = [];
        end

        function advanceOneFrame(app)
            %ADVANCEONEFRAME Advance the increment slider by one, wrapping.
            %   Inputs   none
            %   Outputs  none
            %   Utility  the timer callback, and the only thing it does.
            if app.IsBusy, return, end
            if isempty(app.UIFigure) || ~isgraphics(app.UIFigure)
                app.stopTimer();
                return
            end
            k = round(app.IncrementSlider.Value) + 1;
            if k > app.IncrementSlider.Limits(2)
                k = app.IncrementSlider.Limits(1);
            end
            app.IncrementSlider.Value = k;
            app.onProcessChanged();
            drawnow limitrate;
        end

        function clearBusy(app)
            %CLEARBUSY Clear the busy state after a run or an error.
            %   Inputs   none
            %   Outputs  none
            %   Utility  restore the pointer and re-enable the run gate on both
            %           exits.
            app.IsBusy = false;
        end

        function onExportFrame(app)
            %ONEXPORTFRAME Write the current map view to an image file.
            %   Inputs   none
            %   Outputs  none
            %   Utility  capture one frame of the animation, which the exporter
            %           does not.
            try
                runDir = utils.createRunFolder(app.Status.root, app.Config);
                figDir = fullfile(runDir, 'figures');
                if ~isfolder(figDir), mkdir(figDir); end
                k = round(app.IncrementSlider.Value);
                s = round(app.StageSlider.Value);
                stem = sprintf('frame_k%02d_s%02d', k, s);
                for ax = [app.AxProcessMap app.AxProcessGraph ...
                          app.AxProcessBayes app.AxProcessStage]
                    if isempty(ax) || ~isgraphics(ax), continue, end
                    exportgraphics(ax, fullfile(figDir, ...
                        sprintf('%s_%s.png', stem, matlab.lang.makeValidName(ax.Title.String))), ...
                        'Resolution', 200);
                end
                app.setStatus(sprintf('frame exported to %s', figDir));
            catch err
                app.setStatus(['frame export failed: ' err.message]);
            end
        end
    end
end

% =========================================================================
function st = localSyntheticState(caseData, step)
%LOCALSYNTHETICSTATE A minimal EliminationState for the structural panels.
%   Inputs   CASEDATA the case, STEP the elimination step
%   Outputs  ST, a minimal core.EliminationState
%   Utility  let the graph panels show the procedure on a case nobody has run
%           yet.
%
%   The two graph panels need only j, omega_j and S_j, all of which follow
%   from the elimination order and G_0. Building one here lets the Process
%   Explorer step through the procedure before Run All has been pressed,
%   which is what turns it from a result viewer into the teaching panel
%   specification section 10 asks for.
%   The separator comes from core.eliminationSchedule, not from repeatedly
%   calling removeVariable: removing a variable deletes its factors without
%   putting the generated clique back, so the separator at step three would
%   be missing every fill edge the first two steps created.
sched = core.eliminationSchedule(caseData.graph, caseData.eliminationOrder);
step = max(1, min(step, numel(sched)));

st = core.EliminationState(step, sched(step).frontal);
st.Separator = sched(step).separator;
end

% =========================================================================
function ord = localRunOrder(r)
%LOCALRUNORDER The order a RESULT was actually produced in, or empty.
%   Inputs   R, a method result
%   Outputs  ORD, the order it eliminated in, or empty
%   Utility  an incremental replay appends to the previous order, so the case
%           order may not be the one that ran.
%
%   Empty means "the case's own order", which is the batch pass and every
%   run this project made before the replay existed. Only an incremental
%   result carries an order of its own, and only its LAST increment's order
%   covers the whole graph.
ord = string.empty(1, 0);
if ~isfield(r, 'increment') || isempty(r.increment), return, end
if ~isfield(r.increment, 'order'), return, end
last = r.increment(end).order;
if isstring(last) && ~isempty(last)
    ord = last;
end
end
