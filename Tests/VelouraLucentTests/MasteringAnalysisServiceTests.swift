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

    private func benchmarkReport(for benchmark: MasteringAnalysisService.Benchmark) -> String {
        var lines = ["MasteringAnalysisService benchmark"]
        for stage in benchmark.stages {
            lines.append("\(stage.name): \(String(format: "%.6f", stage.durationSeconds))s")
        }
        lines.append("total: \(String(format: "%.6f", benchmark.totalDurationSeconds))s")
        return lines.joined(separator: "\n")
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
