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
        #expect(bandRMSDB(signal: protected, lower: 150, upper: 400) >= bandRMSDB(signal: processed, lower: 150, upper: 400) + 0.20)
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) >= bandRMSDB(signal: processed, lower: 250, upper: 500) + 0.20)
        #expect(bandRMSDB(signal: protected, lower: 300, upper: 1_000) >= bandRMSDB(signal: processed, lower: 300, upper: 1_000) + 0.08)
        #expect(bandRMSDB(signal: protected, lower: 6_000, upper: 12_000) <= bandRMSDB(signal: processed, lower: 6_000, upper: 12_000) + 0.35)
        #expect(bandRMSDB(signal: protected, lower: 12_000, upper: 16_000) <= bandRMSDB(signal: processed, lower: 12_000, upper: 16_000) + 0.35)
        #expect(bandRMSDB(signal: quietProtected, lower: 20, upper: 150) <= bandRMSDB(signal: quietProcessed, lower: 20, upper: 150) + 0.10)
        #expect(bandRMSDB(signal: quietProtected, lower: 150, upper: 300) <= bandRMSDB(signal: quietProcessed, lower: 150, upper: 300) + 0.10)
        #expect(bandRMSDB(signal: quietProtected, lower: 250, upper: 500) <= bandRMSDB(signal: quietProcessed, lower: 250, upper: 500) + 0.10)
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
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) >= bandRMSDB(signal: mastered, lower: 250, upper: 500) + 0.10)
        #expect(bandRMSDB(signal: protected, lower: 20, upper: 60) <= bandRMSDB(signal: mastered, lower: 20, upper: 60) + 1.20)
    }

    @Test
    func restoresActiveLowMidBodyAgainstCorrectedReferenceWhenOriginalIsLower() {
        let correctedReference = activeLowMidBodySignal()
        let original = attenuateBand(signal: correctedReference, lower: 150, upper: 500, gainDB: -2.0)
        let mastered = attenuateBand(signal: correctedReference, lower: 150, upper: 500, gainDB: -0.7)

        let protected = MasteringLowBodyProtector.process(
            signal: mastered,
            reference: correctedReference,
            activityReference: correctedReference,
            musicalReference: original
        )

        #expect(bandRMSDB(signal: protected, lower: 150, upper: 400) >= bandRMSDB(signal: mastered, lower: 150, upper: 400) + 0.20)
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) >= bandRMSDB(signal: mastered, lower: 250, upper: 500) + 0.20)
        #expect(bandRMSDB(signal: protected, lower: 6_000, upper: 12_000) <= bandRMSDB(signal: mastered, lower: 6_000, upper: 12_000) + 0.15)
    }

    @Test
    func protectsActiveLowMidMinimumWithoutChangingQuietFloor() throws {
        let activityReference = activeLowMidBodySignal()
        let signal = attenuateBand(signal: activityReference, lower: 150, upper: 500, gainDB: -1.0)
        let protected = try #require(MasteringLowBodyProtector.protectActiveLowMidMinimum(
            signal: signal,
            activityReference: activityReference
        ))
        let quietSignal = try excerpt(from: signal, startSeconds: 0.10, durationSeconds: 0.45)
        let quietProtected = try excerpt(from: protected, startSeconds: 0.10, durationSeconds: 0.45)

        #expect(bandRMSDB(signal: protected, lower: 150, upper: 400) >= bandRMSDB(signal: signal, lower: 150, upper: 400) + 0.20)
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) >= bandRMSDB(signal: signal, lower: 250, upper: 500) + 0.20)
        #expect(bandRMSDB(signal: quietProtected, lower: 150, upper: 400) <= bandRMSDB(signal: quietSignal, lower: 150, upper: 400) + 0.02)
        #expect(bandRMSDB(signal: quietProtected, lower: 250, upper: 500) <= bandRMSDB(signal: quietSignal, lower: 250, upper: 500) + 0.02)
    }

    @Test
    func doesNotProtectActiveLowMidMinimumWhenItDidNotDrop() {
        let signal = activeLowMidBodySignal()
        let protected = MasteringLowBodyProtector.protectActiveLowMidMinimum(
            signal: signal,
            activityReference: signal
        )

        #expect(protected == nil)
    }

    @Test
    func doesNotProtectActiveLowMidMinimumForFlatQuietFloor() {
        let signal = flatQuietLowFloorSignal()
        let protected = MasteringLowBodyProtector.protectActiveLowMidMinimum(
            signal: signal,
            activityReference: signal
        )

        #expect(protected == nil)
    }

    @Test
    func doesNotLiftActiveLowMidWhenItDidNotDrop() {
        let reference = activeMidBodySignalWithoutLowFoundation()

        let protected = MasteringLowBodyProtector.process(signal: reference, reference: reference)

        #expect(bandRMSDB(signal: protected, lower: 150, upper: 400) <= bandRMSDB(signal: reference, lower: 150, upper: 400) + 0.02)
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) <= bandRMSDB(signal: reference, lower: 250, upper: 500) + 0.02)
        #expect(bandRMSDB(signal: protected, lower: 300, upper: 1_000) <= bandRMSDB(signal: reference, lower: 300, upper: 1_000) + 0.02)
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
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) <= bandRMSDB(signal: processed, lower: 250, upper: 500) + 0.02)
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
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) <= bandRMSDB(signal: processed, lower: 250, upper: 500) + 0.02)
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
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) >= bandRMSDB(signal: processed, lower: 250, upper: 500) + 0.20)
        #expect(bandRMSDB(signal: protected, lower: 300, upper: 1_000) >= bandRMSDB(signal: processed, lower: 300, upper: 1_000) + 0.08)
    }

    @Test
    func finalLowMidBodyNoiseSafetyRejectsHumReturn() {
        let base = lowMidBodyNoiseSafetySignal(humAmplitude: 0.002)
        let candidate = lowMidBodyNoiseSafetySignal(humAmplitude: 0.020)

        let isSafe = MasteringProcessor().isFinalLowMidBodyNoiseSafe(
            base: base,
            candidate: candidate,
            referenceMeasurements: nil,
            originalReferenceMeasurements: nil
        )

        #expect(isSafe == false)
    }

    @Test
    func finalLowMidBodyNoiseSafetyAcceptsUnchangedLowNoiseFloor() {
        let signal = lowMidBodyNoiseSafetySignal(humAmplitude: 0.002)

        let isSafe = MasteringProcessor().isFinalLowMidBodyNoiseSafe(
            base: signal,
            candidate: signal,
            referenceMeasurements: nil,
            originalReferenceMeasurements: nil
        )

        #expect(isSafe == true)
    }

    @Test
    func finalLowMidBodyReferenceMatchesTargetLoudnessBeforeProtection() throws {
        let processor = MasteringProcessor()
        let reference = activeLowMidBodySignal()
        let louderTarget = applyGain(
            signal: attenuateBand(signal: reference, lower: 150, upper: 500, gainDB: -1.0),
            gainDB: 6.0
        )

        let matchedReference = processor.loudnessMatchedFinalLowMidReference(
            reference: reference,
            target: louderTarget
        )
        let protected = try #require(MasteringLowBodyProtector.protectActiveLowMidMinimum(
            signal: louderTarget,
            activityReference: matchedReference
        ))

        let matchedLoudness = MasteringAnalysisService.integratedLoudness(signal: matchedReference)
        let targetLoudness = MasteringAnalysisService.integratedLoudness(signal: louderTarget)
        #expect(abs(matchedLoudness - targetLoudness) < 0.05)
        #expect(bandRMSDB(signal: protected, lower: 150, upper: 400) >= bandRMSDB(signal: louderTarget, lower: 150, upper: 400) + 0.20)
        #expect(bandRMSDB(signal: protected, lower: 250, upper: 500) >= bandRMSDB(signal: louderTarget, lower: 250, upper: 500) + 0.20)
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

    private func activeLowMidBodySignal() -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let left = (0..<frameCount).map { index -> Float in
            let t = Double(index) / sampleRate
            let activity = t < 0.90 ? 0.12 : 1.0
            let lowBody = (sin(2 * Double.pi * 82 * t) * 0.08
                + sin(2 * Double.pi * 220 * t) * 0.06
                + sin(2 * Double.pi * 360 * t) * 0.055
                + sin(2 * Double.pi * 620 * t) * 0.025) * activity
            let high = (sin(2 * Double.pi * 7_200 * t) * 0.010
                + sin(2 * Double.pi * 13_000 * t) * 0.006) * activity
            return Float(lowBody + high)
        }
        let right = left.map { $0 * 0.96 }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }

    private func lowMidBodyNoiseSafetySignal(humAmplitude: Double) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2)
        let left = (0..<frameCount).map { index -> Float in
            let t = Double(index) / sampleRate
            let musicalBody = sin(2 * Double.pi * 260 * t) * 0.055
                + sin(2 * Double.pi * 440 * t) * 0.060
            let hum = sin(2 * Double.pi * 60 * t) * humAmplitude
                + sin(2 * Double.pi * 180 * t) * humAmplitude * 0.65
            return Float(musicalBody + hum)
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

    private func activeMidBodySignalWithoutLowFoundation() -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let left = (0..<frameCount).map { index -> Float in
            let t = Double(index) / sampleRate
            let activity = t < 0.90 ? 0.12 : 1.0
            let midBody = (sin(2 * Double.pi * 260 * t) * 0.08
                + sin(2 * Double.pi * 620 * t) * 0.05) * activity
            let high = (sin(2 * Double.pi * 7_200 * t) * 0.010
                + sin(2 * Double.pi * 13_000 * t) * 0.006) * activity
            return Float(midBody + high)
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
