import AudioToolbox
import AVFoundation
import Darwin
import Foundation

struct StemInputChannelDescriptionIdentity: Equatable, Sendable {
    let label: UInt32
    let flags: UInt32
    let coordinates: [Float]
}

struct StemInputLayoutIdentity: Equatable, Sendable {
    let channelCount: Int
    let layoutTag: UInt32
    let channelBitmap: UInt32
    let channelDescriptions: [StemInputChannelDescriptionIdentity]
}

enum StemInputChannelMatrixSource: String, Equatable, Sendable {
    case monoDuplication
    case stereoIdentity
    case coreAudioStandardLayout
}

struct StemInputChannelMatrix: Equatable, Sendable {
    static let outputChannelCount = 2

    let source: StemInputChannelMatrixSource
    let inputLayout: StemInputLayoutIdentity
    /// Input-major coefficients: input channel rows, stereo output columns.
    let coefficients: [Float]

    var inputChannelCount: Int { inputLayout.channelCount }
    var outputChannelCount: Int { Self.outputChannelCount }
}

enum StemInputMatrixResolution: Equatable, Sendable {
    case automatic(StemInputChannelMatrix)
    case unsupported(StemInputLayoutIdentity)
}

struct StemInputInspection: Equatable, Sendable {
    let inputURL: URL
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int64
    let layoutIdentity: StemInputLayoutIdentity
    let matrixResolution: StemInputMatrixResolution
}

struct StemInputPreparedResult: Equatable, Sendable {
    let artifact: StemAudioArtifact
    let channelMatrix: StemInputChannelMatrix
    let sourceFrameCount: Int64
}

enum StemInputConversionError: LocalizedError, Equatable, Sendable {
    case invalidSampleRate(Double)
    case invalidChannelCount(Int)
    case emptyInput
    case sourceFrameCountOverflow
    case unsupportedProcessingFormat
    case channelLayoutCountMismatch(expected: Int, actual: Int)
    case unsupportedChannelLayout(StemInputLayoutIdentity)
    case resolvedMixMatrixLayoutMismatch
    case resolvedMixMatrixSourceMismatch(
        expected: StemInputChannelMatrixSource,
        actual: StemInputChannelMatrixSource
    )
    case invalidMatrixCoefficientCount(expected: Int, actual: Int)
    case nonFiniteMatrixCoefficient(index: Int)
    case nonFiniteInputSample(channel: Int, frame: Int64)
    case nonFiniteMixedSample(channel: Int, frame: Int64)
    case unableToCreateAudioBuffer
    case unableToCreateSampleRateConverter
    case sampleRateConversionFailed(String)
    case outputValidationFailed(String)
    case outputAlreadyExists(String)
    case atomicCommitFailed(code: Int32)

