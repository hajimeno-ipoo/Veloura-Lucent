import AudioToolbox
import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct ProcessingActionsTests {
    @Test(arguments: [false, true])
    func correctionContinuesToMasteringOnlyWhenRequested(_ continues: Bool) async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appending(path: "continuation.wav")
        let samples = (0..<24_000).map { index in
            Float(0.1 * sin(2 * Double.pi * 440 * Double(index) / 48_000))
        }
        try AudioFileService.saveAudio(
            AudioSignal(channels: [samples, samples], sampleRate: 48_000),
            to: inputURL
        )
        let actions = ProcessingActions(notificationReporter: NoOpCompletionNotificationReporter.shared)
        defer { actions.shutdown() }
        defer {
            if continues && !actions.job.hasExistingMasteredOutput {
                print("Automatic mastering state:", actions.job.statusMessage, actions.job.masteringStatusMessage,
                      actions.canStartMastering, actions.job.isAnalyzingDisplayAnalysis,
                      actions.job.logText, actions.job.masteringLogText)
            }
        }
        actions.job.prepareForSelection(inputURL)
        let masteringSettings = actions.job.editableMasteringSettings

        actions.startCorrectionProcessing(continueToMastering: continues)
        try await waitUntil {
            actions.presentedError != nil || (
                actions.job.hasExistingOutput
                    && !actions.job.isAnalyzingDisplayAnalysis
                    && (continues ? actions.job.hasExistingMasteredOutput : true)
            )
        }

        #expect(actions.presentedError == nil)
        #expect(actions.job.hasExistingOutput)
        #expect(actions.job.canUseCorrectedAnalysisForMastering)
        #expect(actions.job.hasExistingMasteredOutput == continues)
        #expect(!actions.job.isMastering)
        if continues {
            #expect(actions.job.appliedMasteringSettings == masteringSettings)
        }
    }

    @Test(arguments: [false, true])
    func unsuccessfulCorrectionDoesNotStartAutomaticMastering(_ cancel: Bool) async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let actions = ProcessingActions(notificationReporter: NoOpCompletionNotificationReporter.shared)
        defer { actions.shutdown() }
        actions.job.prepareForSelection(directory.appending(path: "missing.wav"))

        actions.startCorrectionProcessing(continueToMastering: true)
        if cancel { actions.cancelCorrectionProcessing() }
        try await waitUntil { !actions.job.isProcessing }

        #expect(!actions.job.isMastering)
        #expect(!actions.job.hasExistingMasteredOutput)
        #expect(actions.job.masteringStartedAt == nil)
        if cancel {
            #expect(actions.job.logText.contains("補正処理をキャンセルしました"))
        } else {
            #expect(actions.presentedError != nil)
        }
        if let output = actions.job.masteredOutputFile {
            #expect(!FileManager.default.fileExists(atPath: output.path))
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(120)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "処理が制限時間内に完了しませんでした")
    }

    @Test
    func availabilityFollowsProcessingState() {
        let actions = ProcessingActions(notificationReporter: NoOpCompletionNotificationReporter.shared)

        #expect(actions.canAcceptInputAudioDrop)
        #expect(!actions.canStartMastering)

        actions.job.isProcessing = true
        #expect(!actions.canAcceptInputAudioDrop)

        actions.job.isProcessing = false
        actions.job.isMastering = true
        #expect(!actions.canAcceptInputAudioDrop)
    }

    @Test
    func cancelActionsUpdateTheJobState() {
        let actions = ProcessingActions(notificationReporter: NoOpCompletionNotificationReporter.shared)

        actions.job.isProcessing = true
        actions.cancelCorrectionProcessing()
        #expect(actions.job.isCancellingProcessing)
        #expect(actions.job.statusMessage == "キャンセル中")

        actions.job.isProcessing = false
        actions.job.isMastering = true
        actions.cancelMasteringProcessing()
        #expect(actions.job.isCancellingMastering)
        #expect(actions.job.masteringStatusMessage == "キャンセル中")
    }

    @Test
    func orderedLogSinkDrainsMessagesBeforeReturning() async {
        var received: [String] = []
        let sink = OrderedProcessingLogSink { message in
            received.append(message)
        }

        await Task.detached {
            sink.send("読み込み")
            sink.send("解析")
            sink.send("書き出し")
        }.value
        await sink.finish()

        #expect(received == ["読み込み", "解析", "書き出し"])
    }

    @Test
    func cancellationClearsPreviewsForInvalidatedOutputs() {
        let actions = ProcessingActions(notificationReporter: NoOpCompletionNotificationReporter.shared)
        actions.preview.cardState(for: .corrected).sourceURL = URL(filePath: "/tmp/corrected.wav")
        actions.preview.cardState(for: .mastered).sourceURL = URL(filePath: "/tmp/mastered.wav")

        actions.clearCorrectionOutputPreviews()

        #expect(actions.preview.cardState(for: .corrected).sourceURL == nil)
        #expect(actions.preview.cardState(for: .mastered).sourceURL == nil)

        actions.preview.cardState(for: .corrected).sourceURL = URL(filePath: "/tmp/corrected.wav")
        actions.preview.cardState(for: .mastered).sourceURL = URL(filePath: "/tmp/mastered.wav")

        actions.clearMasteringOutputPreview()

        #expect(actions.preview.cardState(for: .corrected).sourceURL != nil)
        #expect(actions.preview.cardState(for: .mastered).sourceURL == nil)
    }

    @Test
    func unknownMultichannelLayoutDoesNotBecomeCurrentInput() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unsupportedURL = directory.appending(path: "unknown-six-channel.wav")
        try writeSixChannelWAVWithoutLayout(to: unsupportedURL)
        let actions = ProcessingActions(notificationReporter: NoOpCompletionNotificationReporter.shared)

        let accepted = actions.acceptDroppedInputAudio([unsupportedURL])

        #expect(!accepted)
        #expect(actions.job.inputFile == nil)
        #expect(actions.preview.cardState(for: .input).sourceURL == nil)
        #expect(actions.presentedError?.title == "チャンネル構成を確認できません")
    }

    @Test
    func unknownMultichannelLayoutPreservesExistingSelection() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unsupportedURL = directory.appending(path: "unknown-six-channel.wav")
        try writeSixChannelWAVWithoutLayout(to: unsupportedURL)
        let existingURL = directory.appending(path: "existing.wav")
        let actions = ProcessingActions(notificationReporter: NoOpCompletionNotificationReporter.shared)
        actions.job.prepareForSelection(existingURL)
        actions.preview.cardState(for: .input).sourceURL = existingURL

        let accepted = actions.acceptDroppedInputAudio([unsupportedURL])

        #expect(!accepted)
        #expect(actions.job.inputFile == existingURL)
        #expect(actions.preview.cardState(for: .input).sourceURL == existingURL)
    }

    @Test
    func standardMultichannelLayoutBecomesCurrentInputWithoutUserConfiguration() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appending(path: "standard-5-1.wav")
        try writeMPEG51AWAV(to: inputURL)
        let actions = ProcessingActions(notificationReporter: NoOpCompletionNotificationReporter.shared)
        defer { actions.shutdown() }

        let accepted = actions.acceptDroppedInputAudio([inputURL])

        #expect(accepted)
        #expect(actions.job.inputFile == inputURL)
        #expect(actions.presentedError == nil)
    }

    @Test
    func shutdownRemovesOnlyTheCurrentJobPreviewFiles() throws {
        let actions = ProcessingActions(
            notificationReporter: NoOpCompletionNotificationReporter.shared
        )
        let corrected = PreviewFileStore.temporaryOutputURL(
            baseName: "processing-actions-current",
            suffix: "corrected"
        )
        let mastered = PreviewFileStore.temporaryOutputURL(
            baseName: "processing-actions-current",
            suffix: "mastered"
        )
        let anotherJob = PreviewFileStore.temporaryOutputURL(
            baseName: "processing-actions-another-job",
            suffix: "corrected"
        )
        defer {
            try? FileManager.default.removeItem(at: corrected)
            try? FileManager.default.removeItem(at: mastered)
            try? FileManager.default.removeItem(at: anotherJob)
        }
        try Data("corrected".utf8).write(to: corrected)
        try Data("mastered".utf8).write(to: mastered)
        try Data("another-job".utf8).write(to: anotherJob)
        actions.job.outputFile = corrected
        actions.job.masteredOutputFile = mastered

        actions.shutdown()

        #expect(!FileManager.default.fileExists(atPath: corrected.path))
        #expect(!FileManager.default.fileExists(atPath: mastered.path))
        #expect(FileManager.default.fileExists(atPath: anotherJob.path))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "veloura-processing-actions-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeSixChannelWAVWithoutLayout(to url: URL) throws {
        let channelCount: UInt16 = 6
        let sampleRate: UInt32 = 48_000
        let bitsPerSample: UInt16 = 16
        let frameCount: UInt32 = 480
        let bytesPerSample = bitsPerSample / 8
        let blockAlign = channelCount * bytesPerSample
        let dataSize = frameCount * UInt32(blockAlign)

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        appendLittleEndian(36 + dataSize, to: &data)
        data.append(contentsOf: "WAVEfmt ".utf8)
        appendLittleEndian(UInt32(16), to: &data)
        appendLittleEndian(UInt16(1), to: &data)
        appendLittleEndian(channelCount, to: &data)
        appendLittleEndian(sampleRate, to: &data)
        appendLittleEndian(sampleRate * UInt32(blockAlign), to: &data)
        appendLittleEndian(blockAlign, to: &data)
        appendLittleEndian(bitsPerSample, to: &data)
        data.append(contentsOf: "data".utf8)
        appendLittleEndian(dataSize, to: &data)
        data.append(Data(count: Int(dataSize)))
        try data.write(to: url)
    }

    private func writeMPEG51AWAV(to url: URL) throws {
        let layout = try #require(
            AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_MPEG_5_1_A)
        )
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            interleaved: false,
            channelLayout: layout
        )
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let buffer = try #require(
            AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480)
        )
        buffer.frameLength = 480
        for channel in 0..<Int(format.channelCount) {
            buffer.floatChannelData?[channel].initialize(
                repeating: Float(channel + 1) * 0.01,
                count: Int(buffer.frameLength)
            )
        }
        try file.write(from: buffer)
    }

    private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}
