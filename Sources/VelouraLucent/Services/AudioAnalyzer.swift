import Foundation

struct AudioSeparatedMeanSpectra: Equatable, Sendable {
    let harmonic: [Float]
    let percussive: [Float]
}

private struct AudioAnalysisSpectrogram: Sendable {
    let magnitudes: [Float]
    let fftSize: Int
    let hopSize: Int
    let frameCount: Int
    let binCount: Int

    func storageIndex(frameIndex: Int, binIndex: Int) -> Int {
        frameIndex * binCount + binIndex
    }

    func magnitude(frameIndex: Int, binIndex: Int) -> Float {
        magnitudes[storageIndex(frameIndex: frameIndex, binIndex: binIndex)]
    }

    func fillMagnitudes(frameIndex: Int, into frameMagnitudes: inout [Float]) {
        if frameMagnitudes.count != binCount {
            frameMagnitudes = Array(repeating: Float.zero, count: binCount)
        }

        let start = frameIndex * binCount
        frameMagnitudes[0..<binCount] = magnitudes[start..<(start + binCount)]
    }

    func fillMagnitudeHistory(binIndex: Int, into history: inout [Float]) {
        if history.count != frameCount {
            history = Array(repeating: Float.zero, count: frameCount)
        }

        for frameIndex in 0..<frameCount {
            history[frameIndex] = magnitude(frameIndex: frameIndex, binIndex: binIndex)
        }
    }
}

struct AudioAnalyzer {
    let mode: AudioAnalysisMode

    init(mode: AudioAnalysisMode = .cpu) {
        self.mode = mode
    }

