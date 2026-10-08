import Foundation

extension MasteringProcessor {
    func applySaturation(signal: AudioSignal, amount: Float, logger: AudioProcessingLogger? = nil) -> AudioSignal {
        let drive = 1 + amount * 2.8
        let mix = min(max(amount * 0.75, 0), 0.4)
        guard mix > 0 else { return signal }

        let channels = signal.channels.map { channel in
            NonlinearOversampling.process(channel) { sample in
                let saturated = tanhf(sample * drive)
                return sample * (1 - mix) + saturated * mix
            }
        }
        if signal.frameCount > 1 {
            logger?.log("倍音/Oversampling: 4倍処理を適用")
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    func effectiveSaturation(_ amount: Float, dynamicsRetention: Float, finishingIntensity: Float) -> Float {
        amount * MasteringSignalMath.clamped(0.64 + finishingIntensity * 0.52 - dynamicsRetention * 0.24, min: 0.35, max: 1.10)
    }
}
