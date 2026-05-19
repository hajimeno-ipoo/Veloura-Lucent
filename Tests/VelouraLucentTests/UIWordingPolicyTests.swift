import Foundation
import Testing

struct UIWordingPolicyTests {
    @Test
    func uiCopyKeepsNumbersAsListeningGuides() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/ContentView.swift",
                "Sources/VelouraLucent/Views/CorrectionSettingsPanel.swift",
                "Sources/VelouraLucent/Views/MasteringSettingsPanel.swift",
                "Sources/VelouraLucent/Services/AudioQualityReportService.swift",
                "Sources/VelouraLucent/Services/NoiseCheckReportService.swift"
            ]
        )

        for bannedPhrase in [
            "追加調整は不要です。",
            "次に触るなら",
            "見込み:",
            "自然に聞こえる方向へ寄せます",
            "Integrated Loudness が"
        ] {
            #expect(!source.contains(bannedPhrase))
        }

        #expect(source.contains("数値上の追加候補はありません。最終版を聴いて違和感がないか確認してください。"))
        #expect(source.contains("聴いて気になる場合の調整候補"))
        #expect(source.contains("目標値に必ず合わせるものではなく、仕上げ意図を確認する目安です。"))
        #expect(source.contains("目安:"))
        #expect(source.contains("聴き比べてください"))
    }

    private func combinedSource(_ relativePaths: [String]) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return try relativePaths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }
}
