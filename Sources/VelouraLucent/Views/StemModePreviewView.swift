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
                onWillStartPlayback: model.stopStemPreviewPlayback
            )

            StemWaveformComparisonView(model: model)

            AverageSpectrumComparisonView(preview: model.previewController)

            VectorScopeView(
                preview: model.previewController,
                masteringSettings: model.masteringSettings
            )

            SpectrogramComparisonView(
                input: model.inputSpectrogram,
                corrected: model.correctedRemixSpectrogram,
                mastered: model.finalSpectrogram
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
}
