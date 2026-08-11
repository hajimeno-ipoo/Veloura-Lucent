import SwiftUI
import Charts

struct CompletionReportPopoverView: View {
    let report: CompletionReport

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                CompletionReportHeaderView(report: report)
                CompletionReportSummaryView(paragraphs: report.summary)
                CompletionReportComparisonView(report: report)

                ForEach(report.sections) { section in
                    CompletionReportDocumentSectionView(section: section, mode: report.mode)
                }

                if !report.charts.isEmpty {
                    CompletionReportChartsView(charts: report.charts)
                }

                if !report.safetyRows.isEmpty {
                    CompletionReportSafetyView(rows: report.safetyRows)
                }

                Text(report.reminder)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(24)
            .velouraTransientOverlayScrollIndicators()
        }
        .frame(minWidth: 760, idealWidth: 840, maxWidth: 900)
        .frame(minHeight: 620, idealHeight: 740, maxHeight: 780)
    }
}

private struct CompletionReportHeaderView: View {
    let report: CompletionReport

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("完了後レポート")
                    .font(.title2.bold())
                Spacer()
                Text(report.safetyRows.isEmpty ? "測定完了" : "安全確認あり")
                    .font(.body.bold())
                    .foregroundStyle(report.safetyRows.isEmpty ? Color.secondary : Color.red)
            }
            Text("入力・\(report.mode.middleStageTitle)・最終版を、同じ測定方法で比較した結果です。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CompletionReportSummaryView: View {
    let paragraphs: [String]

    var body: some View {
        CompletionReportCard(title: "総合結論") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

private struct CompletionReportComparisonView: View {
    let report: CompletionReport

    var body: some View {
        CompletionReportCard(title: "基本情報") {
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                    GridRow {
                        CompletionReportTableText("項目", width: 190, alignment: .leading)
                        CompletionReportTableText("原音", width: 160, alignment: .trailing)
                        CompletionReportTableText(report.mode == .stem ? "再ミックス" : "補正後", width: 160, alignment: .trailing)
                        CompletionReportTableText("マスター", width: 160, alignment: .trailing)
                    }
                    .font(.body.bold())

                    Divider().gridCellColumns(4)

                    ForEach(report.comparisonRows) { row in
                        GridRow(alignment: .firstTextBaseline) {
                            CompletionReportTableText(row.title, width: 190, alignment: .leading)
                                .fontWeight(.semibold)
                            CompletionReportTableText(row.inputValue, width: 160, alignment: .trailing, monospaced: true)
                            CompletionReportTableText(row.processedValue, width: 160, alignment: .trailing, monospaced: true)
                            CompletionReportTableText(row.masteredValue, width: 160, alignment: .trailing, monospaced: true)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            ForEach(Array(report.comparisonNotes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CompletionReportTableText: View {
    let value: String
    let width: CGFloat
    let alignment: Alignment
    let monospaced: Bool

    init(
        _ value: String,
        width: CGFloat,
        alignment: Alignment,
        monospaced: Bool = false
    ) {
        self.value = value
        self.width = width
        self.alignment = alignment
        self.monospaced = monospaced
    }

    var body: some View {
        Text(value)
            .font(monospaced ? .body.monospacedDigit() : .body)
            .frame(width: width, alignment: alignment)
            .textSelection(.enabled)
    }
}

private struct CompletionReportDocumentSectionView: View {
    let section: CompletionReportSection
    let mode: CompletionReportMode

    var body: some View {
        CompletionReportCard(title: section.title) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(section.subsections) { subsection in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(subsection.title)
                            .font(.headline)
                        ForEach(Array(subsection.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph)
                                .font(.body)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !subsection.stageDeltaRows.isEmpty {
                            CompletionReportStageDeltaGrid(
                                rows: subsection.stageDeltaRows,
                                mode: mode
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct CompletionReportStageDeltaGrid: View {
    let rows: [CompletionReportStageDeltaRow]
    let mode: CompletionReportMode

    private var middleTitle: String {
        mode == .stem ? "再ミックス" : "補正後"
    }

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 9) {
                GridRow {
                    CompletionReportTableText("ノイズ項目", width: 210, alignment: .leading)
                    CompletionReportTableText("入力→\(middleTitle)", width: 180, alignment: .trailing)
                    CompletionReportTableText("\(middleTitle)→最終版", width: 180, alignment: .trailing)
                }
                .font(.body.bold())

                Divider().gridCellColumns(3)

                ForEach(rows) { row in
                    GridRow(alignment: .firstTextBaseline) {
                        CompletionReportTableText(row.title, width: 210, alignment: .leading)
                            .fontWeight(.semibold)
                        CompletionReportTableText(
                            row.inputToProcessedValue,
                            width: 180,
                            alignment: .trailing,
                            monospaced: true
                        )
                        CompletionReportTableText(
                            row.processedToMasteredValue,
                            width: 180,
                            alignment: .trailing,
                            monospaced: true
                        )
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

private struct CompletionReportChartsView: View {
    let charts: [CompletionReportChart]

    var body: some View {
        CompletionReportCard(title: "解析画像") {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(charts) { chart in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(chart.title)
                            .font(.headline)
                        CompletionReportChartView(chart: chart)
                            .frame(height: 260)
                        HStack {
                            Text(chart.verticalAxisTitle)
                            Spacer()
                            Text(chart.horizontalAxisTitle)
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct CompletionReportChartView: View {
    let chart: CompletionReportChart

    var body: some View {
        Chart {
            ForEach(chart.series) { series in
                ForEach(Array(series.points.enumerated()), id: \.offset) { _, point in
                    if chart.kind == .waveformComparison, let lowerY = point.lowerY {
                        let xValue = horizontalValue(point.x)
                        let upperY = point.y
                        LineMark(
                            x: .value("X", xValue),
                            y: .value("最大", upperY),
                            series: .value("波形系列", "\(series.id)-maximum")
                        )
                        .foregroundStyle(by: .value("工程", series.title))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        LineMark(
                            x: .value("X", xValue),
                            y: .value("最小", lowerY),
                            series: .value("波形系列", "\(series.id)-minimum")
                        )
                        .foregroundStyle(by: .value("工程", series.title))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    } else {
                        let xValue = horizontalValue(point.x)
                        let yValue = point.y
                        LineMark(
                            x: .value("X", xValue),
                            y: .value("Y", yValue)
                        )
                        .foregroundStyle(by: .value("工程", series.title))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            if chart.kind == .spectrumDelta {
                RuleMark(y: .value("入力", 0))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
        }
        .chartLegend(position: .top, alignment: .leading, spacing: 12)
        .chartXAxis {
            if chart.kind == .spectrumComparison || chart.kind == .spectrumDelta {
                AxisMarks(values: [20.0, 100.0, 1_000.0, 10_000.0, 24_000.0].map(log10)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let logarithmic = value.as(Double.self) {
                            Text(frequencyLabel(pow(10, logarithmic)))
                        }
                    }
                }
            } else {
                AxisMarks(position: .bottom)
            }
        }
    }

    private func horizontalValue(_ value: Double) -> Double {
        switch chart.kind {
        case .spectrumComparison, .spectrumDelta:
            log10(max(value, 1))
        case .loudnessTimeline, .waveformComparison:
            value
        }
    }

    private func frequencyLabel(_ value: Double) -> String {
        value >= 1_000
            ? String(format: "%.0fk", value / 1_000)
            : String(format: "%.0f", value)
    }
}

private struct CompletionReportSafetyView: View {
    let rows: [CompletionReportRow]

    var body: some View {
        CompletionReportCard(title: "安全確認") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .accessibilityHidden(true)
                            Text(row.title)
                                .font(.body.bold())
                            Spacer()
                            Text(row.value)
                                .font(.body.monospacedDigit().bold())
                        }
                        Text(row.detail)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct CompletionReportCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
