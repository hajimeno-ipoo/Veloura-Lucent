import SwiftUI

/// 選択中Stemのraw／補正後を、通常モードと同じ波形・試聴UIで比較します。
@MainActor
struct StemWaveformComparisonView: View {
    @Bindable var model: StemModeWorkspaceModel

    private var preview: AudioPreviewController {
        model.stemPreviewController
    }

    var body: some View {
        AudioWaveformWorkspaceView(
            preview: preview,
            workspaceTitle: "\(model.availableStemRoles.count) Stem 波形",
            playbackStatusText: playbackStatusText,
            tracks: [
                AudioWaveformTrackPresentation(
                    target: .input,
                    title: "分離直後（raw）",
                    tint: .blue,
                    fileURL: model.selectedRawStemPreviewURL,
                    accessibilityLabel: "\(model.selectedStemPreviewRole.stemModeDisplayTitle)の分離直後波形"
                ),
                AudioWaveformTrackPresentation(
                    target: .corrected,
                    title: "補正後Stem",
                    tint: .green,
                    fileURL: model.selectedCorrectedStemPreviewURL,
                    accessibilityLabel: "\(model.selectedStemPreviewRole.stemModeDisplayTitle)の補正後波形"
                ),
            ],
            comparisonSummary: "選択中Stemの分離直後と補正後を同じ位置で聴き比べます",
            sideAButtonTitle: "rawを再生",
            sideBButtonTitle: "補正後を再生",
            switchButtonTitle: "raw／補正後切替",
            activeSideATitle: "raw",
            activeSideBTitle: "補正後",
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
                .font(.callout.weight(.semibold))
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
        case .playing: "\(targetTitle)を再生中"
        case .paused: "\(targetTitle)を一時停止中"
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
