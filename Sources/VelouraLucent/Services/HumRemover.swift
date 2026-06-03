import Foundation

struct HumRemover: Sendable {
    let settings: CorrectionSettings

    func process(signal: AudioSignal) -> AudioSignal {
        let detectedBase = dominantHumBase(signal: signal)
        guard let detectedBase else { return signal }

        let intensity = clamped(settings.lowCleanup * 0.55 + settings.noiseDetectionSensitivity * 0.35, min: 0, max: 1)
        let channels = mapChannelsConcurrently(signal.channels) { channel in
            attenuateHarmonics(channel: channel, sampleRate: signal.sampleRate, baseFrequency: detectedBase, intensity: intensity)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func dominantHumBase(signal: AudioSignal) -> Double? {
        let mono = signal.monoMixdown()
        guard mono.count > 512 else { return nil }

        let candidates = [50.0, 60.0].map { base in
            (base: base, score: humScore(mono: mono, sampleRate: signal.sampleRate, baseFrequency: base))
        }
        guard let best = candidates.max(by: { $0.score < $1.score }), best.score > 8 else {
            return nil
        }
        return best.base
    }

    private func humScore(mono: [Float], sampleRate: Double, baseFrequency: Double) -> Double {
        var harmonic = baseFrequency
        var score = 0.0
        var count = 0
        while harmonic <= min(300, sampleRate * 0.5 - 30) {
            let center = sineMagnitudeDB(mono, frequency: harmonic, sampleRate: sampleRate)
            let lower = sineMagnitudeDB(mono, frequency: max(20, harmonic - 17), sampleRate: sampleRate)
            let upper = sineMagnitudeDB(mono, frequency: min(sampleRate * 0.5 - 20, harmonic + 17), sampleRate: sampleRate)
            score += max(0, center - (lower + upper) * 0.5)
            count += 1
            harmonic += baseFrequency
        }
        return score / Double(max(count, 1))
    }

    private func sineMagnitudeDB(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double {
        var real = 0.0
        var imag = 0.0
        let angular = 2 * Double.pi * frequency / sampleRate
        let cosStep = cos(angular)
        let sinStep = sin(angular)
        var cosine = 1.0
        var sine = 0.0
        for sampleValue in samples {
            let sample = Double(sampleValue)
            real += sample * cosine
            imag -= sample * sine
            let nextCosine = cosine * cosStep - sine * sinStep
            sine = sine * cosStep + cosine * sinStep
            cosine = nextCosine
        }
        let magnitude = sqrt(real * real + imag * imag) * 2 / Double(max(samples.count, 1))
        return 20 * log10(max(magnitude, 1e-12))
    }

    private func attenuateHarmonics(channel: [Float], sampleRate: Double, baseFrequency: Double, intensity: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }

        let frameEnergy = spectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(frameEnergy, 20)
        let activeThreshold = max(SpectralDSP.percentile(frameEnergy, 50), quietThreshold + 1e-9)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        var harmonic = baseFrequency
        var harmonicIndex = 1
        while harmonic <= min(300, sampleRate * 0.5 - 30) {
            let centerBin = min(max(Int(round(harmonic / frequencyStep)), 0), spectrogram.binCount - 1)
            let reduction = clamped((0.46 - Float(harmonicIndex - 1) * 0.055) * intensity, min: 0.10, max: 0.46)
            for frameIndex in 0..<spectrogram.frameCount {
                let frameReduction = reduction * HumRemovalFrameAttenuation.scale(
                    spectrogram: spectrogram,
                    frameIndex: frameIndex,
                    centerBin: centerBin,
                    frameEnergy: frameEnergy[frameIndex],
                    quietThreshold: quietThreshold,
                    activeThreshold: activeThreshold
                )
                for binIndex in max(0, centerBin - 1)...min(spectrogram.binCount - 1, centerBin + 1) {
                    let distance = abs(binIndex - centerBin)
                    let gain = 1 - frameReduction * (distance == 0 ? 1 : 0.45)
                    spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
                }
            }
            harmonicIndex += 1
            harmonic += baseFrequency
        }

        return SpectralDSP.istft(spectrogram)
    }
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.max(minValue, Swift.min(value, maxValue))
}
