import Foundation
import Testing
@testable import VelouraLucent

struct HighFrequencyGenerationControlTests {
    @Test
    func harmonicRepairKeepsOriginalUltraHighWithoutDullingMusicalUltraAir() {
        let input = makeSignal([
            (11_000, 0.08),
            (17_500, 0.018),
            (22_500, 0.010),
        ])
        let analysis = AnalysisData(
            cutoffFrequency: 12_000,
            dominantHarmonics: [],
            harmonicConfidence: 0.9,
            hasShimmer: false,
            shimmerRatio: 0,
            brightnessRatio: 0.3,
            transientAmount: 0.2,
            noiseAmount: 0,
            rolloffDepth: 0.8,
            airBandEnergyRatio: 0.05,
            artifactBandRatio: 0,
            denoiseEffectMetrics: nil
        )
        let prediction = FoldoverRepairPrediction(
            foldoverMix: 0.32,
            airGainBias: 0.16,
            transientBoostBias: 0,
            harshnessGuard: 0
        )

        let output = CorrectionHarmonicRepair(settings: DenoiseStrength.balanced.settings).process(
            signal: input,
            analysis: analysis,
            prediction: prediction
        )

        #expect(output.frameCount == input.frameCount)
        #expect(output.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        #expect(bandLevelDB(output, lower: 21_000, upper: 24_000) <= bandLevelDB(input, lower: 21_000, upper: 24_000) + 0.25)
        #expect(bandLevelDB(output, lower: 16_000, upper: 20_000) >= bandLevelDB(input, lower: 16_000, upper: 20_000) - 0.50)
    }

    @Test
    func toneShelfDoesNotBoostAboveTwentyOneKilohertz() {
        let input = makeSignal([
            (1_000, 0.08),
            (18_000, 0.012),
            (22_500, 0.010),
        ])
        var settings = MasteringProfile.streaming.settings
        settings.lowShelfGain = 0
        settings.lowMidGain = 0
        settings.presenceGain = 0
        settings.highShelfGain = 1.2

        let output = MasteringProcessor().applyTone(
            signal: input,
            analysis: highDeficitAnalysis,
            settings: settings,
            finishingIntensity: 0.5,
            noiseMeasurements: nil,
            logger: nil
        )

        #expect(bandLevelDB(output, lower: 16_000, upper: 20_000) > bandLevelDB(input, lower: 16_000, upper: 20_000))
        #expect(bandLevelDB(output, lower: 21_000, upper: 24_000) <= bandLevelDB(input, lower: 21_000, upper: 24_000) + 0.25)
    }

    @Test
    func dynamicsAirFollowsCompressedBodyGain() {
        let input = makeSignal([
            (220, 0.32),
            (1_200, 0.12),
            (6_000, 0.06),
            (12_000, 0.035),
        ])
        let aggressiveBand = BandCompressorSettings(
            thresholdDB: -32,
            ratio: 6,
            attackMs: 1,
            releaseMs: 100,
            makeupGainDB: 0
        )
        let output = MasteringProcessor().applyMultibandCompression(
            signal: input,
            analysis: neutralAnalysis,
            settings: MultibandCompressionSettings(
                low: aggressiveBand,
                mid: aggressiveBand,
                high: aggressiveBand
            ),
            dynamicsRetention: 0,
            finishingIntensity: 1,
            logger: nil
        )

        let bodyChange = bandLevelDB(output, lower: 180, upper: 3_000)
            - bandLevelDB(input, lower: 180, upper: 3_000)
        let airChange = bandLevelDB(output, lower: 10_000, upper: 16_000)
            - bandLevelDB(input, lower: 10_000, upper: 16_000)
        #expect(
            abs(airChange - bodyChange) <= 0.40,
            "body change \(bodyChange) dB, air change \(airChange) dB"
        )
    }

    @Test
    func airEnhancerDoesNotGenerateTwentyOneToTwentyFourKilohertz() {
        let input = makeSignal([
            (9_000, 0.045),
            (13_000, 0.018),
        ])
        let summary = MasteringSpectralSummary(
            lowBandLevelDB: -28,
            midBandLevelDB: -10,
            highBandLevelDB: -34,
            harshnessScore: 0
        )

        let output = MasteringAirEnhancer().process(
            signal: input,
            spectralSummary: summary,
            settings: MasteringProfile.streaming.settings,
            finishingIntensity: 1,
            logger: nil
        )

        #expect(output.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        #expect(bandLevelDB(output, lower: 21_000, upper: 24_000) <= bandLevelDB(input, lower: 21_000, upper: 24_000) + 0.50)
        #expect(bandLevelDB(output, lower: 12_000, upper: 16_000) >= bandLevelDB(input, lower: 12_000, upper: 16_000) - 0.25)
    }

    private var neutralAnalysis: MasteringAnalysis {
        MasteringAnalysis(
            integratedLoudness: -18,
            truePeakDBFS: -6,
            lowBandLevelDB: -20,
            midBandLevelDB: -20,
            highBandLevelDB: -20,
            harshnessScore: 0,
            stereoWidth: 0.2
        )
    }

    private var highDeficitAnalysis: MasteringAnalysis {
        MasteringAnalysis(
            integratedLoudness: -18,
            truePeakDBFS: -6,
            lowBandLevelDB: -18,
            midBandLevelDB: -12,
            highBandLevelDB: -30,
            harshnessScore: 0,
            stereoWidth: 0.2
        )
    }

    private func makeSignal(_ components: [(frequency: Double, amplitude: Float)]) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate)
        let channel = (0..<frameCount).map { index -> Float in
            let time = Double(index) / sampleRate
            return components.reduce(0) { partial, component in
                partial + Float(sin(2 * .pi * component.frequency * time)) * component.amplitude
            }
        }
        return AudioSignal(channels: [channel, channel], sampleRate: sampleRate)
    }

    private func bandLevelDB(_ signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let mono = signal.monoMixdown()
        let spectrogram = SpectralDSP.stft(mono)
        let frequencyStep = signal.sampleRate / Double(spectrogram.fftSize)
        let lowerBin = max(0, Int(ceil(lower / frequencyStep)))
        let upperBin = min(spectrogram.binCount - 1, Int(floor(upper / frequencyStep)))
        guard lowerBin <= upperBin else { return -120 }

        var energy = 0.0
        var count = 0
        for frameIndex in 0..<spectrogram.frameCount {
            for binIndex in lowerBin...upperBin {
                let magnitude = Double(spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex))
                energy += magnitude * magnitude
                count += 1
            }
        }
        return 10 * log10(max(energy / Double(max(count, 1)), 1e-12))
    }
}