    var errorDescription: String? {
        switch self {
        case let .invalidSampleRate(sampleRate):
            "入力サンプルレートが不正です（\(sampleRate) Hz）。"
        case let .invalidChannelCount(channelCount):
            "入力チャンネル数が不正です（\(channelCount) ch）。"
        case .emptyInput:
            "入力音声に処理できるフレームがありません。"
        case .sourceFrameCountOverflow:
            "入力音声が長すぎるため、安全にフレーム数を扱えません。"
        case .unsupportedProcessingFormat:
            "入力音声を32-bit floatの非インターリーブ形式として読み取れません。"
        case let .channelLayoutCountMismatch(expected, actual):
            "チャンネルレイアウトのチャンネル数が一致しません（音声: \(expected)、レイアウト: \(actual)）。"
        case .unsupportedChannelLayout:
            "この音源はチャンネル構成を確認できないため読み込めません。標準的なチャンネル構成で書き出した音源を使用してください。"
        case .resolvedMixMatrixLayoutMismatch:
            "保存済み変換行列が現在の入力チャンネルレイアウトと一致しません。"
        case let .resolvedMixMatrixSourceMismatch(expected, actual):
            "保存済み変換行列の決定元が現在の入力契約と一致しません（期待: \(expected.rawValue)、実際: \(actual.rawValue)）。"
        case let .invalidMatrixCoefficientCount(expected, actual):
            "変換行列の係数数が不正です（必要: \(expected)、実際: \(actual)）。"
        case let .nonFiniteMatrixCoefficient(index):
            "変換行列の係数 \(index) が有限値ではありません。"
        case let .nonFiniteInputSample(channel, frame):
            "入力音声に有限値ではないサンプルがあります（ch \(channel + 1)、frame \(frame)）。"
        case let .nonFiniteMixedSample(channel, frame):
            "ステレオ変換結果に有限値ではないサンプルがあります（ch \(channel + 1)、frame \(frame)）。"
        case .unableToCreateAudioBuffer:
            "音声変換用バッファを作成できません。"
        case .unableToCreateSampleRateConverter:
            "44.1 kHz変換器を作成できません。"
        case let .sampleRateConversionFailed(message):
            "44.1 kHz変換に失敗しました（\(message)）。"
        case let .outputValidationFailed(message):
            "変換済み入力音声の検証に失敗しました（\(message)）。"
        case let .outputAlreadyExists(path):
            "変換済み入力音声の確定先に既存の成果物があります（\(path)）。"
        case let .atomicCommitFailed(code):
            "変換済み入力音声を確定できませんでした（errno \(code)）。"
        }
    }
}

struct AudioInputConversionService: Sendable {
    static let targetSampleRate = 44_100.0

    private let processingChunkFrameCount: AVAudioFrameCount

    init(processingChunkFrameCount: AVAudioFrameCount = 16_384) {
        self.processingChunkFrameCount = max(processingChunkFrameCount, 1)
    }

    func inspect(inputURL: URL) throws -> StemInputInspection {
        let file = try AVAudioFile(forReading: inputURL)
        return try inspection(inputURL: inputURL, file: file)
    }

    /// Resolves the exact matrix that must be persisted before a run starts.
    func resolveChannelMatrix(inputURL: URL) throws -> StemInputChannelMatrix {
        let inspection = try inspect(inputURL: inputURL)
        return try Self.selectChannelMatrix(resolution: inspection.matrixResolution)
    }

    private func inspection(inputURL: URL, file: AVAudioFile) throws -> StemInputInspection {
        let processingFormat = file.processingFormat
        let channelCount = Int(processingFormat.channelCount)
        try Self.validateBasicFormat(
            sampleRate: processingFormat.sampleRate,
            channelCount: channelCount,
            frameCount: file.length
        )

        let layout = file.fileFormat.channelLayout ?? processingFormat.channelLayout
        let resolution = try Self.resolveChannelMatrix(
            channelCount: channelCount,
            channelLayout: layout
        )
        let identity: StemInputLayoutIdentity
        switch resolution {
        case let .automatic(matrix):
            identity = matrix.inputLayout
        case let .unsupported(requiredIdentity):
            identity = requiredIdentity
        }

        return StemInputInspection(
            inputURL: inputURL,
            sampleRate: processingFormat.sampleRate,
            channelCount: channelCount,
            frameCount: file.length,
            layoutIdentity: identity,
            matrixResolution: resolution
        )
    }