    func analyze(signal: AudioSignal) -> AnalysisData {
        let mono = signal.monoMixdown()
        let spectrogram = makeAnalysisSpectrogram(mono)
        guard spectrogram.frameCount > 0 else {
            return AnalysisData(
                cutoffFrequency: 16_000,
                dominantHarmonics: [],
                harmonicConfidence: 0,
                hasShimmer: false,
                shimmerRatio: 0,
                brightnessRatio: 0,
                transientAmount: 0,
                noiseAmount: 0,
                rolloffDepth: 0,
                airBandEnergyRatio: 0,
                artifactBandRatio: 0,
                denoiseEffectMetrics: DenoiseEffectMetrics(shimmerFlicker: 0, hf12Magnitude: 0, hf16Magnitude: 0, hf18Magnitude: 0)
            )
        }

        let separatedSpectrum = separatedMeanSpectra(spectrogram: spectrogram)
        let harmonicSpectrum = SpectralDSP.medianFilter(separatedSpectrum.harmonic, windowSize: 7)
        let percussiveSpectrum = SpectralDSP.medianFilter(separatedSpectrum.percussive, windowSize: 5)
        let meanSpectrum = zip(harmonicSpectrum, percussiveSpectrum).map { harmonic, percussive in
            harmonic * 0.78 + percussive * 0.22
        }

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
        var harmonicSupport: Float = 0
        if harmonicEnd > harmonicStart + 1 {
            for index in (harmonicStart + 1)..<harmonicEnd {
                let value = harmonicSpectrum[index]
                let localFloor = max(0.015, (harmonicSpectrum[max(harmonicStart, index - 4)...min(harmonicEnd, index + 4)].reduce(0, +) / Float(min(harmonicEnd, index + 4) - max(harmonicStart, index - 4) + 1)) * 1.08)
                if value > harmonicSpectrum[index - 1], value >= harmonicSpectrum[index + 1], value > localFloor {
                    peaks.append(HarmonicPeak(frequency: Double(index) * frequencyStep, magnitude: value))
                    harmonicSupport += value
                }
            }
        }

        let shimmerStart = min(Int(10_000 / frequencyStep), meanSpectrum.count - 1)
        let shimmerEnd = min(Int(14_000 / frequencyStep), meanSpectrum.count - 1)
        let shimmerEnergy = meanSpectrum[shimmerStart...shimmerEnd].reduce(0, +)
        let bodyEnergy = meanSpectrum[0...min(200, meanSpectrum.count - 1)].reduce(0, +)
        let preRolloffEnergy = bandAverage(meanSpectrum, frequencyStep: frequencyStep, lower: 8_000, upper: 12_000)
        let postRolloffEnergy = bandAverage(meanSpectrum, frequencyStep: frequencyStep, lower: 16_000, upper: min(20_000, signal.sampleRate * 0.5))
        let upperBandStart = min(Int(16_000 / frequencyStep), meanSpectrum.count - 1)
        let upperBandEnergy = meanSpectrum[upperBandStart...(meanSpectrum.count - 1)].reduce(0, +)
        let artifactEnergy = bandEnergy(meanSpectrum, frequencyStep: frequencyStep, lower: 18_000, upper: signal.sampleRate * 0.5)
        let centroid = SpectralDSP.spectralCentroid(meanSpectrum, sampleRate: signal.sampleRate, fftSize: spectrogram.fftSize)
        let brightnessRatio = Float(centroid / max(signal.sampleRate * 0.5, 1))
        let transientAmount = estimateTransientAmount(mono)
        let shimmerRatio = shimmerEnergy / max(bodyEnergy + upperBandEnergy, 1e-6)
        let rolloffDepth = min(1.0, max(0, (20 * log10f(max(preRolloffEnergy, 1e-6) / max(postRolloffEnergy, 1e-6))) / 24))
        let airBandEnergyRatio = min(1.0, upperBandEnergy / max(bodyEnergy + upperBandEnergy, 1e-6))
        let artifactBandRatio = min(1.0, artifactEnergy / max(bodyEnergy + upperBandEnergy, 1e-6))
        let harmonicConfidence = min(1.2, harmonicSupport / max(harmonicSupport + percussiveSpectrum[harmonicStart...harmonicEnd].reduce(0, +), 1e-6))
        let noiseAmount = estimateNoiseAmount(
            percussiveSpectrum: percussiveSpectrum,
            meanSpectrum: meanSpectrum,
            frequencyStep: frequencyStep
        )

        return AnalysisData(
            cutoffFrequency: cutoff,
            dominantHarmonics: peaks.sorted { $0.magnitude > $1.magnitude }.prefix(8).map { $0 },
            harmonicConfidence: harmonicConfidence,
            hasShimmer: shimmerEnergy > bodyEnergy * 0.05 || steepestDrop < -4,
            shimmerRatio: shimmerRatio,
            brightnessRatio: brightnessRatio,
            transientAmount: transientAmount,
            noiseAmount: noiseAmount,
            rolloffDepth: rolloffDepth,
            airBandEnergyRatio: airBandEnergyRatio,
            artifactBandRatio: artifactBandRatio,
            denoiseEffectMetrics: denoiseEffectMetrics(from: spectrogram, sampleRate: signal.sampleRate)
        )
    }

    private func makeAnalysisSpectrogram(_ mono: [Float]) -> AudioAnalysisSpectrogram {
        let fftSize = SpectralDSP.fftSize
        let hopSize = SpectralDSP.hopSize
        let binCount = fftSize / 2 + 1
        let expectedFrameCount = analysisSTFTFrameCount(forSampleCount: mono.count, fftSize: fftSize, hopSize: hopSize)
        var magnitudes: [Float] = []
        magnitudes.reserveCapacity(expectedFrameCount * binCount)
        var frameCount = 0

        SpectralDSP.forEachSTFTFrame(mono, fftSize: fftSize, hopSize: hopSize) { frameIndex, _, real, imag in
            frameCount = frameIndex + 1
            for binIndex in 0..<binCount {
                magnitudes.append(hypotf(real[binIndex], imag[binIndex]))
            }
        }

        return AudioAnalysisSpectrogram(
            magnitudes: magnitudes,
            fftSize: fftSize,
            hopSize: hopSize,
            frameCount: frameCount,
            binCount: binCount
        )
    }

