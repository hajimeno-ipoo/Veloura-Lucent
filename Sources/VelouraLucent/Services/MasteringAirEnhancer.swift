import Foundation

struct MasteringAirEnhancer {
    func process(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let harshnessGuard = MasteringSignalMath.clamped(1 - analysis.harshnessScore * 0.62, min: 0.28, max: 1)
        let requestedAir = settings.saturationAmount * 0.030
        let adaptiveAir = MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 42), min: 0, max: 0.055)
        let amount = MasteringSignalMath.clamped((requestedAir + adaptiveAir) * (0.55 + finishingIntensity * 0.65) * harshnessGuard, min: 0, max: 0.11)
        let before = MasteringSignalMath.bandRMSDB(signal: signal, lower: 10_000, upper: 20_000)
        guard amount > 0.001 else {
            logger?.log(
                "高域調整/Air: 処理前 \(String(format: "%.2f", before)) dB / 適用量 0.00 dB / "
                    + "処理後 \(String(format: "%.2f", before)) dB / 理由 高域不足なし"
            )
            return signal
        }

        let channels = mapChannelsConcurrently(signal.channels) { channel in
            let excited = channel.map { tanhf($0 * 2.4) - tanhf($0 * 1.08) }
            let presence = SpectralDSP.lowPass(
                SpectralDSP.highPass(excited, cutoff: 5_500, sampleRate: signal.sampleRate),
                cutoff: 10_000,
                sampleRate: signal.sampleRate
            )
            let air = SpectralDSP.highPass(excited, cutoff: 10_000, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                tanhf(channel[index] + presence[index] * amount * 0.45 + air[index] * amount)
            }
        }

        let result = AudioSignal(channels: channels, sampleRate: signal.sampleRate)
        let after = MasteringSignalMath.bandRMSDB(signal: result, lower: 10_000, upper: 20_000)
        logger?.log(
            "高域調整/Air: 処理前 \(String(format: "%.2f", before)) dB / "
                + "適用量 \(String(format: "%+.2f", after - before)) dB / "
                + "処理後 \(String(format: "%.2f", after)) dB / 理由 高域不足と既存の倍音設定から算出"
        )
        return result
    }
}
