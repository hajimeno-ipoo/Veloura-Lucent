import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct AudioComparisonServiceTests {
    @Test
    func comparisonMetricsAreComputed() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "analysis.wav")

        try makeTestTone(at: fileURL)

        let metrics = try AudioComparisonService.analyze(fileURL: fileURL)

        #expect(metrics.peakDBFS.isFinite)
        #expect(metrics.rmsDBFS.isFinite)
        #expect(metrics.integratedLoudnessLUFS.isFinite)
        #expect(metrics.truePeakDBFS.isFinite)
        #expect(metrics.crestFactorDB.isFinite)
        #expect(metrics.loudnessRangeLU.isFinite)
        #expect(metrics.crestFactorDB >= 0)
        #expect(metrics.loudnessRangeLU >= 0)
        #expect(metrics.stereoWidth >= 0)
        #expect(metrics.stereoCorrelation >= -1)
        #expect(metrics.stereoCorrelation <= 1)
        #expect(metrics.harshnessScore >= 0)
        #expect(metrics.centroidHz > 0)
        #expect(metrics.hf12Ratio >= 0)
        #expect(metrics.bandEnergies.count == 4)
        #expect(metrics.masteringBandEnergies.count == 4)
        #expect(metrics.shortTermLoudness.isEmpty == false)
        #expect(metrics.shortTermLoudness.allSatisfy { $0.levelDB.isFinite })
        #expect(metrics.dynamics.isEmpty == false)
        #expect(metrics.dynamics.allSatisfy { $0.crestFactorDB.isFinite })
        #expect(metrics.averageSpectrum.count == 32)
        #expect(metrics.averageSpectrum.allSatisfy { $0.levelDB.isFinite })
    }

    @Test
    func comparisonMetricsStayWithinRegressionRange() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "metric-regression.wav")

        try makeStereoRegressionTone(at: fileURL)

        let metrics = try AudioComparisonService.analyze(fileURL: fileURL)

        expectClose(metrics.peakDBFS, -17.60, tolerance: 0.20)
        expectClose(metrics.rmsDBFS, -22.05, tolerance: 0.20)
        expectClose(metrics.crestFactorDB, 4.45, tolerance: 0.20)
        expectClose(metrics.loudnessRangeLU, 0.0, tolerance: 0.05)
        expectClose(metrics.integratedLoudnessLUFS, -21.82, tolerance: 0.30)
        expectClose(metrics.truePeakDBFS, -16.77, tolerance: 0.30)
        expectClose(metrics.stereoWidth, 0.134, tolerance: 0.02)
        expectClose(metrics.stereoCorrelation, 0.981, tolerance: 0.02)
        expectClose(metrics.harshnessScore, 1.0, tolerance: 0.02)
        expectClose(metrics.centroidHz, 551.90, tolerance: 5.0)
        #expect(metrics.hf12Ratio < 1e-10)
        #expect(metrics.hf16Ratio < 1e-10)
        #expect(metrics.hf18Ratio < 1e-10)
        #expect(metrics.averageSpectrum.count == 32)
        #expect(metrics.shortTermLoudness.count == 8)
        #expect(metrics.dynamics.count == 4)
        #expect(metrics.bandEnergies.count == 4)
        #expect(metrics.masteringBandEnergies.count == 4)
    }

    @Test
    func concurrentAnalysisMatchesSynchronousAnalysis() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "metric-concurrent.wav")

        try makeStereoRegressionTone(at: fileURL)

        let signal = try AudioFileService.loadAudio(from: fileURL)
        let synchronous = try AudioComparisonService.analyze(signal: signal)
        let concurrent = try await AudioComparisonService.analyzeConcurrently(signal: signal)

        expectClose(concurrent.peakDBFS, synchronous.peakDBFS, tolerance: 0.0001)
        expectClose(concurrent.rmsDBFS, synchronous.rmsDBFS, tolerance: 0.0001)
        expectClose(concurrent.loudnessRangeLU, synchronous.loudnessRangeLU, tolerance: 0.0001)
        expectClose(concurrent.integratedLoudnessLUFS, synchronous.integratedLoudnessLUFS, tolerance: 0.0001)
        expectClose(concurrent.truePeakDBFS, synchronous.truePeakDBFS, tolerance: 0.0001)
        expectClose(concurrent.stereoWidth, synchronous.stereoWidth, tolerance: 0.0001)
        expectClose(concurrent.stereoCorrelation, synchronous.stereoCorrelation, tolerance: 0.0001)
        expectClose(concurrent.harshnessScore, synchronous.harshnessScore, tolerance: 0.0001)
        expectClose(concurrent.centroidHz, synchronous.centroidHz, tolerance: 0.0001)
        #expect(concurrent.averageSpectrum.count == synchronous.averageSpectrum.count)
        #expect(concurrent.shortTermLoudness.count == synchronous.shortTermLoudness.count)
        #expect(concurrent.dynamics.count == synchronous.dynamics.count)
    }

    private func makeTestTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            channel[index] = Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.1)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func makeStereoRegressionTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let tone = sin(2 * Double.pi * 440 * time) * 0.12
            let overtone = sin(2 * Double.pi * 3_200 * time) * 0.025
            left[index] = Float(tone + overtone)
            right[index] = Float(sin(2 * Double.pi * 440 * time + 0.2) * 0.10 + overtone * 0.8)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
