import Foundation

enum MasteringHighFloorPreserver {
    struct ReferenceLevels {
        let referenceDB: [Double]
        let referenceBalanceDB: [Double]?
        let originalReferenceDB: [Double]?
    }

    private struct Rule {
        let label: String
        let lower: Double
        let upper: Double
        let maxDropDB: Double
        let maxBoostDB: Double
    }

    private static var highFloorRules: [Rule] {
        [
            Rule(label: "5-8kHz", lower: 5_000, upper: 8_000, maxDropDB: 4.0, maxBoostDB: 8.0),
            Rule(label: "8-12kHz", lower: 8_000, upper: 12_000, maxDropDB: 4.5, maxBoostDB: 9.0),
            Rule(label: "12-16kHz", lower: 12_000, upper: 16_000, maxDropDB: 4.5, maxBoostDB: 8.0),
            Rule(label: "16kHz以上", lower: 16_000, upper: 24_000, maxDropDB: 5.5, maxBoostDB: 7.0)
        ]
    }

    private static var originalHighFloorRules: [Rule] {
        [
            Rule(label: "原音基準 5-8kHz", lower: 5_000, upper: 8_000, maxDropDB: 5.5, maxBoostDB: 8.0),
            Rule(label: "原音基準 8-12kHz", lower: 8_000, upper: 12_000, maxDropDB: 4.5, maxBoostDB: 12.0),
            Rule(label: "原音基準 12-16kHz", lower: 12_000, upper: 16_000, maxDropDB: 4.5, maxBoostDB: 12.0),
            Rule(label: "原音基準 16kHz以上", lower: 16_000, upper: 24_000, maxDropDB: 6.0, maxBoostDB: 8.0)
        ]
    }

    static func makeReferenceLevels(reference: AudioSignal, originalReference: AudioSignal?) -> ReferenceLevels {
        ReferenceLevels(
            referenceDB: highFloorRules.map {
                MasteringSignalMath.bandRMSDB(signal: reference, lower: $0.lower, upper: $0.upper)
            },
            referenceBalanceDB: originalReference.map { _ in
                originalHighFloorRules.map {
                    MasteringSignalMath.bandBalanceDB(signal: reference, lower: $0.lower, upper: $0.upper)
                }
            },
            originalReferenceDB: originalReference.map { signal in
                originalHighFloorRules.map {
                    MasteringSignalMath.bandBalanceDB(signal: signal, lower: $0.lower, upper: $0.upper)
                }
            }
        )
    }

    static func originalReferenceNeedsHighRecovery(_ referenceLevels: ReferenceLevels) -> Bool {
        guard let referenceBalanceDB = referenceLevels.referenceBalanceDB,
              let originalReferenceDB = referenceLevels.originalReferenceDB
        else { return false }
        let count = min(referenceBalanceDB.count, originalReferenceDB.count, originalHighFloorRules.count)
        guard count > 0 else { return false }

        return (0..<count).contains { index in
            let referenceDB = referenceBalanceDB[index]
            let originalDB = originalReferenceDB[index]
            guard referenceDB.isFinite, originalDB.isFinite else { return false }
            return originalDB - referenceDB > 2.5
        }
    }

    static func preserve(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceLevels: ReferenceLevels,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        peakCeilingDB: Float,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        var current = signal
        var didApply = false

        for (index, rule) in highFloorRules.enumerated() {
            let currentDB = MasteringSignalMath.bandRMSDB(signal: current, lower: rule.lower, upper: rule.upper)
            let referenceDB = referenceLevels.referenceDB[index]
            guard currentDB.isFinite, referenceDB.isFinite else { continue }

            let targetDB = referenceDB - rule.maxDropDB
            let neededBoostDB = targetDB - currentDB
            guard neededBoostDB > 0.25 else { continue }

            let boostDB = min(neededBoostDB, rule.maxBoostDB)
            let gain = powf(10, Float(boostDB) / 20)
            let sampleRate = current.sampleRate
            let channels = mapChannelsConcurrently(current.channels) {
                MasteringSignalMath.scaleBand(
                    channel: $0,
                    sampleRate: sampleRate,
                    lower: rule.lower,
                    upper: min(rule.upper, sampleRate * 0.5 - 100),
                    gain: gain
                )
            }
            current = AudioSignal(channels: channels, sampleRate: sampleRate)
            didApply = true
            logger?.log("高域保持: \(rule.label) +\(String(format: "%.1f", boostDB)) dB")
        }

        if let originalReferenceDB = referenceLevels.originalReferenceDB {
            for (index, rule) in originalHighFloorRules.enumerated() {
                let currentDB = MasteringSignalMath.bandBalanceDB(signal: current, lower: rule.lower, upper: rule.upper)
                let originalDB = originalReferenceDB[index]
                guard currentDB.isFinite, originalDB.isFinite else { continue }

                let targetDB = originalDB - rule.maxDropDB
                let neededBoostDB = targetDB - currentDB
                guard neededBoostDB > 0.25 else { continue }

                let boostDB = min(neededBoostDB, rule.maxBoostDB)
                let gain = powf(10, Float(boostDB) / 20)
                let sampleRate = current.sampleRate
                let channels = mapChannelsConcurrently(current.channels) {
                    MasteringSignalMath.scaleBand(
                        channel: $0,
                        sampleRate: sampleRate,
                        lower: rule.lower,
                        upper: min(rule.upper, sampleRate * 0.5 - 100),
                        gain: gain
                    )
                }
                current = AudioSignal(channels: channels, sampleRate: sampleRate)
                didApply = true
                logger?.log("高域保持: \(rule.label) +\(String(format: "%.1f", boostDB)) dB")
            }
        }

        guard didApply else { return signal }
        let peakLimited = MasteringSignalMath.enforcePeakCeiling(signal: current, peakCeilingDB: peakCeilingDB)
        return constrainNoiseReturn(
            signal: peakLimited,
            fallback: signal,
            reference: reference,
            referenceNoiseMeasurements: referenceNoiseMeasurements,
            originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
            peakCeilingDB: peakCeilingDB,
            logger: logger
        )
    }

