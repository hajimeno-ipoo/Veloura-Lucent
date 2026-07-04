import SwiftUI

enum WorkspaceFooterStageState {
    case pending(String)
    case active(String)
    case complete(String)
    case failed(String)

    var label: String {
        switch self {
        case let .pending(label), let .active(label), let .complete(label), let .failed(label):
            return label
        }
    }

    var systemImage: String {
        switch self {
        case .pending:
            return "circle"
        case .active:
            return "dot.circle.fill"
        case .complete:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending:
            return .secondary
        case .active:
            return ProcessingStatusColors.active
        case .complete:
            return ProcessingStatusColors.complete
        case .failed:
            return .red
        }
    }

    var isActive: Bool {
        if case .active = self {
            return true
        }
        return false
    }
}

struct WorkspaceFooterStage: Identifiable {
    let id: String
    let title: String
    let state: WorkspaceFooterStageState
    let progress: Double?

    init(id: String, title: String, state: WorkspaceFooterStageState, progress: Double? = nil) {
        self.id = id
        self.title = title
        self.state = state
        self.progress = progress.map { min(max($0, 0), 1) }
    }
}
