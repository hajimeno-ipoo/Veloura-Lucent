import BSRoformerMLX
import Testing
@testable import VelouraLucent

struct BSRoformerStemSeparationBackendTests {
    @Test
    func mapsAllSixStemsWithoutChangingSamplesOrFormat() throws {
        let bass = try audio([0.1, 0.2, 0.3, 0.4])
        let drums = try audio([0.5, 0.6, 0.7, 0.8])
        let other = try audio([1, 2, 3, 4])
        let vocals = try audio([0.9, 1.0, 1.1, 1.2])
        let guitar = try audio([0.01, 0.02, 0.03, 0.04])
        let piano = try audio([0.001, 0.002, 0.003, 0.004])

        let output = try BSRoformerStemOutputMapper.makeSixStemOutput(
            from: BSRoformerSeparation(stems: [
                .bass: bass,
                .drums: drums,
                .other: other,
                .vocals: vocals,
                .guitar: guitar,
                .piano: piano,
            ])
        )

        #expect(Set(output.stems.keys) == Set(
            StemProductionModelProfile.profile(for: .bsRoformerSW).sourceOrder.map(\.rawValue)
        ))
        #expect(output.stems[StemRole.bass.rawValue]?.channelMajorSamples == bass.channelMajorSamples)
        #expect(output.stems[StemRole.drums.rawValue]?.channelMajorSamples == drums.channelMajorSamples)
        #expect(output.stems[StemRole.other.rawValue]?.channelMajorSamples == other.channelMajorSamples)
        #expect(output.stems[StemRole.vocals.rawValue]?.channelMajorSamples == vocals.channelMajorSamples)
        #expect(output.stems[StemRole.guitar.rawValue]?.channelMajorSamples == guitar.channelMajorSamples)
        #expect(output.stems[StemRole.piano.rawValue]?.channelMajorSamples == piano.channelMajorSamples)
        #expect(output.stems.values.allSatisfy { $0.channelCount == 2 && $0.sampleRate == 44_100 })
    }

    @Test
    func rejectsMissingSixStemOutput() throws {
        let signal = try audio([0.1, 0.2, 0.3, 0.4])
        let separation = BSRoformerSeparation(stems: [
            .bass: signal,
            .drums: signal,
            .other: signal,
            .vocals: signal,
            .guitar: signal,
        ])

        #expect(
            throws: BSRoformerStemSeparationBackendError.missingStem("piano")
        ) {
            _ = try BSRoformerStemOutputMapper.makeSixStemOutput(from: separation)
        }
    }

    @Test
    func preservesAnIncompatibleStemForContractValidationWithoutMergingIt() throws {
        let stereo = try audio([0.1, 0.2, 0.3, 0.4])
        let monoPiano = try audio([0.1, 0.2], channels: 1)
        let separation = BSRoformerSeparation(stems: [
            .bass: stereo,
            .drums: stereo,
            .other: stereo,
            .vocals: stereo,
            .guitar: stereo,
            .piano: monoPiano,
        ])

        let output = try BSRoformerStemOutputMapper.makeSixStemOutput(from: separation)

        #expect(output.stems[StemRole.other.rawValue]?.channelMajorSamples == stereo.channelMajorSamples)
        #expect(output.stems[StemRole.piano.rawValue]?.channelMajorSamples == monoPiano.channelMajorSamples)
        #expect(output.stems[StemRole.piano.rawValue]?.channelCount == 1)
    }

    private func audio(
        _ samples: [Float],
        channels: Int = 2
    ) throws -> BSRoformerAudio {
        try BSRoformerAudio(
            channelMajorSamples: samples,
            channels: channels,
            sampleRate: 44_100
        )
    }
}
