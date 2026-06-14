import Foundation

enum InspectorAudioSelection: String, CaseIterable, Identifiable {
    case input
    case corrected
    case mastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .input:
            return "入力"
        case .corrected:
            return "補正後"
        case .mastered:
            return "最終版"
        }
    }
}
