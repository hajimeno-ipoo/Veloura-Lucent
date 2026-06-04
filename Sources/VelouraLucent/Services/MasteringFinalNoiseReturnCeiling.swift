import Foundation

extension MasteringProcessor {
    func applyFinalNoiseReturnCeiling(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceHighBandLevels: inout [NoiseReturnHighBandReferenceLevel]?,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        loudnessRestoreFallback: AudioSignal? = nil,
        allowsOriginalReferenceHighRecovery: Bool = false,
        peakCeilingDB: Float,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        var current = signal
        let requiredIDs = [NoiseMeasurementID.hiss, NoiseMeasurementID.sibilance, NoiseMeasurementID.shimmer]
        let referenceNoise = requiredIDs.allSatisfy { referenceNoiseMeasurements?.comparableLevel(for: $0) != nil }
            ? referenceNoiseMeasurements!
            : NoiseMeasurementService.analyze(signal: reference, ids: requiredIDs)
        let originalNoise = originalReferenceNoiseMeasurements
        let referenceSibilance = referenceNoise.comparableLevel(for: NoiseMeasurementID.sibilance)
        let targetSibilance = min(
            originalNoise?.comparableLevel(for: NoiseMeasurementID.sibilance).map { $0 + 2.7 } ?? Double.infinity,
            referenceSibilance.map { $0 > 18.0 ? 15.2 : Double.infinity } ?? Double.infinity
        )

        let maxPasses = 5
        var loudnessRestoreFallbackNoise: NoiseMeasurementSnapshot?
        for pass in 1...maxPasses {
            let currentNoise = NoiseMeasurementService.analyze(signal: current, ids: requiredIDs)
            if let loudnessRestoreFallback,
               Self.finalLoudnessRestoreHissReturnExceedsLimit(
                referenceMeasurements: referenceNoise,
                currentMeasurements: currentNoise
               ) {
                let fallbackNoise = loudnessRestoreFallbackNoise ?? NoiseMeasurementService.analyze(
                    signal: loudnessRestoreFallback,
                    ids: [NoiseMeasurementID.hiss]
                )
                loudnessRestoreFallbackNoise = fallbackNoise
                if Self.shouldUseFinalLoudnessRestoreFallback(
                    referenceMeasurements: referenceNoise,
                    restoredMeasurements: currentNoise,
                    fallbackMeasurements: fallbackNoise
                ) {
                    logger?.log("最終音量復帰: ヒス上限超過のため復帰前へ戻します")
                    return loudnessRestoreFallback
                }
                logger?.log("最終音量復帰: 復帰前もヒス上限超過のため緊急上限確認を続けます")
            }
            let strongestHighFloorExcess = [NoiseMeasurementID.hiss, NoiseMeasurementID.shimmer]
                .compactMap { id -> (rule: NoiseReturnLimit, excessDB: Double)? in
                    let returnDB = currentNoise.noiseReturnDB(from: referenceNoise, id: id)
                    let originalReturnDB = originalNoise.map {
                        currentNoise.noiseReturnDB(from: $0, id: id)
                    } ?? Double.greatestFiniteMagnitude
                    guard let target = Self.finalHighNoiseReturnTarget(
                        for: id,
                        returnDB: returnDB,
                        originalReturnDB: originalReturnDB,
                        appliesCorrectedReferenceLimit: loudnessRestoreFallback != nil
                            && !allowsOriginalReferenceHighRecovery
                    ),
                          let rule = Self.finalNoiseReturnRule(for: id, allowedReturnDB: target)
                    else { return nil }
                    return (rule, returnDB - target)
                }
                .max { $0.excessDB < $1.excessDB }
            let currentSibilance = currentNoise.comparableLevel(for: NoiseMeasurementID.sibilance)
            let shouldLimitSibilance = targetSibilance.isFinite
                && currentSibilance.map { $0 > targetSibilance } == true
            guard strongestHighFloorExcess != nil || shouldLimitSibilance else {
                if pass > 1 {
                    logger?.log("ノイズ戻り: 緊急上限確認 \(pass - 1)/\(maxPasses)")
                }
                return MasteringSignalMath.enforcePeakCeiling(signal: current, peakCeilingDB: peakCeilingDB)
            }

            let sampleRate = current.sampleRate
            if let strongestHighFloorExcess {
                let gain = MasteringNoiseReturnSupport.noiseReturnGain(
                    for: strongestHighFloorExcess.rule,
                    excessDB: strongestHighFloorExcess.excessDB
                )
                if let candidate = MasteringNoiseReturnSupport.constrainedNoiseReturnCandidate(
                    signal: current,
                    guardReferenceLevels: MasteringNoiseReturnSupport.resolvedNoiseReturnHighBandReferenceLevels(
                        &referenceHighBandLevels,
                        signal: reference
                    ),
                    rule: strongestHighFloorExcess.rule,
                    gain: gain,
                    logger: logger
                ) {
                    current = candidate
                    logger?.log("ノイズ戻り: 緊急\(MasteringNoiseReturnSupport.noiseReturnDisplayName(for: strongestHighFloorExcess.rule.id))上限 \(pass)/\(maxPasses)")
                } else {
                    current = Self.forcedNoiseReturnCandidate(
                        signal: current,
                        rule: strongestHighFloorExcess.rule,
                        gain: gain
                    )
                    logger?.log("ノイズ戻り: 緊急\(MasteringNoiseReturnSupport.noiseReturnDisplayName(for: strongestHighFloorExcess.rule.id))上限を優先 \(pass)/\(maxPasses)")
                }
            }

            if shouldLimitSibilance {
                let excessDB = max(0, (currentSibilance ?? targetSibilance) - targetSibilance)
                let channels = mapChannelsConcurrently(current.channels) {
                    Self.limitSibilanceTransients(
                        channel: $0,
                        sampleRate: sampleRate,
                        targetExcessDB: targetSibilance,
                        strengthDB: min(max(3.0, excessDB * 5.0), 10.0)
                    )
                }
                current = AudioSignal(channels: channels, sampleRate: sampleRate)
                logger?.log("ノイズ戻り: 緊急サ行上限 \(pass)/\(maxPasses)")
            }
        }

        return MasteringSignalMath.enforcePeakCeiling(signal: current, peakCeilingDB: peakCeilingDB)
    }

