import Foundation

struct MasteringService {
    func process(inputFile: URL, profile: MasteringProfile, logHandler: @escaping @Sendable (String) -> Void) async throws -> URL {
        try await process(inputFile: inputFile, settings: profile.settings, logHandler: logHandler)
    }

    func process(
        inputFile: URL,
        settings: MasteringSettings,
        initialAnalysis: MasteringAnalysis? = nil,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot? = nil,
        originalReferenceFile: URL? = nil,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot? = nil,
        diagnosticOutputDirectory: URL? = nil,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        let outputURL = Self.temporaryOutputURL(for: inputFile)
        let outputPath = outputURL.path(percentEncoded: false)
        let logger = MasteringClosureLogger(logHandler: logHandler)

        do {
            try await runCancellableDetachedWorker {
                let recorder = MasteringStageTimingRecorder()
                let totalStart = DispatchTime.now().uptimeNanoseconds
                try Task.checkCancellation()
                logger.start(MasteringStep.loadAudio)
                logger.log(MasteringStep.loadAudio.rawValue)
                logger.log("解析モード: マスタリングCPU")
                let signal = try recorder.measure(label: "読み込み", logger: logger) {
                    try AudioFileService.loadAudio(from: inputFile)
                }
                try Task.checkCancellation()
                let originalReferenceSignal: AudioSignal?
                if let originalReferenceFile {
                    originalReferenceSignal = try recorder.measure(label: "原音参照読み込み", logger: logger) {
                        try AudioFileService.loadAudio(from: originalReferenceFile)
                    }
                } else {
                    originalReferenceSignal = nil
                }
                logger.complete(MasteringStep.loadAudio)

                try Task.checkCancellation()
                let analysis: MasteringAnalysis
                logger.start(MasteringStep.analyze)
                logger.log(MasteringStep.analyze.rawValue)
                if let initialAnalysis {
                    analysis = initialAnalysis
                    logger.skip(MasteringStep.analyze, reason: "既存の解析結果を使用")
                    logger.log("解析: 既存結果を使用")
                } else {
                    analysis = recorder.measure(label: "解析", logger: logger) {
                        let benchmark = MasteringAnalysisService.analyzeWithBenchmark(signal: signal)
                        for stage in benchmark.stages {
                            logger.log("解析/\(masteringAnalysisStageDisplayName(stage.name)): \(formatProcessingDuration(stage.durationSeconds))")
                        }
                        return benchmark.analysis
                    }
                    logger.complete(MasteringStep.analyze)
                }

                try Task.checkCancellation()
                let routeNoiseMeasurements: NoiseMeasurementSnapshot
                logger.start(MasteringStep.routeNoiseMeasurement)
                logger.log(MasteringStep.routeNoiseMeasurement.rawValue)
                if let referenceNoiseMeasurements {
                    routeNoiseMeasurements = referenceNoiseMeasurements
                    logger.skip(MasteringStep.routeNoiseMeasurement, reason: "既存の測定結果を使用")
                    logger.log("ノイズ測定: 既存結果を使用")
                } else {
                    routeNoiseMeasurements = recorder.measure(label: "ルート用ノイズ測定", logger: logger) {
                        NoiseMeasurementService.analyze(signal: signal)
                    }
                    logger.complete(MasteringStep.routeNoiseMeasurement)
                }
                try Task.checkCancellation()
                let mastered = try MasteringProcessor().process(
                    signal: signal,
                    analysis: analysis,
                    settings: settings,
                    referenceNoiseMeasurements: routeNoiseMeasurements,
                    originalReferenceSignal: originalReferenceSignal,
                    originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
                    diagnosticOutputDirectory: diagnosticOutputDirectory,
                    logger: logger
                )
                try Task.checkCancellation()
                logger.start(MasteringStep.save)
                logger.log(MasteringStep.save.rawValue)
                try recorder.measure(label: "保存", logger: logger) {
                    try AudioFileService.saveAudio(mastered, to: outputURL)
                }
                logger.complete(MasteringStep.save)
                logger.log("合計: \(formatProcessingDuration(durationSeconds(since: totalStart)))")
            }
            try Task.checkCancellation()
        } catch is CancellationError {
            removeFileIfPresent(at: outputURL)
            throw CancellationError()
        }

        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw AppError.outputNotFound(outputPath)
        }

        return outputURL
    }

    static func defaultOutputURL(for inputFile: URL) -> URL {
        let directory = inputFile.deletingLastPathComponent()
        let fileName = inputFile.deletingPathExtension().lastPathComponent
        let baseName = fileName.hasSuffix("_mastered") ? fileName : "\(fileName)_mastered"
        return directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(AudioFileService.outputFileExtension)
    }

    static func temporaryOutputURL(for inputFile: URL) -> URL {
        let fileName = inputFile.deletingPathExtension().lastPathComponent
        let baseName = fileName.hasSuffix("_mastered") ? fileName : "\(fileName)_mastered"
        return PreviewFileStore.temporaryOutputURL(baseName: baseName, suffix: "mas")
    }
}

private struct MasteringClosureLogger: AudioProcessingLogger, Sendable {
    let logHandler: @Sendable (String) -> Void

    func log(_ message: String) {
        logHandler(message)
    }
}

func formatProcessingDuration(_ seconds: Double) -> String {
    String(format: "%.2f秒", seconds)
}

private func masteringAnalysisStageDisplayName(_ name: String) -> String {
    switch name {
    case "stft":
        "STFT"
    case "streamingSTFTAndSpectralSummaryCPU":
        "STFT+帯域集計(CPU)"
    case "streamingSTFTAndSpectralSummaryMetal":
        "STFT+帯域集計(Metal)"
    case "loudness":
        "ラウドネス"
    case "truePeak":
        "トゥルーピーク"
    case "spectralSummaryCPU":
        "帯域集計(CPU)"
    case "spectralSummaryMetal":
        "帯域集計(Metal)"
    case "spectralSummary":
        "帯域集計"
    case "stereoWidth":
        "ステレオ幅"
    default:
        name
    }
}

private final class MasteringStageTimingRecorder {
    private(set) var totalDurationSeconds: Double = 0

    func measure<T>(label: String, logger: AudioProcessingLogger, work: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let result = try work()
            let duration = durationSeconds(since: start)
            totalDurationSeconds += duration
            logger.log("\(label): \(formatProcessingDuration(duration))")
            return result
        } catch {
            let duration = durationSeconds(since: start)
            totalDurationSeconds += duration
            logger.log("\(label): \(formatProcessingDuration(duration))")
            throw error
        }
    }

    private func durationSeconds(since start: UInt64) -> Double {
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }
}

private func durationSeconds(since start: UInt64) -> Double {
    let end = DispatchTime.now().uptimeNanoseconds
    return Double(end - start) / 1_000_000_000
}
