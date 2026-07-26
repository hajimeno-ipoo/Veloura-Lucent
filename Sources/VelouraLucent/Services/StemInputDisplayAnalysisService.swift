import Foundation

protocol StemInputDisplayAnalyzing: Sendable {
    func analyze(
        inputURL: URL,
        analysisMode: StemAudioAnalysisMode,
        logHandler: (@Sendable (String) -> Void)?
    ) async throws -> StemModeInputDisplayAnalysisResult
}

/// 通常モードと同じ下位解析器を使い、選択した入力音源の表示・試聴情報を作ります。
///
/// これはStem補正workflowのcanonical input生成・評価ではありません。表示用の一部解析が
/// 失敗しても、取得できた波形とスペクトログラムは維持し、補正workflowを停止しません。
struct ProductionStemInputDisplayAnalyzer: StemInputDisplayAnalyzing {
    func analyze(
        inputURL: URL,
        analysisMode: StemAudioAnalysisMode,
        logHandler: (@Sendable (String) -> Void)?
    ) async throws -> StemModeInputDisplayAnalysisResult {
        let signal = try await DisplayAnalysisSupport.measure(
            "ファイル読み込み",
            logHandler: logHandler
        ) {
            try await runCancellableDetachedWorker(priority: .userInitiated) {
                try Task.checkCancellation()
                return try AudioFileService.loadAudio(from: inputURL)
            }
        }
        try Task.checkCancellation()

        let displaySnapshots = try await DisplayAnalysisSupport.measure(
            "プレビュー/スペクトログラム生成",
            logHandler: logHandler
        ) {
            try await runCancellableDetachedWorker(priority: .utility) {
                AudioFileService.makeDisplaySnapshots(from: signal)
            }
        }
        try Task.checkCancellation()

        var warnings: [String] = []

        let metrics: AudioMetricSnapshot?
        do {
            metrics = try await DisplayAnalysisSupport.measure(
                "比較指標",
                logHandler: logHandler
            ) {
                try await AudioComparisonService.analyzeConcurrently(signal: signal)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            metrics = nil
            warnings.append("比較指標: \(error.localizedDescription)")
        }
        try Task.checkCancellation()

        let audioAnalysis: AnalysisData?
        do {
            audioAnalysis = try await DisplayAnalysisSupport.measure(
                "補正解析",
                logHandler: logHandler
            ) {
                try await runCancellableDetachedWorker(priority: .utility) {
                    try Task.checkCancellation()
                    return AudioAnalyzer(mode: analysisMode.resolvedAudioAnalysisMode)
                        .analyze(signal: signal)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            audioAnalysis = nil
            warnings.append("補正解析: \(error.localizedDescription)")
        }
        try Task.checkCancellation()

        let noiseMeasurements: NoiseMeasurementSnapshot?
        do {
            noiseMeasurements = try await DisplayAnalysisSupport.measure(
                "ノイズ測定",
                logHandler: logHandler
            ) {
                try await runCancellableDetachedWorker(priority: .utility) {
                    try NoiseMeasurementService.analyzeCancellable(signal: signal)
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            noiseMeasurements = nil
            warnings.append("ノイズ測定: \(error.localizedDescription)")
        }
        try Task.checkCancellation()

        let evaluation: StemAudioEvaluationSnapshot?
        if let metrics, let noiseMeasurements {
            let request = StemAudioEvaluationRequest(
                purpose: .canonicalInput,
                includeAudioAnalyzerSnapshot: true,
                includeMasteringAnalysisSnapshot: false,
                analysisMode: analysisMode
            )
            var completedMeasurements: [StemAudioEvaluationMeasurement] = [
                .audioComparisonSnapshot,
                .noiseMeasurementSnapshot,
            ]
            if audioAnalysis != nil {
                completedMeasurements.append(.audioAnalyzerSnapshot)
            }
            evaluation = StemAudioEvaluationSnapshot(
                request: request,
                completedMeasurements: completedMeasurements,
                audioMetrics: metrics,
                noiseMeasurements: noiseMeasurements,
                audioAnalysis: audioAnalysis,
                masteringAnalysis: nil
            )
        } else {
            evaluation = nil
        }

        return StemModeInputDisplayAnalysisResult(
            evaluation: evaluation,
            metrics: metrics,
            noiseMeasurements: noiseMeasurements,
            audioAnalysis: audioAnalysis,
            previewSnapshot: displaySnapshots.previewSnapshot,
            spectrogram: displaySnapshots.spectrogram,
            warning: warnings.first
        )
    }
}