    func prepare(
        inputURL: URL,
        outputURL: URL,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> StemInputPreparedResult {
        try Task.checkCancellation()
        let sourceFile = try AVAudioFile(forReading: inputURL)
        let inspection = try inspection(inputURL: inputURL, file: sourceFile)
        let matrix = try Self.selectChannelMatrix(resolution: inspection.matrixResolution)

        return try await prepare(
            sourceFile: sourceFile,
            inspection: inspection,
            outputURL: outputURL,
            matrix: matrix,
            progress: progress
        )
    }

    /// Prepares input using the exact matrix persisted at run start.
    ///
    /// The current file is inspected again only to reject a changed layout or invalid source
    /// contract. Automatically derived coefficients are never substituted for the saved values.
    func prepare(
        inputURL: URL,
        outputURL: URL,
        resolvedChannelMatrix: StemInputChannelMatrix,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> StemInputPreparedResult {
        try Task.checkCancellation()
        let sourceFile = try AVAudioFile(forReading: inputURL)
        let inspection = try inspection(inputURL: inputURL, file: sourceFile)
        try Self.validateResolvedChannelMatrix(
            resolvedChannelMatrix,
            against: inspection
        )
        return try await prepare(
            sourceFile: sourceFile,
            inspection: inspection,
            outputURL: outputURL,
            matrix: resolvedChannelMatrix,
            progress: progress
        )
    }

    private func prepare(
        sourceFile: AVAudioFile,
        inspection: StemInputInspection,
        outputURL: URL,
        matrix: StemInputChannelMatrix,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> StemInputPreparedResult {

        let parentURL = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let temporaryURL = parentURL
            .appending(path: ".\(outputURL.lastPathComponent).\(UUID().uuidString).partial.wav")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        try validateReadableProcessingFormat(sourceFile.processingFormat, expectedChannels: matrix.inputChannelCount)
        do {
            let outputFile = try makeOutputFile(at: temporaryURL)
            progress?(0)
            if abs(sourceFile.processingFormat.sampleRate - Self.targetSampleRate) < 0.000_001 {
                try await writeWithoutSampleRateConversion(
                    sourceFile: sourceFile,
                    outputFile: outputFile,
                    matrix: matrix,
                    sourceFrameCount: inspection.frameCount,
                    progress: progress
                )
            } else {
                try await writeWithSampleRateConversion(
                    sourceFile: sourceFile,
                    outputFile: outputFile,
                    matrix: matrix,
                    sourceFrameCount: inspection.frameCount,
                    progress: progress
                )
            }
        }

        try Task.checkCancellation()
        let validatedFrameCount = try validateOutputFile(at: temporaryURL)
        guard validatedFrameCount <= Int64(Int.max) else {
            throw StemInputConversionError.sourceFrameCountOverflow
        }
        let commitStatus = temporaryURL.path.withCString { temporaryPath in
            outputURL.path.withCString { outputPath in
                Darwin.renameatx_np(
                    AT_FDCWD,
                    temporaryPath,
                    AT_FDCWD,
                    outputPath,
                    UInt32(RENAME_EXCL)
                )
            }
        }
        guard commitStatus == 0 else {
            if errno == EEXIST {
                throw StemInputConversionError.outputAlreadyExists(outputURL.path)
            }
            throw StemInputConversionError.atomicCommitFailed(code: errno)
        }
        progress?(1)

        return StemInputPreparedResult(
            artifact: StemAudioArtifact(
                id: "input-44100",
                kind: .input44100,
                fileURL: outputURL,
                sampleRate: Self.targetSampleRate,
                channelCount: StemInputChannelMatrix.outputChannelCount,
                frameCount: Int(validatedFrameCount)
            ),
            channelMatrix: matrix,
            sourceFrameCount: inspection.frameCount
        )
    }

    static func resolveChannelMatrix(
        channelCount: Int,
        channelLayout: AVAudioChannelLayout?
    ) throws -> StemInputMatrixResolution {
        guard channelCount > 0 else {
            throw StemInputConversionError.invalidChannelCount(channelCount)
        }
        if let channelLayout, Int(channelLayout.channelCount) != channelCount {
            throw StemInputConversionError.channelLayoutCountMismatch(
                expected: channelCount,
                actual: Int(channelLayout.channelCount)
            )
        }

        // An explicit unknown/discrete layout does not become a known mono or
        // stereo layout merely because it happens to contain one or two
        // channels. The channel roles still have no defined meaning, so the
        // app must reject the source instead of guessing or asking for expert input.
        if let channelLayout, isUnknownOrDiscrete(channelLayout: channelLayout) {
            return .unsupported(
                layoutIdentity(
                    channelCount: channelCount,
                    channelLayout: channelLayout,
                    fallbackTag: kAudioChannelLayoutTag_Unknown | UInt32(channelCount)
                )
            )
        }

        if channelCount == 1 {
            let identity = layoutIdentity(
                channelCount: channelCount,
                channelLayout: channelLayout,
                fallbackTag: kAudioChannelLayoutTag_Mono
            )
            return .automatic(
                StemInputChannelMatrix(
                    source: .monoDuplication,
                    inputLayout: identity,
                    coefficients: [1, 1]
                )
            )
        }

        if channelCount == 2 {
            let identity = layoutIdentity(
                channelCount: channelCount,
                channelLayout: channelLayout,
                fallbackTag: kAudioChannelLayoutTag_Stereo
            )
            return .automatic(
                StemInputChannelMatrix(
                    source: .stereoIdentity,
                    inputLayout: identity,
                    coefficients: [1, 0, 0, 1]
                )
            )
        }

        let identity = layoutIdentity(
            channelCount: channelCount,
            channelLayout: channelLayout,
            fallbackTag: kAudioChannelLayoutTag_Unknown | UInt32(channelCount)
        )
        guard let channelLayout else {
            return .unsupported(identity)
        }
        guard Int(channelLayout.channelCount) == channelCount else {
            throw StemInputConversionError.channelLayoutCountMismatch(
                expected: channelCount,
                actual: Int(channelLayout.channelCount)
            )
        }
        guard !isUnknownOrDiscrete(channelLayout: channelLayout) else {
            return .unsupported(identity)
        }
        guard let coefficients = coreAudioStereoMatrix(
            inputLayout: channelLayout,
            inputChannelCount: channelCount
        ) else {
            return .unsupported(identity)
        }

        return .automatic(
            StemInputChannelMatrix(
                source: .coreAudioStandardLayout,
                inputLayout: identity,
                coefficients: coefficients
            )
        )
    }

    static func selectChannelMatrix(
        resolution: StemInputMatrixResolution
    ) throws -> StemInputChannelMatrix {
        switch resolution {
        case let .automatic(matrix):
            try validateMatrixCoefficients(
                matrix.coefficients,
                inputChannelCount: matrix.inputChannelCount
            )
            return matrix
        case let .unsupported(identity):
            throw StemInputConversionError.unsupportedChannelLayout(identity)
        }
    }

    static func validateResolvedChannelMatrix(
        _ matrix: StemInputChannelMatrix,
        against inspection: StemInputInspection
    ) throws {
        guard matrix.inputLayout == inspection.layoutIdentity,
              matrix.inputChannelCount == inspection.channelCount else {
            throw StemInputConversionError.resolvedMixMatrixLayoutMismatch
        }
        let expectedSource: StemInputChannelMatrixSource
        switch inspection.matrixResolution {
        case .automatic(let automatic):
            expectedSource = automatic.source
        case let .unsupported(identity):
            throw StemInputConversionError.unsupportedChannelLayout(identity)
        }
        guard matrix.source == expectedSource else {
            throw StemInputConversionError.resolvedMixMatrixSourceMismatch(
                expected: expectedSource,
                actual: matrix.source
            )
        }
        try validateMatrixCoefficients(
            matrix.coefficients,
            inputChannelCount: matrix.inputChannelCount
        )
    }

    static func apply(
        matrix: StemInputChannelMatrix,
        to inputBuffer: AVAudioPCMBuffer,
        sourceFrameOffset: Int64 = 0
    ) throws -> AVAudioPCMBuffer {
        guard
            inputBuffer.format.commonFormat == .pcmFormatFloat32,
            !inputBuffer.format.isInterleaved,
            Int(inputBuffer.format.channelCount) == matrix.inputChannelCount,
            let inputChannels = inputBuffer.floatChannelData,
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputBuffer.format.sampleRate,
                channels: AVAudioChannelCount(StemInputChannelMatrix.outputChannelCount),
                interleaved: false
            ),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: inputBuffer.frameLength
            ),
            let outputChannels = outputBuffer.floatChannelData
        else {
            throw StemInputConversionError.unableToCreateAudioBuffer
        }
        try validateMatrixCoefficients(
            matrix.coefficients,
            inputChannelCount: matrix.inputChannelCount
        )

        outputBuffer.frameLength = inputBuffer.frameLength
        let frameCount = Int(inputBuffer.frameLength)
        for outputChannel in 0..<StemInputChannelMatrix.outputChannelCount {
            outputChannels[outputChannel].initialize(repeating: 0, count: frameCount)
        }

        for inputChannel in 0..<matrix.inputChannelCount {
            let source = inputChannels[inputChannel]
            let leftCoefficient = matrix.coefficients[(inputChannel * 2)]
            let rightCoefficient = matrix.coefficients[(inputChannel * 2) + 1]
            for frame in 0..<frameCount {
                let inputSample = source[frame]
                guard inputSample.isFinite else {
                    throw StemInputConversionError.nonFiniteInputSample(
                        channel: inputChannel,
                        frame: sourceFrameOffset + Int64(frame)
                    )
                }
                outputChannels[0][frame] += inputSample * leftCoefficient
                outputChannels[1][frame] += inputSample * rightCoefficient
            }
        }

        for outputChannel in 0..<StemInputChannelMatrix.outputChannelCount {
            for frame in 0..<frameCount where !outputChannels[outputChannel][frame].isFinite {
                throw StemInputConversionError.nonFiniteMixedSample(
                    channel: outputChannel,
                    frame: sourceFrameOffset + Int64(frame)
                )
            }
        }
        return outputBuffer
    }

    private func writeWithoutSampleRateConversion(
        sourceFile: AVAudioFile,
        outputFile: AVAudioFile,
        matrix: StemInputChannelMatrix,
        sourceFrameCount: Int64,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        var processedFrames: Int64 = 0
        while processedFrames < sourceFrameCount {
            try Task.checkCancellation()
            let remaining = sourceFrameCount - processedFrames
            let requested = AVAudioFrameCount(min(Int64(processingChunkFrameCount), remaining))
            guard let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFile.processingFormat,
                frameCapacity: requested
            ) else {
                throw StemInputConversionError.unableToCreateAudioBuffer
            }
            try sourceFile.read(into: sourceBuffer, frameCount: requested)
            guard sourceBuffer.frameLength > 0 else { break }
            let mixed = try Self.apply(
                matrix: matrix,
                to: sourceBuffer,
                sourceFrameOffset: processedFrames
            )
            try outputFile.write(from: mixed)
            processedFrames += Int64(sourceBuffer.frameLength)
            progress?(min(Double(processedFrames) / Double(sourceFrameCount), 0.99))
            await Task.yield()
        }
        guard processedFrames == sourceFrameCount else {
            throw StemInputConversionError.outputValidationFailed(
                "入力フレーム数と読み取りフレーム数が一致しません"
            )
        }
    }

