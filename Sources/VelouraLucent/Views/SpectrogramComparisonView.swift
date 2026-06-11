import Charts
import SwiftUI

struct SpectrogramComparisonView: View {
    let input: SpectrogramSnapshot?
    let corrected: SpectrogramSnapshot?
    let mastered: SpectrogramSnapshot?

    var body: some View {
        spectrogramSection
    }
    private var spectrogramSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("スペクトログラム")
                .font(.headline)

            if let input {
                let bounds = combinedSpectrogramBounds(input: input, corrected: corrected, mastered: mastered)
                HStack(alignment: .top, spacing: 14) {
                    spectrogramCard(title: "入力", snapshot: input, tint: .blue, bounds: bounds)
                    spectrogramCard(title: "補正後", snapshot: corrected ?? .empty, tint: .green, bounds: bounds)
                    spectrogramCard(title: "最終版", snapshot: mastered ?? .empty, tint: .orange, bounds: bounds)
                }
            } else {
                Text("音声を選ぶと、ここに入力・補正後・最終版の時間と帯域の変化が表示されます。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func spectrogramCard(title: String, snapshot: SpectrogramSnapshot, tint: Color, bounds: (min: Double, max: Double)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            if snapshot.cells.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(height: 180)
                    .overlay {
                        Text("まだ表示できません")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            } else {
                Chart(snapshot.cells) { cell in
                    RectangleMark(
                        xStart: .value("時間開始", cell.timeStart),
                        xEnd: .value("時間終了", cell.timeEnd),
                        yStart: .value("周波数開始", cell.frequencyStart),
                        yEnd: .value("周波数終了", cell.frequencyEnd)
                    )
                    .foregroundStyle(tint.opacity(spectrogramOpacity(for: cell.levelDB, bounds: bounds)))
                    .lineStyle(.init(lineWidth: 0))
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4))
                }
                .chartYAxis {
                    AxisMarks(values: [100, 1_000, 10_000]) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let frequency = value.as(Double.self) {
                                Text(frequency >= 1000 ? "\(Int(frequency / 1000))k" : "\(Int(frequency))")
                            }
                        }
                    }
                }
                .chartXScale(domain: 0 ... max(snapshot.duration, 0.1))
                .chartYScale(domain: 80 ... 24_000, type: .log)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.black.opacity(0.06))
                        .border(Color.black.opacity(0.08))
                }
                .frame(height: 180)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func combinedSpectrogramBounds(
        input: SpectrogramSnapshot,
        corrected: SpectrogramSnapshot?,
        mastered: SpectrogramSnapshot?
    ) -> (min: Double, max: Double) {
        let snapshots = [input, corrected, mastered].compactMap { $0 }.filter { !$0.cells.isEmpty }
        let minLevel = snapshots.map(\.minLevelDB).min() ?? -96
        let maxLevel = snapshots.map(\.maxLevelDB).max() ?? -24
        return (minLevel, maxLevel)
    }

    private func spectrogramOpacity(for levelDB: Double, bounds: (min: Double, max: Double)) -> Double {
        let normalized = max(0, min(1, (levelDB - bounds.min) / max(bounds.max - bounds.min, 1)))
        return 0.04 + pow(normalized, 0.55) * 0.96
    }


}
