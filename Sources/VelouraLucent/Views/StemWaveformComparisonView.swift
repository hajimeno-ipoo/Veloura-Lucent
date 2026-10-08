import SwiftUI

/// 選択中Stemのraw／補正後を、通常モードと同じ波形・試聴UIで比較します。
@MainActor
struct StemWaveformComparisonView: View {
    @Bindable var model: StemModeWorkspaceModel
    @Environment(\.locale) private var locale

    private var preview: AudioPreviewController {
        model.stemPreviewController
    }

    var body: some View {
        AudioWaveformWorkspaceView(
            preview: preview,
            workspaceTitle: String(format: AppLanguageSettings.string("%d Stem 波形"), model.availableStemRoles.count),
            playbackStatusText: playbackStatusText,
            tracks: [
                AudioWaveformTrackPresentation(
                    target: .input,
                    title: "分離直後（raw）",
                    tint: .blue,
                    fileURL: model.selectedRawStemPreviewURL,
                    accessibilityLabel: String(format: AppLanguageSettings.string("%@の分離直後波形"), AppLanguageSettings.string(model.selectedStemPreviewRole.stemModeDisplayTitle))
                ),
                AudioWaveformTrackPresentation(
                    target: .corrected,
                    title: "補正後Stem",
                    tint: .green,
                    fileURL: model.selectedCorrectedStemPreviewURL,
                    accessibilityLabel: String(format: AppLanguageSettings.string("%@の補正後波形"), AppLanguageSettings.string(model.selectedStemPreviewRole.stemModeDisplayTitle))
                ),
            ],
            comparisonSummary: "分離直後（raw）と補正後Stemを聴き比べます",
            sideAButtonTitle: "Aを再生",
            sideBButtonTitle: "Bを再生",
            switchButtonTitle: "A/B切替",
            activeSideATitle: "A",
            activeSideBTitle: "B",
            volumeAccessibilityLabel: "Stem試聴音量",
            loudnessHelp: "rawと補正後の音量差を試聴時だけ揃えます",
            resetToken: resetToken,
            topAccessory: AnyView(rolePicker),
            playbackInterlocks: [
                model.previewController,
                model.remixPreviewController,
            ]
        )
        .accessibilityElement(children: .contain)
        .environment(\.locale, locale)
        .onAppear(perform: model.refreshSelectedStemPreviewSources)
        .onChange(of: model.selectedRawStemPreviewURL) {
            model.refreshSelectedStemPreviewSources()
        }
        .onChange(of: model.selectedCorrectedStemPreviewURL) {
            model.refreshSelectedStemPreviewSources()
        }
    }

    private var rolePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("表示するStem")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            LiquidGlassSegmentedPicker(
                title: "表示するStem",
                options: model.availableStemRoles,
                selection: mainActorBinding(
                    get: { model.selectedStemPreviewRole },
                    set: { model.selectStemPreviewRole($0) }
                ),
                label: \.stemModeDisplayTitle,
                maxWidth: 448
            )
        }
    }

    private var playbackStatusText: String {
        guard let activeTarget = preview.activeTarget else { return "未再生" }
        let targetTitle = activeTarget == .input ? "raw" : "補正後Stem"
        return switch preview.playbackState(for: activeTarget) {
        case .playing: String(format: AppLanguageSettings.string("%@を再生中"), AppLanguageSettings.string(targetTitle))
        case .paused: String(format: AppLanguageSettings.string("%@を一時停止中"), AppLanguageSettings.string(targetTitle))
        case .stopped: "停止中"
        }
    }

    private var resetToken: String {
        [
            model.selectedStemPreviewRole.rawValue,
            model.selectedRawStemPreviewURL?.path ?? "",
            model.selectedCorrectedStemPreviewURL?.path ?? "",
        ].joined(separator: "|")
    }

}
