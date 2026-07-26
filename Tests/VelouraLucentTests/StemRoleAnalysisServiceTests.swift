import Foundation
import Testing
@testable import VelouraLucent

struct StemRoleAnalysisServiceTests {
    @Test
    func analyzesEveryRoleDirectlyFromFortyEightKilohertzProcessingSignal() throws {
        let service = StemRoleAnalysisService()
        let source = makeStereoSignal(duration: 0.35)
        let originalChannels = source.channels

        for role in StemRole.allCases {
            let snapshot = try service.analyze(
                role: role,
                processingSignal48000: source
            )

            #expect(snapshot.role == role)
            #expect(snapshot.authoritativeSampleRate == 48_000)
            #expect(snapshot.analysisSampleRate == 48_000)
            #expect(snapshot.authoritativeFrameCount == source.frameCount)
            #expect(snapshot.analysisFrameCount == snapshot.authoritativeFrameCount)
            #expect(snapshot.features.count == 4)
            #expect(Set(snapshot.features.map(\.feature)).count == 4)
            #expect(snapshot.features.allSatisfy { feature in
                feature.frameCount > 0
                    && feature.firstQuartile.isFinite
                    && feature.median.isFinite
                    && feature.thirdQuartile.isFinite
                    && feature.interquartileRange.isFinite
                    && feature.firstQuartile <= feature.median
                    && feature.median <= feature.thirdQuartile
                    && feature.interquartileRange >= 0
            })
        }

        #expect(source.sampleRate == 48_000)
        #expect(source.channels == originalChannels)
    }

    @Test
    func rejectsNonAuthoritativeRateMonoAndNonFiniteSamples() {
        let service = StemRoleAnalysisService()
        let valid = makeStereoSignal(duration: 0.05)

        #expect(
            throws: StemRoleAnalysisError.unsupportedAuthoritativeSampleRate(
                expected: 48_000,
                actual: 44_100
            )
        ) {
            try service.analyze(
                role: .vocals,
                processingSignal48000: AudioSignal(
                    channels: valid.channels,
                    sampleRate: 44_100
                )
            )
        }

        #expect(throws: StemRoleAnalysisError.stereoRequired(actualChannelCount: 1)) {
            try service.analyze(
                role: .drums,
                processingSignal48000: AudioSignal(
                    channels: [valid.channels[0]],
                    sampleRate: 48_000
                )
            )
        }

        var nonFinite = valid
        nonFinite.channels[1][3] = .nan
        #expect(
            throws: StemRoleAnalysisError.nonFiniteSample(
                channelIndex: 1,
                frameIndex: 3
            )
        ) {
            try service.analyze(role: .bass, processingSignal48000: nonFinite)
        }
    }

    @Test("各roleの保護対象を同じ時間位置で過不足なく生成する", arguments: StemRole.allCases)
    func producesTimeAlignedProtectionProfile(role: StemRole) throws {
        let signal = makeStereoSignal(duration: 0.35)
        let result = try StemRoleAnalysisService().analyzeWithProtection(
            role: role,
            processingSignal48000: signal
        )
        let profile = result.protectionProfile
        let expected = Set(StemRoleProtectedComponent.allCases.filter { $0.role == role })

        #expect(profile.role == role)
        #expect(profile.signalFrameCount == signal.frameCount)
        #expect(profile.analysisFrameSize == 4_096)
        #expect(profile.hopSize == 2_048)
        #expect(!profile.frames.isEmpty)
        #expect(profile.frames.allSatisfy { frame in
            Set(frame.values.keys) == expected
                && frame.values.values.allSatisfy(\.isFinite)
                && frame.startFrame >= 0
                && frame.validFrameCount > 0
        })
        #expect(profile.frames.last.map { $0.startFrame + $0.validFrameCount } == signal.frameCount)
    }

    private func makeStereoSignal(duration: Double) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        var left = Array(repeating: Float.zero, count: frameCount)
        var right = Array(repeating: Float.zero, count: frameCount)
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let envelope = 0.55 + 0.45 * sin(2 * .pi * 3.2 * time)
            let transient = index.isMultiple(of: 2_205) ? 0.45 : 0
            left[index] = Float(
                envelope * (
                    0.32 * sin(2 * .pi * 110 * time)
                        + 0.2 * sin(2 * .pi * 220 * time)
                        + 0.08 * sin(2 * .pi * 6_500 * time)
                ) + transient
            )
            right[index] = Float(
                envelope * (
                    0.3 * sin(2 * .pi * 110 * time + 0.03)
                        + 0.18 * sin(2 * .pi * 330 * time)
                        + 0.07 * sin(2 * .pi * 8_000 * time)
                ) + transient * 0.85
            )
        }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }
}
