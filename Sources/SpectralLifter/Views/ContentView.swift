import AppKit
import SwiftUI

struct ContentView: View {
    @State private var job = ProcessingJob()
    @State private var preview = AudioPreviewController()

    private let metricColumns = [
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12),
        GridItem(.flexible(minimum: 180), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            topSection
            Divider()
            bottomSection
        }
        .padding(24)
        .frame(minWidth: 920, minHeight: 780)
    }

    private var topSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            inputSection
            outputSection
            previewSection
            actionSection
            progressSection
        }
    }

    private var bottomSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                metricsSection
                logSection
            }
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        analyzeMetrics(for: url, target: .input)
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
                Text(job.isAnalyzingMetrics ? "比較を更新中" : preview.playbackLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("数値と視覚比較")
                    .font(.headline)
                Spacer()
                if job.isAnalyzingMetrics {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let inputMetrics = job.inputMetrics {
                let outputMetrics = job.outputMetrics
                VStack(spacing: 12) {
                    LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 12) {
                        metricCard(title: "Peak", input: inputMetrics.peakDBFS, output: outputMetrics?.peakDBFS, format: .dBFS, positiveIsBetter: false)
                        metricCard(title: "RMS", input: inputMetrics.rmsDBFS, output: outputMetrics?.rmsDBFS, format: .dBFS, positiveIsBetter: false)
                        metricCard(title: "重心", input: inputMetrics.centroidHz, output: outputMetrics?.centroidHz, format: .hertz, positiveIsBetter: true)
                        metricCard(title: "12kHz+", input: inputMetrics.hf12Ratio, output: outputMetrics?.hf12Ratio, format: .ratio(5), positiveIsBetter: true)
                        metricCard(title: "16kHz+", input: inputMetrics.hf16Ratio, output: outputMetrics?.hf16Ratio, format: .ratio(6), positiveIsBetter: true)
                        metricCard(title: "18kHz+", input: inputMetrics.hf18Ratio, output: outputMetrics?.hf18Ratio, format: .ratio(6), positiveIsBetter: true)
                    }

                    bandChart(input: inputMetrics.bandEnergies, output: outputMetrics?.bandEnergies ?? [])
                }
            } else {
                Text("音声を選ぶと、ここに比較結果が表示されます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricCard(title: String, input: Double, output: Double?, format: MetricFormat, positiveIsBetter: Bool) -> some View {
        let delta = output.map { $0 - input }
        let color: Color = {
            guard let delta else { return .secondary }
            if abs(delta) < 0.000001 { return .secondary }
            let improved = positiveIsBetter ? delta > 0 : delta < 0
            return improved ? .green : .orange
        }()

        return VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text("入力  \(formattedValue(input, format: format))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("出力  \(output.map { formattedValue($0, format: format) } ?? "--")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(output == nil ? .secondary : .primary)
            Text(delta.map { "差分  \(formattedDelta($0, format: format))" } ?? "差分  --")
                .font(.caption.monospacedDigit())
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func bandChart(input: [BandEnergyMetric], output: [BandEnergyMetric]) -> some View {
        let outputMap = Dictionary(uniqueKeysWithValues: output.map { ($0.id, $0) })
        let pairs = input.map { ($0, outputMap[$0.id]) }
        let levels = pairs.flatMap { [$0.0.levelDB, $0.1?.levelDB ?? $0.0.levelDB] }
        let maxLevel = (levels.max() ?? 0) + 3
        let minLevel = min((levels.min() ?? -60), -40) - 3

        return VStack(alignment: .leading, spacing: 10) {
            Text("帯域別の見え方")
                .font(.headline)

            ForEach(pairs, id: \.0.id) { inputMetric, outputMetric in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(inputMetric.label)
                            .font(.caption.bold())
                        Text(inputMetric.rangeDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(outputMetric.map { "差分  \(formattedDelta($0.levelDB - inputMetric.levelDB, format: .dBFS))" } ?? "差分  --")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        bandBar(title: "入力", value: inputMetric.levelDB, minLevel: minLevel, maxLevel: maxLevel, tint: .blue)
                        bandBar(title: "出力", value: outputMetric?.levelDB, minLevel: minLevel, maxLevel: maxLevel, tint: .green)
                    }
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func bandBar(title: String, value: Double?, minLevel: Double, maxLevel: Double, tint: Color) -> some View {
        let normalized = value.map { max(0, min(1, ($0 - minLevel) / max(maxLevel - minLevel, 1))) } ?? 0

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value.map { formattedValue($0, format: .dBFS) } ?? "--")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.gradient)
                        .frame(width: proxy.size.width * normalized)
                }
            }
            .frame(height: 10)
        }
        .frame(maxWidth: .infinity)
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
            .frame(maxWidth: .infinity)
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
                analyzeMetrics(for: outputFile, target: .output)
            } catch {
                await MainActor.run {
                    job.finishFailure(error.localizedDescription)
                }
            }
        }
    }

    private enum MetricTarget {
        case input
        case output
    }

    private enum MetricFormat {
        case dBFS
        case hertz
        case ratio(Int)
    }

    private func analyzeMetrics(for url: URL, target: MetricTarget) {
        Task {
            await MainActor.run {
                job.beginMetricAnalysis()
            }

            do {
                let metrics = try await Task.detached(priority: .utility) {
                    try AudioComparisonService.analyze(fileURL: url)
                }.value

                await MainActor.run {
                    switch target {
                    case .input:
                        job.finishInputMetricAnalysis(metrics)
                    case .output:
                        job.finishOutputMetricAnalysis(metrics)
                    }
                }
            } catch {
                await MainActor.run {
                    job.failMetricAnalysis()
                }
            }
        }
    }

    private func formattedValue(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBFS:
            return String(format: "%.2f dB", value)
        case .hertz:
            return String(format: "%.0f Hz", value)
        case .ratio(let decimals):
            return String(format: "%.\(decimals)f", value)
        }
    }

    private func formattedDelta(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBFS:
            return String(format: value >= 0 ? "+%.2f dB" : "%.2f dB", value)
        case .hertz:
            return String(format: value >= 0 ? "+%.0f Hz" : "%.0f Hz", value)
        case .ratio(let decimals):
            return String(format: value >= 0 ? "+%.\(decimals)f" : "%.\(decimals)f", value)
        }
    }
}

#Preview {
    ContentView()
}
