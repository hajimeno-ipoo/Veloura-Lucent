import Foundation
import SwiftUI

struct WaveformTimeRulerView: View {
    let duration: TimeInterval

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.secondary.opacity(0.18))
                    .frame(height: 1)

                ForEach(0..<5, id: \.self) { index in
                    let progress = Double(index) / 4
                    let tickX = min(width * progress, max(width - 1, 0))
                    let labelX = min(max(tickX, 32), max(width - 32, 32))

                    Rectangle()
                        .fill(.secondary.opacity(0.42))
                        .frame(width: 1, height: 5)
                        .offset(x: tickX)

                    Text(waveformTimeText(duration * progress))
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
