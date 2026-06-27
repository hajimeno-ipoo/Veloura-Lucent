import SwiftUI

struct VelouraMainWorkspaceView: View {
    @Bindable var job: ProcessingJob
    let preview: AudioPreviewController
    @State private var displayMode: WorkspaceDisplayMode = .basic
    @State private var isFullLogPresented = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                fixedHeader

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch displayMode {
                        case .basic:
                            basicWorkspace
                        case .detail:
                            DetailedAnalysisWorkspaceView(job: job)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
                .scrollContentBackground(.hidden)

                Divider()
                WorkspaceFooterView(job: job, isFullLogPresented: $isFullLogPresented)
            }

            if isFullLogPresented {
                FullProcessingLogView(
                    correctionLines: job.logLines,
                    masteringLines: job.masteringLogLines,
                    onDismiss: { isFullLogPresented = false }
                )
                .padding(24)
                .transition(.scale(scale: 0.98).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: isFullLogPresented)
    }

    private var fixedHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Veloura Lucent")
                .font(.largeTitle.bold())
            Text("入力、補正後、最終版を聴き比べながら、必要な解析だけを確認します。")
                .foregroundStyle(.secondary)

            LiquidGlassSegmentedControl(
                title: "中央表示",
                options: WorkspaceDisplayMode.allCases,
                selection: $displayMode,
                label: \.title
            )
            .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
