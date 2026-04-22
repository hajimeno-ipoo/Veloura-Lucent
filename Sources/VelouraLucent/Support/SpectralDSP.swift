import Accelerate
import Foundation

struct Spectrogram {
    var real: [Float]
    var imag: [Float]
    let fftSize: Int
    let hopSize: Int
    let originalLength: Int
    let leadingPadding: Int
    let trailingPadding: Int
    let frameCount: Int

    var binCount: Int { fftSize / 2 + 1 }

    init(
        real: [Float],
        imag: [Float],
        fftSize: Int,
        hopSize: Int,
        originalLength: Int,
        leadingPadding: Int,
        trailingPadding: Int,
        frameCount: Int
    ) {
        self.real = real
        self.imag = imag
        self.fftSize = fftSize
        self.hopSize = hopSize
        self.originalLength = originalLength
        self.leadingPadding = leadingPadding
        self.trailingPadding = trailingPadding
        self.frameCount = frameCount
    }

    func storageIndex(frameIndex: Int, binIndex: Int) -> Int {
        frameIndex * binCount + binIndex
    }

    func magnitude(frameIndex: Int, binIndex: Int) -> Float {
        let index = storageIndex(frameIndex: frameIndex, binIndex: binIndex)
        return hypotf(real[index], imag[index])
    }

    func fillMagnitudes(frameIndex: Int, into magnitudes: inout [Float]) {
        if magnitudes.count != binCount {
            magnitudes = Array(repeating: Float.zero, count: binCount)
        }

        let start = frameIndex * binCount
        for binIndex in 0..<binCount {
            let index = start + binIndex
            magnitudes[binIndex] = hypotf(real[index], imag[index])
        }
    }

    func fillMagnitudeHistory(binIndex: Int, into history: inout [Float]) {
        if history.count != frameCount {
            history = Array(repeating: Float.zero, count: frameCount)
        }

        for frameIndex in 0..<frameCount {
            let index = storageIndex(frameIndex: frameIndex, binIndex: binIndex)
            history[frameIndex] = hypotf(real[index], imag[index])
        }
    }

    mutating func scaleBin(frameIndex: Int, binIndex: Int, by gain: Float) {
        let index = storageIndex(frameIndex: frameIndex, binIndex: binIndex)
        real[index] *= gain
        imag[index] *= gain
    }

    func meanMagnitudes() -> [Float] {
        guard frameCount > 0 else { return [] }
        var means = Array(repeating: Float.zero, count: binCount)
        for frameIndex in 0..<frameCount {
            let start = frameIndex * binCount
            for binIndex in 0..<binCount {
                let index = start + binIndex
                means[binIndex] += hypotf(real[index], imag[index])
            }
        }
        let scale = 1 / Float(frameCount)
        return means.map { $0 * scale }
    }

