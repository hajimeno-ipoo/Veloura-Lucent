import Foundation

struct LowMidResidueGuard: Sendable {
    let settings: CorrectionSettings

    func process(signal: AudioSignal) -> AudioSignal {
        let defaults = settings.profile.settings
        let intensity = clamped(
            0.10 + settings.lowMidCleanup * 0.20 + max(0, settings.lowMidCleanup - defaults.lowMidCleanup) * 0.35,
            min: 0.08,
            max: 0.32
        )
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate, intensity: intensity)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processChannel(_ channel: [Float], sampleRate: Double, intensity: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let startBin = min(max(Int(200 / frequencyStep), 0), spectrogram.binCount - 1)
        let endBin = min(max(Int(1_000 / frequencyStep), startBin), spectrogram.binCount - 1)
        guard endBin > startBin else { return channel }

        var bandEnergy = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            for binIndex in startBin...endBin {
                sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            bandEnergy[frameIndex] = sum / Float(endBin - startBin + 1)
        }

        let sustainedThreshold = SpectralDSP.percentile(bandEnergy, 62)
        for frameIndex in 0..<spectrogram.frameCount where bandEnergy[frameIndex] <= sustainedThreshold {
            let reduction = intensity * (1 - bandEnergy[frameIndex] / max(sustainedThreshold, 1e-6))
            let gain = 1 - reduction
            for binIndex in startBin...endBin {
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
            }
        }

        return SpectralDSP.istft(spectrogram)
    }
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.min(maxValue, Swift.max(minValue, value))
}