    private static func constrainNoiseReturn(
        signal: AudioSignal,
        fallback: AudioSignal,
        reference: AudioSignal,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        peakCeilingDB: Float,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let requiredIDs = [NoiseMeasurementID.hiss, NoiseMeasurementID.sibilance]
        let referenceNoise = requiredIDs.allSatisfy { referenceNoiseMeasurements?.comparableLevel(for: $0) != nil }
            ? referenceNoiseMeasurements!
            : NoiseMeasurementService.analyze(signal: reference, ids: requiredIDs)
        let originalNoise = originalReferenceNoiseMeasurements
        let fallbackNoise = NoiseMeasurementService.analyze(signal: fallback, ids: requiredIDs)
        let fallbackOriginalHissReturn = originalNoise.map {
            fallbackNoise.noiseReturnDB(from: $0, id: NoiseMeasurementID.hiss)
        } ?? 0
        let fallbackOriginalSibilanceReturn = originalNoise.map {
            fallbackNoise.noiseReturnDB(from: $0, id: NoiseMeasurementID.sibilance)
        } ?? 0
        let candidates: [(mix: Float, signal: AudioSignal)] = [
            (1.0, signal),
            (0.75, blend(base: fallback, boosted: signal, mix: 0.75)),
            (0.50, blend(base: fallback, boosted: signal, mix: 0.50)),
            (0.25, blend(base: fallback, boosted: signal, mix: 0.25)),
            (0.10, blend(base: fallback, boosted: signal, mix: 0.10)),
            (0.05, blend(base: fallback, boosted: signal, mix: 0.05))
        ]

        for candidate in candidates {
            let candidateNoise = NoiseMeasurementService.analyze(signal: candidate.signal, ids: requiredIDs)
            let hissReturn = candidateNoise.noiseReturnDB(from: referenceNoise, id: NoiseMeasurementID.hiss)
            let sibilanceReturn = candidateNoise.noiseReturnDB(from: referenceNoise, id: NoiseMeasurementID.sibilance)
            let originalHissReturn = originalNoise.map { candidateNoise.noiseReturnDB(from: $0, id: NoiseMeasurementID.hiss) } ?? 0
            let originalSibilanceReturn = originalNoise.map { candidateNoise.noiseReturnDB(from: $0, id: NoiseMeasurementID.sibilance) } ?? 0
            let originalHissCeiling = max(0.5, fallbackOriginalHissReturn + 0.25)
            let originalSibilanceCeiling = min(3.0, max(0.5, fallbackOriginalSibilanceReturn + 0.25))
            guard hissReturn <= 2.0,
                  sibilanceReturn <= 1.5,
                  originalHissReturn <= originalHissCeiling,
                  originalSibilanceReturn <= originalSibilanceCeiling
            else { continue }
            if candidate.mix < 1 {
                logger?.log("高域保持: ノイズ戻り抑制 mix \(String(format: "%.2f", candidate.mix))")
            }
            return MasteringSignalMath.enforcePeakCeiling(signal: candidate.signal, peakCeilingDB: peakCeilingDB)
        }

        let minimumPreserved = blend(base: fallback, boosted: signal, mix: 0.05)
        logger?.log("高域保持: 最低保持 mix 0.05")
        return MasteringSignalMath.enforcePeakCeiling(signal: minimumPreserved, peakCeilingDB: peakCeilingDB)
    }

    private static func blend(base: AudioSignal, boosted: AudioSignal, mix: Float) -> AudioSignal {
        let channelCount = min(base.channels.count, boosted.channels.count)
        guard channelCount > 0 else { return base }
        var channels = base.channels
        for channelIndex in 0..<channelCount {
            let count = min(base.channels[channelIndex].count, boosted.channels[channelIndex].count)
            guard count > 0 else { continue }
            channels[channelIndex] = (0..<count).map { index in
                base.channels[channelIndex][index] * (1 - mix) + boosted.channels[channelIndex][index] * mix
            }
        }
        return AudioSignal(channels: channels, sampleRate: base.sampleRate)
    }
}
