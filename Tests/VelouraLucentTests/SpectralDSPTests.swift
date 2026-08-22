import Foundation
import Testing
@testable import VelouraLucent

struct SpectralDSPTests {
    @Test
    func percentileMatchesSortedReference() {
        let waveValues: [Float] = (0..<256).map { waveFixtureValue(at: $0) }
        let repeatedPatternValues: [Float] = (0..<513).map { index in
            Float((index * 37) % 97) / 97
        }
        let cases: [[Float]] = [
            [],
            [0.42],
            [3, 1, 2],
            [5, 5, 1, 9, 1, 3, 3],
            waveValues,
            repeatedPatternValues
        ]

        for values in cases {
            for percentile in [0, 1, 12, 20, 50, 75, 99, 100] as [Float] {
                #expect(SpectralDSP.percentile(values, percentile) == referencePercentile(values, percentile))
            }
        }
    }

    @Test
    func percentileMatchesSortedReferenceForRealDenoiseProfileShape() {
        let values = (0..<18_095).map { index in
            Float(abs(sin(Double(index) * 0.017) * 0.62 + cos(Double(index) * 0.031) * 0.18))
        }

        #expect(SpectralDSP.percentile(values, 12) == referencePercentile(values, 12))
    }

    @Test
    func percentileMatchesSortedReferenceForRepeatedValues() {
        let silentBandValues = Array(repeating: Float.zero, count: 18_095)
        let sparseBandValues = Array(repeating: Float.zero, count: 17_500)
            + Array(repeating: Float(0.0003), count: 500)
            + Array(repeating: Float(0.001), count: 95)

        for values in [silentBandValues, sparseBandValues] {
            #expect(SpectralDSP.percentile(values, 12) == referencePercentile(values, 12))
            #expect(SpectralDSP.percentile(values, 50) == referencePercentile(values, 50))
            #expect(SpectralDSP.percentile(values, 99) == referencePercentile(values, 99))
        }
    }

    @Test
    func smallWindowMedianMatchesReferenceImplementation() {
        let values = (0..<64).map { index in
            Float(sin(Double(index) * 0.47) * 0.6 + cos(Double(index) * 0.19) * 0.3)
        }

        for windowSize in [5, 7, 9, 17] {
            let optimized = SpectralDSP.medianFilter(values, windowSize: windowSize)
            let reference = referenceMedianFilter(values, windowSize: windowSize)
            #expect(optimized == reference)
        }
    }

    @Test
    func sparseHalfSpectrumFromSTFTFramesMatchesStoredSpectrogramPath() {
        let signal = (0..<16_384).map { index in
            let time = Double(index) / 48_000
            let base = sin(2 * Double.pi * 880 * time) * 0.18
            let upper = sin(2 * Double.pi * 4_600 * time) * 0.08
            let movement = cos(Double(index) * 0.011) * 0.03
            return Float(base + upper + movement)
        }
        let sourceBins = [180, 246, 318]
        let activeBins = [360, 492, 636]

        let spectrogram = SpectralDSP.stft(signal)
        let stored = SpectralDSP.istftSparseHalfSpectrum(
            frameCount: spectrogram.frameCount,
            fftSize: spectrogram.fftSize,
            hopSize: spectrogram.hopSize,
            originalLength: spectrogram.originalLength,
            leadingPadding: spectrogram.leadingPadding,
            trailingPadding: spectrogram.trailingPadding,
            activeBins: activeBins
        ) { frameIndex, realFrame, imagFrame in
            for (sourceBin, targetBin) in zip(sourceBins, activeBins) {
                let lift = Float(0.04 + Double(targetBin) * 0.00001)
                let sourceIndex = spectrogram.storageIndex(frameIndex: frameIndex, binIndex: sourceBin)
                realFrame[targetBin] += spectrogram.real[sourceIndex] * lift
                imagFrame[targetBin] += spectrogram.imag[sourceIndex] * lift
            }
        }

        let streamed = SpectralDSP.istftSparseHalfSpectrumFromSTFTFrames(
            signal,
            activeBins: activeBins
        ) { _, _, sourceReal, sourceImag, realFrame, imagFrame in
            for (sourceBin, targetBin) in zip(sourceBins, activeBins) {
                let lift = Float(0.04 + Double(targetBin) * 0.00001)
                realFrame[targetBin] += sourceReal[sourceBin] * lift
                imagFrame[targetBin] += sourceImag[sourceBin] * lift
            }
        }

        #expect(streamed == stored)
    }

    private func referencePercentile(_ values: [Float], _ percentile: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(max(Int(Float(sorted.count - 1) * percentile / 100), 0), sorted.count - 1)
        return sorted[position]
    }

    private func waveFixtureValue(at index: Int) -> Float {
        let sine = sin(Double(index) * 0.37) * 0.8
        let cosine = cos(Double(index) * 0.11) * 0.4
        return Float(sine + cosine)
    }

    private func referenceMedianFilter(_ values: [Float], windowSize: Int) -> [Float] {
        guard windowSize > 1, !values.isEmpty else { return values }
        let radius = windowSize / 2
        return values.indices.map { index in
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            return Array(values[lower...upper]).sorted()[((upper - lower) / 2)]
        }
    }
}
