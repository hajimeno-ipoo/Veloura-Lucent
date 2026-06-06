import Foundation

extension MasteringProcessor {
    func applyDeEsser(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings) -> AudioSignal {
        guard settings.deEsserAmount > 0.001 else { return signal }

        let threshold = powf(10, settings.deEsserThresholdDB / 20)
        let attackCoeff = expf(-1 / max(Float(signal.sampleRate) * 0.002, 1))
        let releaseCoeff = expf(-1 / max(Float(signal.sampleRate) * 0.090, 1))
        let adaptiveAmount = settings.deEsserAmount * (0.55 + analysis.harshnessScore * 0.75)
        let maxReduction = min(0.68, 0.18 + analysis.harshnessScore * 0.28 + settings.deEsserAmount * 0.20)

        let channels = signal.channels.map { channel in
            let detectionBand = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 4_500, sampleRate: signal.sampleRate),
                cutoff: 9_000,
                sampleRate: signal.sampleRate
            )
            let reductionBand = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 5_500, sampleRate: signal.sampleRate),
                cutoff: 11_000,
                sampleRate: signal.sampleRate
            )
            let detectorRMS = sqrtf(detectionBand.reduce(Float.zero) { partial, sample in
                partial + sample * sample
            } / Float(max(detectionBand.count, 1)))
            let adaptiveThreshold = max(1e-5, min(threshold, detectorRMS))

            var envelope: Float = 0
            return channel.indices.map { index in
                let detectorSample = detectionBand[index]
                let level = abs(detectorSample)
                if level > envelope {
                    envelope = attackCoeff * envelope + (1 - attackCoeff) * level
                } else {
                    envelope = releaseCoeff * envelope + (1 - releaseCoeff) * level
                }

                guard envelope > adaptiveThreshold else { return channel[index] }
                let excess = min(3.0, max(0, (envelope - adaptiveThreshold) / max(adaptiveThreshold, 1e-6)))
                let reduction = min(maxReduction, excess * adaptiveAmount * 0.40)
                return channel[index] - reductionBand[index] * reduction
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }
}
