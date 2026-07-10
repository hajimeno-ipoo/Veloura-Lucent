import Foundation
import Testing

struct UIWordingPolicyTests {
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

        #expect(source.contains("数値上の追加候補はありません。最終版を聴いて違和感がないか確認してください。"))
        #expect(source.contains("聴いて気になる場合の調整候補"))
        #expect(source.contains("目標値に必ず合わせるものではなく、仕上げ意図を確認する目安です。"))
        #expect(source.contains("目安:"))
        #expect(source.contains("聴き比べてください"))
    }

    @Test
    func mainWorkspaceKeepsBasicAndDetailedAnalysisSeparated() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/VelouraMainWorkspaceView.swift",
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
        #expect(source.contains("右側インスペクタと下部ログへ同じ表を重複表示せず"))
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
        #expect(source.contains("Button(\"A/B切替\")"))
        #expect(source.contains(".disabled(comparisonFileURL(for: .a) == nil || comparisonFileURL(for: .b) == nil)\n\n                activeComparisonLabel"))
        #expect(source.contains("Text(\"現在 \\(preview.comparisonPair.title(for: preview.activeComparisonSide))\")"))
        #expect(source.contains(".velouraAdaptiveGlass(in: .capsule, interactive: true)"))
        #expect(source.contains("private var activeComparisonTint: Color"))
        #expect(!source.contains("loudnessComparisonToggle\n                activeComparisonLabel"))
        #expect(source.contains(".buttonStyle(.plain)"))
        #expect(!source.contains(".buttonStyle(.glassProminent)"))
        #expect(!source.contains(".buttonStyle(.glass)"))
        #expect(source.contains(".glassEffect(.regular.tint(tint.opacity(0.16)), in: .capsule)"))
        #expect(!source.contains("ultraThinMaterial"))
        #expect(!source.contains("regularMaterial"))
        #expect(!source.contains("LinearGradient"))
    }

    @Test
    func contentViewConfiguresTransparentLiquidGlassWindow() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/App/VelouraLucentApp.swift",
            "Sources/VelouraLucent/Views/ContentView.swift",
            "Sources/VelouraLucent/Views/VelouraAdaptiveGlassEffect.swift",
            "Sources/VelouraLucent/Models/AppAppearanceSettings.swift"
        ])

        #expect(source.contains("configureLiquidGlassWindow(window)"))
        #expect(source.contains("WindowChromeConfigurator("))
        #expect(source.contains("@State private var windowBackgroundMaterialAmount = AppAppearanceSettings.storedWindowBackgroundMaterialAmount()"))
        #expect(source.contains(".velouraWindowBackground(\n                amount: windowBackgroundMaterialAmount,\n                isFullScreen: isWindowFullScreen\n            )"))
        #expect(source.contains("if isFullScreen"))
        #expect(source.contains(".thinMaterial.materialActiveAppearance(.active),\n                for: .window"))
        #expect(source.contains("let baseGlass: Glass = isFullScreen ? .regular : .clear"))
        #expect(source.contains(".environment(\\.velouraIsFullScreen, isWindowFullScreen)"))
        #expect(source.contains(".thinMaterial.materialActiveAppearance(.active).opacity(clampedAmount)"))
        #expect(source.contains("for: .window"))
        #expect(source.contains("windowBackgroundMaterialAmountKey"))
        #expect(source.contains("storedWindowBackgroundMaterialAmount(defaults: UserDefaults = .standard)"))
        #expect(source.contains("saveWindowBackgroundMaterialAmount("))
        #expect(source.contains("window.isOpaque = false"))
        #expect(source.contains("window.backgroundColor = .clear"))
        #expect(source.contains("window.titlebarAppearsTransparent = true"))
        #expect(source.contains("window.titleVisibility = .hidden"))
        #expect(!source.contains("@AppStorage(AppAppearanceSettings.windowBackgroundMaterialAmountKey)"))
        #expect(!source.contains("containerBackground(.clear, for: .window)"))
        #expect(!source.contains("containerBackground(for: .window)"))
        #expect(!source.contains(".fill(.thinMaterial)"))
        #expect(!source.contains("NSVisualEffectView"))
        #expect(!source.contains("window.backgroundColor = NSColor"))
        #expect(!source.contains(".glassEffect(.regular.opacity"))
    }

    @Test
    func mainWorkspaceUsesLiquidGlassSurfacesWithoutBlockingBarBackground() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/ContentView.swift",
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
            "Sources/VelouraLucent/Views/InspectorSettingsPanel.swift",
            "Sources/VelouraLucent/Views/AppSettingsPanel.swift",
            "Sources/VelouraLucent/Views/SettingsDisclosureCard.swift"
        ])

        #expect(!source.contains("Text(\"設定\")"))
        #expect(!source.contains("右側では、1項目ずつ縦に並べて調整します。"))
        #expect(source.contains("Text(\"詳細設定\")"))
        #expect(source.contains("@SceneStorage(\"inspectorSettingsSelectedSection\")"))
        #expect(!source.contains("@State private var selectedSection: InspectorSettingsSection"))
        #expect(source.contains("@Binding var windowBackgroundMaterialAmount: Double"))
        #expect(source.contains("AppSettingsPanel(windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount)"))
        #expect(source.contains("onEditingChanged: handleWindowBackgroundMaterialEditingChanged"))
        #expect(source.contains("LiquidGlassSegmentedPicker("))
        #expect(source.contains("title: \"詳細設定\""))
        #expect(source.contains("title: \"補正プリセット\""))
        #expect(source.contains("title: \"解析モード\""))
        #expect(source.contains(".velouraAdaptiveGlass(in: .rect(cornerRadius: 14))"))
        #expect(source.contains("アプリ背景の透明感"))
        #expect(source.contains("0%で現在と同じ完全透明です。"))
        #expect(!source.contains("Color(red: 234.0 / 255.0, green: 225.0 / 255.0, blue: 255.0 / 255.0)"))
        #expect(!source.contains(".background(.thinMaterial"))
        #expect(!source.contains(".background(.regularMaterial"))
    }

    @Test
    func contentViewKeepsSidebarAndTogglesRightSettingsPanel() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/ContentView.swift"])

        #expect(source.contains("@State private var isInspectorPresented = true"))
        #expect(source.contains("@State private var sidebarVisibility: NavigationSplitViewVisibility = .all"))
        #expect(source.contains("NavigationSplitView(columnVisibility: $sidebarVisibility)"))
        #expect(source.contains("VelouraSidebarView(job: job)"))
        #expect(source.contains("HStack(spacing: 0)"))
        #expect(source.contains("ZStack(alignment: .topTrailing)"))
        #expect(source.contains("VelouraMainWorkspaceView("))
        #expect(source.contains("if isInspectorPresented"))
        #expect(source.contains("VelouraInspectorView("))
        #expect(source.contains("windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount"))
        #expect(source.contains("inspectorToggleButton"))
        #expect(source.contains("Image(systemName: \"sidebar.right\")"))
        #expect(source.contains(".font(.system(size: 18, weight: .regular))"))
        #expect(source.contains(".frame(width: 24, height: 24)"))
        #expect(source.contains(".padding(.trailing, 24)"))
        #expect(source.contains(".offset(y: -36)"))
        #expect(source.contains(".buttonStyle(.plain)"))
        #expect(source.contains("設定を隠す"))
        #expect(source.contains("設定を表示"))
        #expect(!source.contains("ToolbarItem(placement: .primaryAction)"))
        #expect(!source.contains(".navigationTitle(\"試聴と解析\")"))
        #expect(source.contains(".toolbar(removing: .sidebarToggle)"))
        #expect(source.contains(".toolbar(removing: .title)"))
        #expect(source.contains("TitlebarSidebarToggleConfigurator(visibility: $sidebarVisibility)"))
        #expect(source.contains("NSTitlebarAccessoryViewController()"))
        #expect(source.contains("controller.layoutAttribute = .left"))
        #expect(source.contains("observeToolbar(in: window)"))
        #expect(source.contains("NSToolbar.willAddItemNotification"))
        #expect(source.contains("removeDefaultSidebarToggle(from: window)"))
        #expect(source.contains("item.itemIdentifier == .toggleSidebar"))
        #expect(source.contains("com.apple.SwiftUI.navigationSplitView.toggleSidebar"))
        #expect(source.contains("toolbar.removeItem(at: index)"))
        #expect(source.contains("Image(systemName: \"sidebar.left\")"))
        #expect(source.contains("サイドバーを隠す"))
        #expect(source.contains("サイドバーを表示"))
        #expect(!source.contains(".inspector(isPresented:"))
        #expect(!source.contains(".inspectorColumnWidth("))
    }

    @Test
    func windowScrollbarAppearanceKeepsLiquidGlassScrollbarsQuiet() throws {
        let contentView = try combinedSource([
            "Sources/VelouraLucent/Views/ContentView.swift",
            "Sources/VelouraLucent/Views/VelouraMainWorkspaceView.swift"
        ])
        let configurator = try combinedSource(["Sources/VelouraLucent/Views/WindowScrollbarAppearanceConfigurator.swift"])

        #expect(contentView.components(separatedBy: "WindowScrollbarAppearanceConfigurator()").count >= 3)
        #expect(configurator.contains("struct WindowScrollbarAppearanceConfigurator: NSViewRepresentable"))
        #expect(configurator.contains("func makeCoordinator() -> Coordinator"))
        #expect(configurator.contains("private static let retryDelays: [TimeInterval]"))
        #expect(configurator.contains("NSWindow.didUpdateNotification"))
        #expect(configurator.contains("NSWindow.didResizeNotification"))
        #expect(configurator.contains("contentView.descendants(ofType: NSScrollView.self)"))
        #expect(configurator.contains("scrollView.scrollerStyle = .overlay"))
        #expect(configurator.contains("scrollView.autohidesScrollers = true"))
        #expect(configurator.contains("verticalScroller?.knobStyle = .light"))
        #expect(configurator.contains("horizontalScroller?.knobStyle = .light"))
        #expect(configurator.contains("verticalScroller?.controlSize = .small"))
        #expect(configurator.contains("horizontalScroller?.controlSize = .small"))
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
                "Sources/VelouraLucent/Views/OverallWorkflowView.swift"
            ]
        )

        #expect(source.contains("events: job.recentActivityEvents"))
        #expect(source.contains("ForEach(events.suffix(4))"))
        #expect(source.contains(".frame(maxWidth: .infinity, minHeight: 139, alignment: .topLeading)"))
        #expect(source.contains(".frame(minHeight: 206, idealHeight: 214, maxHeight: 224, alignment: .top)"))
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
    }

    private func combinedSource(_ relativePaths: [String]) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return try relativePaths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }

}
