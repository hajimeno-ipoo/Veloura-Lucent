import Foundation

extension MasteringProcessor {
    func restoreFinalLoudnessAfterGuards(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        targetLKFS: Float,
        requestedTargetLKFS: Float,
        peakCeilingDB: Float,
        policy: LoudnessAdjustmentPolicy,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let currentLoudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        guard currentLoudness.isFinite, currentLoudness > -69 else {
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }

        let loudnessDeficitDB = Double(targetLKFS - currentLoudness)
        let peak = max(MasteringAnalysisService.approximateTruePeak(signal.channels), 1e-6)
        let currentPeakDB = 20 * log10(Double(peak))
        let peakHeadroomDB = max(0, Double(peakCeilingDB) - currentPeakDB)
        let safetyRestoreLimitDB = 2.0
        let requestedTargetHeadroomDB = max(
            0,
            Double(requestedTargetLKFS - currentLoudness) + policy.targetOvershootLimitDB
        )
        let requestedGainDB: Double
        if loudnessDeficitDB > 0.35 {
            requestedGainDB = min(loudnessDeficitDB, peakHeadroomDB, policy.finalRestoreLimitDB)
        } else {
            requestedGainDB = min(
                safetyRestoreLimitDB,
                peakHeadroomDB,
                policy.finalRestoreLimitDB,
                requestedTargetHeadroomDB
            )
        }
        guard requestedGainDB > 0.25 else {
            logger?.log("最終音量復帰: ピーク余裕不足")
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }

        let candidate = MasteringSignalMath.enforcePeakCeiling(
            signal: MasteringSignalMath.applyGain(signal: signal, gainDB: requestedGainDB),
            peakCeilingDB: peakCeilingDB
        )
        let probePlan = MasteringNoiseReturnSupport.noiseReturnProbePlan(for: signal)
        let baseProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: signal, plan: probePlan)
        let candidateProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: candidate, plan: probePlan)
        guard isFinalLoudnessRestoreNoiseSafe(
            baseProbe: baseProbe,
            candidateProbe: candidateProbe,
            referenceMeasurements: referenceNoiseMeasurements,
            originalReferenceMeasurements: originalReferenceNoiseMeasurements
        ), isFinalLoudnessRestoreMudBalanceSafe(base: signal, candidate: candidate) else {
            logger?.log("最終音量復帰: ノイズ保護で見送り")
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }
        logger?.log("最終音量復帰: +\(String(format: "%.1f", requestedGainDB)) dB")
        return candidate
    }

    func enforceFinalLoudnessPolicyBounds(
        signal: AudioSignal,
        baselineLoudness: Float,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        peakCeilingDB: Float,
        policy: LoudnessAdjustmentPolicy,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let currentLoudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        guard baselineLoudness.isFinite,
              currentLoudness.isFinite,
              baselineLoudness > -69,
              currentLoudness > -69
        else {
            logger?.log("最終音量上限: 無音に近いためピーク確認のみ")
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }

        let toleranceDB = 0.05
        let allowedMaximum = Double(baselineLoudness) + policy.maxBoostDB
        let allowedMinimum = Double(baselineLoudness) - policy.maxCutDB
        let current = Double(currentLoudness)

        if current > allowedMaximum + toleranceDB {
            let gainDB = allowedMaximum - current
            logger?.log("最終音量上限: \(formatSignedDB(gainDB)) / \(policy.label) の上限内へ調整")
            return MasteringSignalMath.enforcePeakCeiling(
                signal: MasteringSignalMath.applyGain(signal: signal, gainDB: gainDB),
                peakCeilingDB: peakCeilingDB
            )
        }

        if current < allowedMinimum - toleranceDB {
            let loudnessDeficitDB = allowedMinimum - current
            let peak = max(MasteringAnalysisService.approximateTruePeak(signal.channels), 1e-6)
            let currentPeakDB = 20 * log10(Double(peak))
            let peakHeadroomDB = max(0, Double(peakCeilingDB) - currentPeakDB)
            let restoreDB = min(loudnessDeficitDB, peakHeadroomDB, policy.finalRestoreLimitDB)
            guard restoreDB > 0.25 else {
                logger?.log("最終音量下限: ピーク余裕不足")
                return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
            }

            let candidate = MasteringSignalMath.enforcePeakCeiling(
                signal: MasteringSignalMath.applyGain(signal: signal, gainDB: restoreDB),
                peakCeilingDB: peakCeilingDB
            )
            let probePlan = MasteringNoiseReturnSupport.noiseReturnProbePlan(for: signal)
            let baseProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: signal, plan: probePlan)
            let candidateProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: candidate, plan: probePlan)
            guard isFinalLoudnessRestoreNoiseSafe(
                baseProbe: baseProbe,
                candidateProbe: candidateProbe,
                referenceMeasurements: referenceNoiseMeasurements,
                originalReferenceMeasurements: originalReferenceNoiseMeasurements
            ), isFinalLoudnessRestoreMudBalanceSafe(base: signal, candidate: candidate) else {
                logger?.log("最終音量下限: ノイズ保護で見送り")
                return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
            }

            let candidateLoudness = MasteringAnalysisService.integratedLoudness(signal: candidate)
            let appliedRestoreDB = candidateLoudness.isFinite
                ? Double(candidateLoudness - currentLoudness)
                : loudnessDeficitDB
            logger?.log("最終音量下限: \(formatSignedDB(appliedRestoreDB)) / \(policy.label) の下限内へ調整")
            return candidate
        }

        logger?.log("最終音量上限: \(policy.label) の範囲内")
        return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
    }

    func formatSignedDB(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }

    func isFinalLoudnessRestoreNoiseSafe(
        baseProbe: NoiseReturnProbe,
        candidateProbe: NoiseReturnProbe,
        referenceMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceMeasurements: NoiseMeasurementSnapshot?
    ) -> Bool {
        for rule in InternalAudioJudgementPolicy.masteringNoiseReturnLimits {
            guard let baseLevel = baseProbe.comparableLevel(for: rule.id),
                  let candidateLevel = candidateProbe.comparableLevel(for: rule.id)
            else {
                continue
            }
            if candidateLevel > baseLevel + 0.35 {
                return false
            }
            if let referenceLevel = referenceMeasurements?.comparableLevel(for: rule.id) {
                let referenceLimit = referenceLevel + min(rule.allowedReturnDB + 0.35, Self.finalNoiseReturnLimit(for: rule.id))
                if baseLevel <= referenceLimit, candidateLevel > referenceLimit {
                    return false
                }
            }
            if let originalLevel = originalReferenceMeasurements?.comparableLevel(for: rule.id) {
                let originalLimit = originalLevel + max(0.75, rule.allowedReturnDB)
                if baseLevel <= originalLimit, candidateLevel > originalLimit {
                    return false
                }
            }
        }
        return true
    }

    func isFinalLoudnessRestoreMudBalanceSafe(base: AudioSignal, candidate: AudioSignal) -> Bool {
        let baseMud = MasteringSignalMath.bandBalanceDB(signal: base, lower: 300, upper: 1_000)
        let candidateMud = MasteringSignalMath.bandBalanceDB(signal: candidate, lower: 300, upper: 1_000)
        guard baseMud.isFinite, candidateMud.isFinite else { return true }
        return candidateMud <= baseMud + 0.25
    }
}
