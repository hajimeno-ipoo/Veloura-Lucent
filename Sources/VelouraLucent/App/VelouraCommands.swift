import SwiftUI

struct VelouraCommandActions {
    let canChooseInput: Bool
    let canRunCorrection: Bool
    let canRunMastering: Bool
    let isCorrectionRunning: Bool
    let isMasteringRunning: Bool
    let canCancelCorrection: Bool
    let canCancelMastering: Bool
    let canExportCorrected: Bool
    let canExportMastered: Bool
    let canTogglePlayback: Bool
    let canStopPlayback: Bool
    let canToggleComparisonSide: Bool
    let isPlaybackRunning: Bool
    let isInspectorPresented: Bool
    let chooseInputAudio: @MainActor () -> Void
    let runCorrection: @MainActor () -> Void
    let runMastering: @MainActor () -> Void
    let cancelCorrection: @MainActor () -> Void
    let cancelMastering: @MainActor () -> Void
    let exportCorrected: @MainActor (AudioExportFormat) -> Void
    let exportMastered: @MainActor (AudioExportFormat) -> Void
    let togglePlayback: @MainActor () -> Void
    let stopPlayback: @MainActor () -> Void
    let toggleComparisonSide: @MainActor () -> Void
    let toggleInspector: @MainActor () -> Void

    var correctionCommandTitle: String {
        isCorrectionRunning ? "補正をキャンセル" : "補正を実行"
    }

    var masteringCommandTitle: String {
        isMasteringRunning ? "マスタリングをキャンセル" : "マスタリングを実行"
    }

    var inspectorCommandTitle: String {
        isInspectorPresented ? "設定を隠す" : "設定を表示"
    }

    var playbackCommandTitle: String {
        isPlaybackRunning ? "一時停止" : "再生"
    }
}

private struct VelouraCommandActionsKey: FocusedValueKey {
    typealias Value = VelouraCommandActions
}

extension FocusedValues {
    var velouraCommandActions: VelouraCommandActions? {
        get { self[VelouraCommandActionsKey.self] }
        set { self[VelouraCommandActionsKey.self] = newValue }
    }
}

struct VelouraCommands: Commands {
    @FocusedValue(\.velouraCommandActions) private var actions

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
                        Button("補正後を書き出し") {
                            actions?.exportCorrected(format)
                        }
                        .disabled(actions?.canExportCorrected != true)

                        Button("最終版を書き出し") {
                            actions?.exportMastered(format)
                        }
                        .disabled(actions?.canExportMastered != true)
                    }
                }
            }
            .disabled(actions == nil)
        }

        CommandGroup(after: .sidebar) {
            Button(actions?.inspectorCommandTitle ?? "設定を表示") {
                actions?.toggleInspector()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(actions == nil)
        }
    }
}
