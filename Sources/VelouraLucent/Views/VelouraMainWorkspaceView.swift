import SwiftUI

struct VelouraMainWorkspaceView: View {
    @Bindable var job: ProcessingJob
    let preview: AudioPreviewController
    @State private var displayMode: WorkspaceDisplayMode = .basic
    @State private var isFullLogPresented = false

    var body: some View {
        WorkspaceCenterLayout(
            isFullLogPresented: isFullLogPresented
        ) {
            fixedHeader
        } mainContent: {
            switch displayMode {
            case .basic:
                basicWorkspace
            case .detail:
                DetailedAnalysisWorkspaceView(job: job)
            }
        } footer: {
            WorkspaceFooterView(
                job: job,
                isFullLogPresented: $isFullLogPresented
            )
        } fullLog: {
            FullProcessingLogView(
                job: job,
                onDismiss: { isFullLogPresented = false }
            )
        }
    }

    private var fixedHeader: some View {
        WorkspaceFixedHeaderView(
            title: "Veloura Lucent",
            summary: "音声を補正し、マスタリングで最終版に仕上げます。"
        ) {
            LiquidGlassSegmentedPicker(
                title: "中央表示",
                options: WorkspaceDisplayMode.allCases,
                selection: $displayMode,
                label: \.title
            )
        }
    }

    @ViewBuilder
    private var basicWorkspace: some View {
        AudioWaveformWorkspaceView(
            preview: preview,
            inputFileURL: job.inputFile,
            correctedFileURL: job.hasExistingOutput ? job.outputFile : nil,
            masteredFileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil
        )

        AverageSpectrumComparisonView(preview: preview)

        VectorScopeView(
            preview: preview,
            masteringSettings: job.appliedMasteringSettings ?? job.editableMasteringSettings
        )

        SpectrogramComparisonView(
            input: job.inputSpectrogram,
            corrected: job.outputSpectrogram,
            mastered: job.masteredSpectrogram
        )
    }
}

private enum WorkspaceDisplayMode: String, CaseIterable, Identifiable {
    case basic
    case detail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: "基本表示"
        case .detail: "詳細解析"
        }
    }
}
