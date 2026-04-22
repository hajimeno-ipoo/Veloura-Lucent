import Foundation

protocol AudioProcessingLogger {
    func log(_ message: String)
}

struct AudioProcessingStageBenchmark: Equatable, Sendable {
    let name: String
    let durationSeconds: Double
}

struct NativeAudioProcessingBenchmark: Equatable, Sendable {
    let stages: [AudioProcessingStageBenchmark]

    var totalDurationSeconds: Double {
        stages.reduce(0) { $0 + $1.durationSeconds }
    }

    func duration(for stageName: String) -> Double? {
        stages.first { $0.name == stageName }?.durationSeconds
    }
}

enum AudioAnalysisMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case auto
    case cpu
    case experimentalMetal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "自動"
        case .cpu:
            return "安定CPU"
        case .experimentalMetal:
            return "実験Metal"
        }
    }

    var summary: String {
        switch self {
        case .auto:
            return MetalAudioAnalysisProcessor().isAvailable
                ? "このMacでは高速なMetal解析を使います"
                : "Metal解析を使えないためCPU解析を使います"
        case .cpu:
            return "安定した解析を使います"
        case .experimentalMetal:
            return MetalAudioAnalysisProcessor().isAvailable
                ? "解析の一部をMetalで高速化します"
                : "このMacではMetal解析を使えないためCPUへ戻ります"
        }
    }

    var resolvedMode: AudioAnalysisMode {
        switch self {
        case .auto:
            return MetalAudioAnalysisProcessor().isAvailable ? .experimentalMetal : .cpu
        case .experimentalMetal:
            return MetalAudioAnalysisProcessor().isAvailable ? .experimentalMetal : .cpu
        case .cpu:
            return .cpu
        }
    }

    var resolvedSummary: String {
        let resolved = resolvedMode
        if self == resolved {
            return "使用中: \(resolved.title)"
        }
        return "使用中: \(resolved.title)（\(title)から自動切替）"
    }

    var logDescription: String {
        let resolved = resolvedMode
        if self == resolved {
            return "解析モード: \(resolved.title)"
        }
        return "解析モード: \(title) -> \(resolved.title)"
    }
}

struct AudioSeparatedMeanSpectra: Equatable, Sendable {
    let harmonic: [Float]
    let percussive: [Float]
}

struct NativeAudioProcessor {
    func process(
        inputFile: URL,
        outputFile: URL,
        denoiseStrength: DenoiseStrength = .balanced,
        analysisMode: AudioAnalysisMode = .auto,
        logger: AudioProcessingLogger? = nil
    ) throws {
        _ = try run(
            inputFile: inputFile,
            outputFile: outputFile,
            denoiseStrength: denoiseStrength,
            analysisMode: analysisMode,
            logger: logger,
            collectsBenchmark: false
        )
    }

    func benchmark(
        inputFile: URL,
        outputFile: URL,
        denoiseStrength: DenoiseStrength = .balanced,
        analysisMode: AudioAnalysisMode = .auto,
        logger: AudioProcessingLogger? = nil
    ) throws -> NativeAudioProcessingBenchmark {
        try run(
            inputFile: inputFile,
            outputFile: outputFile,
            denoiseStrength: denoiseStrength,
            analysisMode: analysisMode,
            logger: logger,
            collectsBenchmark: true
        )
    }

