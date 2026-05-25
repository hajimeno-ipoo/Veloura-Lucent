import Foundation
import Testing
@testable import VelouraLucent

struct MasteringLowBodyProtectorTests {
    @Test
    func restoresActiveLowBodyBandsWithoutChangingQuietFloorOrHighBands() throws {
        let reference = activeLowBodySignal()
        var processed = attenuateBand(signal: reference, lower: 20, upper: 150, gainDB: -2.0)
        processed = attenuateBand(signal: processed, lower: 150, upper: 300, gainDB: -2.0)
        processed = attenuateBand(signal: processed, lower: 300, upper: 1_000, gainDB: -1.5)

        let protected = MasteringLowBodyProtector.process(signal: processed, reference: reference)
        let quietProcessed = try excerpt(from: processed, startSeconds: 0.10, durationSeconds: 0.45)
        let quietProtected = try excerpt(from: protected, startSeconds: 0.10, durationSeconds: 0.45)

        #expect(bandRMSDB(signal: protected, lower: 20, upper: 150) >= bandRMSDB(signal: processed, lower: 20, upper: 150) + 0.10)
        #expect(bandRMSDB(signal: protected, lower: 150, upper: 300) >= bandRMSDB(signal: processed, lower: 150, upper: 300) + 0.10)
        #expect(bandRMSDB(signal: protected, lower: 300, upper: 1_000) >= bandRMSDB(signal: processed, lower: 300, upper: 1_000) + 0.08)
        #expect(bandRMSDB(signal: protected, lower: 6_000, upper: 12_000) <= bandRMSDB(signal: processed, lower: 6_000, upper: 12_000) + 0.35)
        #expect(bandRMSDB(signal: protected, lower: 12_000, upper: 16_000) <= bandRMSDB(signal: processed, lower: 12_000, upper: 16_000) + 0.35)
        #expect(bandRMSDB(signal: quietProtected, lower: 20, upper: 150) <= bandRMSDB(signal: quietProcessed, lower: 20, upper: 150) + 0.10)
        #expect(bandRMSDB(signal: quietProtected, lower: 150, upper: 300) <= bandRMSDB(signal: quietProcessed, lower: 150, upper: 300) + 0.10)
    }

    @Test
    func usesMusicalReferenceToRestoreLowBodyLostBeforeMastering() {
        let original = activeLowBodySignal()
        let correctedReference = attenuateBand(signal: original, lower: 60, upper: 150, gainDB: -1.8)
        let mastered = attenuateBand(signal: correctedReference, lower: 60, upper: 150, gainDB: -0.3)

        let protected = MasteringLowBodyProtector.process(
            signal: mastered,
            reference: correctedReference,
            activityReference: correctedReference,
            musicalReference: original
        )

        #expect(bandRMSDB(signal: protected, lower: 60, upper: 150) >= bandRMSDB(signal: mastered, lower: 60, upper: 150) + 0.20)
        #expect(bandRMSDB(signal: protected, lower: 20, upper: 60) <= bandRMSDB(signal: mastered, lower: 20, upper: 60) + 1.20)
    }

    @Test
    func doesNotLiftFlatQuietLowFloor() {
        let reference = flatQuietLowFloorSignal()
        var processed = attenuateBand(signal: reference, lower: 20, upper: 150, gainDB: -2.0)
        processed = attenuateBand(signal: processed, lower: 150, upper: 300, gainDB: -2.0)
        processed = attenuateBand(signal: processed, lower: 300, upper: 1_000, gainDB: -1.5)

        let protected = MasteringLowBodyProtector.process(signal: processed, reference: reference)

        #expect(bandRMSDB(signal: protected, lower: 20, upper: 150) <= bandRMSDB(signal: processed, lower: 20, upper: 150) + 0.02)
        #expect(bandRMSDB(signal: protected, lower: 150, upper: 300) <= bandRMSDB(signal: processed, lower: 150, upper: 300) + 0.02)
        #expect(bandRMSDB(signal: protected, lower: 300, upper: 1_000) <= bandRMSDB(signal: processed, lower: 300, upper: 1_000) + 0.02)
    }

    @Test
    func doesNotLiftLoudnessBoostedQuietFloorWhenActivityReferenceIsQuiet() {
        let activityReference = flatQuietLowFloorSignal()
        let reference = applyGain(signal: activityReference, gainDB: 24)
        var processed = attenuateBand(signal: reference, lower: 20, upper: 150, gainDB: -2.0)
        processed = attenuateBand(signal: processed, lower: 150, upper: 300, gainDB: -2.0)
        processed = attenuateBand(signal: processed, lower: 300, upper: 1_000, gainDB: -1.5)

        let protected = MasteringLowBodyProtector.process(
            signal: processed,
            reference: reference,
            activityReference: activityReference
        )

        #expect(bandRMSDB(signal: protected, lower: 20, upper: 150) <= bandRMSDB(signal: processed, lower: 20, upper: 150) + 0.02)
        #expect(bandRMSDB(signal: protected, lower: 150, upper: 300) <= bandRMSDB(signal: processed, lower: 150, upper: 300) + 0.02)
        #expect(bandRMSDB(signal: protected, lower: 300, upper: 1_000) <= bandRMSDB(signal: processed, lower: 300, upper: 1_000) + 0.02)
    }

