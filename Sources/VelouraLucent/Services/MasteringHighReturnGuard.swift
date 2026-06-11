import Foundation

extension MasteringProcessor {
    func applyHighReturnGuard(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float
    ) -> AudioSignal {
        let reduction = highReturnGuardReduction(
            analysis: analysis,
            settings: settings,
            finishingIntensity: finishingIntensity
        )
        guard reduction > 0.001 else { return signal }

        let channels = signal.channels.map { channel in
            let high = SpectralDSP.highPass(channel, cutoff: 10_000, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                channel[index] - high[index] * reduction
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    func highReturnGuardReduction(
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float
    ) -> Float {
        let harshnessPressure = max(0, analysis.harshnessScore - 0.62) * 0.24
        let airBoostPressure = max(0, settings.highShelfGain - 0.56) * 0.08
        let finishPressure = max(0, finishingIntensity - 0.72) * 0.05
        return MasteringSignalMath.clamped(harshnessPressure + airBoostPressure + finishPressure, min: 0, max: 0.07)
    }

}

