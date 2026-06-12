import SwiftUI

struct VelouraMainWorkspaceView: View {
    @Bindable var job: ProcessingJob
    let preview: AudioPreviewController
    let completionReport: CompletionReport?
    @Binding var selectedSection: VelouraWorkspaceSection

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                PreviewPanelView(
                    preview: preview,
                    inputFileURL: job.inputFile,
                    correctedFileURL: job.hasExistingOutput ? job.outputFile : nil,
                    masteredFileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil,
                    completionReport: completionReport
                )
                .padding(18)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 24))

                Picker("表示", selection: $selectedSection) {
                    ForEach(VelouraWorkspaceSection.allCases) { section in
                        Label(section.title, systemImage: section.systemImage)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.large)

                selectedContent
            }
            .padding(24)
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
    private var selectedContent: some View {
        switch selectedSection {
        case .comparison:
            VStack(alignment: .leading, spacing: 18) {
                AudioComparisonDashboardView(job: job, section: .masteringDifference)
                SpectrogramComparisonView(
                    input: job.inputSpectrogram,
                    corrected: job.outputSpectrogram,
                    mastered: job.masteredSpectrogram
                )
            }
        case .metrics:
            AudioComparisonDashboardView(job: job, section: .metrics)
        case .logs:
            ProcessingLogView(
                correctionLines: job.visibleLogLines,
                masteringLines: job.visibleMasteringLogLines
            )
        }
    }
}
