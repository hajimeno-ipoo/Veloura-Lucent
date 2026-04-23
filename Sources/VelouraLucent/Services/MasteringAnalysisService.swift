import Accelerate
import Foundation

struct MasteringSpectralSummary: Sendable, Equatable {
    let lowBandLevelDB: Double
    let midBandLevelDB: Double
    let highBandLevelDB: Double
    let harshnessScore: Float
}

enum MasteringAnalysisService {
    struct Benchmark: Sendable {
        let analysis: MasteringAnalysis
        let stages: [AudioProcessingStageBenchmark]

        var totalDurationSeconds: Double {
            stages.reduce(0) { $0 + $1.durationSeconds }
        }

        func duration(for stageName: String) -> Double? {
            stages.first { $0.name == stageName }?.durationSeconds
        }
    }

    static func analyze(fileURL: URL) throws -> MasteringAnalysis {
        let signal = try AudioFileService.loadAudio(from: fileURL)
        return analyze(signal: signal)
    }

    static func analyze(signal: AudioSignal) -> MasteringAnalysis {
        analyzeWithBenchmark(signal: signal).analysis
    }

    static func analyzeWithBenchmark(fileURL: URL) throws -> Benchmark {
        let signal = try AudioFileService.loadAudio(from: fileURL)
        return analyzeWithBenchmark(signal: signal)
    }

    static func analyzeWithBenchmark(signal: AudioSignal) -> Benchmark {
        var recorder = AnalysisBenchmarkRecorder()
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            let analysis = MasteringAnalysis(
                integratedLoudness: -70,
                truePeakDBFS: -120,
                lowBandLevelDB: -120,
                midBandLevelDB: -120,
                highBandLevelDB: -120,
                harshnessScore: 0,
                stereoWidth: 0
            )
            return Benchmark(analysis: analysis, stages: [])
        }

        let spectrogram = recorder.measure("stft") {
            SpectralDSP.stft(mono)
        }
        let loudness = recorder.measure("loudness") {
            integratedLoudness(mono: mono, sampleRate: signal.sampleRate)
        }
        let peak = recorder.measure("truePeak") {
            approximateTruePeak(signal.channels)
        }
        let spectralSummaryResult = recorder.measure("spectralSummary") {
            spectralSummary(for: spectrogram, sampleRate: signal.sampleRate)
        }
        let width = recorder.measure("stereoWidth") {
            stereoWidth(for: signal)
        }

