import Foundation

enum RecentActivityDomain: String, Sendable {
    case input
    case correction
    case mastering
    case export
}

struct RecentActivityEvent: Identifiable, Sendable, Equatable {
    let id: UUID
    var timestamp: Date
    let domain: RecentActivityDomain
    var title: String
    var detail: String?
    var fileName: String?
    var audioSummary: String?
    var progress: Double?
    var isRunning: Bool
    var hasFailed: Bool

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        domain: RecentActivityDomain,
        title: String,
        detail: String? = nil,
        fileName: String? = nil,
        audioSummary: String? = nil,
        progress: Double? = nil,
        isRunning: Bool = false,
        hasFailed: Bool = false
    ) {
        self.id = id
        self.timestamp = timestamp
        self.domain = domain
        self.title = title
        self.detail = detail
        self.fileName = fileName
        self.audioSummary = audioSummary
        self.progress = progress
        self.isRunning = isRunning
        self.hasFailed = hasFailed
    }
}