    static func finalNoiseReturnLimit(for id: String) -> Double {
        InternalAudioJudgementPolicy.severityLimit(for: id)?.masteringWorseningCautionDB ?? 2.0
    }

    static func finalLoudnessRestoreHissReturnExceedsLimit(
        referenceMeasurements: NoiseMeasurementSnapshot,
        currentMeasurements: NoiseMeasurementSnapshot
    ) -> Bool {
        guard let referenceHiss = referenceMeasurements.comparableLevel(for: NoiseMeasurementID.hiss),
              let currentHiss = currentMeasurements.comparableLevel(for: NoiseMeasurementID.hiss)
        else {
            return false
        }
        return currentHiss > referenceHiss + InternalAudioJudgementPolicy.finalLoudnessRestoreMaxHissReturnDB
    }

    static func shouldUseFinalLoudnessRestoreFallback(
        referenceMeasurements: NoiseMeasurementSnapshot,
        restoredMeasurements: NoiseMeasurementSnapshot,
        fallbackMeasurements: NoiseMeasurementSnapshot
    ) -> Bool {
        finalLoudnessRestoreHissReturnExceedsLimit(
            referenceMeasurements: referenceMeasurements,
            currentMeasurements: restoredMeasurements
        ) && !finalLoudnessRestoreHissReturnExceedsLimit(
            referenceMeasurements: referenceMeasurements,
            currentMeasurements: fallbackMeasurements
        )
    }

    private static func finalHighNoiseReturnTarget(
        for id: String,
        returnDB: Double,
        originalReturnDB: Double,
        appliesCorrectedReferenceLimit: Bool
    ) -> Double? {
        let limit = finalNoiseReturnLimit(for: id)
        let ruleLimit = InternalAudioJudgementPolicy.masteringNoiseReturnLimits.first(where: { $0.id == id })?.allowedReturnDB ?? limit
        if returnDB > limit, originalReturnDB > 0.5 {
            return min(limit - 0.15, ruleLimit)
        }
        guard appliesCorrectedReferenceLimit else {
            return nil
        }
        let correctedReferenceLimit = InternalAudioJudgementPolicy.finalOutputMaxHighNoiseReturnDB
        guard returnDB > correctedReferenceLimit else {
            return nil
        }
        return correctedReferenceLimit - InternalAudioJudgementPolicy.finalOutputHighNoiseReturnSafetyMarginDB
    }

    private static func finalNoiseReturnRule(for id: String, allowedReturnDB: Double) -> NoiseReturnLimit? {
        guard let rule = InternalAudioJudgementPolicy.masteringNoiseReturnLimits.first(where: { $0.id == id }) else {
            return nil
        }
        return NoiseReturnLimit(
            id: rule.id,
            lowerFrequency: rule.lowerFrequency,
            upperFrequency: rule.upperFrequency,
            allowedReturnDB: allowedReturnDB,
            reductionMultiplier: max(rule.reductionMultiplier, 1.0),
            maxReductionDB: max(rule.maxReductionDB, 6.0)
        )
    }

    private static func forcedNoiseReturnCandidate(
        signal: AudioSignal,
        rule: NoiseReturnLimit,
        gain: Float
    ) -> AudioSignal {
        let sampleRate = signal.sampleRate
        let channels = mapChannelsConcurrently(signal.channels) {
            MasteringSignalMath.scaleBand(
                channel: $0,
                sampleRate: sampleRate,
                lower: rule.lowerFrequency,
                upper: rule.upperFrequency,
                gain: gain
            )
        }
        return AudioSignal(channels: channels, sampleRate: sampleRate)
    }

    private static func limitSibilanceTransients(
        channel: [Float],
        sampleRate: Double,
        targetExcessDB: Double,
        strengthDB: Double
    ) -> [Float] {
        guard !channel.isEmpty, targetExcessDB.isFinite, strengthDB > 0.1 else { return channel }
        let sibilanceBand = MasteringSignalMath.bandPass(
            channel,
            lower: 5_000,
            upper: min(9_000, sampleRate * 0.5 - 100),
            sampleRate: sampleRate
        )
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        guard sibilanceBand.count > frameSize else { return channel }

        var frames: [(range: Range<Int>, levelDB: Double)] = []
        var start = 0
        while start + frameSize <= sibilanceBand.count {
            let range = start..<(start + frameSize)
            frames.append((range, MasteringSignalMath.rmsDB(Array(sibilanceBand[range]))))
            start += hopSize
        }
        guard frames.count >= 4 else { return channel }

        let medianDB = MasteringSignalMath.percentile(frames.map(\.levelDB), 0.50)
        let peakLimitDB = medianDB + max(0, targetExcessDB - 1.0)
        var envelope = Array(repeating: Float.zero, count: channel.count)

        for frame in frames where frame.levelDB > peakLimitDB {
            let excessDB = frame.levelDB - peakLimitDB
            let reductionDB = min(strengthDB, max(0, excessDB) * 2.20)
            let reduction = 1 - powf(10, -Float(reductionDB) / 20)
            for index in frame.range {
                envelope[index] = max(envelope[index], reduction)
            }
        }

        return channel.indices.map { index in
            channel[index] - sibilanceBand[index] * envelope[index]
        }
    }
}
