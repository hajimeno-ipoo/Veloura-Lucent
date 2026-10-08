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
            return AppLanguageSettings.string("キャンセル中...")
        }
        return AppLanguageSettings.string(isCorrectionRunning ? "補正をキャンセル" : "補正を実行")
    }

    var masteringCommandTitle: String {
        if isMasteringCancelling {
            return AppLanguageSettings.string("キャンセル中...")
        }
        return AppLanguageSettings.string(isMasteringRunning ? "マスタリングをキャンセル" : "マスタリングを実行")
    }

    var remixCommandTitle: String {
        if isRemixCancelling {
            return AppLanguageSettings.string("キャンセル中...")
        }
        return AppLanguageSettings.string(isRemixRunning ? "再ミックスをキャンセル" : "再ミックスを実行")
    }

    var remixHelp: String {
        let count = stemCount.map(String.init) ?? AppLanguageSettings.string("全")
        return String(
            format: AppLanguageSettings.string("補正済み%@Stemを自動値と手動上書きで再ミックスします"),
            locale: AppLanguageSettings.locale,
            count
        )
    }

}

struct VelouraWorkspaceChromeActions {
    let isSidebarPresented: Bool
    let isInspectorPresented: Bool
    let toggleSidebar: @MainActor () -> Void
    let toggleInspector: @MainActor () -> Void

    var sidebarCommandTitle: String {
        AppLanguageSettings.string(isSidebarPresented ? "サイドバーを隠す" : "サイドバーを表示")
    }

