import SwiftUI

/// Stem Modeの基本表示です。
///
/// 通常モードと同じ2mix表示に加え、独立したStem raw／補正後試聴欄を表示します。
///
/// 個別Stemは2mix試聴候補へ混在させず、専用の再生状態だけで扱います。
@MainActor
struct StemModePreviewView: View {
    @Bindable var model: StemModeWorkspaceModel
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            AudioWaveformWorkspaceView(
                preview: model.previewController,
                inputFileURL: model.inputPreviewURL,
                correctedFileURL: model.correctedPureSumPreviewArtifact?.fileURL,
                masteredFileURL: model.finalPreviewArtifact?.fileURL,
                correctedTitle: waveformProcessedTitle,
                correctedAccessibilityLabel: AppLanguageSettings.format("%@の波形", AppLanguageSettings.string(waveformProcessedTitle)),
                playbackStatusText: mainPlaybackStatusText,
                comparisonPairPickerMaxWidth: 440,
                playbackInterlocks: [
                    model.stemPreviewController,
                    model.remixPreviewController,
                ]
            )

            StemWaveformComparisonView(model: model)

            StemRemixComparisonView(model: model)

            WorkspaceLazySection {
                AverageSpectrumComparisonView(
                    preview: centralAnalysisPreviewController,
                    targetTitle: centralAnalysisTargetTitle
                )
            }

            VectorScopeView(
                preview: centralAnalysisPreviewController,
                masteringSettings: model.masteringSettings,
                targetTitle: centralAnalysisTargetTitle
            )

            WorkspaceLazySection {
                SpectrogramComparisonView(
                    input: model.inputSpectrogram,
                    corrected: model.correctedRemixSpectrogram,
                    mastered: model.finalSpectrogram,
                    correctedTitle: processedTitle
                )
            }

            if model.isAnalyzingInput || model.isAnalyzingDisplayAudio {
                ProgressView(AppLanguageSettings.string(model.isAnalyzingInput ? "入力音源を解析しています" : "スペクトログラムを解析しています"))
                    .controlSize(.small)
            } else if let error = model.inputAnalysisError ?? model.displayAnalysisError {
                Label(AppLanguageSettings.format("表示用解析の一部を取得できませんでした: %@", error), systemImage: "exclamationmark.triangle")
                    .font(.body)
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .contain)
        .environment(\.locale, locale)
        .onDisappear(perform: model.stopPreviewPlayback)
    }

    private var processedTitle: String {
        model.remixedPreviewArtifact == nil
            ? "補正後"
            : "Stem再ミックス"
    }

    private var waveformProcessedTitle: String {
        "補正後"
    }

    private var centralAnalysisPreviewController: AudioPreviewController {
        model.centralAnalysisPreviewController
    }

    private func centralAnalysisTargetTitle(_ target: AudioPreviewTarget) -> String {
        let preview = centralAnalysisPreviewController
        if preview === model.stemPreviewController {
            let role = AppLanguageSettings.string(model.selectedStemPreviewRole.stemModeDisplayTitle)
            return switch target {
            case .input: String(format: AppLanguageSettings.string("%@ raw"), role)
            case .corrected: String(format: AppLanguageSettings.string("%@ 補正後"), role)
            case .mastered: "最終版"
            }
        }
        if preview === model.remixPreviewController {
            return switch target {
            case .input: "補正後"
            case .corrected: "再ミックス"
            case .mastered: "最終版"
            }
        }
        return targetTitle(target)
    }

    private var mainPlaybackStatusText: String {
        guard let activeTarget = model.previewController.activeTarget else {
            return "未再生"
        }
        let title = targetTitle(activeTarget)
        return switch model.previewController.playbackState(for: activeTarget) {
        case .playing:
            String(format: AppLanguageSettings.string("%@を再生中"), AppLanguageSettings.string(title))
        case .paused:
            String(format: AppLanguageSettings.string("%@を一時停止中"), AppLanguageSettings.string(title))
        case .stopped:
            "停止中"
        }
    }

    private func targetTitle(_ target: AudioPreviewTarget) -> String {
        switch target {
        case .input:
            "入力"
        case .corrected:
            "補正後"
        case .mastered:
            "最終版"
        }
    }

}