        let analysis = MasteringAnalysis(
            integratedLoudness: loudness,
            truePeakDBFS: 20 * log10(max(Double(peak), 1e-12)),
            lowBandLevelDB: spectralSummaryResult.lowBandLevelDB,
            midBandLevelDB: spectralSummaryResult.midBandLevelDB,
            highBandLevelDB: spectralSummaryResult.highBandLevelDB,
            harshnessScore: spectralSummaryResult.harshnessScore,
            stereoWidth: width
        )
        return Benchmark(analysis: analysis, stages: recorder.stages)
    }

    static func integratedLoudness(signal: AudioSignal) -> Float {
        integratedLoudness(mono: signal.monoMixdown(), sampleRate: signal.sampleRate)
    }

    private static func integratedLoudness(mono: [Float], sampleRate: Double) -> Float {
        let energyPrefix = kWeightedEnergyPrefix(mono, sampleRate: sampleRate)
        let sampleCount = max(energyPrefix.count - 1, 0)
        guard sampleCount > 0 else { return -70 }

        let windowSize = max(Int(sampleRate * 0.4), 1)
        let hopSize = max(Int(sampleRate * 0.1), 1)
        var blockLoudness: [Float] = []
        var start = 0

        while start < sampleCount {
            let end = min(sampleCount, start + windowSize)
            let rms = sqrt(max(meanSquare(in: energyPrefix, start: start, end: end), 1e-9))
            blockLoudness.append(20 * log10f(rms))
            start += hopSize
        }

        let absolute = loudnessEnergySum(blockLoudness, gate: -70)
        guard absolute.count > 0 else { return -70 }
        let preliminary = energyAverage(energySum: absolute.energy, count: absolute.count)
        let relativeGate = preliminary - 10
        let relative = relativeLoudnessEnergySum(blockLoudness, gate: relativeGate)
        return relative.count > 0
            ? energyAverage(energySum: relative.energy, count: relative.count)
            : energyAverage(energySum: absolute.energy, count: absolute.count)
    }

    static func approximateTruePeak(_ channels: [[Float]]) -> Float {
        var peak: Float = 0
        for channel in channels {
            peak = max(peak, oversampledPeak(channel))
        }
        return peak
    }

    private struct BinRange {
        let lower: Int
        let upperInclusive: Int

        func contains(_ binIndex: Int) -> Bool {
            binIndex >= lower && binIndex <= upperInclusive
        }
    }

    private static func spectralSummary(for spectrogram: Spectrogram, sampleRate: Double) -> MasteringSpectralSummary {
        guard spectrogram.frameCount > 0 else {
            return MasteringSpectralSummary(lowBandLevelDB: -120, midBandLevelDB: -120, highBandLevelDB: -120, harshnessScore: 0)
        }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let lowRange = binRange(20...180, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let midRange = binRange(180...5_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let highRange = binRange(5_000...20_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let harshUpperMidRange = binRange(3_000...8_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let harshAirRange = binRange(12_000...(sampleRate * 0.5), frequencyStep: frequencyStep, binCount: spectrogram.binCount)

        var lowEnergy: Float = 0
        var midEnergy: Float = 0
        var highEnergy: Float = 0
        var harshUpperMid: Float = 0
        var harshAir: Float = 0
        var lowCount = 0
        var midCount = 0
        var highCount = 0

        let maxBin = max(
            lowRange.upperInclusive,
            midRange.upperInclusive,
            highRange.upperInclusive,
            harshUpperMidRange.upperInclusive,
            harshAirRange.upperInclusive
        )
        for frameIndex in 0..<spectrogram.frameCount {
            let frameStart = frameIndex * spectrogram.binCount
            var frameHarshUpperMid: Float = 0
            var frameHarshAir: Float = 0

            for binIndex in 0...maxBin {
                let storageIndex = frameStart + binIndex
                let magnitude = hypotf(spectrogram.real[storageIndex], spectrogram.imag[storageIndex])
                let energy = magnitude * magnitude

                if lowRange.contains(binIndex) {
                    lowEnergy += energy
                    lowCount += 1
                }
                if midRange.contains(binIndex) {
                    midEnergy += energy
                    midCount += 1
                }
                if highRange.contains(binIndex) {
                    highEnergy += energy
                    highCount += 1
                }
                if harshUpperMidRange.contains(binIndex) {
                    frameHarshUpperMid += magnitude
                }
                if harshAirRange.contains(binIndex) {
                    frameHarshAir += magnitude
                }
            }

            harshUpperMid += frameHarshUpperMid
            harshAir += frameHarshAir
        }

        return MasteringSpectralSummary(
            lowBandLevelDB: bandLevelDB(energy: lowEnergy, count: lowCount),
            midBandLevelDB: bandLevelDB(energy: midEnergy, count: midCount),
            highBandLevelDB: bandLevelDB(energy: highEnergy, count: highCount),
            harshnessScore: min(1.0, harshUpperMid / max(harshUpperMid + harshAir, 1e-6))
        )
    }

    static func stereoWidth(for signal: AudioSignal) -> Float {
        guard signal.channels.count >= 2 else { return 0 }
        let left = signal.channels[0]
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return 0 }
        var midEnergy: Float = 0
        var sideEnergy: Float = 0
        for index in 0..<count {
            let mid = (left[index] + right[index]) * 0.5
            let side = (left[index] - right[index]) * 0.5
            midEnergy += mid * mid
            sideEnergy += side * side
        }
        return min(2.0, sqrt(sideEnergy / max(midEnergy, 1e-9)))
    }

    private static func energyAverage(energySum: Float, count: Int) -> Float {
        let meanEnergy = energySum / Float(max(count, 1))
        return 10 * log10f(max(meanEnergy, 1e-9))
    }

    private static func loudnessEnergySum(_ loudnessValues: [Float], gate: Float) -> (energy: Float, count: Int) {
        var energy: Float = 0
        var count = 0
        for loudness in loudnessValues where loudness > gate {
            energy += powf(10, loudness / 10)
            count += 1
        }
        return (energy, count)
    }

    private static func relativeLoudnessEnergySum(_ loudnessValues: [Float], gate: Float) -> (energy: Float, count: Int) {
        var energy: Float = 0
        var count = 0
        for loudness in loudnessValues where loudness > -70 && loudness >= gate {
            energy += powf(10, loudness / 10)
            count += 1
        }
        return (energy, count)
    }

    private static func kWeightedEnergyPrefix(_ signal: [Float], sampleRate: Double) -> [Float] {
        guard !signal.isEmpty else { return [0] }
        let rc60 = 1.0 / (2.0 * Double.pi * 60)
        let rc1500 = 1.0 / (2.0 * Double.pi * 1_500)
        let dt = 1.0 / sampleRate
        let alpha60 = Float(rc60 / (rc60 + dt))
        let alpha1500 = Float(rc1500 / (rc1500 + dt))
        var prefix = Array(repeating: Float.zero, count: signal.count + 1)
        var high60 = signal[0]
        var high1500 = signal[0]
        let firstWeighted = high60 + high1500 * 0.25
        prefix[1] = firstWeighted * firstWeighted

        guard signal.count > 1 else { return prefix }
        for index in 1..<signal.count {
            high60 = alpha60 * (high60 + signal[index] - signal[index - 1])
            high1500 = alpha1500 * (high1500 + signal[index] - signal[index - 1])
            let weighted = high60 + high1500 * 0.25
            prefix[index + 1] = prefix[index] + weighted * weighted
        }
        return prefix
    }

    private static func meanSquare(in prefix: [Float], start: Int, end: Int) -> Float {
        guard start < end, start >= 0, end < prefix.count else { return 0 }
        return (prefix[end] - prefix[start]) / Float(max(end - start, 1))
    }

    private static func binRange(_ range: ClosedRange<Double>, frequencyStep: Double, binCount: Int) -> BinRange {
        let lower = max(0, min(Int(range.lowerBound / frequencyStep), binCount - 1))
        let upper = max(lower, min(Int(range.upperBound / frequencyStep), binCount - 1))
        return BinRange(lower: lower, upperInclusive: upper)
    }

    private static func bandLevelDB(energy: Float, count: Int) -> Double {
        let rms = sqrt(max(energy / Float(max(count, 1)), 1e-12))
        return 20 * log10(max(Double(rms), 1e-12))
    }

    private static func oversampledPeak(_ channel: [Float]) -> Float {
        guard channel.count > 1 else { return channel.map { abs($0) }.max() ?? 0 }
        return channel.withUnsafeBufferPointer { buffer in
            guard let samples = buffer.baseAddress else { return 0 }
            let sampleCount = buffer.count
            var peak = abs(samples[0])
            var index = 0

            while index < sampleCount - 1 {
                let p0 = index > 0 ? samples[index - 1] : samples[index]
                let p1 = samples[index]
                let p2 = samples[index + 1]
                let p3 = index + 2 < sampleCount ? samples[index + 2] : p2
                peak = max(peak, abs(p1))
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.125)))
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.25)))
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.375)))
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.5)))
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.625)))
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.75)))
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: 0.875)))
                index += 1
            }
            peak = max(peak, abs(samples[sampleCount - 1]))
            return peak
        }
    }

    @inline(__always)
    private static func catmullRom(p0: Float, p1: Float, p2: Float, p3: Float, t: Float) -> Float {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            (2 * p1)
                + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }

    private struct AnalysisBenchmarkRecorder {
        private(set) var stages: [AudioProcessingStageBenchmark] = []

        mutating func measure<T>(_ stageName: String, work: () -> T) -> T {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = work()
            let end = DispatchTime.now().uptimeNanoseconds
            stages.append(
                AudioProcessingStageBenchmark(
                    name: stageName,
                    durationSeconds: Double(end - start) / 1_000_000_000
                )
            )
            return result
        }
    }
}
