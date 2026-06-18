import SwiftUI

struct LoudnessMeterView: View {
    let snapshot: LiveLoudnessMeterSnapshot
    let targetLoudnessLUFS: Double
    let truePeakCeilingDBTP: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                LoudnessMeterColumn(
                    title: "Momentary",
                    value: snapshot.momentaryLUFS,
                    unit: "LUFS",
                    minimum: -60,
                    maximum: 0,
                    referenceValue: targetLoudnessLUFS,
                    referenceLabel: "目標",
                    warningThreshold: targetLoudnessLUFS + 2.0,
                    tickValues: [0, -10, -14, -18, -23, -40, -60]
                )
                LoudnessMeterColumn(
                    title: "Short-Term",
                    value: snapshot.shortTermLUFS,
                    unit: "LUFS",
                    minimum: -60,
                    maximum: 0,
                    referenceValue: targetLoudnessLUFS,
                    referenceLabel: "目標",
                    warningThreshold: targetLoudnessLUFS + 2.0,
                    tickValues: [0, -10, -14, -18, -23, -40, -60]
                )
                LoudnessMeterColumn(
                    title: "Integrated",
                    value: snapshot.integratedLUFS,
                    unit: "LUFS",
                    minimum: -60,
                    maximum: 0,
                    referenceValue: targetLoudnessLUFS,
                    referenceLabel: "目標",
                    warningThreshold: targetLoudnessLUFS + 1.0,
                    tickValues: [0, -10, -14, -18, -23, -40, -60]
                )
                LoudnessMeterColumn(
                    title: "True Peak",
                    value: snapshot.truePeakDBTP,
                    unit: "dBTP",
                    minimum: -12,
                    maximum: 1,
                    referenceValue: truePeakCeilingDBTP,
                    referenceLabel: "上限",
                    warningThreshold: truePeakCeilingDBTP,
                    tickValues: [1, 0, -1, -3, -6, -12]
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 12) {
                referenceText("目標", value: targetLoudnessLUFS, unit: "LUFS")
                referenceText("上限", value: truePeakCeilingDBTP, unit: "dBTP")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    private func referenceText(_ label: String, value: Double, unit: String) -> some View {
        Text("\(label): \(format(value)) \(unit)")
    }

    private var accessibilityDescription: String {
        "ラウドネスメーター。Momentary \(accessibilityValue(snapshot.momentaryLUFS)) LUFS、Short-Term \(accessibilityValue(snapshot.shortTermLUFS)) LUFS、Integrated \(accessibilityValue(snapshot.integratedLUFS)) LUFS、True Peak \(accessibilityValue(snapshot.truePeakDBTP)) dBTP。"
    }

    private func accessibilityValue(_ value: Double?) -> String {
        value.map(format) ?? "未測定"
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

private struct LoudnessMeterColumn: View {
    let title: String
    let value: Double?
    let unit: String
    let minimum: Double
    let maximum: Double
    let referenceValue: Double
    let referenceLabel: String
    let warningThreshold: Double?
    let tickValues: [Double]

    private var clampedValue: Double? {
        value.map { min(max($0, minimum), maximum) }
    }

    private var isOverThreshold: Bool {
        guard let value, let warningThreshold else { return false }
        return value > warningThreshold
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.12))

                if let clampedValue {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(meterGradient)
                        .frame(height: meterHeight * normalized(clampedValue))
                }

                MeterReferenceLine(
                    normalizedPosition: normalized(referenceValue),
                    color: referenceColor
                )
            }
            .frame(width: 42, height: meterHeight)
            .overlay(alignment: .leading) {
                tickLabels
                    .offset(x: -42)
            }
            .overlay(alignment: .trailing) {
                referenceLabelView
                    .offset(x: 34)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.secondary.opacity(0.22), lineWidth: 1)
            }

            Text(value.map(format) ?? "--")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 100)
    }

    private var referenceLabelView: some View {
        GeometryReader { proxy in
            Text(referenceLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(referenceColor)
                .padding(.horizontal, 4)
                .background(.regularMaterial, in: Capsule())
                .position(
                    x: 18,
                    y: proxy.size.height * (1 - normalized(referenceValue))
                )
        }
        .frame(width: 36, height: meterHeight)
    }

    private var tickLabels: some View {
        GeometryReader { proxy in
            ForEach(tickValues, id: \.self) { tickValue in
                Text(tickLabel(tickValue))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .position(
                        x: 16,
                        y: proxy.size.height * (1 - normalized(tickValue))
                    )
            }
        }
        .frame(width: 34, height: meterHeight)
    }

    private var meterHeight: CGFloat {
        190
    }

    private var valueColor: Color {
        guard value != nil else { return .secondary }
        return isOverThreshold ? .red : .primary
    }

    private var referenceColor: Color {
        isOverThreshold ? .red : .blue
    }

    private var meterGradient: LinearGradient {
        LinearGradient(
            colors: [.green, .yellow, .orange, .red],
            startPoint: .bottom,
            endPoint: .top
        )
    }

    private func normalized(_ value: Double) -> Double {
        let span = max(maximum - minimum, 1)
        return min(max((value - minimum) / span, 0), 1)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func tickLabel(_ value: Double) -> String {
        if value > 0 {
            return String(format: "+%.0f", value)
        }
        return String(format: "%.0f", value)
    }
}

private struct MeterReferenceLine: View {
    let normalizedPosition: Double
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let y = proxy.size.height * (1 - min(max(normalizedPosition, 0), 1))
            referencePath(y: y, width: proxy.size.width)
                .stroke(Color.white.opacity(0.85), style: StrokeStyle(lineWidth: 3.2, dash: [3, 2]))
            referencePath(y: y, width: proxy.size.width)
                .stroke(color.opacity(0.95), style: StrokeStyle(lineWidth: 1.8, dash: [3, 2]))
        }
    }

    private func referencePath(y: CGFloat, width: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: width, y: y))
        }
    }
}
