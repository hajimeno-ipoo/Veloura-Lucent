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
            workspaceTitle: "純粋加算／再ミックス A/B",
            tracks: [
                AudioWaveformTrackPresentation(
                    target: .input,
                    title: "補正済み純粋加算",
                    tint: .blue,
                    fileURL: model.correctedPureSumPreviewArtifact?.fileURL,
                    accessibilityLabel: "補正済み純粋加算の波形"
                ),
                AudioWaveformTrackPresentation(
                    target: .corrected,
                    title: "Stem再ミックス",
                    tint: .green,
                    fileURL: model.remixedPreviewArtifact?.fileURL,
                    accessibilityLabel: "Stem再ミックスの波形"
                ),
            ],
            comparisonSummary: "Aはgain・pan・reverbなしの純粋加算、Bは現在の再ミックスです",
            sideAButtonTitle: "純粋加算を再生",
            sideBButtonTitle: "再ミックスを再生",
            switchButtonTitle: "純粋加算／再ミックス切替",
            activeSideATitle: "純粋加算",
            activeSideBTitle: "再ミックス",
            volumeAccessibilityLabel: "再ミックス比較音量",
            loudnessHelp: "純粋加算と再ミックスの音量差を試聴時だけ揃えます",
            resetToken: resetToken,
            onWillStartPlayback: beginPlayback
        )
        .accessibilityElement(children: .contain)
    }

    private var resetToken: String {
        [
            model.correctedPureSumPreviewArtifact?.fileURL.path ?? "",
            model.remixedPreviewArtifact?.fileURL.path ?? "",
        ].joined(separator: "|")
    }

    private func beginPlayback() {
        model.stopTwoMixPreviewPlayback()
        model.stopStemPreviewPlayback()
    }
}
