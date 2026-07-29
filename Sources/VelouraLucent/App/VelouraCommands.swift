import SwiftUI

struct VelouraExportCommandAction: Identifiable {
    let id: String
    let title: String
    let isEnabled: Bool
    let perform: @MainActor (AudioExportFormat) -> Void
}

struct VelouraCommandActions {
    let processingMode: ProcessingMode
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
    let canTogglePlayback: Bool
    let canStopPlayback: Bool
    let canToggleComparisonSide: Bool
    let isPlaybackRunning: Bool
    let selectProcessingMode: @MainActor (ProcessingMode) -> Void
    let chooseInputAudio: @MainActor () -> Void
    let runCorrection: @MainActor () -> Void
    var runRemix: @MainActor () -> Void = {}
    let runMastering: @MainActor () -> Void
    let cancelCorrection: @MainActor () -> Void
    var cancelRemix: @MainActor () -> Void = {}
    let cancelMastering: @MainActor () -> Void
    let togglePlayback: @MainActor () -> Void
    let stopPlayback: @MainActor () -> Void
    let toggleComparisonSide: @MainActor () -> Void

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

    var playbackCommandTitle: String {
        isPlaybackRunning ? "一時停止" : "再生"
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
}

struct VelouraCommands: Commands {
    @FocusedValue(\.velouraCommandActions) private var actions
    @FocusedValue(\.velouraWorkspaceChromeActions) private var chromeActions

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("音声ファイルを開く…", systemImage: "waveform.badge.plus") {
                actions?.chooseInputAudio()
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(actions?.canChooseInput != true)
        }

        CommandMenu("処理") {
            Button(actions?.correctionCommandTitle ?? "補正を実行") {
                if actions?.isCorrectionRunning == true {
                    actions?.cancelCorrection()
                } else {
                    actions?.runCorrection()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(actions.map { $0.isCorrectionRunning ? !$0.canCancelCorrection : !$0.canRunCorrection } ?? true)

            if actions?.processingMode == .stem {
                Button(actions?.remixCommandTitle ?? "再ミックスを実行") {
                    if actions?.isRemixRunning == true {
                        actions?.cancelRemix()
                    } else {
                        actions?.runRemix()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(
                    actions.map {
                        $0.isRemixRunning ? !$0.canCancelRemix : !$0.canRunRemix
                    } ?? true
                )
            }

            Button(actions?.masteringCommandTitle ?? "マスタリングを実行") {
                if actions?.isMasteringRunning == true {
                    actions?.cancelMastering()
                } else {
                    actions?.runMastering()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(actions.map { $0.isMasteringRunning ? !$0.canCancelMastering : !$0.canRunMastering } ?? true)
        }

        CommandMenu("再生") {
            Button(actions?.playbackCommandTitle ?? "再生") {
                actions?.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(actions?.canTogglePlayback != true)

            Button("停止") {
                actions?.stopPlayback()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(actions?.canStopPlayback != true)

            Divider()

            Button("A/B切替") {
                actions?.toggleComparisonSide()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(actions?.canToggleComparisonSide != true)
        }

        CommandGroup(after: .importExport) {
            Menu("書き出し") {
                ForEach(AudioExportFormat.allCases) { format in
                    Menu(format.menuTitle) {
                        ForEach(actions?.exportActions ?? []) { exportAction in
                            Button(exportAction.title) {
                                exportAction.perform(format)
                            }
                            .disabled(!exportAction.isEnabled)
                        }
                    }
                }
            }
            .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Menu("モード") {
                processingModeButton(
                    title: "通常補正",
                    mode: .standard
                )
                processingModeButton(
                    title: "Stem Mode",
                    mode: .stem
                )
            }
            .disabled(actions?.canSwitchProcessingMode != true)

            Divider()

            Button(
                chromeActions?.sidebarCommandTitle ?? "サイドバーを表示"
            ) {
                chromeActions?.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(chromeActions == nil)

            Button(chromeActions?.inspectorCommandTitle ?? "設定を表示") {
                chromeActions?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(chromeActions == nil)
        }
    }

    private func processingModeButton(
        title: String,
        mode: ProcessingMode
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
    }
}
