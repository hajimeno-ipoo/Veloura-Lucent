import Foundation

enum InspectorAudioSelection: String, CaseIterable, Identifiable {
    case input
    case corrected
    case mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input:
            return AppLanguageSettings.string("入力")
        case .corrected:
            return AppLanguageSettings.string("補正後")
        case .mastered:
            return AppLanguageSettings.string("最終版")
        }
    }
}
