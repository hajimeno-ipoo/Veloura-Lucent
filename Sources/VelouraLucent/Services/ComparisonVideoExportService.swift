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
    let spectrumTimeline: [ComparisonVideoSpectrumFrame]

    func spectrumFrame(at time: TimeInterval) -> ComparisonVideoSpectrumFrame {
        Self.spectrumFrame(in: spectrumTimeline, at: time)
    }

    static func spectrumFrame(
        in spectrumTimeline: [ComparisonVideoSpectrumFrame],
        at time: TimeInterval
    ) -> ComparisonVideoSpectrumFrame {
        guard !spectrumTimeline.isEmpty else { return .empty }
        let interval = RealtimeSpectrumAnalyzer.timelineInterval
        let position = min(
            max(time.isFinite ? time : 0, 0) / interval,
            Double(spectrumTimeline.count - 1)
        )
        let lowerIndex = Int(position.rounded(.down))
        let upperIndex = min(lowerIndex + 1, spectrumTimeline.count - 1)
        let fraction = position - Double(lowerIndex)
        let lower = spectrumTimeline[lowerIndex]
        let upper = spectrumTimeline[upperIndex]
        guard lower.points.count == upper.points.count,
              lower.peakLevelsDB.count == upper.peakLevelsDB.count,
              !lower.points.isEmpty else {
            return fraction < 0.5 ? lower : upper
        }
        return ComparisonVideoSpectrumFrame(
            points: zip(lower.points, upper.points).map { lowerPoint, upperPoint in
                RealtimeSpectrumPoint(
                    id: lowerPoint.id,
                    frequencyHz: lowerPoint.frequencyHz,
                    levelDB: lowerPoint.levelDB
                        + (upperPoint.levelDB - lowerPoint.levelDB) * fraction
                )
            },
            peakLevelsDB: zip(lower.peakLevelsDB, upper.peakLevelsDB).map { lowerPeak, upperPeak in
                lowerPeak + (upperPeak - lowerPeak) * fraction
            }
        )
    }
}

struct ComparisonVideoExportRequest: Sendable {
    let first: ComparisonVideoSource
    let second: ComparisonVideoSource
    let startTime: TimeInterval
    let orientation: ComparisonVideoOrientation
    let format: ComparisonVideoFormat
    let displaySettings: ComparisonVideoDisplaySettings
    let firstInspectorInfo: ComparisonVideoInspectorInfo?
    let secondInspectorInfo: ComparisonVideoInspectorInfo?
    let destinationURL: URL

    init(
        first: ComparisonVideoSource,
        second: ComparisonVideoSource,
        startTime: TimeInterval,
        orientation: ComparisonVideoOrientation,
        format: ComparisonVideoFormat,
        displaySettings: ComparisonVideoDisplaySettings? = nil,
        firstInspectorInfo: ComparisonVideoInspectorInfo? = nil,
        secondInspectorInfo: ComparisonVideoInspectorInfo? = nil,
        destinationURL: URL
    ) {
        self.first = first
        self.second = second
        self.startTime = startTime
        self.orientation = orientation
        self.format = format
        self.displaySettings = displaySettings ?? ComparisonVideoDisplaySettings(
            trackTitle: first.trackTitle,
            firstRoleTitle: first.roleTitle,
            secondRoleTitle: second.roleTitle
        )
        self.firstInspectorInfo = firstInspectorInfo
        self.secondInspectorInfo = secondInspectorInfo
        self.destinationURL = destinationURL
    }
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

    func prepareAudio(
        first: ComparisonVideoSource,
        second: ComparisonVideoSource,
        startTime: TimeInterval,
        displaySettings: ComparisonVideoDisplaySettings? = nil
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
        let sequencedOutput = try makeSequence(
            first: firstSignal,
            second: secondSignal,
            plan: plan
        )
        let output = displaySettings.map {
            Self.applyingFade(
                to: sequencedOutput,
                fadeInDuration: $0.effectiveAudioFadeInDuration,
                fadeOutDuration: $0.effectiveAudioFadeOutDuration
            )
        } ?? sequencedOutput
        return ComparisonVideoPreparedAudio(
            signal: output,
            plan: plan,
            spectrumTimeline: displaySettings == nil
                ? []
                : Self.makeSpectrumTimeline(from: output)
        )
    }

    static func applyingFade(
        to signal: AudioSignal,
        fadeInDuration: TimeInterval,
        fadeOutDuration: TimeInterval
    ) -> AudioSignal {
        guard signal.frameCount > 0, signal.sampleRate > 0 else { return signal }
        let duration = Double(max(signal.frameCount - 1, 0)) / signal.sampleRate
        let gains = (0..<signal.frameCount).map { frameIndex in
            Float(ComparisonVideoFadeEnvelope.level(
                at: Double(frameIndex) / signal.sampleRate,
                duration: duration,
                fadeInDuration: fadeInDuration,
                fadeOutDuration: fadeOutDuration
            ))
        }
        return AudioSignal(
            channels: signal.channels.map { channel in
                zip(channel, gains).map { sample, gain in
                    sample * gain
                }
            },
            sampleRate: signal.sampleRate
        )
    }

