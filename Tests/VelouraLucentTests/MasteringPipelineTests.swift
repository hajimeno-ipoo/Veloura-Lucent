import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct MasteringPipelineTests {
    @Test
    func masteringProducesOutputFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "song_lifter.wav")

        try makeTestTone(at: inputURL)

        let output = try await MasteringService().process(inputFile: inputURL, profile: .streaming) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(output.lastPathComponent.contains("song_lifter_mastered"))

        let written = try AVAudioFile(forReading: output)
        #expect(written.length > 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: written.processingFormat, frameCapacity: AVAudioFrameCount(written.length))!
        try written.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        #expect(samples.contains { $0.isFinite })
        #expect(samples.map { abs($0) }.max() ?? 0 <= 1.01)
    }

    @Test
    func masteringAcceptsEditableSettings() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "song_lifter.wav")

        try makeTestTone(at: inputURL)

        var settings = MasteringProfile.streaming.settings
        settings.targetLoudness = -13.2
        settings.stereoWidth = 1.15
        settings.lowMidGain = 0.45
        settings.presenceGain = 0.38
        settings.deEsserAmount = 0.52

        let output = try await MasteringService().process(inputFile: inputURL, settings: settings) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
    }

    private func makeTestTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            left[index] = Float(sin(2 * Double.pi * 220 * t) * 0.08 + sin(2 * Double.pi * 8_000 * t) * 0.02)
            right[index] = Float(sin(2 * Double.pi * 220 * t + 0.12) * 0.08 + sin(2 * Double.pi * 7_600 * t) * 0.018)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }
}
