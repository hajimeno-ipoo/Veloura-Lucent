import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct ProcessingActionsTests {
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
}
