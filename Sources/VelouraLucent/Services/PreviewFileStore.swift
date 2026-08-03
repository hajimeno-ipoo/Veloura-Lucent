import Foundation

enum PreviewFileStore {
    static let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("VelouraLucentPreview", isDirectory: true)

    static func temporaryOutputURL(baseName: String, suffix: String) -> URL {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sanitizedName = shortPreviewBaseName(from: baseName)
        let shortID = String(UUID().uuidString.prefix(6)).lowercased()
        return directory
            .appendingPathComponent("\(sanitizedName)_\(suffix)_\(shortID)")
            .appendingPathExtension(AudioFileService.outputFileExtension)
    }

    static func removeAllPreviewFiles() {
        try? FileManager.default.removeItem(at: directory)
    }

    static func removeOwnedPreviewFileIfPresent(_ url: URL?) {
        guard let url else { return }
        let normalized = url.standardizedFileURL
        guard normalized.deletingLastPathComponent() == directory.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: normalized)
    }

    private static func shortPreviewBaseName(from fileName: String) -> String {
        let trimmed = fileName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return String(trimmed.prefix(24))
    }
}
