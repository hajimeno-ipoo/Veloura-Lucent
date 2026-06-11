import Foundation

extension MasteringProcessor {
    func guidedLoudnessTarget(
        currentLoudness: Float,
        requestedTargetLKFS: Float,
        policy: LoudnessAdjustmentPolicy,
        logger: AudioProcessingLogger?
    ) -> Float {
        guard currentLoudness.isFinite, currentLoudness > -69 else {
            logger?.log("ラウドネス方針: \(policy.label) / 無音に近いため音量変更なし")
            return currentLoudness
        }

        let requestedDeltaDB = Double(requestedTargetLKFS - currentLoudness)
        let appliedDeltaDB: Double
        if abs(requestedDeltaDB) < policy.deadbandDB {
            appliedDeltaDB = 0
        } else if requestedDeltaDB > 0 {
            appliedDeltaDB = min(requestedDeltaDB, policy.maxBoostDB)
        } else {
            appliedDeltaDB = max(requestedDeltaDB, -policy.maxCutDB)
        }

        logger?.log(
            "ラウドネス方針: \(policy.label) / 目安差 \(formatSignedDB(requestedDeltaDB)) -> 適用 \(formatSignedDB(appliedDeltaDB))"
        )
        return currentLoudness + Float(appliedDeltaDB)
    }

    func applyLoudness(signal: AudioSignal, targetLKFS: Float, peakCeilingDB: Float) -> AudioSignal {
        let currentLoudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        guard currentLoudness.isFinite, targetLKFS.isFinite, currentLoudness > -69 else {
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }
        let gain = powf(10, (targetLKFS - currentLoudness) / 20)
        let peakCeiling = powf(10, peakCeilingDB / 20)
        let gainedChannels = signal.channels.map { channel in channel.map { $0 * gain } }
        var channels = MasteringSignalMath.applyLookaheadLimiter(gainedChannels, peakCeiling: peakCeiling, sampleRate: signal.sampleRate)

        let peak = MasteringAnalysisService.approximateTruePeak(channels)
        if peak > peakCeiling {
            let trim = peakCeiling / peak
            channels = channels.map { $0.map { $0 * trim } }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    func effectiveTargetLoudness(_ target: Float, dynamicsRetention: Float, finishingIntensity: Float) -> Float {
        target + (finishingIntensity - 0.5) * 0.9 - dynamicsRetention * 0.45
    }

}

