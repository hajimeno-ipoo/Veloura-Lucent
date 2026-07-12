import Foundation

struct AudioProcessingService {
    func process(
        inputFile: URL,
        denoiseStrength: DenoiseStrength = .balanced,
        correctionSettings: CorrectionSettings? = nil,
        analysisMode: AudioAnalysisMode = .auto,
        initialAnalysis: AnalysisData? = nil,
        initialNoiseMeasurements: NoiseMeasurementSnapshot? = nil,
        diagnosticOutputDirectory: URL? = nil,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        let outputURL = Self.temporaryOutputURL(for: inputFile)
        let outputPath = outputURL.path(percentEncoded: false)

        let logger = ClosureLogger(logHandler: logHandler)
        do {
            try await runCancellableDetachedWorker {
                try NativeAudioProcessor().process(
                    inputFile: inputFile,
                    outputFile: outputURL,
                    denoiseStrength: denoiseStrength,
                    correctionSettings: correctionSettings ?? denoiseStrength.settings,
                    analysisMode: analysisMode,
                    initialAnalysis: initialAnalysis,
                    initialNoiseMeasurements: initialNoiseMeasurements,
                    diagnosticOutputDirectory: diagnosticOutputDirectory,
                    logger: logger
                )
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
        return directory
            .appendingPathComponent("\(fileName)_lifter")
            .appendingPathExtension(AudioFileService.outputFileExtension)
    }

    static func temporaryOutputURL(for inputFile: URL) -> URL {
        let fileName = inputFile.deletingPathExtension().lastPathComponent
        return PreviewFileStore.temporaryOutputURL(baseName: fileName, suffix: "lifter")
    }
}

private struct ClosureLogger: AudioProcessingLogger, Sendable {
    let logHandler: @Sendable (String) -> Void

    func log(_ message: String) {
        logHandler(message)
    }
}