    private func run(
        inputFile: URL,
        outputFile: URL,
        denoiseStrength: DenoiseStrength,
        analysisMode: AudioAnalysisMode,
        logger: AudioProcessingLogger?,
        collectsBenchmark: Bool
    ) throws -> NativeAudioProcessingBenchmark {
        let benchmarkRecorder = collectsBenchmark ? AudioProcessingBenchmarkRecorder() : nil

        logger?.log("入力音声を読み込みます")
        let signal = try measure("loadAudio", recorder: benchmarkRecorder) {
            try AudioFileService.loadAudio(from: inputFile)
        }

        let resolvedAnalysisMode = analysisMode.resolvedMode
        logger?.log("音声を解析します")
        logger?.log(analysisMode.logDescription)
        let analysis = measure("analyze", recorder: benchmarkRecorder) {
            AudioAnalyzer(mode: resolvedAnalysisMode).analyze(signal: signal)
        }
        let neuralPrediction = measure("neuralPrediction", recorder: benchmarkRecorder) {
            NeuralFoldoverEstimator().predict(
                features: NeuralFoldoverFeatures(
                    harmonicConfidence: analysis.harmonicConfidence,
                    shimmerRatio: analysis.shimmerRatio,
                    brightnessRatio: analysis.brightnessRatio,
                    transientAmount: analysis.transientAmount,
                    cutoffFrequency: analysis.cutoffFrequency,
                    noiseAmount: analysis.noiseAmount
                )
            )
        }

        logger?.log("ノイズを除去します")
        let denoised = measure("denoise", recorder: benchmarkRecorder) {
            SpectralGateDenoiser(strength: denoiseStrength).process(signal: signal)
        }

        logger?.log("高域を補完します")
        let upscaled = measure("harmonicUpscale", recorder: benchmarkRecorder) {
            HarmonicUpscaler().process(signal: denoised, analysis: analysis, prediction: neuralPrediction)
        }

        logger?.log("ダイナミクスを整えます")
        let shaped = measure("multibandDynamics", recorder: benchmarkRecorder) {
            MultibandDynamicsProcessor().process(signal: upscaled)
        }

        logger?.log("最終音量を整えます")
        let finalized = measure("loudnessFinalize", recorder: benchmarkRecorder) {
            LoudnessProcessor().process(signal: shaped)
        }

        logger?.log("処理済みファイルを書き出します")
        try measure("saveAudio", recorder: benchmarkRecorder) {
            try AudioFileService.saveAudio(finalized, to: outputFile)
        }
        logger?.log("処理が完了しました")

        return NativeAudioProcessingBenchmark(stages: benchmarkRecorder?.stages ?? [])
    }

    private func measure<T>(
        _ stageName: String,
        recorder: AudioProcessingBenchmarkRecorder?,
        work: () throws -> T
    ) rethrows -> T {
        guard let recorder else {
            return try work()
        }
        return try recorder.measure(stageName, work: work)
    }
}

private final class AudioProcessingBenchmarkRecorder {
    private(set) var stages: [AudioProcessingStageBenchmark] = []

    func measure<T>(_ stageName: String, work: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        defer {
            let end = DispatchTime.now().uptimeNanoseconds
            stages.append(
                AudioProcessingStageBenchmark(
                    name: stageName,
                    durationSeconds: Double(end - start) / 1_000_000_000
                )
            )
        }
        return try work()
    }
}

func mapChannelsConcurrently(_ channels: [[Float]], transform: @escaping @Sendable ([Float]) -> [Float]) -> [[Float]] {
    guard channels.count > 1 else {
        return channels.map(transform)
    }

    let results = ConcurrentChannelResults(count: channels.count)
    DispatchQueue.concurrentPerform(iterations: channels.count) { index in
        let processed = transform(channels[index])
        results.set(processed, at: index)
    }
    return results.values()
}

private final class ConcurrentChannelResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[Float]?]

    init(count: Int) {
        storage = Array(repeating: nil, count: count)
    }

    func set(_ value: [Float], at index: Int) {
        lock.lock()
        storage[index] = value
        lock.unlock()
    }

    func values() -> [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        return storage.map { $0 ?? [] }
    }
}

struct AudioAnalyzer {
    let mode: AudioAnalysisMode

    init(mode: AudioAnalysisMode = .cpu) {
        self.mode = mode
    }

