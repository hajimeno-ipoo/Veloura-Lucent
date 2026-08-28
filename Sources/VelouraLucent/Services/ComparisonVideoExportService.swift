import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import SwiftUI

enum ComparisonVideoExportError: LocalizedError {
    case sourceUnavailable
    case incompatibleSources
    case invalidDuration
    case audioPreparationFailed
    case writerConfigurationFailed
    case videoFrameFailed
    case writingFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceUnavailable:
            "音源が更新されました"
        case .incompatibleSources:
            "選択した音源の長さが一致しません。"
        case .invalidDuration:
            "比較できる音声区間がありません。"
        case .audioPreparationFailed:
            "比較用の音声を準備できませんでした。"
        case .writerConfigurationFailed:
            "動画の書き出し設定を準備できませんでした。"
        case .videoFrameFailed:
            "動画の画面を生成できませんでした。"
        case .writingFailed(let detail):
            "動画を書き出せませんでした（\(detail)）。"
        }
    }
}

struct ComparisonVideoPreparedAudio: Sendable {
    let signal: AudioSignal
    let plan: ComparisonVideoPlan
}

struct ComparisonVideoExportRequest: Sendable {
    let first: ComparisonVideoSource
    let second: ComparisonVideoSource
    let startTime: TimeInterval
    let orientation: ComparisonVideoOrientation
    let format: ComparisonVideoFormat
    let destinationURL: URL
}

private final class ComparisonVideoWritingContext: @unchecked Sendable {
    let writer: AVAssetWriter
    let videoInput: AVAssetWriterInput
    let pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor
    let reader: AVAssetReader
    let readerOutput: AVAssetReaderTrackOutput
    let audioInput: AVAssetWriterInput

    init(
        writer: AVAssetWriter,
        videoInput: AVAssetWriterInput,
        pixelAdaptor: AVAssetWriterInputPixelBufferAdaptor,
        reader: AVAssetReader,
        readerOutput: AVAssetReaderTrackOutput,
        audioInput: AVAssetWriterInput
    ) {
        self.writer = writer
        self.videoInput = videoInput
        self.pixelAdaptor = pixelAdaptor
        self.reader = reader
        self.readerOutput = readerOutput
        self.audioInput = audioInput
    }
}

struct ComparisonVideoExportService {
    static let frameRate: Int32 = 30
    private static let waveformReadChunkFrameCount: AVAudioFrameCount = 16_384

