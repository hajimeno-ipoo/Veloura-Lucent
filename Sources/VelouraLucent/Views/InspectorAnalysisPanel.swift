import SwiftUI

struct InspectorAnalysisPanel: View {
    @Bindable var job: ProcessingJob
    let completionReport: CompletionReport?
    @State private var selectedAudio: InspectorAudioSelection = .input
    @State private var isCompletionReportPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("音声の確認")
                    .font(.title3.bold())
                Spacer()
                if job.isAnalyzingDisplayAnalysis {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("解析中")
                }
            }

            Picker("確認する音源", selection: $selectedAudio) {
                ForEach(InspectorAudioSelection.allCases) { selection in
                    Text(selection.title).tag(selection)
                }
            }
            .pickerStyle(.segmented)

            if let metrics = selectedMetrics {
                metricsGrid(metrics)
            } else {
                ContentUnavailableView(
                    unavailableTitle,
                    systemImage: "waveform.path.ecg",
                    description: Text(unavailableDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 140)
            }

            if let qualityReport {
                qualityWarnings(qualityReport)
            }

            completionReportControl
        }
    }

    private func metricsGrid(_ metrics: AudioMetricSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCell(
                title: "ラウドネス",
                value: String(format: "%.1f LUFS", metrics.integratedLoudnessLUFS),
                color: .primary,
                help: "曲全体の平均的な音量感です。数値だけで音の良し悪しは決まりません。"
            )
            metricCell(
                title: "True Peak",
                value: String(format: "%.2f dBTP", metrics.truePeakDBFS),
                color: truePeakColor(metrics.truePeakDBFS),
                help: "書き出しや再生で歪む可能性を見る最大ピークです。-0.3 dBTPを超える場合は試聴確認が必要です。"
            )
            metricCell(
                title: "ダイナミクス",
                value: String(format: "%.1f dB", metrics.crestFactorDB),
                color: .primary,
                help: "瞬間的なピークと平均音量の差です。曲の強弱や音の起伏を見る目安です。"
            )
            metricCell(
                title: "ステレオ幅",
                value: String(format: "%.2f", metrics.stereoWidth),
                color: .primary,
                help: "左右への広がり具合です。入力、補正後、最終版を切り替えて変化を確認します。"
            )
        }
    }

    private func metricCell(title: String, value: String, color: Color, help: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TermHelpButton(title: title, reading: title, description: help)
            }
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func qualityWarnings(_ report: AudioQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("品質警告")
                    .font(.headline)
                TermHelpButton(
                    title: "品質警告",
                    reading: "ひんしつけいこく",
                    description: "入力、補正後、最終版の実測値を比較し、ピーク、高域、音量、ステレオ幅、音の起伏の大きな変化を表示します。"
                )
                Spacer()
                Text(qualitySeverityText(report.severity))
                    .font(.caption.bold())
                    .foregroundStyle(qualitySeverityColor(report.severity))
            }

            if report.items.isEmpty {
                Label("数値上の追加候補はありません。最終版を聴いて違和感がないか確認してください。", systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("聴いて気になる場合の調整候補")
                        .font(.callout.bold())
                    ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.callout.bold())
                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: qualitySeverityIcon(item.severity))
                                .foregroundStyle(qualitySeverityColor(item.severity))
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var completionReportControl: some View {
        Button("完了後レポートを開く", systemImage: "doc.text.magnifyingglass") {
            isCompletionReportPresented = true
        }
        .disabled(completionReport == nil)
        .help(completionReport == nil ? "最終版と必要な解析が揃うと開けます" : "音量、ノイズ、高域保持の完了後レポートを開きます")
        .popover(isPresented: $isCompletionReportPresented, arrowEdge: .leading) {
            if let completionReport {
                CompletionReportPopoverView(report: completionReport)
            }
        }
    }

    private var selectedMetrics: AudioMetricSnapshot? {
        switch selectedAudio {
        case .input:
            return job.inputMetrics
        case .corrected:
            return job.outputMetrics
        case .mastered:
            return job.masteredMetrics
        }
    }

    private var qualityReport: AudioQualityReport? {
        AudioQualityReportService.makeReport(
            input: job.inputMetrics,
            corrected: job.outputMetrics,
            mastered: job.masteredMetrics
        )
    }

    private var unavailableTitle: String {
        "\(selectedAudio.title)は未解析です"
    }

    private var unavailableDescription: String {
        switch selectedAudio {
        case .input:
            return "音声を選ぶと解析結果を表示します。"
        case .corrected:
            return "補正が完了すると解析結果を表示します。"
        case .mastered:
            return "マスタリングが完了すると解析結果を表示します。"
        }
    }

    private func truePeakColor(_ value: Double) -> Color {
        value > -0.3 ? .red : .primary
    }

    private func qualitySeverityText(_ severity: AudioQualityReportSeverity) -> String {
        switch severity {
        case .info:
            return "確認"
        case .caution:
            return "注意"
        case .warning:
            return "警告"
        }
    }

    private func qualitySeverityColor(_ severity: AudioQualityReportSeverity) -> Color {
        switch severity {
        case .info:
            return .secondary
        case .caution:
            return .orange
        case .warning:
            return .red
        }
    }

    private func qualitySeverityIcon(_ severity: AudioQualityReportSeverity) -> String {
        switch severity {
        case .info:
            return "info.circle.fill"
        case .caution:
            return "exclamationmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        }
    }
}
