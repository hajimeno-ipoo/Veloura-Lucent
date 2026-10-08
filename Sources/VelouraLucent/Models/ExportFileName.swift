import Foundation

enum ExportFileName {
    static func audio(
        inputURL: URL,
        mode: ProcessingMode,
        result: String,
        format: AudioExportFormat
    ) -> String {
        let modeName = AppLanguageSettings.string(mode.title)
        return "\(songName(from: inputURL))_\(modeName)_\(result).\(format.fileExtension)"
    }

    static func processingLog(inputURL: URL, mode: ProcessingMode) -> String {
        let modeName = AppLanguageSettings.string(mode.title)
        return "\(songName(from: inputURL)) 処理ログ - \(modeName).json"
    }

    private static func songName(from inputURL: URL) -> String {
        inputURL.deletingPathExtension().lastPathComponent
    }
}
