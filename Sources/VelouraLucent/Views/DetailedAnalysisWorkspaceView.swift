import Charts
import SwiftUI

struct DetailedAnalysisWorkspaceView: View {
    @Bindable var job: ProcessingJob

    var body: some View {
        DetailedAnalysisComparisonView(
            presentation: DetailedAnalysisPresentation(job: job)
        )
    }
}

@MainActor
struct DetailedAnalysisPresentation {
    let inputMetrics: AudioMetricSnapshot?
    let correctedMetrics: AudioMetricSnapshot?
    let masteredMetrics: AudioMetricSnapshot?
    let noiseReport: NoiseCheckReport?
    let isAnalyzing: Bool
    let statusText: String?
    let failedText: String?
    let analyzingTargets: Set<DisplayAnalysisTarget>
    let failedTargets: Set<DisplayAnalysisTarget>
    let availableTargets: Set<DisplayAnalysisTarget>
    let emptyTitle: String
    let emptyDescription: String
    let correctedTitle: String

    init(job: ProcessingJob) {
        inputMetrics = job.inputMetrics
        correctedMetrics = job.outputMetrics
        masteredMetrics = job.masteredMetrics
        noiseReport = NoiseCheckReportService.makeReport(
            input: job.inputNoiseMeasurements,
            corrected: job.outputNoiseMeasurements,
            mastered: job.masteredNoiseMeasurements,
            correctionSettings: job.appliedCorrectionSettings ?? job.editableCorrectionSettings,
            settings: job.appliedMasteringSettings ?? job.editableMasteringSettings
        )
        isAnalyzing = job.isAnalyzingDisplayAnalysis
        statusText = job.displayAnalysisStatusText
        failedText = job.failedDisplayAnalysisText
        analyzingTargets = Set(
            DisplayAnalysisTarget.allDisplayTargets.filter {
                job.isAnalyzingDisplayAnalysis(for: $0)
            }
        )
        failedTargets = Set(
            DisplayAnalysisTarget.allDisplayTargets.filter {
                job.hasFailedDisplayAnalysis(for: $0)
            }
        )
        availableTargets = Set(
            DisplayAnalysisTarget.allDisplayTargets.filter { target in
                switch target {
                case .input: job.inputFile != nil
                case .corrected: job.hasExistingOutput
                case .mastered: job.hasExistingMasteredOutput
                }
            }
        )
        emptyTitle = "入力音声は未解析です"
        emptyDescription = "音声を選ぶと、入力、補正後、最終版の詳細解析を表示します。"
        correctedTitle = "補正後"
    }

    init(
        inputMetrics: AudioMetricSnapshot?,
        correctedMetrics: AudioMetricSnapshot?,
        masteredMetrics: AudioMetricSnapshot?,
        noiseReport: NoiseCheckReport?,
        isAnalyzing: Bool,
        statusText: String?,
        failedText: String?,
        analyzingTargets: Set<DisplayAnalysisTarget>,
        failedTargets: Set<DisplayAnalysisTarget>,
        availableTargets: Set<DisplayAnalysisTarget>,
        emptyTitle: String,
        emptyDescription: String,
        correctedTitle: String = "補正後"
    ) {
        self.inputMetrics = inputMetrics
        self.correctedMetrics = correctedMetrics
        self.masteredMetrics = masteredMetrics
        self.noiseReport = noiseReport
        self.isAnalyzing = isAnalyzing
        self.statusText = statusText
        self.failedText = failedText
        self.analyzingTargets = analyzingTargets
        self.failedTargets = failedTargets
        self.availableTargets = availableTargets
        self.emptyTitle = emptyTitle
        self.emptyDescription = emptyDescription
        self.correctedTitle = correctedTitle
    }

    func metrics(for target: DisplayAnalysisTarget) -> AudioMetricSnapshot? {
        switch target {
        case .input: inputMetrics
        case .corrected: correctedMetrics
        case .mastered: masteredMetrics
        }
    }
}

struct DetailedAnalysisComparisonView: View {
    let presentation: DetailedAnalysisPresentation
    private let noiseDeltaScale = InputRelativeDeltaScale()
    @State private var showLoudness = false
    @State private var showDynamics = false
    @State private var showSpectrum = false
    @State private var showBands = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            analysisStateSummary