    func writePreviewVideo(
        duration: TimeInterval,
        to destinationURL: URL
    ) async throws {
        guard duration.isFinite, duration > 0 else {
            throw ComparisonVideoExportError.invalidDuration
        }

        let size = CGSize(width: 16, height: 16)
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: .mov)
        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height),
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
            ]
        )
        guard writer.canAdd(videoInput) else {
            throw ComparisonVideoExportError.writerConfigurationFailed
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            throw ComparisonVideoExportError.writingFailed(
                writer.error?.localizedDescription ?? "プレビュー映像を開始できませんでした"
            )
        }
        defer {
            if writer.status == .writing {
                writer.cancelWriting()
            }
        }
        writer.startSession(atSourceTime: .zero)
        guard let pool = pixelAdaptor.pixelBufferPool else {
            throw ComparisonVideoExportError.writerConfigurationFailed
        }
        while !videoInput.isReadyForMoreMediaData {
            guard writer.status == .writing else {
                throw ComparisonVideoExportError.writingFailed(
                    writer.error?.localizedDescription ?? "プレビュー映像入力が停止しました"
                )
            }
            try await Task.sleep(for: .milliseconds(2))
        }
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else {
            throw ComparisonVideoExportError.videoFrameFailed
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(baseAddress, 0, CVPixelBufferGetDataSize(pixelBuffer))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        guard pixelAdaptor.append(pixelBuffer, withPresentationTime: .zero) else {
            throw ComparisonVideoExportError.writingFailed(
                writer.error?.localizedDescription ?? "プレビュー映像を追加できませんでした"
            )
        }
        videoInput.markAsFinished()
        writer.endSession(atSourceTime: CMTime(seconds: duration, preferredTimescale: 600))
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ComparisonVideoExportError.writingFailed(
                writer.error?.localizedDescription ?? "プレビュー映像を完了できませんでした"
            )
        }
    }

    func prepareAudio(
        first: ComparisonVideoSource,
        second: ComparisonVideoSource,
        startTime: TimeInterval
    ) throws -> ComparisonVideoPreparedAudio {
        try requireSource(first)
        try requireSource(second)
        let firstInfo = try AudioFileService.fileInfo(for: first.fileURL)
        let secondInfo = try AudioFileService.fileInfo(for: second.fileURL)
        guard abs(firstInfo.duration - secondInfo.duration)
            <= 1 / min(firstInfo.sampleRate, secondInfo.sampleRate) else {
            throw ComparisonVideoExportError.incompatibleSources
        }
        guard let plan = ComparisonVideoPlan.make(
            sourceDuration: firstInfo.duration,
            requestedStartTime: startTime
        ) else {
            throw ComparisonVideoExportError.invalidDuration
        }
        let firstSignal = try loadSelectedStereoAudio(
            from: first.fileURL,
            startTime: plan.sourceStartTime,
            duration: plan.sourceDuration
        )
        let loadedSecondSignal = try loadSelectedStereoAudio(
            from: second.fileURL,
            startTime: plan.sourceStartTime,
            duration: plan.sourceDuration
        )
        let secondSignal = try AudioSignalSampleRateConverter.convert(
            loadedSecondSignal,
            to: firstSignal.sampleRate
        )
        let output = try makeSequence(
            first: firstSignal,
            second: secondSignal,
            plan: plan
        )
        return ComparisonVideoPreparedAudio(
            signal: output,
            plan: plan
        )
    }

    func makeSelectionWaveform(
        for source: ComparisonVideoSource,
        bucketCount: Int
    ) throws -> [WaveformEnvelopeSample] {
        try requireSource(source)
        guard bucketCount > 0 else { return [] }

        let file = try AVAudioFile(forReading: source.fileURL)
        let format = file.processingFormat
        let frameCount = file.length
        guard format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved,
              frameCount > 0 else {
            throw ComparisonVideoExportError.audioPreparationFailed
        }
        let matrix = try channelMatrix(for: file)
        var minimums = Array(repeating: Float.greatestFiniteMagnitude, count: bucketCount)
        var maximums = Array(repeating: -Float.greatestFiniteMagnitude, count: bucketCount)
        var energies = Array(repeating: Double.zero, count: bucketCount)
        var sampleCounts = Array(repeating: 0, count: bucketCount)
        var processedFrames: AVAudioFramePosition = 0

        while processedFrames < frameCount {
            try Task.checkCancellation()
            let requested = AVAudioFrameCount(min(
                AVAudioFramePosition(Self.waveformReadChunkFrameCount),
                frameCount - processedFrames
            ))
            guard let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: requested
            ) else {
                throw ComparisonVideoExportError.audioPreparationFailed
            }
            try file.read(into: sourceBuffer, frameCount: requested)
            guard sourceBuffer.frameLength > 0 else { break }
            let stereoBuffer = try AudioInputConversionService.apply(
                matrix: matrix,
                to: sourceBuffer,
                sourceFrameOffset: processedFrames
            )
            guard let channels = stereoBuffer.floatChannelData else {
                throw ComparisonVideoExportError.audioPreparationFailed
            }
            for localFrame in 0..<Int(stereoBuffer.frameLength) {
                let absoluteFrame = processedFrames + AVAudioFramePosition(localFrame)
                let bucketIndex = min(
                    Int(absoluteFrame * AVAudioFramePosition(bucketCount) / frameCount),
                    bucketCount - 1
                )
                let sample = (channels[0][localFrame] + channels[1][localFrame]) * 0.5
                minimums[bucketIndex] = min(minimums[bucketIndex], sample)
                maximums[bucketIndex] = max(maximums[bucketIndex], sample)
                energies[bucketIndex] += Double(sample) * Double(sample)
                sampleCounts[bucketIndex] += 1
            }
            processedFrames += AVAudioFramePosition(sourceBuffer.frameLength)
        }
        guard processedFrames == frameCount else {
            throw ComparisonVideoExportError.audioPreparationFailed
        }

        return (0..<bucketCount).map { index in
            guard sampleCounts[index] > 0 else { return .zero }
            return WaveformEnvelopeSample(
                minimum: max(-1, min(1, minimums[index])),
                maximum: max(-1, min(1, maximums[index])),
                rms: min(1, Float(sqrt(energies[index] / Double(sampleCounts[index]))))
            )
        }
    }

    func writePreparedAudio(
        _ prepared: ComparisonVideoPreparedAudio,
        to destinationURL: URL
    ) throws {
        try AudioFileService.saveAudio(prepared.signal, to: destinationURL)
    }

    func export(_ request: ComparisonVideoExportRequest) async throws {
        let prepared = try prepareAudio(
            first: request.first,
            second: request.second,
            startTime: request.startTime
        )
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VelouraComparisonVideo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let audioURL = temporaryDirectory.appendingPathComponent("comparison.wav")
        try writePreparedAudio(prepared, to: audioURL)

        let pendingURL = temporaryDirectory
            .appendingPathComponent("pending")
            .appendingPathExtension(request.format.fileExtension)
        try await writeMovie(
            request: request,
            prepared: prepared,
            audioURL: audioURL,
            destinationURL: pendingURL
        )

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: request.destinationURL.path(percentEncoded: false)) {
            _ = try fileManager.replaceItemAt(request.destinationURL, withItemAt: pendingURL)
        } else {
            try fileManager.moveItem(at: pendingURL, to: request.destinationURL)
        }
    }

    private func requireSource(_ source: ComparisonVideoSource) throws {
        guard source.matchesCurrentFile else {
            throw ComparisonVideoExportError.sourceUnavailable
        }
    }

    private func makeSequence(
        first: AudioSignal,
        second: AudioSignal,
        plan: ComparisonVideoPlan
    ) throws -> AudioSignal {
        let sampleRate = first.sampleRate
        let sourceSignals = [first, second]
        var channels = Array(repeating: [Float](), count: first.channels.count)
        let expectedFrameCount = Int((plan.outputDuration * sampleRate).rounded())
        for channelIndex in channels.indices {
            channels[channelIndex].reserveCapacity(expectedFrameCount)
        }

        for segment in plan.segments {
            let signal = sourceSignals[segment.sourceIndex]
            let localStartTime = segment.sourceStartTime - plan.sourceStartTime
            let startFrame = min(
                max(Int((localStartTime * sampleRate).rounded()), 0),
                signal.frameCount
            )
            let requestedFrames = Int((segment.duration * sampleRate).rounded())
            let endFrame = min(startFrame + requestedFrames, signal.frameCount)
            guard endFrame > startFrame else {
                throw ComparisonVideoExportError.audioPreparationFailed
            }
            for channelIndex in channels.indices {
                channels[channelIndex].append(contentsOf: signal.channels[channelIndex][startFrame..<endFrame])
            }
        }
        guard channels.allSatisfy({ $0.count == channels[0].count }) else {
            throw ComparisonVideoExportError.audioPreparationFailed
        }
        return AudioSignal(channels: channels, sampleRate: sampleRate)
    }

    func loadSelectedStereoAudio(
        from url: URL,
        startTime: TimeInterval,
        duration: TimeInterval
    ) throws -> AudioSignal {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let startFrame = min(
            max(AVAudioFramePosition((startTime * format.sampleRate).rounded()), 0),
            file.length
        )
        let availableFrames = file.length - startFrame
        let requestedFrames = min(
            max(AVAudioFramePosition((duration * format.sampleRate).rounded()), 0),
            availableFrames
        )
        guard format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved,
              requestedFrames > 0,
              requestedFrames <= AVAudioFramePosition(Int.max) else {
            throw ComparisonVideoExportError.audioPreparationFailed
        }
        file.framePosition = startFrame
        let matrix = try channelMatrix(for: file)
        var channels = Array(repeating: [Float](), count: StemInputChannelMatrix.outputChannelCount)
        for channelIndex in channels.indices {
            channels[channelIndex].reserveCapacity(Int(requestedFrames))
        }
        var processedFrames: AVAudioFramePosition = 0

        while processedFrames < requestedFrames {
            try Task.checkCancellation()
            let requestedChunkFrames = AVAudioFrameCount(min(
                AVAudioFramePosition(Self.waveformReadChunkFrameCount),
                requestedFrames - processedFrames
            ))
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: requestedChunkFrames
            ) else {
                throw ComparisonVideoExportError.audioPreparationFailed
            }
            try file.read(into: buffer, frameCount: requestedChunkFrames)
            guard buffer.frameLength > 0 else { break }
            let stereoBuffer = try AudioInputConversionService.apply(
                matrix: matrix,
                to: buffer,
                sourceFrameOffset: startFrame + processedFrames
            )
            guard let channelData = stereoBuffer.floatChannelData else {
                throw ComparisonVideoExportError.audioPreparationFailed
            }
            let frameCount = Int(stereoBuffer.frameLength)
            for channelIndex in channels.indices {
                channels[channelIndex].append(contentsOf: UnsafeBufferPointer(
                    start: channelData[channelIndex],
                    count: frameCount
                ))
            }
            processedFrames += AVAudioFramePosition(buffer.frameLength)
        }
        guard processedFrames == requestedFrames else {
            throw ComparisonVideoExportError.audioPreparationFailed
        }
        return AudioSignal(channels: channels, sampleRate: format.sampleRate)
    }

    private func channelMatrix(for file: AVAudioFile) throws -> StemInputChannelMatrix {
        let channelCount = Int(file.processingFormat.channelCount)
        let channelLayout = file.fileFormat.channelLayout ?? file.processingFormat.channelLayout
        let resolution = try AudioInputConversionService.resolveChannelMatrix(
            channelCount: channelCount,
            channelLayout: channelLayout
        )
        return try AudioInputConversionService.selectChannelMatrix(resolution: resolution)
    }

    private func writeMovie(
        request: ComparisonVideoExportRequest,
        prepared: ComparisonVideoPreparedAudio,
        audioURL: URL,
        destinationURL: URL
    ) async throws {
        let fileType: AVFileType = request.format == .mp4 ? .mp4 : .mov
        let writer = try AVAssetWriter(outputURL: destinationURL, fileType: fileType)
        let size = request.orientation.pixelSize
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 12_000_000,
                AVVideoExpectedSourceFrameRateKey: Int(Self.frameRate),
            ],
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let pixelAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
        ]
        let pixelAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelAttributes
        )

        let audioAsset = AVURLAsset(url: audioURL)
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw ComparisonVideoExportError.audioPreparationFailed
        }
        let reader = try AVAssetReader(asset: audioAsset)
        let readerSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: prepared.signal.sampleRate,
            AVNumberOfChannelsKey: prepared.signal.channels.count,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: readerSettings)
        guard reader.canAdd(readerOutput) else {
            throw ComparisonVideoExportError.writerConfigurationFailed
        }
        reader.add(readerOutput)

        let audioInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: audioSettings(
                format: request.format,
                sampleRate: prepared.signal.sampleRate,
                channelCount: prepared.signal.channels.count
            )
        )
        audioInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else {
            throw ComparisonVideoExportError.writerConfigurationFailed
        }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.startWriting(), reader.startReading() else {
            throw ComparisonVideoExportError.writingFailed(
                writer.error?.localizedDescription ?? reader.error?.localizedDescription ?? "開始できませんでした"
            )
        }
        writer.startSession(atSourceTime: .zero)

        let context = ComparisonVideoWritingContext(
            writer: writer,
            videoInput: videoInput,
            pixelAdaptor: pixelAdaptor,
            reader: reader,
            readerOutput: readerOutput,
            audioInput: audioInput
        )

        async let videoResult: Void = appendVideoFrames(
            request: request,
            prepared: prepared,
            context: context
        )
        async let audioResult: Void = appendAudioSamples(
            context: context
        )
        _ = try await (videoResult, audioResult)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ComparisonVideoExportError.writingFailed(
                writer.error?.localizedDescription ?? "完了できませんでした"
            )
        }
    }

    private func appendVideoFrames(
        request: ComparisonVideoExportRequest,
        prepared: ComparisonVideoPreparedAudio,
        context: ComparisonVideoWritingContext
    ) async throws {
        let totalFrames = Int(ceil(prepared.plan.outputDuration * Double(Self.frameRate)))
        var staticFrames: [Int: CGImage] = [:]
        guard let pool = context.pixelAdaptor.pixelBufferPool else {
            throw ComparisonVideoExportError.writerConfigurationFailed
        }
        for frameIndex in 0..<totalFrames {
            try Task.checkCancellation()
            while !context.videoInput.isReadyForMoreMediaData {
                guard context.writer.status == .writing else {
                    throw ComparisonVideoExportError.writingFailed(
                        context.writer.error?.localizedDescription ?? "映像入力が停止しました"
                    )
                }
                try await Task.sleep(for: .milliseconds(2))
            }
            let outputTime = Double(frameIndex) / Double(Self.frameRate)
            let frameState = ComparisonVideoFrameState(
                trackTitle: request.first.trackTitle,
                firstRoleTitle: request.first.roleTitle,
                secondRoleTitle: request.second.roleTitle,
                plan: prepared.plan,
                outputTime: outputTime
            )
            let image: CGImage?
            if let sourceIndex = Self.cachedStaticFrameSourceIndex(for: frameState),
               let cachedImage = staticFrames[sourceIndex] {
                image = cachedImage
            } else {
                image = await renderFrame(
                    state: frameState,
                    orientation: request.orientation
                )
                if let sourceIndex = Self.cachedStaticFrameSourceIndex(for: frameState),
                   let image {
                    staticFrames[sourceIndex] = image
                }
            }
            guard let image,
                  let pixelBuffer = makePixelBuffer(from: image, pool: pool) else {
                throw ComparisonVideoExportError.videoFrameFailed
            }
            let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: Self.frameRate)
            guard context.pixelAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw ComparisonVideoExportError.writingFailed(
                    context.writer.error?.localizedDescription ?? "映像フレームを追加できませんでした"
                )
            }
        }
        context.videoInput.markAsFinished()
    }

    static func cachedStaticFrameSourceIndex(
        for state: ComparisonVideoFrameState
    ) -> Int? {
        state.transitionProgress >= 1 - 0.000_000_001 ? state.activeSourceIndex : nil
    }

    private func appendAudioSamples(
        context: ComparisonVideoWritingContext
    ) async throws {
        while context.reader.status == .reading {
            try Task.checkCancellation()
            while !context.audioInput.isReadyForMoreMediaData {
                guard context.writer.status == .writing else {
                    throw ComparisonVideoExportError.writingFailed(
                        context.writer.error?.localizedDescription ?? "音声入力が停止しました"
                    )
                }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let sampleBuffer = context.readerOutput.copyNextSampleBuffer() else { break }
            guard context.audioInput.append(sampleBuffer) else {
                throw ComparisonVideoExportError.writingFailed(
                    context.writer.error?.localizedDescription ?? "音声を追加できませんでした"
                )
            }
        }
        context.audioInput.markAsFinished()
        if context.reader.status == .failed {
            throw ComparisonVideoExportError.writingFailed(
                context.reader.error?.localizedDescription ?? "音声を読み込めませんでした"
            )
        }
    }

    @MainActor
    private func renderFrame(
        state: ComparisonVideoFrameState,
        orientation: ComparisonVideoOrientation
    ) -> CGImage? {
        let size = orientation.pixelSize
        let renderer = ImageRenderer(
            content: ComparisonVideoFrameView(state: state, orientation: orientation)
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        renderer.isOpaque = true
        renderer.colorMode = .nonLinear
        return renderer.cgImage
    }

    private func makePixelBuffer(
        from image: CGImage,
        pool: CVPixelBufferPool
    ) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(
                data: baseAddress,
                width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              ) else {
            return nil
        }
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: CVPixelBufferGetWidth(buffer),
                height: CVPixelBufferGetHeight(buffer)
            )
        )
        return buffer
    }

    private func audioSettings(
        format: ComparisonVideoFormat,
        sampleRate: Double,
        channelCount: Int
    ) -> [String: Any] {
        switch format {
        case .mp4:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: 320_000,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue,
            ]
        case .mov:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        }
    }
}
