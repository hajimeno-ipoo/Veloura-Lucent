import SwiftUI

struct ProcessingControlsView: View {
    @Bindable var job: ProcessingJob
    let onChooseInput: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            inputSection
            settingsSection
            outputSection
        }
    }
    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("入力ファイル")
                .font(.headline)

            HStack {
                Text(job.inputFile?.path(percentEncoded: false) ?? "まだ選択されていません")
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button("音声を選ぶ", action: onChooseInput)
                .disabled(job.isProcessing || job.isMastering)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("プレビュー用の一時保持")
                .font(.headline)

            outputPathRow(title: "補正後プレビュー", fileURL: job.outputFile, placeholder: "補正を実行すると一時ファイルが作られます")
            outputPathRow(title: "最終版プレビュー", fileURL: job.masteredOutputFile, placeholder: "マスタリングを実行すると一時ファイルが作られます")
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            DetailedSettingsPanel(job: job)
            analysisModeSection
        }
    }

    private func outputPathRow(title: String, fileURL: URL?, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(fileURL?.path(percentEncoded: false) ?? placeholder)
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var analysisModeSection: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("解析モード")
                    .font(.subheadline.weight(.semibold))
                Picker("解析モード", selection: $job.selectedAnalysisMode) {
                    ForEach(AudioAnalysisMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(job.isProcessing)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("説明")
                    .font(.subheadline.weight(.semibold))
                Text(job.selectedAnalysisMode.summary)
                    .foregroundStyle(job.selectedAnalysisMode == .experimentalMetal ? .orange : .secondary)
                Text(job.selectedAnalysisMode.resolvedSummary)
                    .font(.caption)
                    .foregroundStyle(job.selectedAnalysisMode.resolvedMode == .experimentalMetal ? .orange : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