            if let input = presentation.inputMetrics {
                metricComparisonCard(
                    input: input,
                    corrected: presentation.correctedMetrics,
                    mastered: presentation.masteredMetrics
                )

                if let noiseReport {
                    noiseComparisonCard(noiseReport)
                } else {
                    unavailableCard(
                        title: "ノイズ7種類比較",
                        description: "ノイズ測定が完了すると、ヒス、サ行、高域のチラつき、こもり、ハム、低域ゴロゴロ、環境音を表示します。"
                    )
                }

                correlationCard(stages: comparisonStages)

                VStack(alignment: .leading, spacing: 16) {
                    analysisDisclosureSection(
                        title: "短時間ラウドネス",
                        help: "場面ごとの音量感です。入力、\(presentation.correctedTitle)、最終版を同じ基準で比べます。",
                        isExpanded: $showLoudness
                    ) {
                        shortTermLoudnessChart(stages: comparisonStages)
                    }
                    .analysisCard()

                    analysisDisclosureSection(
                        title: "ダイナミクス推移",
                        help: "音の山と平均音量の差です。小さくなりすぎると、音が押し固められている可能性があります。",
                        isExpanded: $showDynamics
                    ) {
                        dynamicsChart(stages: comparisonStages)
                    }
                    .analysisCard()

                    analysisDisclosureSection(
                        title: "平均スペクトル比較",
                        help: "曲全体の周波数ごとの相対量です。再生中スペクトルとは別に、全体の傾向を比べます。",
                        isExpanded: $showSpectrum
                    ) {
                        spectrumComparisonCharts(stages: comparisonStages)
                    }
                    .analysisCard()

                    analysisDisclosureSection(
                        title: "周波数帯域詳細",
                        help: "9つの帯域を、入力、\(presentation.correctedTitle)、最終版の3段階と、入力を基準にした差分で確認します。実測値と差分は同じ小数第2位の表示値から計算します。",
                        isExpanded: $showBands
                    ) {
                        bandDetailRows(
                            input: input,
                            corrected: presentation.correctedMetrics,
                            mastered: presentation.masteredMetrics
                        )
                    }
                    .analysisCard()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    presentation.emptyTitle,
                    systemImage: "waveform.path.ecg",
                    description: Text(presentation.emptyDescription)
                )
                .frame(maxWidth: .infinity, minHeight: 260)
                .analysisCard()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var analysisStateSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("解析状態")
                    .font(.headline)
                Spacer()
                if presentation.isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("解析中")
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], alignment: .leading, spacing: 8) {
                ForEach(DisplayAnalysisTarget.allDisplayTargets, id: \.self) { target in
                    statePill(for: target)
                }
            }

            if let statusText = presentation.statusText {
                Label(statusText, systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let failedText = presentation.failedText {
                Label(failedText, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .analysisCard()
    }

    private func statePill(for target: DisplayAnalysisTarget) -> some View {
        let state = aggregateState(for: target)
        return HStack(spacing: 8) {
            Circle()
                .fill(state.color)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(for: target))
                    .font(.callout.weight(.semibold))
                Text(state.title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(state.color.opacity(0.12)), in: .capsule)
        .accessibilityElement(children: .combine)
    }

    private func aggregateState(for target: DisplayAnalysisTarget) -> DisplayAnalysisPresentationState {
        DisplayAnalysisPresentationState.resolve(
            hasSource: presentation.availableTargets.contains(target),
            hasMetrics: metrics(for: target) != nil,
            isRunning: presentation.analyzingTargets.contains(target),
            hasFailed: presentation.failedTargets.contains(target)
        )
    }

    private func metricComparisonCard(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> some View {
        let rows = metricRows(input: input, corrected: corrected, mastered: mastered)
        return VStack(alignment: .leading, spacing: 12) {
            sectionLabel(
                title: "主要数値比較",
                help: "入力、\(presentation.correctedTitle)、最終版、処理差分、マスタリング差分を同じ表で見ます。差分は良し悪しではなく、何が変わったかを見るための値です。"
            )

            ViewThatFits(in: .horizontal) {
                wideMetricTable(
                    rows,
                    labelWidth: 152,
                    numericWidth: 104,
                    horizontalSpacing: 14
                )
                wideMetricTable(
                    rows,
                    labelWidth: 108,
                    numericWidth: 72,
                    horizontalSpacing: 8
                )
            }
        }
        .analysisCard()
        .accessibilityElement(children: .contain)
    }

    private func wideMetricTable(
        _ rows: [MetricComparisonRow],
        labelWidth: CGFloat,
        numericWidth: CGFloat,
        horizontalSpacing: CGFloat
    ) -> some View {
        Grid(
            alignment: .leadingFirstTextBaseline,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: 10
        ) {
            GridRow {
                tableHeader("項目")
                    .frame(width: labelWidth, alignment: .leading)
                Color.clear
                    .frame(width: 24, height: 1)
                    .accessibilityHidden(true)
                tableHeader("入力")
                    .multilineTextAlignment(.trailing)
                    .frame(width: numericWidth, alignment: .trailing)
                tableHeader(presentation.correctedTitle)
                    .multilineTextAlignment(.trailing)
                    .frame(width: numericWidth, alignment: .trailing)
                tableHeader("最終版")
                    .multilineTextAlignment(.trailing)
                    .frame(width: numericWidth, alignment: .trailing)
                tableHeader(processingDeltaTitle)
                    .multilineTextAlignment(.trailing)
                    .frame(width: numericWidth, alignment: .trailing)
                tableHeader("マスタリング差分")
                    .multilineTextAlignment(.trailing)
                    .frame(width: numericWidth, alignment: .trailing)
            }
            Divider().gridCellColumns(7)
            ForEach(rows) { row in
                GridRow {
                    Text(row.definition.label)
                        .font(.callout.weight(.semibold))
                        .frame(width: labelWidth, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    TermHelpButton(
                        title: row.definition.label,
                        reading: row.definition.reading,
                        description: row.definition.description
                    )
                    metricValue(row.input, format: row.valueFormat, tint: .blue)
                        .frame(width: numericWidth, alignment: .trailing)
                    metricValue(row.corrected, format: row.valueFormat, tint: .green)
                        .frame(width: numericWidth, alignment: .trailing)
                    metricValue(row.mastered, format: row.valueFormat, tint: .orange)
                        .frame(width: numericWidth, alignment: .trailing)
                    metricValue(row.correctionDelta, format: row.deltaFormat, tint: .primary)
                        .frame(width: numericWidth, alignment: .trailing)
                    metricValue(row.masteringDelta, format: row.deltaFormat, tint: .primary)
                        .frame(width: numericWidth, alignment: .trailing)
                }
            }
        }
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func metricValue(_ value: Double?, format: MetricFormat, tint: Color) -> some View {
        Text(value.map { formatValue($0, format: format) } ?? "--")
            .font(.callout.monospacedDigit().weight(.semibold))
            .foregroundStyle(value == nil ? .secondary : tint)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
    }

    private func noiseComparisonCard(_ report: NoiseCheckReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(
                title: "ノイズ7種類比較",
                help: "ヒス、サ行、高域のチラつき、こもり、ハム、低域ゴロゴロ、環境音を、入力、\(presentation.correctedTitle)、最終版で比較します。"
            )

            ForEach(report.rows) { row in
                noiseRow(row)
            }
        }
        .analysisCard()
        .accessibilityElement(children: .contain)
    }

    private func noiseRow(_ row: NoiseCheckRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.label)
                        .font(.headline)
                    Text(row.measurementDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(row.displayDescription)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(noiseOriginalComparisonStatus(row))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(noiseOriginalComparisonColor(row))
                    Text(noiseOriginalComparisonReason(row))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            noiseStageFlow(row)
            noiseOriginalDeltaComparison(row)
        }
        .padding(12)
        .velouraAdaptiveGlass(in: .rect(cornerRadius: 12))
    }

    private func noiseStageFlow(_ row: NoiseCheckRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            noiseStageValue(title: "入力", value: row.input, tint: .blue)
            noiseStageTransition(deltaDB: row.correctionDeltaDB)
            noiseStageValue(title: presentation.correctedTitle, value: row.corrected, tint: .green)
            noiseStageTransition(deltaDB: row.masteringDeltaDB)
            noiseStageValue(title: "最終版", value: row.mastered, tint: .orange)
        }
    }

    private func noiseStageValue(
        title: String,
        value: NoiseCheckValue?,
        tint: Color
    ) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(value.map { formatNoiseValue($0) } ?? "--")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(value == nil ? Color.secondary : tint)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private func noiseStageTransition(deltaDB: Double?) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(formatNoiseDelta(deltaDB))
                .font(.callout.monospacedDigit().weight(.semibold))
            Text(noiseDeltaDirectionText(deltaDB))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 104)
        .accessibilityElement(children: .combine)
    }

    private func noiseOriginalDeltaComparison(_ row: NoiseCheckRow) -> some View {
        let displayScale = InputRelativeDeltaScale.fitting(
            [row.correctedDeltaFromInputDB, row.masteredDeltaFromInputDB].compactMap { $0 }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text("原音を基準にした差分")
                .font(.callout.weight(.semibold))
            HStack(spacing: 8) {
                Color.clear.frame(width: 112, height: 1)
                HStack(spacing: 8) {
                    Text("ノイズ減少 \(formatNoiseDelta(-displayScale.maximumMagnitudeDB))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Text("原音 0")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                    Text("ノイズ増加 \(formatNoiseDelta(displayScale.maximumMagnitudeDB))")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                Color.clear.frame(width: 92, height: 1)
            }
            noiseOriginalDeltaTrack(
                title: presentation.correctedTitle,
                deltaDB: row.correctedDeltaFromInputDB,
                displayScale: displayScale
            )
            noiseOriginalDeltaTrack(
                title: "最終版",
                deltaDB: row.masteredDeltaFromInputDB,
                displayScale: displayScale
            )
            Text("中央の帯は原音との差が±1.0 dB以内です。表示範囲は補正後と最終版の差に合わせて項目ごとに調整します。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func noiseOriginalDeltaTrack(
        title: String,
        deltaDB: Double?,
        displayScale: InputRelativeDeltaScale
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .frame(width: 112, alignment: .leading)
            GeometryReader { proxy in
                let unchangedStart = proxy.size.width * displayScale.ratio(for: -displayScale.unchangedThresholdDB)
                let unchangedEnd = proxy.size.width * displayScale.ratio(for: displayScale.unchangedThresholdDB)
                let center = proxy.size.width * displayScale.ratio(for: 0)
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 10)
                        .offset(y: 2)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: max(1, unchangedEnd - unchangedStart), height: 10)
                        .offset(x: unchangedStart, y: 2)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.70))
                        .frame(width: 1, height: 14)
                        .offset(x: center)
                    if let deltaDB {
                        Image(systemName: noiseDeltaMarkerSymbol(deltaDB, displayScale: displayScale))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(noiseDeltaColor(deltaDB))
                            .position(
                                x: max(6, min(proxy.size.width - 6, proxy.size.width * displayScale.ratio(for: deltaDB))),
                                y: 7
                            )
                    }
                }
            }
            .frame(height: 14)
            Text(formatNoiseDelta(deltaDB))
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 92, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)、原音比 \(formatNoiseDelta(deltaDB))")
    }

    private func correlationCard(stages: [AnalysisStageMetrics]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(
                title: "ステレオ相関",
                help: "左右の音がどれくらい同じ向きで鳴っているかを見る指標です。0より下はモノラル再生で音が痩せる可能性があります。"
            )
            Text("0未満はモノラル再生で音が痩せる可能性があります。0以上は左右の音が同じ向きに近い状態です。")
                .font(.callout)
                .foregroundStyle(.secondary)

            if stages.isEmpty {
                Text("解析が完了するとステレオ相関を表示します。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(stages) { stage in
                    correlationRow(stage)
                }
                Divider()
                correlationTimelineSection(stages: stages)
            }
        }
        .analysisCard()
        .accessibilityElement(children: .contain)
    }

    private func correlationRow(_ stage: AnalysisStageMetrics) -> some View {
        let value = max(-1, min(1, stage.metrics.stereoCorrelation))
        let ratio = (value + 1) * 0.5
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(stage.label)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(String(format: "%+.2f", value))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(correlationColor(value: value, fallback: stage.color))
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.secondary.opacity(0.12))
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.red.opacity(0.10))
                        Rectangle()
                            .fill(stage.color.opacity(0.12))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: proxy.size.width * 0.5)
                    Capsule()
                        .fill(correlationColor(value: value, fallback: stage.color))
                        .frame(width: 12, height: 22)
                        .offset(x: max(0, min(proxy.size.width - 12, proxy.size.width * ratio - 6)))
                }
            }
            .frame(height: 22)
            HStack {
                Text("-1 逆相")
                Spacer()
                Text("0 注意")
                Spacer()
                Text("+1 同相")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stage.label)のステレオ相関")
        .accessibilityValue(String(format: "%+.2f。-1は逆相、0は注意、+1は同相です。", value))
    }

    private func correlationTimelineSection(stages: [AnalysisStageMetrics]) -> some View {
        let points = correlationTimelinePoints(stages: stages)
        let maxTime = max(1, ceil(correlationTimelineDuration(stages: stages)))
        return VStack(alignment: .leading, spacing: 8) {
            Text("時間ごとの相関推移")
                .font(.callout.weight(.semibold))
            Text("0未満の時間帯は、モノラル再生で音が痩せる可能性があります。無音区間は相関値として計算せず、線を区切ります。")
                .font(.callout)
                .foregroundStyle(.secondary)
            if points.isEmpty {
                Text(correlationTimelineUnavailableText(stages: stages))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
                    .velouraAdaptiveGlass(in: .rect(cornerRadius: 12))
            } else {
                correlationTimelineChart(points: points, maxTime: maxTime)
                    .accessibilityLabel("時間ごとのステレオ相関推移")
                if let note = correlationTimelinePartialNote(stages: stages) {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func correlationTimelineChart(points: [TimelinePoint], maxTime: Double) -> some View {
        Chart {
            RectangleMark(
                xStart: .value("開始", 0),
                xEnd: .value("終了", maxTime),
                yStart: .value("逆相", -1),
                yEnd: .value("注意", 0)
            )
            .foregroundStyle(Color.red.opacity(0.08))
            RuleMark(y: .value("注意ライン", 0))
                .foregroundStyle(Color.red.opacity(0.55))
                .lineStyle(.init(lineWidth: 1.5))
            ForEach(points) { point in
                LineMark(
                    x: .value("時間", point.time),
                    y: .value("相関", point.value),
                    series: .value("区間", point.lineGroup)
                )
                .foregroundStyle(by: .value("音源", point.series))
                .interpolationMethod(.catmullRom)
                .lineStyle(.init(lineWidth: 2.5))
            }
        }
        .chartForegroundStyleScale(stageColorScale)
        .chartLegend(position: .bottom)
        .chartXScale(domain: 0 ... maxTime)
        .chartYScale(domain: -1 ... 1)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(String(format: "%.0fs", seconds))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [-1, 0, 1]) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let correlation = value.as(Double.self) {
                        Text(correlationAxisLabel(correlation))
                    }
                }
            }
        }
        .frame(height: 220)
        .graphHoverOverlay { time, _ in
            timelineHoverReadout(
                points: points,
                time: time,
                restrictsToLineSegments: true,
                valueFormatter: { String(format: "%+.2f", $0) }
            )
        }
    }

    private func correlationTimelineDuration(stages: [AnalysisStageMetrics]) -> Double {
        let analyzedDurations = stages.map(\.metrics.duration).filter { $0 > 0 }
        if let duration = analyzedDurations.max() {
            return duration
        }
        return correlationTimelinePoints(stages: stages).map(\.time).max() ?? 1
    }

    private func shortTermLoudnessChart(stages: [AnalysisStageMetrics]) -> some View {
        let points = timelinePoints(stages: stages) { $0.shortTermLoudness.map { ($0.time, $0.levelDB) } }
        let domain = paddedDomain(values: points.map(\.value), fallback: -36 ... -12, step: 2)
        return timelineChart(points: points, yDomain: domain, valueLabel: "LUFS")
            .accessibilityLabel("短時間ラウドネス推移")
    }

    private func dynamicsChart(stages: [AnalysisStageMetrics]) -> some View {
        let points = timelinePoints(stages: stages) { $0.dynamics.map { ($0.time, $0.crestFactorDB) } }
        let domain = paddedDomain(values: points.map(\.value), fallback: 0 ... 18, step: 2)
        return timelineChart(points: points, yDomain: domain, valueLabel: "dB")
            .accessibilityLabel("ダイナミクス推移")
    }

    private func timelineChart(points: [TimelinePoint], yDomain: ClosedRange<Double>, valueLabel: String) -> some View {
        Chart(points) { point in
            LineMark(
                x: .value("時間", point.time),
                y: .value(valueLabel, point.value)
            )
            .foregroundStyle(by: .value("音源", point.series))
            .interpolationMethod(.catmullRom)
            .lineStyle(.init(lineWidth: 2.5))
        }
        .chartForegroundStyleScale(stageColorScale)
        .chartLegend(position: .bottom)
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisTick()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(String(format: "%.0fs", seconds))
                    }
                }
            }
        }
        .frame(height: 250)
        .graphHoverOverlay { time, _ in
            timelineHoverReadout(
                points: points,
                time: time,
                valueFormatter: { String(format: "%.1f %@", $0, valueLabel) }
            )
        }
    }

    private func spectrumComparisonCharts(stages: [AnalysisStageMetrics]) -> some View {
        let points = spectrumPoints(stages: stages)
        let delta = spectrumDeltaPoints()
        let spectrumDomain = paddedDomain(values: points.map(\.levelDB), fallback: -80 ... 0, step: 3)
        let deltaDomain = paddedSymmetricDomain(values: delta.map(\.deltaDB), fallback: -6 ... 6)
        return VStack(alignment: .leading, spacing: 12) {
            Chart {
                RectangleMark(
                    xStart: .value("注目帯域開始", 8_000),
                    xEnd: .value("注目帯域終了", 12_000),
                    yStart: .value("下限", spectrumDomain.lowerBound),
                    yEnd: .value("上限", spectrumDomain.upperBound)
                )
                .foregroundStyle(Color.orange.opacity(0.07))
                ForEach(points) { point in
                    LineMark(
                        x: .value("周波数", point.frequencyHz),
                        y: .value("相対dB", point.levelDB)
                    )
                    .foregroundStyle(by: .value("音源", point.series))
                    .interpolationMethod(.catmullRom)
                    .lineStyle(.init(lineWidth: 2.4))
                }
            }
            .chartForegroundStyleScale(stageColorScale)
            .chartXScale(domain: 80 ... 20_000, type: .log)
            .chartYScale(domain: spectrumDomain)
            .chartXAxis { spectrumAxisMarks() }
            .frame(height: 220)
            .accessibilityLabel("平均スペクトル比較")
            .graphHoverOverlay { frequency, _ in
                spectrumHoverReadout(points: points, frequency: frequency)
            }

            if !delta.isEmpty {
                Chart {
                    RuleMark(y: .value("基準", 0))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                    ForEach(delta) { point in
                        LineMark(
                            x: .value("周波数", point.frequencyHz),
                            y: .value("差分dB", point.deltaDB)
                        )
                        .foregroundStyle(by: .value("差分", point.series))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(.init(lineWidth: 2.2, dash: [6, 4]))
                    }
                }
                .chartForegroundStyleScale([
                    "\(presentation.correctedTitle) - 入力": Color.green,
                    "最終版 - \(presentation.correctedTitle)": Color.orange
                ])
                .chartXScale(domain: 80 ... 20_000, type: .log)
                .chartYScale(domain: deltaDomain)
                .chartXAxis { spectrumAxisMarks() }
                .frame(height: 160)
                .accessibilityLabel("平均スペクトル差分")
            }
        }
    }

    private func timelineHoverReadout(
        points: [TimelinePoint],
        time: Double,
        restrictsToLineSegments: Bool = false,
        valueFormatter: (Double) -> String
    ) -> GraphHoverReadout? {
        let values = ["入力", presentation.correctedTitle, "最終版"].compactMap { series -> GraphHoverValue? in
            let seriesPoints = points.filter { $0.series == series }
            let eligiblePoints: [TimelinePoint]
            if restrictsToLineSegments {
                let segments = Dictionary(grouping: seriesPoints, by: \TimelinePoint.lineGroup)
                guard let segment = segments.values.first(where: { segment in
                    guard let start = segment.map(\.time).min(), let end = segment.map(\.time).max() else {
                        return false
                    }
                    return start <= time && time <= end
                }) else { return nil }
                eligiblePoints = segment
            } else {
                eligiblePoints = seriesPoints
            }
            guard let point = eligiblePoints.min(by: { abs($0.time - time) < abs($1.time - time) }) else {
                return nil
            }
            return GraphHoverValue(
                label: series,
                value: valueFormatter(point.value),
                color: stageColor(for: series)
            )
        }
        guard !values.isEmpty else { return nil }
        return GraphHoverReadout(
            axisLabel: String(format: "%.1fs", time),
            values: values
        )
    }

    private func spectrumHoverReadout(
        points: [SpectrumPoint],
        frequency: Double
    ) -> GraphHoverReadout? {
        let values = ["入力", presentation.correctedTitle, "最終版"].compactMap { series -> GraphHoverValue? in
            guard let point = points.lazy
                .filter({ $0.series == series })
                .min(by: { logarithmicDistance($0.frequencyHz, frequency) < logarithmicDistance($1.frequencyHz, frequency) })
            else { return nil }
            return GraphHoverValue(
                label: series,
                value: String(format: "%.1f dB", point.levelDB),
                color: stageColor(for: series)
            )
        }
        guard !values.isEmpty else { return nil }
        return GraphHoverReadout(axisLabel: frequencyReadout(frequency), values: values)
    }

    private func logarithmicDistance(_ lhs: Double, _ rhs: Double) -> Double {
        abs(log(max(lhs, 1)) - log(max(rhs, 1)))
    }

    private func frequencyReadout(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            return String(format: "%.1f kHz", frequency / 1_000)
        }
        return String(format: "%.0f Hz", frequency)
    }

    private func stageColor(for series: String) -> Color {
        if series == "入力" { return .blue }
        if series == presentation.correctedTitle { return .green }
        if series == "最終版" { return .orange }
        return .secondary
    }

    private func bandDetailRows(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> some View {
        let correctedMap = Dictionary(uniqueKeysWithValues: (corrected?.bandEnergies ?? []).map { ($0.id, $0.levelDB) })
        let masteredMap = Dictionary(uniqueKeysWithValues: (mastered?.bandEnergies ?? []).map { ($0.id, $0.levelDB) })
        let rows = input.bandEnergies.map { band in
            let comparison = FrequencyBandDisplayComparison(
                input: band.levelDB,
                corrected: correctedMap[band.id],
                mastered: masteredMap[band.id]
            )
            return BandDetailRow(
                id: band.id,
                definition: termDefinition(for: band.id),
                range: band.rangeDescription,
                input: comparison.input,
                corrected: comparison.corrected,
                mastered: comparison.mastered,
                correctionDelta: comparison.correctionDelta,
                masteringDelta: comparison.masteringDelta,
                masteredDeltaFromInput: comparison.masteredDeltaFromInput
            )
        }
        return VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                bandDetailRow(row)
            }
        }
    }

    private func bandDetailRow(_ row: BandDetailRow) -> some View {
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                termLabel(row.definition)
                Text(row.range)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            bandStageFlow(row)
            bandInputRelativeDeltaComparison(row)
        }
        .padding(10)
        .velouraAdaptiveGlass(in: .rect(cornerRadius: 12))
    }

    private func bandStageFlow(_ row: BandDetailRow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            bandStageValue(title: "入力", value: row.input, tint: .blue)
            bandStageTransition(deltaDB: row.correctionDelta)
            bandStageValue(title: presentation.correctedTitle, value: row.corrected, tint: .green)
            bandStageTransition(deltaDB: row.masteringDelta)
            bandStageValue(title: "最終版", value: row.mastered, tint: .orange)
        }
    }

    private func bandStageValue(title: String, value: Double?, tint: Color) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(value.map { formatValue($0, format: .dB) } ?? "--")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(value == nil ? Color.secondary : tint)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityElement(children: .combine)
    }

    private func bandStageTransition(deltaDB: Double?) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)
            Text(formatBandDelta(deltaDB))
                .font(.callout.monospacedDigit().weight(.semibold))
            Text(bandDeltaDirectionText(deltaDB))
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 104)
        .accessibilityElement(children: .combine)
    }

    private func bandInputRelativeDeltaComparison(_ row: BandDetailRow) -> some View {
        let displayScale = InputRelativeDeltaScale.fitting(
            [row.correctionDelta, row.masteredDeltaFromInput].compactMap { $0 }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text("入力を基準にした差分")
                .font(.callout.weight(.semibold))
            HStack(spacing: 8) {
                Color.clear.frame(width: 112, height: 1)
                HStack(spacing: 8) {
                    Text("帯域減少 \(formatBandDelta(-displayScale.maximumMagnitudeDB))")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                    Text("入力 0.00 dB")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                    Text("帯域増加 \(formatBandDelta(displayScale.maximumMagnitudeDB))")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                Color.clear.frame(width: 92, height: 1)
            }
            bandInputRelativeDeltaTrack(
                title: presentation.correctedTitle,
                deltaDB: row.correctionDelta,
                displayScale: displayScale,
                tint: .green
            )
            bandInputRelativeDeltaTrack(
                title: "最終版",
                deltaDB: row.masteredDeltaFromInput,
                displayScale: displayScale,
                tint: .orange
            )
            Text("中央の帯は入力との差が±1.00 dB以内です。表示範囲は補正後と最終版の差に合わせて帯域ごとに調整します。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func bandInputRelativeDeltaTrack(
        title: String,
        deltaDB: Double?,
        displayScale: InputRelativeDeltaScale,
        tint: Color
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .frame(width: 112, alignment: .leading)
            GeometryReader { proxy in
                let unchangedStart = proxy.size.width * displayScale.ratio(for: -displayScale.unchangedThresholdDB)
                let unchangedEnd = proxy.size.width * displayScale.ratio(for: displayScale.unchangedThresholdDB)
                let center = proxy.size.width * displayScale.ratio(for: 0)
                ZStack(alignment: .topLeading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.10))
                        .frame(height: 10)
                        .offset(y: 2)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentColor.opacity(0.14))
                        .frame(width: max(1, unchangedEnd - unchangedStart), height: 10)
                        .offset(x: unchangedStart, y: 2)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.70))
                        .frame(width: 1, height: 14)
                        .offset(x: center)
                    if let deltaDB {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tint)
                            .position(
                                x: max(6, min(proxy.size.width - 6, proxy.size.width * displayScale.ratio(for: deltaDB))),
                                y: 7
                            )
                    }
                }
            }
            .frame(height: 14)
            Text(formatBandDelta(deltaDB))
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 92, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)、入力比 \(formatBandDelta(deltaDB))")
    }

    private func unavailableCard(title: String, description: String) -> some View {
        ContentUnavailableView(title, systemImage: "chart.bar.doc.horizontal", description: Text(description))
            .frame(maxWidth: .infinity, minHeight: 180)
            .analysisCard()
    }

    private func analysisDisclosureSection<Content: View>(
        title: String,
        help: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                analysisDisclosureButton(title: title, isExpanded: isExpanded)
                sectionLabel(title: title, help: help)
            }

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity)
            }
        }
    }

    private func analysisDisclosureButton(title: String, isExpanded: Binding<Bool>) -> some View {
        DisclosureToggleButton(
            title: title,
            isExpanded: isExpanded.wrappedValue,
            accessibilityHint: "解析項目を開閉します"
        ) {
            LiquidGlassMotion.perform(
                reduceMotion: reduceMotion,
                animation: LiquidGlassMotion.panel
            ) {
                isExpanded.wrappedValue.toggle()
            }
        }
    }

    private func sectionLabel(title: String, help: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
            TermHelpButton(title: title, reading: title, description: help)
        }
    }

    private func termLabel(_ definition: TermDefinition) -> some View {
        HStack(spacing: 5) {
            Text(definition.label)
                .font(.callout.weight(.semibold))
            TermHelpButton(title: definition.label, reading: definition.reading, description: definition.description)
        }
    }

    private var noiseReport: NoiseCheckReport? {
        presentation.noiseReport
    }

    private var processingDeltaTitle: String {
        presentation.correctedTitle == "補正後" ? "補正差分" : "処理差分"
    }

    private var comparisonStages: [AnalysisStageMetrics] {
        var stages: [AnalysisStageMetrics] = []
        if let metrics = presentation.inputMetrics {
            stages.append(AnalysisStageMetrics(id: "input", label: "入力", color: .blue, metrics: metrics))
        }
        if let metrics = presentation.correctedMetrics {
            stages.append(
                AnalysisStageMetrics(
                    id: "corrected",
                    label: presentation.correctedTitle,
                    color: .green,
                    metrics: metrics
                )
            )
        }
        if let metrics = presentation.masteredMetrics {
            stages.append(AnalysisStageMetrics(id: "mastered", label: "最終版", color: .orange, metrics: metrics))
        }
        return stages
    }

    private var stageColorScale: KeyValuePairs<String, Color> {
        ["入力": .blue, presentation.correctedTitle: .green, "最終版": .orange]
    }

    private func metricRows(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> [MetricComparisonRow] {
        let mainRows: [MetricComparisonRow] = [
            metricRow(term: .loudness, input: input.integratedLoudnessLUFS, corrected: corrected?.integratedLoudnessLUFS, mastered: mastered?.integratedLoudnessLUFS, valueFormat: .lufs, deltaFormat: .luDelta),
            metricRow(term: .truePeak, input: input.truePeakDBFS, corrected: corrected?.truePeakDBFS, mastered: mastered?.truePeakDBFS, valueFormat: .dBTP, deltaFormat: .dBDelta),
            metricRow(term: .stereoWidth, input: input.stereoWidth, corrected: corrected?.stereoWidth, mastered: mastered?.stereoWidth, valueFormat: .ratio(2), deltaFormat: .ratioDelta(2)),
            metricRow(term: .harshness, input: input.harshnessScore, corrected: corrected?.harshnessScore, mastered: mastered?.harshnessScore, valueFormat: .score(2), deltaFormat: .scoreDelta(2)),
            metricRow(term: .crest, input: input.crestFactorDB, corrected: corrected?.crestFactorDB, mastered: mastered?.crestFactorDB, valueFormat: .dB, deltaFormat: .dBDelta),
            metricRow(term: .lra, input: input.loudnessRangeLU, corrected: corrected?.loudnessRangeLU, mastered: mastered?.loudnessRangeLU, valueFormat: .lu, deltaFormat: .luDelta)
        ]

        let correctedMap = Dictionary(uniqueKeysWithValues: (corrected?.bandEnergies ?? []).map { ($0.id, $0.levelDB) })
        let masteredMap = Dictionary(uniqueKeysWithValues: (mastered?.bandEnergies ?? []).map { ($0.id, $0.levelDB) })
        let bandRows = input.bandEnergies.map { band in
            MetricComparisonRow(
                definition: termDefinition(for: band.id),
                input: band.levelDB,
                corrected: correctedMap[band.id],
                mastered: masteredMap[band.id],
                correctionDelta: corrected.flatMap {
                    AudioQualityAssessmentService.normalizedBandDelta(
                        id: band.id,
                        reference: input,
                        target: $0
                    )
                },
                masteringDelta: {
                    guard let corrected, let mastered else { return nil }
                    return AudioQualityAssessmentService.normalizedBandDelta(
                        id: band.id,
                        reference: corrected,
                        target: mastered
                    )
                }(),
                valueFormat: .dB,
                deltaFormat: .dBDelta
            )
        }

        return mainRows + bandRows
    }

    private func metricRow(
        term: TermDefinition,
        input: Double?,
        corrected: Double?,
        mastered: Double?,
        valueFormat: MetricFormat,
        deltaFormat: MetricFormat
    ) -> MetricComparisonRow {
        let correctionDelta = {
            guard let input, let corrected else { return Optional<Double>.none }
            return corrected - input
        }()
        let masteringDelta = {
            guard let corrected, let mastered else { return Optional<Double>.none }
            return mastered - corrected
        }()
        return MetricComparisonRow(
            definition: term,
            input: input,
            corrected: corrected,
            mastered: mastered,
            correctionDelta: correctionDelta,
            masteringDelta: masteringDelta,
            valueFormat: valueFormat,
            deltaFormat: deltaFormat
        )
    }

    private func metrics(for target: DisplayAnalysisTarget) -> AudioMetricSnapshot? {
        presentation.metrics(for: target)
    }

    private func title(for target: DisplayAnalysisTarget) -> String {
        switch target {
        case .input: "入力"
        case .corrected: presentation.correctedTitle
        case .mastered: "最終版"
        }
    }

    private func timelinePoints(
        stages: [AnalysisStageMetrics],
        values: (AudioMetricSnapshot) -> [(Double, Double)]
    ) -> [TimelinePoint] {
        stages.flatMap { stage in
            values(stage.metrics).enumerated().map { index, value in
                TimelinePoint(
                    id: "\(stage.id)-\(index)",
                    time: value.0,
                    series: stage.label,
                    lineGroup: stage.id,
                    value: value.1
                )
            }
        }
    }

    private func correlationTimelinePoints(stages: [AnalysisStageMetrics]) -> [TimelinePoint] {
        stages.flatMap { stage in
            let metrics = stage.metrics.stereoCorrelationTimeline
            let step = correlationTimelineStep(metrics)
            var segment = 0
            var previousTime: Double?
            return metrics.map { metric in
                if let previousTime, metric.time - previousTime > step * 1.5 {
                    segment += 1
                }
                previousTime = metric.time
                return TimelinePoint(
                    id: "\(stage.id)-\(metric.id)",
                    time: metric.time,
                    series: stage.label,
                    lineGroup: "\(stage.id)-segment-\(segment)",
                    value: metric.value
                )
            }
        }
    }

    private func correlationTimelineStep(_ metrics: [TimedCorrelationMetric]) -> Double {
        let deltas = zip(metrics, metrics.dropFirst()).map { $1.time - $0.time }.filter { $0 > 0 }
        return deltas.min() ?? 0.5
    }

    private func correlationTimelineUnavailableText(stages: [AnalysisStageMetrics]) -> String {
        if stages.allSatisfy({ $0.metrics.stereoCorrelationTimelineStatus == .mono }) {
            return "モノラル音源のため、ステレオ相関推移はありません。"
        }
        if stages.allSatisfy({ $0.metrics.stereoCorrelationTimelineStatus == .silent }) {
            return "音が入っているステレオ区間がないため、ステレオ相関推移はありません。"
        }
        return "ステレオ音源の解析が完了すると、時間ごとの相関推移を表示します。"
    }

    private func correlationTimelinePartialNote(stages: [AnalysisStageMetrics]) -> String? {
        let missing = stages.compactMap { stage -> String? in
            guard stage.metrics.stereoCorrelationTimeline.isEmpty else { return nil }
            switch stage.metrics.stereoCorrelationTimelineStatus {
            case .mono:
                return "\(stage.label): モノラル音源のため表示しません"
            case .silent:
                return "\(stage.label): 音が入っているステレオ区間がないため表示しません"
            case .unavailable:
                return "\(stage.label): ステレオ相関推移は未解析です"
            case .available:
                return nil
            }
        }
        guard !missing.isEmpty else { return nil }
        return missing.joined(separator: " / ")
    }

    private func correlationAxisLabel(_ value: Double) -> String {
        if value <= -1 { return "-1 逆相" }
        if value >= 1 { return "+1 同相" }
        return "0 注意"
    }

    private func spectrumPoints(stages: [AnalysisStageMetrics]) -> [SpectrumPoint] {
        stages.flatMap { stage in
            stage.metrics.averageSpectrum.map {
                SpectrumPoint(id: "\(stage.id)-\($0.id)", frequencyHz: $0.frequencyHz, series: stage.label, levelDB: $0.levelDB)
            }
        }
    }

    private func spectrumDeltaPoints() -> [SpectrumDeltaPoint] {
        var points: [SpectrumDeltaPoint] = []
        if let input = presentation.inputMetrics,
           let corrected = presentation.correctedMetrics {
            let correctedMap = Dictionary(uniqueKeysWithValues: corrected.averageSpectrum.map { ($0.id, $0) })
            points += input.averageSpectrum.compactMap {
                guard let correctedPoint = correctedMap[$0.id] else { return nil }
                return SpectrumDeltaPoint(
                    id: "corrected-input-\($0.id)",
                    frequencyHz: $0.frequencyHz,
                    series: "\(presentation.correctedTitle) - 入力",
                    deltaDB: correctedPoint.levelDB - $0.levelDB
                )
            }
        }
        if let corrected = presentation.correctedMetrics,
           let mastered = presentation.masteredMetrics {
            let masteredMap = Dictionary(uniqueKeysWithValues: mastered.averageSpectrum.map { ($0.id, $0) })
            points += corrected.averageSpectrum.compactMap {
                guard let masteredPoint = masteredMap[$0.id] else { return nil }
                return SpectrumDeltaPoint(
                    id: "mastered-corrected-\($0.id)",
                    frequencyHz: $0.frequencyHz,
                    series: "最終版 - \(presentation.correctedTitle)",
                    deltaDB: masteredPoint.levelDB - $0.levelDB
                )
            }
        }
        return points
    }

    private func spectrumAxisMarks() -> some AxisContent {
        AxisMarks(values: [100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000]) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let frequency = value.as(Double.self) {
                    Text(frequency >= 1_000 ? "\(Int(frequency / 1_000))k" : "\(Int(frequency))")
                }
            }
        }
    }

    private func paddedDomain(values: [Double], fallback: ClosedRange<Double>, step: Double) -> ClosedRange<Double> {
        guard let minValue = values.min(), let maxValue = values.max() else { return fallback }
        let lower = floor(minValue / step) * step - step * 0.5
        let upper = ceil(maxValue / step) * step + step * 0.5
        return lower ... max(upper, lower + step)
    }

    private func paddedSymmetricDomain(values: [Double], fallback: ClosedRange<Double>) -> ClosedRange<Double> {
        guard let maxMagnitude = values.map({ abs($0) }).max() else { return fallback }
        let bound = max(1, ceil(maxMagnitude * 1.2))
        return -bound ... bound
    }

    private func correlationColor(value: Double, fallback: Color) -> Color {
        if value < 0 { return .red }
        if value < 0.25 { return .orange }
        return fallback
    }

    private func noiseSeverityColor(_ severity: NoiseCheckSeverity) -> Color {
        switch severity {
        case .low: .secondary
        case .caution: .orange
        case .warning: .red
        }
    }

    private func noiseOriginalComparisonStatus(_ row: NoiseCheckRow) -> String {
        guard let deltaDB = row.latestDeltaFromInputDB else { return row.summaryText }
        if deltaDB >= noiseDeltaScale.unchangedThresholdDB {
            return "ノイズが増加"
        }
        if deltaDB <= -noiseDeltaScale.maximumMagnitudeDB {
            return "ノイズが大きく減少"
        }
        if deltaDB <= -noiseDeltaScale.unchangedThresholdDB {
            return "ノイズが減少"
        }
        return "原音とほぼ同じ"
    }

    private func noiseOriginalComparisonReason(_ row: NoiseCheckRow) -> String {
        guard let deltaDB = row.latestDeltaFromInputDB else { return "原音との比較待ち" }
        let currentLevel = noiseCurrentLevelText(row.severity)
        if abs(deltaDB) < noiseDeltaScale.unchangedThresholdDB {
            return "原音比 \(formatNoiseDelta(deltaDB))・±1.0 dB以内・現在は\(currentLevel)"
        }
        return "原音比 \(formatNoiseDelta(deltaDB))・現在は\(currentLevel)"
    }

    private func noiseOriginalComparisonColor(_ row: NoiseCheckRow) -> Color {
        guard let deltaDB = row.latestDeltaFromInputDB else { return noiseSeverityColor(row.severity) }
        return noiseDeltaColor(deltaDB)
    }

    private func noiseDeltaColor(_ deltaDB: Double) -> Color {
        if deltaDB >= noiseDeltaScale.unchangedThresholdDB { return .red }
        if deltaDB <= -noiseDeltaScale.unchangedThresholdDB { return .green }
        return .secondary
    }

    private func noiseCurrentLevelText(_ severity: NoiseCheckSeverity) -> String {
        switch severity {
        case .low: "目立つ問題なし"
        case .caution: "少し目立つ"
        case .warning: "目立つ"
        }
    }

    private func noiseDeltaDirectionText(_ deltaDB: Double?) -> String {
        guard let deltaDB else { return "比較待ち" }
        if abs(deltaDB) < 0.05 { return "変化なし" }
        return deltaDB > 0 ? "ノイズ増加" : "ノイズ減少"
    }

    private func bandDeltaDirectionText(_ deltaDB: Double?) -> String {
        guard let deltaDB else { return "比較待ち" }
        if abs(deltaDB) < 0.005 { return "変化なし" }
        return deltaDB > 0 ? "帯域増加" : "帯域減少"
    }

    private func formatBandDelta(_ deltaDB: Double?) -> String {
        guard let deltaDB else { return "--" }
        if abs(deltaDB) < 0.005 { return "±0.00 dB" }
        return formatValue(deltaDB, format: .dBDelta)
    }

    private func noiseDeltaMarkerSymbol(
        _ deltaDB: Double,
        displayScale: InputRelativeDeltaScale
    ) -> String {
        if deltaDB <= -displayScale.maximumMagnitudeDB {
            return "arrowtriangle.left.fill"
        }
        if deltaDB >= displayScale.maximumMagnitudeDB {
            return "arrowtriangle.right.fill"
        }
        return "circle.fill"
    }

    private func formatNoiseDelta(_ deltaDB: Double?) -> String {
        guard let deltaDB else { return "--" }
        if abs(deltaDB) < 0.05 { return "±0.0 dB" }
        return String(format: deltaDB > 0 ? "+%.1f dB" : "%.1f dB", deltaDB)
    }

    private func formatNoiseValue(_ value: NoiseCheckValue) -> String {
        String(format: "%.1f %@", value.levelDB, value.unitLabel)
    }

    private func formatValue(_ value: Double, format: MetricFormat) -> String {
        switch format {
        case .dBTP:
            String(format: "%.2f dBTP", value)
        case .dB:
            String(format: "%.2f dB", value)
        case .dBDelta:
            String(format: value >= 0 ? "+%.2f dB" : "%.2f dB", value)
        case .lu:
            String(format: "%.2f LU", value)
        case .luDelta:
            String(format: value >= 0 ? "+%.2f LU" : "%.2f LU", value)
        case .lufs:
            String(format: "%.1f LUFS", value)
        case .ratio(let decimals), .score(let decimals):
            String(format: "%.\(decimals)f", value)
        case .ratioDelta(let decimals), .scoreDelta(let decimals):
            String(format: value >= 0 ? "+%.\(decimals)f" : "%.\(decimals)f", value)
        }
    }

    private func termDefinition(for id: String) -> TermDefinition {
        termDefinitions[id] ?? TermDefinition(id: id, label: id, reading: id, description: "")
    }

    private var termDefinitions: [String: TermDefinition] {
        Dictionary(uniqueKeysWithValues: [
            .loudness,
            .truePeak,
            .stereoWidth,
            .harshness,
            .crest,
            .lra,
            .rumble,
            .warmth,
            .mud,
            .core,
            .presence,
            .sparkle,
            .air,
            .ultraAir,
            .generatedUltraHigh
        ].map { ($0.id, $0) })
    }
}

