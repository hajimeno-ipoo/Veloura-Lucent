import SwiftUI

struct AverageSpectrumComparisonView: View {
    let preview: AudioPreviewController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("再生中スペクトル")
                    .font(.headline)
                TermHelpButton(
                    title: "再生中スペクトル",
                    reading: "さいせいちゅうすぺくとる",
                    description: "再生している音声バッファをその場で解析し、周波数ごとの強さを表示します。入力、補正後、最終版を切り替えた時に、いま鳴っている音の変化を確認する表示です。"
                )
                Spacer()
                spectrumLegend
            }

            if spectrumSeries.isEmpty {
                unavailableMessage("音声を再生すると、いま鳴っている音の周波数バランスを表示します")
            } else {
                SpectrumCanvasChart(series: spectrumSeries)
                    .frame(height: 220)
                    .accessibilityLabel("再生中音声のリアルタイムスペクトル")
            }
        }
    }

    private var spectrumLegend: some View {
        HStack(spacing: 12) {
            ForEach(spectrumSeries) { series in
                legendItem(title: series.name, color: series.color)
            }
        }
    }

    private func legendItem(title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .fill(color)
                .frame(width: 18, height: 3)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var spectrumSeries: [SpectrumSeries] {
        AudioPreviewTarget.allCases.compactMap { target in
            series(from: preview.cardState(for: target).realtimeSpectrum, target: target)
        }
    }

    private func series(from samples: [RealtimeSpectrumPoint], target: AudioPreviewTarget) -> SpectrumSeries? {
        let points = samples.map {
            SpectrumCurvePoint(
                id: "\(target.rawValue)-\($0.id)",
                frequencyHz: $0.frequencyHz,
                levelDB: $0.levelDB
            )
        }
        guard !points.isEmpty else { return nil }
        return SpectrumSeries(id: target.rawValue, name: target.rawValue, color: color(for: target), points: points)
    }

    private func color(for target: AudioPreviewTarget) -> Color {
        switch target {
        case .input:
            return .blue
        case .corrected:
            return .green
        case .mastered:
            return .orange
        }
    }

    private func unavailableMessage(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SpectrumCanvasChart: View {
    let series: [SpectrumSeries]
    @State private var hoverLocation: CGPoint?
    @State private var canvasSize: CGSize = .zero

    private let xDomain = 80.0 ... 20_000.0
    private let yDomain = -100.0 ... 0.0
    private let wideXTicks = [100.0, 200.0, 500.0, 1_000.0, 2_000.0, 5_000.0, 10_000.0, 20_000.0]
    private let compactXTicks = [100.0, 1_000.0, 5_000.0, 10_000.0, 20_000.0]
    private let yTicks = [0.0, -20.0, -40.0, -60.0, -80.0, -100.0]
    private let plotInsets = EdgeInsets(top: 14, leading: 42, bottom: 28, trailing: 18)
    private let wideTickMinimumWidth: CGFloat = 620

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hoverReadout ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Canvas { context, size in
                let plotRect = plotRect(in: size)
                drawBackground(context: &context, plotRect: plotRect)
                drawAirBand(context: &context, plotRect: plotRect)
                drawGrid(context: &context, plotRect: plotRect, xTicks: xTicks(for: size.width))
                drawSeries(context: &context, plotRect: plotRect)
                drawHover(context: &context, plotRect: plotRect)
            }
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear {
                            canvasSize = proxy.size
                        }
                        .onChange(of: proxy.size) { _, newSize in
                            canvasSize = newSize
                        }
                }
            }
            .overlay(alignment: .topLeading) {
                AxisLabelOverlay(
                    plotInsets: plotInsets,
                    xTicks: xTicks(for: canvasSize.width),
                    yTicks: yTicks,
                    xPosition: xPosition,
                    yPosition: yPosition,
                    frequencyLabel: frequencyLabel
                )
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoverLocation = location
                case .ended:
                    hoverLocation = nil
                }
            }
        }
    }

    private var hoverReadout: String? {
        guard let hoverLocation else { return nil }
        let plotRect = plotRect(in: canvasSize)
        guard plotRect.contains(hoverLocation) else { return nil }
        let frequency = frequency(atX: hoverLocation.x, in: plotRect)
        let values = series.compactMap { source -> String? in
            guard let point = nearestPoint(in: source, frequency: frequency) else { return nil }
            return "\(source.name) \(String(format: "%.1f dBFS", point.levelDB))"
        }
        guard !values.isEmpty else { return nil }
        return "\(frequencyReadoutLabel(frequency))  " + values.joined(separator: " / ")
    }

    private func drawBackground(context: inout GraphicsContext, plotRect: CGRect) {
        context.fill(
            Path(plotRect),
            with: .color(Color.secondary.opacity(0.035))
        )
        context.stroke(
            Path(plotRect),
            with: .color(Color.secondary.opacity(0.18)),
            lineWidth: 1
        )
    }

    private func drawAirBand(context: inout GraphicsContext, plotRect: CGRect) {
        let startX = xPosition(8_000, in: plotRect)
        let endX = xPosition(12_000, in: plotRect)
        let rect = CGRect(x: startX, y: plotRect.minY, width: max(endX - startX, 1), height: plotRect.height)
        context.fill(Path(rect), with: .color(Color.orange.opacity(0.07)))
    }

    private func drawGrid(context: inout GraphicsContext, plotRect: CGRect, xTicks: [Double]) {
        var path = Path()
        for tick in xTicks {
            let x = xPosition(tick, in: plotRect)
            path.move(to: CGPoint(x: x, y: plotRect.minY))
            path.addLine(to: CGPoint(x: x, y: plotRect.maxY))
        }
        for tick in yTicks {
            let y = yPosition(tick, in: plotRect)
            path.move(to: CGPoint(x: plotRect.minX, y: y))
            path.addLine(to: CGPoint(x: plotRect.maxX, y: y))
        }
        context.stroke(path, with: .color(Color.secondary.opacity(0.16)), lineWidth: 0.8)
    }

    private func drawSeries(context: inout GraphicsContext, plotRect: CGRect) {
        for source in series {
            let path = smoothedSeriesPath(for: source, in: plotRect)
            context.stroke(path, with: .color(source.color), lineWidth: 1.25)
        }
    }

    private func smoothedSeriesPath(for source: SpectrumSeries, in plotRect: CGRect) -> Path {
        let points = source.points.compactMap { point -> CGPoint? in
            guard xDomain.contains(point.frequencyHz) else { return nil }
            return CGPoint(
                x: xPosition(point.frequencyHz, in: plotRect),
                y: yPosition(point.levelDB, in: plotRect)
            )
        }

        var path = Path()
        guard let firstPoint = points.first else { return path }
        path.move(to: firstPoint)

        guard points.count > 1 else { return path }

        for index in 1..<points.count {
            let previousPoint = points[index - 1]
            let currentPoint = points[index]
            let midpoint = CGPoint(
                x: (previousPoint.x + currentPoint.x) / 2,
                y: (previousPoint.y + currentPoint.y) / 2
            )

            path.addQuadCurve(to: midpoint, control: previousPoint)

            if index == points.count - 1 {
                path.addQuadCurve(to: currentPoint, control: currentPoint)
            }
        }

        return path
    }

    private func drawHover(context: inout GraphicsContext, plotRect: CGRect) {
        guard let hoverLocation, plotRect.contains(hoverLocation) else { return }
        var path = Path()
        path.move(to: CGPoint(x: hoverLocation.x, y: plotRect.minY))
        path.addLine(to: CGPoint(x: hoverLocation.x, y: plotRect.maxY))
        context.stroke(path, with: .color(Color.primary.opacity(0.36)), lineWidth: 1)
    }

    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: plotInsets.leading,
            y: plotInsets.top,
            width: max(size.width - plotInsets.leading - plotInsets.trailing, 1),
            height: max(size.height - plotInsets.top - plotInsets.bottom, 1)
        )
    }

    private func xTicks(for width: CGFloat) -> [Double] {
        width >= wideTickMinimumWidth ? wideXTicks : compactXTicks
    }

    private func xPosition(_ frequency: Double, in rect: CGRect) -> CGFloat {
        let minLog = log(xDomain.lowerBound)
        let maxLog = log(xDomain.upperBound)
        let value = min(max(frequency, xDomain.lowerBound), xDomain.upperBound)
        let ratio = (log(value) - minLog) / (maxLog - minLog)
        return rect.minX + CGFloat(ratio) * rect.width
    }

    private func yPosition(_ level: Double, in rect: CGRect) -> CGFloat {
        let value = min(max(level, yDomain.lowerBound), yDomain.upperBound)
        let ratio = (value - yDomain.lowerBound) / (yDomain.upperBound - yDomain.lowerBound)
        return rect.maxY - CGFloat(ratio) * rect.height
    }

    private func frequency(atX x: CGFloat, in rect: CGRect) -> Double {
        let plotX = min(max(x - rect.minX, 0), rect.width)
        let ratio = Double(plotX / max(rect.width, 1))
        let minLog = log(xDomain.lowerBound)
        let maxLog = log(xDomain.upperBound)
        return exp(minLog + ratio * (maxLog - minLog))
    }

    private func nearestPoint(in source: SpectrumSeries, frequency: Double) -> SpectrumCurvePoint? {
        source.points.min {
            abs(log($0.frequencyHz) - log(frequency)) < abs(log($1.frequencyHz) - log(frequency))
        }
    }

    private func frequencyLabel(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            let value = frequency / 1_000
            if value.rounded() == value {
                return "\(Int(value))k"
            }
            return String(format: "%.1fk", value)
        }
        return "\(Int(frequency.rounded()))"
    }

    private func frequencyReadoutLabel(_ frequency: Double) -> String {
        if frequency >= 1_000 {
            return String(format: "%.1fkHz", frequency / 1_000)
        }
        return "\(Int(frequency.rounded()))Hz"
    }
}

private struct AxisLabelOverlay: View {
    let plotInsets: EdgeInsets
    let xTicks: [Double]
    let yTicks: [Double]
    let xPosition: (Double, CGRect) -> CGFloat
    let yPosition: (Double, CGRect) -> CGFloat
    let frequencyLabel: (Double) -> String

    var body: some View {
        GeometryReader { proxy in
            let plotRect = CGRect(
                x: plotInsets.leading,
                y: plotInsets.top,
                width: max(proxy.size.width - plotInsets.leading - plotInsets.trailing, 1),
                height: max(proxy.size.height - plotInsets.top - plotInsets.bottom, 1)
            )

            ForEach(yTicks, id: \.self) { tick in
                Text(String(format: "%.0f", tick))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: plotInsets.leading - 18, y: yPosition(tick, plotRect))
            }

            ForEach(xTicks, id: \.self) { tick in
                Text(frequencyLabel(tick))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: xPosition(tick, plotRect), y: plotRect.maxY + 14)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SpectrumSeries: Identifiable {
    let id: String
    let name: String
    let color: Color
    let points: [SpectrumCurvePoint]
}

private struct SpectrumCurvePoint: Identifiable {
    let id: String
    let frequencyHz: Double
    let levelDB: Double
}
