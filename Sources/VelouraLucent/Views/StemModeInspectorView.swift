import SwiftUI

@MainActor
struct StemModeInspectorView: View {
    @Bindable var model: StemModeWorkspaceModel
    @Bindable var modelManager: StemModelManager
    @Binding var windowBackgroundMaterialAmount: Double
    @Binding var isWindowBackgroundBlurEnabled: Bool
    @Binding var windowBackgroundBlurLevel: WindowBackgroundBlurLevel
    @Binding var selectedSettingsSectionRawValue: String
    let isWindowFullScreen: Bool
    let openKeyboardShortcutManager: @MainActor () -> Void

    var body: some View {
        ScrollView {
            StemModeInspectorSettingsPanel(
                model: model,
                modelManager: modelManager,
                windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled,
                windowBackgroundBlurLevel: $windowBackgroundBlurLevel,
                selectedSectionRawValue: $selectedSettingsSectionRawValue,
                isWindowFullScreen: isWindowFullScreen,
                openKeyboardShortcutManager: openKeyboardShortcutManager
            )
            .padding(14)
            .velouraTransientOverlayScrollIndicators()
        }
        .scrollContentBackground(.hidden)
    }
}

enum StemModeInspectorSettingsSection: String, CaseIterable, Identifiable {
    case correction
    case remix
    case mastering
    case app

    var id: String { rawValue }
    var title: String {
        switch self {
        case .correction: "補正"
        case .remix: "再ミックス"
        case .mastering: "マスタリング"
        case .app: "アプリ"
        }
    }
}

@MainActor
private struct StemModeInspectorSettingsPanel: View {
    @Bindable var model: StemModeWorkspaceModel
    @Bindable var modelManager: StemModelManager
    @Binding var windowBackgroundMaterialAmount: Double
    @Binding var isWindowBackgroundBlurEnabled: Bool
    @Binding var windowBackgroundBlurLevel: WindowBackgroundBlurLevel
    @Binding var selectedSectionRawValue: String
    let isWindowFullScreen: Bool
    let openKeyboardShortcutManager: @MainActor () -> Void

    var body: some View {
        InspectorSettingsSectionLayout(
            options: StemModeInspectorSettingsSection.allCases,
            selection: selectedSectionBinding,
            label: \.title,
            isDisabled: model.isRunActive || model.isStartingRun
        ) {
            switch selectedSection {
            case .correction:
                StemModeCorrectionSettingsView(model: model)
                    .disabled(model.isCorrectionSettingsDisabled)
            case .remix:
                StemModeRemixSettingsView(model: model)
            case .mastering:
                StemModeMasteringSettingsView(model: model)
                    .disabled(model.isMasteringSettingsDisabled)
            case .app:
                VStack(alignment: .leading, spacing: 18) {
                    AppSettingsPanel(
                        windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                        isWindowBackgroundBlurEnabled: $isWindowBackgroundBlurEnabled,
                        windowBackgroundBlurLevel: $windowBackgroundBlurLevel,
                        isWindowFullScreen: isWindowFullScreen,
                        openKeyboardShortcutManager: openKeyboardShortcutManager
                    )
                    Divider()
                    StemModeAnalysisModeSettings(model: model)
                    Divider()
                    StemModelManagementSection(
                        modelManager: modelManager,
                        settings: model.separationSettings,
                        modelPresentation: model.modelPresentation,
                        isDisabled: model.isRunActive || model.isStartingRun
                    )
                }
            }
        }
    }

    private var selectedSection: StemModeInspectorSettingsSection {
        StemModeInspectorSettingsSection(rawValue: selectedSectionRawValue) ?? .correction
    }

    private var selectedSectionBinding: Binding<StemModeInspectorSettingsSection> {
        Binding(
            get: { selectedSection },
            set: { selectedSectionRawValue = $0.rawValue }
        )
    }
}

