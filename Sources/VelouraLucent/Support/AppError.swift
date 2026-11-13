import Foundation

enum AppError: LocalizedError {
    case outputNotFound(String)
    case audioReadFailed
    case audioWriteFailed
    case audioExportExceedsPCMRange

    var errorDescription: String? {
        switch self {
        case .outputNotFound(let path):
            return "出力ファイルが見つかりません: \(path)"
        case .audioReadFailed:
            return "音声ファイルの読み込みに失敗しました。"
        case .audioWriteFailed:
            return "音声ファイルの書き出しに失敗しました。"
        case .audioExportExceedsPCMRange:
            return AppLanguageSettings.string("0 dBFSを超える音声をこの形式で書き出すと、波形の頂点が切れるため書き出しを中止しました。")
                + "\n" + AppLanguageSettings.string("「高品質保存」（32-bit float WAV）を選んで書き出してください。")
        }
    }
}
