import Accelerate
import Foundation

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
        let weighted = kWeight(mono, sampleRate: sampleRate)
        let energyPrefix = energyPrefix(for: weighted)
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

        let absoluteGated = blockLoudness.filter { $0 > -70 }
        guard !absoluteGated.isEmpty else { return -70 }
        let preliminary = energyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return energyAverage(relativeGated.isEmpty ? absoluteGated : relativeGated)
    }

    static func approximateTruePeak(_ channels: [[Float]]) -> Float {
        channels.map(oversampledPeak).max() ?? 0
    }

    private struct SpectralSummary {
        let lowBandLevelDB: Double
        let midBandLevelDB: Double
        let highBandLevelDB: Double
        let harshnessScore: Float
    }

    private struct BinRange {
        let lower: Int
        let upperInclusive: Int
    }

    private static func spectralSummary(for spectrogram: Spectrogram, sampleRate: Double) -> SpectralSummary {
        guard spectrogram.frameCount > 0 else {
            return SpectralSummary(lowBandLevelDB: -120, midBandLevelDB: -120, highBandLevelDB: -120, harshnessScore: 0)
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

        for frameIndex in 0..<spectrogram.frameCount {
            accumulateBandEnergy(spectrogram: spectrogram, frameIndex: frameIndex, range: lowRange, energy: &lowEnergy, count: &lowCount)
            accumulateBandEnergy(spectrogram: spectrogram, frameIndex: frameIndex, range: midRange, energy: &midEnergy, count: &midCount)
            accumulateBandEnergy(spectrogram: spectrogram, frameIndex: frameIndex, range: highRange, energy: &highEnergy, count: &highCount)
            harshUpperMid += magnitudeSum(spectrogram: spectrogram, frameIndex: frameIndex, range: harshUpperMidRange)
            harshAir += magnitudeSum(spectrogram: spectrogram, frameIndex: frameIndex, range: harshAirRange)
        }

        return SpectralSummary(
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

    private static func energyAverage(_ loudnessValues: [Float]) -> Float {
        let meanEnergy = loudnessValues.map { powf(10, $0 / 10) }.reduce(0, +) / Float(max(loudnessValues.count, 1))
        return 10 * log10f(max(meanEnergy, 1e-9))
    }

    private static func energyPrefix(for values: [Float]) -> [Float] {
        var prefix = Array(repeating: Float.zero, count: values.count + 1)
        for index in values.indices {
            prefix[index + 1] = prefix[index] + values[index] * values[index]
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

    private static func accumulateBandEnergy(
        spectrogram: Spectrogram,
        frameIndex: Int,
        range: BinRange,
        energy: inout Float,
        count: inout Int
    ) {
        for binIndex in range.lower...range.upperInclusive {
            let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            energy += magnitude * magnitude
            count += 1
        }
    }

    private static func magnitudeSum(spectrogram: Spectrogram, frameIndex: Int, range: BinRange) -> Float {
        var sum: Float = 0
        for binIndex in range.lower...range.upperInclusive {
            sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
        }
        return sum
    }

    private static func bandLevelDB(energy: Float, count: Int) -> Double {
        let rms = sqrt(max(energy / Float(max(count, 1)), 1e-12))
        return 20 * log10(max(Double(rms), 1e-12))
    }

    private static func kWeight(_ signal: [Float], sampleRate: Double) -> [Float] {
        let highPassed = SpectralDSP.highPass(signal, cutoff: 60, sampleRate: sampleRate)
        let shelfBase = SpectralDSP.highPass(signal, cutoff: 1_500, sampleRate: sampleRate)
        return zip(highPassed, shelfBase).map { $0 + $1 * 0.25 }
    }

    private static func oversampledPeak(_ channel: [Float]) -> Float {
        guard channel.count > 1 else { return channel.map { abs($0) }.max() ?? 0 }
        var peak: Float = 0
        for index in 0..<(channel.count - 1) {
            let p0 = index > 0 ? channel[index - 1] : channel[index]
            let p1 = channel[index]
            let p2 = channel[index + 1]
            let p3 = index + 2 < channel.count ? channel[index + 2] : p2
            peak = max(peak, abs(p1))
            for step in 1...7 {
                let t = Float(step) / 8
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: t)))
            }
        }
        peak = max(peak, abs(channel[channel.count - 1]))
        return peak
    }

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