    private func writeWithSampleRateConversion(
        sourceFile: AVAudioFile,
        outputFile: AVAudioFile,
        matrix: StemInputChannelMatrix,
        sourceFrameCount: Int64,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        guard
            let converterInputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceFile.processingFormat.sampleRate,
                channels: AVAudioChannelCount(StemInputChannelMatrix.outputChannelCount),
                interleaved: false
            ),
            let converterOutputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Self.targetSampleRate,
                channels: AVAudioChannelCount(StemInputChannelMatrix.outputChannelCount),
                interleaved: false
            ),
            let converter = AVAudioConverter(from: converterInputFormat, to: converterOutputFormat)
        else {
            throw StemInputConversionError.unableToCreateSampleRateConverter
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering

        let ratio = Self.targetSampleRate / sourceFile.processingFormat.sampleRate
        let outputCapacity = AVAudioFrameCount(
            max(1, ceil(Double(processingChunkFrameCount) * ratio) + 256)
        )
        let inputState = StemInputConverterInputState(
            sourceFile: sourceFile,
            matrix: matrix,
            sourceFrameCount: sourceFrameCount,
            processingChunkFrameCount: processingChunkFrameCount
        )

        while true {
            try Task.checkCancellation()
            guard let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: converterOutputFormat,
                frameCapacity: outputCapacity
            ) else {
                throw StemInputConversionError.unableToCreateAudioBuffer
            }

            var conversionError: NSError?
            let status = converter.convert(
                to: outputBuffer,
                error: &conversionError
            ) { requestedPackets, inputStatus in
                inputState.provideInput(
                    requestedPackets: requestedPackets,
                    status: inputStatus
                )
            }

            if let deferredInputError = inputState.deferredError {
                throw deferredInputError
            }
            if let conversionError {
                throw StemInputConversionError.sampleRateConversionFailed(
                    conversionError.localizedDescription
                )
            }
            if outputBuffer.frameLength > 0 {
                try Self.validateFinite(buffer: outputBuffer, sourceFrameOffset: 0)
                try outputFile.write(from: outputBuffer)
            }
            progress?(min(Double(inputState.sourceFramesRead) / Double(sourceFrameCount), 0.99))

            switch status {
            case .error:
                throw StemInputConversionError.sampleRateConversionFailed("AVAudioConverter error")
            case .endOfStream:
                guard inputState.sourceFramesRead == sourceFrameCount else {
                    throw StemInputConversionError.outputValidationFailed(
                        "入力フレーム数と変換器へ渡したフレーム数が一致しません"
                    )
                }
                return
            case .haveData, .inputRanDry:
                break
            @unknown default:
                throw StemInputConversionError.sampleRateConversionFailed(
                    "未知のAVAudioConverter状態"
                )
            }
            await Task.yield()
        }
    }

    private func makeOutputFile(at url: URL) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: Self.targetSampleRate,
            AVNumberOfChannelsKey: StemInputChannelMatrix.outputChannelCount,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        return try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }

    private func validateOutputFile(at url: URL) throws -> Int64 {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw StemInputConversionError.outputValidationFailed(error.localizedDescription)
        }
        guard abs(file.processingFormat.sampleRate - Self.targetSampleRate) < 0.000_001 else {
            throw StemInputConversionError.outputValidationFailed("サンプルレートが44.1 kHzではありません")
        }
        guard file.processingFormat.channelCount == StemInputChannelMatrix.outputChannelCount else {
            throw StemInputConversionError.outputValidationFailed("出力がステレオではありません")
        }
        guard file.length > 0 else {
            throw StemInputConversionError.outputValidationFailed("出力フレームがありません")
        }

        var validatedFrames: Int64 = 0
        while validatedFrames < file.length {
            let remaining = file.length - validatedFrames
            let requested = AVAudioFrameCount(min(Int64(processingChunkFrameCount), remaining))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: requested
            ) else {
                throw StemInputConversionError.unableToCreateAudioBuffer
            }
            do {
                try file.read(into: buffer, frameCount: requested)
            } catch {
                throw StemInputConversionError.outputValidationFailed(error.localizedDescription)
            }
            guard buffer.frameLength > 0 else {
                throw StemInputConversionError.outputValidationFailed("出力を末尾まで再読込できません")
            }
            do {
                try Self.validateFinite(buffer: buffer, sourceFrameOffset: validatedFrames)
            } catch {
                throw StemInputConversionError.outputValidationFailed(error.localizedDescription)
            }
            validatedFrames += Int64(buffer.frameLength)
        }
        guard validatedFrames == file.length else {
            throw StemInputConversionError.outputValidationFailed("出力フレーム数が再読込時に変化しました")
        }
        return file.length
    }

    private func validateReadableProcessingFormat(
        _ format: AVAudioFormat,
        expectedChannels: Int
    ) throws {
        guard format.sampleRate.isFinite, format.sampleRate > 0 else {
            throw StemInputConversionError.invalidSampleRate(format.sampleRate)
        }
        guard Int(format.channelCount) == expectedChannels else {
            throw StemInputConversionError.channelLayoutCountMismatch(
                expected: expectedChannels,
                actual: Int(format.channelCount)
            )
        }
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
            throw StemInputConversionError.unsupportedProcessingFormat
        }
    }

    private static func validateBasicFormat(
        sampleRate: Double,
        channelCount: Int,
        frameCount: AVAudioFramePosition
    ) throws {
        guard sampleRate.isFinite, sampleRate > 0 else {
            throw StemInputConversionError.invalidSampleRate(sampleRate)
        }
        guard channelCount > 0 else {
            throw StemInputConversionError.invalidChannelCount(channelCount)
        }
        guard frameCount > 0 else {
            throw StemInputConversionError.emptyInput
        }
    }

    private static func validateMatrixCoefficients(
        _ coefficients: [Float],
        inputChannelCount: Int
    ) throws {
        let expected = inputChannelCount * StemInputChannelMatrix.outputChannelCount
        guard coefficients.count == expected else {
            throw StemInputConversionError.invalidMatrixCoefficientCount(
                expected: expected,
                actual: coefficients.count
            )
        }
        if let index = coefficients.firstIndex(where: { !$0.isFinite }) {
            throw StemInputConversionError.nonFiniteMatrixCoefficient(index: index)
        }
    }

    private static func validateFinite(
        buffer: AVAudioPCMBuffer,
        sourceFrameOffset: Int64
    ) throws {
        guard
            buffer.format.commonFormat == .pcmFormatFloat32,
            !buffer.format.isInterleaved,
            let channels = buffer.floatChannelData
        else {
            throw StemInputConversionError.unsupportedProcessingFormat
        }
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) where !channels[channel][frame].isFinite {
                throw StemInputConversionError.nonFiniteMixedSample(
                    channel: channel,
                    frame: sourceFrameOffset + Int64(frame)
                )
            }
        }
    }

    private static func layoutIdentity(
        channelCount: Int,
        channelLayout: AVAudioChannelLayout?,
        fallbackTag: AudioChannelLayoutTag
    ) -> StemInputLayoutIdentity {
        guard let channelLayout else {
            return StemInputLayoutIdentity(
                channelCount: channelCount,
                layoutTag: fallbackTag,
                channelBitmap: 0,
                channelDescriptions: []
            )
        }
        let layout = channelLayout.layout.pointee
        let descriptions = channelDescriptions(in: channelLayout).map { description in
            StemInputChannelDescriptionIdentity(
                label: description.mChannelLabel,
                flags: description.mChannelFlags.rawValue,
                coordinates: [
                    description.mCoordinates.0,
                    description.mCoordinates.1,
                    description.mCoordinates.2
                ]
            )
        }
        return StemInputLayoutIdentity(
            channelCount: channelCount,
            layoutTag: layout.mChannelLayoutTag,
            channelBitmap: layout.mChannelBitmap.rawValue,
            channelDescriptions: descriptions
        )
    }

    private static func isUnknownOrDiscrete(channelLayout: AVAudioChannelLayout) -> Bool {
        let layout = channelLayout.layout.pointee
        let tagFamily = layout.mChannelLayoutTag & 0xFFFF_0000
        let unknownFamily = kAudioChannelLayoutTag_Unknown & 0xFFFF_0000
        let discreteFamily = kAudioChannelLayoutTag_DiscreteInOrder & 0xFFFF_0000
        if tagFamily == unknownFamily || tagFamily == discreteFamily {
            return true
        }
        return channelDescriptions(in: channelLayout).contains { description in
            let label = description.mChannelLabel
            return label == kAudioChannelLabel_Unknown || label >= kAudioChannelLabel_Discrete_0
        }
    }

    private static func channelDescriptions(
        in channelLayout: AVAudioChannelLayout
    ) -> [AudioChannelDescription] {
        let count = Int(channelLayout.layout.pointee.mNumberChannelDescriptions)
        guard count > 0 else { return [] }
        guard let offset = MemoryLayout<AudioChannelLayout>.offset(
            of: \AudioChannelLayout.mChannelDescriptions
        ) else {
            return []
        }
        let descriptions = UnsafeRawPointer(channelLayout.layout)
            .advanced(by: offset)
            .assumingMemoryBound(to: AudioChannelDescription.self)
        return Array(UnsafeBufferPointer(start: descriptions, count: count))
    }

    private static func coreAudioStereoMatrix(
        inputLayout: AVAudioChannelLayout,
        inputChannelCount: Int
    ) -> [Float]? {
        guard let stereoLayout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo) else {
            return nil
        }
        var layoutPointers = [inputLayout.layout, stereoLayout.layout]
        var coefficients = [Float](
            repeating: 0,
            count: inputChannelCount * StemInputChannelMatrix.outputChannelCount
        )
        var outputSize = UInt32(coefficients.count * MemoryLayout<Float>.size)
        let status = layoutPointers.withUnsafeMutableBufferPointer { pointerBuffer in
            coefficients.withUnsafeMutableBytes { coefficientBytes in
                AudioFormatGetProperty(
                    kAudioFormatProperty_MatrixMixMap,
                    UInt32(pointerBuffer.count * MemoryLayout<UnsafePointer<AudioChannelLayout>>.size),
                    pointerBuffer.baseAddress,
                    &outputSize,
                    coefficientBytes.baseAddress
                )
            }
        }
        guard
            status == noErr,
            outputSize == UInt32(coefficients.count * MemoryLayout<Float>.size),
            coefficients.allSatisfy(\.isFinite)
        else {
            return nil
        }
        return coefficients
    }

}

