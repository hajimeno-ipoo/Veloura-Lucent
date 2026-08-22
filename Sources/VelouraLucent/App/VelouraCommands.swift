import SwiftUI

struct VelouraExportCommandAction: Identifiable {
    let id: String
    let title: String
    let isEnabled: Bool
    var startsSection = false
    let perform: @MainActor (AudioExportFormat) -> Void
}

struct VelouraCommandActions {
    let processingMode: ProcessingMode
    let processedAudioTitle: String
    var stemCount: Int? = nil
    let canSwitchProcessingMode: Bool
    let canChooseInput: Bool
    let canRunCorrection: Bool
    var canRunRemix = false
    let canRunMastering: Bool
    let isCorrectionRunning: Bool
    var isRemixRunning = false
    let isMasteringRunning: Bool
    let isCorrectionCancelling: Bool
    var isRemixCancelling = false
    let isMasteringCancelling: Bool
    let canCancelCorrection: Bool
    var canCancelRemix = false
    let canCancelMastering: Bool
    let exportActions: [VelouraExportCommandAction]
    let selectProcessingMode: @MainActor (ProcessingMode) -> Void
    let chooseInputAudio: @MainActor () -> Void
    let runCorrection: @MainActor () -> Void
    var runRemix: @MainActor () -> Void = {}
    let runMastering: @MainActor () -> Void
    let cancelCorrection: @MainActor () -> Void
    var cancelRemix: @MainActor () -> Void = {}
    let cancelMastering: @MainActor () -> Void

    var correctionCommandTitle: String {
        if isCorrectionCancelling {
            return "キャンセル中..."
        }
        return isCorrectionRunning ? "補正をキャンセル" : "補正を実行"
    }

    var masteringCommandTitle: String {
        if isMasteringCancelling {
            return "キャンセル中..."
        }
        return isMasteringRunning ? "マスタリングをキャンセル" : "マスタリングを実行"
    }

    var remixCommandTitle: String {
        if isRemixCancelling {
            return "キャンセル中..."
        }
        return isRemixRunning ? "再ミックスをキャンセル" : "再ミックスを実行"
    }

    var remixHelp: String {
        let count = stemCount.map(String.init) ?? "全"
        return "補正済み\(count)Stemを自動値と手動上書きで再ミックスします"
    }

}

struct VelouraWorkspaceChromeActions {
    let isSidebarPresented: Bool
    let isInspectorPresented: Bool
    let toggleSidebar: @MainActor () -> Void
    let toggleInspector: @MainActor () -> Void

    var sidebarCommandTitle: String {
        isSidebarPresented ? "サイドバーを隠す" : "サイドバーを表示"
    }

    var inspectorCommandTitle: String {
        isInspectorPresented ? "設定を隠す" : "設定を表示"
    }
}

enum VelouraWorkspaceDisplaySelection {
    case basic
    case detailedAnalysis
    case fullLog
}

enum VelouraInspectorSettingsSelection {
    case correction
    case remix
    case mastering
    case app
}

struct VelouraInspectorSettingsPresentationState {
    let isStemMode: Bool
    let selection: Binding<VelouraInspectorSettingsSelection>
    let isInspectorPresented: Binding<Bool>

    func show(_ selection: VelouraInspectorSettingsSelection) {
        guard isStemMode || selection != .remix else { return }
        self.selection.wrappedValue = selection
        isInspectorPresented.wrappedValue = true
    }
}

struct VelouraInspectorAnalysisPresentationState {
    let canShowCompletionReport: Bool
    let selection: Binding<InspectorAudioSelection>
    let isInspectorPresented: Binding<Bool>
    let isCompletionReportPresented: Binding<Bool>

    func show(_ selection: InspectorAudioSelection) {
        self.selection.wrappedValue = selection
        isInspectorPresented.wrappedValue = true
    }

    func showCompletionReport() {
        guard canShowCompletionReport else { return }
        isInspectorPresented.wrappedValue = true
        isCompletionReportPresented.wrappedValue = true
    }
}

