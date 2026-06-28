import Charts
import SwiftUI

struct DetailedAnalysisWorkspaceView: View {
    @Bindable var job: ProcessingJob
    @State private var showLoudness = false
    @State private var showDynamics = false
    @State private var showSpectrum = false
    @State private var showBands = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            analysisStateSummary

            if let input = job.inputMetrics {
                metricComparisonCard(input: input, corrected: job.outputMetrics, mastered: job.masteredMetrics)

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
                        help: "場面ごとの音量感です。入力、補正後、最終版を同じ基準で比べます。",
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
                        help: "8つの帯域を、入力、補正後、最終版、補正差分、マスタリング差分で確認します。",
                        isExpanded: $showBands
                    ) {
                        bandDetailRows(input: input, corrected: job.outputMetrics, mastered: job.masteredMetrics)
                    }
                    .analysisCard()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView(
                    "入力音声は未解析です",
                    systemImage: "waveform.path.ecg",
                    description: Text("音声を選ぶと、入力、補正後、最終版の詳細解析を表示します。")
                )
                .frame(maxWidth: .infinity, minHeight: 260)
                .analysisCard()
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("詳細解析")
                    .font(.title2.bold())
                TermHelpButton(
                    title: "詳細解析",
                    reading: "しょうさいかいせき",
                    description: "元からあった数値比較、ノイズ比較、周波数グラフ、ラウドネス推移、ダイナミクス推移、相関表示を、入力、補正後、最終版で見比べる画面です。"
                )
            }
            Text("右側インスペクタと下部ログへ同じ表を重複表示せず、中央で3音源の変化を確認します。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var analysisStateSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("解析状態")
                    .font(.headline)
                Spacer()
                if job.isAnalyzingDisplayAnalysis {
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

            if let statusText = job.displayAnalysisStatusText {
                Label(statusText, systemImage: "clock")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let failedText = job.failedDisplayAnalysisText {
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

    private func aggregateState(for target: DisplayAnalysisTarget) -> AnalysisVisualState {
        if job.isAnalyzingDisplayAnalysis(for: target) {
            return .running
        }
        if job.hasFailedDisplayAnalysis(for: target) {
            return .failed
        }
        if metrics(for: target) != nil {
            return .completed
        }
        return .idle
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
                help: "入力、補正後、最終版、補正差分、マスタリング差分を同じ表で見ます。差分は良し悪しではなく、何が変わったかを見るための値です。"
            )

            ViewThatFits(in: .horizontal) {
                wideMetricTable(rows)
                compactMetricList(rows)
            }
        }
        .analysisCard()
        .accessibilityElement(children: .contain)
    }

    private func wideMetricTable(_ rows: [MetricComparisonRow]) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                tableHeader("項目")
                tableHeader("入力")
                tableHeader("補正後")
                tableHeader("最終版")
                tableHeader("補正差分")
                tableHeader("マスタリング差分")
            }
            Divider().gridCellColumns(6)
            ForEach(rows) { row in
                GridRow {
                    termLabel(row.definition)
                    metricValue(row.input, format: row.valueFormat, tint: .blue)
                    metricValue(row.corrected, format: row.valueFormat, tint: .green)
                    metricValue(row.mastered, format: row.valueFormat, tint: .orange)
                    metricValue(row.correctionDelta, format: row.deltaFormat, tint: .primary)
                    metricValue(row.masteringDelta, format: row.deltaFormat, tint: .primary)
                }
            }
        }
    }

    private func compactMetricList(_ rows: [MetricComparisonRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 8) {
                    termLabel(row.definition)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], alignment: .leading, spacing: 8) {
                        valueChip(title: "入力", value: row.input, format: row.valueFormat, color: .blue)
                        valueChip(title: "補正後", value: row.corrected, format: row.valueFormat, color: .green)
                        valueChip(title: "最終版", value: row.mastered, format: row.valueFormat, color: .orange)
                        valueChip(title: "補正差分", value: row.correctionDelta, format: row.deltaFormat, color: .primary)
                        valueChip(title: "マスタリング差分", value: row.masteringDelta, format: row.deltaFormat, color: .primary)
                    }
                }
                .padding(10)
                .glassEffect(.clear, in: .rect(cornerRadius: 12))
            }
        }
    }

    private func valueChip(title: String, value: Double?, format: MetricFormat, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            metricValue(value, format: format, tint: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            HStack {
                sectionLabel(
                    title: "ノイズ7種類比較",
                    help: "ヒス、サ行、高域のチラつき、こもり、ハム、低域ゴロゴロ、環境音を、入力、補正後、最終版で比較します。"
                )
                Spacer()
                Text(noiseSeverityText(report.severity))
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(noiseSeverityColor(report.severity))
            }

            ForEach(report.rows) { row in
                noiseRow(row)
            }

            if !report.recommendedActions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("聴いて気になる場合の調整候補")
                        .font(.headline)
                    ForEach(report.recommendedActions) { action in
                        noiseActionRow(action)
                    }
                }
                .padding(.top, 4)
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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(row.displayDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(row.summaryText)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(noiseSeverityColor(row.severity))
            }

            noiseBarLine(title: "入力", value: row.input, row: row, tint: .blue)
            noiseBarLine(title: "補正後", value: row.corrected, row: row, tint: .green, detail: row.correctionEffectText)
            noiseBarLine(title: "最終版", value: row.mastered, row: row, tint: .orange, detail: row.masteringEffectText)
        }
        .padding(12)
        .glassEffect(.clear, in: .rect(cornerRadius: 12))
    }

    private func noiseBarLine(
        title: String,
        value: NoiseCheckValue?,
        row: NoiseCheckRow,
        tint: Color,
        detail: String? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.callout.weight(.semibold))
                .frame(width: 48, alignment: .leading)
            GeometryReader { proxy in
                let ratio = row.displayScale.ratio(for: value?.levelDB)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(value == nil ? 0.16 : 0.10))
                    if value != nil {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tint.opacity(0.72))
                            .frame(width: max(3, proxy.size.width * ratio))
                    }
                }
            }
            .frame(height: 10)
            Text(value.map { formatNoiseValue($0) } ?? "--")
                .font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 86, alignment: .trailing)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 132, alignment: .leading)
            }
        }
    }

    private func noiseActionRow(_ action: NoiseCheckAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(action.title)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(action.currentValue) -> \(action.recommendedValue)")
                    .font(.callout.monospacedDigit().weight(.semibold))
            }
            Text(action.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(action.caution)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .glassEffect(.clear, in: .rect(cornerRadius: 12))
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
                    .glassEffect(.clear, in: .rect(cornerRadius: 12))
            } else {
                correlationTimelineChart(points: points, maxTime: maxTime)
                    .frame(height: 220)
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
            .frame(height: 250)
            .accessibilityLabel("短時間ラウドネス推移")
    }

    private func dynamicsChart(stages: [AnalysisStageMetrics]) -> some View {
        let points = timelinePoints(stages: stages) { $0.dynamics.map { ($0.time, $0.crestFactorDB) } }
        let domain = paddedDomain(values: points.map(\.value), fallback: 0 ... 18, step: 2)
        return timelineChart(points: points, yDomain: domain, valueLabel: "dB")
            .frame(height: 250)
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
                    "補正後 - 入力": Color.green,
                    "最終版 - 補正後": Color.orange
                ])
                .chartXScale(domain: 80 ... 20_000, type: .log)
                .chartYScale(domain: deltaDomain)
                .chartXAxis { spectrumAxisMarks() }
                .frame(height: 160)
                .accessibilityLabel("平均スペクトル差分")
            }
        }
    }

    private func bandDetailRows(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?
    ) -> some View {
        let correctedMap = Dictionary(uniqueKeysWithValues: (corrected?.bandEnergies ?? []).map { ($0.id, $0.levelDB) })
        let masteredMap = Dictionary(uniqueKeysWithValues: (mastered?.bandEnergies ?? []).map { ($0.id, $0.levelDB) })
        let rows = input.bandEnergies.map {
            BandDetailRow(
                id: $0.id,
                definition: termDefinition(for: $0.id),
                range: $0.rangeDescription,
                input: $0.levelDB,
                corrected: correctedMap[$0.id],
                mastered: masteredMap[$0.id]
            )
        }
        let allValues = rows.flatMap { [$0.input, $0.corrected ?? $0.input, $0.mastered ?? $0.corrected ?? $0.input] }
        let minValue = (allValues.min() ?? -60) - 3
        let maxValue = (allValues.max() ?? 0) + 3

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(rows) { row in
                bandDetailRow(row, minValue: minValue, maxValue: maxValue)
            }
        }
    }

    private func bandDetailRow(_ row: BandDetailRow, minValue: Double, maxValue: Double) -> some View {
        let correctionDelta = row.corrected.map { $0 - row.input }
        let masteringDelta = {
            guard let corrected = row.corrected, let mastered = row.mastered else { return Optional<Double>.none }
            return mastered - corrected
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                termLabel(row.definition)
                Text(row.range)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("補正 \(correctionDelta.map { formatValue($0, format: .dBDelta) } ?? "--") / 仕上げ \(masteringDelta.map { formatValue($0, format: .dBDelta) } ?? "--")")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            bandBar(title: "入力", value: row.input, minValue: minValue, maxValue: maxValue, tint: .blue)
            bandBar(title: "補正後", value: row.corrected, minValue: minValue, maxValue: maxValue, tint: .green)
            bandBar(title: "最終版", value: row.mastered, minValue: minValue, maxValue: maxValue, tint: .orange)
        }
        .padding(10)
        .glassEffect(.clear, in: .rect(cornerRadius: 12))
    }

    private func bandBar(title: String, value: Double?, minValue: Double, maxValue: Double, tint: Color) -> some View {
        let ratio = value.map { max(0, min(1, ($0 - minValue) / max(maxValue - minValue, 1))) } ?? 0
        return HStack(spacing: 8) {
            Text(title)
                .font(.callout)
                .frame(width: 48, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.10))
                    if value != nil {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(tint.opacity(0.70))
                            .frame(width: proxy.size.width * ratio)
                    }
                }
            }
            .frame(height: 10)
            Text(value.map { formatValue($0, format: .dB) } ?? "--")
                .font(.callout.monospacedDigit())
                .frame(width: 74, alignment: .trailing)
        }
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
            }
        }
    }

    private func analysisDisclosureButton(title: String, isExpanded: Binding<Bool>) -> some View {
        Button {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            Image(systemName: isExpanded.wrappedValue ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded.wrappedValue ? "開いています" : "閉じています")
        .accessibilityHint("解析項目を開閉します")
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
        NoiseCheckReportService.makeReport(
            input: job.inputNoiseMeasurements,
            corrected: job.outputNoiseMeasurements,
            mastered: job.masteredNoiseMeasurements,
            correctionSettings: job.appliedCorrectionSettings ?? job.editableCorrectionSettings,
            settings: job.appliedMasteringSettings ?? job.editableMasteringSettings
        )
    }

    private var comparisonStages: [AnalysisStageMetrics] {
        var stages: [AnalysisStageMetrics] = []
        if let metrics = job.inputMetrics {
            stages.append(AnalysisStageMetrics(id: "input", label: "入力", color: .blue, metrics: metrics))
        }
        if let metrics = job.outputMetrics {
            stages.append(AnalysisStageMetrics(id: "corrected", label: "補正後", color: .green, metrics: metrics))
        }
        if let metrics = job.masteredMetrics {
            stages.append(AnalysisStageMetrics(id: "mastered", label: "最終版", color: .orange, metrics: metrics))
        }
        return stages
    }

    private var stageColorScale: KeyValuePairs<String, Color> {
        ["入力": .blue, "補正後": .green, "最終版": .orange]
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
        let bandRows = input.bandEnergies.map {
            metricRow(
                term: termDefinition(for: $0.id),
                input: $0.levelDB,
                corrected: correctedMap[$0.id],
                mastered: masteredMap[$0.id],
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
        switch target {
        case .input: job.inputMetrics
        case .corrected: job.outputMetrics
        case .mastered: job.masteredMetrics
        }
    }

    private func title(for target: DisplayAnalysisTarget) -> String {
        switch target {
        case .input: "入力"
        case .corrected: "補正後"
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
        if let input = job.inputMetrics, let corrected = job.outputMetrics {
            let correctedMap = Dictionary(uniqueKeysWithValues: corrected.averageSpectrum.map { ($0.id, $0) })
            points += input.averageSpectrum.compactMap {
                guard let correctedPoint = correctedMap[$0.id] else { return nil }
                return SpectrumDeltaPoint(id: "corrected-input-\($0.id)", frequencyHz: $0.frequencyHz, series: "補正後 - 入力", deltaDB: correctedPoint.levelDB - $0.levelDB)
            }
        }
        if let corrected = job.outputMetrics, let mastered = job.masteredMetrics {
            let masteredMap = Dictionary(uniqueKeysWithValues: mastered.averageSpectrum.map { ($0.id, $0) })
            points += corrected.averageSpectrum.compactMap {
                guard let masteredPoint = masteredMap[$0.id] else { return nil }
                return SpectrumDeltaPoint(id: "mastered-corrected-\($0.id)", frequencyHz: $0.frequencyHz, series: "最終版 - 補正後", deltaDB: masteredPoint.levelDB - $0.levelDB)
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

    private func noiseSeverityText(_ severity: NoiseCheckSeverity) -> String {
        switch severity {
        case .low: "確認"
        case .caution: "注意"
        case .warning: "警告"
        }
    }

    private func noiseSeverityColor(_ severity: NoiseCheckSeverity) -> Color {
        switch severity {
        case .low: .secondary
        case .caution: .orange
        case .warning: .red
        }
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
            .ultraAir
        ].map { ($0.id, $0) })
    }
}

private extension View {
    func analysisCard() -> some View {
        self
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .glassEffect(.clear, in: .rect(cornerRadius: 16))
    }
}

private enum AnalysisVisualState {
    case idle
    case running
    case completed
    case failed

    var title: String {
        switch self {
        case .idle: "未解析"
        case .running: "解析中"
        case .completed: "完了"
        case .failed: "失敗"
        }
    }

    var color: Color {
        switch self {
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
