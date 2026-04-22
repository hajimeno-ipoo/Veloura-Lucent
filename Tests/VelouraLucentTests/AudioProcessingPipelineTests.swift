import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct AudioProcessingPipelineTests {
    @Test
    func pipelineProducesOutputFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "input.wav")

        try makeTestTone(at: inputURL)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong
        ) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(output.lastPathComponent.contains("input_lifter"))
        let written = try AVAudioFile(forReading: output)
        #expect(written.length > 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: written.processingFormat, frameCapacity: AVAudioFrameCount(written.length))!
        try written.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        #expect(samples.contains { $0.isFinite })
        #expect(samples.map { abs($0) }.max() ?? 0 <= 1.01)
    }

    @Test
    func pipelineHandlesLocalizedFilename() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "violin #002 睡眠.wav")

        try makeTestTone(at: inputURL, duration: 6)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .gentle
        ) { _ in }

        #expect(output.lastPathComponent.contains("_lifter_"))
        #expect(FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test
    func pipelineAcceptsExperimentalMetalAnalysisMode() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "metal-analysis.wav")

        try makeTestTone(at: inputURL)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .experimentalMetal
        ) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
    }

    @Test
    func pipelineAcceptsAutoAnalysisMode() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "auto-analysis.wav")

        try makeTestTone(at: inputURL)
        let logs = LogCollector()

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .auto
        ) { message in
            logs.append(message)
        }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(logs.values.contains("解析モード: 自動 -> \(AudioAnalysisMode.auto.resolvedMode.title)"))
    }

    @Test
    func outputURLsUseWavEvenWhenInputExtensionIsCompressed() {
        let inputURL = URL(fileURLWithPath: "/tmp/demo-track.mp3")

        let defaultOutput = AudioProcessingService.defaultOutputURL(for: inputURL)
        let temporaryOutput = AudioProcessingService.temporaryOutputURL(for: inputURL)

        #expect(defaultOutput.pathExtension == AudioFileService.outputFileExtension)
        #expect(temporaryOutput.pathExtension == AudioFileService.outputFileExtension)
    }

    private func makeTestTone(at url: URL, duration: Double = 2) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
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

private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
