import Foundation

struct RumbleReducer: Sendable {
    let settings: CorrectionSettings

    func process(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot? = nil,
        logger: AudioProcessingLogger? = nil
    ) -> AudioSignal {
        let intensity = clamped(settings.lowCleanup * 0.68 + settings.noiseDetectionSensitivity * 0.22, min: 0, max: 1)
        guard intensity > 0.05 else {
            logger?.log("低域ノイズ/測定回数: 0")
            return signal
        }
        let activeLowBodyScale = RumbleFrameAttenuation.activeMusicScale(correctionIntensity: settings.correctionIntensity)
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate, intensity: intensity, activeLowBodyScale: activeLowBodyScale)
        }
        return adaptiveRumbleLimit(
            signal: AudioSignal(channels: channels, sampleRate: signal.sampleRate),
            reference: reference,
            referenceMeasurements: referenceMeasurements,
            logger: logger
        )
    }

    private func adaptiveRumbleLimit(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot?,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let improvementDB = settings.correctionIntensity >= 0.65 ? 3.2 : (settings.correctionIntensity >= 0.45 ? 1.2 : 0.0)
        guard improvementDB > 0 else {
            logger?.log("低域ノイズ/測定回数: 0")
            return signal
        }

        let measurements = referenceMeasurements?.comparableLevel(for: NoiseMeasurementID.rumble) == nil
            ? NoiseMeasurementService.analyze(signal: reference, ids: [NoiseMeasurementID.rumble])
            : referenceMeasurements!
        guard let referenceRumble = measurements.comparableLevel(for: NoiseMeasurementID.rumble) else {
            logger?.log("低域ノイズ/測定回数: 0")
            return signal
        }
        let target = referenceRumble - improvementDB
        var currentSignal = signal
        var measurementCount = 0
        for _ in 0..<4 {
            measurementCount += 1
            guard let current = NoiseMeasurementService.analyze(signal: currentSignal, ids: [NoiseMeasurementID.rumble]).comparableLevel(for: NoiseMeasurementID.rumble) else {
                logger?.log("低域ノイズ/測定回数: \(measurementCount)")
                return currentSignal
            }
            let excessDB = max(0, current - target)
            guard excessDB > 0.1 else {
                logger?.log("低域ノイズ/測定回数: \(measurementCount)")
                return currentSignal
            }

            let gain = powf(10, -Float(min(excessDB, 48)) / 20)
            let sampleRate = currentSignal.sampleRate
            let channels = mapChannelsConcurrently(currentSignal.channels) {
                scaleBand($0, sampleRate: sampleRate, lower: 20, upper: 150, gain: gain)
            }
            currentSignal = AudioSignal(channels: channels, sampleRate: sampleRate)
        }
        logger?.log("低域ノイズ/測定回数: \(measurementCount)")
        return currentSignal
    }

    private func scaleBand(_ channel: [Float], sampleRate: Double, lower: Double, upper: Double, gain: Float) -> [Float] {
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(channel, cutoff: lower, sampleRate: sampleRate),
            cutoff: min(upper, sampleRate * 0.5 - 100),
            sampleRate: sampleRate
        )
        let reduction = 1 - gain
        return channel.indices.map { index in
            channel[index] - band[index] * reduction
        }
    }

    private func processChannel(_ channel: [Float], sampleRate: Double, intensity: Float, activeLowBodyScale: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }
        let frameEnergy = spectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(frameEnergy, 20)
        let activeThreshold = max(SpectralDSP.percentile(frameEnergy, 50), quietThreshold + 1e-9)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let endBin = min(max(Int(150 / frequencyStep), 0), spectrogram.binCount - 1)

        for binIndex in 0...endBin {
            let frequency = Double(binIndex) * frequencyStep
            let bandWeight: Float
            if frequency < 20 {
                bandWeight = 0.95
            } else if frequency < 35 {
                bandWeight = 0.82
            } else if frequency < 80 {
                bandWeight = 1.25
            } else {
                bandWeight = 0.50
            }
            for frameIndex in 0..<spectrogram.frameCount {
                let frameScale = RumbleFrameAttenuation.scale(
                    frequency: frequency,
                    frameEnergy: frameEnergy[frameIndex],
                    quietThreshold: quietThreshold,
                    activeThreshold: activeThreshold,
                    activeScale: activeLowBodyScale
                )
                let gain = clamped(1 - bandWeight * intensity * frameScale, min: 0.05, max: 1)
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
            }
        }

        return SpectralDSP.istft(spectrogram)
    }
}

struct RumbleFrameAttenuation: Sendable {
    static let activeMusicScale: Float = 0.60
    private static let balancedCorrectionIntensity: Float = 0.50
    private static let strongCorrectionIntensity: Float = 0.72

    static func activeMusicScale(correctionIntensity: Float) -> Float {
        if correctionIntensity <= balancedCorrectionIntensity { return activeMusicScale }
        if correctionIntensity >= strongCorrectionIntensity { return 1.0 }
        let progress = (correctionIntensity - balancedCorrectionIntensity)
            / (strongCorrectionIntensity - balancedCorrectionIntensity)
        return activeMusicScale + (1.0 - activeMusicScale) * progress
    }

    static func scale(
        frequency: Double,
        frameEnergy: Float,
        quietThreshold: Float,
        activeThreshold: Float,
        activeScale: Float = activeMusicScale
    ) -> Float {
        guard frequency >= 60, frequency < 150 else {
            return 1
        }
        return scale(
            frameEnergy: frameEnergy,
            quietThreshold: quietThreshold,
            activeThreshold: activeThreshold,
            activeScale: activeScale
        )
    }

    static func scale(
        frameEnergy: Float,
        quietThreshold: Float,
        activeThreshold: Float,
        activeScale: Float
    ) -> Float {
        if frameEnergy <= quietThreshold { return 1 }
        if frameEnergy >= activeThreshold { return activeScale }
        let position = (frameEnergy - quietThreshold) / max(activeThreshold - quietThreshold, 1e-9)
        return 1 - (1 - activeScale) * position
    }
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.min(maxValue, Swift.max(minValue, value))
}
