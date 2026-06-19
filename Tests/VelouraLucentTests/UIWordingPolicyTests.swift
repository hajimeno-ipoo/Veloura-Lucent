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
                "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift",
                "Sources/VelouraLucent/Views/VectorScopeView.swift",
                "Sources/VelouraLucent/Views/VectorScopeModePicker.swift"
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
        #expect(source.contains("VectorScopeView("))
        #expect(source.contains("preview: preview"))
        #expect(source.contains("Text(\"ベクトルスコープ\")"))
        #expect(source.contains("Picker(\"ベクトルスコープ表示\", selection: $displayMode)"))
        #expect(source.contains("TermHelpButton("))
        #expect(source.contains("Polar Sampleは、左右チャンネルのサンプルを半円上の点で表示します。"))
        #expect(source.contains("Polar Levelは、短い時間の平均を線で表示します。"))
        #expect(source.contains("Lissajousは、左右チャンネルの瞬間的な関係を菱形の中の点で表示します。"))
        #expect(source.contains("Lissajous"))
        #expect(source.contains("Polar Sample"))
        #expect(source.contains("Polar Level"))
        #expect(source.contains("Text(\"相関\")"))
        #expect(source.contains("Text(\"L/Rバランス\")"))
        #expect(!source.contains("再生中ベクトルスコープ"))
        #expect(source.contains("短時間ラウドネス"))
        #expect(source.contains("ダイナミクス推移"))
        #expect(source.contains("平均スペクトル比較"))
        #expect(source.contains("周波数帯域詳細"))
        #expect(source.contains("右側インスペクタと下部ログへ同じ表を重複表示せず"))
        #expect(source.contains("仕上がりの方向") == false)
    }

    @Test
    func contentViewKeepsSidebarAndTogglesRightSettingsPanel() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/ContentView.swift"])

        #expect(source.contains("@State private var isInspectorPresented = true"))
        #expect(source.contains("NavigationSplitView {"))
        #expect(source.contains("VelouraSidebarView(job: job)"))
        #expect(source.contains("HStack(spacing: 0)"))
        #expect(source.contains("VelouraMainWorkspaceView("))
        #expect(source.contains("if isInspectorPresented"))
        #expect(source.contains("VelouraInspectorView(job: job, completionReport: completionReport)"))
        #expect(source.contains("ToolbarItem(placement: .primaryAction)"))
        #expect(source.contains(".labelStyle(.iconOnly)"))
        #expect(source.contains(".buttonStyle(.plain)"))
        #expect(source.contains("設定を隠す"))
        #expect(source.contains("設定を表示"))
        #expect(!source.contains("NavigationSplitView(columnVisibility:"))
        #expect(!source.contains(".inspector(isPresented:"))
        #expect(!source.contains(".inspectorColumnWidth("))
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
    func stereoCorrelationMeterShowsReadableScale() throws {
        let source = try combinedSource([
            "Sources/VelouraLucent/Views/DetailedAnalysisWorkspaceView.swift",
            "Sources/VelouraLucent/Views/VectorScopeView.swift"
        ])

        #expect(source.contains("0未満はモノラル再生で音が痩せる可能性があります。"))
        #expect(source.contains("-1 逆相"))
        #expect(source.contains("0 注意"))
        #expect(source.contains("+1 同相"))
        #expect(source.contains("-1は逆相、0は注意、+1は同相です。"))
        #expect(source.contains("correlationScaleLabel(value: \"+1\", meaning: \"同相\")"))
        #expect(source.contains("correlationScaleLabel(value: \"0\", meaning: \"注意\")"))
        #expect(source.contains("correlationScaleLabel(value: \"-1\", meaning: \"逆相\")"))
        #expect(source.contains("時間ごとの相関推移"))
        #expect(source.contains("無音区間は相関値として計算せず、線を区切ります。"))
        #expect(source.contains("モノラル音源のため、ステレオ相関推移はありません。"))
        #expect(source.contains("chartYScale(domain: -1 ... 1)"))
        #expect(source.contains("RuleMark(y: .value(\"注意ライン\", 0))"))
        #expect(source.contains("series: .value(\"区間\", point.lineGroup)"))
        #expect(source.contains("correlationTimelineDuration(stages: stages)"))
        #expect(source.contains("Lissajous: 縦=同相 / 横=逆相 / 斜め=左右偏り。"))
        #expect(source.contains("Polar Sample: 45度安全ライン内は同相、外側は位相ずれを示します。"))
        #expect(source.contains("Polar Level: 平均線の角度でステレオ位置、長さで振幅を確認します。"))
        #expect(source.contains("モノラル音源のため、左右の関係は表示しません"))
        #expect(source.contains("チャンネル音源はベクトルスコープ未対応です"))
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

    @Test
    func realtimeSpectrumKeepsChartFrameVisibleBeforePlayback() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/AverageSpectrumComparisonView.swift"])

        #expect(source.contains("ZStack"))
        #expect(source.contains("SpectrumCanvasChart(series: spectrumSeries)"))
        #expect(source.contains("if spectrumSeries.isEmpty"))
        #expect(source.contains("emptySpectrumMessage"))
    }

    @Test
    func spectrogramShowsSharedTimeAxis() throws {
        let source = try combinedSource(["Sources/VelouraLucent/Views/SpectrogramComparisonView.swift"])

        #expect(source.contains("timeAxisDuration"))
        #expect(source.contains("SpectrogramTimeAxisView"))
        #expect(source.contains("スペクトログラムの時間目盛り"))
        #expect(source.contains("formatTime"))
        #expect(source.contains("sharedDuration: timeAxisDuration"))
        #expect(source.contains("chartXScale(domain: 0 ... max(sharedDuration ?? snapshot.duration, 0.1))"))
    }

    private func combinedSource(_ relativePaths: [String]) throws -> String {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        return try relativePaths
            .map { try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }
}
