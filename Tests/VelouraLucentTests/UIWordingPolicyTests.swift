import Foundation
import Testing

struct UIWordingPolicyTests {
    @Test
    func uiCopyKeepsNumbersAsListeningGuides() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/ContentView.swift",
                "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift",
                "Sources/VelouraLucent/Views/InspectorAnalysisPanel.swift",
                "Sources/VelouraLucent/Views/InspectorSettingsPanel.swift",
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

    @Test
    func mainWorkspaceKeepsBasicAndDetailedAnalysisSeparated() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/VelouraMainWorkspaceView.swift",
                "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"
            ]
        )

        #expect(source.contains("基本表示"))
        #expect(source.contains("詳細解析"))
        #expect(source.contains("AudioWaveformWorkspaceView"))
        #expect(source.contains("AverageSpectrumComparisonView"))
        #expect(source.contains("SpectrogramComparisonView"))
        #expect(source.contains("主要数値比較"))
        #expect(source.contains("補正差分"))
        #expect(source.contains("マスタリング差分"))
        #expect(source.contains("ノイズ7種類比較"))
        #expect(source.contains("ステレオ相関"))
        #expect(source.contains("短時間ラウドネス"))
        #expect(source.contains("ダイナミクス推移"))
        #expect(source.contains("平均スペクトル比較"))
        #expect(source.contains("周波数帯域詳細"))
        #expect(source.contains("右側インスペクタと下部ログへ同じ表を重複表示せず"))
        #expect(source.contains("仕上がりの方向") == false)
    }

    @Test
    func detailedAnalysisHeavyChartsStartCollapsed() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift"])

        #expect(source.contains("@State private var showLoudness = false"))
        #expect(source.contains("@State private var showDynamics = false"))
        #expect(source.contains("@State private var showSpectrum = false"))
        #expect(source.contains("@State private var showBands = false"))
    }

    @Test
    func sidebarUsesApprovedInformationSections() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/VelouraSidebarView.swift",
                "Sources/VelouraLucent/Views/SidebarFileRow.swift",
                "Sources/VelouraLucent/Views/SidebarProcessStatusRow.swift"
            ]
        )

        #expect(source.contains("Section(\"音源\")"))
        #expect(source.contains("Section(\"工程\")"))
        #expect(!source.contains("Section(\"ファイル情報\")"))
        #expect(!source.contains("Section(\"入力\")"))
        #expect(!source.contains("Section(\"処理状態\")"))
        #expect(source.contains("fileInfo: job.inputFileInfo"))
        #expect(source.contains("fileInfo: job.hasExistingOutput ? job.outputFileInfo : nil"))
        #expect(source.contains("fileInfo: job.hasExistingMasteredOutput ? job.masteredFileInfo : nil"))
        #expect(source.contains("fileInfo.technicalSummary"))
        #expect(source.contains("fileInfo.durationText"))
        #expect(source.contains("progressText"))
    }

    @Test
    func sidebarShowsFullCorrectionAndMasteringStepLists() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/SidebarProcessingStatusView.swift",
                "Sources/VelouraLucent/Views/SidebarProcessStatusRow.swift"
            ]
        )

        #expect(source.contains("ProcessingStep.allCases"))
        #expect(source.contains("MasteringStep.allCases"))
        #expect(source.contains("completedSteps: job.completedSteps"))
        #expect(source.contains("skippedSteps: job.skippedSteps"))
        #expect(source.contains("failedSteps: job.failedSteps"))
        #expect(source.contains("completedSteps: job.completedMasteringSteps"))
        #expect(source.contains("skippedSteps: job.skippedMasteringSteps"))
        #expect(source.contains("failedSteps: job.failedMasteringSteps"))
        #expect(source.contains("実行中"))
        #expect(source.contains("省略"))
        #expect(source.contains("失敗"))
    }

    @Test
    func footerUsesStructuredRecentEventsAndRealProgress() throws {
        let source = try combinedSource(
            [
                "Sources/VelouraLucent/Views/RecentProcessingLogView.swift",
                "Sources/VelouraLucent/Views/WorkspaceFooterView.swift",
                "Sources/VelouraLucent/Views/OverallWorkflowView.swift"
            ]
        )

        #expect(source.contains("events: job.recentActivityEvents"))
        #expect(source.contains("ForEach(events.suffix(3))"))
        #expect(source.contains("event.timestamp"))
        #expect(source.contains("event.fileName"))
        #expect(source.contains("event.audioSummary"))
        #expect(source.contains("event.progress"))
        #expect(source.contains("job.progressValue"))
        #expect(source.contains("job.masteringProgressValue"))
        #expect(source.contains("Text(\"全体進捗\")"))
        #expect(!source.contains("correctionLines: job.visibleLogLines"))
    }

    @Test
    func filePanelsDoNotUseNestedModalEventLoops() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Services/FilePanelService.swift"])

        #expect(source.contains("panel.begin"))
        #expect(!source.contains("runModal()"))
    }

    private func combinedSource(_ relativePaths: [String]) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return try relativePaths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }
}
