import Foundation
import Testing
@testable import VelouraLucent

struct AudioSignalSampleRateConverterTests {
    @Test
    func convertsFortyFourPointOneKilohertzStereoSignalToFortyEightKilohertz() throws {
        let source = testSignal(sampleRate: 44_100)

        let converted = try AudioSignalSampleRateConverter.convert(source, to: 48_000)

        #expect(converted.sampleRate == 48_000)
        #expect(converted.channels.count == source.channels.count)
        #expect(converted.frameCount == 4_800)
        #expect(converted.channels.allSatisfy { $0.count == converted.frameCount })
        #expect(converted.channels.allSatisfy { channel in channel.allSatisfy(\.isFinite) })
    }

    @Test
    func sameSampleRateReturnsTheValidatedSignalWithoutChangingSamples() throws {
        let source = AudioSignal(
            channels: [
                [-1.25, -0.5, 0, 0.75, 1.4],
                [1.1, 0.25, 0, -0.75, -1.3]
            ],
            sampleRate: 44_100
        )

        let converted = try AudioSignalSampleRateConverter.convert(source, to: 44_100)

        #expect(converted.sampleRate == source.sampleRate)
        #expect(converted.channels == source.channels)
    }

    @Test
    func rejectsMissingChannelsAndEmptyFramesBeforeNoOp() {
        #expect(throws: AudioSignalSampleRateConversionError.missingChannels) {
            try AudioSignalSampleRateConverter.convert(
                AudioSignal(channels: [], sampleRate: 44_100),
                to: 44_100
            )
        }
        #expect(throws: AudioSignalSampleRateConversionError.emptyFrames) {
            try AudioSignalSampleRateConverter.convert(
                AudioSignal(channels: [[], []], sampleRate: 44_100),
                to: 44_100
            )
        }
    }

    @Test
    func rejectsInconsistentChannelFrameCounts() {
        let signal = AudioSignal(
            channels: [
                [0, 0.1, 0.2],
                [0, 0.1]
            ],
            sampleRate: 44_100
        )

        #expect(
            throws: AudioSignalSampleRateConversionError.inconsistentFrameCount(
                channelIndex: 1,
                expected: 3,
                actual: 2
            )
        ) {
            try AudioSignalSampleRateConverter.convert(signal, to: 48_000)
        }
    }

    @Test
    func rejectsNonFiniteSamples() {
        for sample in [Float.nan, Float.infinity, -Float.infinity] {
            let signal = AudioSignal(
                channels: [
                    [0, sample],
                    [0, 0]
                ],
                sampleRate: 44_100
            )

            #expect(
                throws: AudioSignalSampleRateConversionError.nonFiniteSample(
                    channelIndex: 0,
                    frameIndex: 1
                )
            ) {
                try AudioSignalSampleRateConverter.convert(signal, to: 48_000)
            }
        }
    }

    @Test
    func rejectsInvalidSourceAndTargetSampleRates() {
        let validSignal = AudioSignal(channels: [[0], [0]], sampleRate: 44_100)
        let invalidSource = AudioSignal(channels: [[0], [0]], sampleRate: .nan)

        #expect(throws: AudioSignalSampleRateConversionError.invalidSourceSampleRate) {
            try AudioSignalSampleRateConverter.convert(invalidSource, to: 48_000)
        }
        #expect(throws: AudioSignalSampleRateConversionError.invalidTargetSampleRate) {
            try AudioSignalSampleRateConverter.convert(validSignal, to: .infinity)
        }
    }

    private func testSignal(sampleRate: Double) -> AudioSignal {
        let frameCount = Int(sampleRate * 0.1)
        let left = (0..<frameCount).map { index in
            let time = Double(index) / sampleRate
            return Float(
                sin(2 * Double.pi * 440 * time) * 0.36
                    + sin(2 * Double.pi * 6_400 * time) * 0.08
            )
        }
        let right = (0..<frameCount).map { index in
            let time = Double(index) / sampleRate
            return Float(
                sin(2 * Double.pi * 880 * time) * 0.28
                    + sin(2 * Double.pi * 10_200 * time) * 0.05
            )
        }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }
}
