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
    let duration: TimeInterval
    let viewport: WaveformViewport

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.secondary.opacity(0.18))
                    .frame(height: 1)

                ForEach(0..<5, id: \.self) { index in
                    let localProgress = Double(index) / 4
                    let globalProgress = viewport.globalProgress(
                        forLocalProgress: localProgress
                    )
                    let tickX = min(width * localProgress, max(width - 1, 0))
                    let labelX = min(max(tickX, 32), max(width - 32, 32))

                    Rectangle()
                        .fill(.secondary.opacity(0.42))
                        .frame(width: 1, height: 5)
                        .offset(x: tickX)

                    Text(waveformTimeText(duration * globalProgress))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 64)
                        .position(x: labelX, y: 18)
                }
            }
        }
        .frame(height: 32)
        .accessibilityHidden(true)
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
                    String(format: "%.1f倍", viewport.zoomScale)
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
        .accessibilityLabel(title)
        .help(title)
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