struct VelouraWaveformPresentationState {
    let viewport: Binding<WaveformViewport>
    let maximumZoomScale: Double
    let centerProgress: Double

    var canZoomOut: Bool {
        viewport.wrappedValue.canZoomOut
    }

    var canZoomIn: Bool {
        viewport.wrappedValue.canZoomIn(maximumZoomScale: maximumZoomScale)
    }

    func zoomOut() {
        var updatedViewport = viewport.wrappedValue
        updatedViewport.zoomOut(
            maximumZoomScale: maximumZoomScale,
            centeredAt: centerProgress
        )
        viewport.wrappedValue = updatedViewport
    }

    func zoomIn() {
        var updatedViewport = viewport.wrappedValue
        updatedViewport.zoomIn(
            maximumZoomScale: maximumZoomScale,
            centeredAt: centerProgress
        )
        viewport.wrappedValue = updatedViewport
    }

    func showWholeWaveform() {
        var updatedViewport = viewport.wrappedValue
        updatedViewport.reset()
        viewport.wrappedValue = updatedViewport
    }
}

@MainActor
struct VelouraPlaybackPresentationState {
    let preview: AudioPreviewController
    let playbackInterlocks: [AudioPreviewController]
    let sideACommandTitle: String
    let sideBCommandTitle: String
    let comparisonSwitchCommandTitle: String
    let allowsComparisonPairSelection: Bool

    init(
        preview: AudioPreviewController,
        playbackInterlocks: [AudioPreviewController],
        sideACommandTitle: String = "Aを再生",
        sideBCommandTitle: String = "Bを再生",
        comparisonSwitchCommandTitle: String = "A/B切替",
        allowsComparisonPairSelection: Bool = true
    ) {
        self.preview = preview
        self.playbackInterlocks = playbackInterlocks
        self.sideACommandTitle = sideACommandTitle
        self.sideBCommandTitle = sideBCommandTitle
        self.comparisonSwitchCommandTitle = comparisonSwitchCommandTitle
        self.allowsComparisonPairSelection = allowsComparisonPairSelection
    }

    var canTogglePlayback: Bool { preview.canToggleComparisonPlayback }
    var canStopPlayback: Bool { preview.activeTarget != nil }
    var canToggleComparisonSide: Bool { preview.canToggleComparisonSide }
    var canPlayComparisonSideA: Bool { sourceURL(for: .a) != nil }
    var canPlayComparisonSideB: Bool { sourceURL(for: .b) != nil }
    var isPlaybackRunning: Bool { preview.isComparisonPlaybackRunning }
    var isLoudnessMatchingEnabled: Bool { preview.isLoudnessMatchedComparisonEnabled }

    var playbackCommandTitle: String {
        isPlaybackRunning ? "一時停止" : "再生"
    }

    func togglePlayback() {
        prepareForPlayback()
        preview.toggleComparisonPlayback()
    }

    func stopPlayback() {
        preview.stopPlayback()
    }

    func toggleComparisonSide() {
        prepareForPlayback()
        preview.toggleComparisonSide()
    }

    func playComparisonSideA() {
        prepareForPlayback()
        preview.playComparisonSide(.a)
    }

    func playComparisonSideB() {
        prepareForPlayback()
        preview.playComparisonSide(.b)
    }

    func setComparisonPair(_ pair: AudioComparisonPair) {
        prepareForPlayback()
        preview.setComparisonPair(pair)
    }

    func toggleLoudnessMatching() {
        preview.setLoudnessMatchedComparisonEnabled(
            !preview.isLoudnessMatchedComparisonEnabled
        )
    }

    private func sourceURL(for side: AudioComparisonSide) -> URL? {
        preview.cardState(for: preview.comparisonTarget(for: side)).sourceURL
    }

    private func prepareForPlayback() {
        playbackInterlocks.forEach { $0.stopPlayback() }
    }
}

@MainActor
struct VelouraStemPlaybackPresentationState {
    let selectedStemTitle: String
    let stemComparison: VelouraPlaybackPresentationState
    let remixComparison: VelouraPlaybackPresentationState
}

