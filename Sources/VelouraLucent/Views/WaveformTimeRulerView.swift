import Foundation
import SwiftUI

struct WaveformViewport: Equatable {
    private static let minimumZoomScale = 1.0
    private static let zoomButtonStep = 0.1
    private static let comparisonTolerance = 0.000_001

    private(set) var zoomScale = minimumZoomScale
    private(set) var startProgress = 0.0

    var visibleProgressSpan: Double {
        1 / zoomScale
    }

    var endProgress: Double {
        min(startProgress + visibleProgressSpan, 1)
    }

    static func maximumZoomScale(
        sampleCount: Int,
        displayWidth: Double
    ) -> Double {
        guard sampleCount > 1, displayWidth > 1 else {
            return minimumZoomScale
        }
        return max(
            minimumZoomScale,
            Double(sampleCount) / displayWidth
        )
    }

    var canZoomOut: Bool {
        zoomScale > Self.minimumZoomScale + Self.comparisonTolerance
    }

    func canZoomIn(maximumZoomScale: Double) -> Bool {
        zoomScale < clampedMaximumZoomScale(maximumZoomScale) - Self.comparisonTolerance
    }

    func zoomPosition(maximumZoomScale: Double) -> Double {
        let maximum = clampedMaximumZoomScale(maximumZoomScale)
        guard maximum > Self.minimumZoomScale else { return 0 }
        return clamped(log(zoomScale) / log(maximum))
    }

    mutating func zoomIn(
        maximumZoomScale: Double,
        centeredAt progress: Double
    ) {
        setZoomPosition(
            zoomPosition(maximumZoomScale: maximumZoomScale) + Self.zoomButtonStep,
            maximumZoomScale: maximumZoomScale,
            centeredAt: progress
        )
    }

    mutating func zoomOut(
        maximumZoomScale: Double,
        centeredAt progress: Double
    ) {
        setZoomPosition(
            zoomPosition(maximumZoomScale: maximumZoomScale) - Self.zoomButtonStep,
            maximumZoomScale: maximumZoomScale,
            centeredAt: progress
        )
    }

    mutating func setZoomPosition(
        _ position: Double,
        maximumZoomScale: Double,
        centeredAt progress: Double
    ) {
        let maximum = clampedMaximumZoomScale(maximumZoomScale)
        guard maximum > Self.minimumZoomScale else {
            reset()
            return
        }
        setZoomScale(
            pow(maximum, clamped(position)),
            maximumZoomScale: maximum,
            centeredAt: progress
        )
    }

    mutating func constrain(
        maximumZoomScale: Double,
        centeredAt progress: Double
    ) {
        setZoomScale(
            zoomScale,
            maximumZoomScale: maximumZoomScale,
            centeredAt: progress
        )
    }

    mutating func reset() {
        zoomScale = Self.minimumZoomScale
        startProgress = 0
    }

    mutating func followPlayback(_ progress: Double) {
        guard canZoomOut else { return }

        let clampedProgress = clamped(progress)
        let span = visibleProgressSpan
        let maximumStart = max(1 - span, 0)
        startProgress = min(
            max(clampedProgress - span / 2, 0),
            maximumStart
        )
    }

    mutating func pan(
        from initialStartProgress: Double,
        horizontalTranslationFraction: Double
    ) {
        guard canZoomOut else { return }

        let maximumStart = max(1 - visibleProgressSpan, 0)
        startProgress = min(
            max(
                initialStartProgress
                    - horizontalTranslationFraction * visibleProgressSpan,
                0
            ),
            maximumStart
        )
    }

    mutating func moveVisibleRange(byVisibleSpanFraction fraction: Double) {
        guard canZoomOut else { return }

        let maximumStart = max(1 - visibleProgressSpan, 0)
        startProgress = min(
            max(startProgress + fraction * visibleProgressSpan, 0),
            maximumStart
        )
    }

    func globalProgress(forLocalProgress progress: Double) -> Double {
        clamped(startProgress + clamped(progress) * visibleProgressSpan)
    }

    func localProgress(forGlobalProgress progress: Double) -> Double {
        clamped((clamped(progress) - startProgress) / visibleProgressSpan)
    }

    func contains(_ progress: Double) -> Bool {
        let clampedProgress = clamped(progress)
        return clampedProgress >= startProgress && clampedProgress <= endProgress
    }

    private mutating func setZoomScale(
        _ newScale: Double,
        maximumZoomScale: Double,
        centeredAt progress: Double
    ) {
        let maximum = clampedMaximumZoomScale(maximumZoomScale)
        zoomScale = min(max(newScale, Self.minimumZoomScale), maximum)
        let span = visibleProgressSpan
        let maximumStart = max(1 - span, 0)
        startProgress = min(
            max(clamped(progress) - span / 2, 0),
            maximumStart
        )
    }

    private func clamped(_ progress: Double) -> Double {
        min(max(progress, 0), 1)
    }

    private func clampedMaximumZoomScale(_ maximumZoomScale: Double) -> Double {
        max(maximumZoomScale, Self.minimumZoomScale)
    }
}

