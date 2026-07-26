import SwiftUI

@MainActor
struct WorkspaceToolbarView: View {
    let commandActions: VelouraCommandActions
    @Binding var processingMode: ProcessingMode
    let isModeSwitchDisabled: Bool

    @State private var highlightedTarget: LiquidGlassToolbarTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        HStack(spacing: 8) {
            ProcessingModeToolbarPicker(
                selection: $processingMode,
                isDisabled: isModeSwitchDisabled
            )

            actionGroup
            exportMenu
        }
    }

    private var actionGroup: some View {
        GlassEffectContainer(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: commandActions.chooseInputAudio) {
                    actionLabel(
                        "音声を選ぶ",
                        systemImage: "waveform.badge.plus",
                        target: .chooseInput
                    )
                }
                .buttonStyle(.plain)
                .onHover { updateHighlight(.chooseInput, isHovering: $0) }
                .help("入力音声を選びます")
                .disabled(isChooseInputDisabled)
                .keyboardShortcut("o", modifiers: .command)

                Button(action: performCorrectionAction) {
                    actionLabel(
                        correctionTitle,
                        systemImage: isCorrectionRunning
                            ? "xmark.circle.fill"
                            : "wand.and.sparkles",
                        target: .runCorrection
                    )
                }
                .buttonStyle(.plain)
                .onHover { updateHighlight(.runCorrection, isHovering: $0) }
                .help(correctionHelp)
                .disabled(isCorrectionDisabled)
                .keyboardShortcut("r", modifiers: .command)

                Button(action: performMasteringAction) {
                    actionLabel(
                        masteringTitle,
                        systemImage: isMasteringRunning
                            ? "xmark.circle.fill"
                            : "slider.horizontal.3",
                        target: .runMastering
                    )
                }
                .buttonStyle(.plain)
                .onHover { updateHighlight(.runMastering, isHovering: $0) }
                .help(masteringHelp)
                .disabled(isMasteringDisabled)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            .padding(4)
            .velouraAdaptiveGlass(in: .capsule, interactive: true)
        }
        .accessibilityElement(children: .contain)
    }

    private var exportMenu: some View {
        Menu {
            ForEach(AudioExportFormat.allCases) { format in
                Menu(format.menuTitle) {
                    exportMenuContent(format: format)
                }
            }
        } label: {
            exportLabel
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .padding(4)
        .velouraAdaptiveGlass(in: .capsule, interactive: true)
        .onHover { updateHighlight(.export, isHovering: $0) }
        .accessibilityLabel("書き出し")
        .help(exportHelp)
    }

    @ViewBuilder
    private func exportMenuContent(format: AudioExportFormat) -> some View {
        ForEach(commandActions.exportActions) { exportAction in
            Button(exportAction.title) {
                exportAction.perform(format)
            }
            .disabled(!exportAction.isEnabled)
        }
    }

    private var exportLabel: some View {
        LiquidGlassToolbarLabel(
            title: "書き出し",
            systemImage: "square.and.arrow.down",
            isActive: highlightedTarget == .export,
            effectID: "toolbar-action-highlight",
            namespace: glassNamespace,
            reduceMotion: reduceMotion
        )
    }

    private func actionLabel(
        _ title: String,
        systemImage: String,
        target: LiquidGlassToolbarTarget
    ) -> some View {
        LiquidGlassToolbarLabel(
            title: title,
            systemImage: systemImage,
            isActive: highlightedTarget == target,
            effectID: "toolbar-action-highlight",
            namespace: glassNamespace,
            reduceMotion: reduceMotion
        )
    }

    private var isChooseInputDisabled: Bool {
        !commandActions.canChooseInput
    }

    private var correctionTitle: String {
        commandActions.correctionCommandTitle
    }

    private var masteringTitle: String {
        commandActions.masteringCommandTitle
    }

    private var isCorrectionRunning: Bool {
        commandActions.isCorrectionRunning
    }

    private var isMasteringRunning: Bool {
        commandActions.isMasteringRunning
    }

    private var isCorrectionDisabled: Bool {
        commandActions.isCorrectionRunning
            ? !commandActions.canCancelCorrection
            : !commandActions.canRunCorrection
    }

    private var isMasteringDisabled: Bool {
        commandActions.isMasteringRunning
            ? !commandActions.canCancelMastering
            : !commandActions.canRunMastering
    }

    private var correctionHelp: String {
        isCorrectionRunning
            ? "補正処理をキャンセルします"
            : "入力音声に補正処理をかけます"
    }

    private var masteringHelp: String {
        isMasteringRunning
            ? "マスタリングをキャンセルします"
            : "補正後音声を最終版へ仕上げます"
    }

    private var exportHelp: String {
        processingMode == .standard
            ? "補正後または最終版を書き出します"
            : "補正後2mix、補正済みStemまたはStem Mode最終版を書き出します"
    }

    private func performCorrectionAction() {
        if commandActions.isCorrectionRunning {
            commandActions.cancelCorrection()
        } else {
            commandActions.runCorrection()
        }
    }

    private func performMasteringAction() {
        if commandActions.isMasteringRunning {
            commandActions.cancelMastering()
        } else {
            commandActions.runMastering()
        }
    }

    private func updateHighlight(
        _ target: LiquidGlassToolbarTarget,
        isHovering: Bool
    ) {
        let nextTarget = isHovering
            ? target
            : (highlightedTarget == target ? nil : highlightedTarget)
        guard nextTarget != highlightedTarget else { return }
        LiquidGlassMotion.perform(
            reduceMotion: reduceMotion,
            animation: LiquidGlassMotion.selection
        ) {
            highlightedTarget = nextTarget
        }
    }
}
