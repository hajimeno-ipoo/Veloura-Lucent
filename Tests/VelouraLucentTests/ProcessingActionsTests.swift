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
}