    var inspectorCommandTitle: String {
        AppLanguageSettings.string(isInspectorPresented ? "設定を隠す" : "設定を表示")
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
        sideACommandTitle: String = AppLanguageSettings.string("Aを再生"),
        sideBCommandTitle: String = AppLanguageSettings.string("Bを再生"),
        comparisonSwitchCommandTitle: String = AppLanguageSettings.string("A/B切替"),
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
        AppLanguageSettings.string(isPlaybackRunning ? "一時停止" : "再生")
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
    @AppStorage(AppLanguageSettings.key) private var languageSelectionRawValue = AppLanguageSelection.system.rawValue
    private let shortcutSettings: KeyboardShortcutSettings

    init(shortcutSettings: KeyboardShortcutSettings = .shared) {
        self.shortcutSettings = shortcutSettings
    }

    private var processedAudioTitle: String {
        localized(actions?.processedAudioTitle ?? "補正後")
    }

    private func localized(_ key: String) -> String {
        // Reading AppStorage makes the Commands body refresh as soon as the language changes.
        _ = languageSelectionRawValue
        return AppLanguageSettings.string(key)
    }

    private func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), locale: AppLanguageSettings.locale, arguments: arguments)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(localized("Veloura Lucentについて"), systemImage: "info.circle") {
                openWindow(id: "about")
            }

            Divider()

            Button(localized("キーボード操作…"), systemImage: "keyboard") {
                keyboardShortcutManagerPresentation?.wrappedValue = true
            }
            .disabled(commandsAreSuspended || keyboardShortcutManagerPresentation == nil)
        }

        CommandGroup(after: .newItem) {
            Button(localized("音声ファイルを開く…"), systemImage: "waveform.badge.plus") {
                actions?.chooseInputAudio()
            }
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .chooseInputAudio))
            .disabled(commandsAreSuspended || actions?.canChooseInput != true)
        }

        CommandMenu(localized("処理")) {
            Button(actions?.correctionCommandTitle ?? localized("補正を実行")) {
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
                Button(actions?.remixCommandTitle ?? localized("再ミックスを実行")) {
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

            Button(actions?.masteringCommandTitle ?? localized("マスタリングを実行")) {
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

        CommandMenu(localized("再生")) {
            if let stemPlaybackState {
                Menu(localizedFormat("入力／%@／最終版", localized("補正後"))) {
                    primaryComparisonPlaybackCommands()
                }

                Menu(localizedFormat("%@：raw／補正後", localized(stemPlaybackState.selectedStemTitle))) {
                    Menu(localized("再生するStem")) {
                        stemPreviewRoleButtons()
                    }

                    Divider()

                    fixedComparisonPlaybackCommands(stemPlaybackState.stemComparison)
                }

                Menu(localized("補正後／再ミックス")) {
                    fixedComparisonPlaybackCommands(stemPlaybackState.remixComparison)
                }
            } else {
                primaryComparisonPlaybackCommands()
            }
        }

        CommandGroup(after: .importExport) {
            Menu(localized("書き出し")) {
                ForEach(AudioExportFormat.allCases) { format in
                    Menu(localizedFormat("%@（%@）", localized(format.title), localized(format.detail))) {
                        ForEach(actions?.exportActions ?? []) { exportAction in
                            if exportAction.startsSection {
                                Divider()
                            }
                            Button(localized(exportAction.title)) {
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
            Menu(localized("モード")) {
                processingModeButton(
                    title: localized(ProcessingMode.standard.title),
                    mode: .standard,
                    shortcutAction: .selectStandardMode
                )
                processingModeButton(
                    title: localized(ProcessingMode.stem.title),
                    mode: .stem,
                    shortcutAction: .selectStemMode
                )
            }
            .disabled(commandsAreSuspended || actions?.canSwitchProcessingMode != true)

            Divider()

            Menu(localized("中央表示")) {
                Button(localized("基本表示")) {
                    workspaceDisplaySelection?.wrappedValue = .basic
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .showBasicDisplay))
                .disabled(commandsAreSuspended || workspaceDisplaySelection == nil)

                Button(localized("詳細解析")) {
                    workspaceDisplaySelection?.wrappedValue = .detailedAnalysis
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .showDetailedAnalysis))
                .disabled(commandsAreSuspended || workspaceDisplaySelection == nil)

                Divider()

                Button(localized("詳細ログ")) {
                    workspaceDisplaySelection?.wrappedValue = .fullLog
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .showFullLog))
                .disabled(commandsAreSuspended || workspaceDisplaySelection == nil)
            }
            .disabled(commandsAreSuspended)

            Menu(localized("右側設定")) {
                inspectorSectionButton(
                    title: localized("補正"),
                    shortcutAction: .showCorrectionSettings,
                    isDisabled: inspectorSettingsState == nil,
                    perform: { inspectorSettingsState?.show(.correction) }
                )
                inspectorSectionButton(
                    title: localized("再ミックス"),
                    shortcutAction: .showRemixSettings,
                    isDisabled: inspectorSettingsState?.isStemMode != true,
                    perform: { inspectorSettingsState?.show(.remix) }
                )
                inspectorSectionButton(
                    title: localized("マスタリング"),
                    shortcutAction: .showMasteringSettings,
                    isDisabled: inspectorSettingsState == nil,
                    perform: { inspectorSettingsState?.show(.mastering) }
                )
                inspectorSectionButton(
                    title: localized("アプリ"),
                    shortcutAction: .showAppSettings,
                    isDisabled: inspectorSettingsState == nil,
                    perform: { inspectorSettingsState?.show(.app) }
                )
            }
            .disabled(commandsAreSuspended)

            Menu(localized("解析結果")) {
                inspectorSectionButton(
                    title: localized("入力"),
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
                    title: localized("最終版"),
                    shortcutAction: .showMasteredAnalysis,
                    isDisabled: inspectorAnalysisState == nil,
                    perform: { inspectorAnalysisState?.show(.mastered) }
                )

                Divider()

                inspectorSectionButton(
                    title: localized("完了後レポート"),
                    shortcutAction: .showCompletionReport,
                    isDisabled: inspectorAnalysisState?.canShowCompletionReport != true,
                    perform: { inspectorAnalysisState?.showCompletionReport() }
                )
            }
            .disabled(commandsAreSuspended)

            Menu(localized("波形")) {
                Button(localized("縮小")) {
                    waveformState?.zoomOut()
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .zoomWaveformOut))
                .disabled(commandsAreSuspended || waveformState?.canZoomOut != true)

                Button(localized("拡大")) {
                    waveformState?.zoomIn()
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .zoomWaveformIn))
                .disabled(commandsAreSuspended || waveformState?.canZoomIn != true)

                Button(localized("全体表示")) {
                    waveformState?.showWholeWaveform()
                }
                .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .showWholeWaveform))
                .disabled(commandsAreSuspended || waveformState?.canZoomOut != true)
            }
            .disabled(commandsAreSuspended)

            Divider()

            Button(
                localized(chromeActions?.sidebarCommandTitle ?? "サイドバーを表示")
            ) {
                chromeActions?.toggleSidebar()
            }
            .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .toggleSidebar))
            .disabled(commandsAreSuspended || chromeActions == nil)

            Button(localized(chromeActions?.inspectorCommandTitle ?? "設定を表示")) {
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
        Button(localized(playbackState?.sideACommandTitle ?? "Aを再生")) {
            playbackState?.playComparisonSideA()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .playSideA))
        .disabled(commandsAreSuspended || playbackState?.canPlayComparisonSideA != true)

        Button(localized(playbackState?.playbackCommandTitle ?? "再生")) {
            playbackState?.togglePlayback()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .togglePlayback))
        .disabled(commandsAreSuspended || playbackState?.canTogglePlayback != true)

        Button(localized("停止")) {
            playbackState?.stopPlayback()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .stopPlayback))
        .disabled(commandsAreSuspended || playbackState?.canStopPlayback != true)

        Button(localized(playbackState?.sideBCommandTitle ?? "Bを再生")) {
            playbackState?.playComparisonSideB()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .playSideB))
        .disabled(commandsAreSuspended || playbackState?.canPlayComparisonSideB != true)

        Divider()

        Button(localized(playbackState?.comparisonSwitchCommandTitle ?? "A/B切替")) {
            playbackState?.toggleComparisonSide()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .toggleComparisonSide))
        .disabled(commandsAreSuspended || playbackState?.canToggleComparisonSide != true)

        Button(
            playbackState?.isLoudnessMatchingEnabled == true
                ? localized("ラウドネス合わせをオフ")
                : localized("ラウドネス合わせをオン")
        ) {
            playbackState?.toggleLoudnessMatching()
        }
        .keyboardShortcut(shortcutSettings.keyboardShortcut(for: .toggleLoudnessMatching))
        .disabled(commandsAreSuspended || playbackState == nil)

        if playbackState?.allowsComparisonPairSelection == true {
            Divider()

            Menu(localized("比較対象")) {
                comparisonPairButton(
                    title: localizedFormat("入力と%@", localized("補正後")),
                    pair: .inputVsCorrected,
                    shortcutAction: .compareInputCorrected
                )
                comparisonPairButton(
                    title: localized("入力と最終版"),
                    pair: .inputVsMastered,
                    shortcutAction: .compareInputMastered
                )
                comparisonPairButton(
                    title: localizedFormat("%@と最終版", localized("補正後")),
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
                    Label(localized(role.stemModeDisplayTitle), systemImage: "checkmark")
                } else {
                    Text(localized(role.stemModeDisplayTitle))
                }
            }
        }
    }

    @ViewBuilder
    private func fixedComparisonPlaybackCommands(
        _ state: VelouraPlaybackPresentationState
    ) -> some View {
        Button(localized(state.sideACommandTitle)) {
            state.playComparisonSideA()
        }
        .disabled(commandsAreSuspended || !state.canPlayComparisonSideA)

        Button(localized(state.playbackCommandTitle)) {
            state.togglePlayback()
        }
        .disabled(commandsAreSuspended || !state.canTogglePlayback)

        Button(localized("停止")) {
            state.stopPlayback()
        }
        .disabled(commandsAreSuspended || !state.canStopPlayback)

        Button(localized(state.sideBCommandTitle)) {
            state.playComparisonSideB()
        }
        .disabled(commandsAreSuspended || !state.canPlayComparisonSideB)

        Divider()

        Button(localized(state.comparisonSwitchCommandTitle)) {
            state.toggleComparisonSide()
        }
        .disabled(commandsAreSuspended || !state.canToggleComparisonSide)

        Button(
            state.isLoudnessMatchingEnabled
                ? localized("ラウドネス合わせをオフ")
                : localized("ラウドネス合わせをオン")
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
