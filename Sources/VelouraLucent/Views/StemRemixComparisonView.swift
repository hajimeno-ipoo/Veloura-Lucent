import SwiftUI

/// 純粋加算と再ミックスを、通常モードと同じ波形・試聴UIで比較します。
@MainActor
struct StemRemixComparisonView: View {
    @Bindable var model: StemModeWorkspaceModel

    private var preview: AudioPreviewController {
        model.remixPreviewController
    }

    var body: some View {
        AudioWaveformWorkspaceView(
            preview: preview,
            workspaceTitle: "補正後／再ミックス A/B",
            tracks: [
                AudioWaveformTrackPresentation(
                    target: .input,
                    title: "補正後",
                    tint: .blue,
                    fileURL: model.correctedPureSumPreviewArtifact?.fileURL,
                    accessibilityLabel: "補正後の波形"
                ),
                AudioWaveformTrackPresentation(
                    target: .corrected,
                    title: "再ミックス",
                    tint: .green,
                    fileURL: model.remixedPreviewArtifact?.fileURL,
                    accessibilityLabel: "再ミックスの波形"
                ),
            ],
            comparisonSummary: "Aは補正後、Bは現在の再ミックスです",
            sideAButtonTitle: "補正後を再生",
            sideBButtonTitle: "再ミックスを再生",
            switchButtonTitle: "補正後／再ミックス切替",
            activeSideATitle: "補正後",
            activeSideBTitle: "再ミックス",
            volumeAccessibilityLabel: "再ミックス比較音量",
            loudnessHelp: "補正後と再ミックスの音量差を試聴時だけ揃えます",
            resetToken: resetToken,
            playbackInterlocks: [
                model.previewController,
                model.stemPreviewController,
            ]
        )
        .accessibilityElement(children: .contain)
    }

    private var resetToken: String {
        [
            model.correctedPureSumPreviewArtifact?.fileURL.path ?? "",
            model.remixedPreviewArtifact?.fileURL.path ?? "",
        ].joined(separator: "|")
    }

}