    func analyze(signal: AudioSignal) -> AnalysisData {
        let mono = signal.monoMixdown()
        let spectrogram = SpectralDSP.stft(mono)
        guard spectrogram.frameCount > 0 else {
            return AnalysisData(cutoffFrequency: 16_000, dominantHarmonics: [], harmonicConfidence: 0, hasShimmer: false, shimmerRatio: 0, brightnessRatio: 0, transientAmount: 0, noiseAmount: 0)
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
        let upperBandStart = min(Int(16_000 / frequencyStep), meanSpectrum.count - 1)
        let upperBandEnergy = meanSpectrum[upperBandStart...(meanSpectrum.count - 1)].reduce(0, +)
        let centroid = SpectralDSP.spectralCentroid(meanSpectrum, sampleRate: signal.sampleRate, fftSize: spectrogram.fftSize)
        let brightnessRatio = Float(centroid / max(signal.sampleRate * 0.5, 1))
        let transientAmount = estimateTransientAmount(mono)
        let shimmerRatio = shimmerEnergy / max(bodyEnergy + upperBandEnergy, 1e-6)
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
            noiseAmount: noiseAmount
        )
    }

    private func separatedMeanSpectra(spectrogram: Spectrogram) -> AudioSeparatedMeanSpectra {
        if mode == .experimentalMetal,
           let separatedSpectrum = MetalAudioAnalysisProcessor().separatedMeanSpectra(spectrogram: spectrogram) {
            return separatedSpectrum
        }
        return cpuSeparatedMeanSpectra(spectrogram: spectrogram)
    }

