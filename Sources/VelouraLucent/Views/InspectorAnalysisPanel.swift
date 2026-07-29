import SwiftUI

struct InspectorAnalysisPanel: View {
    @Bindable var job: ProcessingJob
    let completionReport: CompletionReport?

    var body: some View {
        InspectorAnalysisPanelContent(
            isAnalyzing: job.isAnalyzingDisplayAnalysis,
            inputMetrics: job.inputMetrics,
            processedMetrics: job.outputMetrics,
            masteredMetrics: job.masteredMetrics,
            processedTitle: "補正後",
            qualityReport: qualityReport,
            completionReport: completionReport,
            selectionTitle: \.title,
            unavailableDescription: unavailableDescription
        ) {
            EmptyView()
        }
    }

    private var qualityReport: AudioQualityReport? {
        AudioQualityReportService.makeReport(
            input: job.inputMetrics,
            corrected: job.outputMetrics,
            mastered: job.masteredMetrics
        )
    }

    private func unavailableDescription(_ selection: InspectorAudioSelection) -> String {
        switch selection {
        case .input:
            "音声を選ぶと解析結果を表示します。"
        case .corrected:
            "補正が完了すると解析結果を表示します。"
        case .mastered:
            "マスタリングが完了すると解析結果を表示します。"
        }
    }
}

struct InspectorAnalysisPanelContent<AdditionalContent: View>: View {
    let isAnalyzing: Bool
    let inputMetrics: AudioMetricSnapshot?
    let processedMetrics: AudioMetricSnapshot?
    let masteredMetrics: AudioMetricSnapshot?
    let processedTitle: String
    let qualityReport: AudioQualityReport?
    let completionReport: CompletionReport?
    let selectionTitle: (InspectorAudioSelection) -> String
    let unavailableDescription: (InspectorAudioSelection) -> String
    @ViewBuilder let additionalContent: AdditionalContent

    @State private var selectedAudio: InspectorAudioSelection = .input
    @State private var isCompletionReportPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("解析結果と品質確認")
                    .font(.title3.bold())
                Spacer()
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("解析中")
                }
            }

            LiquidGlassSegmentedPicker(
                title: "確認する音源",
                options: InspectorAudioSelection.allCases,
                selection: $selectedAudio,
                label: selectionTitle
            )

            if let metrics = selectedMetrics {
                metricsGrid(metrics)
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(selectionTitle(selectedAudio))は未解析です")
                            .font(.headline)
                        Text(unavailableDescription(selectedAudio))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }

            if let qualityReport {
                qualityWarnings(qualityReport)
            }

            additionalContent
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
                help: "左右への広がり具合です。入力、\(processedTitle)、最終版を切り替えて変化を確認します。"
            )
        }
    }

    private func metricCell(
        title: String,
        value: String,
        color: Color,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TermHelpButton(title: title, reading: title, description: help)
            }
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
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
                    description: "入力、\(processedTitle)、最終版の実測値を比較し、ピーク、高域、音量、ステレオ幅、音の起伏の大きな変化を表示します。"
                )
                Spacer()
                Text(qualitySeverityText(report.severity))
                    .font(.body)
                    .foregroundStyle(qualitySeverityColor(report.severity))
            }

            if report.items.isEmpty {
                Label(
                    "数値上の追加候補はありません。最終版を聴いて違和感がないか確認してください。",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("聴いて気になる場合の調整候補")
                        .font(.body)
                    ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.body)
                                Text(item.detail)
                                    .font(.body)
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
        LiquidGlassActionButton(
            title: "完了後レポートを開く",
            systemImage: "doc.text.magnifyingglass",
            isDisabled: completionReport == nil
        ) {
            isCompletionReportPresented = true
        }
        .help(
            completionReport == nil
                ? "最終版と必要な解析が揃うと開けます"
                : "音量、ノイズ、高域保持の完了後レポートを開きます"
        )
        .popover(isPresented: $isCompletionReportPresented, arrowEdge: .leading) {
            if let completionReport {
                CompletionReportPopoverView(report: completionReport)
            }
        }
    }

    private var selectedMetrics: AudioMetricSnapshot? {
        switch selectedAudio {
        case .input:
            inputMetrics
        case .corrected:
            processedMetrics
        case .mastered:
            masteredMetrics
        }
    }

    private func truePeakColor(_ value: Double) -> Color {
        value > -0.3 ? .red : .primary
    }

    private func qualitySeverityText(_ severity: AudioQualityReportSeverity) -> String {
        switch severity {
        case .info:
            "確認"
        case .caution:
            "注意"
        case .warning:
            "警告"
        }
    }

    private func qualitySeverityColor(_ severity: AudioQualityReportSeverity) -> Color {
        switch severity {
        case .info:
            .secondary
        case .caution:
            VelouraTextColors.orange
        case .warning:
            .red
        }
    }

    private func qualitySeverityIcon(_ severity: AudioQualityReportSeverity) -> String {
        switch severity {
        case .info:
            "info.circle.fill"
        case .caution:
            "exclamationmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        }
    }
}
