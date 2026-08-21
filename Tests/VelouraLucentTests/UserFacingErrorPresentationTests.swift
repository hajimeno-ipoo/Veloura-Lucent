import AudioToolbox
import Foundation
import Testing
@testable import VelouraLucent

struct UserFacingErrorPresentationTests {
    @Test
    func readFailureExplainsWhatTheUserCanCheck() {
        let presentation = UserFacingErrorPresentation.make(
            for: AppError.audioReadFailed,
            operation: .inputAnalysis
        )

        #expect(presentation.title == "音声ファイルを読み込めませんでした")
        #expect(presentation.recoverySuggestion.contains("読み取り権限"))
        #expect(presentation.technicalDetails == AppError.audioReadFailed.localizedDescription)
    }

    @Test
    func exportFailureDoesNotDescribeItselfAsProcessingFailure() {
        let presentation = UserFacingErrorPresentation.make(
            for: NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError),
            operation: .masteredExport
        )

        #expect(presentation.title == "最終版を書き出せませんでした")
        #expect(presentation.recoverySuggestion.contains("書き込み権限"))
    }

    @Test
    func unsupportedChannelLayoutExplainsStandardLayoutRequirement() {
        let layout = StemInputLayoutIdentity(
            channelCount: 6,
            layoutTag: kAudioChannelLayoutTag_Unknown | 6,
            channelBitmap: 0,
            channelDescriptions: []
        )
        let presentation = UserFacingErrorPresentation.make(
            for: StemInputConversionError.unsupportedChannelLayout(layout),
            operation: .inputAnalysis
        )

        #expect(presentation.title == "チャンネル構成を確認できません")
        #expect(presentation.message.contains("各チャンネルの役割"))
        #expect(presentation.recoverySuggestion.contains("標準的なチャンネル構成"))
    }
}
