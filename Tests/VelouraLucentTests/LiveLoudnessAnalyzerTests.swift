import Foundation
import Testing
@testable import VelouraLucent

struct LiveLoudnessAnalyzerTests {
    @Test
    func referenceToneMeasuresCorrectlyAtSupportedSampleRates() throws {
        for sampleRate in [44_100.0, 48_000.0, 96_000.0] {
            let frameCount = Int(sampleRate)
            let amplitude = pow(10, -23.0 / 20.0)
            let channel = (0..<frameCount).map { index in
                Float(amplitude * sin(2 * .pi * 1_000 * Double(index) / sampleRate))
            }
            let analyzer = LiveLoudnessAnalyzer(sampleRate: sampleRate)
            let snapshot = analyzer.snapshot(
                from: RealtimeSpectrumSampleBuffer(
                    channelSamples: [channel, channel],
                    sampleRate: sampleRate
                )
            )

            let momentary = try #require(snapshot.momentaryLUFS)
            let integrated = try #require(snapshot.integratedLUFS)
            let truePeak = try #require(snapshot.truePeakDBTP)
            #expect(abs(momentary - (-23.0)) <= 0.1)
            #expect(abs(integrated - (-23.0)) <= 0.1)
            #expect(abs(truePeak - (-23.0)) <= 0.2)
        }
    }
}
