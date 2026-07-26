import SwiftUI

@MainActor
struct StemModeInspectorView: View {
    @Bindable var model: StemModeWorkspaceModel
    @Bindable var modelManager: StemModelManager
    @Binding var windowBackgroundMaterialAmount: Double
    let isWindowFullScreen: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                StemModeInspectorSettingsPanel(
                    model: model,
                    modelManager: modelManager,
                    windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                    isWindowFullScreen: isWindowFullScreen
                )
                Divider()
                StemModeInspectorAudioPanel(model: model)
            }
            .padding(14)
            .velouraTransientOverlayScrollIndicators()
        }
        .scrollContentBackground(.hidden)
    }
}

private enum StemModeInspectorSettingsSection: String, CaseIterable, Identifiable {
    case correction
    case mastering
    case app

    var id: String { rawValue }
    var title: String {
        switch self {
        case .correction: "補正"
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
    let isWindowFullScreen: Bool
    @SceneStorage("stemModeInspectorSettingsSelectedSection")
    private var selectedSectionRawValue = StemModeInspectorSettingsSection.correction.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("詳細設定")
                    .font(.headline)
                LiquidGlassSegmentedPicker(
                    title: "詳細設定",
                    options: StemModeInspectorSettingsSection.allCases,
                    selection: selectedSectionBinding,
                    label: \.title,
                    isDisabled: model.isRunActive || model.isStartingRun
                )
            }

            switch selectedSection {
            case .correction:
                StemModeCorrectionSettingsView(model: model)
                    .disabled(model.isCorrectionSettingsDisabled)
            case .mastering:
                StemModeMasteringSettingsView(model: model)
                    .disabled(model.isMasteringSettingsDisabled)
            case .app:
                VStack(alignment: .leading, spacing: 18) {
                    AppSettingsPanel(
                        windowBackgroundMaterialAmount: $windowBackgroundMaterialAmount,
                        isWindowFullScreen: isWindowFullScreen
                    )
                    StemModeAnalysisModeSettings(model: model)
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
            Text("解析モード")
                .font(.headline)

            LiquidGlassSegmentedPicker(
                title: "解析モード",
                options: AudioAnalysisMode.allCases,
                selection: $model.selectedAnalysisMode,
                label: \.title,
                isDisabled: model.isRunActive || model.isStartingRun
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
            Text("補正開始時にrunへ固定し、Stem解析とDSP内部解析へ同じ方式を使用します。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

@MainActor
private struct StemModeInspectorAudioPanel: View {
    @Bindable var model: StemModeWorkspaceModel
    @State private var selectedAudio: InspectorAudioSelection = .input
    @State private var isCompletionReportPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("解析結果と品質確認")
                    .font(.title3.bold())
                Spacer()
                if model.isAnalyzingDisplayAudio {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("解析中")
                }
            }

            LiquidGlassSegmentedPicker(
                title: "確認する音源",
                options: InspectorAudioSelection.allCases,
                selection: $selectedAudio,
                label: \.title
            )

            if let metrics = selectedMetrics {
                metricsGrid(metrics)
            } else {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(selectedAudio.title)は未解析です")
                            .font(.headline)
                        Text(unavailableDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }

            if let report = model.qualityReports?.audioQuality {
                qualityWarnings(report)
            }

            importantWarnings
            completionReportControl
        }
    }

    private func metricsGrid(_ metrics: AudioMetricSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            metricCell(
                title: "ラウドネス",
                value: String(format: "%.1f LUFS", metrics.integratedLoudnessLUFS),
                color: .primary
            )
            metricCell(
                title: "True Peak",
                value: String(format: "%.2f dBTP", metrics.truePeakDBFS),
                color: metrics.truePeakDBFS > -0.3 ? .red : .primary
            )
            metricCell(
                title: "ダイナミクス",
                value: String(format: "%.1f dB", metrics.crestFactorDB),
                color: .primary
            )
            metricCell(
                title: "ステレオ幅",
                value: String(format: "%.2f", metrics.stereoWidth),
                color: .primary
            )
        }
    }

    private func metricCell(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private func qualityWarnings(_ report: AudioQualityReport) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("品質警告")
                    .font(.headline)
                Spacer()
                Text(severityText(report.severity))
                    .foregroundStyle(severityColor(report.severity))
            }

            if report.items.isEmpty {
                Label(
                    "数値上の追加候補はありません。最終版を聴いて違和感がないか確認してください。",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.callout)
                .foregroundStyle(.green)
            } else {
                ForEach(Array(report.items.enumerated()), id: \.offset) { _, item in
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(item.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(severityColor(item.severity))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var importantWarnings: some View {
        let issues = model.remixAnalysisPresentation?.validation.analysisIssues ?? []
        if let lastError = model.session.lastError {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("重要警告")
                        .font(.headline)
                    Text(lastError.message)
                        .font(.callout)
                }
            } icon: {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        } else if !issues.isEmpty {
            DisclosureGroup("再ミックス解析の確認事項（\(issues.count)件）") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        Text("\(issue.subject): \(issue.detail)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private var completionReportControl: some View {
        LiquidGlassActionButton(
            title: "完了後レポートを開く",
            systemImage: "doc.text.magnifyingglass",
            isDisabled: model.qualityReports?.completion == nil
        ) {
            isCompletionReportPresented = true
        }
        .popover(isPresented: $isCompletionReportPresented, arrowEdge: .leading) {
            if let report = model.qualityReports?.completion {
                CompletionReportPopoverView(report: report)
            }
        }
    }

    private var selectedMetrics: AudioMetricSnapshot? {
        switch selectedAudio {
        case .input: model.inputMetrics
        case .corrected: model.correctedRemixMetrics
        case .mastered: model.finalMetrics
        }
    }

    private var unavailableDescription: String {
        switch selectedAudio {
        case .input: "補正段で入力解析が完了すると表示します。"
        case .corrected: "補正段で補正済み4Stemの再ミックス解析が完了すると表示します。"
        case .mastered: "マスタリングが完了すると表示します。"
        }
    }

    private func severityText(_ severity: AudioQualityReportSeverity) -> String {
        switch severity {
        case .info: "確認"
        case .caution: "注意"
        case .warning: "警告"
        }
    }

    private func severityColor(_ severity: AudioQualityReportSeverity) -> Color {
        switch severity {
        case .info: .secondary
        case .caution: .orange
        case .warning: .red
        }
    }
}
