import Charts
import SwiftUI

struct SpectrogramComparisonView: View {
    let input: SpectrogramSnapshot?
    let corrected: SpectrogramSnapshot?
    let mastered: SpectrogramSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("スペクトログラム")
                    .font(.headline)
                TermHelpButton(
                    title: "スペクトログラム",
                    reading: "すぺくとろぐらむ",
                    description: "横方向が時間、縦方向が周波数です。色は入力、補正後、最終版で共通の表示dBを示します。赤に近いほど強く、青や黒に近いほど弱い成分です。"
                )
                Spacer()
                Text("時間 →")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(spacing: 0) {
                    spectrogramRow(title: "入力", snapshot: input, tint: .blue, sharedDuration: timeAxisDuration)
                    Divider()
                    spectrogramRow(title: "補正後", snapshot: corrected, tint: .green, sharedDuration: timeAxisDuration)
                    Divider()
                    spectrogramRow(title: "最終版", snapshot: mastered, tint: .orange, sharedDuration: timeAxisDuration)
                    if let duration = timeAxisDuration {
                        timeAxis(duration: duration)
                    }
                }
                spectrogramLegend
            }
            .padding(8)
            .glassEffect(.clear, in: .rect(cornerRadius: 16))
        }
    }

    private func spectrogramRow(title: String, snapshot: SpectrogramSnapshot?, tint: Color, sharedDuration: Double?) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title)
                    .font(.callout.weight(.semibold))
            }
            .frame(width: 78, alignment: .leading)

            if let snapshot, !snapshot.cells.isEmpty {
                Chart(snapshot.cells) { cell in
                    RectangleMark(
                        xStart: .value("時間開始", cell.timeStart),
                        xEnd: .value("時間終了", cell.timeEnd),
                        yStart: .value("周波数開始", cell.frequencyStart),
                        yEnd: .value("周波数終了", cell.frequencyEnd)
                    )
                    .foregroundStyle(SpectrogramDisplayColorScale.color(for: cell.levelDB))
                    .lineStyle(.init(lineWidth: 0))
                }
                .chartXAxis(.hidden)
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
                .chartXScale(domain: 0 ... max(sharedDuration ?? snapshot.duration, 0.1))
                .chartYScale(domain: 80 ... 24_000, type: .log)
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.black.opacity(0.06))
                        .border(Color.black.opacity(0.08))
                }
                .frame(height: 94)
                .accessibilityLabel("\(title)のスペクトログラム")
            } else {
                Text(unavailableText(for: title))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 94)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var timeAxisDuration: Double? {
        [input, corrected, mastered]
            .compactMap { snapshot -> Double? in
                guard let snapshot, snapshot.duration > 0 else { return nil }
                return snapshot.duration
            }
            .max()
    }

    private func timeAxis(duration: Double) -> some View {
        HStack(spacing: 12) {
            Color.clear
                .frame(width: 78)
            SpectrogramTimeAxisView(duration: duration)
                .frame(height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("スペクトログラムの時間目盛り")
    }

    private var spectrogramLegend: some View {
        VStack(spacing: 4) {
            Text("表示dB")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 4) {
                LinearGradient(
                    colors: SpectrogramDisplayColorScale.legendColors,
                    startPoint: .bottom,
                    endPoint: .top
                )
                .frame(width: 12, height: 286)
                .overlay {
                    Rectangle()
                        .stroke(.separator, lineWidth: 0.5)
                }

                VStack {
                    ForEach(SpectrogramDisplayColorScale.legendLevels, id: \.self) { level in
                        Text("\(Int(level))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if level != SpectrogramDisplayColorScale.legendLevels.last {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(height: 286)
            }
        }
        .padding(.trailing, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("スペクトログラムの表示dB凡例。0からマイナス100デシベル")
    }

    private func unavailableText(for title: String) -> String {
        switch title {
        case "入力":
            return "音声を選ぶと表示します"
        case "補正後":
            return "補正が完了すると表示します"
        default:
            return "マスタリングが完了すると表示します"
        }
    }
}

private struct SpectrogramTimeAxisView: View {
    let duration: Double

    var body: some View {
        GeometryReader { proxy in
            let ticks = timeTicks(for: duration)
            let width = max(proxy.size.width, 1)

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.separator.opacity(0.7))
                    .frame(height: 1)
                    .offset(y: 4)

                ForEach(ticks) { tick in
                    VStack(spacing: 3) {
                        Rectangle()
                            .fill(.separator.opacity(0.8))
                            .frame(width: 1, height: 5)
                        Text(formatTime(tick.time))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 48)
                    .position(
                        x: labelPosition(for: tick.time, width: width),
                        y: 14
                    )
                }
            }
        }
    }

    private func timeTicks(for duration: Double) -> [TimeTick] {
        [0, 0.25, 0.5, 0.75, 1].map { ratio in
            TimeTick(time: max(duration, 0) * ratio)
        }
    }

    private func formatTime(_ time: Double) -> String {
        let totalSeconds = Int(time.rounded())
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func labelPosition(for time: Double, width: CGFloat) -> CGFloat {
        guard width >= 48 else { return width / 2 }
        let rawX = CGFloat(time / max(duration, 0.1)) * width
        return min(max(rawX, 24), width - 24)
    }

    private struct TimeTick: Identifiable {
        let time: Double

        var id: Double { time }
    }
}

enum SpectrogramDisplayColorScale {
    static let legendLevels: [Double] = [0, -20, -40, -60, -80, -100]
    static let legendColors: [Color] = stops.map(\.color)

    private static let stops: [Stop] = [
        Stop(levelDB: -100, red: 0.01, green: 0.02, blue: 0.08),
        Stop(levelDB: -80, red: 0.04, green: 0.15, blue: 0.55),
        Stop(levelDB: -60, red: 0.00, green: 0.62, blue: 0.90),
        Stop(levelDB: -40, red: 0.18, green: 0.76, blue: 0.36),
        Stop(levelDB: -20, red: 0.98, green: 0.78, blue: 0.08),
        Stop(levelDB: 0, red: 0.92, green: 0.12, blue: 0.08)
    ]

    static func normalizedPosition(for levelDB: Double) -> Double {
        let clamped = min(
            AudioFileService.spectrogramDisplayMaximumDB,
            max(AudioFileService.spectrogramDisplayMinimumDB, levelDB)
        )
        return (clamped - AudioFileService.spectrogramDisplayMinimumDB)
            / (AudioFileService.spectrogramDisplayMaximumDB - AudioFileService.spectrogramDisplayMinimumDB)
    }

    static func color(for levelDB: Double) -> Color {
        let clamped = AudioFileService.spectrogramDisplayMinimumDB
            + normalizedPosition(for: levelDB)
                * (AudioFileService.spectrogramDisplayMaximumDB - AudioFileService.spectrogramDisplayMinimumDB)
        guard let upperIndex = stops.firstIndex(where: { $0.levelDB >= clamped }) else {
            return stops.last!.color
        }
        guard upperIndex > 0 else {
            return stops[upperIndex].color
        }

        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let progress = (clamped - lower.levelDB) / (upper.levelDB - lower.levelDB)
        return Color(
            red: lower.red + (upper.red - lower.red) * progress,
            green: lower.green + (upper.green - lower.green) * progress,
            blue: lower.blue + (upper.blue - lower.blue) * progress
        )
    }

    private struct Stop {
        let levelDB: Double
        let red: Double
        let green: Double
        let blue: Double

        var color: Color {
            Color(red: red, green: green, blue: blue)
        }
    }
}
