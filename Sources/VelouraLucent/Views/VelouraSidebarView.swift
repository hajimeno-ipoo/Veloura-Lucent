import SwiftUI

struct VelouraSidebarView: View {
    @Bindable var job: ProcessingJob

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarHeader

                sidebarSection(title: "音源") {
                    SidebarFileRow(
                        title: "入力音声",
                        systemImage: "waveform",
                        fileURL: job.inputFile,
                        fileInfo: job.inputFileInfo,
                        placeholder: "まだ選択されていません",
                        tint: .blue
                    )
                    SidebarFileRow(
                        title: "補正後",
                        systemImage: "waveform.badge.checkmark",
                        fileURL: job.hasExistingOutput ? job.outputFile : nil,
                        fileInfo: job.hasExistingOutput ? job.outputFileInfo : nil,
                        placeholder: "補正後に表示されます",
                        tint: .green
                    )
                    SidebarFileRow(
                        title: "最終版",
                        systemImage: "waveform.path.ecg.rectangle",
                        fileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil,
                        fileInfo: job.hasExistingMasteredOutput ? job.masteredFileInfo : nil,
                        placeholder: "マスタリング後に表示されます",
                        tint: .orange
                    )
                }

                sidebarSection(title: "工程") {
                    SidebarProcessingStatusView(job: job)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 18)
        }
        .scrollContentBackground(.hidden)
    }

    private var sidebarHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .accessibilityHidden(true)
                Text("Veloura Lucent")
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .font(.callout.bold())
            Text("流れと状態を確認します。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sidebarSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
