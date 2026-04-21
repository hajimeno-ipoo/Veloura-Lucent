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
        #expect(metrics.harshnessScore >= 0)
        #expect(metrics.centroidHz > 0)
        #expect(metrics.hf12Ratio >= 0)
        #expect(metrics.bandEnergies.count == 4)
        #expect(metrics.masteringBandEnergies.count == 4)
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
}
