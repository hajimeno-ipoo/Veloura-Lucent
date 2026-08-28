import SwiftUI

struct ComparisonVideoRangeView: View {
    let waveform: [WaveformEnvelopeSample]
    let fullDuration: TimeInterval
    let startTime: TimeInterval
    let onStartTimeChange: (TimeInterval) -> Void

    @State private var dragStartTime: TimeInterval?

    private var selectionDuration: TimeInterval {
        min(ComparisonVideoPlan.maximumOutputDuration, fullDuration)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let selectionWidth = proxy.size.width * selectionDuration / fullDuration
                let selectionOffset = proxy.size.width * startTime / fullDuration

                ZStack(alignment: .leading) {
                    ComparisonVideoWaveformShape(samples: waveform)
                        .stroke(.secondary.opacity(0.68), lineWidth: 1)

                    Rectangle()
                        .fill(.primary.opacity(0.12))
                        .frame(width: max(selectionOffset, 0))

                    Rectangle()
                        .fill(.primary.opacity(0.12))
                        .frame(width: max(proxy.size.width - selectionOffset - selectionWidth, 0))
                        .offset(x: selectionOffset + selectionWidth)

                    RoundedRectangle(cornerRadius: 8)
                        .fill(LiquidGlassSegmentedPickerStyle.selectedTint.opacity(0.30))
                        .stroke(
                            LiquidGlassSegmentedPickerStyle.selectedText.opacity(0.78),
                            lineWidth: 1.5
                        )
                        .overlay(alignment: .leading) {
                            selectionHandle
                        }
                        .overlay(alignment: .trailing) {
                            selectionHandle
                        }
                        .frame(width: max(selectionWidth, 6))
                        .offset(x: selectionOffset)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
                .gesture(selectionDrag(width: proxy.size.width))
            }
            .frame(height: 66)

            HStack {
                Text(timeText(startTime))
                Spacer()
                Text(timeText(startTime + selectionDuration))
            }
            .font(.callout.monospacedDigit().weight(.semibold))
        }
        .padding(10)
        .velouraAdaptiveGlass(in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("比較する60秒の範囲")
        .accessibilityValue("\(timeText(startTime))から\(timeText(startTime + selectionDuration))")
        .accessibilityAdjustableAction { direction in
            let offset: TimeInterval = direction == .increment ? 1 : -1
            onStartTimeChange(startTime + offset)
        }
    }

    private var selectionHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LiquidGlassSegmentedPickerStyle.selectedText.opacity(0.82))
            .frame(width: 3, height: 34)
            .padding(.horizontal, 6)
    }

    private func selectionDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard fullDuration > selectionDuration, width > 0 else {
                    onStartTimeChange(0)
                    return
                }
                if dragStartTime == nil {
                    dragStartTime = startTime
                }
                let origin = dragStartTime ?? startTime
                onStartTimeChange(origin + value.translation.width / width * fullDuration)
            }
            .onEnded { _ in
                dragStartTime = nil
            }
    }

    private func timeText(_ seconds: TimeInterval) -> String {
        let value = max(Int(seconds.rounded(.down)), 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
