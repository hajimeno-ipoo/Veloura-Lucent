import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct AudioFileServiceTests {
    @Test
    func loadAudioKeepsFortyEightKilohertzInputUnchanged() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = testSignal(sampleRate: 48_000)
        let sourceURL = directory.appending(path: "source-48k.wav")
        try AudioFileService.saveAudio(source, to: sourceURL)

        let loaded = try AudioFileService.loadAudio(from: sourceURL)

        #expect(loaded.sampleRate == 48_000)
        #expect(loaded.frameCount == source.frameCount)
        #expect(loaded.channels.count == source.channels.count)
        #expect(maximumAbsoluteDifference(loaded, source) <= 0.000_001)
    }

    @Test
    func loadAudioConvertsFortyFourPointOneKilohertzInputToFortyEightKilohertz() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = testSignal(sampleRate: 44_100)
        let sourceURL = directory.appending(path: "source-44k1.wav")
        try AudioFileService.saveAudio(source, to: sourceURL)

        let loaded = try AudioFileService.loadAudio(from: sourceURL)

        #expect(loaded.sampleRate == AudioFileService.targetSampleRate)
        #expect(loaded.frameCount == 4_800)
        #expect(loaded.channels.count == source.channels.count)
    }

    @Test
    func loadAudioResamplingMatchesAVAudioConverterReference() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = testSignal(sampleRate: 44_100)
        let sourceURL = directory.appending(path: "source-44k1.wav")
        try AudioFileService.saveAudio(source, to: sourceURL)
        let savedSource = try loadRawAudio(from: sourceURL)
        let expected = try referenceConvertedSampleRate(
            signal: savedSource,
            to: AudioFileService.targetSampleRate
        )

        let loaded = try AudioFileService.loadAudio(from: sourceURL)

        #expect(loaded.sampleRate == expected.sampleRate)
        #expect(loaded.frameCount == expected.frameCount)
        #expect(loaded.channels.count == expected.channels.count)
        #expect(rootMeanSquareDifference(loaded, expected) <= 0.000_001)
        #expect(maximumAbsoluteDifference(loaded, expected) <= 0.000_01)
    }

    private func testSignal(sampleRate: Double) -> AudioSignal {
        let frameCount = Int(sampleRate * 0.1)
        let left = (0..<frameCount).map { index in
            let time = Double(index) / sampleRate
            return Float(
                sin(2 * Double.pi * 440 * time) * 0.36
                    + sin(2 * Double.pi * 6_400 * time) * 0.08
            )
        }
        let right = (0..<frameCount).map { index in
            let time = Double(index) / sampleRate
            return Float(
                sin(2 * Double.pi * 880 * time) * 0.28
                    + sin(2 * Double.pi * 10_200 * time) * 0.05
            )
        }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "veloura-audio-file-service-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func loadRawAudio(from url: URL) throws -> AudioSignal {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: file.processingFormat.channelCount,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return audioSignal(from: buffer)
    }

    private func referenceConvertedSampleRate(signal sourceSignal: AudioSignal, to sampleRate: Double) throws -> AudioSignal {
        let channelCount = AVAudioChannelCount(sourceSignal.channels.count)
        guard
            let inputFormat = AVAudioFormat(standardFormatWithSampleRate: sourceSignal.sampleRate, channels: channelCount),
            let outputFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channelCount),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            throw AppError.audioWriteFailed
        }

        let inputBuffer = try pcmBuffer(from: sourceSignal, format: inputFormat)
        let outputCapacity = AVAudioFrameCount(ceil(Double(sourceSignal.frameCount) * sampleRate / sourceSignal.sampleRate)) + 64
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            throw AppError.audioWriteFailed
        }

        let inputState = TestAudioConverterInputState(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if inputState.didProvideInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputState.didProvideInput = true
            inputStatus.pointee = .haveData
            return inputState.buffer
        }
        guard status != .error, conversionError == nil else {
            throw conversionError ?? AppError.audioWriteFailed
        }
        return audioSignal(from: outputBuffer)
    }

    private func pcmBuffer(from signal: AudioSignal, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(signal.frameCount)) else {
            throw AppError.audioWriteFailed
        }
        buffer.frameLength = AVAudioFrameCount(signal.frameCount)
        for (channelIndex, channel) in signal.channels.enumerated() {
            guard let destination = buffer.floatChannelData?[channelIndex] else {
                throw AppError.audioWriteFailed
            }
            destination.update(from: channel, count: channel.count)
        }
        return buffer
    }

    private func audioSignal(from buffer: AVAudioPCMBuffer) -> AudioSignal {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let channels = (0..<channelCount).map { channelIndex in
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![channelIndex], count: frameLength))
        }
        return AudioSignal(channels: channels, sampleRate: buffer.format.sampleRate)
    }

    private func rootMeanSquareDifference(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Double {
        let channelCount = min(lhs.channels.count, rhs.channels.count)
        var sumSquares = 0.0
        var sampleCount = 0
        for channelIndex in 0..<channelCount {
            let frameCount = min(lhs.channels[channelIndex].count, rhs.channels[channelIndex].count)
            for frameIndex in 0..<frameCount {
                let difference = Double(lhs.channels[channelIndex][frameIndex] - rhs.channels[channelIndex][frameIndex])
                sumSquares += difference * difference
                sampleCount += 1
            }
        }
        return sqrt(sumSquares / Double(max(sampleCount, 1)))
    }

    private func maximumAbsoluteDifference(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Float {
        let channelCount = min(lhs.channels.count, rhs.channels.count)
        var maximum: Float = 0
        for channelIndex in 0..<channelCount {
            let frameCount = min(lhs.channels[channelIndex].count, rhs.channels[channelIndex].count)
            for frameIndex in 0..<frameCount {
                maximum = max(maximum, abs(lhs.channels[channelIndex][frameIndex] - rhs.channels[channelIndex][frameIndex]))
            }
        }
        return maximum
    }
}

private final class TestAudioConverterInputState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
