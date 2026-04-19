import Accelerate
import Foundation

struct Spectrogram {
    var real: [[Float]]
    var imag: [[Float]]
    let fftSize: Int
    let hopSize: Int
    let originalLength: Int
    let leadingPadding: Int
    let trailingPadding: Int

    var frameCount: Int { real.count }
    var binCount: Int { fftSize / 2 + 1 }

    func magnitudes() -> [[Float]] {
        zip(real, imag).map { realFrame, imagFrame in
            zip(realFrame, imagFrame).map { hypotf($0, $1) }
        }
    }

    func magnitude(frameIndex: Int, binIndex: Int) -> Float {
        hypotf(real[frameIndex][binIndex], imag[frameIndex][binIndex])
    }

    func meanMagnitudes() -> [Float] {
        guard frameCount > 0 else { return [] }
        var means = Array(repeating: Float.zero, count: binCount)
        for frameIndex in 0..<frameCount {
            for binIndex in 0..<binCount {
                means[binIndex] += magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
        }
        let scale = 1 / Float(frameCount)
        return means.map { $0 * scale }
    }

    func frameAverageMagnitudes() -> [Float] {
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { frameIndex in
            var sum: Float = 0
            for binIndex in 0..<binCount {
                sum += magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            return sum / Float(binCount)
        }
    }
}

enum SpectralDSP {
    static let fftSize = 2048
    static let hopSize = 512
    private static let resourceCache = FFTResourceCache()

    static func stft(_ signal: [Float], fftSize: Int = fftSize, hopSize: Int = hopSize) -> Spectrogram {
        let source = signal.isEmpty ? [Float.zero] : signal
        let padding = fftSize / 2
        let paddedSource = reflectPad(signal: source, count: padding)
        let remainder = max(0, (paddedSource.count - fftSize) % hopSize)
        let trailingPadding = remainder == 0 ? 0 : (hopSize - remainder)
        let workingSource = trailingPadding > 0 ? paddedSource + Array(repeating: Float.zero, count: trailingPadding) : paddedSource
        let frameCount = max(1, Int(ceil(Double(max(workingSource.count - fftSize, 0)) / Double(hopSize))) + 1)
        let resources = resourceCache.resources(for: fftSize)
        let window = resources.window
        let dft = resources.forward

        var realFrames: [[Float]] = []
        var imagFrames: [[Float]] = []
        realFrames.reserveCapacity(frameCount)
        imagFrames.reserveCapacity(frameCount)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopSize
            var frame = Array(repeating: Float.zero, count: fftSize)
            if start < workingSource.count {
                let available = min(fftSize, workingSource.count - start)
                frame[0..<available] = workingSource[start..<(start + available)]
            }
            vDSP.multiply(frame, window, result: &frame)

            let inputImag = Array(repeating: Float.zero, count: fftSize)
            var outputReal = Array(repeating: Float.zero, count: fftSize)
            var outputImag = Array(repeating: Float.zero, count: fftSize)
            dft.transform(inputReal: frame, inputImaginary: inputImag, outputReal: &outputReal, outputImaginary: &outputImag)

            realFrames.append(Array(outputReal[0...(fftSize / 2)]))
            imagFrames.append(Array(outputImag[0...(fftSize / 2)]))
        }

        return Spectrogram(
            real: realFrames,
            imag: imagFrames,
            fftSize: fftSize,
            hopSize: hopSize,
            originalLength: source.count,
            leadingPadding: padding,
            trailingPadding: trailingPadding
        )
    }

    static func istft(_ spectrogram: Spectrogram) -> [Float] {
        let fftSize = spectrogram.fftSize
        let hopSize = spectrogram.hopSize
        let outputLength = max(
            spectrogram.originalLength + spectrogram.leadingPadding + spectrogram.trailingPadding,
            fftSize + max(0, spectrogram.frameCount - 1) * hopSize
        )
        let resources = resourceCache.resources(for: fftSize)
        let window = resources.window
        let dft = resources.inverse

        var output = Array(repeating: Float.zero, count: outputLength)
        var windowSums = Array(repeating: Float.zero, count: outputLength)

        for frameIndex in 0..<spectrogram.frameCount {
            let start = frameIndex * hopSize
            var fullReal = Array(repeating: Float.zero, count: fftSize)
            var fullImag = Array(repeating: Float.zero, count: fftSize)
            let halfReal = spectrogram.real[frameIndex]
            let halfImag = spectrogram.imag[frameIndex]
            fullReal[0..<halfReal.count] = halfReal[0..<halfReal.count]
            fullImag[0..<halfImag.count] = halfImag[0..<halfImag.count]

            if halfReal.count > 2 {
                for index in 1..<(halfReal.count - 1) {
                    fullReal[fftSize - index] = halfReal[index]
                    fullImag[fftSize - index] = -halfImag[index]
                }
            }

            var outputReal = Array(repeating: Float.zero, count: fftSize)
            var outputImag = Array(repeating: Float.zero, count: fftSize)
            dft.transform(inputReal: fullReal, inputImaginary: fullImag, outputReal: &outputReal, outputImaginary: &outputImag)

            var frame = outputReal.map { $0 / Float(fftSize) }
            vDSP.multiply(frame, window, result: &frame)
            let available = min(fftSize, outputLength - start)
            guard available > 0 else { continue }
            for index in 0..<available {
                output[start + index] += frame[index]
                windowSums[start + index] += window[index] * window[index]
            }
        }

        for index in output.indices where windowSums[index] > 1e-6 {
            output[index] /= windowSums[index]
        }

        let start = min(spectrogram.leadingPadding, output.count)
        let end = min(start + spectrogram.originalLength, output.count)
        return Array(output[start..<end])
    }

    static func amplitudeToDecibels(_ values: [Float]) -> [Float] {
        let reference = max(values.max() ?? 1e-6, 1e-6)
        return values.map { 20 * log10f(max($0, 1e-6) / reference) }
    }

    static func percentile(_ values: [Float], _ percentile: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(max(Int(Float(sorted.count - 1) * percentile / 100), 0), sorted.count - 1)
        return sorted[position]
    }

    static func movingAverage(_ values: [Float], windowSize: Int) -> [Float] {
        guard windowSize > 1, !values.isEmpty else { return values }
        let radius = windowSize / 2
        return values.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            let slice = values[lower...upper]
            return slice.reduce(0, +) / Float(slice.count)
        }
    }