    private func analysisSTFTFrameCount(forSampleCount sampleCount: Int, fftSize: Int, hopSize: Int) -> Int {
        let sourceCount = sampleCount == 0 ? 1 : sampleCount
        let paddedCount = sourceCount > 1 ? sourceCount + fftSize : sourceCount
        let remainder = max(0, (paddedCount - fftSize) % hopSize)
        let trailingPadding = remainder == 0 ? 0 : hopSize - remainder
        let workingCount = paddedCount + trailingPadding
        return max(1, Int(ceil(Double(max(workingCount - fftSize, 0)) / Double(hopSize))) + 1)
    }

    private func denoiseEffectMetrics(from spectrogram: AudioAnalysisSpectrogram, sampleRate: Double) -> DenoiseEffectMetrics {
        guard spectrogram.frameCount > 0, spectrogram.binCount > 0 else {
            return DenoiseEffectMetrics(shimmerFlicker: 0, hf12Magnitude: 0, hf16Magnitude: 0, hf18Magnitude: 0)
        }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let shimmerStart = binIndex(for: 10_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let shimmerEnd = binIndex(for: 16_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let hf12Start = binIndex(for: 12_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let hf16Start = binIndex(for: 16_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let hf18Start = binIndex(for: 18_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)

        var hf12Sum: Float = 0
        var hf16Sum: Float = 0
        var hf18Sum: Float = 0
        var previousShimmerMean: Float?
        var shimmerDiffSum: Float = 0
        var shimmerFrameCount = 0

        for frameIndex in 0..<spectrogram.frameCount {
            var shimmerEnergy: Float = 0
            var shimmerCount = 0
            for binIndex in 0..<spectrogram.binCount {
                let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
                if binIndex >= hf12Start { hf12Sum += magnitude }
                if binIndex >= hf16Start { hf16Sum += magnitude }
                if binIndex >= hf18Start { hf18Sum += magnitude }
                if binIndex >= shimmerStart, binIndex <= shimmerEnd {
                    shimmerEnergy += magnitude
                    shimmerCount += 1
                }
            }

            let shimmerMean = shimmerEnergy / Float(max(shimmerCount, 1))
            if let previousShimmerMean {
                shimmerDiffSum += abs(shimmerMean - previousShimmerMean)
            }
            previousShimmerMean = shimmerMean
            shimmerFrameCount += 1
        }

        let frameCount = Float(max(spectrogram.frameCount, 1))
        return DenoiseEffectMetrics(
            shimmerFlicker: shimmerDiffSum / Float(max(shimmerFrameCount - 1, 1)),
            hf12Magnitude: hf12Sum / frameCount,
            hf16Magnitude: hf16Sum / frameCount,
            hf18Magnitude: hf18Sum / frameCount
        )
    }

    private func binIndex(for frequency: Double, frequencyStep: Double, binCount: Int) -> Int {
        min(max(Int(frequency / frequencyStep), 0), binCount - 1)
    }

    private func bandEnergy(_ spectrum: [Float], frequencyStep: Double, lower: Double, upper: Double) -> Float {
        guard !spectrum.isEmpty, frequencyStep > 0 else { return 0 }
        let start = min(max(Int(lower / frequencyStep), 0), spectrum.count - 1)
        let end = min(max(Int(upper / frequencyStep), start), spectrum.count - 1)
        guard end >= start else { return 0 }
        return spectrum[start...end].reduce(0, +)
    }

    private func bandAverage(_ spectrum: [Float], frequencyStep: Double, lower: Double, upper: Double) -> Float {
        guard !spectrum.isEmpty, frequencyStep > 0 else { return 0 }
        let start = min(max(Int(lower / frequencyStep), 0), spectrum.count - 1)
        let end = min(max(Int(upper / frequencyStep), start), spectrum.count - 1)
        guard end >= start else { return 0 }
        return spectrum[start...end].reduce(0, +) / Float(end - start + 1)
    }

    private func separatedMeanSpectra(spectrogram: AudioAnalysisSpectrogram) -> AudioSeparatedMeanSpectra {
        if mode == .experimentalMetal,
           let separatedSpectrum = MetalAudioAnalysisProcessor().separatedMeanSpectra(
            magnitudes: spectrogram.magnitudes,
            frameCount: spectrogram.frameCount,
            binCount: spectrogram.binCount
           ) {
            return separatedSpectrum
        }
        return cpuSeparatedMeanSpectra(spectrogram: spectrogram)
    }

    private func cpuSeparatedMeanSpectra(spectrogram: AudioAnalysisSpectrogram) -> AudioSeparatedMeanSpectra {
        guard spectrogram.frameCount > 0, spectrogram.binCount > 0 else {
            return AudioSeparatedMeanSpectra(harmonic: [], percussive: [])
        }

        let frameCount = spectrogram.frameCount
        let binCount = spectrogram.binCount
        var temporalMedian = Array(repeating: Float.zero, count: frameCount * binCount)
        var history = Array(repeating: Float.zero, count: frameCount)

        for binIndex in 0..<binCount {
            spectrogram.fillMagnitudeHistory(binIndex: binIndex, into: &history)
            let filtered = SpectralDSP.medianFilter(history, windowSize: 17)
            for frameIndex in 0..<frameCount {
                temporalMedian[frameIndex * binCount + binIndex] = filtered[frameIndex]
            }
        }

        var harmonicSpectrum = Array(repeating: Float.zero, count: binCount)
        var percussiveSpectrum = Array(repeating: Float.zero, count: binCount)
        var frameMagnitudes = Array(repeating: Float.zero, count: binCount)

        for frameIndex in 0..<frameCount {
            spectrogram.fillMagnitudes(frameIndex: frameIndex, into: &frameMagnitudes)
            let spectralMedian = SpectralDSP.medianFilter(frameMagnitudes, windowSize: 9)
            for binIndex in 0..<binCount {
                let harmonicWeight = temporalMedian[frameIndex * binCount + binIndex]
                let percussiveWeight = spectralMedian[binIndex]
                let total = max(harmonicWeight + percussiveWeight, 1e-6)
                let magnitude = frameMagnitudes[binIndex]
                harmonicSpectrum[binIndex] += magnitude * harmonicWeight / total
                percussiveSpectrum[binIndex] += magnitude * percussiveWeight / total
            }
        }

        let scale = 1 / Float(max(frameCount, 1))
        for binIndex in 0..<binCount {
            harmonicSpectrum[binIndex] *= scale
            percussiveSpectrum[binIndex] *= scale
        }
        return AudioSeparatedMeanSpectra(harmonic: harmonicSpectrum, percussive: percussiveSpectrum)
    }

    private func estimateTransientAmount(_ signal: [Float]) -> Float {
        guard signal.count > 2 else { return 0 }
        var diffSum: Float = 0
        var levelSum: Float = abs(signal[0])
        for index in 1..<signal.count {
            diffSum += abs(signal[index] - signal[index - 1])
            levelSum += abs(signal[index])
        }
        let averageDiff = diffSum / Float(signal.count - 1)
        let averageLevel = max(levelSum / Float(signal.count), 1e-6)
        return min(1.5, averageDiff / averageLevel)
    }

    private func estimateNoiseAmount(percussiveSpectrum: [Float], meanSpectrum: [Float], frequencyStep: Double) -> Float {
        guard !percussiveSpectrum.isEmpty, !meanSpectrum.isEmpty else { return 0 }
        let granularStart = min(max(Int(12_000 / frequencyStep), 0), percussiveSpectrum.count - 1)
        let granularEnd = min(max(Int(20_000 / frequencyStep), granularStart), percussiveSpectrum.count - 1)
        let bodyEnd = min(max(Int(4_000 / frequencyStep), 0), meanSpectrum.count - 1)
        let granularEnergy = percussiveSpectrum[granularStart...granularEnd].reduce(0, +)
        let bodyEnergy = meanSpectrum[0...bodyEnd].reduce(0, +)
        return min(1.0, granularEnergy / max(granularEnergy + bodyEnergy * 0.65, 1e-6))
    }
}
