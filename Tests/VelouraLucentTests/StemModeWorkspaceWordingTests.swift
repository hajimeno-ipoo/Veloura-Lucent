import Foundation
import Testing

struct StemModeWorkspaceWordingTests {
    @Test
    func workspaceKeepsApprovedProductionAndSoundQualityContractsVisible() throws {
        let remixComparison = try source(
            "Sources/VelouraLucent/Views/StemRemixComparisonView.swift"
        )
        let stemWorkspace = try source(
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift"
        )
        let source = try combinedSource([
            "Sources/VelouraLucent/App/VelouraCommands.swift",
            "Sources/VelouraLucent/Views/WorkspaceToolbarView.swift",
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift",
            "Sources/VelouraLucent/Views/StemModeSidebarView.swift",
            "Sources/VelouraLucent/Views/StemModePreviewView.swift",
            "Sources/VelouraLucent/Views/StemRemixComparisonView.swift",
            "Sources/VelouraLucent/Views/StemModeRemixSettingsView.swift",
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
        #expect(source.contains("再ミックスと既存マスタリングを独立して実行します"))
        #expect(stemWorkspace.contains(
            "summary: \"4／6Stem分離・Stem別補正を基準に、再ミックスと既存マスタリングを独立して実行します\""
        ))
        #expect(!stemWorkspace.contains(
            "summary: \"\\(model.availableStemRoles.count)Stem分離"
        ))
        #expect(source.contains("raw使用"))
        #expect(source.contains("DSP最終適用結果"))
        #expect(!source.contains("採用したStem"))
        #expect(source.contains("comparisonSwitchCommandTitle ?? \"A/B切替\""))
        #expect(source.contains("sideAButtonTitle: \"rawを再生\""))
        #expect(source.contains("sideBButtonTitle: \"補正後を再生\""))
        #expect(source.contains("switchButtonTitle: \"raw／補正後切替\""))
        #expect(source.contains("title: \"分離直後（raw）\""))
        #expect(source.contains("title: \"補正後Stem\""))
        #expect(source.contains("stemPreviewController"))
        #expect(source.contains("AudioWaveformWorkspaceView("))
        #expect(source.contains("workspaceTitle: \"補正後／再ミックス A/B\""))
        #expect(source.contains("sideAButtonTitle: \"補正後を再生\""))
        #expect(source.contains("sideBButtonTitle: \"再ミックスを再生\""))
        #expect(remixComparison.contains("title: \"再ミックス\""))
        #expect(remixComparison.contains("accessibilityLabel: \"再ミックスの波形\""))
        #expect(!remixComparison.contains("title: \"Stem再ミックス\""))
        #expect(!source.contains("補正済み純粋加算"))
        #expect(!source.contains("workspaceTitle: \"純粋加算／再ミックス A/B\""))
        #expect(source.contains("手動"))
        #expect(source.contains("自動値"))
        #expect(source.contains("補正ログ"))
        #expect(source.contains("マスタリングログ"))
        #expect(source.contains("直近ログ"))
        #expect(source.contains("全体進捗"))
    }

    @Test
    func remixSettingsFollowStandardInspectorControlsWithoutDuplicateActions() throws {
        let remix = try source(
            "Sources/VelouraLucent/Views/StemModeRemixSettingsView.swift"
        )
        let sidebar = try source(
            "Sources/VelouraLucent/Views/StemModeSidebarView.swift"
        )
        let knob = try source(
            "Sources/VelouraLucent/Views/DAWKnobControl.swift"
        )

        #expect(remix.components(separatedBy: "\"手動\"").count - 1 == 1)
        #expect(remix.contains("TermHelpButton(\n                        title: \"再ミックス調整\""))
        #expect(remix.contains("全Stemの音量が0 dB、パンが0"))
        #expect(remix.contains("Stem間の衝突回避が無効または0"))
        #expect(remix.contains("再ミックス後は補正後とほぼ同じ音になります"))
        #expect(!remix.contains("パンが中央"))
        #expect(remix.contains("let plan = model.automaticRemixPlan"))
        #expect(remix.contains(
            "let effective = model.displayedRemixSettings"
        ))
        #expect(remix.contains(
            "補正後に自動値を算出します。現在は中立値を表示しています。"
        ))
        #expect(remix.contains(
            "補正前の手動値を保持しています。補正後は未変更項目に自動値を使用します。"
        ))
        #expect(!remix.contains("再ミックス設定は補正後に準備されます"))
        #expect(!remix.contains("if let plan = model.automaticRemixPlan"))
        #expect(
            remix.components(
                separatedBy: ".disabled(model.isRemixSettingsDisabled)"
            ).count - 1 == 1
        )
        #expect(remix.contains(
            "isInteractionEnabled: !model.isRemixSettingsDisabled"
        ))
        #expect(knob.contains("isInteractionEnabled: Bool = true"))
        #expect(
            knob.components(
                separatedBy: ".disabled(!isInteractionEnabled)"
            ).count - 1 == 2
        )
        #expect(remix.contains(".frame(width: DAWKnobMetrics.threeColumnWidth)"))
        #expect(remix.contains("help: SettingHelp("))
        #expect(!remix.contains("help: nil"))
        #expect(!remix.contains("現在値（"))
        #expect(!remix.contains("つまみを変更するには"))
        #expect(remix.contains("private var remixResetRow"))
        #expect(remix.contains("title: \"自動値へ戻す\""))
        #expect(!remix.contains("Task { await model.beginRemix() }"))
        #expect(!remix.contains("private func remixToggle("))
        #expect(remix.contains("private func collisionAvoidanceControl<Content: View>("))
        #expect(remix.contains("dragValueScale: range.upperBound - range.lowerBound"))
        #expect(remix.contains("displayValueText: panNumberText"))
        #expect(remix.contains("summary: \"音量、左右位置、共通リバーブへの送信量を調整します。\""))
        #expect(!remix.contains("roleSummary(settings:"))
        #expect(!remix.contains("labels: [\"0.25秒\", \"2.13秒\", \"4秒\"]"))
        #expect(remix.contains("labels: [\"短い\", \"標準\", \"長い\"]"))
        #expect(!remix.contains(".velouraAdaptiveGlass(in: .rect(cornerRadius: 10))"))
        #expect(sidebar.contains("showsTransientStatus: false"))
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
        let about = try source(
            "Sources/VelouraLucent/Views/VelouraAboutView.swift"
        )
        let modelAcquisitionSheet = try source(
            "Sources/VelouraLucent/Views/StemModelAcquisitionProgressSheet.swift"
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
        #expect(modelManagement.contains("LiquidGlassSegmentedPicker("))
        #expect(modelManagement.contains("title: \"分離モデル\""))
        #expect(modelManagement.contains("options: StemSeparationModel.allCases"))
        #expect(modelManagement.contains("StemSeparationChoiceGuide(selectedModel:"))
        #expect(modelManagement.contains("安定・実績・バランス重視"))
        #expect(modelManagement.contains("精度・細かさ・分離感重視"))
        #expect(modelManagement.contains("StemSeparationHelpContent("))
        #expect(modelManagement.contains("HelpSection(title: \"仕組み\")"))
        #expect(modelManagement.contains("HelpSection(title: \"\\(selectedModel.displayName)の特徴\")"))
        #expect(modelManagement.contains("ComparisonTable()"))
        #expect(modelManagement.contains("分離結果は、楽曲、録音状態、音の重なり方によって変わります。"))
        #expect(!modelManagement.contains("50曲"))
        #expect(!modelManagement.contains("最大メモリ"))
        #expect(modelManagement.contains("LabeledContent(\"モデル状態\")"))
        #expect(modelManagement.contains("Text(presentation.title)"))
        #expect(modelManagement.contains("Text(presentation.message)"))
        #expect(!modelManagement.contains("Text(\"選択できる操作\")"))
        #expect(!modelManagement.contains("if !modelManager.isAcquiringModels"))
        #expect(modelManagement.contains("|| modelManager.isAcquiringModels"))
        #expect(modelManagement.contains("HStack(spacing: 10)"))
        #expect(modelManagement.contains("LiquidGlassActionButton("))
        #expect(modelManagement.contains("layout: .inspectorWide"))
        #expect(modelManagement.contains("prepareAcquisitionConfirmation(purpose:"))
        #expect(!modelManagement.contains("ModelDownloadConfirmationSheet"))
        #expect(modelManagement.contains("downloadConfirmationIsPresented"))
        #expect(modelManagement.contains("Button(presentation.affirmativeTitle)"))
        #expect(modelManagement.contains("Stem分離に必要なAIモデルを取得します。"))
        #expect(!modelManagement.contains("DownloadContractCard"))
        #expect(!modelManagement.contains("RightsAndProvenanceCard"))
        #expect(!modelManagement.contains("DownloadAssetCard"))
        #expect(modelManagement.contains("try modelManager.confirmAcquisition()"))
        #expect(modelManagement.contains("承認するまでネットワーク通信は開始しません"))
        #expect(modelManagement.contains("\"AIモデルを削除しますか？\""))
        #expect(modelManagement.contains("Button(\"削除\", role: .destructive)"))
        #expect(!modelManagement.contains("ModelDeletionConfirmationSheet"))
        #expect(!modelManagement.contains(".buttonStyle(.bordered)"))
        #expect(liquidGlassActionButton.contains("var layout: Layout = .compact"))
        #expect(liquidGlassActionButton.contains("case inspectorWide"))
        #expect(liquidGlassActionButton.contains(
            "minHeight: 32, alignment: .center"
        ))
        #expect(liquidGlassActionButton.contains(".onHover(perform: updateHover)"))
        #expect(liquidGlassActionButton.contains(".liquidGlassCapsuleMorphSurface("))
        #expect(liquidGlassActionButton.contains("LiquidGlassMotion.perform("))
        #expect(modelManagement.contains("Image(systemName: \"exclamationmark.circle\")"))
        #expect(!modelManagement.contains("title = \"モデル検証\""))
        #expect(modelAcquisitionSheet.contains("canRetryDownload: retryPurpose != nil"))
        #expect(modelAcquisitionSheet.contains("title: \"再ダウンロード\""))
        #expect(modelAcquisitionSheet.contains("action: modelManager.retryFailedAcquisition"))
        #expect(
            modelManagement.components(
                separatedBy: "title = \"AIモデルを取得\""
            ).count - 1 == 2
        )
        #expect(modelManagement.contains("shifts / overlap"))
        #expect(modelManagement.contains("split / segment"))
        #expect(modelManagement.contains("batch size / run seed"))
        #expect(modelManagement.contains("入力選択後に生成"))
        #expect(modelManagement.contains("方式　Demucs v4"))
        #expect(modelManagement.contains("StemProductionModelProfile.profile(for: selectedModel)"))
        #expect(modelManagement.contains("modelPresentation?.runContract.activeRoles"))
        #expect(modelManagement.contains("STFT FFT / hop / window"))
        #expect(modelManagement.contains("roles.map(\\.stemModeDisplayTitle)"))
        #expect(modelManagement.contains("出力　\\(outputDescription)"))
        #expect(!modelManagement.contains("6Stem → 既存4Stem"))
        #expect(modelManagement.contains("dim / depth / heads"))
        #expect(!modelManagement.contains("shifts / overlap　0 / 0"))
        #expect(!about.contains("Text(\"AIモデル情報\")"))
        #expect(about.contains(
            "音声を補正し、マスタリングで最終版に仕上げます。"
        ))
        #expect(about.contains("CFBundleShortVersionString"))
        #expect(about.contains(
            ".containerBackground(.regularMaterial, for: .window)"
        ))
        #expect(about.contains("WindowChromeConfigurator("))
        #expect(about.contains("hidesTitle: false"))
        #expect(about.contains("extendsContentIntoTitlebar: true"))
        #expect(standardWorkspace.contains("NSApplication.didBecomeActiveNotification"))
        #expect(standardWorkspace.contains("NSWindow.didBecomeKeyNotification"))
        #expect(standardWorkspace.contains("scheduleTransparentTitlebarReapplication"))
        #expect(about.contains("LiquidGlassSegmentedPicker("))
        #expect(about.contains("title: \"AIモデル\""))
        #expect(about.contains("options: StemSeparationModel.allCases"))
        #expect(!about.contains(".pickerStyle(.segmented)"))
        #expect(about.contains("informationList("))
        #expect(about.contains("(label: \"ライセンス情報\""))
        #expect(about.contains("(label: \"モデルの来歴\""))
        #expect(about.contains("Divider()"))
        #expect(!about.contains(".velouraAdaptiveGlass("))
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
        #expect(workspaceShell.contains("static let minimumCenterWidth: CGFloat = 680"))
        #expect(workspaceShell.contains("static let inspectorWidth: CGFloat = 480"))
        #expect(workspaceShell.contains("static let recentLogMinimumWidth: CGFloat = 260"))
        #expect(workspaceShell.contains("static let expandedWorkflowMinimumWidth: CGFloat = 360"))
        #expect(workspaceShell.contains("stageCount: stages.count"))
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
        #expect(!root.contains(".correctedPureSum48000"))
        #expect(root.contains("return model.exportableArtifacts.map { artifact in"))
        #expect(root.contains("artifact.kind.stemModeExportMenuTitle"))
        #expect(root.contains("artifact.kind.isCorrectedStemArtifact"))
        #expect(!root.contains(".correctedStem(.drums)"))
        #expect(!root.contains(".correctedStem(.bass)"))
        #expect(!root.contains(".correctedStem(.other)"))
        #expect(!root.contains(".correctedStem(.vocals)"))
        #expect(!root.contains(".finalMaster"))

        #expect(stemWorkspace.contains("private var fixedHeader: some View"))
        #expect(stemWorkspace.contains("WorkspaceFixedHeaderView("))
        #expect(workspaceShell.contains(".font(.largeTitle.bold())"))
        #expect(workspaceShell.contains(".padding(.horizontal, 24)"))
        #expect(workspaceShell.contains(".padding(.bottom, 12)"))
        #expect(workspaceShell.contains(".scrollEdgeEffectStyle(.soft, for: .top)"))
        #expect(!stemWorkspace.contains("maxWidth: 240"))
    }

    @Test
    func aboutWindowReappliesTransparentTitlebarAfterActivation() throws {
        let about = try source(
            "Sources/VelouraLucent/Views/VelouraAboutView.swift"
        )
        let windowChrome = try source(
            "Sources/VelouraLucent/Views/ContentView.swift"
        )

        #expect(about.contains("extendsContentIntoTitlebar: true"))
        #expect(windowChrome.contains(
            "NSApplication.didBecomeActiveNotification"
        ))
        #expect(windowChrome.contains("NSWindow.didBecomeKeyNotification"))
        #expect(windowChrome.contains(
            "scheduleTransparentTitlebarReapplication(for: window)"
        ))
        #expect(windowChrome.contains(
            "Task.sleep(nanoseconds: 100_000_000)"
        ))
        #expect(windowChrome.contains(
            "window.titlebarAppearsTransparent = true"
        ))
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
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/StemWaveformComparisonView.swift",
            "Sources/VelouraLucent/Views/AudioWaveformWorkspaceView.swift",
        ])

        #expect(source.contains("AudioWaveformWorkspaceView("))
        #expect(source.contains("hoveredWaveformProgress"))
        #expect(source.contains("hoveredWaveformTarget"))
        #expect(source.contains("viewport: waveformViewport"))
        #expect(source.contains("WaveformZoomControls("))
        #expect(source.contains("hoverProgress: hoveredWaveformProgress"))
        #expect(source.contains("onHover: { progress in"))
        #expect(source.contains("waveformViewport.reset()"))
        #expect(source.contains("resetToken: resetToken"))
        #expect(source.contains("model.selectedStemPreviewRole.rawValue"))
        #expect(source.contains("model.selectStemPreviewRole($0)"))
        #expect(source.contains("options: model.availableStemRoles"))
        #expect(source.contains("maxWidth: 448"))
        #expect(!source.contains("model.selectCorrectionRole($0)"))
        #expect(source.contains("preview.playbackState(for: activeTarget) == .playing"))
        #expect(source.contains("fileURL: model.selectedRawStemPreviewURL"))
        #expect(source.contains("fileURL: model.selectedCorrectedStemPreviewURL"))
        #expect(source.contains("Button(\"Finderに表示\", systemImage: \"folder\")"))
        #expect(source.contains("NSWorkspace.shared.activateFileViewerSelecting([fileURL])"))
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
        #expect(stem.contains("ForEach(Array(model.stemEvaluations.enumerated())"))
        #expect(stem.contains("model.availableStemRoles.count"))
        #expect(!stem.contains("4Stemそれぞれ"))
        #expect(!stem.contains("raw 4Stem"))
        #expect(!stem.contains("補正後4Stem"))
        #expect(!stem.contains("Text(\"4Stemの解析完了後に表示します。\")"))
        #expect(stem.contains("protectionEvidence"))
        #expect(stem.contains("rawRemixEvaluation"))
        #expect(!stem.contains("validation.measurements"))
        #expect(stem.contains("validation.analysisIssues"))
        #expect(stem.contains("Text(\"解析上の確認事項\")"))
        #expect(stem.contains("Text(\"確認事項はありません。\")"))
        #expect(stem.contains("Text(\"再ミックス解析が完了すると表示します。\")"))
        #expect(stem.contains("音声を選ぶと、入力、補正後または再ミックス、Stem Mode最終版"))
        #expect(!stem.contains("補正段の入力解析が完了すると"))
        #expect(stem.contains("@State private var showStemSpecificAnalysis = false"))
        #expect(stem.contains("@State private var showRemixSpecificAnalysis = false"))
        #expect(stem.contains("DisclosureToggleButton("))
        #expect(stem.contains("TermHelpButton("))
        #expect(stem.contains("isExpanded: $showStemSpecificAnalysis"))
        #expect(stem.contains("isExpanded: $showRemixSpecificAnalysis"))
        #expect(stem.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        #expect(stem.contains("animation: LiquidGlassMotion.panel"))
        #expect(stem.contains(".transition(.opacity)"))
        #expect(!stem.contains("transaction.disablesAnimations = true"))
        #expect(standard.contains("func analysisCard() -> some View"))
        #expect(standard.contains("DisclosureToggleButton("))
        #expect(standard.contains("animation: LiquidGlassMotion.panel"))
        #expect(standard.contains(".transition(.opacity)"))
        #expect(!standard.contains("transaction.disablesAnimations = true"))
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
    func detailedAnalysisTablesUseSharedAlignmentRules() throws {
        let standard = try source(
            "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"
        )
        let stem = try source(
            "Sources/VelouraLucent/Views/StemModeDetailedAnalysisWorkspaceView.swift"
        )
        let validation = try source(
            "Sources/VelouraLucent/Services/StemValidationService.swift"
        )

        #expect(standard.contains("func analysisTableLabelCell("))
        #expect(standard.contains("func analysisTableNumericColumn("))
        #expect(standard.contains("func analysisTableTextColumn("))
        #expect(standard.contains("Divider().gridCellColumns(7)"))
        #expect(standard.contains("Text(row.definition.label)"))
        #expect(standard.contains("labelWidth: 108"))
        #expect(standard.contains("numericWidth: 72"))
        #expect(standard.contains("horizontalSpacing: 8"))
        #expect(!standard.contains("compactMetricList"))
        #expect(!standard.contains("valueChip"))
        #expect(stem.contains("headerCell(\"処理段\")"))
        #expect(stem.contains("headerCell(\"実行内容\")"))
        #expect(stem.contains("Divider().gridCellColumns(3)"))
        #expect(stem.contains("Divider().gridCellColumns(4)"))
        #expect(stem.contains(".analysisTableNumericColumn()"))
        #expect(!stem.contains("validationMeasurements("))
        #expect(!stem.contains("再合成・残差・帯域・ノイズ測定"))
        #expect(stem.contains("validationIssues(model.remixAnalysisPresentation?.validation.analysisIssues)"))
        #expect(!stem.contains("自動候補選択には使用しません"))
        #expect(stem.contains("数値だけで完成音を自動選択しません"))
        #expect(validation.contains("struct StemValidationMeasurement"))
        #expect(validation.contains("measurements: measurements"))
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
    func previewReusesStandardComparisonAndAddsDedicatedRemixAB() throws {
        let preview = try combinedSource([
            "Sources/VelouraLucent/Views/StemModePreviewView.swift",
            "Sources/VelouraLucent/Views/StemRemixComparisonView.swift",
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
        #expect(preview.contains("correctedTitle: waveformProcessedTitle"))
        #expect(preview.contains("comparisonPairLabel: comparisonPairLabel"))
        #expect(preview.contains("comparisonPairSummary: comparisonPairSummary"))
        #expect(preview.contains("comparisonPairPickerMaxWidth: 440"))
        #expect(preview.contains("comparisonPairPickerMaxWidth: CGFloat = 360"))
        #expect(preview.contains("maxWidth: comparisonPairPickerMaxWidth"))
        #expect(preview.contains("targetTitle: targetTitle"))
        #expect(preview.contains(
            "WorkspaceLazySection {\n                AverageSpectrumComparisonView"
        ))
        #expect(preview.contains(
            "WorkspaceLazySection {\n                SpectrogramComparisonView"
        ))
        #expect(preview.contains("model.remixedPreviewArtifact == nil"))
        #expect(preview.contains("private var waveformProcessedTitle: String {\n        \"再ミックス\"\n    }"))
        #expect(preview.contains("case .correctedVsMastered:\n            \"再ミックスvs最終版\""))
        #expect(preview.contains("\"補正後\""))
        #expect(preview.contains("\"Stem再ミックス\""))
        #expect(preview.contains("\"再ミックスvs最終版\""))
        #expect(model.contains("let previewController = AudioPreviewController()"))
        #expect(model.contains("let remixPreviewController = AudioPreviewController()"))
        #expect(model.contains("func updatePreviewSources"))
        #expect(model.contains("finalCommitLockState == .unlocked"))
        #expect(model.contains("!isStartingRun"))
    }

    @Test
    func exportMenusExposeRequestedArtifactsInRequestedOrder() throws {
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
        #expect(rootSource.contains("return model.exportableArtifacts.map { artifact in"))
        #expect(rootSource.contains("artifact.kind.stemModeExportMenuTitle"))
        #expect(rootSource.contains("artifact.kind.isCorrectedStemArtifact"))
        #expect(!rootSource.contains("let entries: [(kind: StemArtifactKind"))
        #expect(!rootSource.contains(".correctedStem(.drums)"))
        #expect(!rootSource.contains(".correctedStem(.bass)"))
        #expect(!rootSource.contains(".correctedStem(.other)"))
        #expect(!rootSource.contains(".correctedStem(.vocals)"))
        #expect(resultsSource.contains("ForEach(commandActions.exportActions)"))
        #expect(resultsSource.contains("if exportAction.startsSection"))
        #expect(resultsSource.contains("再ミックス済み、マスタリング済み、または補正済みStemを書き出します"))
        #expect(!resultsSource.contains("raw Stem"))
        #expect(!resultsSource.contains("No Vocals"))
        #expect(!resultsSource.contains("試聴版"))
        #expect(resultsSource.contains("ForEach(AudioExportFormat.allCases)"))
        #expect(models.contains("exportArtifact: @MainActor (StemAudioArtifact, AudioExportFormat) async throws -> URL"))

        #expect(resultsSource.contains("ForEach(commandActions.exportActions)"))
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
        #expect(source.contains("cancelRemix"))
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
        #expect(inspector.contains("TermHelpButton(\n                    title: \"解析モード\""))
        #expect(inspector.contains("$model.selectedAnalysisMode"))
        #expect(inspector.contains("isDisabled: model.session.isCorrectionProcessing"))
        #expect(!inspector.contains("補正開始時にrunへ固定"))
        #expect(!inspector.contains("実際のStem解析とDSP内部解析"))
        #expect(workspaceModel.contains("analysisMode: StemAudioAnalysisMode(selectedAnalysisMode)"))
        #expect(workflow.contains("let analysisMode: StemAudioAnalysisMode"))
        #expect(!workflow.contains("checkpoint"))
        #expect(evaluator.contains("request.analysisMode.resolvedAudioAnalysisMode"))
        #expect(correction.contains("rawEvaluation.request.analysisMode.resolvedAudioAnalysisMode"))
    }

    @Test
    func stemModeReusesStandardInspectorAndInputSelectionContracts() throws {
        let standardInspector = try source(
            "Sources/VelouraLucent/Views/InspectorAnalysisPanel.swift"
        )
        let stemInspector = try source(
            "Sources/VelouraLucent/Views/StemModeInspectorView.swift"
        )
        let root = try source(
            "Sources/VelouraLucent/Views/VelouraRootView.swift"
        )
        let recentLog = try source(
            "Sources/VelouraLucent/Views/RecentProcessingLogView.swift"
        )

        #expect(standardInspector.contains(
            "struct InspectorAnalysisPanelContent<AdditionalContent: View>: View"
        ))
        #expect(standardInspector.contains("InspectorAnalysisPanelContent("))
        #expect(stemInspector.contains("InspectorAnalysisPanelContent("))
        #expect(!stemInspector.contains("private func metricsGrid("))
        #expect(!stemInspector.contains("private func qualityWarnings("))
        #expect(!stemInspector.contains("private var completionReportControl"))
        #expect(stemInspector.contains("processedTitle: processedTitle"))
        #expect(!standardInspector.contains("qualityReport:"))
        #expect(!stemInspector.contains("qualityReport:"))
        #expect(stemInspector.contains("model.remixedPreviewArtifact == nil"))

        #expect(root.contains("private func chooseStemInputAudio()"))
        #expect(root.contains("FilePanelService.chooseAudioFile"))
        #expect(!root.contains(".fileImporter("))
        #expect(!root.contains("isStemFileImporterPresented"))
        #expect(!root.contains("presentStemFileImporter"))

        #expect(recentLog.contains("case .remix: \"slider.horizontal.3\""))
        #expect(recentLog.contains("case .mastering: \"waveform.badge.checkmark\""))
    }

    @Test
    func stemSeparationSeparatesBeginnerChoiceFromDetailedHelp() throws {
        let source = try source(
            "Sources/VelouraLucent/Views/StemModelManagementSection.swift"
        )

        #expect(source.contains("StemSeparationChoiceGuide(selectedModel:"))
        #expect(source.contains("static let cardMaxWidth: CGFloat = 360"))
        #expect(
            source.components(
                separatedBy: ".frame(maxWidth: Layout.cardMaxWidth, alignment: .leading)"
            ).count - 1 == 2
        )
        #expect(source.contains("if selectedModel == .htdemucs"))
        #expect(source.contains("安定・実績・バランス重視"))
        #expect(source.contains("精度・細かさ・分離感重視"))
        #expect(source.contains("StemSeparationHelpContent("))
        #expect(source.contains("HelpSection(title: \"仕組み\")"))
        #expect(source.contains("HelpSection(title: \"\\(selectedModel.displayName)の特徴\")"))
        #expect(source.contains("ComparisonTable()"))
        #expect(source.contains("分離結果は、楽曲、録音状態、音の重なり方によって変わります。"))
        #expect(!source.contains("50曲"))
        #expect(!source.contains("最大メモリ"))
        #expect(source.contains("HelpSection(title: \"選択中モデルの詳細情報\")"))
        #expect(source.contains("StemProductionModelProfile.profile(for: selectedModel)"))
        #expect(source.contains("modelPresentation?.runContract.activeRoles"))
        #expect(source.contains("roles.map(\\.stemModeDisplayTitle)"))
        #expect(source.contains("出力　\\(outputDescription)"))
        #expect(!source.contains("6Stem → 既存4Stem"))
        #expect(source.contains("shifts / overlap"))
    }

    @Test
    func currentDocumentationSeparatesHTFourStemFromBSSixStemAndPreservesHistoricalRecord() throws {
        let readme = try source("README.md")
        let modelAssetsReadme = try source(
            "Sources/VelouraLucent/Resources/StemModels/README.md"
        )
        let historicalRuntimeValidation = try source(
            "Docs/BSRoformerSwiftRuntimeValidation_2026-07-30.md"
        )

        #expect(readme.contains("HTDemucsでは4Stem、BS-RoFormer-SWではGuitar／Pianoを含む6Stemへ分離"))
        #expect(readme.contains("Stem Modeは補正、再ミックス、マスタリングの三段階"))
        #expect(readme.contains("BS実行時のギター、ピアノ"))
        #expect(!readme.contains("6Stem → 既存4Stem"))

        #expect(modelAssetsReadme.contains("HTDemucs keeps its four independent outputs"))
        #expect(modelAssetsReadme.contains("BS-RoFormer-SW keeps its six independent outputs"))
        #expect(modelAssetsReadme.contains("does not merge guitar or"))
        #expect(modelAssetsReadme.contains("piano into other"))

        #expect(historicalRuntimeValidation.contains("2026-07-30時点"))
        #expect(historicalRuntimeValidation.contains("既存4Stemへ統合する互換実装"))
        #expect(historicalRuntimeValidation.contains("2026-08-12以降の現在実装"))
        #expect(historicalRuntimeValidation.contains("Guitar／Pianoを統合せず6Stemのまま扱います"))
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
