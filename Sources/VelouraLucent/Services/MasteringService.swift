import Foundation

struct MasteringService {
    func process(inputFile: URL, profile: MasteringProfile, logHandler: @escaping @Sendable (String) -> Void) async throws -> URL {
        try await process(inputFile: inputFile, settings: profile.settings, logHandler: logHandler)
    }

    func process(inputFile: URL, settings: MasteringSettings, logHandler: @escaping @Sendable (String) -> Void) async throws -> URL {
        let outputURL = Self.temporaryOutputURL(for: inputFile)
        let outputPath = outputURL.path(percentEncoded: false)
        let logger = MasteringClosureLogger(logHandler: logHandler)

        try await Task.detached(priority: .userInitiated) {
            let recorder = MasteringStageTimingRecorder()
            let totalStart = DispatchTime.now().uptimeNanoseconds
            logger.log(MasteringStep.analyze.rawValue)
            logger.log("解析モード: マスタリングCPU")
            let analysisInput = try recorder.measure(label: "解析", logger: logger) {
                let signal = try AudioFileService.loadAudio(from: inputFile)
                let benchmark = MasteringAnalysisService.analyzeWithBenchmark(signal: signal)
                for stage in benchmark.stages {
                    logger.log("解析/\(masteringAnalysisStageDisplayName(stage.name)): \(formatProcessingDuration(stage.durationSeconds))")
                }
                return (signal, benchmark.analysis)
            }
            let mastered = MasteringProcessor().process(
                signal: analysisInput.0,
                analysis: analysisInput.1,
                settings: settings,
                logger: logger
            )
            logger.log(MasteringStep.save.rawValue)
            try recorder.measure(label: "保存", logger: logger) {
                try AudioFileService.saveAudio(mastered, to: outputURL)
            }
            logger.log("合計: \(formatProcessingDuration(durationSeconds(since: totalStart)))")
        }.value

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
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VelouraLucentPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let sanitizedName = shortPreviewBaseName(from: baseName)
        let shortID = String(UUID().uuidString.prefix(6)).lowercased()
        return tempDirectory
            .appendingPathComponent("\(sanitizedName)_\(shortID)")
            .appendingPathExtension(AudioFileService.outputFileExtension)
    }

    private static func shortPreviewBaseName(from fileName: String) -> String {
        let trimmed = fileName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return String(trimmed.prefix(28))
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
    case "loudness":
        "ラウドネス"
    case "truePeak":
        "トゥルーピーク"
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