struct VelouraStemSelectionPresentationState {
    let availableRoles: [StemRole]
    let previewRole: Binding<StemRole>

    func selectPreviewStem(_ role: StemRole) {
        guard availableRoles.contains(role) else { return }
        previewRole.wrappedValue = role
    }

    func isPreviewStemSelected(_ role: StemRole) -> Bool {
        previewRole.wrappedValue == role
    }
}

private struct VelouraCommandActionsKey: FocusedValueKey {
    typealias Value = VelouraCommandActions
}

private struct VelouraWorkspaceChromeActionsKey: FocusedValueKey {
    typealias Value = VelouraWorkspaceChromeActions
}

extension FocusedValues {
    var velouraCommandActions: VelouraCommandActions? {
        get { self[VelouraCommandActionsKey.self] }
        set { self[VelouraCommandActionsKey.self] = newValue }
    }

    var velouraWorkspaceChromeActions: VelouraWorkspaceChromeActions? {
        get { self[VelouraWorkspaceChromeActionsKey.self] }
        set { self[VelouraWorkspaceChromeActionsKey.self] = newValue }
    }

    @Entry var velouraWorkspaceDisplaySelection: Binding<VelouraWorkspaceDisplaySelection>?
    @Entry var velouraInspectorSettingsPresentationState: VelouraInspectorSettingsPresentationState?
    @Entry var velouraInspectorAnalysisPresentationState: VelouraInspectorAnalysisPresentationState?
    @Entry var velouraWaveformPresentationState: VelouraWaveformPresentationState?
    @Entry var velouraPlaybackPresentationState: VelouraPlaybackPresentationState?
    @Entry var velouraStemPlaybackPresentationState: VelouraStemPlaybackPresentationState?
    @Entry var velouraStemSelectionPresentationState: VelouraStemSelectionPresentationState?
    @Entry var velouraKeyboardShortcutManagerPresentation: Binding<Bool>?
    @Entry var velouraCommandsSuspended: Bool?
}

@MainActor
struct VelouraCommands: Commands {
    @FocusedValue(\.velouraCommandActions) private var actions
    @FocusedValue(\.velouraWorkspaceChromeActions) private var chromeActions
    @FocusedValue(\.velouraWorkspaceDisplaySelection) private var workspaceDisplaySelection
    @FocusedValue(\.velouraInspectorSettingsPresentationState) private var inspectorSettingsState
    @FocusedValue(\.velouraInspectorAnalysisPresentationState) private var inspectorAnalysisState
    @FocusedValue(\.velouraWaveformPresentationState) private var waveformState
    @FocusedValue(\.velouraPlaybackPresentationState) private var playbackState
    @FocusedValue(\.velouraStemPlaybackPresentationState) private var stemPlaybackState
    @FocusedValue(\.velouraStemSelectionPresentationState) private var stemSelectionState
    @FocusedValue(\.velouraKeyboardShortcutManagerPresentation) private var keyboardShortcutManagerPresentation
    @FocusedValue(\.velouraCommandsSuspended) private var commandsSuspended
    @Environment(\.openWindow) private var openWindow
    private let shortcutSettings: KeyboardShortcutSettings

    init(shortcutSettings: KeyboardShortcutSettings = .shared) {
        self.shortcutSettings = shortcutSettings
    }

    private var processedAudioTitle: String {
        actions?.processedAudioTitle ?? "補正後"
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Veloura Lucentについて", systemImage: "info.circle") {
                openWindow(id: "about")
            }

            Divider()