extension View {
    func analysisCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.clear)
                    .velouraAdaptiveGlass(in: .rect(cornerRadius: 16))
                    .allowsHitTesting(false)
            }
    }

    func analysisTableLabelCell(minWidth: CGFloat = 152) -> some View {
        self
            .font(.callout.weight(.semibold))
            .frame(minWidth: minWidth, alignment: .leading)
    }

    func analysisTableNumericColumn(minWidth: CGFloat = 104) -> some View {
        self
            .frame(minWidth: minWidth, alignment: .trailing)
    }

    func analysisTableTextColumn(minWidth: CGFloat = 120) -> some View {
        self
            .frame(minWidth: minWidth, alignment: .leading)
    }
}

private extension DisplayAnalysisPresentationState {
    var color: Color {
        switch self {
        case .notSelected: .secondary
        case .idle: .secondary
        case .running: .blue
        case .completed: .green
        case .failed: .red
        }
    }
}

private struct AnalysisStageMetrics: Identifiable {
    let id: String
    let label: String
    let color: Color
    let metrics: AudioMetricSnapshot
}

private struct MetricComparisonRow: Identifiable {
    let definition: TermDefinition
    let input: Double?
    let corrected: Double?
    let mastered: Double?
    let correctionDelta: Double?
    let masteringDelta: Double?
    let valueFormat: MetricFormat
    let deltaFormat: MetricFormat

