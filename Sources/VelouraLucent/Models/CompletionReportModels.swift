import Foundation

enum CompletionReportSeverity: Int, Sendable, Equatable, Comparable {
    case normal
    case caution
    case warning

    static func < (lhs: CompletionReportSeverity, rhs: CompletionReportSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct CompletionReport: Sendable, Equatable {
    let loudnessRows: [CompletionReportRow]
    let noiseRows: [CompletionReportRow]
    let highFrequencyRows: [CompletionReportRow]
    let reminder: String

    var severity: CompletionReportSeverity {
        (loudnessRows + noiseRows + highFrequencyRows).map(\.severity).max() ?? .normal
    }
}

struct CompletionReportRow: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let severity: CompletionReportSeverity
}
