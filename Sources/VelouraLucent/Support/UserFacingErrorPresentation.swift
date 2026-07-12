import Foundation

enum UserFacingErrorOperation {
    case inputAnalysis
    case correction
    case mastering
    case correctedExport
    case masteredExport
}

struct UserFacingErrorPresentation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let recoverySuggestion: String
    let technicalDetails: String

    var alertMessage: String {
        "\(message)\n\n\(recoverySuggestion)"
    }

    static func make(for error: Error, operation: UserFacingErrorOperation) -> Self {
        let technicalDetails = error.localizedDescription

        if let appError = error as? AppError {
            switch appError {
            case .audioReadFailed:
                return Self(
                    title: "音声ファイルを読み込めませんでした",
                    message: "選択した音声ファイルを開けませんでした。",
                    recoverySuggestion: "ファイルが破損していないか、読み取り権限があるか確認してください。",
                    technicalDetails: technicalDetails
                )
            case .audioWriteFailed:
                return Self(
                    title: "音声ファイルを書き出せませんでした",
                    message: "保存先へ音声ファイルを書き込めませんでした。",
                    recoverySuggestion: "保存先の空き容量と書き込み権限を確認してください。",
                    technicalDetails: technicalDetails
                )
            case .outputNotFound:
                break
            }
        }

        switch operation {
        case .inputAnalysis:
            return Self(
                title: "音声ファイルを解析できませんでした",
                message: "選択した音声ファイルの読み込みまたは解析を完了できませんでした。",
                recoverySuggestion: "対応している音声ファイルを選び、ファイルが破損していないか確認してください。",
                technicalDetails: technicalDetails
            )
        case .correction:
            return Self(
                title: "補正処理に失敗しました",
                message: "音声の補正を完了できませんでした。",
                recoverySuggestion: "入力ファイルを確認して、もう一度補正を実行してください。",
                technicalDetails: technicalDetails
            )
        case .mastering:
            return Self(
                title: "マスタリングに失敗しました",
                message: "最終版の作成を完了できませんでした。",
                recoverySuggestion: "補正後の音声を確認して、もう一度マスタリングを実行してください。",
                technicalDetails: technicalDetails
            )
        case .correctedExport:
            return Self(
                title: "補正後の音声を書き出せませんでした",
                message: "補正後の音声を指定した保存先へ書き込めませんでした。",
                recoverySuggestion: "保存先の空き容量と書き込み権限を確認してください。",
                technicalDetails: technicalDetails
            )
        case .masteredExport:
            return Self(
                title: "最終版を書き出せませんでした",
                message: "最終版を指定した保存先へ書き込めませんでした。",
                recoverySuggestion: "保存先の空き容量と書き込み権限を確認してください。",
                technicalDetails: technicalDetails
            )
        }
    }
}
