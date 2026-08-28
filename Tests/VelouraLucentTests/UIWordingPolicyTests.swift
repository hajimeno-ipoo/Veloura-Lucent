import Foundation
import Testing

struct UIWordingPolicyTests {
    @Test
    func inspectorAnalysisSummaryUsesCompactUnavailableStateInBothModes() throws {
        let standardInspector = try combinedSource([
            "Sources/VelouraLucent/Views/InspectorAnalysisPanel.swift"
        ])
        let stemInspector = try combinedSource([
            "Sources/VelouraLucent/Views/StemModeInspectorView.swift"
        ])
        let root = try combinedSource([
            "Sources/VelouraLucent/Views/VelouraRootView.swift"
        ])

        #expect(standardInspector.contains(
            "struct InspectorAnalysisPanelContent<AdditionalContent: View>: View"
        ))
        #expect(standardInspector.contains("Text(\"解析結果\")"))
        #expect(!standardInspector.contains("Text(\"品質確認\")"))
        #expect(!standardInspector.contains("qualityWarnings("))
        #expect(!standardInspector.contains("qualityReport:"))
        #expect(standardInspector.contains("Image(systemName: \"waveform.path.ecg\")"))
        #expect(standardInspector.contains(".accessibilityElement(children: .combine)"))
        #expect(standardInspector.contains("InspectorAnalysisPanelContent("))
        #expect(stemInspector.contains("InspectorAnalysisPanelContent("))
        #expect(!standardInspector.contains(
            "\\.velouraInspectorAnalysisPresentationState"
        ))
        #expect(root.contains("\\.velouraInspectorAnalysisPresentationState"))
        #expect(root.contains("selection: currentAnalysisSelectionBinding"))
        #expect(root.contains("isInspectorPresented: $isInspectorPresented"))
        #expect(stemInspector.contains("Text(\"再ミックス解析の確認事項\")"))
        #expect(stemInspector.contains("Text(\"確認事項はありません。\")"))
        #expect(!stemInspector.contains("addingValidationIssues"))

        let sharedSource = standardInspector + stemInspector
        #expect(!sharedSource.contains("Text(\"音声の確認\")"))
        #expect(!sharedSource.contains("ContentUnavailableView("))
        #expect(!sharedSource.contains("minHeight: 140"))
    }

    @Test
    func completionReportUsesDetailedThreeStageDocumentWithoutAdjustmentCandidates() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/CompletionReportPopoverView.swift"
        ])

        #expect(source.contains("CompletionReportComparisonView(report: report)"))
        #expect(source.contains("ForEach(report.sections)"))
        #expect(source.contains("CompletionReportStageDeltaGrid"))
        #expect(source.contains("Grid(alignment: .leading"))
        #expect(source.contains("入力→\\(middleTitle)"))
        #expect(source.contains("\\(middleTitle)→最終版"))
        #expect(source.contains("report.safetyRows.isEmpty"))
        #expect(source.contains("minWidth: 760"))
        #expect(!source.contains("調整候補"))
    }

    @Test
    func uiCopyKeepsNumbersAsListeningGuides() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/ContentView.swift",
                "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift",
                "Sources/VelouraLucent/Views/InspectorAnalysisPanel.swift",
                "Sources/VelouraLucent/Views/InspectorSettingsPanel.swift",
                "Sources/VelouraLucent/Services/AudioQualityReportService.swift",
                "Sources/VelouraLucent/Services/NoiseCheckReportService.swift"
            ]
        )

        for bannedPhrase in [
            "追加調整は不要です。",
            "次に触るなら",
            "見込み:",
            "自然に聞こえる方向へ寄せます",
            "Integrated Loudness が"
        ] {
            #expect(!source.contains(bannedPhrase))
        }

        #expect(!source.contains("数値上の追加候補はありません。最終版を聴いて違和感がないか確認してください。"))
        #expect(!source.contains("聴いて気になる場合の調整候補"))
        #expect(source.contains("目標値に必ず合わせるものではなく、仕上げ意図を確認する目安です。"))
        #expect(source.contains("目安:"))
        #expect(source.contains("聴き比べてください"))
    }

    @Test
    func mainWorkspaceKeepsBasicAndDetailedAnalysisSeparated() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/VelouraMainWorkspaceView.swift",
                "Sources/VelouraLucent/Views/WorkspaceShellView.swift",
                "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift",
                "Sources/VelouraLucent/Views/VectorScopeView.swift",
                "Sources/VelouraLucent/Views/VectorScopeModePicker.swift"
            ]
        )

        #expect(source.contains("基本表示"))
        #expect(source.contains("詳細解析"))
        #expect(source.contains("fixedHeader"))
        #expect(source.contains("LiquidGlassSegmentedPicker("))
        #expect(source.contains("title: \"中央表示\""))
        #expect(source.contains(".padding(.top, 16)"))
        #expect(!source.contains(".navigationTitle(\"試聴と解析\")"))
        #expect(source.contains("AudioWaveformWorkspaceView"))
        #expect(source.contains("AverageSpectrumComparisonView"))
        #expect(source.contains("SpectrogramComparisonView"))
        #expect(source.contains("struct VelouraBasicWorkspaceView: View"))
        #expect(source.contains("VelouraBasicWorkspaceView("))
        #expect(!source.contains("private var basicWorkspace"))
        #expect(source.contains("struct WorkspaceLazySection<Content: View>: View"))
        #expect(source.contains("LazyVStack(alignment: .leading, spacing: 0)"))
        #expect(source.contains(
            "WorkspaceLazySection {\n            AverageSpectrumComparisonView"
        ))
        #expect(source.contains(
            "WorkspaceLazySection {\n            SpectrogramComparisonView"
        ))
        #expect(source.contains("主要数値比較"))
        #expect(source.contains("補正差分"))
        #expect(source.contains("マスタリング差分"))
        #expect(source.contains("ノイズ7種類比較"))
        #expect(source.contains("ステレオ相関"))
        #expect(source.contains("VectorScopeView("))
        #expect(source.contains("preview: preview"))
        #expect(source.contains("Text(\"ベクトルスコープ\")"))
        #expect(source.contains("title: \"ベクトルスコープ表示\""))
        #expect(source.contains("TermHelpButton("))
        #expect(source.contains("Polar Sampleは、左右チャンネルのサンプルを半円上の点で表示します。"))
        #expect(source.contains("Polar Levelは、短い時間のレベルを線で表示します。"))
        #expect(source.contains("title: \"Polar Level検出方式\""))
        #expect(source.contains("Lissajousは、左右チャンネルの瞬間的な関係を菱形の中の点で表示します。"))
        #expect(source.contains("Lissajous"))
        #expect(source.contains("Polar Sample"))
        #expect(source.contains("Polar Level"))
        #expect(source.contains("Text(\"相関\")"))
        #expect(source.contains("Text(\"L/Rバランス\")"))
        #expect(!source.contains("再生中ベクトルスコープ"))
        #expect(source.contains("短時間ラウドネス"))
        #expect(source.contains("ダイナミクス推移"))
        #expect(source.contains("平均スペクトル比較"))
        #expect(source.contains("周波数帯域詳細"))
        #expect(!source.contains("private var header: some View"))
        #expect(!source.contains("title: \"詳細解析\""))
        #expect(!source.contains("右側インスペクタと下部ログへ同じ表を重複表示せず"))
        #expect(source.contains("仕上がりの方向") == false)
    }

    @Test
    func audioWaveformWorkspaceUsesLiquidGlassForAuditionControls() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/AudioWaveformWorkspaceView.swift"])

        #expect(source.contains(".glassCard(cornerRadius: 16)"))
        #expect(source.contains("GlassEffectContainer(spacing: 10)"))
        #expect(source.contains("title: \"比較対象\""))
        #expect(source.contains("VStack(alignment: .leading, spacing: 8)"))
        #expect(source.contains("comparisonLabel\n                comparisonSummary\n                Spacer(minLength: 0)\n            }\n            comparisonPairPicker"))
        #expect(source.contains("comparisonPairPicker"))
        #expect(!source.contains("comparisonLabel\n                comparisonPairPicker\n                comparisonSummary"))
        #expect(!source.contains("比較動画を作成"))
        #expect(!source.contains("comparisonVideoLaunch"))
        #expect(source.contains("WaveformTransportButton(\n                    title: switchButtonTitle"))
        #expect(source.contains("isDisabled: comparisonFileURL(for: .a) == nil\n                        || comparisonFileURL(for: .b) == nil"))
        #expect(source.contains("Text(\"現在 \\(activeSideTitle)\")"))
        #expect(source.contains(".velouraAdaptiveGlass(in: .capsule, interactive: true)"))
        #expect(source.contains("private var activeComparisonTint: Color"))
        #expect(!source.contains("loudnessComparisonToggle\n                activeComparisonLabel"))
        #expect(source.contains("WaveformTransportButtonStyle("))
        #expect(!source.contains(".buttonStyle(.glassProminent)"))
        #expect(!source.contains(".buttonStyle(.glass)"))
        #expect(source.contains(".glassEffect(.regular.tint(tint.opacity(0.16)), in: .capsule)"))
        #expect(!source.contains("ultraThinMaterial"))
        #expect(!source.contains("regularMaterial"))
        #expect(!source.contains("LinearGradient"))
    }

    @Test
    func waveformComparisonUsesSignedPeakRMSAndSharedTimeReadout() throws {
        let waveform = try combinedSource([
            "Sources/VelouraLucent/Views/AudioWaveformWorkspaceView.swift"
        ])
        let timeRuler = try combinedSource([
            "Sources/VelouraLucent/Views/WaveformTimeRulerView.swift"
        ])

        #expect(waveform.components(separatedBy: "Canvas {").count - 1 == 1)
        #expect(waveform.contains("verticalEnvelopePath("))
        #expect(waveform.contains("context.stroke("))
        #expect(waveform.contains("renderedSamples(for: size.width)"))
        #expect(waveform.contains("sample.minimum"))
        #expect(waveform.contains("sample.maximum"))
        #expect(waveform.contains("sample.rms"))
        #expect(waveform.contains(".onContinuousHover"))
        #expect(waveform.contains("hoveredWaveformProgress"))
        #expect(waveform.contains("viewport: waveformViewport"))
        #expect(waveform.contains("WaveformZoomControls("))
        #expect(waveform.contains("viewport.globalProgress("))
        #expect(waveform.contains(".highPriorityGesture("))
        #expect(waveform.contains("SpatialTapGesture()"))
        #expect(waveform.contains("onSeek(progress)"))
        #expect(waveform.contains("onPanChanged("))
        #expect(waveform.contains("onPanEnded("))
        #expect(waveform.contains("visibleSamples()"))
        #expect(waveform.contains("preview.playbackState(for: activeTarget) == .playing"))
        #expect(waveform.contains("let isSelected = comparisonSide.map"))
        #expect(waveform.contains("$0 == preview.activeComparisonSide"))
        #expect(waveform.contains("isSelected: isSelected"))
        #expect(waveform.contains("Color(nsColor: .secondaryLabelColor)"))
        #expect(waveform.contains("waveformTint.opacity(isSelected ? 0.48 : 0.36)"))
        #expect(waveform.contains("waveformTint.opacity(isSelected ? 0.95 : 0.78)"))
        #expect(timeRuler.contains("ForEach(0..<5"))
        #expect(timeRuler.contains("waveformTimeText(duration * globalProgress)"))
        #expect(timeRuler.contains("static func maximumZoomScale("))
        #expect(timeRuler.contains("Slider("))
        #expect(!timeRuler.contains("Text(\"\\(viewport.zoomScale)倍\")"))
        #expect(timeRuler.contains("func followPlayback(_ progress: Double)"))
        #expect(timeRuler.contains("mutating func pan("))
        #expect(timeRuler.contains("Label(\"全体表示\", systemImage: \"arrow.left.and.right\")"))
    }

    @Test
    func contentViewConfiguresAccessibleTransparentWindow() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/App/VelouraLucentApp.swift",
            "Sources/VelouraLucent/Views/ContentView.swift",
            "Sources/VelouraLucent/Views/VelouraRootView.swift",
            "Sources/VelouraLucent/Views/VelouraAdaptiveGlassEffect.swift",
            "Sources/VelouraLucent/Models/AppAppearanceSettings.swift"
        ])

        #expect(source.contains("configureLiquidGlassWindow(window)"))
        #expect(source.contains("WindowChromeConfigurator("))
        #expect(source.contains("@State private var windowBackgroundMaterialAmount ="))
        #expect(source.contains("@State private var isWindowBackgroundBlurEnabled ="))
        #expect(source.contains("@State private var windowBackgroundBlurLevel ="))
        #expect(source.contains("@Environment(\\.accessibilityReduceTransparency) private var reduceTransparency"))
        #expect(source.contains("let appearanceState = AppAppearanceSettings.windowAppearanceState("))
        #expect(source.contains(".velouraWindowBackground(state: appearanceState)"))
        #expect(source.contains("appearanceState: appearanceState"))
        #expect(source.contains("if state.usesOpaqueBackground"))
        #expect(source.contains("state.effectiveBlurLevel.material"))
        #expect(source.contains(".materialActiveAppearance(.active)"))
        #expect(source.contains("appearanceState?.updatingFullScreen(isFullScreen)"))
        #expect(source.contains("if isFullScreen"))
        #expect(source.contains("willUseFullScreenPresentationOptions"))
        #expect(source.contains("windowWillEnterFullScreen"))
        #expect(source.contains("windowDidFailToEnterFullScreen"))
        #expect(source.contains("prepareWindowForFullScreenTransition(window)"))
        #expect(source.contains("window.isOpaque = true"))
        #expect(source.contains("window.backgroundColor = .windowBackgroundColor"))
        #expect(source.contains("window.displayIfNeeded()"))
        #expect(source.contains("let baseGlass: Glass = requestedGlass ?? (isFullScreen ? .regular : .clear)"))
        #expect(source.contains(".environment(\\.velouraIsFullScreen, isWindowFullScreen)"))
        #expect(source.contains("for: .window"))
        #expect(!source.contains("Color(nsColor: .windowBackgroundColor)"))
        #expect(source.contains("windowBackgroundMaterialAmountKey"))
        #expect(source.contains("windowBackgroundBlurEnabledKey"))
        #expect(source.contains("windowBackgroundBlurLevelKey"))
        #expect(source.contains("storedWindowBackgroundMaterialAmount(defaults: UserDefaults = .standard)"))
        #expect(source.contains("storedWindowBackgroundBlurEnabled(defaults: UserDefaults = .standard)"))
        #expect(source.contains("storedWindowBackgroundBlurLevel("))
        #expect(source.contains("saveWindowBackgroundMaterialAmount("))
        #expect(source.contains("saveWindowBackgroundBlurEnabled("))
        #expect(source.contains("saveWindowBackgroundBlurLevel("))
        #expect(source.contains("window.isOpaque = false"))
        #expect(source.contains("window.backgroundColor = .clear"))
        #expect(source.contains("window.titlebarAppearsTransparent = true"))
        #expect(source.contains("window.titleVisibility = .hidden"))
        #expect(!source.contains("@AppStorage(AppAppearanceSettings.windowBackgroundMaterialAmountKey)"))
        #expect(!source.contains("containerBackground(.clear, for: .window)"))
        #expect(!source.contains(".fill(.thinMaterial)"))
        #expect(!source.contains("NSVisualEffectView"))
        #expect(!source.contains("window.backgroundColor = NSColor"))
        #expect(!source.contains(".glassEffect(.regular.opacity"))
    }

    @Test
    func mainWorkspaceUsesLiquidGlassSurfacesWithoutBlockingBarBackground() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/ContentView.swift",
            "Sources/VelouraLucent/Views/WorkspaceShellView.swift",
            "Sources/VelouraLucent/Views/VelouraSidebarView.swift",
            "Sources/VelouraLucent/Views/VelouraMainWorkspaceView.swift",
            "Sources/VelouraLucent/Views/VelouraInspectorView.swift",
            "Sources/VelouraLucent/Views/WorkspaceFooterView.swift",
            "Sources/VelouraLucent/Views/SpectrogramComparisonView.swift",
            "Sources/VelouraLucent/Views/AverageSpectrumComparisonView.swift",
            "Sources/VelouraLucent/Views/VectorScopeView.swift",
            "Sources/VelouraLucent/Views/LoudnessMeterView.swift",
            "Sources/VelouraLucent/Views/RecentProcessingLogView.swift",
            "Sources/VelouraLucent/Views/ProcessingLogView.swift",
            "Sources/VelouraLucent/Views/FullProcessingLogView.swift",
            "Sources/VelouraLucent/Views/VelouraAdaptiveGlassEffect.swift"
        ])

        #expect(source.contains(".velouraAdaptiveGlass(in: .rect(cornerRadius: 16))"))
        #expect(source.contains(".velouraAdaptiveGlass(in: .rect(cornerRadius: 14))"))
        #expect(source.contains(".glassEffect(.clear, in: .capsule)"))
        #expect(source.contains("GlassEffectContainer(spacing: 14)"))
        #expect(source.contains(".velouraAdaptiveGlass(in: .rect(cornerRadius: 18))"))
        #expect(source.contains("@State private var isFullLogPresented = false"))
        #expect(source.contains("VelouraMainWorkspaceView("))
        #expect(source.contains("FullProcessingLogView("))
        #expect(source.contains("job: job"))
        #expect(source.contains("isFullLogPresented: $isFullLogPresented"))
        #expect(source.contains("isFullLogPresented = true"))
        #expect(source.contains("onDismiss: { isFullLogPresented = false }"))
        #expect(!source.contains("private var fullProcessingLogOverlay: some View"))
        #expect(!source.contains("Color.white.opacity(0.50)"))
        #expect(!source.contains(".zIndex(10)"))
        #expect(source.components(separatedBy: ".scrollContentBackground(.hidden)").count >= 3)
        #expect(!source.contains(".sheet(isPresented: $isFullLogPresented)"))
        #expect(!source.contains("@State private var fullLogWindowController: NSWindowController?"))
        #expect(!source.contains("private func openFullProcessingLogWindow()"))
        #expect(!source.contains("NSWindowController(window: window)"))
        #expect(!source.contains(".presentationBackground(.clear)"))
        #expect(!source.contains("FullProcessingLogWindowConfigurator"))
        #expect(!source.contains(".listStyle(.sidebar)"))
        #expect(!source.contains(".background(.bar)"))
        #expect(!source.contains(".background(.background.secondary"))
        #expect(!source.contains(".glassEffect(.clear, in: .rect(cornerRadius: 0))"))
    }

    @Test
    func realtimeAnalysisMetersUseAdaptiveGlassSurfaces() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/AverageSpectrumComparisonView.swift",
            "Sources/VelouraLucent/Views/VectorScopeView.swift",
            "Sources/VelouraLucent/Views/LoudnessMeterView.swift"
        ])

        #expect(source.contains("SpectrumCanvasChart(series: spectrumSeries)"))
        #expect(source.contains("BalanceMeterView(value: snapshot.balance)"))
        #expect(source.contains("LoudnessMeterColumn("))
        #expect(source.components(separatedBy: ".velouraAdaptiveGlass(in: .rect(cornerRadius: 16))").count >= 4)
        #expect(source.contains(".glassEffect(.clear, in: .capsule)"))
        #expect(!source.contains(".background(.regularMaterial"))
        #expect(!source.contains(".background(Color.secondary.opacity(0.05)"))
    }

    @Test
    func inspectorSettingsUsesUnifiedGlassInsteadOfLavenderCards() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/VelouraRootView.swift",
            "Sources/VelouraLucent/Views/InspectorSettingsPanel.swift",
            "Sources/VelouraLucent/Views/AppSettingsPanel.swift",
            "Sources/VelouraLucent/Views/SettingsDisclosureCard.swift",
            "Sources/VelouraLucent/Views/DisclosureToggleButton.swift"
        ])

        #expect(!source.contains("Text(\"設定\")"))
        #expect(!source.contains("右側では、1項目ずつ縦に並べて調整します。"))
        #expect(source.contains("Text(\"詳細設定\")"))
        #expect(source.contains("@SceneStorage(\"inspectorSettingsSelectedSection\")"))
        #expect(source.contains("@Binding var selectedSectionRawValue: String"))
        #expect(source.contains("isInspectorPresented = true"))
        #expect(!source.contains("@State private var selectedSection: InspectorSettingsSection"))
        #expect(source.contains("@Binding var windowBackgroundMaterialAmount: Double"))
        #expect(source.contains("@Binding var isWindowBackgroundBlurEnabled: Bool"))
        #expect(source.contains("@Binding var windowBackgroundBlurLevel: WindowBackgroundBlurLevel"))
        #expect(source.contains("AppSettingsPanel("))
        #expect(source.contains("windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount"))
        #expect(source.contains("isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled"))
        #expect(source.contains("windowBackgroundBlurLevel: $windowBackgroundBlurLevel"))
        #expect(source.contains("isWindowFullScreen: isWindowFullScreen"))
        #expect(source.contains("onEditingChanged: handleWindowBackgroundMaterialEditingChanged"))
        #expect(source.contains("handleWindowBackgroundBlurLevelEditingChanged(isEditing)"))
        #expect(source.contains("LiquidGlassSegmentedPicker("))
        #expect(source.contains("title: \"詳細設定\""))
        #expect(source.contains("title: \"補正プリセット\""))
        #expect(source.contains("Image(systemName: \"chevron.right\")"))
        #expect(source.contains(".rotationEffect(.degrees(isExpanded ? 90 : 0))"))
        #expect(source.contains("animation: LiquidGlassMotion.panel"))
        #expect(source.contains(".transition(.opacity)"))
        #expect(source.contains("title: \"解析モード\""))
        #expect(source.contains(".velouraAdaptiveGlass(in: .rect(cornerRadius: 14))"))
        #expect(source.contains("アプリ背景の透明感"))
        #expect(source.contains("0%で現在と同じ完全透明です。数値を上げると、アプリ全体の背景だけが濃くなります。"))
        #expect(source.contains("Toggle(\"ぼかし具合を調整\""))
        #expect(source.contains("if isWindowBackgroundBlurEnabled {"))
        #expect(source.contains("Text(\"ぼかし具合\")"))
        #expect(source.contains("step: 1"))
        #expect(source.contains("tick: { position in"))
        #expect(source.contains("SliderTick(position)"))
        #expect(source.contains("WindowBackgroundBlurLevel.level(for: position).title"))
        #expect(source.contains("従来の透明感設定を使用しています。"))
        #expect(!source.contains("Color(red: 234.0 / 255.0, green: 225.0 / 255.0, blue: 255.0 / 255.0)"))
        #expect(!source.contains(".background(.thinMaterial"))
        #expect(!source.contains(".background(.regularMaterial"))
    }

    @Test
    func contentViewKeepsSidebarAndTogglesRightSettingsPanel() throws {
        let contentViewSource = try combinedSource([
            "Sources/VelouraLucent/Views/ContentView.swift"
        ])
        let combined = try combinedSource([
            "Sources/VelouraLucent/Views/ContentView.swift",
            "Sources/VelouraLucent/Views/VelouraRootView.swift",
            "Sources/VelouraLucent/Views/WorkspaceShellView.swift",
        ])
        let sidebarToggleStart = try #require(
            contentViewSource.range(of: "private struct TitlebarSidebarToggleButton")
        )
        let inspectorConfiguratorStart = try #require(
            contentViewSource.range(
                of: "struct TitlebarInspectorToggleConfigurator",
                range: sidebarToggleStart.upperBound..<contentViewSource.endIndex
            )
        )
        let sidebarToggle = String(
            contentViewSource[
                sidebarToggleStart.lowerBound..<inspectorConfiguratorStart.lowerBound
            ]
        )

        #expect(combined.contains("@State private var isInspectorPresented = true"))
        #expect(combined.contains(
            "@State private var sidebarVisibility: NavigationSplitViewVisibility = .all"
        ))
        #expect(combined.contains("WorkspaceShellView("))
        #expect(combined.contains("VelouraSidebarView(job: runtime.standardActions.job)"))
        #expect(combined.contains("NavigationSplitView(columnVisibility: $sidebarVisibility)"))
        #expect(combined.contains("HStack(spacing: 0)"))
        #expect(combined.contains("VelouraMainWorkspaceView("))
        #expect(combined.contains("width: isInspectorPresented"))
        #expect(combined.contains("VelouraInspectorView("))
        #expect(combined.contains("windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount"))
        #expect(combined.contains("isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled"))
        #expect(combined.contains("windowBackgroundBlurLevel: $windowBackgroundBlurLevel"))
        #expect(combined.contains("TitlebarInspectorToggleConfigurator("))
        #expect(combined.contains("isPresented: $isInspectorPresented"))
        #expect(combined.contains(
            "\\.velouraInspectorAnalysisPresentationState"
        ))
        #expect(combined.contains("selection: currentAnalysisSelectionBinding"))
        #expect(combined.contains("isInspectorPresented: $isInspectorPresented"))
        #expect(combined.contains("TitlebarInspectorToggleButton"))
        #expect(combined.contains("Image(systemName: \"sidebar.right\")"))
        #expect(combined.contains(".font(.system(size: 18, weight: .regular))"))
        #expect(combined.contains(".frame(width: 24, height: 24)"))
        #expect(combined.contains("controller.layoutAttribute = .right"))
        #expect(combined.contains(".buttonStyle(.plain)"))
        #expect(combined.contains("設定を隠す"))
        #expect(combined.contains("設定を表示"))
        #expect(!combined.contains("ToolbarItem(placement: .primaryAction)"))
        #expect(!combined.contains(".navigationTitle(\"試聴と解析\")"))
        #expect(combined.contains(".navigationSplitViewColumnWidth("))
        #expect(combined.contains(".navigationSplitViewStyle(.prominentDetail)"))
        #expect(combined.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(combined.contains(".toolbar(removing: .title)"))
        #expect(combined.contains("TitlebarSidebarToggleConfigurator("))
        #expect(combined.contains("visibility: $sidebarVisibility"))
        #expect(combined.contains("NSTitlebarAccessoryViewController()"))
        #expect(combined.contains("controller.layoutAttribute = .left"))
        #expect(combined.contains("observeToolbar(in: window)"))
        #expect(combined.contains("NSToolbar.willAddItemNotification"))
        #expect(combined.contains("removeDefaultSidebarToggle"))
        #expect(combined.contains("Image(systemName: \"sidebar.left\")"))
        #expect(combined.contains("サイドバーを隠す"))
        #expect(combined.contains("サイドバーを表示"))
        #expect(sidebarToggle.contains(
            "@Environment(\\.accessibilityReduceMotion) private var reduceMotion"
        ))
        #expect(sidebarToggle.contains("LiquidGlassMotion.perform("))
        #expect(sidebarToggle.contains("animation: LiquidGlassMotion.panel"))
        #expect(!combined.contains(".inspector(isPresented:"))
        #expect(!combined.contains(".inspectorColumnWidth("))
    }

    @Test
    func commonWorkspaceRestoresStandardSidebarWidthRange() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/VelouraRootView.swift",
            "Sources/VelouraLucent/Views/WorkspaceShellView.swift",
        ])

        #expect(source.contains("static let sidebarMinimumWidth: CGFloat = 220"))
        #expect(source.contains("static let sidebarIdealWidth: CGFloat = 260"))
        #expect(source.contains("static let sidebarMaximumWidth: CGFloat = 300"))
        #expect(source.contains("static let minimumCenterWidth: CGFloat = 680"))
        #expect(source.contains("static let inspectorWidth: CGFloat = 480"))
        #expect(source.contains("static let inspectorVisibleMinimumWindowWidth: CGFloat = 1_500"))
        #expect(source.contains("static let inspectorHiddenMinimumWindowWidth: CGFloat = 1_500"))
        #expect(source.contains("static let recentLogMinimumWidth: CGFloat = 260"))
        #expect(source.contains("static let expandedWorkflowMinimumWidth: CGFloat = 360"))
        #expect(source.contains("stageCount: stages.count"))
        #expect(source.contains("sidebarVisibility: $sidebarVisibility"))
        #expect(source.contains("NavigationSplitView(columnVisibility: $sidebarVisibility)"))
    }

    @Test
    func inspectorAnalysisBelongsToTheExtendedWorkspaceBottomRegion() throws {
        let combined = try combinedSource([
            "Sources/VelouraLucent/Views/ContentView.swift",
            "Sources/VelouraLucent/Views/StemModeWorkspaceView.swift",
            "Sources/VelouraLucent/Views/VelouraMainWorkspaceView.swift",
            "Sources/VelouraLucent/Views/WorkspaceShellView.swift",
            "Sources/VelouraLucent/Views/VelouraRootView.swift",
        ])
        let shell = try combinedSource([
            "Sources/VelouraLucent/Views/WorkspaceShellView.swift",
        ])
        let shellOwner = shell.components(
            separatedBy: "struct WorkspaceCenterLayout<"
        )[0]

        #expect(combined.contains("bottomRegionTrailingExtension: isInspectorPresented"))
        #expect(shell.contains("HStack(alignment: .top, spacing: 0)"))
        #expect(shell.contains(
            "Divider()\n                    .padding(.trailing, -bottomRegionTrailingExtension)"
        ))
        #expect(shell.contains(
            "analysisPanel\n                        .padding(14)"
        ))
        #expect(!shell.contains(
            "ScrollView {\n                        analysisPanel"
        ))
        #expect(shell.contains(".padding(.trailing, -bottomRegionTrailingExtension)"))
        #expect(shellOwner.contains(".contentMargins("))
        #expect(shellOwner.contains(".mask(alignment: .top)"))
        #expect(shellOwner.contains(
            "width: isInspectorPresented\n                            ? WorkspaceLayoutMetrics.inspectorWidth\n                            : 0"
        ))
        #expect(shellOwner.contains(".clipped()"))
        #expect(shellOwner.contains(".opacity(isInspectorPresented ? 1 : 0)"))
        #expect(shellOwner.contains(".allowsHitTesting(isInspectorPresented)"))
        #expect(shellOwner.contains(".accessibilityHidden(!isInspectorPresented)"))
        #expect(!shellOwner.contains("if isInspectorPresented"))
        #expect(shell.contains("value = max(value, nextValue())"))
        #expect(!shellOwner.contains("analysisPanel"))
        #expect(!shellOwner.contains("Color.clear"))
        #expect(!combined.contains("ZStack(alignment: .bottomTrailing)"))
        #expect(!combined.contains("inspectorFooter"))
        #expect(!combined.contains("footerTrailingInset"))
        #expect(!combined.contains("safeAreaInset"))
    }

    @Test
    func dawKnobUsesPersistentCustomInteractionIndicator() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/DAWKnobControl.swift"])

        #expect(source.contains("@FocusState private var isFocused: Bool"))
        #expect(source.contains(".focusEffectDisabled()"))
        #expect(source.contains(".fill(isActivelyInteracting ? Color.green : Color.clear)"))
        #expect(source.contains(".stroke(Color.secondary, lineWidth: 1)"))
        #expect(source.contains(".contentShape(.interaction, Path(ellipseIn: DAWKnobMetrics.knobHitRect))"))
        #expect(source.contains(".highPriorityGesture(dragGesture)"))
        #expect(source.contains("DragGesture(minimumDistance: 0)"))
        #expect(source.contains("phases: .all"))
        #expect(source.contains(".buttonRepeatBehavior(.enabled)"))
        #expect(source.contains("PressTrackingPlainButtonStyle"))
        #expect(source.contains("DAWKnobValueRing(value: value, range: range"))
        #expect(source.contains("private var valueAndUnitLabel: some View"))
        #expect(source.contains("HStack(alignment: .firstTextBaseline, spacing: DAWKnobMetrics.valueUnitSpacing)"))
        #expect(source.contains("DAWKnobStepRail("))
        #expect(source.contains("width: DAWKnobMetrics.stepRailHitSize.width"))
        #expect(source.contains("height: DAWKnobMetrics.stepRailHitSize.height"))
        #expect(source.contains("label: \"\\(title)を下げる\""))
        #expect(source.contains("label: \"\\(title)を上げる\""))
        #expect(source.contains("TermHelpButton(title: help.title"))
        #expect(!source.contains("fixedArtworkImage"))
        #expect(!source.contains("transparentStepButton"))
        #expect(source.contains("NSEvent.keyRepeatDelay"))
        #expect(source.contains("NSEvent.keyRepeatInterval"))
        #expect(source.contains("keyRepeatTask?.cancel()"))
        #expect(source.contains(".frame(width: DAWKnobMetrics.controlWidth, height: DAWKnobMetrics.controlHeight)"))
        #expect(!source.contains("private var knobInteractionSurface"))
        #expect(!source.contains(".contentShape(Rectangle())\n        .gesture(dragGesture)"))
    }

    @Test
    func menuCommandsExposeProcessingPlaybackAndInspectorShortcuts() throws {
        let commands = try combinedSource(["Sources/VelouraLucent/App/VelouraCommands.swift"])
        let root = try combinedSource(["Sources/VelouraLucent/Views/VelouraRootView.swift"])
        let toolbar = try combinedSource(["Sources/VelouraLucent/Views/WorkspaceToolbarView.swift"])
        let preview = try combinedSource(["Sources/VelouraLucent/Models/AudioPreviewController.swift"])
        let waveform = try combinedSource(["Sources/VelouraLucent/Views/AudioWaveformWorkspaceView.swift"])
        let shortcutManager = try combinedSource([
            "Sources/VelouraLucent/Views/KeyboardShortcutManagementView.swift",
        ])

        #expect(commands.contains("CommandMenu(\"再生\")"))
        #expect(commands.contains("Menu(\"モード\")"))
        #expect(commands.contains("title: \"通常補正\""))
        #expect(commands.contains("title: \"Stem Mode\""))
        #expect(commands.contains("actions?.selectProcessingMode(mode)"))
        #expect(commands.contains("ForEach(actions?.exportActions ?? [])"))
        #expect(commands.contains("if exportAction.startsSection"))
        #expect(commands.contains("shortcutSettings.keyboardShortcut(for: .runCorrection)"))
        #expect(commands.contains("if actions?.processingMode == .stem"))
        #expect(commands.contains("shortcutSettings.keyboardShortcut(for: .runRemix)"))
        #expect(commands.contains("shortcutSettings.keyboardShortcut(for: .runMastering)"))
        #expect(commands.contains("shortcutSettings.keyboardShortcut(for: .togglePlayback)"))
        #expect(commands.contains("shortcutSettings.keyboardShortcut(for: .stopPlayback)"))
        #expect(commands.contains("shortcutSettings.keyboardShortcut(for: .toggleComparisonSide)"))
        #expect(commands.contains("shortcutSettings.keyboardShortcut(for: .toggleInspector)"))
        #expect(commands.contains("playbackState?.sideACommandTitle"))
        #expect(commands.contains("playbackState?.sideBCommandTitle"))
        #expect(commands.contains("playbackState?.comparisonSwitchCommandTitle"))
        #expect(commands.contains("if playbackState?.allowsComparisonPairSelection == true"))
        #expect(commands.contains("@FocusedValue(\\.velouraStemPlaybackPresentationState)"))
        #expect(commands.contains("Menu(\"入力／\\(processedAudioTitle)／最終版\")"))
        #expect(commands.contains("Menu(\"\\(stemPlaybackState.selectedStemTitle)：raw／補正後\")"))
        #expect(commands.contains("Menu(\"補正後／再ミックス\")"))
        #expect(commands.contains("fixedComparisonPlaybackCommands(stemPlaybackState.stemComparison)"))
        #expect(commands.contains("fixedComparisonPlaybackCommands(stemPlaybackState.remixComparison)"))
        #expect(commands.contains("Menu(\"再生するStem\")"))
        #expect(commands.contains("stemSelectionState?.selectPreviewStem(role)"))
        #expect(commands.contains("stemSelectionState?.isPreviewStemSelected(role)"))
        #expect(!commands.contains("CommandMenu(\"Stem\")"))
        #expect(!commands.contains("設定Stem"))
        #expect(root.contains("\\.velouraCommandActions"))
        #expect(root.contains("selectProcessingMode: selectProcessingMode"))
        #expect(root.contains("_ = runtime.selectMode(mode)"))
        #expect(root.contains("playbackInterlocks:"))
        #expect(root.contains("exportActions: stemExportCommandActions"))
        #expect(root.contains("\\.velouraCommandsSuspended"))
        #expect(root.contains("isKeyboardShortcutManagerPresented"))
        #expect(root.contains("processedAudioTitle: commandActions.processedAudioTitle"))
        #expect(commands.contains("title: \"入力と\\(processedAudioTitle)\""))
        #expect(commands.contains("title: \"\\(processedAudioTitle)と最終版\""))
        #expect(commands.contains("title: processedAudioTitle"))
        #expect(!commands.contains("title: \"入力と補正後\""))
        #expect(shortcutManager.contains("action.title(processedAudioTitle: processedAudioTitle)"))
        #expect(shortcutManager.contains("Image(systemName: \"square.and.pencil\")"))
        #expect(shortcutManager.contains(".font(.system(size: 20, weight: .regular))"))
        #expect(!shortcutManager.contains("Text(\"変更\")"))
        #expect(shortcutManager.contains("Text(\"キャンセル\")"))
        #expect(shortcutManager.contains("Text(\"キーを押してください\")"))
        #expect(shortcutManager.contains("HStack(spacing: 14)"))
        #expect(shortcutManager.contains(
            "if isEditing {\n                Color.clear.frame(width: 164, height: 1)"
        ))
        #expect(shortcutManager.contains(
            "Text(actionTitle)\n                .font(.system(size: 16, weight: .regular))"
        ))
        #expect(shortcutManager.contains(
            "Text(operation.operation)\n                                            .font(.system(size: 16, weight: .regular))"
        ))
        #expect(!shortcutManager.contains(".weight(.bold)"))
        #expect(!shortcutManager.contains(".weight(.semibold)"))
        #expect(!shortcutManager.contains(".fontWeight(.medium)"))
        #expect(shortcutManager.contains(
            "Text(shortcut.displayText)\n                .font(.system(size: 20, weight: .regular))"
        ))
        #expect(shortcutManager.contains(
            "Text(operation.keys)\n                                            .font(.system(size: 20, weight: .regular))"
        ))
        #expect(!shortcutManager.contains("\"xmark\""))
        #expect(shortcutManager.contains("変更をキャンセル"))
        #expect(shortcutManager.contains("selectNextKeyView(nil)"))
        #expect(shortcutManager.contains("selectPreviousKeyView(nil)"))
        #expect(shortcutManager.contains("operation: \"次の操作へ移動\""))
        #expect(shortcutManager.contains("keys: \"Tab\""))
        #expect(shortcutManager.contains("operation: \"選択中の操作を実行\""))
        #expect(shortcutManager.contains("keys: \"Space\""))
        #expect(shortcutManager.contains("operation: \"確認画面で決定\""))
        #expect(shortcutManager.contains("keys: \"Return\""))
        #expect(shortcutManager.contains("operation: \"確認画面をキャンセル\""))
        #expect(shortcutManager.contains("keys: \"Esc\""))
        #expect(shortcutManager.contains("struct FixedKeyboardOperationGroup"))
        #expect(shortcutManager.contains("systemFixedOperations.map"))
        #expect(shortcutManager.contains("ForEach(fixedOperationGroups)"))
        #expect(shortcutManager.contains("ForEach(group.operations)"))
        #expect(shortcutManager.contains("sectionHeader(group.title)"))
        #expect(shortcutManager.contains("shortcutCategoryCard"))
        #expect(shortcutManager.contains("RoundedRectangle(cornerRadius: 14)"))
        #expect(shortcutManager.contains(".stroke(Color.secondary.opacity(0.36), lineWidth: 1)"))
        #expect(shortcutManager.contains(".padding(.horizontal, 10)"))
        #expect(shortcutManager.contains("action.id != categoryActions.last?.id"))
        #expect(shortcutManager.contains("operation.id != group.operations.last?.id"))
        #expect(shortcutManager.contains("operation: shortcut.conflictTitle"))
        #expect(!shortcutManager.contains("Text(operation.detail)"))
        #expect(!shortcutManager.contains("の固定操作"))
        #expect(!shortcutManager.contains("Space  /  Return"))
        #expect(toolbar.contains("ForEach(commandActions.exportActions)"))
        #expect(toolbar.contains("if exportAction.startsSection"))
        #expect(root.contains("title: \"補正済み\""))
        #expect(root.contains("title: \"マスタリング済み\""))
        #expect(toolbar.contains("補正済みまたはマスタリング済みの音源を書き出します"))
        #expect(preview.contains("func toggleComparisonPlayback()"))
        #expect(waveform.contains("preview.toggleComparisonPlayback()"))
        #expect(commands.contains("@FocusedValue(\\.velouraPlaybackPresentationState)"))
        for removedClosureCarrier in [
            "VelouraWorkspacePresentationActions",
            "VelouraInspectorSettingsPresentationActions",
            "VelouraInspectorAnalysisPresentationActions",
            "VelouraWaveformPresentationActions",
            "VelouraPlaybackPresentationActions",
        ] {
            #expect(!commands.contains("struct \(removedClosureCarrier)"))
        }
        #expect(commands.contains("Binding<VelouraWorkspaceDisplaySelection>"))
        #expect(commands.contains("let preview: AudioPreviewController"))
        #expect(!commands.contains("let togglePlayback: @MainActor"))
        #expect(commands.contains("commandsSuspended == true"))
        #expect(commands.contains(".disabled(commandsAreSuspended || workspaceDisplaySelection == nil)"))
        #expect(commands.contains(".disabled(commandsAreSuspended || actions?.canSwitchProcessingMode != true)"))
        #expect(commands.contains(".disabled(commandsAreSuspended || isDisabled)"))
        #expect(commands.contains(".disabled(commandsAreSuspended || waveformState?.canZoomOut != true)"))
        #expect(root.contains("\\.velouraStemPlaybackPresentationState"))
        #expect(root.contains("selectedStemTitle: model.selectedStemPreviewRole.stemModeDisplayTitle"))
        #expect(root.contains("preview: model.stemPreviewController"))
        #expect(root.contains("preview: model.remixPreviewController"))
        #expect(!waveform.contains("\\.velouraPlaybackPresentationState"))
        #expect(waveform.contains("prepareForPlayback()"))
        #expect(!waveform.contains("private func togglePlayback()"))
        #expect(!waveform.contains(".keyboardShortcut(\"b\", modifiers: [.command])"))
        #expect(!toolbar.contains(".keyboardShortcut("))
    }

    @Test
    func toolbarUsesDistinctStageIconsAndRedCancellationTitles() throws {
        let toolbar = try combinedSource([
            "Sources/VelouraLucent/Views/WorkspaceToolbarView.swift",
        ])
        let label = try combinedSource([
            "Sources/VelouraLucent/Views/LiquidGlassToolbarLabel.swift",
        ])

        #expect(toolbar.components(separatedBy: "\"slider.horizontal.3\"").count - 1 == 1)
        #expect(toolbar.components(separatedBy: "\"waveform.badge.checkmark\"").count - 1 == 1)
        #expect(toolbar.contains("isCancellation: isCorrectionRunning"))
        #expect(toolbar.contains("isCancellation: commandActions.isRemixRunning"))
        #expect(toolbar.contains("isCancellation: isMasteringRunning"))
        #expect(label.contains("if isCancellation"))
        #expect(label.contains("toolbarLabel\n                .foregroundStyle(.red)"))
        #expect(label.contains("Label(title, systemImage: systemImage)"))
    }

    @Test
    func comparisonVideoButtonIsIconOnlyAndFollowsExportInToolbar() throws {
        let toolbar = try combinedSource([
            "Sources/VelouraLucent/Views/WorkspaceToolbarView.swift",
        ])
        let root = try combinedSource([
            "Sources/VelouraLucent/Views/VelouraRootView.swift",
        ])

        #expect(toolbar.contains("exportMenu\n            comparisonVideoButton"))
        #expect(toolbar.contains("systemImage: \"rectangle.stack.badge.play\""))
        #expect(toolbar.contains(".labelStyle(.iconOnly)"))
        #expect(toolbar.contains(".accessibilityLabel(\"比較動画を作成\")"))
        #expect(toolbar.contains("ComparisonVideoLaunchStore.shared.prepare(comparisonVideoLaunch)"))
        #expect(toolbar.contains("openWindow(id: \"comparison-video\")"))
        #expect(root.contains("comparisonVideoLaunch: comparisonVideoLaunch"))
    }

    @Test
    func appBundleDeclaresJapaneseAsItsLocalization() throws {
        let package = try combinedSource(["Package.swift"])
        let buildScript = try combinedSource(["script/build_and_run.sh"])
        let localizedInfo = try combinedSource(["Resources/ja.lproj/InfoPlist.strings"])

        #expect(package.contains("defaultLocalization: \"ja\""))
        #expect(buildScript.contains("<key>CFBundleDevelopmentRegion</key>\n  <string>ja</string>"))
        #expect(buildScript.contains("<key>CFBundleLocalizations</key>"))
        #expect(buildScript.contains("<key>LSMultipleInstancesProhibited</key>\n  <true/>"))
        #expect(buildScript.contains("PRODUCTION_BUNDLE_ID=\"com.codex.VelouraLucent\""))
        #expect(buildScript.contains("PROJECT_BUNDLE_ID=\"com.codex.VelouraLucent.project\""))
        #expect(buildScript.contains("BUNDLE_ID=\"$PROJECT_BUNDLE_ID\""))
        #expect(buildScript.contains("BUNDLE_ID=\"$PRODUCTION_BUNDLE_ID\""))
        #expect(buildScript.contains("APP_VERSION=\"${VELOURA_APP_VERSION:-1.0.0}\""))
        #expect(buildScript.contains("/bin/date -u +%Y%m%d%H%M%S"))
        #expect(buildScript.contains("\"$MODE\" == \"package\" || \"$MODE\" == \"--package\""))
        #expect(buildScript.contains("git -C \"$ROOT_DIR\" rev-list --count HEAD"))
        #expect(buildScript.contains("<key>CFBundleShortVersionString</key>\n  <string>$APP_VERSION</string>"))
        #expect(buildScript.contains("<key>CFBundleVersion</key>\n  <string>$BUILD_VERSION</string>"))
        #expect(buildScript.contains("command=\"$(/bin/ps -p \"$pid\" -o command="))
        #expect(buildScript.contains("\"$command\" == \"$FINAL_APP_BINARY\""))
        #expect(buildScript.contains("verify_pid=\"$(published_app_pids"))
        #expect(!buildScript.contains("pkill -x"))
        #expect(!buildScript.contains("pkill -TERM -x"))
        #expect(!buildScript.contains("pkill -KILL -x"))
        #expect(buildScript.contains("cp -R \"$APP_LOCALIZATION_SOURCE\" \"$APP_RESOURCES/ja.lproj\""))
        #expect(localizedInfo.contains("\"CFBundleDisplayName\" = \"Veloura Lucent\";"))
    }

    @Test
    func contentViewDelegatesProcessingAndAnalysisTaskOwnership() throws {
        let contentView = try combinedSource(["Sources/VelouraLucent/Views/ContentView.swift"])
        let root = try combinedSource(["Sources/VelouraLucent/Views/VelouraRootView.swift"])
        let toolbar = try combinedSource(["Sources/VelouraLucent/Views/WorkspaceToolbarView.swift"])
        let processingActions = try combinedSource(["Sources/VelouraLucent/App/ProcessingActions.swift"])
        let analysisCoordinator = try combinedSource(["Sources/VelouraLucent/App/DisplayAnalysisCoordinator.swift"])

        #expect(contentView.contains("@State private var processingActions = ProcessingActions("))
        #expect(root.contains("runCorrection: actions.startCorrectionProcessing"))
        #expect(root.contains("runMastering: actions.startMasteringProcessing"))
        #expect(toolbar.contains("commandActions.runCorrection()"))
        #expect(toolbar.contains("commandActions.runMastering()"))
        #expect(contentView.contains("processingActions.acceptDroppedInputAudio"))
        #expect(contentView.contains("processingActions.shutdown()"))
        #expect(!contentView.contains("private func startCorrectionProcessing()"))
        #expect(!contentView.contains("private func startMasteringProcessing()"))
        #expect(!contentView.contains("private func runDisplayAnalysis("))
        #expect(!contentView.contains("Task<Void, Never>?"))

        #expect(processingActions.contains("final class ProcessingActions"))
        #expect(processingActions.contains("private var correctionTask: Task<Void, Never>?"))
        #expect(processingActions.contains("private var masteringTask: Task<Void, Never>?"))
        #expect(processingActions.contains("func startCorrectionProcessing()"))
        #expect(processingActions.contains("func startMasteringProcessing()"))
        #expect(processingActions.contains("func exportCorrectedAudio(as format: AudioExportFormat)"))

        #expect(analysisCoordinator.contains("final class DisplayAnalysisCoordinator"))
        #expect(analysisCoordinator.contains("private var inputSelectionID = UUID()"))
        #expect(analysisCoordinator.contains("private var tasks: [DisplayAnalysisTarget: Task<Void, Never>]"))
        #expect(analysisCoordinator.contains("private func runDisplayAnalysis("))
    }

    @Test
    func scrollIndicatorsAreTransientOverlayAndSmallInEachScrollableRegion() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/VelouraScrollIndicators.swift",
            "Sources/VelouraLucent/Views/VelouraSidebarView.swift",
            "Sources/VelouraLucent/Views/VelouraMainWorkspaceView.swift",
            "Sources/VelouraLucent/Views/VelouraInspectorView.swift",
            "Sources/VelouraLucent/Views/FullProcessingLogView.swift",
            "Sources/VelouraLucent/Views/WorkspaceShellView.swift",
            "Sources/VelouraLucent/Views/CompletionReportPopoverView.swift"
        ])
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let oldConfiguratorURL = root.appendingPathComponent(
            "Sources/VelouraLucent/Views/WindowScrollbarAppearanceConfigurator.swift"
        )

        #expect(source.components(separatedBy: ".velouraTransientOverlayScrollIndicators()").count == 6)
        #expect(source.contains("hostView?.enclosingScrollView"))
        #expect(source.contains("scrollView.scrollerStyle = .overlay"))
        #expect(source.contains("scrollView.autohidesScrollers = false"))
        #expect(source.contains("scroller.controlSize = .small"))
        #expect(source.contains("NSView.boundsDidChangeNotification"))
        #expect(source.contains("private static let hideDelay: TimeInterval"))
        #expect(source.contains("final class VelouraTransientOverlayScroller: NSScroller"))
        #expect(source.contains("override class var isCompatibleWithOverlayScrollers: Bool"))
        #expect(source.contains("self == VelouraTransientOverlayScroller.self"))
        #expect(source.contains("private static let subduedAlpha: CGFloat = 0.55"))
        #expect(source.contains("NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast"))
        #expect(source.contains("alphaValue = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast"))
        #expect(source.contains("guard isScrollActive else { return }"))
        #expect(source.contains("configure(scrollView)\n            setScrollActive(true, in: scrollView)"))
        #expect(source.contains("setScrollActive(true, in: scrollView)"))
        #expect(source.contains("setScrollActive(false, in: scrollView)"))
        #expect(!source.contains("knobStyle"))
        #expect(!source.contains("window?.contentView"))
        #expect(!source.contains("descendants(ofType:"))
        #expect(!FileManager.default.fileExists(atPath: oldConfiguratorURL.path))
    }

    @Test
    func detailedAnalysisHeavyChartsStartCollapsed() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"])

        #expect(source.contains("@State private var showLoudness = false"))
        #expect(source.contains("@State private var showDynamics = false"))
        #expect(source.contains("@State private var showSpectrum = false"))
        #expect(source.contains("@State private var showBands = false"))
        #expect(source.contains("VStack(alignment: .leading, spacing: 16)"))
        #expect(!source.contains("adaptiveColumns"))
    }

    @Test
    func liquidGlassSegmentedPickerReplacesSeparateCustomPickers() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/LiquidGlassSegmentedPicker.swift",
            "Sources/VelouraLucent/Views/VelouraMainWorkspaceView.swift",
            "Sources/VelouraLucent/Views/AudioWaveformWorkspaceView.swift",
            "Sources/VelouraLucent/Views/VectorScopeView.swift",
            "Sources/VelouraLucent/Views/VectorScopeModePicker.swift",
            "Sources/VelouraLucent/Views/InspectorSettingsPanel.swift",
            "Sources/VelouraLucent/Views/InspectorAnalysisPanel.swift"
        ])

        for title in [
            "中央表示",
            "比較対象",
            "ベクトルスコープ表示",
            "Polar Level検出方式",
            "詳細設定",
            "補正プリセット",
            "解析モード",
            "確認する音源"
        ] {
            #expect(source.contains("title: \"\(title)\""))
        }

        #expect(source.contains("struct LiquidGlassSegmentedPicker<Selection: Hashable>: View"))
        #expect(source.contains("GlassEffectContainer(spacing: 6)"))
        #expect(source.contains(".velouraAdaptiveGlass(in: .capsule, interactive: true)"))
        #expect(source.contains("Color(red: 222 / 255, green: 209 / 255, blue: 254 / 255)"))
        #expect(source.contains("Color(red: 111 / 255, green: 85 / 255, blue: 200 / 255)"))
        #expect(source.contains(".foregroundStyle(isSelected ? LiquidGlassSegmentedPickerStyle.selectedText : Color.secondary)"))
        #expect(source.contains("tint: LiquidGlassSegmentedPickerStyle.selectedTint.opacity(0.30)"))
        #expect(source.contains("SelectedLiquidGlassSegmentModifier("))
        #expect(source.contains(".glassEffectID(\"selected-liquid-glass-segment\", in: namespace)"))
        #expect(source.contains(".glassEffectTransition(reduceMotion ? .identity : .matchedGeometry)"))
        #expect(source.contains(".frame(maxWidth: maxWidth, alignment: .leading)"))
        #expect(source.contains("var maxWidth: CGFloat = 360"))
        #expect(source.contains(".padding(.horizontal, 12)"))
        #expect(source.contains(".accessibilityLabel(title)"))
        #expect(source.contains(".accessibilityValue(isSelected ? \"選択中\" : \"未選択\")"))
        #expect(!source.contains("LiquidGlassTabBar("))
        #expect(!source.contains("LiquidGlassSegmentedControl("))
        #expect(!source.contains(".pickerStyle(.segmented)"))
        #expect(!source.contains(".frame(maxWidth: 420"))
    }

    @Test
    func detailedAnalysisUsesAdaptiveGlassCards() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"])

        #expect(source.contains("func analysisCard() -> some View"))
        #expect(source.contains(".velouraAdaptiveGlass(in: .rect(cornerRadius: 16))"))
        #expect(source.contains(".velouraAdaptiveGlass(in: .rect(cornerRadius: 12))"))
        #expect(source.contains(".glassEffect(.regular.tint(state.color.opacity(0.12)), in: .capsule)"))
        #expect(!source.contains(".background(.regularMaterial"))
        #expect(!source.contains(".background(Color.secondary.opacity(0.05)"))
        #expect(!source.contains(".background(Color.secondary.opacity(0.06)"))
        #expect(!source.contains(".background(Color.orange.opacity(0.08)"))
    }

    @Test
    func stereoCorrelationMeterShowsReadableScale() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Models/AudioProcessingModels.swift",
            "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift",
            "Sources/VelouraLucent/Views/VectorScopeView.swift"
        ])

        #expect(source.contains("0未満はモノラル再生で音が痩せる可能性があります。"))
        #expect(source.contains("-1 逆相"))
        #expect(source.contains("0 注意"))
        #expect(source.contains("+1 同相"))
        #expect(source.contains("-1は逆相、0は注意、+1は同相です。"))
        #expect(source.contains("correlationScaleLabel(value: \"+1\", meaning: \"同相\")"))
        #expect(source.contains("correlationScaleLabel(value: \"0\", meaning: \"注意\")"))
        #expect(source.contains("correlationScaleLabel(value: \"-1\", meaning: \"逆相\")"))
        #expect(source.contains("時間ごとの相関推移"))
        #expect(source.contains("無音区間は相関値として計算せず、線を区切ります。"))
        #expect(source.contains("モノラル音源のため、ステレオ相関推移はありません。"))
        #expect(source.contains("chartYScale(domain: -1 ... 1)"))
        #expect(source.contains("RuleMark(y: .value(\"注意ライン\", 0))"))
        #expect(source.contains("series: .value(\"区間\", point.lineGroup)"))
        #expect(source.contains("correlationTimelineDuration(stages: stages)"))
        #expect(source.contains("Lissajous: 縦=同相 / 横=逆相 / 斜め=左右偏り。"))
        #expect(source.contains("Polar Sample: 45度安全ライン内は同相、外側は位相ずれを示します。"))
        #expect(source.contains("Polar Level: 線の角度でステレオ位置を確認します。"))
        #expect(source.contains("RMS: 短い時間の平均レベルを線の長さで表示します。"))
        #expect(source.contains("Peak: 短い時間の瞬間最大レベルを線の長さで表示します。"))
        #expect(source.contains("モノラル音源のため、左右の関係は表示しません"))
        #expect(source.contains("チャンネル音源はベクトルスコープ未対応です"))
    }

    @Test
    func sidebarUsesApprovedInformationSections() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/VelouraSidebarView.swift",
                "Sources/VelouraLucent/Views/SidebarFileRow.swift",
                "Sources/VelouraLucent/Views/SidebarProcessingStatusView.swift",
                "Sources/VelouraLucent/Views/SidebarProcessStatusRow.swift"
            ]
        )

        #expect(source.contains("sidebarSection(title: \"音源\")"))
        #expect(source.contains("sidebarSection(title: \"工程\")"))
        #expect(source.contains("Divider()"))
        #expect(!source.contains("wrapsContentInGlass"))
        #expect(!source.contains("sidebarCard"))
        #expect(!source.contains(".sidebarProcessCard()"))
        #expect(!source.contains("Section(\"ファイル情報\")"))
        #expect(!source.contains("Section(\"入力\")"))
        #expect(!source.contains("Section(\"処理状態\")"))
        #expect(source.contains("fileInfo: job.inputFileInfo"))
        #expect(source.contains("fileInfo: job.hasExistingOutput ? job.outputFileInfo : nil"))
        #expect(source.contains("fileInfo: job.hasExistingMasteredOutput ? job.masteredFileInfo : nil"))
        #expect(source.contains("fileInfo.technicalSummary"))
        #expect(source.contains("fileInfo.durationText"))
        #expect(source.contains("progressText"))
    }

    @Test
    func sidebarCurrentProgressUsesOneHorizontalLine() throws {
        let source = try combinedSource(
            ["Sources/VelouraLucent/Views/SidebarProcessStatusRow.swift"]
        )

        #expect(source.contains("HStack(alignment: .firstTextBaseline, spacing: 8)"))
        #expect(source.contains("Text(currentStatusText)"))
        #expect(source.contains("if let displayedActiveStepDetail"))
        #expect(!source.contains(".lineLimit(2)"))
        #expect(!source.contains(".fixedSize(horizontal: false, vertical: true)"))
    }

    @Test
    func correctionAndMasteringCountersUseCompactSidebarDetails() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Services/ShimmerPeakLimiter.swift",
                "Sources/VelouraLucent/Services/MasteringNoiseReturnGuard.swift",
            ]
        )

        #expect(source.contains("区間\", for:"))
        #expect(source.contains("回目\", for:"))
        #expect(!source.contains(" 区間を確認中"))
        #expect(!source.contains(" 回目を確認中"))
    }

    @Test
    func sidebarShowsFullCorrectionAndMasteringStepLists() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/SidebarProcessingStatusView.swift",
                "Sources/VelouraLucent/Views/SidebarProcessStatusRow.swift"
            ]
        )

        #expect(source.contains("ProcessingStep.allCases"))
        #expect(source.contains("MasteringStep.allCases"))
        #expect(source.contains("completedSteps: job.completedSteps"))
        #expect(source.contains("skippedSteps: job.skippedSteps"))
        #expect(source.contains("failedSteps: job.failedSteps"))
        #expect(source.contains("completedSteps: job.completedMasteringSteps"))
        #expect(source.contains("skippedSteps: job.skippedMasteringSteps"))
        #expect(source.contains("failedSteps: job.failedMasteringSteps"))
        #expect(source.contains("実行中"))
        #expect(source.contains("省略"))
        #expect(source.contains("失敗"))
    }

    @Test
    func footerUsesStructuredRecentEventsAndRealProgress() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/RecentProcessingLogView.swift",
                "Sources/VelouraLucent/Views/WorkspaceFooterView.swift",
                "Sources/VelouraLucent/Views/WorkspaceShellView.swift",
                "Sources/VelouraLucent/Views/OverallWorkflowView.swift"
            ]
        )

        #expect(source.contains("events: job.recentActivityEvents"))
        #expect(source.contains("ForEach(events.suffix(4))"))
        #expect(source.contains(".frame(maxWidth: .infinity, minHeight: 139, alignment: .topLeading)"))
        #expect(source.contains("minHeight: 206"))
        #expect(source.contains("idealHeight: 214"))
        #expect(source.contains("maxHeight: 224"))
        #expect(source.contains("event.timestamp"))
        #expect(source.contains("event.fileName"))
        #expect(source.contains("event.audioSummary"))
        #expect(source.contains("event.progress"))
        #expect(source.contains("job.progressValue"))
        #expect(source.contains("job.masteringProgressValue"))
        #expect(source.contains("Text(\"全体進捗\")"))
        #expect(!source.contains("correctionLines: job.visibleLogLines"))
    }

    @Test
    func filePanelsDoNotUseNestedModalEventLoops() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Services/FilePanelService.swift"])

        #expect(source.contains("panel.begin"))
        #expect(!source.contains("runModal()"))
    }

    @Test
    func realtimeSpectrumKeepsChartFrameVisibleBeforePlayback() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/AverageSpectrumComparisonView.swift"])

        #expect(source.contains("ZStack"))
        #expect(source.contains("SpectrumCanvasChart(series: spectrumSeries)"))
        #expect(source.contains("if spectrumSeries.isEmpty"))
        #expect(source.contains("emptySpectrumMessage"))
        #expect(source.contains("preview.comparisonPair.targets.compactMap"))
        #expect(!source.contains("AudioPreviewTarget.allCases.compactMap"))
    }

    @Test
    func analyzedGraphsExposeCursorReadouts() throws {
        let detailSource = try combinedSource([
            "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"
        ])
        let spectrogramSource = try combinedSource([
            "Sources/VelouraLucent/Views/SpectrogramComparisonView.swift"
        ])
        let hoverOverlaySource = try combinedSource([
            "Sources/VelouraLucent/Views/GraphHoverOverlay.swift"
        ])

        #expect(detailSource.components(separatedBy: ".graphHoverOverlay").count - 1 == 3)
        #expect(detailSource.contains("timelineHoverReadout"))
        #expect(detailSource.contains("restrictsToLineSegments: true"))
        #expect(detailSource.contains("spectrumHoverReadout"))
        #expect(spectrogramSource.contains("spectrogramHoverReadout"))
        #expect(spectrogramSource.contains(".graphHoverOverlay"))
        #expect(hoverOverlaySource.contains("VStack(alignment: .leading, spacing: 4)"))
        #expect(hoverOverlaySource.contains(".frame(height: 28, alignment: .leading)"))
    }

    @Test
    func spectrogramShowsSharedTimeAxis() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/SpectrogramComparisonView.swift"])

        #expect(source.contains("timeAxisDuration"))
        #expect(source.contains("SpectrogramTimeAxisView"))
        #expect(source.contains("スペクトログラムの時間目盛り"))
        #expect(source.contains("formatTime"))
        #expect(source.contains("sharedDuration: timeAxisDuration"))
        #expect(source.contains("chartXScale(domain: 0 ... max(sharedDuration ?? snapshot.duration, 0.1))"))
        #expect(!source.contains("Text(\"時間 →\")"))
    }

    @Test
    func noiseComparisonExplainsStageAndInputRelativeChanges() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"])

        #expect(source.contains("noiseStageFlow(row)"))
        #expect(source.contains("noiseOriginalDeltaComparison(row)"))
        #expect(source.contains("Text(\"原音を基準にした差分\")"))
        #expect(source.contains("Text(\"原音 0\")"))
        #expect(source.contains("中央の帯は原音との差が±1.0 dB以内です。"))
        #expect(source.contains("表示範囲は補正後と最終版の差に合わせて項目ごとに調整します。"))
        #expect(source.contains("InputRelativeDeltaScale.fitting("))
        #expect(source.contains("displayScale: displayScale"))
        #expect(source.contains("deltaDB: row.correctedDeltaFromInputDB"))
        #expect(source.contains("deltaDB: row.masteredDeltaFromInputDB"))
        #expect(!source.contains("private func noiseBarLine("))
        #expect(!source.contains("noiseSeverityText(report.severity)"))
        #expect(!source.contains("report.recommendedActions"))
        #expect(!source.contains("private func noiseActionRow("))
    }

    @Test
    func frequencyBandDetailsUseConsistentDisplayedValuesAndDeltas() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"])

        #expect(source.contains("bandStageFlow(row)"))
        #expect(source.contains("bandInputRelativeDeltaComparison(row)"))
        #expect(source.contains("FrequencyBandDisplayComparison("))
        #expect(source.contains("Text(\"入力を基準にした差分\")"))
        #expect(source.contains("Text(\"入力 0.00 dB\")"))
        #expect(source.contains("Text(\"帯域減少 "))
        #expect(source.contains("Text(\"帯域増加 "))
        #expect(source.contains("masteredDeltaFromInput: comparison.masteredDeltaFromInput"))
        #expect(source.contains("deltaDB: row.correctionDelta"))
        #expect(source.contains("deltaDB: row.masteredDeltaFromInput"))
        #expect(source.contains("formatBandDelta("))
        #expect(source.contains("±1.00 dB以内"))
        #expect(source.contains("実測値と差分は同じ小数第2位の表示値から計算します。"))
        #expect(source.contains("表示範囲は補正後と最終版の差に合わせて帯域ごとに調整します。"))
        #expect(!source.contains("private func bandBar("))
        #expect(!source.contains("全体音量差を除く: 処理"))
        #expect(!source.contains("入力を基準にした差分（全体音量差を除く）"))
    }

    @Test
    func noiseAndFrequencyBandDetailsUseReadableTextHierarchy() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"])
        let noiseSection = try sourceSection(
            source,
            from: "private func noiseRow(",
            to: "private func correlationCard("
        )
        let frequencyBandSection = try sourceSection(
            source,
            from: "private func bandDetailRow(",
            to: "private func unavailableCard("
        )

        #expect(noiseSection.contains("Text(row.measurementDescription)\n                        .font(.body)"))
        #expect(noiseSection.contains("Text(row.displayDescription)\n                        .font(.body)"))
        #expect(frequencyBandSection.contains("Text(row.range)\n                    .font(.body)"))
        #expect(!noiseSection.contains(".font(.footnote"))
        #expect(!frequencyBandSection.contains(".font(.footnote"))
        #expect(noiseSection.contains(".font(.callout)"))
        #expect(frequencyBandSection.contains(".font(.callout)"))
        #expect(noiseSection.contains(".lineLimit(2)"))
        #expect(frequencyBandSection.contains(".lineLimit(2)"))
    }

    private func combinedSource(_ relativePaths: [String]) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return try relativePaths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }

    private func sourceSection(_ source: String, from start: String, to end: String) throws -> String {
        let startRange = try #require(source.range(of: start))
        let endRange = try #require(source.range(of: end, range: startRange.upperBound..<source.endIndex))
        return String(source[startRange.lowerBound..<endRange.lowerBound])
    }

}
