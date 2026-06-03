import Accelerate
import Foundation

struct MasteringSpectralSummary: Sendable, Equatable {
    let lowBandLevelDB: Double
    let midBandLevelDB: Double
    let highBandLevelDB: Double
    let harshnessScore: Float
}

enum MasteringAnalysisService {
    enum SpectralSummaryBackend: Sendable, Equatable {
        case cpu
        case metal

        var stageName: String {
            switch self {
            case .cpu:
                "spectralSummaryCPU"
            case .metal:
                "spectralSummaryMetal"
            }
        }
    }

    private struct SpectralSummaryResult: Sendable, Equatable {
        let summary: MasteringSpectralSummary
        let backend: SpectralSummaryBackend
    }

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
        let loudnessMeasurement = recorder.measure("loudness") {
            LoudnessMeasurementService.measure(signal: signal, includeLoudnessRange: false)
        }
        let peak = recorder.measure("truePeak") {
            loudnessMeasurement.truePeakDBFS
        }
        let spectralSummaryResult = recorder.measureSpectralSummary {
            spectralSummary(for: spectrogram, sampleRate: signal.sampleRate)
        }
        let width = recorder.measure("stereoWidth") {
            stereoWidth(for: signal)
        }

        let analysis = MasteringAnalysis(
            integratedLoudness: Float(loudnessMeasurement.integratedLoudnessLUFS),
            truePeakDBFS: peak,
            lowBandLevelDB: spectralSummaryResult.summary.lowBandLevelDB,
            midBandLevelDB: spectralSummaryResult.summary.midBandLevelDB,
            highBandLevelDB: spectralSummaryResult.summary.highBandLevelDB,
            harshnessScore: spectralSummaryResult.summary.harshnessScore,
            stereoWidth: width
        )
        return Benchmark(analysis: analysis, stages: recorder.stages)
    }

    static func integratedLoudness(signal: AudioSignal) -> Float {
        LoudnessMeasurementService.integratedLoudness(signal: signal)
    }

    static func approximateTruePeak(_ channels: [[Float]]) -> Float {
        LoudnessMeasurementService.truePeakLinear(channels)
    }

    private struct BinRange {
        let lower: Int
        let upperInclusive: Int

        func contains(_ binIndex: Int) -> Bool {
            binIndex >= lower && binIndex <= upperInclusive
        }
    }

    private static func spectralSummary(for spectrogram: Spectrogram, sampleRate: Double) -> SpectralSummaryResult {
        if let metalSummary = MetalAudioAnalysisProcessor().masteringSpectralSummary(spectrogram: spectrogram, sampleRate: sampleRate) {
            return SpectralSummaryResult(summary: metalSummary, backend: .metal)
        }
        return SpectralSummaryResult(summary: cpuSpectralSummary(for: spectrogram, sampleRate: sampleRate), backend: .cpu)
    }

    private static func cpuSpectralSummary(for spectrogram: Spectrogram, sampleRate: Double) -> MasteringSpectralSummary {
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
        var leftEnergy: Float = 0
        var rightEnergy: Float = 0
        var crossEnergy: Float = 0
        left.withUnsafeBufferPointer { leftBuffer in
            right.withUnsafeBufferPointer { rightBuffer in
                guard let leftBase = leftBuffer.baseAddress, let rightBase = rightBuffer.baseAddress else { return }
                vDSP_svesq(leftBase, 1, &leftEnergy, vDSP_Length(count))
                vDSP_svesq(rightBase, 1, &rightEnergy, vDSP_Length(count))
                vDSP_dotpr(leftBase, 1, rightBase, 1, &crossEnergy, vDSP_Length(count))
            }
        }
        let totalEnergy = leftEnergy + rightEnergy
        let midEnergy = max((totalEnergy + 2 * crossEnergy) * 0.25, 0)
        let sideEnergy = max((totalEnergy - 2 * crossEnergy) * 0.25, 0)
        return min(2.0, sqrt(sideEnergy / max(midEnergy, 1e-9)))
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

        mutating func measureSpectralSummary(_ work: () -> SpectralSummaryResult) -> SpectralSummaryResult {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = work()
            let end = DispatchTime.now().uptimeNanoseconds
            stages.append(
                AudioProcessingStageBenchmark(
                    name: result.backend.stageName,
                    durationSeconds: Double(end - start) / 1_000_000_000
                )
            )
            return result
        }
    }
}
