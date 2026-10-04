import Foundation

/// Processes only the nonlinear delta at 4x rate. Centered FIRs keep the original
/// sample positions, while adding the delta back leaves the linear input intact.
enum NonlinearOversampling {
    private static let factor = 4
    private static let radius = 32
    private static let kernel: [Float] = {
        let halfLength = radius * factor
        let cutoff = 0.46 / Double(factor)
        let values = (-halfLength...halfLength).map { offset -> Double in
            let t = Double(offset)
            let sinc = offset == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * t) / (.pi * t)
            let window = 0.42 + 0.5 * cos(.pi * t / Double(halfLength))
                + 0.08 * cos(2 * .pi * t / Double(halfLength))
            return sinc * window
        }
        let sum = values.reduce(0, +)
        return values.map { Float($0 / sum) }
    }()

    private static let phases: [[Float]] = (0..<factor).map { phase in
        let halfLength = radius * factor
        let weights = (-radius...radius).map { offset -> Float in
            let index = phase - offset * factor + halfLength
            return kernel.indices.contains(index) ? kernel[index] : 0
        }
        let sum = weights.reduce(0, +)
        return weights.map { $0 / sum }
    }

    static func process(
        _ samples: [Float],
        transform: (Float) -> Float
    ) -> [Float] {
        guard samples.count > 1 else { return samples.map(transform) }
        let padding = radius * 2
        let period = (samples.count - 1) * 2
        let padded = (-padding..<(samples.count + padding)).map { index -> Float in
            let wrapped = ((index % period) + period) % period
            return samples[wrapped < samples.count ? wrapped : period - wrapped]
        }
        let halfLength = radius * factor
        let deltaCount = (samples.count - 1) * factor + 1 + halfLength * 2
        var delta = Array(repeating: Float.zero, count: deltaCount)
        for index in delta.indices {
            let position = index - halfLength
            // Floor division also handles the reflected samples before time zero.
            let phase = ((position % factor) + factor) % factor
            let base = (position - phase) / factor + padding - radius
            let weights = phases[phase]
            var interpolated: Float = 0
            for tap in weights.indices {
                interpolated += padded[base + tap] * weights[tap]
            }
            delta[index] = transform(interpolated) - interpolated
        }
        var output = samples
        for index in output.indices {
            let start = index * factor
            var filteredDelta: Float = 0
            for tap in kernel.indices {
                filteredDelta += delta[start + tap] * kernel[tap]
            }
            output[index] += filteredDelta
        }
        return output
    }
}
