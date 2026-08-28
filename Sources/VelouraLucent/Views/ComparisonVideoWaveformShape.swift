import SwiftUI

struct ComparisonVideoWaveformShape: Shape {
    let samples: [WaveformEnvelopeSample]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !samples.isEmpty, rect.width > 0, rect.height > 0 else { return path }
        let centerY = rect.midY
        let width = rect.width / CGFloat(samples.count)
        for (index, sample) in samples.enumerated() {
            let x = rect.minX + (CGFloat(index) + 0.5) * width
            let minimum = min(max(CGFloat(sample.minimum), -1), 1)
            let maximum = min(max(CGFloat(sample.maximum), -1), 1)
            path.move(to: CGPoint(x: x, y: centerY - maximum * rect.height * 0.46))
            path.addLine(to: CGPoint(x: x, y: centerY - minimum * rect.height * 0.46))
        }
        return path
    }
}