    static func medianFilter(_ values: [Float], windowSize: Int) -> [Float] {
        guard windowSize > 1, !values.isEmpty else { return values }
        let radius = windowSize / 2
        return values.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            return Array(values[lower...upper]).sorted()[((upper - lower) / 2)]
        }
    }

    static func spectralCentroid(_ spectrum: [Float], sampleRate: Double, fftSize: Int) -> Double {
        let frequencyStep = sampleRate / Double(fftSize)
        let numerator = spectrum.enumerated().reduce(0.0) { partial, pair in
            partial + Double(pair.offset) * frequencyStep * Double(pair.element)
        }
        let denominator = max(Double(spectrum.reduce(0, +)), 1e-9)
        return numerator / denominator
    }

    static func peak(_ signal: [Float]) -> Float {
        signal.map { abs($0) }.max() ?? 0
    }

    static func lowPass(_ signal: [Float], cutoff: Double, sampleRate: Double) -> [Float] {
        guard signal.count > 1 else { return signal }
        let rc = 1.0 / (2.0 * Double.pi * cutoff)
        let dt = 1.0 / sampleRate
        let alpha = Float(dt / (rc + dt))
        var output = Array(repeating: Float.zero, count: signal.count)
        output[0] = signal[0]
        for index in 1..<signal.count {
            output[index] = output[index - 1] + alpha * (signal[index] - output[index - 1])
        }
        return output
    }

    static func highPass(_ signal: [Float], cutoff: Double, sampleRate: Double) -> [Float] {
        guard signal.count > 1 else { return signal }
        let rc = 1.0 / (2.0 * Double.pi * cutoff)
        let dt = 1.0 / sampleRate
        let alpha = Float(rc / (rc + dt))
        var output = Array(repeating: Float.zero, count: signal.count)
        output[0] = signal[0]
        for index in 1..<signal.count {
            output[index] = alpha * (output[index - 1] + signal[index] - signal[index - 1])
        }
        return output
    }

    fileprivate static func sqrtWindow(count: Int) -> [Float] {
        let hann = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: count, isHalfWindow: false)
        return hann.map { sqrtf(max($0, 0)) }
    }

    private static func reflectPad(signal: [Float], count: Int) -> [Float] {
        guard count > 0, signal.count > 1 else { return signal }
        let prefix = (0..<count).map { index in
            signal[min(signal.count - 1, count - index)]
        }
        let suffix = (0..<count).map { index in
            signal[max(0, signal.count - 2 - index)]
        }
        return prefix + signal + suffix.reversed()
    }
}

private struct FFTResources {
    let forward: vDSP.DiscreteFourierTransform<Float>
    let inverse: vDSP.DiscreteFourierTransform<Float>
    let window: [Float]
}

private final class FFTResourceCache: @unchecked Sendable {
    private var cache: [Int: FFTResources] = [:]
    private let lock = NSLock()

    func resources(for fftSize: Int) -> FFTResources {
        lock.lock()
        defer { lock.unlock() }

        if let cached = cache[fftSize] {
            return cached
        }

        let resources = FFTResources(
            forward: try! vDSP.DiscreteFourierTransform<Float>(
                count: fftSize,
                direction: .forward,
                transformType: .complexComplex,
                ofType: Float.self
            ),
            inverse: try! vDSP.DiscreteFourierTransform<Float>(
                count: fftSize,
                direction: .inverse,
                transformType: .complexComplex,
                ofType: Float.self
            ),
            window: SpectralDSP.sqrtWindow(count: fftSize)
        )
        cache[fftSize] = resources
        return resources
    }
}
