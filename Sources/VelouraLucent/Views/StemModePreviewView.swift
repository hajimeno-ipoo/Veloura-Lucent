import SwiftUI

/// Stem Modeの基本表示です。
///
/// 通常モードと同じ2mix表示に加え、独立したStem raw／補正後試聴欄を表示します。
///
/// 個別Stemは2mix試聴候補へ混在させず、専用の再生状態だけで扱います。
@MainActor
struct StemModePreviewView: View {
    @Bindable var model: StemModeWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            AudioWaveformWorkspaceView(
                preview: model.previewController,
                inputFileURL: model.inputPreviewURL,
                correctedFileURL: model.correctedRemixPreviewArtifact?.fileURL,
                masteredFileURL: model.finalPreviewArtifact?.fileURL,
                correctedTitle: processedTitle,
                correctedAccessibilityLabel: "\(processedTitle)の波形",
                playbackStatusText: mainPlaybackStatusText,
                comparisonPairLabel: comparisonPairLabel,
                comparisonPairSummary: comparisonPairSummary,
                onWillStartPlayback: model.stopAuxiliaryPreviewPlayback
            )

            StemWaveformComparisonView(model: model)

            StemRemixComparisonView(model: model)

            AverageSpectrumComparisonView(
                preview: model.previewController,
                targetTitle: targetTitle
            )

            VectorScopeView(
                preview: model.previewController,
                masteringSettings: model.masteringSettings,
                targetTitle: targetTitle
            )

            SpectrogramComparisonView(
                input: model.inputSpectrogram,
                corrected: model.correctedRemixSpectrogram,
                mastered: model.finalSpectrogram,
                correctedTitle: processedTitle
            )

            if model.isAnalyzingInput || model.isAnalyzingDisplayAudio {
                ProgressView(model.isAnalyzingInput ? "入力音源を解析しています" : "スペクトログラムを解析しています")
                    .controlSize(.small)
            } else if let error = model.inputAnalysisError ?? model.displayAnalysisError {
                Label("表示用解析の一部を取得できませんでした: \(error)", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .contain)
        .onDisappear(perform: model.stopPreviewPlayback)
    }

    private var processedTitle: String {
        model.remixedPreviewArtifact == nil
            ? "補正済み純粋加算"
            : "Stem再ミックス"
    }

    private var mainPlaybackStatusText: String {
        guard let activeTarget = model.previewController.activeTarget else {
            return "未再生"
        }
        let title = targetTitle(activeTarget)
        return switch model.previewController.playbackState(for: activeTarget) {
        case .playing:
            "\(title)を再生中"
        case .paused:
            "\(title)を一時停止中"
        case .stopped:
            "停止中"
        }
    }

    private func targetTitle(_ target: AudioPreviewTarget) -> String {
        switch target {
        case .input:
            "入力"
        case .corrected:
            processedTitle
        case .mastered:
            "最終版"
        }
    }

    private func comparisonPairLabel(_ pair: AudioComparisonPair) -> String {
        switch pair {
        case .inputVsCorrected:
            "入力 vs \(processedTitle)"
        case .inputVsMastered:
            "入力 vs 最終版"
        case .correctedVsMastered:
            "\(processedTitle) vs 最終版"
        }
    }

    private func comparisonPairSummary(_ pair: AudioComparisonPair) -> String {
        switch pair {
        case .inputVsCorrected:
            "入力と\(processedTitle)を聴き比べます"
        case .inputVsMastered:
            "最初の音と最終版をそのまま聴き比べます"
        case .correctedVsMastered:
            "\(processedTitle)とマスタリング後を聴き比べます"
        }
    }
}