@MainActor
private struct StemModeAnalysisModeSettings: View {
    @Bindable var model: StemModeWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("解析モード")
                    .font(.title3.bold())
                TermHelpButton(
                    title: "解析モード",
                    reading: "かいせきもーど",
                    description: "補正前の音声解析に使う方式です。自動はこのMacで使える方式を選び、安定CPUは速度より安定性を優先し、実験Metalは対応MacでGPUを使います。"
                )
            }

            LiquidGlassSegmentedPicker(
                title: "解析モード",
                options: AudioAnalysisMode.allCases,
                selection: $model.selectedAnalysisMode,
                label: \.title,
                isDisabled: model.session.isCorrectionProcessing
            )

            Text(model.selectedAnalysisMode.summary)
                .foregroundStyle(
                    model.selectedAnalysisMode == .experimentalMetal
                        ? VelouraTextColors.orange
                        : .secondary
                )
            Text(model.selectedAnalysisMode.resolvedSummary)
                .font(.body)
                .foregroundStyle(
                    model.selectedAnalysisMode.resolvedMode == .experimentalMetal
                        ? VelouraTextColors.orange
                        : .secondary
                )
        }
    }
}

@MainActor
struct StemModeInspectorAnalysisPanel: View {
    @Bindable var model: StemModeWorkspaceModel
    @Binding var selectedAudio: InspectorAudioSelection
    @Binding var isCompletionReportPresented: Bool

    var body: some View {
        InspectorAnalysisPanelContent(
            isAnalyzing: model.isAnalyzingInput || model.isAnalyzingDisplayAudio,
            inputMetrics: model.inputMetrics,
            processedMetrics: model.correctedRemixMetrics,
            masteredMetrics: model.finalMetrics,
            processedTitle: processedTitle,
            completionReport: completionReport,
            selectedAudio: $selectedAudio,
            isCompletionReportPresented: $isCompletionReportPresented,
            peakCeilingDB: Double(
                (model.qualityReports?.masteringSettings ?? model.masteringSettings).peakCeilingDB
            ),
            analysisState: analysisState,
            selectionTitle: selectionTitle,
            unavailableDescription: unavailableDescription
        ) {
            importantWarnings
        }
    }

    private var completionReport: CompletionReport? {
        model.qualityReports?.completion
    }

    private func analysisState(_ selection: InspectorAudioSelection) -> DisplayAnalysisPresentationState {
        let target: DisplayAnalysisTarget
        let hasSource: Bool
        let isRunning: Bool
        let hasFailed: Bool

        switch selection {
        case .input:
            target = .input
            hasSource = model.selectedInputURL != nil
            isRunning = model.isAnalyzingInput
            hasFailed = model.inputAnalysisError != nil
        case .corrected:
            target = .corrected
            hasSource = model.correctedRemixPreviewArtifact != nil
            isRunning = model.isAnalyzingDisplayAudio && hasSource
            hasFailed = model.displayAnalysisError != nil && hasSource
        case .mastered:
            target = .mastered
            hasSource = model.finalPreviewArtifact != nil
            isRunning = model.isAnalyzingDisplayAudio && hasSource
            hasFailed = model.displayAnalysisError != nil && hasSource
        }

        let metrics: AudioMetricSnapshot?
        switch target {
        case .input: metrics = model.inputMetrics
        case .corrected: metrics = model.correctedRemixMetrics
        case .mastered: metrics = model.finalMetrics
        }
        return DisplayAnalysisPresentationState.resolve(
            hasSource: hasSource,
            hasMetrics: metrics != nil,
            isRunning: isRunning,
            hasFailed: hasFailed
        )
    }

    private var processedTitle: String {
        model.remixedPreviewArtifact == nil
            ? "補正後"
            : "Stem再ミックス"
    }

    private func selectionTitle(_ selection: InspectorAudioSelection) -> String {
        switch selection {
        case .input:
            "入力"
        case .corrected:
            processedTitle
        case .mastered:
            "最終版"
        }
    }

    private func unavailableDescription(_ selection: InspectorAudioSelection) -> String {
        switch selection {
        case .input:
            "音声を選ぶと解析結果を表示します。"
        case .corrected:
            "\(processedTitle)の解析が完了すると表示します。"
        case .mastered:
            "マスタリングが完了すると表示します。"
        }
    }

    @ViewBuilder
    private var importantWarnings: some View {
        if let lastError = model.session.lastError {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("重要警告")
                        .font(.title3.bold())
                    Text(lastError.message)
                        .font(.body)
                }
            } icon: {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            Text("再ミックス解析の確認事項")
                .font(.title3.bold())

            if let presentation = model.remixAnalysisPresentation {
                let issues = presentation.validation.analysisIssues
                if issues.isEmpty {
                    Text("確認事項はありません。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(issues.count)件あります。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text("\(issue.subject): \(issue.detail)")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("再ミックス解析が完了すると表示します。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

}
