import Foundation

protocol AudioProcessingLogger {
    func log(_ message: String)
}

struct NativeAudioProcessor {
    func process(
        inputFile: URL,
        outputFile: URL,
        denoiseStrength: DenoiseStrength = .balanced,
        logger: AudioProcessingLogger? = nil
    ) throws {
        logger?.log("入力音声を読み込みます")
        let signal = try AudioFileService.loadAudio(from: inputFile)

        logger?.log("音声を解析します")
        let analysis = AudioAnalyzer().analyze(signal: signal)

        logger?.log("ノイズを除去します")
        let denoised = SpectralGateDenoiser(strength: denoiseStrength).process(signal: signal)

        logger?.log("高域を補完します")
        let upscaled = HarmonicUpscaler().process(signal: denoised, analysis: analysis)

        logger?.log("ダイナミクスを整えます")
        let shaped = MultibandDynamicsProcessor().process(signal: upscaled)

        logger?.log("最終音量を整えます")
        let finalized = LoudnessProcessor().process(signal: shaped)

        logger?.log("処理済みファイルを書き出します")
        try AudioFileService.saveAudio(finalized, to: outputFile)
        logger?.log("処理が完了しました")
    }
}

private struct AudioAnalyzer {
    func analyze(signal: AudioSignal) -> AnalysisData {
        let mono = signal.monoMixdown()
        let spectrogram = SpectralDSP.stft(mono)
        guard spectrogram.frameCount > 0 else {
            return AnalysisData(cutoffFrequency: 16_000, dominantHarmonics: [], hasShimmer: false, shimmerRatio: 0, brightnessRatio: 0, transientAmount: 0)
        }

        let meanSpectrum = SpectralDSP.medianFilter(spectrogram.meanMagnitudes(), windowSize: 5)

        let frequencyStep = signal.sampleRate / Double(spectrogram.fftSize)
        let decibels = SpectralDSP.amplitudeToDecibels(meanSpectrum)
        let cutoffStart = Int(12_000 / frequencyStep)
        let cutoffEnd = min(Int(16_000 / frequencyStep), decibels.count - 1)
        var cutoff = 16_000.0
        var steepestDrop = Float.greatestFiniteMagnitude
        if cutoffEnd > cutoffStart + 1 {
            for index in cutoffStart..<(cutoffEnd - 1) {
                let delta = decibels[index + 1] - decibels[index]
                if delta < steepestDrop {
                    steepestDrop = delta
                    cutoff = Double(index) * frequencyStep
                }
            }
        }

        let harmonicStart = Int(300 / frequencyStep)
        let harmonicEnd = min(Int(800 / frequencyStep), meanSpectrum.count - 1)
        var peaks: [HarmonicPeak] = []
        if harmonicEnd > harmonicStart + 1 {
            for index in (harmonicStart + 1)..<harmonicEnd {
                let value = meanSpectrum[index]
                if value > meanSpectrum[index - 1], value >= meanSpectrum[index + 1], value > 0.1 {
                    peaks.append(HarmonicPeak(frequency: Double(index) * frequencyStep, magnitude: value))
                }
            }
        }

        let shimmerStart = min(Int(10_000 / frequencyStep), meanSpectrum.count - 1)
        let shimmerEnd = min(Int(14_000 / frequencyStep), meanSpectrum.count - 1)
        let shimmerEnergy = meanSpectrum[shimmerStart...shimmerEnd].reduce(0, +)
        let bodyEnergy = meanSpectrum[0...min(200, meanSpectrum.count - 1)].reduce(0, +)
        let upperBandStart = min(Int(16_000 / frequencyStep), meanSpectrum.count - 1)
        let upperBandEnergy = meanSpectrum[upperBandStart...(meanSpectrum.count - 1)].reduce(0, +)
        let centroid = SpectralDSP.spectralCentroid(meanSpectrum, sampleRate: signal.sampleRate, fftSize: spectrogram.fftSize)
        let brightnessRatio = Float(centroid / max(signal.sampleRate * 0.5, 1))
        let transientAmount = estimateTransientAmount(mono)
        let shimmerRatio = shimmerEnergy / max(bodyEnergy + upperBandEnergy, 1e-6)

        return AnalysisData(
            cutoffFrequency: cutoff,
            dominantHarmonics: peaks.sorted { $0.magnitude > $1.magnitude }.prefix(8).map { $0 },
            hasShimmer: shimmerEnergy > bodyEnergy * 0.05 || steepestDrop < -4,
            shimmerRatio: shimmerRatio,
            brightnessRatio: brightnessRatio,
            transientAmount: transientAmount
        )
    }

