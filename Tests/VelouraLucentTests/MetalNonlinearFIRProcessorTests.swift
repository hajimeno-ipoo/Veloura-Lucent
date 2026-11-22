import Foundation
import Testing
@testable import VelouraLucent

struct MetalNonlinearFIRProcessorTests {
    @Test
    func bothFIRCommandsPreserveCPUExcitationAndFinalSaturation() throws {
        // Include high frequencies and non-periodic content; compare actual CPU
        // nonlinear functions, rather than a GPU identity or a constant signal.
        let samples = (0..<9_601).map { index -> Float in
            let time = Double(index) / 48_000
            return Float(sin(2 * .pi * 173 * time) * 0.22
                + sin(2 * .pi * 11_300 * time) * 0.05
                + cos(Double(index * index) * 0.002) * 0.013)
        }
        let transforms: [(Float) -> Float] = [
            { tanhf($0 * 2.8) - tanhf($0 * 1.1) },
            { tanhf($0 * 0.98) }
        ]
        for transform in transforms {
            let expected = NonlinearOversampling.process(samples, transform: transform)
            let actual = try #require(
                NonlinearOversampling.processUsingMetal(samples, transform: transform),
                "Both new FIR Metal commands must complete; CPU fallback cannot satisfy this test"
            )
            #expect(actual.map(\.bitPattern) == expected.map(\.bitPattern))
        }
    }

    @Test
    func shortInputsRetainOriginalCPUBehavior() {
        let shortSignal = (0..<4_095).map { Float(sin(Double($0) * 0.13) * 0.4) }
        for samples: [Float] in [[], [0.5], Array(shortSignal.prefix(33)), shortSignal] {
            let expected = NonlinearOversampling.process(samples) { tanhf($0 * 0.98) }
            let actual = NonlinearOversampling.process(samples, useMetal: true) { tanhf($0 * 0.98) }
            #expect(actual.map(\.bitPattern) == expected.map(\.bitPattern))
            if samples.count < 2 {
                #expect(NonlinearOversampling.processUsingMetal(samples) { tanhf($0 * 0.98) } == nil)
            }
        }
    }

    @Test
    func fullStereoRepairPreservesCPUOutput() {
        let channel = (0..<9_600).map { index -> Float in
            let time = Double(index) / 48_000
            let envelope = Float(index < 2_400 ? 1 : exp(-Double(index - 2_400) / 5_000))
            return Float(sin(2 * .pi * 220 * time) * 0.18 + sin(2 * .pi * 11_000 * time) * 0.03) * envelope
        }
        let signal = AudioSignal(channels: [channel, channel.map { -$0 * 0.7 }], sampleRate: 48_000)
        let analysis = AnalysisData(
            cutoffFrequency: 12_000, dominantHarmonics: [], harmonicConfidence: 0.9,
            hasShimmer: false, shimmerRatio: 0, brightnessRatio: 0.3, transientAmount: 0.2,
            noiseAmount: 0, rolloffDepth: 0.8, airBandEnergyRatio: 0.05,
            artifactBandRatio: 0, denoiseEffectMetrics: nil
        )
        let prediction = FoldoverRepairPrediction(foldoverMix: 0.32, airGainBias: 0.16, transientBoostBias: 0, harshnessGuard: 0)
        let cpu = CorrectionHarmonicRepair(settings: DenoiseStrength.balanced.settings, useMetal: false)
            .process(signal: signal, analysis: analysis, prediction: prediction)
        let actual = CorrectionHarmonicRepair(settings: DenoiseStrength.balanced.settings)
            .process(signal: signal, analysis: analysis, prediction: prediction)
        #expect(actual.frameCount == signal.frameCount)
        for (actualChannel, expectedChannel) in zip(actual.channels, cpu.channels) {
            #expect(actualChannel.allSatisfy { $0.isFinite })
            #expect(actualChannel.map(\.bitPattern) == expectedChannel.map(\.bitPattern))
        }
    }
}
