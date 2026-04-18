import AVFoundation
import Foundation
import Testing
@testable import SpectralLifter

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

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }
}
