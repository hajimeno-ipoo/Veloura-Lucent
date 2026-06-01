import AVFoundation
import AudioToolbox
import Foundation
import Testing
@testable import VelouraLucent

struct AudioExportTests {
    @Test
    func supportedFormatsWriteExpectedAudioFiles() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "source.wav")
        try AudioFileService.saveAudio(testSignal(), to: sourceURL)

        for format in AudioExportFormat.allCases {
            let outputURL = directory.appending(path: "output-\(format.rawValue).\(format.fileExtension)")
            try AudioFileService.exportAudio(from: sourceURL, to: outputURL, format: format)

            let file = try AVAudioFile(forReading: outputURL)
            let stream = file.fileFormat.streamDescription.pointee

            #expect(FileManager.default.fileExists(atPath: outputURL.path()))
            #expect(file.fileFormat.channelCount == 2)
            #expect(outputURL.pathExtension == format.fileExtension)
            #expect(abs(Double(file.length) / file.fileFormat.sampleRate - 0.1) < 0.01)

            switch format {
            case .highQualityWAV:
                #expect(try Data(contentsOf: outputURL) == Data(contentsOf: sourceURL))
                #expect(file.fileFormat.sampleRate == 48_000)
                #expect(stream.mFormatID == kAudioFormatLinearPCM)
                #expect(stream.mBitsPerChannel == 32)
                #expect(stream.mFormatFlags & kAudioFormatFlagIsFloat != 0)
            case .deliveryWAV:
                #expect(file.fileFormat.sampleRate == 48_000)
                #expect(stream.mFormatID == kAudioFormatLinearPCM)
                #expect(stream.mBitsPerChannel == 24)
                #expect(stream.mFormatFlags & kAudioFormatFlagIsFloat == 0)
            case .cdWAV:
                #expect(file.fileFormat.sampleRate == 44_100)
                #expect(stream.mFormatID == kAudioFormatLinearPCM)
                #expect(stream.mBitsPerChannel == 16)
                #expect(stream.mFormatFlags & kAudioFormatFlagIsFloat == 0)
            case .sharingAAC:
                #expect(file.fileFormat.sampleRate == 48_000)
                #expect(stream.mFormatID == kAudioFormatMPEG4AAC)
            }

            let writtenSignal = try AudioFileService.loadAudio(from: outputURL)
            #expect(writtenSignal.channels.allSatisfy { channel in channel.allSatisfy(\.isFinite) })
        }
    }

    @Test
    func tpdfDitherChangesSilenceWithinOneLeastSignificantBit() {
        let signal = AudioSignal(channels: [Array(repeating: 0, count: 2_048)], sampleRate: 44_100)
        let first = AudioFileService.applyTPDFDither(to: signal, bitDepth: 16, seed: 42)
        let second = AudioFileService.applyTPDFDither(to: signal, bitDepth: 16, seed: 42)
        let samples = first.channels[0]
        let leastSignificantBit = Float(1.0 / pow(2.0, 15))

        #expect(samples.contains { $0 != 0 })
        #expect(samples.allSatisfy { abs($0) <= leastSignificantBit })
        #expect(first.channels == second.channels)
    }

    @Test
    func integerExportLimitsSamplesToPCMRange() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "loud-source.wav")
        let outputURL = directory.appending(path: "loud-delivery.wav")
        let signal = AudioSignal(channels: [[-1.4, -1, 0, 1, 1.4]], sampleRate: 48_000)
        try AudioFileService.saveAudio(signal, to: sourceURL)
        try AudioFileService.exportAudio(from: sourceURL, to: outputURL, format: .deliveryWAV)

        let written = try AudioFileService.loadAudio(from: outputURL)
        #expect(written.channels[0].allSatisfy { $0 >= -1 && $0 <= 1 })
    }

    @Test
    func exportReplacesExistingDestinationAfterConversion() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "source.wav")
        let outputURL = directory.appending(path: "existing.wav")
        try AudioFileService.saveAudio(testSignal(), to: sourceURL)
        try Data("old".utf8).write(to: outputURL)

        try AudioFileService.exportAudio(from: sourceURL, to: outputURL, format: .deliveryWAV)

        let file = try AVAudioFile(forReading: outputURL)
        #expect(file.fileFormat.streamDescription.pointee.mBitsPerChannel == 24)
    }

    @Test
    func encodedExportRejectsNonFiniteSamples() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "non-finite-source.wav")
        let outputURL = directory.appending(path: "non-finite-delivery.wav")
        let signal = AudioSignal(channels: [[0, .nan, 0]], sampleRate: 48_000)
        try AudioFileService.saveAudio(signal, to: sourceURL)

        #expect(throws: AppError.self) {
            try AudioFileService.exportAudio(from: sourceURL, to: outputURL, format: .deliveryWAV)
        }
    }

    private func testSignal() -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = 4_800
        let left = (0..<frameCount).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.55)
        }
        let right = (0..<frameCount).map { index in
            Float(sin(2 * Double.pi * 880 * Double(index) / sampleRate) * 0.45)
        }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "veloura-audio-export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
