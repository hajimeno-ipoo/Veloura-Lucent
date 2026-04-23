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
        #expect(benchmark.stages.map(\.name) == ["stft", "loudness", "truePeak", "spectralSummary", "stereoWidth"])
        #expect(benchmark.stages.allSatisfy { $0.durationSeconds >= 0 })
        #expect(benchmark.analysis.integratedLoudness.isFinite)
        #expect(benchmark.analysis.truePeakDBFS.isFinite)

        let report = realAudioBenchmarkReport(inputURL: inputURL, benchmark: benchmark)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentRealMasteringAnalysisBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
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

    private func realAudioBenchmarkReport(inputURL: URL, benchmark: MasteringAnalysisService.Benchmark) -> String {
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
        return lines.joined(separator: "\n")
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
}
