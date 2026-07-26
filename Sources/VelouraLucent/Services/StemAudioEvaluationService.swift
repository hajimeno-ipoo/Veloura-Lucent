import Foundation

enum StemAudioEvaluationService {
    static func evaluate(
        signal: AudioSignal,
        request: StemAudioEvaluationRequest
    ) async throws -> StemAudioEvaluationSnapshot {
        try Task.checkCancellation()
        try await validate(signal: signal)

        // Stem成果物の44.1 kHz信号は音声正本のまま保持します。通常モードの解析器は
        // 48 kHz入力で検証され、LoudnessMeasurementServiceのK-weighting係数も48 kHz用のため、
        // 解析・品質評価だけに使う独立copyを既存AVAudioConverter経路で作ります。
        let analysisSignal = try await runCancellableDetachedWorker(priority: .utility) {
            try Task.checkCancellation()
            let converted = try AudioSignalSampleRateConverter.convert(signal, to: 48_000)
            try Task.checkCancellation()
            return converted
        }

        let audioMetrics = try await AudioComparisonService.analyzeConcurrently(signal: analysisSignal)
        try Task.checkCancellation()

        let noiseMeasurements = try await runCancellableDetachedWorker(priority: .utility) {
            try NoiseMeasurementService.analyzeCancellable(signal: analysisSignal)
        }
        try Task.checkCancellation()

        let audioAnalysis: AnalysisData?
        if request.includeAudioAnalyzerSnapshot {
            audioAnalysis = try await runCancellableDetachedWorker(priority: .utility) {
                try Task.checkCancellation()
                let analysis = AudioAnalyzer(
                    mode: request.analysisMode.resolvedAudioAnalysisMode
                ).analyze(signal: analysisSignal)
                try Task.checkCancellation()
                return analysis
            }
        } else {
            audioAnalysis = nil
        }

        let masteringAnalysis: MasteringAnalysis?
        if request.includeMasteringAnalysisSnapshot {
            masteringAnalysis = try await runCancellableDetachedWorker(priority: .utility) {
                try Task.checkCancellation()
                let analysis = MasteringAnalysisService.analyze(signal: analysisSignal)
                try Task.checkCancellation()
                return analysis
            }
        } else {
            masteringAnalysis = nil
        }

        try Task.checkCancellation()
        return StemAudioEvaluationSnapshot(
            request: request,
            completedMeasurements: request.requestedMeasurements,
            audioMetrics: audioMetrics,
            noiseMeasurements: noiseMeasurements,
            audioAnalysis: audioAnalysis,
            masteringAnalysis: masteringAnalysis
        )
    }

    private static func validate(signal: AudioSignal) async throws {
        try await runCancellableDetachedWorker(priority: .utility) {
            try Task.checkCancellation()
            guard !signal.channels.isEmpty else {
                throw StemAudioEvaluationError.noChannels
            }
            guard signal.sampleRate.isFinite, signal.sampleRate > 0 else {
                throw StemAudioEvaluationError.invalidSampleRate
            }

            let expectedFrameCount = signal.channels[0].count
            guard expectedFrameCount > 0 else {
                throw StemAudioEvaluationError.emptySignal
            }

            for (channelIndex, channel) in signal.channels.enumerated() {
                try Task.checkCancellation()
                guard channel.count == expectedFrameCount else {
                    throw StemAudioEvaluationError.inconsistentFrameCount(
                        channelIndex: channelIndex,
                        expected: expectedFrameCount,
                        actual: channel.count
                    )
                }

                for (frameIndex, sample) in channel.enumerated() {
                    if frameIndex.isMultiple(of: 4_096) {
                        try Task.checkCancellation()
                    }
                    guard sample.isFinite else {
                        throw StemAudioEvaluationError.nonFiniteSample(
                            channelIndex: channelIndex,
                            frameIndex: frameIndex
                        )
                    }
                }
            }
        }
    }
}