    func frameAverageMagnitudes() -> [Float] {
        guard frameCount > 0 else { return [] }
        return (0..<frameCount).map { frameIndex in
            var sum: Float = 0
            let start = frameIndex * binCount
            for binIndex in 0..<binCount {
                let index = start + binIndex
                sum += hypotf(real[index], imag[index])
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

        let binCount = fftSize / 2 + 1
        var realFrames = Array(repeating: Float.zero, count: frameCount * binCount)
        var imagFrames = Array(repeating: Float.zero, count: frameCount * binCount)
        let inputImag = Array(repeating: Float.zero, count: fftSize)
        var frame = Array(repeating: Float.zero, count: fftSize)
        var outputReal = Array(repeating: Float.zero, count: fftSize)
        var outputImag = Array(repeating: Float.zero, count: fftSize)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopSize
            frame[0..<fftSize] = workingSource[start..<(start + fftSize)]
            vDSP.multiply(frame, window, result: &frame)

            dft.transform(inputReal: frame, inputImaginary: inputImag, outputReal: &outputReal, outputImaginary: &outputImag)

            let outputStart = frameIndex * binCount
            realFrames[outputStart..<(outputStart + binCount)] = outputReal[0..<binCount]
            imagFrames[outputStart..<(outputStart + binCount)] = outputImag[0..<binCount]
        }

        return Spectrogram(
            real: realFrames,
            imag: imagFrames,
            fftSize: fftSize,
            hopSize: hopSize,
            originalLength: source.count,
            leadingPadding: padding,
            trailingPadding: trailingPadding,
            frameCount: frameCount
        )
    }

    static func istft(_ spectrogram: Spectrogram) -> [Float] {
        let fftSize = spectrogram.fftSize
        let hopSize = spectrogram.hopSize
        return inverseTransform(
            frameCount: spectrogram.frameCount,
            fftSize: fftSize,
            hopSize: hopSize,
            originalLength: spectrogram.originalLength,
            leadingPadding: spectrogram.leadingPadding,
            trailingPadding: spectrogram.trailingPadding
        ) { frameIndex, fullReal, fullImag in
            let inputStart = frameIndex * spectrogram.binCount
            fullReal[0..<spectrogram.binCount] = spectrogram.real[inputStart..<(inputStart + spectrogram.binCount)]
            fullImag[0..<spectrogram.binCount] = spectrogram.imag[inputStart..<(inputStart + spectrogram.binCount)]

            if spectrogram.binCount > 2 {
                for index in 1..<(spectrogram.binCount - 1) {
                    let sourceIndex = inputStart + index
                    fullReal[fftSize - index] = spectrogram.real[sourceIndex]
                    fullImag[fftSize - index] = -spectrogram.imag[sourceIndex]
                }
            }
        }
    }

    static func istft(
        frameCount: Int,
        fftSize: Int,
        hopSize: Int,
        originalLength: Int,
        leadingPadding: Int,
        trailingPadding: Int,
        fillHalfSpectrum: (_ frameIndex: Int, _ binCount: Int, _ real: inout [Float], _ imag: inout [Float]) -> Void
    ) -> [Float] {
        let binCount = fftSize / 2 + 1
        return inverseTransform(
            frameCount: frameCount,
            fftSize: fftSize,
            hopSize: hopSize,
            originalLength: originalLength,
            leadingPadding: leadingPadding,
            trailingPadding: trailingPadding
        ) { frameIndex, fullReal, fullImag in
            for index in fullReal.indices {
                fullReal[index] = .zero
                fullImag[index] = .zero
            }
            fillHalfSpectrum(frameIndex, binCount, &fullReal, &fullImag)
            if binCount > 2 {
                for index in 1..<(binCount - 1) {
                    fullReal[fftSize - index] = fullReal[index]
                    fullImag[fftSize - index] = -fullImag[index]
                }
            }
        }
    }

    static func istftSparseHalfSpectrum(
        frameCount: Int,
        fftSize: Int,
        hopSize: Int,
        originalLength: Int,
        leadingPadding: Int,
        trailingPadding: Int,
        activeBins: [Int],
        fillActiveBins: (_ frameIndex: Int, _ real: inout [Float], _ imag: inout [Float]) -> Void
    ) -> [Float] {
        let binCount = fftSize / 2 + 1
        return inverseTransform(
            frameCount: frameCount,
            fftSize: fftSize,
            hopSize: hopSize,
            originalLength: originalLength,
            leadingPadding: leadingPadding,
            trailingPadding: trailingPadding
        ) { frameIndex, fullReal, fullImag in
            fillActiveBins(frameIndex, &fullReal, &fullImag)
            for binIndex in activeBins where binIndex > 0 && binIndex < binCount - 1 {
                fullReal[fftSize - binIndex] = fullReal[binIndex]
                fullImag[fftSize - binIndex] = -fullImag[binIndex]
            }
        } cleanupFrame: { fullReal, fullImag in
            for binIndex in activeBins {
                fullReal[binIndex] = .zero
                fullImag[binIndex] = .zero
                if binIndex > 0 && binIndex < binCount - 1 {
                    let mirrorIndex = fftSize - binIndex
                    fullReal[mirrorIndex] = .zero
                    fullImag[mirrorIndex] = .zero
                }
            }
        }
    }

    private static func inverseTransform(
        frameCount: Int,
        fftSize: Int,
        hopSize: Int,
        originalLength: Int,
        leadingPadding: Int,
        trailingPadding: Int,
        prepareFrame: (_ frameIndex: Int, _ fullReal: inout [Float], _ fullImag: inout [Float]) -> Void,
        cleanupFrame: ((_ fullReal: inout [Float], _ fullImag: inout [Float]) -> Void)? = nil
    ) -> [Float] {
        let outputLength = max(
            originalLength + leadingPadding + trailingPadding,
            fftSize + max(0, frameCount - 1) * hopSize
        )
        let resources = resourceCache.resources(for: fftSize)
        let window = resources.window
        let dft = resources.inverse
        var output = Array(repeating: Float.zero, count: outputLength)
        var windowSums = Array(repeating: Float.zero, count: outputLength)
        var fullReal = Array(repeating: Float.zero, count: fftSize)
        var fullImag = Array(repeating: Float.zero, count: fftSize)
        var outputReal = Array(repeating: Float.zero, count: fftSize)
        var outputImag = Array(repeating: Float.zero, count: fftSize)
        var frame = Array(repeating: Float.zero, count: fftSize)
        let inverseScale = 1 / Float(fftSize)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopSize
            prepareFrame(frameIndex, &fullReal, &fullImag)

            dft.transform(inputReal: fullReal, inputImaginary: fullImag, outputReal: &outputReal, outputImaginary: &outputImag)
            cleanupFrame?(&fullReal, &fullImag)

            vDSP.multiply(inverseScale, outputReal, result: &frame)
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

        let start = min(leadingPadding, output.count)
        let end = min(start + originalLength, output.count)
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
        if windowSize <= 17 {
            return smallWindowMedianFilter(values, windowSize: windowSize)
        }

        let radius = windowSize / 2
        return values.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            return Array(values[lower...upper]).sorted()[((upper - lower) / 2)]
        }
    }

    private static func smallWindowMedianFilter(_ values: [Float], windowSize: Int) -> [Float] {
        let radius = windowSize / 2
        var output = Array(repeating: Float.zero, count: values.count)
        var windowValues = Array(repeating: Float.zero, count: min(windowSize, values.count))

        for index in values.indices {
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            let count = upper - lower + 1

            if windowValues.count != count {
                windowValues = Array(repeating: Float.zero, count: count)
            }

            for offset in 0..<count {
                windowValues[offset] = values[lower + offset]
            }
            windowValues.sort()
            output[index] = windowValues[(upper - lower) / 2]
        }

        return output
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