            Button("キーボード操作…", systemImage: "keyboard") {
                keyboardShortcutManagerPresentation?.wrappedValue = true
            }
            .disabled(commandsAreSuspended || keyboardShortcutManagerPresentation == nil)
        }

        CommandGroup(after: .newItem) {
            Button("音声ファイルを開く…", systemImage: "waveform.badge.plus") {
                actions?.chooseInputAudio()
            }
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .chooseInputAudio))
            .disabled(commandsAreSuspended || actions?.canChooseInput != true)
        }

        CommandMenu("処理") {
            Button(actions?.correctionCommandTitle ?? "補正を実行") {
                if actions?.isCorrectionRunning == true {
                    actions?.cancelCorrection()
                } else {
                    actions?.runCorrection()
                }
            }
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .runCorrection))
            .disabled(
                commandsAreSuspended
                    || (actions.map { $0.isCorrectionRunning ? !$0.canCancelCorrection : !$0.canRunCorrection } ?? true)
            )

            if actions?.processingMode == .stem {
                Button(actions?.remixCommandTitle ?? "再ミックスを実行") {
                    if actions?.isRemixRunning == true {
                        actions?.cancelRemix()
                    } else {
                        actions?.runRemix()
                    }
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .runRemix))
                .disabled(
                    commandsAreSuspended || (actions.map {
                        $0.isRemixRunning ? !$0.canCancelRemix : !$0.canRunRemix
                    } ?? true)
                )
            }

            Button(actions?.masteringCommandTitle ?? "マスタリングを実行") {
                if actions?.isMasteringRunning == true {
                    actions?.cancelMastering()
                } else {
                    actions?.runMastering()
                }
            }
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .runMastering))
            .disabled(
                commandsAreSuspended
                    || (actions.map { $0.isMasteringRunning ? !$0.canCancelMastering : !$0.canRunMastering } ?? true)
            )
        }

        CommandMenu("再生") {
            if let stemPlaybackState {
                Menu("入力／\(processedAudioTitle)／最終版") {
                    primaryComparisonPlaybackCommands()
                }

                Menu("\(stemPlaybackState.selectedStemTitle)：raw／補正後") {
                    Menu("再生するStem") {
                        stemPreviewRoleButtons()
                    }

                    Divider()

                    fixedComparisonPlaybackCommands(stemPlaybackState.stemComparison)
                }

                Menu("補正後／再ミックス") {
                    fixedComparisonPlaybackCommands(stemPlaybackState.remixComparison)
                }
            } else {
                primaryComparisonPlaybackCommands()
            }
        }

        CommandGroup(after: .importExport) {
            Menu("書き出し") {
                ForEach(AudioExportFormat.allCases) { format in
                    Menu(format.menuTitle) {
                        ForEach(actions?.exportActions ?? []) { exportAction in
                            if exportAction.startsSection {
                                Divider()
                            }
                            Button(exportAction.title) {
                                exportAction.perform(format)
                            }
                            .disabled(commandsAreSuspended || !exportAction.isEnabled)
                        }
                    }
                }
            }
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .openExportMenu))
            .disabled(commandsAreSuspended || actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Menu("モード") {
                processingModeButton(
                    title: "通常補正",
                    mode: .standard,
                    shortcutAction: .selectStandardMode
                )
                processingModeButton(
                    title: "Stem Mode",
                    mode: .stem,
                    shortcutAction: .selectStemMode
                )
            }
            .disabled(commandsAreSuspended || actions?.canSwitchProcessingMode != true)

            Divider()

            Menu("中央表示") {
                Button("基本表示") {
                    workspaceDisplaySelection?.wrappedValue = .basic
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .showBasicDisplay))
                .disabled(commandsAreSuspended || workspaceDisplaySelection == nil)

                Button("詳細解析") {
                    workspaceDisplaySelection?.wrappedValue = .detailedAnalysis
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .showDetailedAnalysis))
                .disabled(commandsAreSuspended || workspaceDisplaySelection == nil)

                Divider()

                Button("詳細ログ") {
                    workspaceDisplaySelection?.wrappedValue = .fullLog
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .showFullLog))
                .disabled(commandsAreSuspended || workspaceDisplaySelection == nil)
            }
            .disabled(commandsAreSuspended)

            Menu("右側設定") {
                inspectorSectionButton(
                    title: "補正",
                    shortcutAction: .showCorrectionSettings,
                    isDisabled: inspectorSettingsState == nil,
                    perform: { inspectorSettingsState?.show(.correction) }
                )
                inspectorSectionButton(
                    title: "再ミックス",
                    shortcutAction: .showRemixSettings,
                    isDisabled: inspectorSettingsState?.isStemMode != true,
                    perform: { inspectorSettingsState?.show(.remix) }
                )
                inspectorSectionButton(
                    title: "マスタリング",
                    shortcutAction: .showMasteringSettings,
                    isDisabled: inspectorSettingsState == nil,
                    perform: { inspectorSettingsState?.show(.mastering) }
                )
                inspectorSectionButton(
                    title: "アプリ",
                    shortcutAction: .showAppSettings,
                    isDisabled: inspectorSettingsState == nil,
                    perform: { inspectorSettingsState?.show(.app) }
                )
            }
            .disabled(commandsAreSuspended)

            Menu("解析結果") {
                inspectorSectionButton(
                    title: "入力",
                    shortcutAction: .showInputAnalysis,
                    isDisabled: inspectorAnalysisState == nil,
                    perform: { inspectorAnalysisState?.show(.input) }
                )
                inspectorSectionButton(
                    title: processedAudioTitle,
                    shortcutAction: .showCorrectedAnalysis,
                    isDisabled: inspectorAnalysisState == nil,
                    perform: { inspectorAnalysisState?.show(.corrected) }
                )
                inspectorSectionButton(
                    title: "最終版",
                    shortcutAction: .showMasteredAnalysis,
                    isDisabled: inspectorAnalysisState == nil,
                    perform: { inspectorAnalysisState?.show(.mastered) }
                )

                Divider()

                inspectorSectionButton(
                    title: "完了後レポート",
                    shortcutAction: .showCompletionReport,
                    isDisabled: inspectorAnalysisState?.canShowCompletionReport != true,
                    perform: { inspectorAnalysisState?.showCompletionReport() }
                )
            }
            .disabled(commandsAreSuspended)

            Menu("波形") {
                Button("縮小") {
                    waveformState?.zoomOut()
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .zoomWaveformOut))
                .disabled(commandsAreSuspended || waveformState?.canZoomOut != true)

                Button("拡大") {
                    waveformState?.zoomIn()
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .zoomWaveformIn))
                .disabled(commandsAreSuspended || waveformState?.canZoomIn != true)

                Button("全体表示") {
                    waveformState?.showWholeWaveform()
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .showWholeWaveform))
                .disabled(commandsAreSuspended || waveformState?.canZoomOut != true)
            }
            .disabled(commandsAreSuspended)

            Divider()

            Button(
                chromeActions?.sidebarCommandTitle ?? "サイドバーを表示"
            ) {
                chromeActions?.toggleSidebar()
            }
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .toggleSidebar))
            .disabled(commandsAreSuspended || chromeActions == nil)

            Button(chromeActions?.inspectorCommandTitle ?? "設定を表示") {
                chromeActions?.toggleInspector()
            }
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .toggleInspector))
            .disabled(commandsAreSuspended || chromeActions == nil)
        }
    }

    private var commandsAreSuspended: Bool {
        commandsSuspended == true
    }

    private func processingModeButton(
        title: String,
        mode: ProcessingMode,
        shortcutAction: VelouraShortcutAction
    ) -> some View {
        Button {
            actions?.selectProcessingMode(mode)
        } label: {
            if actions?.processingMode == mode {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: shortcutAction))
        .disabled(commandsAreSuspended || actions?.canSwitchProcessingMode != true)
    }

    private func comparisonPairButton(
        title: String,
        pair: AudioComparisonPair,
        shortcutAction: VelouraShortcutAction
    ) -> some View {
        Button(title) {
            playbackState?.setComparisonPair(pair)
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: shortcutAction))
        .disabled(
            commandsAreSuspended
                || playbackState?.allowsComparisonPairSelection != true
        )
    }

    @ViewBuilder
    private func primaryComparisonPlaybackCommands() -> some View {
        Button(playbackState?.sideACommandTitle ?? "Aを再生") {
            playbackState?.playComparisonSideA()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .playSideA))
        .disabled(commandsAreSuspended || playbackState?.canPlayComparisonSideA != true)

        Button(playbackState?.playbackCommandTitle ?? "再生") {
            playbackState?.togglePlayback()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .togglePlayback))
        .disabled(commandsAreSuspended || playbackState?.canTogglePlayback != true)

        Button("停止") {
            playbackState?.stopPlayback()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .stopPlayback))
        .disabled(commandsAreSuspended || playbackState?.canStopPlayback != true)

        Button(playbackState?.sideBCommandTitle ?? "Bを再生") {
            playbackState?.playComparisonSideB()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .playSideB))
        .disabled(commandsAreSuspended || playbackState?.canPlayComparisonSideB != true)

        Divider()

        Button(playbackState?.comparisonSwitchCommandTitle ?? "A/B切替") {
            playbackState?.toggleComparisonSide()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .toggleComparisonSide))
        .disabled(commandsAreSuspended || playbackState?.canToggleComparisonSide != true)

        Button(
            playbackState?.isLoudnessMatchingEnabled == true
                ? "ラウドネス合わせをオフ"
                : "ラウドネス合わせをオン"
        ) {
            playbackState?.toggleLoudnessMatching()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .toggleLoudnessMatching))
        .disabled(commandsAreSuspended || playbackState == nil)

        if playbackState?.allowsComparisonPairSelection == true {
            Divider()

            Menu("比較対象") {
                comparisonPairButton(
                    title: "入力と\(processedAudioTitle)",
                    pair: .inputVsCorrected,
                    shortcutAction: .compareInputCorrected
                )
                comparisonPairButton(
                    title: "入力と最終版",
                    pair: .inputVsMastered,
                    shortcutAction: .compareInputMastered
                )
                comparisonPairButton(
                    title: "\(processedAudioTitle)と最終版",
                    pair: .correctedVsMastered,
                    shortcutAction: .compareCorrectedMastered
                )
            }
        }
    }

    @ViewBuilder
    private func stemPreviewRoleButtons() -> some View {
        ForEach(stemSelectionState?.availableRoles ?? [], id: \.rawValue) { role in
            Button {
                stemSelectionState?.selectPreviewStem(role)
            } label: {
                if stemSelectionState?.isPreviewStemSelected(role) == true {
                    Label(role.stemModeDisplayTitle, systemImage: "checkmark")
                } else {
                    Text(role.stemModeDisplayTitle)
                }
            }
        }
    }

    @ViewBuilder
    private func fixedComparisonPlaybackCommands(
        _ state: VelouraPlaybackPresentationState
    ) -> some View {
        Button(state.sideACommandTitle) {
            state.playComparisonSideA()
        }
        .disabled(commandsAreSuspended || !state.canPlayComparisonSideA)

        Button(state.playbackCommandTitle) {
            state.togglePlayback()
        }
        .disabled(commandsAreSuspended || !state.canTogglePlayback)

        Button("停止") {
            state.stopPlayback()
        }
        .disabled(commandsAreSuspended || !state.canStopPlayback)

        Button(state.sideBCommandTitle) {
            state.playComparisonSideB()
        }
        .disabled(commandsAreSuspended || !state.canPlayComparisonSideB)

        Divider()

        Button(state.comparisonSwitchCommandTitle) {
            state.toggleComparisonSide()
        }
        .disabled(commandsAreSuspended || !state.canToggleComparisonSide)

        Button(
            state.isLoudnessMatchingEnabled
                ? "ラウドネス合わせをオフ"
                : "ラウドネス合わせをオン"
        ) {
            state.toggleLoudnessMatching()
        }
        .disabled(commandsAreSuspended)
    }

    private func inspectorSectionButton(
        title: String,
        shortcutAction: VelouraShortcutAction,
        isDisabled: Bool = false,
        perform: @escaping @MainActor () -> Void
    ) -> some View {
        Button(title, action: perform)
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: shortcutAction))
            .disabled(commandsAreSuspended || isDisabled)
    }
}
