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
}