    private func estimateTransientAmount(_ signal: [Float]) -> Float {
        guard signal.count > 2 else { return 0 }
        var diff = Array(repeating: Float.zero, count: signal.count - 1)
        for index in 1..<signal.count {
            diff[index - 1] = abs(signal[index] - signal[index - 1])
        }
        let averageDiff = diff.reduce(0, +) / Float(diff.count)
        let averageLevel = max(signal.map { abs($0) }.reduce(0, +) / Float(signal.count), 1e-6)
        return min(1.5, averageDiff / averageLevel)
    }
}

private struct SpectralGateDenoiser {
    let strength: DenoiseStrength

    private var tuning: DenoiseTuning {
        switch strength {
        case .gentle:
            return DenoiseTuning(passes: 1, thresholdMultiplier: 1.28, lowBandFloor: 0.22, highBandFloor: 0.33, quietPercentile: 16, transientProtection: 0.28)
        case .balanced:
            return DenoiseTuning(passes: 2, thresholdMultiplier: 1.46, lowBandFloor: 0.16, highBandFloor: 0.28, quietPercentile: 20, transientProtection: 0.22)
        case .strong:
            return DenoiseTuning(passes: 3, thresholdMultiplier: 1.68, lowBandFloor: 0.11, highBandFloor: 0.22, quietPercentile: 26, transientProtection: 0.16)
        }
    }

    func process(signal: AudioSignal) -> AudioSignal {
        let channels = signal.channels.map { channel in
            var current = channel
            for _ in 0..<tuning.passes {
                current = processPass(current)
            }
            return current
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processPass(_ channel: [Float]) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }
        let binCount = spectrogram.binCount
        var noiseProfile = Array(repeating: Float.zero, count: binCount)
        let frameEnergy = spectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(frameEnergy, tuning.quietPercentile)
        let quietFrameIndices = frameEnergy.enumerated().compactMap { index, value in
            value <= quietThreshold ? index : nil
        }
        let sourceFrameIndices = quietFrameIndices.isEmpty ? Array(0..<spectrogram.frameCount) : quietFrameIndices
        var noiseSums = Array(repeating: Float.zero, count: binCount)
        var noiseMinimums = Array(repeating: Float.greatestFiniteMagnitude, count: binCount)
        let smoothedFrameEnergy = SpectralDSP.movingAverage(frameEnergy, windowSize: 7)

        for frameIndex in sourceFrameIndices {
            for binIndex in 0..<binCount {
                let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
                noiseSums[binIndex] += magnitude
                noiseMinimums[binIndex] = min(noiseMinimums[binIndex], magnitude)
            }
        }

        let sourceCount = Float(max(sourceFrameIndices.count, 1))
        for binIndex in 0..<binCount {
            let averageNoise = noiseSums[binIndex] / sourceCount
            let minimumNoise = noiseMinimums[binIndex].isFinite ? noiseMinimums[binIndex] : averageNoise
            let baseNoise = averageNoise * 0.8 + minimumNoise * 0.2
            let normalizedBand = Float(binIndex) / Float(max(binCount - 1, 1))
            let highBandBias: Float = 0.94 + powf(normalizedBand, 1.25) * 0.18
            noiseProfile[binIndex] = baseNoise * highBandBias
        }

        for frameIndex in 0..<spectrogram.frameCount {
            let transientRatio = frameEnergy[frameIndex] / max(smoothedFrameEnergy[frameIndex], 1e-6)
            let transientLift = max(0, min(0.35, (transientRatio - 1) * tuning.transientProtection))
            for binIndex in 0..<spectrogram.binCount {
                let magnitude = hypotf(spectrogram.real[frameIndex][binIndex], spectrogram.imag[frameIndex][binIndex])
                let normalizedBand = Float(binIndex) / Float(max(spectrogram.binCount - 1, 1))
                let threshold = noiseProfile[binIndex] * tuning.thresholdMultiplier * (0.92 + powf(normalizedBand, 1.1) * 0.24)
                let floor = tuning.lowBandFloor + (tuning.highBandFloor - tuning.lowBandFloor) * powf(normalizedBand, 1.25)
                let rawMask = max(floor, min(1.0, (magnitude - threshold) / max(magnitude, 1e-6)))
                let mask = min(1.0, rawMask + transientLift)
                spectrogram.real[frameIndex][binIndex] *= mask
                spectrogram.imag[frameIndex][binIndex] *= mask
            }
        }

        return SpectralDSP.istft(spectrogram)
    }
}

