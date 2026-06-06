import Foundation

struct CorrectionHarmonicRepair: Sendable {
    let settings: CorrectionSettings

    func process(signal: AudioSignal, analysis: AnalysisData, prediction: NeuralFoldoverPrediction) -> AudioSignal {
        let defaults = settings.profile.settings
        let cutoff = max(analysis.cutoffFrequency - 1_000, 12_000)
        let harmonicWeight = min(1.25, 0.55 + Float(analysis.dominantHarmonics.count) * 0.08 + analysis.harmonicConfidence * 0.26)
        let shimmerControl = analysis.hasShimmer ? max(0.65, 1 - analysis.shimmerRatio * 1.4) : 1.0
        let deficiency = Float(max(0, 16_000 - analysis.cutoffFrequency) / 4_000)
        let brightnessBoost = max(0.9, min(1.2, 1.02 + (0.55 - analysis.brightnessRatio) * 0.35))
        let harmonicScale = clamped(1 + (settings.harmonicRepairAmount - defaults.harmonicRepairAmount) * 0.70 + (settings.presenceRepair - defaults.presenceRepair) * 0.25, min: 0.60, max: 1.45)
        let noiseGuard = clamped(1.0 - analysis.noiseAmount * 0.60 - analysis.artifactBandRatio * 0.50, min: 0.25, max: 1.0)
        let airScale = clamped(0.35 + (settings.airRepair - defaults.airRepair) * 0.28 - (settings.highNaturalness - defaults.highNaturalness) * 0.30, min: 0.18, max: 0.58) * noiseGuard
        let transientScale = clamped(0.42 + (settings.presenceRepair - defaults.presenceRepair) * 0.20, min: 0.24, max: 0.62) * noiseGuard
        let foldoverScale = clamped(1 + (settings.foldoverRepairAmount - defaults.foldoverRepairAmount) * 0.85 - (settings.highNaturalness - defaults.highNaturalness) * 0.25, min: 0.45, max: 1.45)
        let cleanupGuard = clamped(1 - settings.correctionIntensity * 0.58 - settings.noiseDetectionSensitivity * 0.18, min: 0.28, max: 1.0)
        let baseGain = max(0.03, min(0.16, (0.06 + deficiency * 0.05) * harmonicWeight * shimmerControl)) * harmonicScale * noiseGuard * cleanupGuard
        let airGain = max(
            0,
            min(0.16, (0.05 + deficiency * 0.08) * brightnessBoost - analysis.shimmerRatio * 0.04 + prediction.airGainBias * 0.45)
        ) * (1 - prediction.harshnessGuard * 0.55) * airScale * cleanupGuard
        let transientBoost = max(
            0,
            min(0.12, 0.04 + analysis.transientAmount * 0.03 + prediction.transientBoostBias * 0.45)
        ) * (1 - prediction.harshnessGuard * 0.35) * transientScale * cleanupGuard
        let foldoverMix = max(
            0.02,
            min(0.22, 0.05 + deficiency * 0.11 + analysis.harmonicConfidence * 0.06 - analysis.shimmerRatio * 0.06 + prediction.foldoverMix * 0.70 - 0.12)
        ) * (1 - prediction.harshnessGuard * 0.62) * foldoverScale * noiseGuard * cleanupGuard

        let channels = mapChannelsConcurrently(signal.channels) { channel in
            let folded = foldover(channel: channel, sampleRate: signal.sampleRate, cutoff: cutoff, mix: foldoverMix)
            let excited = channel.map { tanhf($0 * 2.8) - tanhf($0 * 1.1) }
            let presence = SpectralDSP.lowPass(SpectralDSP.highPass(excited, cutoff: cutoff, sampleRate: signal.sampleRate), cutoff: 13_500, sampleRate: signal.sampleRate)
            let air = SpectralDSP.highPass(excited, cutoff: 13_500, sampleRate: signal.sampleRate)
            let body = SpectralDSP.lowPass(channel, cutoff: 4_000, sampleRate: signal.sampleRate)
            let transient = SpectralDSP.highPass(zip(channel, body).map(-), cutoff: 2_500, sampleRate: signal.sampleRate)
            return channel.indices.map {
                let mixed = channel[$0]
                    + folded[$0]
                    + presence[$0] * baseGain
                    + air[$0] * airGain
                    + transient[$0] * transientBoost
                return tanhf(mixed * 0.98)
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func foldover(channel: [Float], sampleRate: Double, cutoff: Double, mix: Float) -> [Float] {
        let fftSize = SpectralDSP.fftSize
        let binCount = fftSize / 2 + 1
        let frequencyStep = sampleRate / Double(fftSize)
        let sourceStart = max(1, min(Int(max(cutoff * 0.5, 5_500) / frequencyStep), binCount - 1))
        let sourceEnd = max(sourceStart, min(Int(min(cutoff * 0.95, 12_000) / frequencyStep), binCount - 1))
        let targetStart = max(sourceStart + 1, min(Int(16_000 / frequencyStep), binCount - 1))
        guard sourceEnd > sourceStart, targetStart < binCount else {
            return Array(repeating: 0, count: channel.count)
        }

        var activeBins: [Int] = []
        var seenBins = Set<Int>()
        for sourceBin in sourceStart...sourceEnd {
            let targetBin = min(binCount - 1, sourceBin * 2)
            guard targetBin >= targetStart, seenBins.insert(targetBin).inserted else { continue }
            activeBins.append(targetBin)
        }

        return SpectralDSP.istftSparseHalfSpectrumFromSTFTFrames(
            channel,
            activeBins: activeBins
        ) { _, sourceBinCount, sourceReal, sourceImag, realFrame, imagFrame in
            for sourceBin in sourceStart...sourceEnd {
                let targetBin = min(sourceBinCount - 1, sourceBin * 2)
                guard targetBin >= targetStart else { continue }
                let normalizedPosition = Float(targetBin - targetStart) / Float(max(sourceBinCount - targetStart - 1, 1))
                let lift = mix * (1 - normalizedPosition * 0.45)
                realFrame[targetBin] += sourceReal[sourceBin] * lift
                imagFrame[targetBin] += sourceImag[sourceBin] * lift
            }
        }
    }
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.min(maxValue, Swift.max(minValue, value))
}
