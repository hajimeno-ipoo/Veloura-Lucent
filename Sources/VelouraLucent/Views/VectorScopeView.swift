import SwiftUI

struct VectorScopeView: View {
    let preview: AudioPreviewController
    let masteringSettings: MasteringSettings
    @State private var displayMode: VectorScopeDisplayMode = .polarSample
    @State private var contentWidth: CGFloat = 0

    private let horizontalLayoutMinimumWidth: CGFloat = 1_024

    private var activeTarget: AudioPreviewTarget? {
        preview.activeTarget
    }

    private var snapshot: VectorScopeSnapshot {
        guard let activeTarget else { return .unavailable }
        return preview.cardState(for: activeTarget).vectorScopeSnapshot
    }

    private var loudnessSnapshot: LiveLoudnessMeterSnapshot {
        guard let activeTarget else { return .unavailable }
        return preview.cardState(for: activeTarget).liveLoudnessMeterSnapshot
    }

    var body: some View {
        Group {
            if usesHorizontalLayout {
                HStack(alignment: .top, spacing: 24) {
                    scopePanel
                    loudnessPanel
                }
            } else {
                VStack(alignment: .leading, spacing: 20) {
                    scopePanel
                    loudnessPanel
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        contentWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size) { _, newSize in
                        contentWidth = newSize.width
                    }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var usesHorizontalLayout: Bool {
        contentWidth >= horizontalLayoutMinimumWidth
    }

    private var scopePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("ベクトルスコープ")
                    .font(.headline)
                TermHelpButton(
                    title: "ベクトルスコープ",
                    reading: "べくとるすこーぷ",
                    description: "左右チャンネルの瞬間的な関係を点や線で表示します。縦に近いほど同相、横に広がるほど逆相成分が多く、斜め方向は左右どちらかへ偏った状態を示します。"
                )
                Spacer()
                if activeTarget != nil {
                    Button("履歴を消す", action: preview.resetVectorScopeHistory)
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }

            Text(scopeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            VectorScopeModePicker(displayMode: $displayMode)

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    scopePlot
                        .frame(minWidth: 0, maxWidth: .infinity)
                    CorrelationMeterView(value: snapshot.correlation)
                        .frame(width: 92, height: 300)
                }

                BalanceMeterView(value: snapshot.balance)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .padding(12)
            .glassEffect(.clear, in: .rect(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, minHeight: 430, alignment: .topLeading)
    }

    private var loudnessPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("ラウドネスメーター")
                    .font(.headline)
                TermHelpButton(
                    title: "ラウドネスメーター",
                    reading: "らうどねすめーたー",
                    description: "音の大きさとピークを確認するメーターです。Momentaryは約0.4秒、Short-Termは約3秒、Integratedは再生開始からの平均、True Peakは再生中に出た最大ピークを示します。"
                )
                Spacer()
                if let activeTarget {
                    Text(activeTarget.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(targetColor(activeTarget))
                }
            }

            Text("目標線と上限線で、再生中の音を確認します。")
                .font(.caption)
                .foregroundStyle(.secondary)

            loudnessMeter
        }
        .frame(maxWidth: .infinity, minHeight: 430, alignment: .topLeading)
    }

    private var scopePlot: some View {
        ZStack {
            VectorScopePlot(
                snapshot: snapshot,
                mode: displayMode,
                color: activeTarget.map(targetColor) ?? .secondary
            )

            if let message = statusMessage {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(16)
                    .glassEffect(.clear, in: .rect(cornerRadius: 12))
                    .padding(24)
            }
        }
        .frame(height: 300)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var loudnessMeter: some View {
        LoudnessMeterView(
            snapshot: loudnessSnapshot,
            targetLoudnessLUFS: Double(masteringSettings.targetLoudness),
            truePeakCeilingDBTP: Double(masteringSettings.peakCeilingDB)
        )
        .frame(minHeight: 346)
    }

    private var scopeDescription: String {
        switch displayMode {
        case .polarSample:
            return "Polar Sample: 45度安全ライン内は同相、外側は位相ずれを示します。"
        case .polarLevel:
            return "Polar Level: 平均線の角度でステレオ位置、長さで振幅を確認します。"
        case .lissajous:
            return "Lissajous: 縦=同相 / 横=逆相 / 斜め=左右偏り。"
        }
    }

    private var statusMessage: String? {
        switch snapshot.inputState {
        case .unavailable:
            return nil
        case .mono:
            return "モノラル音源のため、左右の関係は表示しません"
        case .stereo:
            return snapshot.points.isEmpty && snapshot.polarSamplePoints.isEmpty && snapshot.polarLevelLines.isEmpty
                ? "音声信号を待っています"
                : nil
        case let .multichannel(channelCount):
            return "\(channelCount)チャンネル音源はベクトルスコープ未対応です"
        }
    }

    private var accessibilityDescription: String {
        guard activeTarget != nil else {
            return "ベクトルスコープ。停止中です"
        }
        if let statusMessage {
            return "ベクトルスコープ。\(statusMessage)"
        }
        let targetName = activeTarget?.rawValue ?? "音源"
        return "ベクトルスコープ。\(targetName)の\(displayMode.title)を表示中です"
    }

    private func targetColor(_ target: AudioPreviewTarget) -> Color {
        switch target {
        case .input: .blue
        case .corrected: .green
        case .mastered: .orange
        }
    }
}

private struct VectorScopePlot: View {
    let snapshot: VectorScopeSnapshot
    let mode: VectorScopeDisplayMode
    let color: Color

    var body: some View {
        Canvas { context, size in
            let metrics = plotMetrics(in: size)
            drawGrid(context: context, metrics: metrics)

            switch mode {
            case .polarSample:
                draw(points: snapshot.polarSamplePoints, context: context, metrics: metrics)
            case .polarLevel:
                draw(lines: snapshot.polarLevelLines, context: context, metrics: metrics)
            case .lissajous:
                draw(points: snapshot.points, context: context, metrics: metrics)
            }

            drawLabels(context: context, metrics: metrics)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }

    private func plotMetrics(in size: CGSize) -> PlotMetrics {
        let labelInset: CGFloat = 34
        let plotRect = CGRect(
            x: labelInset,
            y: labelInset,
            width: max(0, size.width - labelInset * 2),
            height: max(0, size.height - labelInset * 2)
        )
        let lissajousRadius = min(plotRect.width, plotRect.height) * 0.45
        let polarRadius = min(plotRect.width * 0.5, plotRect.height * 0.86)
        return PlotMetrics(
            rect: plotRect,
            center: CGPoint(x: plotRect.midX, y: plotRect.midY),
            origin: CGPoint(x: plotRect.midX, y: plotRect.maxY),
            lissajousRadius: lissajousRadius,
            polarRadius: polarRadius
        )
    }

    private func drawGrid(context: GraphicsContext, metrics: PlotMetrics) {
        switch mode {
        case .lissajous:
            drawLissajousGrid(context: context, metrics: metrics)
        case .polarSample, .polarLevel:
            drawPolarGrid(context: context, metrics: metrics)
        }
    }

    private func drawLissajousGrid(context: GraphicsContext, metrics: PlotMetrics) {
        let radius = metrics.lissajousRadius
        let top = CGPoint(x: metrics.center.x, y: metrics.center.y - radius)
        let right = CGPoint(x: metrics.center.x + radius, y: metrics.center.y)
        let bottom = CGPoint(x: metrics.center.x, y: metrics.center.y + radius)
        let left = CGPoint(x: metrics.center.x - radius, y: metrics.center.y)

        for scale in [0.35, 0.65, 1.0] {
            var diamond = Path()
            diamond.move(to: CGPoint(x: metrics.center.x, y: metrics.center.y - radius * scale))
            diamond.addLine(to: CGPoint(x: metrics.center.x + radius * scale, y: metrics.center.y))
            diamond.addLine(to: CGPoint(x: metrics.center.x, y: metrics.center.y + radius * scale))
            diamond.addLine(to: CGPoint(x: metrics.center.x - radius * scale, y: metrics.center.y))
            diamond.closeSubpath()
            context.stroke(diamond, with: .color(.secondary.opacity(scale == 1.0 ? 0.30 : 0.10)), lineWidth: scale == 1.0 ? 1.4 : 1)
        }

        var guides = Path()
        guides.move(to: top)
        guides.addLine(to: bottom)
        guides.move(to: left)
        guides.addLine(to: right)
        guides.move(to: CGPoint(x: (top.x + left.x) / 2, y: (top.y + left.y) / 2))
        guides.addLine(to: CGPoint(x: (bottom.x + right.x) / 2, y: (bottom.y + right.y) / 2))
        guides.move(to: CGPoint(x: (top.x + right.x) / 2, y: (top.y + right.y) / 2))
        guides.addLine(to: CGPoint(x: (bottom.x + left.x) / 2, y: (bottom.y + left.y) / 2))
        context.stroke(guides, with: .color(.secondary.opacity(0.18)), lineWidth: 1)
        drawCenterPoint(context: context, at: metrics.center)
    }

    private func drawPolarGrid(context: GraphicsContext, metrics: PlotMetrics) {
        let radius = metrics.polarRadius
        for scale in [0.33, 0.66, 1.0] {
            let arc = semicirclePath(origin: metrics.origin, radius: radius * scale)
            context.stroke(arc, with: .color(.secondary.opacity(scale == 1.0 ? 0.30 : 0.10)), lineWidth: scale == 1.0 ? 1.4 : 1)
        }

        var baseline = Path()
        baseline.move(to: CGPoint(x: metrics.origin.x - radius, y: metrics.origin.y))
        baseline.addLine(to: CGPoint(x: metrics.origin.x + radius, y: metrics.origin.y))
        context.stroke(baseline, with: .color(.secondary.opacity(0.24)), lineWidth: 1)

        var safety = Path()
        safety.move(to: metrics.origin)
        safety.addLine(to: CGPoint(x: metrics.origin.x - radius * 0.71, y: metrics.origin.y - radius * 0.71))
        safety.move(to: metrics.origin)
        safety.addLine(to: CGPoint(x: metrics.origin.x + radius * 0.71, y: metrics.origin.y - radius * 0.71))
        context.stroke(safety, with: .color(.blue.opacity(0.45)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))

        var vertical = Path()
        vertical.move(to: metrics.origin)
        vertical.addLine(to: CGPoint(x: metrics.origin.x, y: metrics.origin.y - radius))
        context.stroke(vertical, with: .color(.secondary.opacity(0.18)), lineWidth: 1)

        drawCenterPoint(context: context, at: metrics.origin)
    }

    private func semicirclePath(origin: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        for step in 0...72 {
            let theta = Double.pi - (Double.pi * Double(step) / 72)
            let point = CGPoint(
                x: origin.x + cos(theta) * radius,
                y: origin.y - sin(theta) * radius
            )
            if step == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private func drawCenterPoint(context: GraphicsContext, at point: CGPoint) {
        let center = Path(ellipseIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
        context.fill(center, with: .color(.secondary.opacity(0.5)))
    }

    private func draw(points: [VectorScopePoint], context: GraphicsContext, metrics: PlotMetrics) {
        for point in points {
            let position = position(for: point, metrics: metrics)
            let dotRadius: CGFloat = point.isClipped ? 2.4 : (mode == .polarSample ? 1.45 : 1.25)
            let dot = Path(ellipseIn: CGRect(
                x: position.x - dotRadius,
                y: position.y - dotRadius,
                width: dotRadius * 2,
                height: dotRadius * 2
            ))
            let opacity = max(0.05, 0.78 - point.age * 0.73)
            context.fill(dot, with: .color((point.isClipped ? Color.red : color).opacity(opacity)))
        }
    }

    private func draw(lines: [VectorScopeLine], context: GraphicsContext, metrics: PlotMetrics) {
        for line in lines.reversed() {
            let outerEnd = polarPosition(x: line.x, y: line.y, metrics: metrics)
            let shrinkScale = max(0.38, 1 - CGFloat(line.age) * 0.62)
            let shrinkingEnd = CGPoint(
                x: metrics.origin.x + (outerEnd.x - metrics.origin.x) * shrinkScale,
                y: metrics.origin.y + (outerEnd.y - metrics.origin.y) * shrinkScale
            )
            let opacity = max(0.08, 0.82 - line.age * 0.72)

            var outerTrace = Path()
            outerTrace.move(to: metrics.origin)
            outerTrace.addLine(to: outerEnd)
            context.stroke(outerTrace, with: .color((line.isClipped ? Color.red : color).opacity(opacity * 0.22)), lineWidth: 2)

            var path = Path()
            path.move(to: metrics.origin)
            path.addLine(to: shrinkingEnd)
            context.stroke(path, with: .color((line.isClipped ? Color.red : color).opacity(opacity)), lineWidth: line.age == 0 ? 3 : 2)
        }
    }

    private func drawLabels(context: GraphicsContext, metrics: PlotMetrics) {
        switch mode {
        case .lissajous:
            let radius = metrics.lissajousRadius
            context.draw(Text("同相").font(.caption.bold()).foregroundStyle(.secondary), at: CGPoint(x: metrics.center.x, y: metrics.center.y - radius - 12), anchor: .bottom)
            context.draw(Text("逆相成分").font(.caption).foregroundStyle(.secondary), at: CGPoint(x: metrics.center.x - radius - 10, y: metrics.center.y), anchor: .trailing)
            context.draw(Text("逆相成分").font(.caption).foregroundStyle(.secondary), at: CGPoint(x: metrics.center.x + radius + 10, y: metrics.center.y), anchor: .leading)
            context.draw(Text("L").font(.caption.bold()).foregroundStyle(.secondary), at: CGPoint(x: metrics.center.x - radius * 0.72, y: metrics.center.y + radius * 0.72 + 10), anchor: .topTrailing)
            context.draw(Text("R").font(.caption.bold()).foregroundStyle(.secondary), at: CGPoint(x: metrics.center.x + radius * 0.72, y: metrics.center.y + radius * 0.72 + 10), anchor: .topLeading)
        case .polarSample, .polarLevel:
            let radius = metrics.polarRadius
            context.draw(Text("同相").font(.caption.bold()).foregroundStyle(.secondary), at: CGPoint(x: metrics.origin.x, y: metrics.origin.y - radius - 12), anchor: .bottom)
            context.draw(Text("L").font(.caption.bold()).foregroundStyle(.secondary), at: CGPoint(x: metrics.origin.x - radius, y: metrics.origin.y + 10), anchor: .top)
            context.draw(Text("R").font(.caption.bold()).foregroundStyle(.secondary), at: CGPoint(x: metrics.origin.x + radius, y: metrics.origin.y + 10), anchor: .top)
            context.draw(Text("45度安全ライン").font(.caption).foregroundStyle(.blue.opacity(0.85)), at: CGPoint(x: metrics.origin.x + radius * 0.52, y: metrics.origin.y - radius * 0.52), anchor: .bottomLeading)
        }
    }

    private func position(for point: VectorScopePoint, metrics: PlotMetrics) -> CGPoint {
        switch mode {
        case .lissajous:
            CGPoint(
                x: metrics.center.x + CGFloat(point.x) * metrics.lissajousRadius,
                y: metrics.center.y - CGFloat(point.y) * metrics.lissajousRadius
            )
        case .polarSample, .polarLevel:
            polarPosition(x: point.x, y: point.y, metrics: metrics)
        }
    }

    private func polarPosition(x: Double, y: Double, metrics: PlotMetrics) -> CGPoint {
        CGPoint(
            x: metrics.origin.x + CGFloat(x) * metrics.polarRadius,
            y: metrics.origin.y - CGFloat(max(0, y)) * metrics.polarRadius
        )
    }

    private struct PlotMetrics {
        let rect: CGRect
        let center: CGPoint
        let origin: CGPoint
        let lissajousRadius: CGFloat
        let polarRadius: CGFloat
    }
}

private struct CorrelationMeterView: View {
    let value: Double?

    var body: some View {
        VStack(spacing: 6) {
            Text("相関")
                .font(.caption.weight(.semibold))

            HStack(alignment: .top, spacing: 6) {
                GeometryReader { proxy in
                    let safeValue = value.map { max(-1, min(1, $0)) }
                    let y = safeValue.map { proxy.size.height * CGFloat((1 - (($0 + 1) / 2))) }
                    ZStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.08))
                        Rectangle()
                            .fill(Color.red.opacity(0.12))
                            .frame(height: proxy.size.height / 2)
                            .offset(y: proxy.size.height / 2)
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(height: 1)
                            .offset(y: proxy.size.height / 2)
                        if let y {
                            Capsule()
                                .fill((safeValue ?? 0) < 0 ? Color.red : Color.blue)
                                .frame(width: 18, height: 8)
                                .offset(y: min(max(y - 4, 0), proxy.size.height - 8))
                        }
                    }
                }
                .frame(width: 34, height: 220)

                VStack(alignment: .leading) {
                    correlationScaleLabel(value: "+1", meaning: "同相")
                    Spacer()
                    correlationScaleLabel(value: "0", meaning: "注意")
                    Spacer()
                    correlationScaleLabel(value: "-1", meaning: "逆相")
                }
                .frame(height: 220)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabel)
        }
    }

    private func correlationScaleLabel(value: String, meaning: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.monospacedDigit())
            Text(meaning)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
    }

    private var accessibilityLabel: String {
        guard let value else {
            return "相関メーター。未測定です。プラス1は同相、0は注意、マイナス1は逆相です。"
        }
        return String(format: "相関メーター。現在値 %.2f。プラス1は同相、0は注意、マイナス1は逆相です。", value)
    }
}

private struct BalanceMeterView: View {
    let value: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("L/Rバランス")
                .font(.caption.weight(.semibold))
            GeometryReader { proxy in
                let safeValue = value.map { max(-1, min(1, $0)) }
                let x = safeValue.map { proxy.size.width * CGFloat(($0 + 1) / 2) }
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.08))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 1)
                        .offset(x: proxy.size.width / 2)
                    if let x {
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: 8, height: 18)
                            .offset(x: min(max(x - 4, 0), proxy.size.width - 8))
                    }
                }
            }
            .frame(height: 18)
            HStack {
                Text("L")
                Spacer()
                Text("中央")
                Spacer()
                Text("R")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
