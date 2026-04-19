import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct SpectrogramSnapshotTests {
    @Test
    func spectrogramSnapshotContainsCells() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let fileURL = tempDirectory.appending(path: "spectrogram.wav")

        try makeTestTone(at: fileURL)

        let snapshot = try AudioFileService.makeSpectrogramSnapshot(for: fileURL)

        #expect(snapshot.cells.isEmpty == false)
        #expect(snapshot.timeBucketCount > 0)
        #expect(snapshot.frequencyBucketCount > 0)
    }

    private func makeTestTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            channel[index] = Float(sin(2 * Double.pi * 440 * t) * 0.1 + sin(2 * Double.pi * 4000 * t) * 0.03)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }
}
