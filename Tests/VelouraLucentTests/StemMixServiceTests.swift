import Foundation
import Testing
@testable import VelouraLucent

struct StemMixServiceTests {
    private let service = StemMixService()

    @Test
    func pureSumAddsFourRolesSampleForSampleWithoutChangingFormat() throws {
        let result = try service.pureSum(stems: Array(makeExactSumStems().reversed()))

        #expect(result.signal.sampleRate == 44_100)
        #expect(result.signal.channels.count == 2)
        #expect(result.signal.frameCount == 4)
        #expect(result.signal.channels == [
            [0.34375, -0.1875, 0.25, -0.5625],
            [-0.25, 0.375, -0.1875, 0.5625]
        ])
    }

    @Test
    func pureSumPreservesFiniteOverRangeSamplesWithoutAutomaticGain() throws {
        let result = try service.pureSum(stems: makeConstantStems(
            left: [0.375, -0.375],
            right: [-0.375, 0.375]
        ))

        #expect(result.signal.channels == [[1.5, -1.5], [-1.5, 1.5]])
        #expect(result.peaks.samplePeakLinear == 1.5)
        #expect(result.peaks.overRangeSampleCount == 4)
        #expect(result.peaks.samplePeakExceedsFullScale)
        #expect(result.peaks.hasOverRange)
    }

    @Test
    func pureSumUsesVocalsDrumsBassOtherFloat32Order() throws {
        let vocals: Float = 1e20
        let drums: Float = -1e20
        let bass: Float = 3.25
        let other: Float = 1.5
        let expected = ((vocals + drums) + bass) + other
        let differentOrder = ((drums + bass) + other) + vocals
        let stems = makeRoleValueStems([
            .vocals: vocals,
            .drums: drums,
            .bass: bass,
            .other: other,
        ])

        let result = try service.pureSum(stems: Array(stems.reversed()))

        #expect(expected.bitPattern != differentOrder.bitPattern)
        #expect(result.signal.channels[0][0].bitPattern == expected.bitPattern)
        #expect(result.signal.channels[1][0].bitPattern == expected.bitPattern)
    }

    @Test
    func finitePureSumIsKeptWhenTruePeakCannotBeRepresented() throws {
        let largest = Float.greatestFiniteMagnitude
        let result = try service.pureSum(stems: makeRoleValueStems(
            [.vocals: largest],
            frameCount: 2
        ))

        #expect(result.signal.channels == [
            [largest, largest],
            [largest, largest],
        ])
        #expect(result.peaks.samplePeakLinear == largest)
        #expect(result.peaks.truePeakMeasurement == .unavailable)
        #expect(result.peaks.overRangeSampleCount == 4)
    }

    @Test
    func duplicateAndMissingRolesAreRejected() {
        var duplicated = makeExactSumStems()
        duplicated[2] = StemMixInput(role: .vocals, signal: duplicated[2].signal)
        #expect(throws: StemMixError.duplicateRole(.vocals)) {
            try service.pureSum(stems: duplicated)
        }

        let missing = makeExactSumStems().filter { $0.role != .other }
        #expect(throws: StemMixError.missingRole(.other)) {
            try service.pureSum(stems: missing)
        }
    }

    @Test
    func nonFiniteInputSamplesAreRejected() {
        for nonFiniteSample in [Float.nan, Float.infinity, -Float.infinity] {
            var stems = makeExactSumStems()
            var channels = stems[1].signal.channels
            channels[1][2] = nonFiniteSample
            stems[1] = StemMixInput(
                role: .bass,
                signal: AudioSignal(channels: channels, sampleRate: 44_100)
            )

            #expect(
                throws: StemMixError.nonFiniteSample(
                    role: .bass,
                    channelIndex: 1,
                    frameIndex: 2
                )
            ) {
                try service.pureSum(stems: stems)
            }
        }
    }

    @Test
    func mismatchedFormatsAndFramesAreRejected() {
        var uneven = makeExactSumStems()
        uneven[2] = StemMixInput(
            role: .other,
            signal: AudioSignal(channels: [[0, 0, 0, 0], [0, 0, 0]], sampleRate: 44_100)
        )
        #expect(
            throws: StemMixError.unevenChannelFrameCount(
                role: .other,
                channelIndex: 1,
                expected: 4,
                actual: 3
            )
        ) {
            try service.pureSum(stems: uneven)
        }

        var sampleRate = makeExactSumStems()
        sampleRate[1] = StemMixInput(
            role: .bass,
            signal: AudioSignal(channels: sampleRate[1].signal.channels, sampleRate: 48_000)
        )
        #expect(
            throws: StemMixError.sampleRateMismatch(
                role: .bass,
                expected: 44_100,
                actual: 48_000
            )
        ) {
            try service.pureSum(stems: sampleRate)
        }

        var channelCount = makeExactSumStems()
        channelCount[2] = StemMixInput(
            role: .other,
            signal: AudioSignal(channels: [[0, 0, 0, 0]], sampleRate: 44_100)
        )
        #expect(
            throws: StemMixError.channelCountMismatch(
                role: .other,
                expected: 2,
                actual: 1
            )
        ) {
            try service.pureSum(stems: channelCount)
        }

        var frameCount = makeExactSumStems()
        frameCount[3] = StemMixInput(
            role: .vocals,
            signal: AudioSignal(channels: [[0, 0, 0], [0, 0, 0]], sampleRate: 44_100)
        )
        #expect(
            throws: StemMixError.frameCountMismatch(
                role: .vocals,
                expected: 4,
                actual: 3
            )
        ) {
            try service.pureSum(stems: frameCount)
        }
    }

    @Test
    func emptyAudioStructuresAndInvalidSampleRateAreRejected() {
        var noChannels = makeExactSumStems()
        noChannels[0] = StemMixInput(
            role: .drums,
            signal: AudioSignal(channels: [], sampleRate: 44_100)
        )
        #expect(throws: StemMixError.missingChannels(role: .drums)) {
            try service.pureSum(stems: noChannels)
        }

        var noFrames = makeExactSumStems()
        noFrames[1] = StemMixInput(
            role: .bass,
            signal: AudioSignal(channels: [[], []], sampleRate: 44_100)
        )
        #expect(throws: StemMixError.emptyFrames(role: .bass)) {
            try service.pureSum(stems: noFrames)
        }

        var invalidRate = makeExactSumStems()
        invalidRate[0] = StemMixInput(
            role: .drums,
            signal: AudioSignal(channels: invalidRate[0].signal.channels, sampleRate: .nan)
        )
        #expect(throws: StemMixError.invalidSampleRate(role: .drums)) {
            try service.pureSum(stems: invalidRate)
        }
    }

    @Test
    func finiteInputsThatOverflowFloat32SumAreRejected() {
        let veryLarge = Float.greatestFiniteMagnitude * 0.75
        let stems = makeConstantStems(left: [veryLarge, 0], right: [0, veryLarge])

        #expect(throws: StemMixError.nonFiniteMixedSample(channelIndex: 0, frameIndex: 0)) {
            try service.pureSum(stems: stems)
        }
    }

    private func makeExactSumStems() -> [StemMixInput] {
        [
            StemMixInput(
                role: .drums,
                signal: AudioSignal(
                    channels: [
                        [0.125, 0.25, -0.25, 0.125],
                        [-0.125, 0.25, 0.125, -0.25]
                    ],
                    sampleRate: 44_100
                )
            ),
            StemMixInput(
                role: .bass,
                signal: AudioSignal(
                    channels: [
                        [-0.0625, 0.125, 0.5, -0.25],
                        [0.0625, -0.125, -0.25, 0.5]
                    ],
                    sampleRate: 44_100
                )
            ),
            StemMixInput(
                role: .other,
                signal: AudioSignal(
                    channels: [
                        [0.03125, -0.0625, -0.125, 0.0625],
                        [-0.03125, 0.0625, 0.125, -0.0625]
                    ],
                    sampleRate: 44_100
                )
            ),
            StemMixInput(
                role: .vocals,
                signal: AudioSignal(
                    channels: [
                        [0.25, -0.5, 0.125, -0.5],
                        [-0.15625, 0.1875, -0.1875, 0.375]
                    ],
                    sampleRate: 44_100
                )
            )
        ]
    }

    private func makeConstantStems(left: [Float], right: [Float]) -> [StemMixInput] {
        StemRole.allCases.map { role in
            StemMixInput(
                role: role,
                signal: AudioSignal(channels: [left, right], sampleRate: 44_100)
            )
        }
    }

    private func makeRoleValueStems(
        _ values: [StemRole: Float],
        frameCount: Int = 1
    ) -> [StemMixInput] {
        StemRole.allCases.map { role in
            let channel = Array(repeating: values[role, default: 0], count: frameCount)
            return StemMixInput(
                role: role,
                signal: AudioSignal(channels: [channel, channel], sampleRate: 44_100)
            )
        }
    }
}
