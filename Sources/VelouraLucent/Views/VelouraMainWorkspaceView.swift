import SwiftUI

struct VelouraMainWorkspaceView: View {
    @Bindable var job: ProcessingJob
    let preview: AudioPreviewController
    @State private var displayMode: WorkspaceDisplayMode = .basic

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    Picker("中央表示", selection: $displayMode) {
                        ForEach(WorkspaceDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 360, alignment: .leading)
                    .accessibilityLabel("中央表示")

                    switch displayMode {
                    case .basic:
                        basicWorkspace
                    case .detail:
                        DetailedAnalysisWorkspaceView(job: job)
                    }
                }
                .padding(24)
            }

            Divider()
            WorkspaceFooterView(job: job)
        }
        .navigationTitle("試聴と解析")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Veloura Lucent")
                .font(.largeTitle.bold())
            Text("入力、補正後、最終版を聴き比べながら、必要な解析だけを確認します。")
                .foregroundStyle(.secondary)
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

        VectorScopeView(preview: preview)

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