    private static func makeSpectrumTimeline(
        from signal: AudioSignal
    ) -> [ComparisonVideoSpectrumFrame] {
        guard let firstChannel = signal.channels.first, !firstChannel.isEmpty else { return [] }
        var mono = Array(repeating: Float.zero, count: firstChannel.count)
        for channel in signal.channels {
            for index in mono.indices {
                mono[index] += channel[index] / Float(signal.channels.count)
            }
        }
        let rawTimeline = RealtimeSpectrumAnalyzer.timeline(
            from: mono,
            sampleRate: signal.sampleRate,
            frequencies: ComparisonVideoSpectrumProcessor.frequencies
        )
        return ComparisonVideoSpectrumProcessor.frames(
            from: rawTimeline,
            interval: RealtimeSpectrumAnalyzer.timelineInterval
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
            startTime: request.startTime,
            displaySettings: request.displaySettings
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
                displaySettings: request.displaySettings,
                firstInspectorInfo: request.firstInspectorInfo,
                secondInspectorInfo: request.secondInspectorInfo,
                plan: prepared.plan,
                outputTime: outputTime,
                visualizerSpectrum: prepared.spectrumFrame(at: outputTime)
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
                  let pixelBuffer = makePixelBuffer(
                    from: image,
                    pool: pool,
                    state: frameState,
                    orientation: request.orientation
                  ) else {
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
            content: ComparisonVideoFrameView(
                state: state,
                orientation: orientation,
                showsDynamicOverlays: false
            )
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
        pool: CVPixelBufferPool,
        state: ComparisonVideoFrameState,
        orientation: ComparisonVideoOrientation
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
        drawDynamicOverlays(
            in: context,
            state: state,
            orientation: orientation
        )
        return buffer
    }

    private func drawDynamicOverlays(
        in context: CGContext,
        state: ComparisonVideoFrameState,
        orientation: ComparisonVideoOrientation
    ) {
        let canvasSize = orientation.pixelSize
        if state.displaySettings.visualizerEnabled {
            drawSpectrumVisualizer(
                in: context,
                state: state,
                orientation: orientation
            )
        }

        let blackOpacity = 1 - state.videoFadeLevel
        if blackOpacity > 0 {
            context.setFillColor(CGColor(gray: 0, alpha: CGFloat(blackOpacity)))
            context.fill(CGRect(origin: .zero, size: canvasSize))
        }
    }

    private func drawSpectrumVisualizer(
        in context: CGContext,
        state: ComparisonVideoFrameState,
        orientation: ComparisonVideoOrientation
    ) {
        let settings = state.displaySettings
        let canvasSize = orientation.pixelSize
        let visualizerSize = settings.visualizerSize(for: orientation)
        let position = settings.position(for: .visualizer)
        let originX = canvasSize.width * position.x / 100 - visualizerSize.width / 2
        let originYFromTop = canvasSize.height * position.y / 100 - visualizerSize.height / 2
        let dots = ComparisonVideoSpectrumGeometry.dots(
            for: state.visualizerSpectrum,
            in: visualizerSize
        )
        guard let gradient = makeVisualizerGradient(settings: settings) else { return }
        let gradientStart = CGPoint(x: originX, y: 0)
        let gradientEnd = CGPoint(x: originX + visualizerSize.width, y: 0)
        let layers: [([CGRect], CGFloat)] = [
            (dots.outerGlowDots, 0.08),
            (dots.innerGlowDots, 0.16),
            (dots.peakGlowDots, 0.24),
            (dots.inactiveDots, 0.10),
            (dots.lowDots, 0.68),
            (dots.middleDots, 0.84),
            (dots.highDots, 1),
            (dots.reflectionDots, 0.18),
            (dots.peakDots, 1)
        ]
        for (rects, opacity) in layers {
            fillSpectrumDots(
                rects,
                opacity: opacity,
                in: context,
                gradient: gradient,
                gradientStart: gradientStart,
                gradientEnd: gradientEnd,
                originX: originX,
                originYFromTop: originYFromTop,
                canvasHeight: canvasSize.height
            )
        }
    }

    private func makeVisualizerGradient(
        settings: ComparisonVideoDisplaySettings
    ) -> CGGradient? {
        let stops = settings.visualizerGradientStops
        let colors = stops.map { stop in
            let color = stop.color
            return CGColor(
                red: CGFloat(color.red),
                green: CGFloat(color.green),
                blue: CGFloat(color.blue),
                alpha: CGFloat(color.alpha)
            )
        }
        return CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: colors as CFArray,
            locations: stops.map { CGFloat($0.location) }
        )
    }

    private func fillSpectrumDots(
        _ rects: [CGRect],
        opacity: CGFloat,
        in context: CGContext,
        gradient: CGGradient,
        gradientStart: CGPoint,
        gradientEnd: CGPoint,
        originX: CGFloat,
        originYFromTop: CGFloat,
        canvasHeight: CGFloat
    ) {
        guard !rects.isEmpty else { return }
        let path = CGMutablePath()
        for rect in rects {
            path.addEllipse(in: outputRect(
                for: rect,
                originX: originX,
                originYFromTop: originYFromTop,
                canvasHeight: canvasHeight
            ))
        }
        context.saveGState()
        context.setAlpha(opacity)
        context.addPath(path)
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: gradientStart,
            end: gradientEnd,
            options: []
        )
        context.restoreGState()
    }

    private func outputRect(
        for rect: CGRect,
        originX: CGFloat,
        originYFromTop: CGFloat,
        canvasHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: originX + rect.minX,
            y: canvasHeight - originYFromTop - rect.maxY,
            width: rect.width,
            height: rect.height
        )
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