private final class StemInputConverterInputState: @unchecked Sendable {
    private let sourceFile: AVAudioFile
    private let matrix: StemInputChannelMatrix
    private let sourceFrameCount: Int64
    private let processingChunkFrameCount: AVAudioFrameCount

    private(set) var sourceFramesRead: Int64 = 0
    private(set) var deferredError: Error?
    private var reachedEndOfInput = false

    init(
        sourceFile: AVAudioFile,
        matrix: StemInputChannelMatrix,
        sourceFrameCount: Int64,
        processingChunkFrameCount: AVAudioFrameCount
    ) {
        self.sourceFile = sourceFile
        self.matrix = matrix
        self.sourceFrameCount = sourceFrameCount
        self.processingChunkFrameCount = processingChunkFrameCount
    }

    func provideInput(
        requestedPackets: AVAudioPacketCount,
        status: UnsafeMutablePointer<AVAudioConverterInputStatus>
    ) -> AVAudioBuffer? {
        if deferredError != nil || reachedEndOfInput {
            status.pointee = .endOfStream
            return nil
        }
        if Task.isCancelled {
            deferredError = CancellationError()
            status.pointee = .endOfStream
            return nil
        }

        do {
            let remaining = sourceFrameCount - sourceFramesRead
            guard remaining > 0 else {
                reachedEndOfInput = true
                status.pointee = .endOfStream
                return nil
            }
            let requested = max(AVAudioFrameCount(requestedPackets), 1)
            let capacity = AVAudioFrameCount(
                min(Int64(min(requested, processingChunkFrameCount)), remaining)
            )
            guard let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFile.processingFormat,
                frameCapacity: capacity
            ) else {
                throw StemInputConversionError.unableToCreateAudioBuffer
            }
            try sourceFile.read(into: sourceBuffer, frameCount: capacity)
            guard sourceBuffer.frameLength > 0 else {
                reachedEndOfInput = true
                status.pointee = .endOfStream
                return nil
            }
            let mixed = try AudioInputConversionService.apply(
                matrix: matrix,
                to: sourceBuffer,
                sourceFrameOffset: sourceFramesRead
            )
            sourceFramesRead += Int64(sourceBuffer.frameLength)
            if sourceFramesRead >= sourceFrameCount {
                reachedEndOfInput = true
            }
            status.pointee = .haveData
            return mixed
        } catch {
            deferredError = error
            status.pointee = .endOfStream
            return nil
        }
    }
}
