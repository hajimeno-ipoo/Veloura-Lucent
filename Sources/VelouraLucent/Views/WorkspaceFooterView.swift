import SwiftUI

struct WorkspaceFooterView: View {
    @Bindable var job: ProcessingJob
    let onOpenFullLog: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 22) {
            RecentProcessingLogView(
                events: job.recentActivityEvents,
                onOpenFullLog: onOpenFullLog
            )
            .padding(12)
            .glassEffect(.clear, in: .rect(cornerRadius: 14))
            .frame(maxWidth: .infinity, alignment: .topLeading)

            OverallWorkflowView(stages: workflowStages)
                .padding(12)
                .glassEffect(.clear, in: .rect(cornerRadius: 14))
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 360, alignment: .topLeading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minHeight: 140, maxHeight: 158, alignment: .top)
    }

    private var workflowStages: [WorkspaceFooterStage] {
        [
            WorkspaceFooterStage(id: "analysis", title: "入力解析", state: inputAnalysisState),
            WorkspaceFooterStage(
                id: "correction",
                title: "補正処理",
                state: correctionState,
                progress: job.isProcessing ? job.progressValue : nil
            ),
            WorkspaceFooterStage(
                id: "mastering",
                title: "マスタリング",
                state: masteringState,
                progress: job.isMastering ? job.masteringProgressValue : nil
            ),
            WorkspaceFooterStage(id: "export", title: "書き出し", state: exportState)
        ]
    }

    private var inputAnalysisState: WorkspaceFooterStageState {
        if job.hasFailedDisplayAnalysis(for: .input) {
            return .failed("解析失敗")
        }
        if job.isAnalyzingDisplayAnalysis(for: .input) {
            return .active("解析中")
        }
        if job.inputMetrics != nil {
            return .complete("完了")
        }
        if job.inputFile != nil {
            return .active("準備中")
        }
        return .pending("未選択")
    }

    private var correctionState: WorkspaceFooterStageState {
        if job.lastError != nil || !job.failedSteps.isEmpty {
            return .failed("失敗")
        }
        if job.isProcessing {
            return .active(job.activeStep?.title ?? "処理中")
        }
        if job.hasExistingOutput {
            return .complete("完了")
        }
        return .pending(job.inputFile == nil ? "待機" : "実行待ち")
    }

    private var masteringState: WorkspaceFooterStageState {
        if job.masteringLastError != nil || !job.failedMasteringSteps.isEmpty {
            return .failed("失敗")
        }
        if job.isMastering {
            return .active(job.masteringActiveStep?.title ?? "処理中")
        }
        if job.hasExistingMasteredOutput {
            return .complete("完了")
        }
        return .pending(job.hasExistingOutput ? "実行待ち" : "待機")
    }

    private var exportState: WorkspaceFooterStageState {
        if job.hasExistingMasteredOutput {
            return job.exportedMasteredFile == nil ? .pending("保存可能") : .complete("保存済み")
        }
        if job.isMastering {
            return .pending("仕上げ中")
        }
        if job.hasExistingOutput {
            return job.exportedCorrectedFile == nil ? .pending("保存可能") : .complete("保存済み")
        }
        return .pending("待機")
    }
}
