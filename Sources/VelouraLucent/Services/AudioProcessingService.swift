import Foundation

struct AudioProcessingService {
    func process(
        inputFile: URL,
        denoiseStrength: DenoiseStrength = .balanced,
        analysisMode: AudioAnalysisMode = .auto,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        let outputURL = Self.temporaryOutputURL(for: inputFile)
        let outputPath = outputURL.path(percentEncoded: false)

        let logger = ClosureLogger(logHandler: logHandler)
        try await Task.detached(priority: .userInitiated) {
            try NativeAudioProcessor().process(
                inputFile: inputFile,
                outputFile: outputURL,
                denoiseStrength: denoiseStrength,
                analysisMode: analysisMode,
                logger: logger
            )
        }.value

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
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VelouraLucentPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let sanitizedName = shortPreviewBaseName(from: fileName)
        let shortID = String(UUID().uuidString.prefix(6)).lowercased()
        return tempDirectory
            .appendingPathComponent("\(sanitizedName)_lifter_\(shortID)")
            .appendingPathExtension(AudioFileService.outputFileExtension)
    }

    private static func shortPreviewBaseName(from fileName: String) -> String {
        let trimmed = fileName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return String(trimmed.prefix(24))
    }
}

private struct ClosureLogger: AudioProcessingLogger, Sendable {
    let logHandler: @Sendable (String) -> Void

    func log(_ message: String) {
        logHandler(message)
    }
}
