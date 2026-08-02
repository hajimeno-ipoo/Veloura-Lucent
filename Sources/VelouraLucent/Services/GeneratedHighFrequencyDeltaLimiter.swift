import Foundation

/// DSPが新しく作った差分だけを20〜21kHzで滑らかに減らします。
/// 入力に元から含まれる超高域は変更しません。
enum GeneratedHighFrequencyDeltaLimiter {
    private static let fullRetentionUpperFrequency = 20_000.0
    private static let zeroRetentionFrequency = 21_000.0

    static func preserveOriginalUltraHigh(
        original: AudioSignal,
        processed: AudioSignal
    ) -> AudioSignal {
        guard original.sampleRate == processed.sampleRate,
              original.channels.count == processed.channels.count,
              zip(original.channels, processed.channels).allSatisfy({ $0.count == $1.count }),
              original.sampleRate * 0.5 > fullRetentionUpperFrequency else {
            return processed
        }

        let channels = zip(original.channels, processed.channels).map { originalChannel, processedChannel in
            let generatedDelta = zip(processedChannel, originalChannel).map(-)
            var spectrogram = SpectralDSP.stft(generatedDelta)
            let frequencyStep = original.sampleRate / Double(spectrogram.fftSize)

            for binIndex in 0..<spectrogram.binCount {
                let frequency = Double(binIndex) * frequencyStep
                let gain = retentionGain(at: frequency)
                guard gain < 1 else { continue }
                for frameIndex in 0..<spectrogram.frameCount {
                    spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
                }
            }

            let limitedDelta = SpectralDSP.istft(spectrogram)
            return zip(originalChannel, limitedDelta).map(+)
        }
        return AudioSignal(channels: channels, sampleRate: original.sampleRate)
    }

    private static func retentionGain(at frequency: Double) -> Float {
        if frequency <= fullRetentionUpperFrequency { return 1 }
        if frequency >= zeroRetentionFrequency { return 0 }

        let position = (frequency - fullRetentionUpperFrequency)
            / (zeroRetentionFrequency - fullRetentionUpperFrequency)
        return Float(0.5 * (1 + cos(.pi * position)))
    }
}
