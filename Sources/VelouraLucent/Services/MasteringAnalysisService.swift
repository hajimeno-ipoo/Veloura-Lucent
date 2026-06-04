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

        var streamingStageName: String {
            switch self {
            case .cpu:
                "streamingSTFTAndSpectralSummaryCPU"
            case .metal:
                "streamingSTFTAndSpectralSummaryMetal"
            }
        }
    }

    private struct SpectralSummaryResult: Sendable, Equatable {
        let summary: MasteringSpectralSummary
        let backend: SpectralSummaryBackend
    }

    private struct SpectralFrameSummary {
        var lowEnergy: Float = 0
        var midEnergy: Float = 0
        var highEnergy: Float = 0
        var harshUpperMid: Float = 0
        var harshAir: Float = 0
        var lowCount = 0
        var midCount = 0
        var highCount = 0
        var frameCount = 0
        var backend: SpectralSummaryBackend = .cpu
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

        let frameSummary = recorder.measureSpectralFrameSummary {
            spectralFrameSummary(for: mono, sampleRate: signal.sampleRate)
        }
        let loudnessMeasurement = recorder.measure("loudness") {
            LoudnessMeasurementService.measure(signal: signal, includeLoudnessRange: false)
        }
        let peak = recorder.measure("truePeak") {
            loudnessMeasurement.truePeakDBFS
        }
        let spectralSummaryResult = recorder.measureSpectralSummary {
            spectralSummary(from: frameSummary)
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

    private static func spectralFrameSummary(for mono: [Float], sampleRate: Double) -> SpectralFrameSummary {
        metalSpectralFrameSummary(for: mono, sampleRate: sampleRate) ?? cpuSpectralFrameSummary(for: mono, sampleRate: sampleRate)
    }

    private static func metalSpectralFrameSummary(for mono: [Float], sampleRate: Double) -> SpectralFrameSummary? {
        let processor = MetalAudioAnalysisProcessor()
        guard processor.isAvailable else { return nil }

        let fftSize = SpectralDSP.fftSize
        let binCount = fftSize / 2 + 1
        let frequencyStep = sampleRate / Double(fftSize)
        let lowRange = binRange(20...180, frequencyStep: frequencyStep, binCount: binCount)
        let midRange = binRange(180...5_000, frequencyStep: frequencyStep, binCount: binCount)
        let highRange = binRange(5_000...20_000, frequencyStep: frequencyStep, binCount: binCount)

        let chunkFrameCapacity = 512
        var summary = SpectralFrameSummary(backend: .metal)
        var chunkReal: [Float] = []
        var chunkImag: [Float] = []
        var chunkFrameCount = 0
        chunkReal.reserveCapacity(chunkFrameCapacity * binCount)
        chunkImag.reserveCapacity(chunkFrameCapacity * binCount)

        func flushChunk() -> Bool {
            guard chunkFrameCount > 0 else { return true }
            guard let frameSums = processor.masteringSpectralFrameSums(
                realValues: chunkReal,
                imagValues: chunkImag,
                frameCount: chunkFrameCount,
                binCount: binCount,
                fftSize: fftSize,
                sampleRate: sampleRate
            ) else {
                return false
            }

            accumulateFrameSums(frameSums, frameCount: chunkFrameCount, into: &summary)
            chunkReal.removeAll(keepingCapacity: true)
            chunkImag.removeAll(keepingCapacity: true)
            chunkFrameCount = 0
            return true
        }

        var failed = false
        SpectralDSP.forEachSTFTFrame(mono, fftSize: fftSize, hopSize: SpectralDSP.hopSize) { _, _, real, imag in
            guard !failed else { return }
            chunkReal.append(contentsOf: real.prefix(binCount))
            chunkImag.append(contentsOf: imag.prefix(binCount))
            chunkFrameCount += 1
            if chunkFrameCount == chunkFrameCapacity {
                failed = !flushChunk()
            }
        }
        guard !failed, flushChunk() else { return nil }

        summary.lowCount = summary.frameCount * (lowRange.upperInclusive - lowRange.lower + 1)
        summary.midCount = summary.frameCount * (midRange.upperInclusive - midRange.lower + 1)
        summary.highCount = summary.frameCount * (highRange.upperInclusive - highRange.lower + 1)
        return summary
    }

    private static func cpuSpectralFrameSummary(for mono: [Float], sampleRate: Double) -> SpectralFrameSummary {
        let fftSize = SpectralDSP.fftSize
        let binCount = fftSize / 2 + 1
        let frequencyStep = sampleRate / Double(fftSize)
        let lowRange = binRange(20...180, frequencyStep: frequencyStep, binCount: binCount)
        let midRange = binRange(180...5_000, frequencyStep: frequencyStep, binCount: binCount)
        let highRange = binRange(5_000...20_000, frequencyStep: frequencyStep, binCount: binCount)
        let harshUpperMidRange = binRange(3_000...8_000, frequencyStep: frequencyStep, binCount: binCount)
        let harshAirRange = binRange(12_000...(sampleRate * 0.5), frequencyStep: frequencyStep, binCount: binCount)
        let maxBin = max(
            lowRange.upperInclusive,
            midRange.upperInclusive,
            highRange.upperInclusive,
            harshUpperMidRange.upperInclusive,
            harshAirRange.upperInclusive
        )

        var summary = SpectralFrameSummary()
        SpectralDSP.forEachSTFTFrame(mono, fftSize: fftSize, hopSize: SpectralDSP.hopSize) { _, _, real, imag in
            summary.frameCount += 1
            var frameLowEnergy: Float = 0
            var frameMidEnergy: Float = 0
            var frameHighEnergy: Float = 0
            var frameHarshUpperMid: Float = 0
            var frameHarshAir: Float = 0

            for binIndex in 0...maxBin {
                let magnitude = stableMagnitude(real: real[binIndex], imag: imag[binIndex])
                let energy = magnitude * magnitude

                if lowRange.contains(binIndex) {
                    frameLowEnergy += energy
                }
                if midRange.contains(binIndex) {
                    frameMidEnergy += energy
                }
                if highRange.contains(binIndex) {
                    frameHighEnergy += energy
                }
                if harshUpperMidRange.contains(binIndex) {
                    frameHarshUpperMid += magnitude
                }
                if harshAirRange.contains(binIndex) {
                    frameHarshAir += magnitude
                }
            }

            summary.lowEnergy += frameLowEnergy
            summary.midEnergy += frameMidEnergy
            summary.highEnergy += frameHighEnergy
            summary.harshUpperMid += frameHarshUpperMid
            summary.harshAir += frameHarshAir
        }
        summary.lowCount = summary.frameCount * (lowRange.upperInclusive - lowRange.lower + 1)
        summary.midCount = summary.frameCount * (midRange.upperInclusive - midRange.lower + 1)
        summary.highCount = summary.frameCount * (highRange.upperInclusive - highRange.lower + 1)
        return summary
    }

    private static func spectralSummary(from frameSummary: SpectralFrameSummary) -> SpectralSummaryResult {
        guard frameSummary.frameCount > 0 else {
            return SpectralSummaryResult(
                summary: MasteringSpectralSummary(lowBandLevelDB: -120, midBandLevelDB: -120, highBandLevelDB: -120, harshnessScore: 0),
                backend: frameSummary.backend
            )
        }

        return SpectralSummaryResult(
            summary: MasteringSpectralSummary(
                lowBandLevelDB: bandLevelDB(energy: frameSummary.lowEnergy, count: frameSummary.lowCount),
                midBandLevelDB: bandLevelDB(energy: frameSummary.midEnergy, count: frameSummary.midCount),
                highBandLevelDB: bandLevelDB(energy: frameSummary.highEnergy, count: frameSummary.highCount),
                harshnessScore: min(1.0, frameSummary.harshUpperMid / max(frameSummary.harshUpperMid + frameSummary.harshAir, 1e-6))
            ),
            backend: frameSummary.backend
        )
    }

    private static func accumulateFrameSums(_ frameSums: [Float], frameCount: Int, into summary: inout SpectralFrameSummary) {
        for frameIndex in 0..<frameCount {
            let outputStart = frameIndex * 5
            summary.lowEnergy += frameSums[outputStart]
            summary.midEnergy += frameSums[outputStart + 1]
            summary.highEnergy += frameSums[outputStart + 2]
            summary.harshUpperMid += frameSums[outputStart + 3]
            summary.harshAir += frameSums[outputStart + 4]
        }
        summary.frameCount += frameCount
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

    private static func stableMagnitude(real: Float, imag: Float) -> Float {
        let realValue = abs(real)
        let imagValue = abs(imag)
        let larger = max(realValue, imagValue)
        guard larger > 0 else { return 0 }
        let smaller = min(realValue, imagValue)
        let ratio = smaller / larger
        return larger * sqrtf(1 + ratio * ratio)
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

        mutating func measureSpectralFrameSummary(_ work: () -> SpectralFrameSummary) -> SpectralFrameSummary {
            let start = DispatchTime.now().uptimeNanoseconds
            let result = work()
            let end = DispatchTime.now().uptimeNanoseconds
            stages.append(
                AudioProcessingStageBenchmark(
                    name: result.backend.streamingStageName,
                    durationSeconds: Double(end - start) / 1_000_000_000
                )
            )
            return result
        }
    }
}