    @Test
    func restoresFlatSustainedLowBodyMusic() {
        let reference = flatSustainedLowBodySignal()
        var processed = attenuateBand(signal: reference, lower: 20, upper: 150, gainDB: -2.0)
        processed = attenuateBand(signal: processed, lower: 150, upper: 300, gainDB: -2.0)
        processed = attenuateBand(signal: processed, lower: 300, upper: 1_000, gainDB: -1.5)

        let protected = MasteringLowBodyProtector.process(signal: processed, reference: reference)

        #expect(bandRMSDB(signal: protected, lower: 20, upper: 150) >= bandRMSDB(signal: processed, lower: 20, upper: 150) + 0.10)
        #expect(bandRMSDB(signal: protected, lower: 150, upper: 300) >= bandRMSDB(signal: processed, lower: 150, upper: 300) + 0.10)
        #expect(bandRMSDB(signal: protected, lower: 300, upper: 1_000) >= bandRMSDB(signal: processed, lower: 300, upper: 1_000) + 0.08)
    }

    private func activeLowBodySignal() -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let left = (0..<frameCount).map { index -> Float in
            let t = Double(index) / sampleRate
            let activity = t < 0.90 ? 0.12 : 1.0
            let lowBody = (sin(2 * Double.pi * 82 * t) * 0.10
                + sin(2 * Double.pi * 210 * t) * 0.07
                + sin(2 * Double.pi * 620 * t) * 0.035) * activity
            let high = (sin(2 * Double.pi * 7_200 * t) * 0.010
                + sin(2 * Double.pi * 13_000 * t) * 0.006) * activity
            return Float(lowBody + high)
        }
        let right = left.map { $0 * 0.96 }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }

    private func flatQuietLowFloorSignal() -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let left = (0..<frameCount).map { index -> Float in
            let t = Double(index) / sampleRate
            let lowFloor = sin(2 * Double.pi * 82 * t) * 0.010
                + sin(2 * Double.pi * 210 * t) * 0.007
                + sin(2 * Double.pi * 620 * t) * 0.0035
            let highFloor = sin(2 * Double.pi * 7_200 * t) * 0.0010
                + sin(2 * Double.pi * 13_000 * t) * 0.0006
            return Float(lowFloor + highFloor)
        }
        let right = left.map { $0 * 0.96 }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }

    private func flatSustainedLowBodySignal() -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let left = (0..<frameCount).map { index -> Float in
            let t = Double(index) / sampleRate
            let lowBody = sin(2 * Double.pi * 82 * t) * 0.10
                + sin(2 * Double.pi * 210 * t) * 0.07
                + sin(2 * Double.pi * 620 * t) * 0.035
            let high = sin(2 * Double.pi * 7_200 * t) * 0.010
                + sin(2 * Double.pi * 13_000 * t) * 0.006
            return Float(lowBody + high)
        }
        let right = left.map { $0 * 0.96 }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }

    private func attenuateBand(signal: AudioSignal, lower: Double, upper: Double, gainDB: Float) -> AudioSignal {
        let gain = powf(10, gainDB / 20)
        let channels = signal.channels.map { channel in
            let band = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: lower, sampleRate: signal.sampleRate),
                cutoff: min(upper, signal.sampleRate * 0.5 - 100),
                sampleRate: signal.sampleRate
            )
            return channel.indices.map { index in
                channel[index] + band[index] * (gain - 1)
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyGain(signal: AudioSignal, gainDB: Float) -> AudioSignal {
        let gain = powf(10, gainDB / 20)
        return AudioSignal(
            channels: signal.channels.map { channel in channel.map { $0 * gain } },
            sampleRate: signal.sampleRate
        )
    }

    private func excerpt(from signal: AudioSignal, startSeconds: Double, durationSeconds: Double) throws -> AudioSignal {
        let startFrame = max(0, Int(signal.sampleRate * startSeconds))
        let frameCount = max(1, Int(signal.sampleRate * durationSeconds))
        let endFrame = min(signal.frameCount, startFrame + frameCount)
        guard startFrame < endFrame else {
            throw AudioQualityFixtureError.missingFixture("excerpt")
        }
        return AudioSignal(
            channels: signal.channels.map { Array($0[startFrame..<endFrame]) },
            sampleRate: signal.sampleRate
        )
    }

    private func bandRMSDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let upperBound = min(upper, signal.sampleRate * 0.5 - 100)
        guard lower < upperBound else { return -120 }
        let mono = signal.monoMixdown()
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(mono, cutoff: lower, sampleRate: signal.sampleRate),
            cutoff: upperBound,
            sampleRate: signal.sampleRate
        )
        let meanSquare = band.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(band.count, 1))
        return 10 * log10(max(meanSquare, 1e-12))
    }
}
