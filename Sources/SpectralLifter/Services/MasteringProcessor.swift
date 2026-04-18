import Foundation

struct MasteringProcessor {
    func process(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings, logger: AudioProcessingLogger? = nil) -> AudioSignal {
        logger?.log(MasteringStep.tone.rawValue)
        var current = applyTone(signal: signal, analysis: analysis, settings: settings)

        logger?.log(MasteringStep.dynamics.rawValue)
        current = applyBandControl(signal: current, analysis: analysis, amount: settings.bandControlAmount)

        logger?.log(MasteringStep.saturate.rawValue)
        current = applySaturation(signal: current, amount: settings.saturationAmount)

        logger?.log(MasteringStep.stereo.rawValue)
        current = applyStereoWidth(signal: current, targetWidth: settings.stereoWidth)

        logger?.log(MasteringStep.loudness.rawValue)
        return applyLoudness(signal: current, targetLKFS: settings.targetLoudness, peakCeilingDB: settings.peakCeilingDB)
    }

    private func applyTone(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings) -> AudioSignal {
        let lowAdjustment = settings.lowShelfGain + max(0, Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 6))
        let highAdjustment = settings.highShelfGain - analysis.harshnessScore * 0.7 + max(0, Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 8))

        let channels = signal.channels.map { channel in
            let low = SpectralDSP.lowPass(channel, cutoff: 180, sampleRate: signal.sampleRate)
            let high = SpectralDSP.highPass(channel, cutoff: 5_000, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                let boosted = channel[index] + low[index] * lowAdjustment * 0.12 + high[index] * highAdjustment * 0.08
                return tanhf(boosted)
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyBandControl(signal: AudioSignal, analysis: MasteringAnalysis, amount: Float) -> AudioSignal {
        let harshReduction = max(0.86, 1 - analysis.harshnessScore * amount * 0.55)
        let lowLift = 1 + max(0, Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 12)) * amount * 0.4

        let channels = signal.channels.map { channel in
            let low = SpectralDSP.lowPass(channel, cutoff: 220, sampleRate: signal.sampleRate)
            let high = SpectralDSP.highPass(channel, cutoff: 4_500, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                let controlled = channel[index] + low[index] * (lowLift - 1) - high[index] * (1 - harshReduction) * 0.45
                return tanhf(controlled)
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applySaturation(signal: AudioSignal, amount: Float) -> AudioSignal {
        let drive = 1 + amount * 2.8
        let mix = min(max(amount * 0.75, 0), 0.4)

        let channels = signal.channels.map { channel in
            channel.map { sample in
                let saturated = tanhf(sample * drive)
                return sample * (1 - mix) + saturated * mix
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyStereoWidth(signal: AudioSignal, targetWidth: Float) -> AudioSignal {
        guard signal.channels.count >= 2 else { return signal }
        let left = signal.channels[0]
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return signal }

        var widenedLeft = left
        var widenedRight = right
        for index in 0..<count {
            let mid = (left[index] + right[index]) * 0.5
            let side = (left[index] - right[index]) * 0.5 * targetWidth
            widenedLeft[index] = tanhf(mid + side)
            widenedRight[index] = tanhf(mid - side)
        }

        var channels = signal.channels
        channels[0] = widenedLeft
        channels[1] = widenedRight
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyLoudness(signal: AudioSignal, targetLKFS: Float, peakCeilingDB: Float) -> AudioSignal {
        let currentLoudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        let gain = powf(10, (targetLKFS - currentLoudness) / 20)
        let peakCeiling = powf(10, peakCeilingDB / 20)
        var channels = signal.channels.map { channel in channel.map { $0 * gain } }

        var peak = MasteringAnalysisService.approximateTruePeak(channels)
        if peak > peakCeiling {
            let limiterGain = peakCeiling / peak
            channels = channels.map { channel in
                channel.map { tanhf($0 * limiterGain / max(peakCeiling, 1e-6)) * peakCeiling }
            }
            peak = MasteringAnalysisService.approximateTruePeak(channels)
            if peak > peakCeiling {
                let trim = peakCeiling / peak
                channels = channels.map { $0.map { $0 * trim } }
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }
}
