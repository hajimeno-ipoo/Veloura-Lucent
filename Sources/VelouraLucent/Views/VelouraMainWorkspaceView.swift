import SwiftUI

struct VelouraMainWorkspaceView<AnalysisPanel: View>: View {
    @Bindable var job: ProcessingJob
    let preview: AudioPreviewController
    let bottomRegionTrailingExtension: CGFloat
    let analysisPanel: AnalysisPanel
    @State private var displayMode: WorkspaceDisplayMode = .basic
    @State private var isFullLogPresented = false

    init(
        job: ProcessingJob,
        preview: AudioPreviewController,
        bottomRegionTrailingExtension: CGFloat,
        @ViewBuilder analysisPanel: () -> AnalysisPanel
    ) {
        self.job = job
        self.preview = preview
        self.bottomRegionTrailingExtension = bottomRegionTrailingExtension
        self.analysisPanel = analysisPanel()
    }

    var body: some View {
        WorkspaceCenterLayout(
            isFullLogPresented: isFullLogPresented,
            bottomRegionTrailingExtension: bottomRegionTrailingExtension
        ) {
            fixedHeader
        } mainContent: {
            switch displayMode {
            case .basic:
                VelouraBasicWorkspaceView(
                    preview: preview,
                    inputFileURL: job.inputFile,
                    correctedFileURL: job.hasExistingOutput ? job.outputFile : nil,
                    masteredFileURL: job.hasExistingMasteredOutput
                        ? job.masteredOutputFile
                        : nil,
                    masteringSettings: job.appliedMasteringSettings
                        ?? job.editableMasteringSettings,
                    inputSpectrogram: job.inputSpectrogram,
                    correctedSpectrogram: job.outputSpectrogram,
                    masteredSpectrogram: job.masteredSpectrogram,
                    comparisonVideoLaunch: ComparisonVideoLaunch(
                        mode: .standard,
                        sources: ComparisonVideoSourceCatalog.standard(job: job)
                    )
                )
            case .detail:
                DetailedAnalysisWorkspaceView(job: job)
            }
        } footer: {
            WorkspaceFooterView(
                job: job,
                isFullLogPresented: $isFullLogPresented
            )
        } analysisPanel: {
            analysisPanel
        } fullLog: {
            FullProcessingLogView(
                job: job,
                onDismiss: { isFullLogPresented = false }
            )
        }
        .focusedSceneValue(
            \.velouraWorkspaceDisplaySelection,
            workspaceDisplaySelection
        )
    }

    private var workspaceDisplaySelection: Binding<VelouraWorkspaceDisplaySelection> {
        Binding(
            get: {
                if isFullLogPresented { return .fullLog }
                return displayMode == .basic ? .basic : .detailedAnalysis
            },
            set: { selection in
                switch selection {
                case .basic:
                    isFullLogPresented = false
                    displayMode = .basic
                case .detailedAnalysis:
                    isFullLogPresented = false
                    displayMode = .detail
                case .fullLog:
                    isFullLogPresented = true
                }
            }
        )
    }

    private var fixedHeader: some View {
        WorkspaceFixedHeaderView(
            title: "Veloura Lucent",
            summary: "音声を補正し、マスタリングで最終版に仕上げます。"
        ) {
            LiquidGlassSegmentedPicker(
                title: "中央表示",
                options: WorkspaceDisplayMode.allCases,
                selection: $displayMode,
                label: \.title
            )
        }
    }

}

private struct VelouraBasicWorkspaceView: View {
    let preview: AudioPreviewController
    let inputFileURL: URL?
    let correctedFileURL: URL?
    let masteredFileURL: URL?
    let masteringSettings: MasteringSettings
    let inputSpectrogram: SpectrogramSnapshot?
    let correctedSpectrogram: SpectrogramSnapshot?
    let masteredSpectrogram: SpectrogramSnapshot?
    let comparisonVideoLaunch: ComparisonVideoLaunch

    var body: some View {
        AudioWaveformWorkspaceView(
            preview: preview,
            inputFileURL: inputFileURL,
            correctedFileURL: correctedFileURL,
            masteredFileURL: masteredFileURL,
            comparisonVideoLaunch: comparisonVideoLaunch
        )

        WorkspaceLazySection {
            AverageSpectrumComparisonView(preview: preview)
        }

        VectorScopeView(
            preview: preview,
            masteringSettings: masteringSettings
        )

        WorkspaceLazySection {
            SpectrogramComparisonView(
                input: inputSpectrogram,
                corrected: correctedSpectrogram,
                mastered: masteredSpectrogram
            )
        }
    }
}

private enum WorkspaceDisplayMode: String, CaseIterable, Identifiable {
    case basic
    case detail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .basic: "基本表示"
        case .detail: "詳細解析"
        }
    }
}
