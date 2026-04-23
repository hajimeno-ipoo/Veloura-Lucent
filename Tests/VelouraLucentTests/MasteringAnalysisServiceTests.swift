import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct MasteringAnalysisServiceTests {
    @Test
    func masteringAnalysisReturnsFiniteValues() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "mastering-analysis.wav")

        try makeStereoTone(at: fileURL)

        let analysis = try MasteringAnalysisService.analyze(fileURL: fileURL)

        #expect(analysis.integratedLoudness.isFinite)
        #expect(analysis.truePeakDBFS.isFinite)
        #expect(analysis.lowBandLevelDB.isFinite)
        #expect(analysis.midBandLevelDB.isFinite)
        #expect(analysis.highBandLevelDB.isFinite)
        #expect(analysis.stereoWidth >= 0)
    }

    @Test
    func masteringAnalysisBenchmarkRecordsStages() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "mastering-analysis-benchmark.wav")

        try makeStereoTone(at: fileURL)

        let plainAnalysis = try MasteringAnalysisService.analyze(fileURL: fileURL)
        let benchmark = try MasteringAnalysisService.analyzeWithBenchmark(fileURL: fileURL)
        let expectedStages = ["stft", "loudness", "truePeak", "spectralSummary", "stereoWidth"]

        #expect(benchmark.analysis.integratedLoudness == plainAnalysis.integratedLoudness)
        #expect(benchmark.analysis.truePeakDBFS == plainAnalysis.truePeakDBFS)
        #expect(benchmark.analysis.lowBandLevelDB == plainAnalysis.lowBandLevelDB)
        #expect(benchmark.analysis.midBandLevelDB == plainAnalysis.midBandLevelDB)
        #expect(benchmark.analysis.highBandLevelDB == plainAnalysis.highBandLevelDB)
        #expect(benchmark.analysis.harshnessScore == plainAnalysis.harshnessScore)
        #expect(benchmark.analysis.stereoWidth == plainAnalysis.stereoWidth)
        #expect(benchmark.stages.map(\.name) == expectedStages)
        #expect(benchmark.stages.allSatisfy { $0.durationSeconds >= 0 })

        let report = benchmarkReport(for: benchmark)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentMasteringAnalysisBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    @Test
    func masteringAnalysisMatchesReferenceImplementation() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "mastering-analysis-reference.wav")

        try makeStereoTone(at: fileURL)

        let signal = try AudioFileService.loadAudio(from: fileURL)
        let analysis = MasteringAnalysisService.analyze(signal: signal)
        let reference = referenceAnalysis(signal: signal)

        #expect(analysis.integratedLoudness == reference.integratedLoudness)
        #expect(analysis.truePeakDBFS == reference.truePeakDBFS)
        #expect(analysis.lowBandLevelDB == reference.lowBandLevelDB)
        #expect(analysis.midBandLevelDB == reference.midBandLevelDB)
        #expect(analysis.highBandLevelDB == reference.highBandLevelDB)
        #expect(analysis.harshnessScore == reference.harshnessScore)
        #expect(analysis.stereoWidth == reference.stereoWidth)
    }

    @Test
    func recordsRealAudioMasteringAnalysisBenchmark() throws {
        guard ProcessInfo.processInfo.environment["VELOURA_RUN_REAL_AUDIO_BENCHMARK"] == "1" else {
            return
        }

        let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let inputURL = projectDirectory.appending(path: "violin #002 睡眠.wav")
        guard FileManager.default.fileExists(atPath: inputURL.path(percentEncoded: false)) else {
            Issue.record("Real audio fixture is missing: \(inputURL.path(percentEncoded: false))")
            return
        }

        let benchmark = try MasteringAnalysisService.analyzeWithBenchmark(fileURL: inputURL)
        let signal = try AudioFileService.loadAudio(from: inputURL)
        let spectrogram = SpectralDSP.stft(signal.monoMixdown())
        let metalSpectralSummary = measureMetalSpectralSummary(spectrogram: spectrogram, sampleRate: signal.sampleRate)
        #expect(benchmark.stages.map(\.name) == ["stft", "loudness", "truePeak", "spectralSummary", "stereoWidth"])
        #expect(benchmark.stages.allSatisfy { $0.durationSeconds >= 0 })
        #expect(benchmark.analysis.integratedLoudness.isFinite)
        #expect(benchmark.analysis.truePeakDBFS.isFinite)

        let report = realAudioBenchmarkReport(inputURL: inputURL, benchmark: benchmark, metalSpectralSummary: metalSpectralSummary)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentRealMasteringAnalysisBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    @Test
    func metalMasteringSpectralSummaryStaysNearCPUWhenAvailable() throws {
        let processor = MetalAudioAnalysisProcessor()
        guard processor.isAvailable else { return }

        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "metal-mastering-summary.wav")

        try makeStereoTone(at: fileURL)

        let signal = try AudioFileService.loadAudio(from: fileURL)
        let spectrogram = SpectralDSP.stft(signal.monoMixdown())
        let cpu = MasteringAnalysisService.analyze(signal: signal)
        let metal = processor.masteringSpectralSummary(spectrogram: spectrogram, sampleRate: signal.sampleRate)

        #expect(metal != nil)
        guard let metal else { return }
        expectClose(metal.lowBandLevelDB, cpu.lowBandLevelDB, tolerance: 0.001)
        expectClose(metal.midBandLevelDB, cpu.midBandLevelDB, tolerance: 0.001)
        expectClose(metal.highBandLevelDB, cpu.highBandLevelDB, tolerance: 0.001)
        expectClose(metal.harshnessScore, cpu.harshnessScore, tolerance: 0.0001)
    }

    @Test
    func approximateTruePeakMatchesReferenceInterpolation() {
        let channels: [[Float]] = [
            [0, 0.12, -0.37, 0.52, -0.18, 0.04, -0.09],
            [0.08, -0.16, 0.24, -0.31, 0.18, -0.02, 0.01]
        ]

        #expect(MasteringAnalysisService.approximateTruePeak(channels) == referenceTruePeak(channels))
    }

    private func benchmarkReport(for benchmark: MasteringAnalysisService.Benchmark) -> String {
        var lines = ["MasteringAnalysisService benchmark"]
        for stage in benchmark.stages {
            lines.append("\(stage.name): \(String(format: "%.6f", stage.durationSeconds))s")
        }
        lines.append("total: \(String(format: "%.6f", benchmark.totalDurationSeconds))s")
        return lines.joined(separator: "\n")
    }

    private func realAudioBenchmarkReport(
        inputURL: URL,
        benchmark: MasteringAnalysisService.Benchmark,
        metalSpectralSummary: TimedMetalSpectralSummary?
    ) -> String {
        let slowestStage = benchmark.stages.max { $0.durationSeconds < $1.durationSeconds }
        var lines = [
            "Veloura Lucent real mastering analysis benchmark",
            "input: \(inputURL.path(percentEncoded: false))",
            "integratedLoudness: \(String(format: "%.3f", benchmark.analysis.integratedLoudness)) LKFS",
            "truePeak: \(String(format: "%.3f", benchmark.analysis.truePeakDBFS)) dBFS",
            "lowBand: \(String(format: "%.3f", benchmark.analysis.lowBandLevelDB)) dB",
            "midBand: \(String(format: "%.3f", benchmark.analysis.midBandLevelDB)) dB",
            "highBand: \(String(format: "%.3f", benchmark.analysis.highBandLevelDB)) dB",
            "harshness: \(String(format: "%.3f", benchmark.analysis.harshnessScore))",
            "stereoWidth: \(String(format: "%.3f", benchmark.analysis.stereoWidth))",
            "total: \(String(format: "%.6f", benchmark.totalDurationSeconds))s"
        ]
        if let slowestStage {
            lines.append("slowest: \(slowestStage.name)=\(String(format: "%.6f", slowestStage.durationSeconds))s")
        }
        for stage in benchmark.stages {
            lines.append("\(stage.name): \(String(format: "%.6f", stage.durationSeconds))s")
        }
        if let metalSpectralSummary {
            lines.append("experimentalMetal.spectralSummary: \(String(format: "%.6f", metalSpectralSummary.durationSeconds))s")
            lines.append("experimentalMetal.lowBand: \(String(format: "%.3f", metalSpectralSummary.summary.lowBandLevelDB)) dB")
            lines.append("experimentalMetal.midBand: \(String(format: "%.3f", metalSpectralSummary.summary.midBandLevelDB)) dB")
            lines.append("experimentalMetal.highBand: \(String(format: "%.3f", metalSpectralSummary.summary.highBandLevelDB)) dB")
            lines.append("experimentalMetal.harshness: \(String(format: "%.3f", metalSpectralSummary.summary.harshnessScore))")
            lines.append("diff.lowBand.metal_minus_cpu: \(String(format: "%.6f", metalSpectralSummary.summary.lowBandLevelDB - benchmark.analysis.lowBandLevelDB)) dB")
            lines.append("diff.midBand.metal_minus_cpu: \(String(format: "%.6f", metalSpectralSummary.summary.midBandLevelDB - benchmark.analysis.midBandLevelDB)) dB")
            lines.append("diff.highBand.metal_minus_cpu: \(String(format: "%.6f", metalSpectralSummary.summary.highBandLevelDB - benchmark.analysis.highBandLevelDB)) dB")
            lines.append("diff.harshness.metal_minus_cpu: \(String(format: "%.6f", metalSpectralSummary.summary.harshnessScore - benchmark.analysis.harshnessScore))")
            let cpuSpectralSummary = benchmark.duration(for: "spectralSummary") ?? 0
            lines.append("speedup.spectralSummary.cpu_over_experimentalMetal: \(String(format: "%.3f", speedRatio(cpuSpectralSummary, metalSpectralSummary.durationSeconds)))x")
        } else {
            lines.append("experimentalMetal.spectralSummary: unavailable")
        }
        return lines.joined(separator: "\n")
    }

    private func measureMetalSpectralSummary(spectrogram: Spectrogram, sampleRate: Double) -> TimedMetalSpectralSummary? {
        let processor = MetalAudioAnalysisProcessor()
        guard processor.isAvailable else { return nil }

        var summary: MasteringSpectralSummary?
        let duration = measureSeconds {
            summary = processor.masteringSpectralSummary(spectrogram: spectrogram, sampleRate: sampleRate)
        }
        guard let summary else { return nil }
        return TimedMetalSpectralSummary(summary: summary, durationSeconds: duration)
    }

    private func measureSeconds(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }

    private func speedRatio(_ cpu: Double, _ metal: Double) -> Double {
        metal > 0 ? cpu / metal : 0
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double) {
        #expect(abs(actual - expected) <= tolerance)
    }

    private func expectClose(_ actual: Float, _ expected: Float, tolerance: Float) {
        #expect(abs(actual - expected) <= tolerance)
    }

    private func referenceTruePeak(_ channels: [[Float]]) -> Float {
        channels.map(referenceOversampledPeak).max() ?? 0
    }

    private func referenceOversampledPeak(_ channel: [Float]) -> Float {
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
                peak = max(peak, abs(referenceCatmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: t)))
            }
        }
        peak = max(peak, abs(channel[channel.count - 1]))
        return peak
    }

    private func referenceCatmullRom(p0: Float, p1: Float, p2: Float, p3: Float, t: Float) -> Float {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            (2 * p1)
                + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }

    private func referenceAnalysis(signal: AudioSignal) -> MasteringAnalysis {
        let mono = signal.monoMixdown()
        let spectrogram = SpectralDSP.stft(mono)
        let spectralSummary = referenceSpectralSummary(for: spectrogram, sampleRate: signal.sampleRate)
        let truePeak = referenceTruePeak(signal.channels)
        return MasteringAnalysis(
            integratedLoudness: referenceIntegratedLoudness(mono: mono, sampleRate: signal.sampleRate),
            truePeakDBFS: 20 * log10(max(Double(truePeak), 1e-12)),
            lowBandLevelDB: spectralSummary.lowBandLevelDB,
            midBandLevelDB: spectralSummary.midBandLevelDB,
            highBandLevelDB: spectralSummary.highBandLevelDB,
            harshnessScore: spectralSummary.harshnessScore,
            stereoWidth: MasteringAnalysisService.stereoWidth(for: signal)
        )
    }

    private func referenceIntegratedLoudness(mono: [Float], sampleRate: Double) -> Float {
        let weighted = referenceKWeight(mono, sampleRate: sampleRate)
        let energyPrefix = referenceEnergyPrefix(for: weighted)
        let sampleCount = max(energyPrefix.count - 1, 0)
        guard sampleCount > 0 else { return -70 }

        let windowSize = max(Int(sampleRate * 0.4), 1)
        let hopSize = max(Int(sampleRate * 0.1), 1)
        var blockLoudness: [Float] = []
        var start = 0

        while start < sampleCount {
            let end = min(sampleCount, start + windowSize)
            let rms = sqrt(max(referenceMeanSquare(in: energyPrefix, start: start, end: end), 1e-9))
            blockLoudness.append(20 * log10f(rms))
            start += hopSize
        }

        let absoluteGated = blockLoudness.filter { $0 > -70 }
        guard !absoluteGated.isEmpty else { return -70 }
        let preliminary = referenceEnergyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return referenceEnergyAverage(relativeGated.isEmpty ? absoluteGated : relativeGated)
    }

    private func referenceKWeight(_ signal: [Float], sampleRate: Double) -> [Float] {
        let highPassed = SpectralDSP.highPass(signal, cutoff: 60, sampleRate: sampleRate)
        let shelfBase = SpectralDSP.highPass(signal, cutoff: 1_500, sampleRate: sampleRate)
        return zip(highPassed, shelfBase).map { $0 + $1 * 0.25 }
    }

    private func referenceEnergyAverage(_ loudnessValues: [Float]) -> Float {
        let meanEnergy = loudnessValues.map { powf(10, $0 / 10) }.reduce(0, +) / Float(max(loudnessValues.count, 1))
        return 10 * log10f(max(meanEnergy, 1e-9))
    }

    private func referenceEnergyPrefix(for values: [Float]) -> [Float] {
        var prefix = Array(repeating: Float.zero, count: values.count + 1)
        for index in values.indices {
            prefix[index + 1] = prefix[index] + values[index] * values[index]
        }
        return prefix
    }

    private func referenceMeanSquare(in prefix: [Float], start: Int, end: Int) -> Float {
        guard start < end, start >= 0, end < prefix.count else { return 0 }
        return (prefix[end] - prefix[start]) / Float(max(end - start, 1))
    }

    private func referenceSpectralSummary(for spectrogram: Spectrogram, sampleRate: Double) -> ReferenceSpectralSummary {
        guard spectrogram.frameCount > 0 else {
            return ReferenceSpectralSummary(lowBandLevelDB: -120, midBandLevelDB: -120, highBandLevelDB: -120, harshnessScore: 0)
        }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let lowRange = referenceBinRange(20...180, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let midRange = referenceBinRange(180...5_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let highRange = referenceBinRange(5_000...20_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let harshUpperMidRange = referenceBinRange(3_000...8_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let harshAirRange = referenceBinRange(12_000...(sampleRate * 0.5), frequencyStep: frequencyStep, binCount: spectrogram.binCount)

        var lowEnergy: Float = 0
        var midEnergy: Float = 0
        var highEnergy: Float = 0
        var harshUpperMid: Float = 0
        var harshAir: Float = 0
        var lowCount = 0
        var midCount = 0
        var highCount = 0

        for frameIndex in 0..<spectrogram.frameCount {
            referenceAccumulateBandEnergy(spectrogram: spectrogram, frameIndex: frameIndex, range: lowRange, energy: &lowEnergy, count: &lowCount)
            referenceAccumulateBandEnergy(spectrogram: spectrogram, frameIndex: frameIndex, range: midRange, energy: &midEnergy, count: &midCount)
            referenceAccumulateBandEnergy(spectrogram: spectrogram, frameIndex: frameIndex, range: highRange, energy: &highEnergy, count: &highCount)
            harshUpperMid += referenceMagnitudeSum(spectrogram: spectrogram, frameIndex: frameIndex, range: harshUpperMidRange)
            harshAir += referenceMagnitudeSum(spectrogram: spectrogram, frameIndex: frameIndex, range: harshAirRange)
        }

        return ReferenceSpectralSummary(
            lowBandLevelDB: referenceBandLevelDB(energy: lowEnergy, count: lowCount),
            midBandLevelDB: referenceBandLevelDB(energy: midEnergy, count: midCount),
            highBandLevelDB: referenceBandLevelDB(energy: highEnergy, count: highCount),
            harshnessScore: min(1.0, harshUpperMid / max(harshUpperMid + harshAir, 1e-6))
        )
    }

    private func referenceBinRange(_ range: ClosedRange<Double>, frequencyStep: Double, binCount: Int) -> ReferenceBinRange {
        let lower = max(0, min(Int(range.lowerBound / frequencyStep), binCount - 1))
        let upper = max(lower, min(Int(range.upperBound / frequencyStep), binCount - 1))
        return ReferenceBinRange(lower: lower, upperInclusive: upper)
    }

    private func referenceAccumulateBandEnergy(
        spectrogram: Spectrogram,
        frameIndex: Int,
        range: ReferenceBinRange,
        energy: inout Float,
        count: inout Int
    ) {
        for binIndex in range.lower...range.upperInclusive {
            let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            energy += magnitude * magnitude
            count += 1
        }
    }

    private func referenceMagnitudeSum(spectrogram: Spectrogram, frameIndex: Int, range: ReferenceBinRange) -> Float {
        var sum: Float = 0
        for binIndex in range.lower...range.upperInclusive {
            sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
        }
        return sum
    }

    private func referenceBandLevelDB(energy: Float, count: Int) -> Double {
        let rms = sqrt(max(energy / Float(max(count, 1)), 1e-12))
        return 20 * log10(max(Double(rms), 1e-12))
    }

    private func makeStereoTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for index in 0..<frameCount {
            let phase = 2 * Double.pi * Double(index) / sampleRate
            left[index] = Float(sin(phase * 220) * 0.12)
            right[index] = Float(sin(phase * 220 + 0.15) * 0.10)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private struct ReferenceSpectralSummary {
        let lowBandLevelDB: Double
        let midBandLevelDB: Double
        let highBandLevelDB: Double
        let harshnessScore: Float
    }

    private struct ReferenceBinRange {
        let lower: Int
        let upperInclusive: Int
    }

    private struct TimedMetalSpectralSummary {
        let summary: MasteringSpectralSummary
        let durationSeconds: Double
    }
}
