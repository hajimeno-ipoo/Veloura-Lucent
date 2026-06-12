import SwiftUI

enum VelouraWorkspaceSection: String, CaseIterable, Identifiable {
    case comparison
    case metrics
    case logs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .comparison:
            return "比較"
        case .metrics:
            return "数値"
        case .logs:
            return "ログ"
        }
    }

    var systemImage: String {
        switch self {
        case .comparison:
            return "waveform.and.magnifyingglass"
        case .metrics:
            return "chart.bar.xaxis"
        case .logs:
            return "list.bullet.rectangle"
        }
    }
}