struct WaveformTimeRulerView: View {
    private static let intervals: [TimeInterval] = [
        0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5,
        1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 900, 1_800, 3_600
    ]

    let duration: TimeInterval
    let viewport: WaveformViewport

    var body: some View {
        Canvas { context, size in
            let start = duration * viewport.startProgress
            let end = duration * viewport.endProgress
            let span = end - start
            guard span.isFinite, span > 0, size.width > 0 else { return }

            let interval = Self.intervals.first { interval in
                let label = context.resolve(timeLabel(end, interval: interval))
                let labelWidth = label.measure(in: size).width
                return interval / span * size.width >= labelWidth + 12
            } ?? 3_600

            // Anchor ticks to the start of the audio, so panning only moves their positions.
            let first = Int(ceil(start / interval - 1e-9))
            let last = Int(floor(end / interval + 1e-9))
            guard first <= last else { return }

            let baselineY = size.height - 1
            var marks = Path()
            marks.move(to: CGPoint(x: 0, y: baselineY))
            marks.addLine(to: CGPoint(x: size.width, y: baselineY))
            var lastLabelEnd = -CGFloat.infinity

            for index in first...last {
                let seconds = Double(index) * interval
                let progress = viewport.localProgress(forGlobalProgress: seconds / duration)
                let x = progress * size.width
                marks.move(to: CGPoint(x: x, y: baselineY))
                marks.addLine(to: CGPoint(x: x, y: baselineY - 8))

                let label = context.resolve(timeLabel(seconds, interval: interval))
                let labelWidth = label.measure(in: size).width
                let left = min(max(x - labelWidth / 2, 0), size.width - labelWidth)
                guard left >= 0, left >= lastLabelEnd + 4 else { continue }
                context.draw(label, at: CGPoint(x: left, y: baselineY - 10), anchor: .bottomLeading)
                lastLabelEnd = left + labelWidth
            }

            context.stroke(marks, with: .color(.primary.opacity(0.65)), lineWidth: 1)
        }
        .frame(height: 28)
        .accessibilityHidden(true)
    }

    private func timeLabel(_ seconds: TimeInterval, interval: TimeInterval) -> Text {
        let time: String
        if interval >= 1 {
            time = waveformTimeText(seconds.rounded())
        } else {
            let digits = Int(ceil(-log10(interval)))
            let scale = Int(pow(10, Double(digits)))
            let units = Int((seconds * Double(scale)).rounded())
            let whole = waveformTimeText(Double(units / scale))
            let fraction = String(format: "%0*d", digits, units % scale)
            time = "\(whole).\(fraction)"
        }
        return Text(time)
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.primary)
    }
}

struct WaveformZoomControls: View {
    @Binding var viewport: WaveformViewport
    let centerProgress: Double
    let maximumZoomScale: Double

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                zoomButton(
                    title: "波形を縮小",
                    systemImage: "minus",
                    isDisabled: !viewport.canZoomOut
                ) {
                    viewport.zoomOut(
                        maximumZoomScale: maximumZoomScale,
                        centeredAt: centerProgress
                    )
                }

                Slider(
                    value: Binding(
                        get: {
                            viewport.zoomPosition(
                                maximumZoomScale: maximumZoomScale
                            )
                        },
                        set: { position in
                            viewport.setZoomPosition(
                                position,
                                maximumZoomScale: maximumZoomScale,
                                centeredAt: centerProgress
                            )
                        }
                    ),
                    in: 0 ... 1
                )
                .tint(LiquidGlassSegmentedPickerStyle.sliderTint)
                .frame(width: 120)
                .disabled(maximumZoomScale <= 1)
                .help("波形の表示範囲を連続的に調整します")
                .accessibilityLabel("波形の拡大率")
                .accessibilityValue(
                    AppLanguageSettings.format("%.1f倍", viewport.zoomScale)
                )

                zoomButton(
                    title: "波形を拡大",
                    systemImage: "plus",
                    isDisabled: !viewport.canZoomIn(
                        maximumZoomScale: maximumZoomScale
                    )
                ) {
                    viewport.zoomIn(
                        maximumZoomScale: maximumZoomScale,
                        centeredAt: centerProgress
                    )
                }

                Divider()
                    .frame(height: 20)

                Button {
                    viewport.reset()
                } label: {
                    Label("全体表示", systemImage: "arrow.left.and.right")
                        .font(.callout)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 32)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewport.canZoomOut)
                .help("波形全体を表示")
            }
            .padding(4)
            .velouraAdaptiveGlass(in: .capsule, interactive: true)
        }
        .fixedSize()
        .onChange(of: maximumZoomScale) {
            viewport.constrain(
                maximumZoomScale: maximumZoomScale,
                centeredAt: centerProgress
            )
        }
    }

    private func zoomButton(
        title: String,
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .glassEffect(.clear.interactive(), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(AppLanguageSettings.string(title))
        .help(AppLanguageSettings.string(title))
    }
}

func waveformTimeText(_ duration: TimeInterval) -> String {
    let totalSeconds = max(Int(duration.rounded(.down)), 0)
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}
