import SwiftUI

@MainActor
struct StemModeFooterView: View {
    @Bindable var model: StemModeWorkspaceModel
    @Binding var isFullLogPresented: Bool

    var body: some View {
        WorkspaceFooterLayout(
            events: model.session.recentActivityEvents,
            stages: workflowStages,
            isFullLogPresented: $isFullLogPresented
        )
    }

    private var workflowStages: [WorkspaceFooterStage] {
        [
            WorkspaceFooterStage(id: "analysis", title: "入力解析", state: inputAnalysisState),
            WorkspaceFooterStage(
                id: "correction",
                title: "補正処理",
                state: state(
                    for: model.session.correctionDisplayProgress,
                    isProcessing: model.session.isCorrectionProcessing,
                    pending: model.selectedInputURL == nil ? "待機" : "実行待ち"
                ),
                progress: activeProgress(
                    for: model.session.correctionDisplayProgress,
                    isProcessing: model.session.isCorrectionProcessing
                )
            ),
            WorkspaceFooterStage(
                id: "mastering",
                title: "マスタリング",
                state: state(
                    for: model.session.masteringDisplayProgress,
                    isProcessing: model.session.isMasteringProcessing,
                    pending: correctionComplete ? "実行待ち" : "待機"
                ),
                progress: activeProgress(
                    for: model.session.masteringDisplayProgress,
                    isProcessing: model.session.isMasteringProcessing
                )
            ),
            WorkspaceFooterStage(id: "export", title: "書き出し", state: exportState)
        ]
    }

    private var inputAnalysisState: WorkspaceFooterStageState {
        if model.isAnalyzingInput { return .active("解析中") }
        if model.inputEvaluation == nil, model.inputAnalysisError != nil {
            return .failed("一部取得失敗")
        }
        let progress = model.session.progress(for: .validateInput)
        if model.inputEvaluation != nil {
            return .complete("完了")
        }
        if progress.status == .failed { return .failed("失敗") }
        return .pending(model.selectedInputURL == nil ? "未選択" : "解析待ち")
    }

    private var exportState: WorkspaceFooterStageState {
        if model.isExportingAnyArtifact { return .active("保存中") }
        if model.session.lastExportedDestinationURL != nil { return .complete("保存済み") }
        if !model.exportableArtifacts.isEmpty { return .pending("保存可能") }
        return .pending("待機")
    }

    private var correctionComplete: Bool {
        model.session.correctionDisplayProgress.allSatisfy {
            $0.status == .completed || $0.status == .skipped
        }
    }

    private func state(
        for progresses: [StemModeProcessStepProgress],
        isProcessing: Bool,
        pending: String
    ) -> WorkspaceFooterStageState {
        if progresses.contains(where: { $0.status == .failed }) {
            return .failed("失敗")
        }
        if isProcessing {
            let title = progresses.first(where: { $0.status == .running })?.step.title
            return .active(title ?? "処理中")
        }
        if progresses.allSatisfy({ $0.status == .completed || $0.status == .skipped }) {
            return .complete("完了")
        }
        return .pending(pending)
    }

    private func activeProgress(
        for progresses: [StemModeProcessStepProgress],
        isProcessing: Bool
    ) -> Double? {
        guard isProcessing else { return nil }
        return progresses.map(\.fraction).reduce(0, +) / Double(progresses.count)
    }
}

struct StemModeFullProcessingLogView: View {
    let session: StemWorkflowSession
    let onDismiss: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Text("処理ログ")
                        .font(.title2.bold())
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                            .velouraAdaptiveGlass(in: Circle(), interactive: true)
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                    .accessibilityLabel("閉じる")
                    .help("詳細ログを閉じます")
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)

                ScrollView {
                    ProcessingLogView(
                        correctionLines: session.correctionLogLines,
                        masteringLines: session.masteringLogLines
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .velouraTransientOverlayScrollIndicators()
                }
                .scrollContentBackground(.hidden)
            }
            .velouraAdaptiveGlass(in: .rect(cornerRadius: 18))
        }
        .frame(minWidth: 640, idealWidth: 840, minHeight: 520, idealHeight: 680)
        .padding(18)
    }
}