private struct DenoiseTuning {
    let passes: Int
    let thresholdMultiplier: Float
    let lowBandFloor: Float
    let highBandFloor: Float
    let quietPercentile: Float
    let transientProtection: Float
}

private struct MultibandDynamicsProcessor {
    let bands: [(ClosedRange<Double>, Float, Float)] = [
        (5_000...8_000, 3.0, 80),
        (10_000...14_000, 3.2, 68),
        (18_000...24_000, 2.8, 82)
    ]

    func process(signal: AudioSignal) -> AudioSignal {
        let channels = signal.channels.map { processChannel($0, sampleRate: signal.sampleRate) }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processChannel(_ channel: [Float], sampleRate: Double) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)

        for (band, reductionDB, percentile) in bands {
            let start = min(Int(band.lowerBound / frequencyStep), spectrogram.binCount - 1)
            let end = min(Int(band.upperBound / frequencyStep), spectrogram.binCount - 1)
            guard end > start else { continue }

            let bandEnergy: [Float] = (0..<spectrogram.frameCount).map { frameIndex in
                let values = (start...end).map { hypotf(spectrogram.real[frameIndex][$0], spectrogram.imag[frameIndex][$0]) }
                return values.reduce(0, +) / Float(values.count)
            }
            let threshold = SpectralDSP.percentile(bandEnergy, percentile)
            let reductionLinear = powf(10, -reductionDB / 20)
            let mask = SpectralDSP.movingAverage(bandEnergy.map { energy in
                energy > threshold ? reductionLinear + (1 - reductionLinear) * (threshold / max(energy, 1e-6)) : 1
            }, windowSize: 5)

            for frameIndex in 0..<spectrogram.frameCount {
                let gain = max(reductionLinear, min(1.0, mask[frameIndex]))
                for binIndex in start...end {
                    spectrogram.real[frameIndex][binIndex] *= gain
                    spectrogram.imag[frameIndex][binIndex] *= gain
                }
            }
        }

        return SpectralDSP.istft(spectrogram)
    }
}

