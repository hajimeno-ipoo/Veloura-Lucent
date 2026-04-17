import AppKit
import SwiftUI

struct ContentView: View {
    @State private var job = ProcessingJob()
    @State private var preview = AudioPreviewController()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            inputSection
            outputSection
            previewSection
            actionSection
            progressSection
            logSection
        }
        .padding(24)
        .frame(minWidth: 820, minHeight: 680)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spectral Lifter")
                .font(.largeTitle.bold())
            Text("AI音源の高域補完とシマーノイズ低減を、Macアプリから直接実行します。")
                .foregroundStyle(.secondary)
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
                Button("音声を選ぶ") {
                    if let url = FilePanelService.chooseAudioFile() {
                        job.prepareForSelection(url)
                        preview.stopPlayback()
                    }
                }
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("出力ファイル")
                .font(.headline)

            Text(job.outputFile?.path(percentEncoded: false) ?? "入力ファイルを選ぶと自動で決まります")
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var actionSection: some View {
        HStack(spacing: 12) {
            Button(job.isProcessing ? "処理中..." : "処理を開始") {
                startProcessing()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(job.inputFile == nil || job.isProcessing)

            Button("結果を開く") {
                guard let outputFile = job.outputFile else { return }
                NSWorkspace.shared.open(outputFile)
            }
            .disabled(!job.hasExistingOutput || job.isProcessing)

            Button("Finderで表示") {
                guard let outputFile = job.outputFile else { return }
                NSWorkspace.shared.activateFileViewerSelecting([outputFile])
            }
            .disabled(!job.hasExistingOutput || job.isProcessing)

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(job.statusMessage)
                    .foregroundStyle(job.statusColor)
                Text(preview.playbackLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ビフォーアフター確認")
                .font(.headline)

            HStack(spacing: 14) {
                previewCard(
                    title: "入力音声",
                    target: .input,
                    fileURL: job.inputFile,
                    tint: .blue
                )

                previewCard(
                    title: "出力音声",
                    target: .output,
                    fileURL: job.hasExistingOutput ? job.outputFile : nil,
                    tint: .green
                )
            }
        }
    }

    private func previewCard(title: String, target: AudioPreviewTarget, fileURL: URL?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text(preview.durationText(for: fileURL))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(fileURL?.lastPathComponent ?? "まだ確認できません")
                .lineLimit(2)
                .foregroundStyle(fileURL == nil ? .secondary : .primary)

            HStack(spacing: 8) {
                Button(preview.activeTarget == target ? "停止" : "再生") {
                    preview.togglePlayback(for: fileURL, target: target)
                }
                .disabled(fileURL == nil)

                if let fileURL {
                    Button("Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(tint.opacity(0.25), lineWidth: 1)
                )
        )
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("進行状況")
                    .font(.headline)
                Spacer()
                Text(job.progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: job.progressValue)
                .tint(job.statusColor)

            HStack(spacing: 8) {
                ForEach(ProcessingStep.allCases, id: \.self) { step in
                    progressBadge(for: step)
                }
            }
        }
    }

    private func progressBadge(for step: ProcessingStep) -> some View {
        let isCompleted = job.completedSteps.contains(step)
        let isActive = job.activeStep == step

        return HStack(spacing: 6) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : isActive ? "dot.circle.fill" : "circle")
                .foregroundStyle(isCompleted ? Color.green : isActive ? Color.orange : Color.secondary)
            Text(step.title)
                .font(.caption)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(isActive ? Color.orange.opacity(0.14) : isCompleted ? Color.green.opacity(0.14) : Color.secondary.opacity(0.08))
        )
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("処理ログ")
                .font(.headline)

            ScrollView {
                Text(job.logText.isEmpty ? "ここに処理ログが表示されます。" : job.logText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .frame(minHeight: 180)
        }
    }

    private func startProcessing() {
        guard let inputFile = job.inputFile else { return }

        Task {
            job.beginProcessing()

            do {
                let outputFile = try await AudioProcessingService().process(inputFile: inputFile) { message in
                    Task { @MainActor in
                        job.appendLog(message)
                    }
                }
                await MainActor.run {
                    job.finishSuccess(outputFile)
                }
            } catch {
                await MainActor.run {
                    job.finishFailure(error.localizedDescription)
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
