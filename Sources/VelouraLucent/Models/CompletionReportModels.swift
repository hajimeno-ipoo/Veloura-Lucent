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
    let lowFrequencyRows: [CompletionReportRow]
    let qualityRows: [CompletionReportRow]
    let reminder: String

    init(
        loudnessRows: [CompletionReportRow],
        noiseRows: [CompletionReportRow],
        highFrequencyRows: [CompletionReportRow],
        lowFrequencyRows: [CompletionReportRow] = [],
        qualityRows: [CompletionReportRow] = [],
        reminder: String
    ) {
        self.loudnessRows = loudnessRows
        self.noiseRows = noiseRows
        self.highFrequencyRows = highFrequencyRows
        self.lowFrequencyRows = lowFrequencyRows
        self.qualityRows = qualityRows
        self.reminder = reminder
    }

    var severity: CompletionReportSeverity {
        (loudnessRows + noiseRows + highFrequencyRows + lowFrequencyRows + qualityRows)
            .map(\.severity)
            .max() ?? .normal
    }
}

struct CompletionReportRow: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let value: String
    let detail: String
    let severity: CompletionReportSeverity
}
