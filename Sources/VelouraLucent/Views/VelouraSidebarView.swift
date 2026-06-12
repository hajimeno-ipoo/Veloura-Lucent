import SwiftUI

struct VelouraSidebarView: View {
    @Bindable var job: ProcessingJob

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Veloura Lucent", systemImage: "waveform")
                        .font(.title3.bold())
                    Text("流れと状態を確認します。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("入力") {
                fileSummaryRow(
                    title: "入力ファイル",
                    fileURL: job.inputFile,
                    placeholder: "まだ選択されていません"
                )
                fileSummaryRow(
                    title: "補正後プレビュー",
                    fileURL: job.hasExistingOutput ? job.outputFile : nil,
                    placeholder: "補正後に表示されます"
                )
                fileSummaryRow(
                    title: "最終版プレビュー",
                    fileURL: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil,
                    placeholder: "マスタリング後に表示されます"
                )
            }

            Section("進捗") {
                ProcessingProgressView(job: job)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("工程")
    }

    private func fileSummaryRow(title: String, fileURL: URL?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout.weight(.semibold))
            Text(fileURL?.lastPathComponent ?? placeholder)
                .font(.callout)
                .foregroundStyle(fileURL == nil ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let fileURL {
                let path = fileURL.path(percentEncoded: false)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(path)
            }
        }
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(fileURL?.path(percentEncoded: false) ?? placeholder)
    }
}
