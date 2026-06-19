import SwiftUI

struct VelouraSidebarView: View {
    @Bindable var job: ProcessingJob

    var body: some View {
        List {
            Section {
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
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(.init(top: 5, leading: 10, bottom: 5, trailing: 8))
            }

            Section("音源") {
                SidebarFileRow(
                    title: "入力音声",
                    systemImage: "waveform",
                    fileURL: job.inputFile,
                    fileInfo: job.inputFileInfo,
                    placeholder: "まだ選択されていません",
                    tint: .blue
                )
                .listRowInsets(.init(top: 4, leading: 10, bottom: 4, trailing: 8))
                SidebarFileRow(
                    title: "補正後",
                    systemImage: "waveform.badge.checkmark",
                    fileURL: job.hasExistingOutput ? job.outputFile : nil,
                    fileInfo: job.hasExistingOutput ? job.outputFileInfo : nil,
                    placeholder: "補正後に表示されます",
                    tint: .green
                )
                .listRowInsets(.init(top: 4, leading: 10, bottom: 4, trailing: 8))
                SidebarFileRow(
                    title: "最終版",
                    systemImage: "waveform.path.ecg.rectangle",
                    fileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil,
                    fileInfo: job.hasExistingMasteredOutput ? job.masteredFileInfo : nil,
                    placeholder: "マスタリング後に表示されます",
                    tint: .orange
                )
                .listRowInsets(.init(top: 4, leading: 10, bottom: 4, trailing: 8))
            }

            Section("工程") {
                SidebarProcessingStatusView(job: job)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(.init(top: 5, leading: 10, bottom: 5, trailing: 8))
            }

        }
        .listStyle(.sidebar)
    }

}
