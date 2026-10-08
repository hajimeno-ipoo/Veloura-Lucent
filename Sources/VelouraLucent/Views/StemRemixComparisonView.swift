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
            workspaceTitle: "補正後／再ミックス",
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
            comparisonSummary: "補正後と再ミックスを聴き比べます",
            sideAButtonTitle: "Aを再生",
            sideBButtonTitle: "Bを再生",
            switchButtonTitle: "A/B切替",
            activeSideATitle: "A",
            activeSideBTitle: "B",
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
