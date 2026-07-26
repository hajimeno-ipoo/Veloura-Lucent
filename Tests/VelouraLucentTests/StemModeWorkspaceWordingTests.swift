import Foundation
import Testing

struct StemModeWorkspaceWordingTests {
    @Test
    func workspaceKeepsApprovedProductionAndSoundQualityContractsVisible() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/App/VelouraCommands.swift",
            "Sources/VelouraLucent/Views/WorkspaceToolbarView.swift",
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift",
            "Sources/VelouraLucent/Views/StemModeSidebarView.swift",
            "Sources/VelouraLucent/Views/StemModePreviewView.swift",
            "Sources/VelouraLucent/Views/StemWaveformComparisonView.swift",
            "Sources/VelouraLucent/Views/AudioWaveformWorkspaceView.swift",
            "Sources/VelouraLucent/Views/StemModeDetailedAnalysisWorkspaceView.swift",
            "Sources/VelouraLucent/Views/StemModeInspectorView.swift",
            "Sources/VelouraLucent/Views/StemModeFooterView.swift",
            "Sources/VelouraLucent/Views/RecentProcessingLogView.swift",
            "Sources/VelouraLucent/Views/OverallWorkflowView.swift",
            "Sources/VelouraLucent/Views/ProcessingLogView.swift"
        ])

        #expect(source.contains("補正をキャンセル"))
        #expect(source.contains("マスタリングをキャンセル"))
        #expect(!source.contains("保存して中断"))
        #expect(!source.contains("現在のrun IDに対する処理更新を止めます"))
        #expect(source.contains("True Peak"))
        #expect(source.contains("dBTP"))
        #expect(!source.contains("Raw／試聴用ピーク"))
        #expect(!source.contains("試聴用共通ゲイン"))
        #expect(!source.contains("Sample Peakから推測して補完していません。"))
        #expect(!source.localizedCaseInsensitiveContains("corpus"))
        #expect(source.contains("通常モードと同じ二段階操作"))
        #expect(source.contains("raw使用"))
        #expect(source.contains("DSP最終適用結果"))
        #expect(!source.contains("採用したStem"))
        #expect(source.contains("Button(\"A/B切替\")"))
        #expect(source.contains("Button(\"rawを再生\")"))
        #expect(source.contains("Button(\"補正後を再生\")"))
        #expect(source.contains("Button(\"raw／補正後切替\")"))
        #expect(source.contains("title: \"分離直後（raw）\""))
        #expect(source.contains("title: \"補正後Stem\""))
        #expect(source.contains("stemPreviewController"))
        #expect(source.contains("onWillStartPlayback: model.stopStemPreviewPlayback"))
        #expect(source.contains("補正ログ"))
        #expect(source.contains("マスタリングログ"))
        #expect(source.contains("直近ログ"))
        #expect(source.contains("全体進捗"))
    }

    @Test
    func workspaceReusesStandardModeStatusColorsAndTitlebarToggles() throws {
        let root = try source(
            "Sources/VelouraLucent/Views/VelouraRootView.swift"
        )
        let workspace = try source(
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift"
        )
        let sidebar = try source(
            "Sources/VelouraLucent/Views/StemModeSidebarView.swift"
        )
        let processingStart = try #require(
            sidebar.range(of: "private struct StemModeSidebarProcessingStatusView")
        )
        let processingSidebar = String(sidebar[processingStart.lowerBound...])

        #expect(root.contains(
            "TitlebarSidebarToggleConfigurator("
        ))
        #expect(root.contains(
            "TitlebarInspectorToggleConfigurator("
        ))
        #expect(!workspace.contains("TitlebarSidebarToggleConfigurator("))
        #expect(!workspace.contains("TitlebarInspectorToggleConfigurator("))
        #expect(!workspace.contains("Button(\"インスペクタ\""))
        #expect(!workspace.contains("private func toggleInspector()"))
        #expect(processingSidebar.contains("ProcessingStatusColors.active"))
        #expect(processingSidebar.contains("ProcessingStatusColors.complete"))
        #expect(!processingSidebar.contains("tint: .green"))
        #expect(!processingSidebar.contains("tint: .orange"))
    }

    @Test
    func rootAndStemWorkspaceReuseStandardLiquidGlassToolbarAndHeaderLayout() throws {
        let root = try source(
            "Sources/VelouraLucent/Views/VelouraRootView.swift"
        )
        let standardWorkspace = try source(
            "Sources/VelouraLucent/Views/ContentView.swift"
        )
        let stemWorkspace = try source(
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift"
        )
        let inspector = try source(
            "Sources/VelouraLucent/Views/StemModeInspectorView.swift"
        )
        let sharedToolbarLabel = try source(
            "Sources/VelouraLucent/Views/LiquidGlassToolbarLabel.swift"
        )
        let processingModePicker = try source(
            "Sources/VelouraLucent/Views/ProcessingModeToolbarPicker.swift"
        )
        let workspaceToolbar = try source(
            "Sources/VelouraLucent/Views/WorkspaceToolbarView.swift"
        )
        let workspaceShell = try source(
            "Sources/VelouraLucent/Views/WorkspaceShellView.swift"
        )
        let modelManagement = try source(
            "Sources/VelouraLucent/Views/StemModelManagementSection.swift"
        )
        let liquidGlassActionButton = try source(
            "Sources/VelouraLucent/Views/LiquidGlassActionButton.swift"
        )

        #expect(root.contains("processingMode: processingModeBinding"))
        #expect(root.contains("isSidebarPresented: isSidebarPresented"))
        #expect(root.contains("isInspectorPresented: isInspectorPresented"))
        #expect(root.components(separatedBy: "isAvailable: true").count == 3)
        #expect(!root.contains("isWorkspaceChromeAvailable"))
        #expect(!root.contains("StemModelRecoveryView"))
        #expect(!root.contains("workspaceOrRecovery"))
        #expect(!root.contains("ToolbarItem(placement: .automatic)"))
        #expect(root.contains(
            "ToolbarItem(placement: .principal) {\n                WorkspaceToolbarView("
        ))
        #expect(
            root.components(
                separatedBy: "ToolbarItem(placement: .principal)"
            ).count == 2
        )
        #expect(!standardWorkspace.contains("ToolbarItem(placement: .principal)"))
        #expect(!stemWorkspace.contains("ToolbarItem(placement: .principal)"))
        #expect(!standardWorkspace.contains("ToolbarSpacer("))
        #expect(!stemWorkspace.contains("ToolbarSpacer("))
        #expect(!stemWorkspace.contains("ToolbarItem(placement: .primaryAction)"))
        #expect(root.contains("modelManager: runtime.stemModelManager"))
        #expect(inspector.contains("StemModelManagementSection("))
        #expect(inspector.contains("case .app:"))
        #expect(modelManagement.contains("Text(\"Stem分離\")"))
        #expect(modelManagement.contains("LabeledContent(\"モデル状態\")"))
        #expect(modelManagement.contains("Text(presentation.title)"))
        #expect(modelManagement.contains("Text(presentation.message)"))
        #expect(modelManagement.contains("Text(\"選択できる操作\")"))
        #expect(modelManagement.contains("HStack(spacing: 10)"))
        #expect(modelManagement.contains("LiquidGlassActionButton("))
        #expect(modelManagement.contains("layout: .inspectorWide"))
        #expect(!modelManagement.contains(".buttonStyle(.bordered)"))
        #expect(liquidGlassActionButton.contains("var layout: Layout = .compact"))
        #expect(liquidGlassActionButton.contains("case inspectorWide"))
        #expect(liquidGlassActionButton.contains(
            "minHeight: 32, alignment: .center"
        ))
        #expect(liquidGlassActionButton.contains(".onHover(perform: updateHover)"))
        #expect(liquidGlassActionButton.contains(".liquidGlassCapsuleMorphSurface("))
        #expect(liquidGlassActionButton.contains("LiquidGlassMotion.perform("))
        #expect(modelManagement.contains("systemImage: \"exclamationmark.circle\""))
        #expect(modelManagement.contains("title = \"モデル検証\""))
        #expect(modelManagement.contains("title = \"モデル再取得\""))
        #expect(modelManagement.contains("shifts / overlap"))
        #expect(modelManagement.contains("split / segment"))
        #expect(modelManagement.contains("batch size / run seed"))
        #expect(modelManagement.contains("入力選択後に生成"))
        #expect(!inspector.contains("onManageModels"))
        #expect(!standardWorkspace.contains(".background(TitlebarSidebarToggleConfigurator"))
        #expect(!standardWorkspace.contains(".background(TitlebarInspectorToggleConfigurator"))
        #expect(!stemWorkspace.contains(".background(TitlebarSidebarToggleConfigurator"))
        #expect(!stemWorkspace.contains(".background(TitlebarInspectorToggleConfigurator"))
        #expect(root.contains("VelouraSidebarView(job: runtime.standardActions.job)"))
        #expect(root.contains("StemModeSidebarView(model: runtime.stemWorkspaceModel)"))
        #expect(workspaceShell.contains("static let sidebarMinimumWidth: CGFloat = 220"))
        #expect(workspaceShell.contains("static let sidebarIdealWidth: CGFloat = 260"))
        #expect(workspaceShell.contains("static let sidebarMaximumWidth: CGFloat = 300"))
        #expect(workspaceShell.contains("static let minimumCenterWidth: CGFloat = 620"))
        #expect(workspaceShell.contains("static let inspectorWidth: CGFloat = 440"))
        #expect(workspaceShell.contains(
            "NavigationSplitView(columnVisibility: $sidebarVisibility)"
        ))
        #expect(workspaceShell.contains(".navigationSplitViewStyle(.prominentDetail)"))
        #expect(workspaceShell.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(!standardWorkspace.contains("NavigationSplitView("))
        #expect(!stemWorkspace.contains("NavigationSplitView("))
        #expect(processingModePicker.contains("LiquidGlassSegmentedPicker("))
        #expect(!processingModePicker.contains("ToolbarItem("))
        #expect(!processingModePicker.contains("ToolbarItem(placement: .navigation)"))
        #expect(processingModePicker.contains("options: ProcessingMode.allCases"))
        #expect(!processingModePicker.contains(".pickerStyle(.segmented)"))

        #expect(workspaceToolbar.contains("HStack(spacing: 8)"))
        #expect(workspaceToolbar.contains("ProcessingModeToolbarPicker("))
        #expect(workspaceToolbar.contains("private var actionGroup: some View"))
        #expect(workspaceToolbar.contains("private var exportMenu: some View"))
        #expect(!workspaceToolbar.contains("isStemReady"))
        #expect(!workspaceToolbar.contains("standardActionGroup"))
        #expect(!workspaceToolbar.contains("stemActionGroup"))
        #expect(!workspaceToolbar.contains("standardExportMenu"))
        #expect(!workspaceToolbar.contains("stemExportMenu"))
        #expect(workspaceToolbar.contains("commandActions.runCorrection()"))
        #expect(workspaceToolbar.contains("commandActions.cancelCorrection()"))
        #expect(workspaceToolbar.contains("commandActions.runMastering()"))
        #expect(workspaceToolbar.contains("commandActions.cancelMastering()"))
        #expect(root.contains("runCorrection: actions.startCorrectionProcessing"))
        #expect(root.contains("Task { await model.beginCorrection() }"))
        #expect(root.contains("runMastering: actions.startMasteringProcessing"))
        #expect(root.contains("Task { await model.beginMastering() }"))
        #expect(workspaceToolbar.contains("@State private var highlightedTarget"))
        #expect(workspaceToolbar.contains("@Namespace private var glassNamespace"))
        #expect(workspaceToolbar.contains(".onHover { updateHighlight("))
        #expect(root.contains(".sharedBackgroundVisibility(.hidden)"))
        #expect(sharedToolbarLabel.contains(".liquidGlassCapsuleMorphSurface("))
        #expect(workspaceToolbar.contains(".accessibilityLabel(\"書き出し\")"))
        #expect(workspaceToolbar.contains("ForEach(commandActions.exportActions)"))
        #expect(root.contains(".correctedRemix48000"))
        #expect(root.contains(".correctedStem(.drums)"))
        #expect(root.contains(".correctedStem(.bass)"))
        #expect(root.contains(".correctedStem(.other)"))
        #expect(root.contains(".correctedStem(.vocals)"))
        #expect(root.contains(".finalMaster"))

        #expect(stemWorkspace.contains("private var fixedHeader: some View"))
        #expect(stemWorkspace.contains("WorkspaceFixedHeaderView("))
        #expect(workspaceShell.contains(".font(.largeTitle.bold())"))
        #expect(workspaceShell.contains(".padding(.horizontal, 24)"))
        #expect(workspaceShell.contains(".padding(.bottom, 12)"))
        #expect(workspaceShell.contains(".scrollEdgeEffectStyle(.soft, for: .top)"))
        #expect(!stemWorkspace.contains("maxWidth: 240"))
    }

    @Test
    func stemEvaluationShowsOneWayCorrectionEvidenceWithoutCorpusDependency() throws {
        let source = try source(
            "Sources/VelouraLucent/Views/StemModeDetailedAnalysisWorkspaceView.swift"
        )

        #expect(!source.localizedCaseInsensitiveContains("corpus"))
        #expect(source.contains("Stem固有解析"))
        #expect(source.contains("DSP最終適用結果"))
        #expect(source.contains("usedRawFallback"))
        #expect(source.contains("rawを使用しました"))
        #expect(!source.localizedCaseInsensitiveContains("candidate"))
        #expect(!source.contains("selectedSource"))
        #expect(source.contains(".accessibilityElement(children: .contain)"))
        #expect(!source.contains("private var header: some View"))
        #expect(!source.contains("Text(\"詳細解析\")"))
        #expect(!source.contains("数値だけで音質を自動判定しません。"))
    }

    @Test
    func stemWaveformComparisonUsesTheSharedTimeRulerAndHoverPosition() throws {
        let source = try source(
            "Sources/VelouraLucent/Views/StemWaveformComparisonView.swift"
        )

        #expect(source.contains("hoveredWaveformProgress"))
        #expect(source.contains("hoveredWaveformTarget"))
        #expect(source.contains("WaveformTimeRulerView(duration: waveformDuration)"))
        #expect(source.contains("hoverProgress: hoveredWaveformProgress"))
        #expect(source.contains("onHover: { progress in"))
    }

    @Test
    func stemDetailedAnalysisReusesTheStandardDisplayAndAddsStemEvidence() throws {
        let standard = try source(
            "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"
        )
        let stem = try source(
            "Sources/VelouraLucent/Views/StemModeDetailedAnalysisWorkspaceView.swift"
        )

        #expect(standard.contains("struct DetailedAnalysisComparisonView"))
        #expect(standard.contains("struct DetailedAnalysisPresentation"))
        #expect(stem.contains("DetailedAnalysisComparisonView(presentation: commonPresentation)"))
        #expect(!stem.contains("private func metricComparison("))
        #expect(!stem.contains("private func timelineCharts("))
        #expect(!stem.contains("private func spectrumComparison("))
        #expect(stem.contains("roleAnalysisSnapshot"))
        #expect(stem.contains("protectionEvidence"))
        #expect(stem.contains("rawRemixEvaluation"))
        #expect(stem.contains("validation.measurements"))
        #expect(stem.contains("validation.analysisIssues"))
        #expect(stem.contains("音声を選ぶと、入力、補正後再ミックス、Stem Mode最終版"))
        #expect(!stem.contains("補正段の入力解析が完了すると"))
        #expect(stem.contains("@State private var showStemSpecificAnalysis = false"))
        #expect(stem.contains("@State private var showRemixSpecificAnalysis = false"))
        #expect(stem.contains("DisclosureToggleButton("))
        #expect(stem.contains("TermHelpButton("))
        #expect(stem.contains("isExpanded: $showStemSpecificAnalysis"))
        #expect(stem.contains("isExpanded: $showRemixSpecificAnalysis"))
        #expect(standard.contains("func analysisCard() -> some View"))
        #expect(standard.contains("DisclosureToggleButton("))
        #expect(stem.contains(".analysisCard()"))
        #expect(stem.contains("DisclosureToggleButton("))
        #expect(!stem.contains("stemAnalysisCard"))
        #expect(!stem.contains(".font(.caption"))
        #expect(stem.contains("各DSPの最終適用結果"))
        #expect(stem.contains("route決定の詳しい理由や処理経過は詳細ログ"))
        #expect(stem.contains("Text(\"DSP最終適用結果\")"))
        #expect(!stem.contains("通常モードroute、DSPと役割別guardの結果"))
    }

    @Test
    func workspaceHasNoSavedRunOrCrossLaunchResumeSurface() throws {
        let workspace = try source(
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift"
        )
        let models = try source(
            "Sources/VelouraLucent/Models/StemModeWorkspaceModels.swift"
        )

        #expect(!workspace.contains("保存済みrun"))
        #expect(!workspace.contains("StemModeResumeRunsView"))
        #expect(!workspace.contains("保存して中断"))
        #expect(!models.contains("loadResumeRuns"))
        #expect(!models.contains("resumeRun"))
        #expect(!models.contains("discardResumeRun"))
    }

    @Test
    func fullProcessingLogReplacesTheRegularWorkspaceAndFooter() throws {
        let workspace = try source(
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift"
        )
        let shell = try source(
            "Sources/VelouraLucent/Views/WorkspaceShellView.swift"
        )

        #expect(workspace.contains("WorkspaceCenterLayout("))
        #expect(workspace.contains("StemModeFullProcessingLogView("))
        #expect(workspace.contains("StemModeFooterView("))
        #expect(shell.contains("if isFullLogPresented"))
        #expect(shell.contains("fullLog()"))
        #expect(shell.contains("Divider()"))
        #expect(shell.contains("footer()"))
    }

    @Test
    func previewUsesTheSameThreeProcessingStagesAsStandardMode() throws {
        let preview = try combinedSource([
            "Sources/VelouraLucent/Views/StemModePreviewView.swift",
            "Sources/VelouraLucent/Views/AudioWaveformWorkspaceView.swift"
        ])
        let model = try source(
            "Sources/VelouraLucent/Models/StemModeWorkspaceModel.swift"
        )

        #expect(!preview.contains("Text(\"基本表示\")"))
        #expect(!preview.contains("A/B試聴は品質を自動判定する処理ではありません。"))
        #expect(!preview.contains("4 raw Stem"))
        #expect(!preview.contains("No Vocals"))
        #expect(!preview.contains("試聴版"))
        #expect(preview.contains("Aを再生"))
        #expect(preview.contains("Bを再生"))
        #expect(preview.contains("A/B切替"))
        #expect(preview.contains("波形と試聴比較"))
        #expect(preview.contains("試聴音量"))
        #expect(model.contains("let previewController = AudioPreviewController()"))
        #expect(model.contains("func updatePreviewSources"))
        #expect(model.contains("finalCommitLockState == .unlocked"))
        #expect(model.contains("!isStartingRun"))
    }

    @Test
    func resultsExposeEveryApprovedArtifactInTheApprovedOrder() throws {
        let resultsSource = try source(
            "Sources/VelouraLucent/Views/WorkspaceToolbarView.swift"
        )
        let rootSource = try source(
            "Sources/VelouraLucent/Views/VelouraRootView.swift"
        )
        let models = try source(
            "Sources/VelouraLucent/Models/StemModeWorkspaceModels.swift"
        )

        #expect(rootSource.contains("model.exportableArtifacts"))
        #expect(rootSource.contains("kind.stemModeDisplayTitle"))
        #expect(rootSource.contains(".correctedRemix48000"))
        #expect(rootSource.contains(".correctedStem(.drums)"))
        #expect(rootSource.contains(".correctedStem(.bass)"))
        #expect(rootSource.contains(".correctedStem(.other)"))
        #expect(rootSource.contains(".correctedStem(.vocals)"))
        #expect(rootSource.contains(".finalMaster"))
        #expect(resultsSource.contains("ForEach(commandActions.exportActions)"))
        #expect(resultsSource.contains("補正後2mix、補正済みStemまたはStem Mode最終版を書き出します"))
        #expect(!resultsSource.contains("raw Stem"))
        #expect(!resultsSource.contains("No Vocals"))
        #expect(!resultsSource.contains("試聴版"))
        #expect(resultsSource.contains("ForEach(AudioExportFormat.allCases)"))
        #expect(models.contains("exportArtifact: @MainActor (StemAudioArtifact, AudioExportFormat) async throws -> URL"))

        let correctedRemix = try #require(
            rootSource.range(of: ".correctedRemix48000")
        )
        let correctedStems = try #require(
            rootSource.range(of: ".correctedStem(.drums)")
        )
        let finalMaster = try #require(
            rootSource.range(of: ".finalMaster")
        )
        #expect(correctedRemix.lowerBound < correctedStems.lowerBound)
        #expect(correctedStems.lowerBound < finalMaster.lowerBound)
    }

    @Test
    func workspaceUsesImmediateCancellationWithoutThreeChoiceInterruption() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/WorkspaceToolbarView.swift",
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift",
            "Sources/VelouraLucent/Models/StemModeWorkspaceModel.swift",
            "Sources/VelouraLucent/Models/StemModeWorkspaceModels.swift"
        ])

        #expect(!source.contains("switchToStandard"))
        #expect(source.contains("cancelCorrection"))
        #expect(source.contains("cancelMastering"))
        #expect(!source.contains("保存して中断"))
        #expect(!source.contains("成果物を破棄"))
        #expect(!source.contains("処理を続ける"))
    }

    @Test
    func analysisModeIsShownAndConnectedToTheCurrentStemSession() throws {
        let inspector = try source(
            "Sources/VelouraLucent/Views/StemModeInspectorView.swift"
        )
        let workspaceModel = try source(
            "Sources/VelouraLucent/Models/StemModeWorkspaceModel.swift"
        )
        let workflow = try source(
            "Sources/VelouraLucent/Services/StemWorkflowService.swift"
        )
        let evaluator = try source(
            "Sources/VelouraLucent/Services/StemAudioEvaluationService.swift"
        )
        let correction = try source(
            "Sources/VelouraLucent/Services/StemCorrectionService.swift"
        )

        #expect(inspector.contains("解析モード"))
        #expect(inspector.contains("$model.selectedAnalysisMode"))
        #expect(workspaceModel.contains("analysisMode: StemAudioAnalysisMode(selectedAnalysisMode)"))
        #expect(workflow.contains("let analysisMode: StemAudioAnalysisMode"))
        #expect(!workflow.contains("checkpoint"))
        #expect(evaluator.contains("request.analysisMode.resolvedAudioAnalysisMode"))
        #expect(correction.contains("rawEvaluation.request.analysisMode.resolvedAudioAnalysisMode"))
    }

    @Test
    func obsoleteSixPageViewsAreRemovedAfterIntegration() {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let obsoletePaths = [
            "Sources/VelouraLucent/Views/StemModeOverviewView.swift",
            "Sources/VelouraLucent/Views/StemModeQualityReportsView.swift",
            "Sources/VelouraLucent/Views/StemModeResultsView.swift",
            "Sources/VelouraLucent/Views/StemModeStemEvaluationView.swift",
        ]

        for path in obsoletePaths {
            #expect(!FileManager.default.fileExists(atPath: repositoryRoot.appending(path: path).path))
        }
    }

    private func combinedSource(_ paths: [String]) throws -> String {
        try paths.map(source).joined(separator: "\n")
    }

    private func source(_ relativePath: String) throws -> String {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repositoryRoot.appending(path: relativePath),
            encoding: .utf8
        )
    }
}
