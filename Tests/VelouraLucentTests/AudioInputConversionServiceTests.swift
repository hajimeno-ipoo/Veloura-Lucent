import AudioToolbox
import AVFoundation
import CryptoKit
import Foundation
import Testing
@testable import VelouraLucent

struct AudioInputConversionServiceTests {
    @Test
    func monoMatrixDuplicatesEverySampleWithoutGainChange() throws {
        let matrix = try #require(
            try AudioInputConversionService.resolveChannelMatrix(
                channelCount: 1,
                channelLayout: nil
            ).automaticMatrix
        )
        let input = try makeBuffer(
            sampleRate: 44_100,
            channels: [[-0.75, -0.125, 0, 0.25, 0.9]]
        )

        let output = try AudioInputConversionService.apply(matrix: matrix, to: input)
        let samples = try samples(from: output)

        #expect(matrix.source == .monoDuplication)
        #expect(matrix.coefficients == [1, 1])
        #expect(samples[0] == [-0.75, -0.125, 0, 0.25, 0.9])
        #expect(samples[1] == samples[0])
    }

    @Test
    func stereoMatrixPreservesLeftAndRightWithoutCrossfeed() throws {
        let matrix = try #require(
            try AudioInputConversionService.resolveChannelMatrix(
                channelCount: 2,
                channelLayout: nil
            ).automaticMatrix
        )
        let left: [Float] = [-0.8, -0.2, 0.1, 0.7]
        let right: [Float] = [0.6, 0.3, -0.4, -0.9]
        let input = try makeBuffer(sampleRate: 44_100, channels: [left, right])

        let output = try AudioInputConversionService.apply(matrix: matrix, to: input)
        let outputSamples = try samples(from: output)

        #expect(matrix.source == .stereoIdentity)
        #expect(matrix.coefficients == [1, 0, 0, 1])
        #expect(outputSamples[0] == left)
        #expect(outputSamples[1] == right)
    }

    @Test
    func mpeg51AToStereoUsesTheCoreAudioMatrixMixMapCoefficients() throws {
        let layout = try #require(
            AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A)
        )
        let matrix = try #require(
            try AudioInputConversionService.resolveChannelMatrix(
                channelCount: 6,
                channelLayout: layout
            ).automaticMatrix
        )
        let minusThreeDB = Float(1 / sqrt(2.0))
        let expected: [Float] = [
            1, 0,
            0, 1,
            minusThreeDB, minusThreeDB,
            0, 0,
            minusThreeDB, 0,
            0, minusThreeDB
        ]

        #expect(matrix.source == .coreAudioStandardLayout)
        #expect(matrix.inputChannelCount == 6)
        #expect(matrix.coefficients.count == expected.count)
        for index in expected.indices {
            #expect(abs(matrix.coefficients[index] - expected[index]) < 0.000_001)
        }
    }

    @Test
    func unknownAndDiscreteMultichannelLayoutsAreRejectedWithoutManualConfiguration() throws {
        let tags: [AudioChannelLayoutTag] = [
            kAudioChannelLayoutTag_Unknown | 6,
            kAudioChannelLayoutTag_DiscreteInOrder | 6
        ]

        for tag in tags {
            let layout = try #require(AVAudioChannelLayout(layoutTag: tag))
            let resolution = try AudioInputConversionService.resolveChannelMatrix(
                channelCount: 6,
                channelLayout: layout
            )
            let identity = try #require(resolution.unsupportedIdentity)

            #expect(identity.channelCount == 6)
            #expect(identity.layoutTag == tag)
            #expect(throws: StemInputConversionError.unsupportedChannelLayout(identity)) {
                try AudioInputConversionService.selectChannelMatrix(resolution: resolution)
            }
        }
    }

    @Test
    func explicitUnknownOrDiscreteOneAndTwoChannelLayoutsAreRejected() throws {
        let cases: [(channelCount: Int, tag: AudioChannelLayoutTag)] = [
            (1, kAudioChannelLayoutTag_Unknown | 1),
            (2, kAudioChannelLayoutTag_Unknown | 2),
            (1, kAudioChannelLayoutTag_DiscreteInOrder | 1),
            (2, kAudioChannelLayoutTag_DiscreteInOrder | 2),
        ]

        for item in cases {
            let layout = try #require(AVAudioChannelLayout(layoutTag: item.tag))
            let resolution = try AudioInputConversionService.resolveChannelMatrix(
                channelCount: item.channelCount,
                channelLayout: layout
            )
            let identity = try #require(resolution.unsupportedIdentity)

            #expect(identity.channelCount == item.channelCount)
            #expect(identity.layoutTag == item.tag)
            #expect(throws: StemInputConversionError.unsupportedChannelLayout(identity)) {
                try AudioInputConversionService.selectChannelMatrix(resolution: resolution)
            }
        }
    }

    @Test
    func prepare44100StereoStreamsAcrossChunksWithoutChangingSamples() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appending(path: "input-44100.wav")
        let outputURL = directory.appending(path: "prepared-44100.wav")
        let left: [Float] = (0..<37).map { index in
            Float(index - 18) / 40
        }
        let right: [Float] = (0..<37).map { index in
            Float(18 - index) / 50
        }
        try writeFloatWAV(
            at: inputURL,
            sampleRate: 44_100,
            channels: [left, right]
        )

        let result = try await AudioInputConversionService(
            processingChunkFrameCount: 5
        ).prepare(inputURL: inputURL, outputURL: outputURL)
        let outputFile = try AVAudioFile(forReading: outputURL)
        let outputSamples = try readAllSamples(from: outputFile)

        #expect(outputFile.processingFormat.sampleRate == 44_100)
        #expect(outputFile.processingFormat.channelCount == 2)
        #expect(outputFile.length == 37)
        #expect(outputSamples[0] == left)
        #expect(outputSamples[1] == right)
        #expect(result.channelMatrix.source == .stereoIdentity)
        #expect(result.sourceFrameCount == 37)
        #expect(result.artifact.fileURL == outputURL)
        #expect(result.artifact.sampleRate == 44_100)
        #expect(result.artifact.channelCount == 2)
        #expect(result.artifact.frameCount == 37)
    }

    @Test
    func prepareWithResolvedMatrixUsesPersistedCoefficientsWithoutAutomaticReplacement() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appending(path: "input-exact-matrix.wav")
        let outputURL = directory.appending(path: "prepared-exact-matrix.wav")
        let left: [Float] = [0.1, 0.2, 0.3, 0.4]
        let right: [Float] = [-0.5, -0.6, -0.7, -0.8]
        try writeFloatWAV(at: inputURL, sampleRate: 44_100, channels: [left, right])

        let service = AudioInputConversionService(processingChunkFrameCount: 2)
        let inspection = try service.inspect(inputURL: inputURL)
        let automatic = try #require(inspection.matrixResolution.automaticMatrix)
        let persistedExactMatrix = StemInputChannelMatrix(
            source: automatic.source,
            inputLayout: automatic.inputLayout,
            coefficients: [0, 1, 1, 0]
        )

        let result = try await service.prepare(
            inputURL: inputURL,
            outputURL: outputURL,
            resolvedChannelMatrix: persistedExactMatrix
        )
        let outputSamples = try readAllSamples(from: AVAudioFile(forReading: outputURL))

        #expect(result.channelMatrix == persistedExactMatrix)
        #expect(outputSamples[0] == right)
        #expect(outputSamples[1] == left)
        #expect(result.channelMatrix.coefficients != automatic.coefficients)
    }

    @Test
    func resolvedMatrixRejectsChangedLayoutSourceDimensionsAndNonFiniteCoefficients() throws {
        let automatic = StemInputChannelMatrix(
            source: .stereoIdentity,
            inputLayout: StemInputLayoutIdentity(
                channelCount: 2,
                layoutTag: kAudioChannelLayoutTag_Stereo,
                channelBitmap: 0,
                channelDescriptions: []
            ),
            coefficients: [1, 0, 0, 1]
        )
        let inspection = StemInputInspection(
            inputURL: URL(filePath: "/tmp/input.wav"),
            sampleRate: 44_100,
            channelCount: 2,
            frameCount: 100,
            layoutIdentity: automatic.inputLayout,
            matrixResolution: .automatic(automatic)
        )

        let changedLayout = StemInputChannelMatrix(
            source: .stereoIdentity,
            inputLayout: StemInputLayoutIdentity(
                channelCount: 2,
                layoutTag: kAudioChannelLayoutTag_Stereo,
                channelBitmap: 1,
                channelDescriptions: []
            ),
            coefficients: automatic.coefficients
        )
        #expect(throws: StemInputConversionError.resolvedMixMatrixLayoutMismatch) {
            try AudioInputConversionService.validateResolvedChannelMatrix(
                changedLayout,
                against: inspection
            )
        }

        let changedSource = StemInputChannelMatrix(
            source: .monoDuplication,
            inputLayout: automatic.inputLayout,
            coefficients: automatic.coefficients
        )
        #expect(
            throws: StemInputConversionError.resolvedMixMatrixSourceMismatch(
                expected: .stereoIdentity,
                actual: .monoDuplication
            )
        ) {
            try AudioInputConversionService.validateResolvedChannelMatrix(
                changedSource,
                against: inspection
            )
        }

        let wrongDimensions = StemInputChannelMatrix(
            source: .stereoIdentity,
            inputLayout: automatic.inputLayout,
            coefficients: [1, 0, 0]
        )
        #expect(
            throws: StemInputConversionError.invalidMatrixCoefficientCount(
                expected: 4,
                actual: 3
            )
        ) {
            try AudioInputConversionService.validateResolvedChannelMatrix(
                wrongDimensions,
                against: inspection
            )
        }

        let nonFinite = StemInputChannelMatrix(
            source: .stereoIdentity,
            inputLayout: automatic.inputLayout,
            coefficients: [1, 0, .infinity, 1]
        )
        #expect(throws: StemInputConversionError.nonFiniteMatrixCoefficient(index: 2)) {
            try AudioInputConversionService.validateResolvedChannelMatrix(
                nonFinite,
                against: inspection
            )
        }
    }

    @Test
    func prepare48000Uses44100StereoMasteringSRCWithExpectedDuration() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appending(path: "input-48000.wav")
        let outputURL = directory.appending(path: "prepared-44100.wav")
        let sourceFrameCount = 4_800
        let left: [Float] = (0..<sourceFrameCount).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / 48_000) * 0.25)
        }
        let right: [Float] = (0..<sourceFrameCount).map { index in
            Float(sin(2 * Double.pi * 660 * Double(index) / 48_000) * 0.2)
        }
        try writeFloatWAV(
            at: inputURL,
            sampleRate: 48_000,
            channels: [left, right]
        )

        let result = try await AudioInputConversionService(
            processingChunkFrameCount: 127
        ).prepare(inputURL: inputURL, outputURL: outputURL)
        let outputFile = try AVAudioFile(forReading: outputURL)
        let outputSamples = try readAllSamples(from: outputFile)
        let expectedFrameCount = Int64(
            (Double(sourceFrameCount) * 44_100 / 48_000).rounded()
        )

        #expect(outputFile.processingFormat.sampleRate == 44_100)
        #expect(outputFile.processingFormat.channelCount == 2)
        #expect(outputFile.length == expectedFrameCount)
        #expect(result.artifact.frameCount == Int(expectedFrameCount))
        #expect(result.sourceFrameCount == Int64(sourceFrameCount))
        #expect(outputSamples.count == 2)
        #expect(outputSamples.allSatisfy { channel in channel.allSatisfy(\.isFinite) })
        #expect(outputSamples.flatMap { $0 }.contains { abs($0) > 0.01 })
    }

    @Test
    func nonFiniteInputRemovesPartialOutputAndPreservesExistingDestination() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appending(path: "input-with-nan.wav")
        let outputURL = directory.appending(path: "existing-output.wav")
        var left = [Float](repeating: 0.125, count: 12)
        left[7] = .nan
        let right = [Float](repeating: -0.25, count: 12)
        try writeFloatWAV(
            at: inputURL,
            sampleRate: 44_100,
            channels: [left, right]
        )
        let persistedInput = try readAllSamples(from: AVAudioFile(forReading: inputURL))
        #expect(persistedInput[0][7].isNaN)

        let existingData = Data("existing-user-output".utf8)
        try existingData.write(to: outputURL)

        do {
            _ = try await AudioInputConversionService(
                processingChunkFrameCount: 4
            ).prepare(inputURL: inputURL, outputURL: outputURL)
            Issue.record("NaNを含む入力が拒否されませんでした")
        } catch let error as StemInputConversionError {
            #expect(error == .nonFiniteInputSample(channel: 0, frame: 7))
        } catch {
            Issue.record("想定外のエラー型です: \(error)")
        }

        #expect(try Data(contentsOf: outputURL) == existingData)
        let partials = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { url in
            url.lastPathComponent.hasPrefix(".\(outputURL.lastPathComponent).")
                && url.lastPathComponent.hasSuffix(".partial.wav")
        }
        #expect(partials.isEmpty)
    }

    @Test
    func successfulPreparationNeverReplacesAnExistingDestination() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appending(path: "input.wav")
        let outputURL = directory.appending(path: "existing-output.wav")
        try writeFloatWAV(
            at: inputURL,
            sampleRate: 44_100,
            channels: [
                [0.1, 0.2, 0.3, 0.4],
                [-0.1, -0.2, -0.3, -0.4],
            ]
        )
        let existingData = Data("verified-completed-artifact".utf8)
        try existingData.write(to: outputURL)

        await #expect(throws: StemInputConversionError.outputAlreadyExists(outputURL.path)) {
            _ = try await AudioInputConversionService(
                processingChunkFrameCount: 2
            ).prepare(inputURL: inputURL, outputURL: outputURL)
        }

        #expect(try Data(contentsOf: outputURL) == existingData)
        let partials = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { url in
            url.lastPathComponent.hasPrefix(".\(outputURL.lastPathComponent).")
                && url.lastPathComponent.hasSuffix(".partial.wav")
        }
        #expect(partials.isEmpty)
    }

    private func makeBuffer(
        sampleRate: Double,
        channels: [[Float]]
    ) throws -> AVAudioPCMBuffer {
        let frameCount = try #require(channels.first?.count)
        #expect(channels.allSatisfy { $0.count == frameCount })
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: AVAudioChannelCount(channels.count),
                interleaved: false
            )
        )
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        let pointers = try #require(buffer.floatChannelData)
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for channelIndex in channels.indices {
            for frameIndex in channels[channelIndex].indices {
                pointers[channelIndex][frameIndex] = channels[channelIndex][frameIndex]
            }
        }
        return buffer
    }

    private func samples(from buffer: AVAudioPCMBuffer) throws -> [[Float]] {
        let pointers = try #require(buffer.floatChannelData)
        let frameCount = Int(buffer.frameLength)
        return (0..<Int(buffer.format.channelCount)).map { channelIndex in
            Array(UnsafeBufferPointer(start: pointers[channelIndex], count: frameCount))
        }
    }

    private func writeFloatWAV(
        at url: URL,
        sampleRate: Double,
        channels: [[Float]]
    ) throws {
        let buffer = try makeBuffer(sampleRate: sampleRate, channels: channels)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels.count,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    private func readAllSamples(from file: AVAudioFile) throws -> [[Float]] {
        guard file.length <= Int64(AVAudioFrameCount.max) else {
            throw StemInputConversionTestSupportError.fixtureTooLarge
        }
        let buffer = try #require(
            AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            )
        )
        try file.read(into: buffer)
        return try samples(from: buffer)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(
            path: "VelouraStemInputTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension StemInputMatrixResolution {
    var automaticMatrix: StemInputChannelMatrix? {
        guard case let .automatic(matrix) = self else { return nil }
        return matrix
    }

    var unsupportedIdentity: StemInputLayoutIdentity? {
        guard case let .unsupported(identity) = self else { return nil }
        return identity
    }
}

private enum StemInputConversionTestSupportError: Error {
    case fixtureTooLarge
}
