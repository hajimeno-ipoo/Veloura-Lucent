import SwiftUI

struct InspectorAnalysisPanel: View {
    @Bindable var job: ProcessingJob
    let completionReport: CompletionReport?
    @Binding var selectedAudio: InspectorAudioSelection
    @Binding var isCompletionReportPresented: Bool

    var body: some View {
        InspectorAnalysisPanelContent(
            isAnalyzing: job.isAnalyzingDisplayAnalysis,
            inputMetrics: job.inputMetrics,
            processedMetrics: job.outputMetrics,
            masteredMetrics: job.masteredMetrics,
            processedTitle: "補正後",
            completionReport: completionReport,
            selectedAudio: $selectedAudio,
            isCompletionReportPresented: $isCompletionReportPresented,
            peakCeilingDB: peakCeilingDB,
            analysisState: analysisState,
            selectionTitle: \.title,
            unavailableDescription: unavailableDescription
        ) {
            EmptyView()
        }
    }

    private var peakCeilingDB: Double {
        Double((job.appliedMasteringSettings ?? job.editableMasteringSettings).peakCeilingDB)
    }

    private func analysisState(_ selection: InspectorAudioSelection) -> DisplayAnalysisPresentationState {
        let target: DisplayAnalysisTarget
        let hasSource: Bool
        let metrics: AudioMetricSnapshot?
        switch selection {
        case .input:
            target = .input
            hasSource = job.inputFile != nil
            metrics = job.inputMetrics
        case .corrected:
            target = .corrected
            hasSource = job.hasExistingOutput
            metrics = job.outputMetrics
        case .mastered:
            target = .mastered
            hasSource = job.hasExistingMasteredOutput
            metrics = job.masteredMetrics
        }
        return DisplayAnalysisPresentationState.resolve(
            hasSource: hasSource,
            hasMetrics: metrics != nil,
            isRunning: job.isAnalyzingDisplayAnalysis(for: target),
            hasFailed: job.hasFailedDisplayAnalysis(for: target)
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
    let completionReport: CompletionReport?
    @Binding var selectedAudio: InspectorAudioSelection
    @Binding var isCompletionReportPresented: Bool
    let peakCeilingDB: Double
    let analysisState: (InspectorAudioSelection) -> DisplayAnalysisPresentationState
    let selectionTitle: (InspectorAudioSelection) -> String
    let unavailableDescription: (InspectorAudioSelection) -> String
    @ViewBuilder let additionalContent: AdditionalContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("解析結果")
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
                let state = analysisState(selectedAudio)
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(emptyStateTitle(state, selection: selectedAudio))
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

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    additionalContent
                }

                completionReportControl
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func metricsGrid(_ metrics: AudioMetricSnapshot) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: 8),
                count: 4
            ),
            spacing: 8
        ) {
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
                help: truePeakHelp
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
        selectedAudio == .mastered && value > peakCeilingDB ? .red : .primary
    }

    private var truePeakHelp: String {
        if selectedAudio == .mastered {
            return "書き出しや再生で歪む可能性を見る最大ピークです。今回の設定上限は \(String(format: "%.1f", peakCeilingDB)) dBTP です。"
        }
        return "書き出しや再生で歪む可能性を見る最大ピークです。入力と処理途中の値は、最終版の設定上限による合否判定には使いません。"
    }

    private func emptyStateTitle(
        _ state: DisplayAnalysisPresentationState,
        selection: InspectorAudioSelection
    ) -> String {
        let title = selectionTitle(selection)
        switch state {
        case .notSelected:
            return "\(title)は未選択です"
        case .idle:
            return "\(title)は未解析です"
        case .running:
            return "\(title)を解析中です"
        case .completed:
            return "\(title)の解析結果を表示できません"
        case .failed:
            return "\(title)の解析に失敗しました"
        }
    }

}
