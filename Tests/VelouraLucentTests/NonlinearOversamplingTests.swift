import Foundation
import Testing
@testable import VelouraLucent

struct NonlinearOversamplingTests {
    @Test
    func saturationRemovesFoldedThirdHarmonicAtProcessingRates() {
        for rate in [44_100.0, 48_000.0] {
            let input = tone(frequency: 11_000, amplitude: 0.8, rate: rate)
            let amount: Float = 0.09
            let drive = 1 + amount * 2.8
            let mix = amount * 0.75
            let old = input.map { $0 * (1 - mix) + tanhf($0 * drive) * mix }
            let output = MasteringProcessor().applySaturation(
                signal: AudioSignal(channels: [input], sampleRate: rate), amount: amount
            ).channels[0]
            let foldedFrequency = rate - 33_000
            let oldLevel = level(old, rate: rate, frequency: foldedFrequency)
            let newLevel = level(output, rate: rate, frequency: foldedFrequency)
            #expect(newLevel < oldLevel - 40)
            #expect(abs(level(output, rate: rate, frequency: 11_000) - level(old, rate: rate, frequency: 11_000)) < 0.1)
        }
    }

    @Test
    func fourTimesRateSuppressesHigherOrderFoldback() {
        // At 2x, the 85 kHz fifth harmonic of 17 kHz folds to 11 kHz.
        // A third-harmonic-only test would not detect that regression.
        let samples = tone(frequency: 17_000, amplitude: 0.8, rate: 48_000)
        let signal = AudioSignal(channels: [samples], sampleRate: 48_000)
        let output = MasteringProcessor().applySaturation(signal: signal, amount: 0.09)
        #expect(level(output.channels[0], rate: 48_000, frequency: 11_000) < -100)
    }

    @Test
    func intentionalLowFrequencyHarmonicsRemain() {
        let input = tone(frequency: 1_000, amplitude: 0.8, rate: 48_000)
        let original = input.map { tanhf($0 * 2.8) }
        let output = NonlinearOversampling.process(input) { tanhf($0 * 2.8) }
        for frequency in [1_000.0, 3_000.0, 5_000.0] {
            #expect(abs(level(output, rate: 48_000, frequency: frequency) - level(original, rate: 48_000, frequency: frequency)) < 0.1)
        }
    }

    @Test
    func repairAndAirDoNotRetainFoldedFifteenKilohertz() {
        let samples = tone(frequency: 11_000, amplitude: 0.2, rate: 48_000)
        let input = AudioSignal(channels: [samples], sampleRate: 48_000)
        let analysis = AnalysisData(
            cutoffFrequency: 12_000, dominantHarmonics: [], harmonicConfidence: 0.9,
            hasShimmer: false, shimmerRatio: 0, brightnessRatio: 0.3, transientAmount: 0.2,
            noiseAmount: 0, rolloffDepth: 0.8, airBandEnergyRatio: 0.05,
            artifactBandRatio: 0, denoiseEffectMetrics: nil
        )
        let repair = CorrectionHarmonicRepair(settings: DenoiseStrength.balanced.settings).process(
            signal: input, analysis: analysis,
            prediction: FoldoverRepairPrediction(foldoverMix: 0.32, airGainBias: 0.16, transientBoostBias: 0, harshnessGuard: 0)
        )
        let settings = MasteringProfile.streaming.settings
        let air = MasteringAirEnhancer().process(
            signal: input,
            spectralSummary: MasteringSpectralSummary(lowBandLevelDB: -28, midBandLevelDB: -10, highBandLevelDB: -34, harshnessScore: 0),
            settings: settings, finishingIntensity: settings.finishingIntensity, logger: nil
        )
        for output in [repair, air] {
            #expect(level(output.channels[0], rate: 48_000, frequency: 15_000) < -100)
            #expect(output.frameCount == input.frameCount)
        }
    }

    @Test
    func identityZeroMixAndConstantSignalsKeepTheirValues() {
        let samples: [Float] = [0.1, -0.7, 0.3, 0.9, -0.2]
        #expect(NonlinearOversampling.process(samples) { $0 } == samples)
        #expect(MasteringProcessor().applySaturation(signal: AudioSignal(channels: [samples], sampleRate: 48_000), amount: 0).channels[0] == samples)
        let constant = Array(repeating: Float(0.4), count: 129)
        let output = NonlinearOversampling.process(constant) { tanhf($0 * 2.8) }
        #expect(output.allSatisfy { abs($0 - tanhf(0.4 * 2.8)) < 2e-6 })
    }

    @Test
    func shortInputsAndCenteredImpulseKeepLengthAndPosition() {
        for samples: [Float] in [[], [0.5], [0.2, -0.4], [0.1, 0.2, -0.4]] {
            let output = NonlinearOversampling.process(samples) { tanhf($0) }
            #expect(output.count == samples.count)
            #expect(output.allSatisfy { $0.isFinite })
        }
        var impulse = Array(repeating: Float.zero, count: 257)
        impulse[128] = 0.8
        let output = NonlinearOversampling.process(impulse) { tanhf($0 * 2.8) }
        #expect(output.indices.max(by: { abs(output[$0]) < abs(output[$1]) }) == 128)
        for offset in 1...64 {
            #expect(abs(output[128 - offset] - output[128 + offset]) < 2e-6)
        }
    }
}

private func tone(frequency: Double, amplitude: Float, rate: Double) -> [Float] {
    (0..<Int(rate * 0.2)).map { Float(sin(2 * .pi * frequency * Double($0) / rate)) * amplitude }
}

private func level(_ samples: [Float], rate: Double, frequency: Double) -> Double {
    let start = samples.count / 4, end = samples.count * 3 / 4
    var real = 0.0, imaginary = 0.0
    for index in start..<end {
        let phase = 2 * Double.pi * frequency * Double(index) / rate
        real += Double(samples[index]) * cos(phase)
        imaginary += Double(samples[index]) * sin(phase)
    }
    return 20 * log10(max(2 * hypot(real, imaginary) / Double(end - start), 1e-15))
}