private struct HarmonicUpscaler {
    func process(signal: AudioSignal, analysis: AnalysisData) -> AudioSignal {
        let cutoff = max(analysis.cutoffFrequency - 1_000, 12_000)
        let harmonicWeight = min(1.2, 0.6 + Float(analysis.dominantHarmonics.count) * 0.08)
        let shimmerControl = analysis.hasShimmer ? max(0.65, 1 - analysis.shimmerRatio * 1.4) : 1.0
        let deficiency = Float(max(0, 16_000 - analysis.cutoffFrequency) / 4_000)
        let brightnessBoost = max(0.9, min(1.2, 1.02 + (0.55 - analysis.brightnessRatio) * 0.35))
        let baseGain = max(0.05, min(0.18, (0.08 + deficiency * 0.08) * harmonicWeight * shimmerControl))
        let airGain = max(0.10, min(0.42, (0.12 + deficiency * 0.24) * brightnessBoost - analysis.shimmerRatio * 0.03))
        let transientBoost = max(0.10, min(0.30, 0.14 + analysis.transientAmount * 0.08))

        let channels = signal.channels.map { channel in
            let excited = channel.map { tanhf($0 * 2.8) - tanhf($0 * 1.1) }
            let presence = SpectralDSP.lowPass(SpectralDSP.highPass(excited, cutoff: cutoff, sampleRate: signal.sampleRate), cutoff: 13_500, sampleRate: signal.sampleRate)
            let air = SpectralDSP.highPass(excited, cutoff: 13_500, sampleRate: signal.sampleRate)
            let body = SpectralDSP.lowPass(channel, cutoff: 4_000, sampleRate: signal.sampleRate)
            let transient = SpectralDSP.highPass(zip(channel, body).map(-), cutoff: 2_500, sampleRate: signal.sampleRate)
            return channel.indices.map {
                let mixed = channel[$0] + presence[$0] * baseGain + air[$0] * airGain + transient[$0] * transientBoost
                return tanhf(mixed * 0.98)
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }
}

private struct LoudnessProcessor {
    let targetLKFS: Float = -14
    let peakLimitDB: Float = -1
    let limiterReleaseMs: Float = 120

    func process(signal: AudioSignal) -> AudioSignal {
        let loudness = integratedLoudness(signal)
        let gain = powf(10, (targetLKFS - loudness) / 20)
        let peakLimit = powf(10, peakLimitDB / 20)

        let gainedChannels = signal.channels.map { channel in
            channel.map { $0 * gain }
        }
        var channels = applyLinkedLimiter(gainedChannels, peakLimit: peakLimit, sampleRate: signal.sampleRate)

        let peak = approximateTruePeak(channels: channels)
        if peak > peakLimit {
            let trim = peakLimit / peak
            channels = channels.map { $0.map { $0 * trim } }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyLinkedLimiter(_ channels: [[Float]], peakLimit: Float, sampleRate: Double) -> [[Float]] {
        guard let first = channels.first else { return channels }
        guard first.count > 0 else { return channels }

        let releaseCoeff = expf(-1 / max(Float(sampleRate) * limiterReleaseMs * 0.001, 1))
        var gain: Float = 1
        var limited = channels

        for index in 0..<first.count {
            let framePeak = channels.reduce(Float.zero) { partial, channel in
                guard index < channel.count else { return partial }
                return max(partial, abs(channel[index]))
            }

            let desiredGain = framePeak > peakLimit ? peakLimit / max(framePeak, 1e-6) : 1
            if desiredGain < gain {
                gain = desiredGain
            } else {
                gain = gain * releaseCoeff + (1 - releaseCoeff)
            }

            for channelIndex in limited.indices where index < limited[channelIndex].count {
                limited[channelIndex][index] = limited[channelIndex][index] * gain
            }
        }

        return limited
    }

    private func integratedLoudness(_ signal: AudioSignal) -> Float {
        let weighted = kWeight(signal.monoMixdown(), sampleRate: signal.sampleRate)
        let windowSize = max(Int(signal.sampleRate * 0.4), 1)
        let hopSize = max(Int(signal.sampleRate * 0.1), 1)
        var blockLoudness: [Float] = []
        var start = 0
        while start < weighted.count {
            let end = min(weighted.count, start + windowSize)
            let block = Array(weighted[start..<end])
            let rms = sqrt(max(block.reduce(0) { $0 + $1 * $1 } / Float(max(block.count, 1)), 1e-9))
            let loudness = 20 * log10f(rms)
            blockLoudness.append(loudness)
            start += hopSize
        }

        let absoluteGated = blockLoudness.filter { $0 > -70 }
        guard !absoluteGated.isEmpty else { return -70 }
        let preliminary = energyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return energyAverage(relativeGated.isEmpty ? absoluteGated : relativeGated)
    }

    private func energyAverage(_ loudnessValues: [Float]) -> Float {
        let meanEnergy = loudnessValues.map { powf(10, $0 / 10) }.reduce(0, +) / Float(max(loudnessValues.count, 1))
        return 10 * log10f(max(meanEnergy, 1e-9))
    }

    private func kWeight(_ signal: [Float], sampleRate: Double) -> [Float] {
        let highPassed = SpectralDSP.highPass(signal, cutoff: 60, sampleRate: sampleRate)
        let shelfBase = SpectralDSP.highPass(signal, cutoff: 1_500, sampleRate: sampleRate)
        return zip(highPassed, shelfBase).map { $0 + $1 * 0.25 }
    }

    private func approximateTruePeak(channels: [[Float]]) -> Float {
        channels.map(oversampledPeak).max() ?? 0
    }

    private func oversampledPeak(_ channel: [Float]) -> Float {
        guard channel.count > 1 else { return channel.map { abs($0) }.max() ?? 0 }
        var peak: Float = 0
        for index in 0..<(channel.count - 1) {
            let a = channel[index]
            let b = channel[index + 1]
            for step in 0...3 {
                let t = Float(step) / 4
                peak = max(peak, abs(a * (1 - t) + b * t))
            }
        }
        return peak
    }
}
