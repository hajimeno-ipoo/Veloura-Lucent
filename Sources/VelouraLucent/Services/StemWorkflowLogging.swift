import Foundation

enum StemWorkflowLogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}

struct StemWorkflowLogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let runID: UUID
    let timestamp: Date
    let level: StemWorkflowLogLevel
    let step: StemWorkflowStep?
    let message: String

    init(
        id: UUID = UUID(),
        runID: UUID,
        timestamp: Date = Date(),
        level: StemWorkflowLogLevel,
        step: StemWorkflowStep?,
        message: String
    ) {
        self.id = id
        self.runID = runID
        self.timestamp = timestamp
        self.level = level
        self.step = step
        self.message = message
    }
}
