import Foundation

enum ExportFileName {
    static func audio(
        inputURL: URL,
        mode: ProcessingMode,
        result: String,
        format: AudioExportFormat
    ) -> String {
        let modeName = mode == .standard ? "通常" : "ステム"
        return "\(songName(from: inputURL))_\(modeName)_\(result).\(format.fileExtension)"
    }

    static func processingLog(inputURL: URL, mode: ProcessingMode) -> String {
        let modeName = mode == .standard ? "通常" : "Stem Mode"
        return "\(songName(from: inputURL)) 処理ログ - \(modeName).json"
    }

    private static func songName(from inputURL: URL) -> String {
        inputURL.deletingPathExtension().lastPathComponent
    }
}
