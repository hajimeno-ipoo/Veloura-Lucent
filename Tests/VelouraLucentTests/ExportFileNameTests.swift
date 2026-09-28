import Foundation
import Testing
@testable import VelouraLucent

struct ExportFileNameTests {
    private let inputURL = URL(fileURLWithPath: "/tmp/夜の曲.v2.wav")

    @Test
    func audioNamesUseSongModeAndResult() {
        #expect(ExportFileName.audio(
            inputURL: inputURL,
            mode: .standard,
            result: "補正",
            format: .deliveryWAV
        ) == "夜の曲.v2_通常_補正.wav")
        #expect(ExportFileName.audio(
            inputURL: inputURL,
            mode: .standard,
            result: "マスタリング",
            format: .sharingAAC
        ) == "夜の曲.v2_通常_マスタリング.m4a")
        #expect(ExportFileName.audio(
            inputURL: inputURL,
            mode: .stem,
            result: "再ミックス",
            format: .highQualityWAV
        ) == "夜の曲.v2_ステム_再ミックス.wav")
    }

    @Test
    func stemResultsUseTheirUserVisibleNames() {
        #expect(StemArtifactKind.correctedPureSum48000.exportFileNameComponent == "補正")
        #expect(StemArtifactKind.remixed48000.exportFileNameComponent == "再ミックス")
        #expect(StemArtifactKind.finalMaster.exportFileNameComponent == "マスタリング")
        #expect(StemArtifactKind.input44100.exportFileNameComponent == nil)
        for role in StemRole.allCases {
            #expect(StemArtifactKind.correctedStem(role).exportFileNameComponent == role.stemModeDisplayTitle)
            #expect(StemArtifactKind.rawStem(role).exportFileNameComponent == nil)
        }
    }

    @Test
    func logNamesReplaceOnlyTheAppNameWithTheSongName() {
        #expect(ExportFileName.processingLog(inputURL: inputURL, mode: .standard)
            == "夜の曲.v2 処理ログ - 通常.json")
        #expect(ExportFileName.processingLog(inputURL: inputURL, mode: .stem)
            == "夜の曲.v2 処理ログ - Stem Mode.json")
    }
}