    private func cpuSeparatedMeanSpectra(spectrogram: Spectrogram) -> AudioSeparatedMeanSpectra {
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

private struct SpectralGateDenoiser: Sendable {
    let strength: DenoiseStrength

    private var tuning: DenoiseTuning {
        switch strength {
        case .gentle:
            return DenoiseTuning(passes: 1, thresholdMultiplier: 1.28, lowBandFloor: 0.22, highBandFloor: 0.33, quietPercentile: 16, transientProtection: 0.28, granularReduction: 0.18)
        case .balanced:
            return DenoiseTuning(passes: 2, thresholdMultiplier: 1.46, lowBandFloor: 0.16, highBandFloor: 0.28, quietPercentile: 20, transientProtection: 0.22, granularReduction: 0.26)
        case .strong:
            return DenoiseTuning(passes: 3, thresholdMultiplier: 1.68, lowBandFloor: 0.11, highBandFloor: 0.22, quietPercentile: 26, transientProtection: 0.16, granularReduction: 0.34)
        }
    }

    func process(signal: AudioSignal) -> AudioSignal {
        let channels = mapChannelsConcurrently(signal.channels) { channel in
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
        let coefficients = DenoiseMaskCoefficients(
            binCount: binCount,
            lowBandFloor: tuning.lowBandFloor,
            highBandFloor: tuning.highBandFloor
        )
        var noiseProfile = Array(repeating: Float.zero, count: binCount)
        var granularProfile = Array(repeating: Float.zero, count: binCount)
        let frameEnergy = spectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(frameEnergy, tuning.quietPercentile)
        let quietFrameIndices = frameEnergy.enumerated().compactMap { index, value in
            value <= quietThreshold ? index : nil
        }
        let sourceFrameIndices = quietFrameIndices.isEmpty ? Array(0..<spectrogram.frameCount) : quietFrameIndices
        var noiseSums = Array(repeating: Float.zero, count: binCount)
        var noiseMinimums = Array(repeating: Float.greatestFiniteMagnitude, count: binCount)
        var granularSums = Array(repeating: Float.zero, count: binCount)
        let smoothedFrameEnergy = SpectralDSP.movingAverage(frameEnergy, windowSize: 7)

        for frameIndex in sourceFrameIndices {
            let frameStart = frameIndex * binCount
            let previousFrameStart = frameStart - binCount
            for binIndex in 0..<binCount {
                let index = frameStart + binIndex
                let magnitude = hypotf(spectrogram.real[index], spectrogram.imag[index])
                noiseSums[binIndex] += magnitude
                noiseMinimums[binIndex] = min(noiseMinimums[binIndex], magnitude)
                if frameIndex > 0 {
                    let previousIndex = previousFrameStart + binIndex
                    let previous = hypotf(spectrogram.real[previousIndex], spectrogram.imag[previousIndex])
                    granularSums[binIndex] += abs(magnitude - previous)
                }
            }
        }

        let sourceCount = Float(max(sourceFrameIndices.count, 1))
        for binIndex in 0..<binCount {
            let averageNoise = noiseSums[binIndex] / sourceCount
            let minimumNoise = noiseMinimums[binIndex].isFinite ? noiseMinimums[binIndex] : averageNoise
            let baseNoise = averageNoise * 0.8 + minimumNoise * 0.2
            noiseProfile[binIndex] = baseNoise * coefficients.highBandBias[binIndex]
            let granularAverage = granularSums[binIndex] / sourceCount
            granularProfile[binIndex] = granularAverage * coefficients.granularProfileScale[binIndex]
        }

        for frameIndex in 0..<spectrogram.frameCount {
            let transientRatio = frameEnergy[frameIndex] / max(smoothedFrameEnergy[frameIndex], 1e-6)
            let transientLift = max(0, min(0.35, (transientRatio - 1) * tuning.transientProtection))
            let frameStart = frameIndex * binCount
            let previousFrameStart = frameStart - binCount
            for binIndex in 0..<binCount {
                let index = frameStart + binIndex
                let magnitude = hypotf(spectrogram.real[index], spectrogram.imag[index])
                let threshold = noiseProfile[binIndex] * tuning.thresholdMultiplier * coefficients.thresholdScale[binIndex]
                let floor = coefficients.floor[binIndex]
                let rawMask = max(floor, min(1.0, (magnitude - threshold) / max(magnitude, 1e-6)))
                let granularActivity: Float
                if frameIndex > 0 {
                    let previousIndex = previousFrameStart + binIndex
                    let previous = hypotf(spectrogram.real[previousIndex], spectrogram.imag[previousIndex])
                    granularActivity = abs(magnitude - previous)
                } else {
                    granularActivity = 0
                }
                let granularThreshold = granularProfile[binIndex] * coefficients.granularThresholdScale[binIndex]
                let granularExcess = max(0, granularActivity - granularThreshold)
                let granularMask = max(
                    floor,
                    1 - min(0.72, granularExcess / max(magnitude + granularThreshold, 1e-6)) * tuning.granularReduction
                )
                let mask = min(1.0, max(rawMask, granularMask) + transientLift)
                spectrogram.real[index] *= mask
                spectrogram.imag[index] *= mask
            }
        }

        return SpectralDSP.istft(spectrogram)
    }
}

struct DenoiseMaskCoefficients: Sendable {
    let highBandBias: [Float]
    let granularProfileScale: [Float]
    let thresholdScale: [Float]
    let floor: [Float]
    let granularThresholdScale: [Float]

    init(binCount: Int, lowBandFloor: Float, highBandFloor: Float) {
        let denominator = Float(max(binCount - 1, 1))
        var highBandBias: [Float] = []
        var granularProfileScale: [Float] = []
        var thresholdScale: [Float] = []
        var floor: [Float] = []
        var granularThresholdScale: [Float] = []
        highBandBias.reserveCapacity(binCount)
        granularProfileScale.reserveCapacity(binCount)
        thresholdScale.reserveCapacity(binCount)
        floor.reserveCapacity(binCount)
        granularThresholdScale.reserveCapacity(binCount)

        for binIndex in 0..<binCount {
            let normalizedBand = Float(binIndex) / denominator
            highBandBias.append(0.94 + powf(normalizedBand, 1.25) * 0.18)
            granularProfileScale.append(max(0, (normalizedBand - 0.42) / 0.58))
            thresholdScale.append(0.92 + powf(normalizedBand, 1.1) * 0.24)
            floor.append(lowBandFloor + (highBandFloor - lowBandFloor) * powf(normalizedBand, 1.25))
            granularThresholdScale.append(1.1 + normalizedBand * 0.6)
        }

        self.highBandBias = highBandBias
        self.granularProfileScale = granularProfileScale
        self.thresholdScale = thresholdScale
        self.floor = floor
        self.granularThresholdScale = granularThresholdScale
    }
}

private struct DenoiseTuning: Sendable {
    let passes: Int
    let thresholdMultiplier: Float
    let lowBandFloor: Float
    let highBandFloor: Float
    let quietPercentile: Float
    let transientProtection: Float
    let granularReduction: Float
}

private struct MultibandDynamicsProcessor: Sendable {
    let bands: [(ClosedRange<Double>, Float, Float)] = [
        (5_000...8_000, 3.0, 80),
        (10_000...14_000, 3.2, 68),
        (18_000...24_000, 2.8, 82)
    ]

    func process(signal: AudioSignal) -> AudioSignal {
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processChannel(_ channel: [Float], sampleRate: Double) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        var bandEnergy = Array(repeating: Float.zero, count: spectrogram.frameCount)
        var rawMask = Array(repeating: Float.zero, count: spectrogram.frameCount)
        var smoothedMask = Array(repeating: Float.zero, count: spectrogram.frameCount)

        for (band, reductionDB, percentile) in bands {
            let start = min(Int(band.lowerBound / frequencyStep), spectrogram.binCount - 1)
            let end = min(Int(band.upperBound / frequencyStep), spectrogram.binCount - 1)
            guard end > start else { continue }

            fillBandEnergy(spectrogram: spectrogram, startBin: start, endBin: end, into: &bandEnergy)
            let threshold = SpectralDSP.percentile(bandEnergy, percentile)
            let reductionLinear = powf(10, -reductionDB / 20)
            fillBandMask(
                bandEnergy: bandEnergy,
                threshold: threshold,
                reductionLinear: reductionLinear,
                into: &rawMask
            )
            fillMovingAverage(rawMask, windowSize: 5, into: &smoothedMask)

            for frameIndex in 0..<spectrogram.frameCount {
                let gain = max(reductionLinear, min(1.0, smoothedMask[frameIndex]))
                for binIndex in start...end {
                    spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
                }
            }
        }

        return SpectralDSP.istft(spectrogram)
    }

    private func fillBandEnergy(
        spectrogram: Spectrogram,
        startBin: Int,
        endBin: Int,
        into bandEnergy: inout [Float]
    ) {
        if bandEnergy.count != spectrogram.frameCount {
            bandEnergy = Array(repeating: Float.zero, count: spectrogram.frameCount)
        }

        let binCount = Float(endBin - startBin + 1)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            for binIndex in startBin...endBin {
                sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            bandEnergy[frameIndex] = sum / binCount
        }
    }

    private func fillBandMask(
        bandEnergy: [Float],
        threshold: Float,
        reductionLinear: Float,
        into mask: inout [Float]
    ) {
        if mask.count != bandEnergy.count {
            mask = Array(repeating: Float.zero, count: bandEnergy.count)
        }

        for index in bandEnergy.indices {
            let energy = bandEnergy[index]
            mask[index] = energy > threshold ? reductionLinear + (1 - reductionLinear) * (threshold / max(energy, 1e-6)) : 1
        }
    }

    private func fillMovingAverage(_ values: [Float], windowSize: Int, into smoothed: inout [Float]) {
        guard windowSize > 1, !values.isEmpty else {
            smoothed = values
            return
        }

        if smoothed.count != values.count {
            smoothed = Array(repeating: Float.zero, count: values.count)
        }

        let radius = windowSize / 2
        for index in values.indices {
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            var sum: Float = 0
            for valueIndex in lower...upper {
                sum += values[valueIndex]
            }
            smoothed[index] = sum / Float(upper - lower + 1)
        }
    }
}

private struct HarmonicUpscaler: Sendable {
    func process(signal: AudioSignal, analysis: AnalysisData, prediction: NeuralFoldoverPrediction) -> AudioSignal {
        let cutoff = max(analysis.cutoffFrequency - 1_000, 12_000)
        let harmonicWeight = min(1.25, 0.55 + Float(analysis.dominantHarmonics.count) * 0.08 + analysis.harmonicConfidence * 0.26)
        let shimmerControl = analysis.hasShimmer ? max(0.65, 1 - analysis.shimmerRatio * 1.4) : 1.0
        let deficiency = Float(max(0, 16_000 - analysis.cutoffFrequency) / 4_000)
        let brightnessBoost = max(0.9, min(1.2, 1.02 + (0.55 - analysis.brightnessRatio) * 0.35))
        let baseGain = max(0.05, min(0.22, (0.08 + deficiency * 0.08) * harmonicWeight * shimmerControl))
        let airGain = max(
            0.06,
            min(0.34, (0.10 + deficiency * 0.18) * brightnessBoost - analysis.shimmerRatio * 0.03 + prediction.airGainBias)
        ) * (1 - prediction.harshnessGuard * 0.55)
        let transientBoost = max(
            0.06,
            min(0.24, 0.12 + analysis.transientAmount * 0.06 + prediction.transientBoostBias)
        ) * (1 - prediction.harshnessGuard * 0.35)
        let foldoverMix = max(
            0.04,
            min(0.32, 0.08 + deficiency * 0.16 + analysis.harmonicConfidence * 0.08 - analysis.shimmerRatio * 0.04 + prediction.foldoverMix - 0.12)
        ) * (1 - prediction.harshnessGuard * 0.62)

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
        let spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return Array(repeating: 0, count: channel.count) }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let sourceStart = max(1, min(Int(max(cutoff * 0.5, 5_500) / frequencyStep), spectrogram.binCount - 1))
        let sourceEnd = max(sourceStart, min(Int(min(cutoff * 0.95, 12_000) / frequencyStep), spectrogram.binCount - 1))
        let targetStart = max(sourceStart + 1, min(Int(16_000 / frequencyStep), spectrogram.binCount - 1))
        guard sourceEnd > sourceStart, targetStart < spectrogram.binCount else {
            return Array(repeating: 0, count: channel.count)
        }

        var activeBins: [Int] = []
        var seenBins = Set<Int>()
        for sourceBin in sourceStart...sourceEnd {
            let targetBin = min(spectrogram.binCount - 1, sourceBin * 2)
            guard targetBin >= targetStart, seenBins.insert(targetBin).inserted else { continue }
            activeBins.append(targetBin)
        }

        return SpectralDSP.istftSparseHalfSpectrum(
            frameCount: spectrogram.frameCount,
            fftSize: spectrogram.fftSize,
            hopSize: spectrogram.hopSize,
            originalLength: spectrogram.originalLength,
            leadingPadding: spectrogram.leadingPadding,
            trailingPadding: spectrogram.trailingPadding,
            activeBins: activeBins
        ) { frameIndex, realFrame, imagFrame in
            for sourceBin in sourceStart...sourceEnd {
                let targetBin = min(spectrogram.binCount - 1, sourceBin * 2)
                guard targetBin >= targetStart else { continue }
                let normalizedPosition = Float(targetBin - targetStart) / Float(max(spectrogram.binCount - targetStart - 1, 1))
                let lift = mix * (1 - normalizedPosition * 0.45)
                let sourceIndex = spectrogram.storageIndex(frameIndex: frameIndex, binIndex: sourceBin)
                realFrame[targetBin] += spectrogram.real[sourceIndex] * lift
                imagFrame[targetBin] += spectrogram.imag[sourceIndex] * lift
            }
        }
    }
}

private struct LoudnessProcessor {
    let peakLimitDB: Float = -1
    let limiterReleaseMs: Float = 120

    func process(signal: AudioSignal) -> AudioSignal {
        let peakLimit = powf(10, peakLimitDB / 20)
        var channels = applyLinkedLimiter(signal.channels, peakLimit: peakLimit, sampleRate: signal.sampleRate)

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
