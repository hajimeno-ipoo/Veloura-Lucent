import Foundation

enum AppError: LocalizedError {
    case outputNotFound(String)
    case audioReadFailed
    case audioWriteFailed

    var errorDescription: String? {
        switch self {
        case .outputNotFound(let path):
            return "出力ファイルが見つかりません: \(path)"
        case .audioReadFailed:
            return "音声ファイルの読み込みに失敗しました。"
        case .audioWriteFailed:
            return "音声ファイルの書き出しに失敗しました。"
        }
    }
}