    var id: String { definition.id }
}

private struct BandDetailRow: Identifiable {
    let id: String
    let definition: TermDefinition
    let range: String
    let input: Double
    let corrected: Double?
    let mastered: Double?
    let correctionDelta: Double?
    let masteringDelta: Double?
    let masteredDeltaFromInput: Double?
}

private struct TimelinePoint: Identifiable {
    let id: String
    let time: Double
    let series: String
    let lineGroup: String
    let value: Double
}

private struct SpectrumPoint: Identifiable {
    let id: String
    let frequencyHz: Double
    let series: String
    let levelDB: Double
}

private struct SpectrumDeltaPoint: Identifiable {
    let id: String
    let frequencyHz: Double
    let series: String
    let deltaDB: Double
}

private struct TermDefinition: Identifiable {
    let id: String
    let label: String
    let reading: String
    let description: String

    static let loudness = TermDefinition(id: "loudness", label: "音量", reading: "おんりょう", description: "曲全体の平均的な大きさです。LUFSで表示します。")
    static let truePeak = TermDefinition(id: "truePeak", label: "True Peak", reading: "とぅるーぴーく", description: "書き出しや再生で歪む可能性を見る最大ピークです。dBTPで表示します。")
    static let stereoWidth = TermDefinition(id: "stereoWidth", label: "ステレオ幅", reading: "すてれおはば", description: "左右への広がり具合です。")
    static let harshness = TermDefinition(id: "harshness", label: "ハーシュネス", reading: "はーしゅねす", description: "高域の耳障りさの指標です。")
    static let crest = TermDefinition(id: "crest", label: "Crest", reading: "くれすと", description: "瞬間的なピークと平均音量の差です。")
    static let lra = TermDefinition(id: "lra", label: "LRA", reading: "えるあーるえー", description: "曲全体の音量変化の幅です。")
    static let rumble = TermDefinition(id: "rumble", label: "低域ノイズ", reading: "ていいきのいず", description: "20Hzから150Hzの不要な低音のゴロゴロ感です。")
    static let warmth = TermDefinition(id: "warmth", label: "太さ", reading: "ふとさ", description: "150Hzから300Hzの音の厚みです。")
    static let mud = TermDefinition(id: "mud", label: "こもり", reading: "こもり", description: "300Hzから1kHzの暗さやこもりに関わる帯域です。")
    static let core = TermDefinition(id: "core", label: "声の芯", reading: "こえのしん", description: "1kHzから4kHzの声や主旋律の中心です。")
    static let presence = TermDefinition(id: "presence", label: "刺さり", reading: "ささり", description: "4kHzから8kHzの明瞭さ、サ行、耳に痛い成分です。")
    static let sparkle = TermDefinition(id: "sparkle", label: "煌びやかさ", reading: "きらびやかさ", description: "8kHzから12kHzの抜け感やきらめきです。")
    static let air = TermDefinition(id: "air", label: "空気感", reading: "くうきかん", description: "12kHzから16kHzの息感や空気の伸びです。")
    static let ultraAir = TermDefinition(id: "ultraAir", label: "超高域", reading: "ちょうこういき", description: "16kHzから20kHzの高域の最上部です。")
    static let generatedUltraHigh = TermDefinition(id: "generatedUltraHigh", label: "生成超高域", reading: "せいせいちょうこういき", description: "21kHzから24kHzに新しく増えた成分を確認する帯域です。")
}

private enum MetricFormat {
    case dBTP
    case dB
    case dBDelta
    case lu
    case luDelta
    case lufs
    case ratio(Int)
    case ratioDelta(Int)
    case score(Int)
    case scoreDelta(Int)
}
