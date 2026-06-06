import Foundation

extension MasteringProcessor {
    func applyTone(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings, finishingIntensity: Float) -> AudioSignal {
        let lowAdjustmentDB = settings.lowShelfGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 18), min: -0.25, max: 1.2)
        let lowMidAdjustmentDB = settings.lowMidGain - MasteringSignalMath.clamped(Float((analysis.lowBandLevelDB - analysis.midBandLevelDB) / 16), min: -0.2, max: 0.7)
        let roomAdjustmentDB = min(0, settings.lowMidGain * 0.45) - max(0, settings.lowShelfGain - 0.70) * 0.10
        let presenceAdjustmentDB = settings.presenceGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 16), min: -0.2, max: 0.8) - analysis.harshnessScore * 0.32
        let highAdjustmentDB = settings.highShelfGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 18), min: -0.25, max: 0.9) - analysis.harshnessScore * 0.55
        let toneScale = 0.72 + finishingIntensity * 0.46

        let lowDelta = MasteringSignalMath.gainDelta(forDB: lowAdjustmentDB) * toneScale
        let lowMidDelta = MasteringSignalMath.gainDelta(forDB: lowMidAdjustmentDB) * toneScale
        let roomDelta = MasteringSignalMath.gainDelta(forDB: roomAdjustmentDB) * toneScale
        let presenceDelta = MasteringSignalMath.gainDelta(forDB: presenceAdjustmentDB) * toneScale
        let highDelta = MasteringSignalMath.gainDelta(forDB: highAdjustmentDB) * toneScale

        let channels = signal.channels.map { channel in
            let low = SpectralDSP.lowPass(channel, cutoff: 120, sampleRate: signal.sampleRate)
            let lowMid = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 120, sampleRate: signal.sampleRate),
                cutoff: 420,
                sampleRate: signal.sampleRate
            )
            let roomLowMid = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 420, sampleRate: signal.sampleRate),
                cutoff: 1_200,
                sampleRate: signal.sampleRate
            )
            let presence = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 2_500, sampleRate: signal.sampleRate),
                cutoff: 5_500,
                sampleRate: signal.sampleRate
            )
            let high = SpectralDSP.highPass(channel, cutoff: 10_000, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                channel[index]
                    + low[index] * lowDelta
                    + lowMid[index] * lowMidDelta
                    + roomLowMid[index] * roomDelta
                    + presence[index] * presenceDelta
                    + high[index] * highDelta
            }
        }

        return applySibilanceAwareBrillianceLift(
            signal: AudioSignal(channels: channels, sampleRate: signal.sampleRate),
            analysis: analysis,
            settings: settings,
            finishingIntensity: finishingIntensity
        )
    }

    private func applySibilanceAwareBrillianceLift(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float
    ) -> AudioSignal {
        let highDeficit = MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 24), min: 0, max: 0.45)
        let baseLiftDB = settings.highShelfGain * 1.05 + highDeficit - analysis.harshnessScore * 0.22
        let liftDB = MasteringSignalMath.clamped(baseLiftDB * (0.70 + finishingIntensity * 0.22), min: 0, max: 1.00)
        guard liftDB > 0.08 else { return signal }

        let gain = powf(10, liftDB / 20)
        let sampleRate = signal.sampleRate
        let channels = mapChannelsConcurrently(signal.channels) {
            sibilanceAwareBrillianceLift(channel: $0, sampleRate: sampleRate, gain: gain)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func sibilanceAwareBrillianceLift(channel: [Float], sampleRate: Double, gain: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let sibilanceStartBin = clampedBin(5_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let sibilanceEndBin = clampedBin(8_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let brillianceStartBin = clampedBin(9_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let brillianceEndBin = clampedBin(12_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        guard sibilanceEndBin > sibilanceStartBin, brillianceEndBin > brillianceStartBin else { return channel }

        var sibilanceEnergy = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            sibilanceEnergy[frameIndex] = bandEnergy(
                spectrogram: spectrogram,
                frameIndex: frameIndex,
                startBin: sibilanceStartBin,
                endBin: sibilanceEndBin
            )
        }
        let transientThreshold = max(SpectralDSP.percentile(sibilanceEnergy, 50) * 1.05, 1e-7)

        for frameIndex in 0..<spectrogram.frameCount {
            let frameGain = sibilanceEnergy[frameIndex] > transientThreshold ? 1.0 : gain
            guard frameGain > 1.0001 else { continue }
            for binIndex in brillianceStartBin...brillianceEndBin {
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: frameGain)
            }
        }

        return SpectralDSP.istft(spectrogram)
    }

    private func bandEnergy(spectrogram: Spectrogram, frameIndex: Int, startBin: Int, endBin: Int) -> Float {
        var sum: Float = 0
        for binIndex in startBin...endBin {
            let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            sum += magnitude * magnitude
        }
        return sum / Float(max(1, endBin - startBin + 1))
    }

    private func clampedBin(_ frequency: Double, frequencyStep: Double, binCount: Int) -> Int {
        min(max(Int(frequency / frequencyStep), 0), binCount - 1)
    }
}
