import Foundation

enum CompletionReportSeverity: Int, Sendable, Equatable, Comparable {
    case normal
    case caution
    case warning

    static func < (lhs: CompletionReportSeverity, rhs: CompletionReportSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum CompletionReportMode: Sendable, Equatable {
    case standard
    case stem

    var middleStageTitle: String {
        switch self {
        case .standard: "補正後"
        case .stem: "Stem再ミックス"
        }
    }
}

enum CompletionReportChartKind: String, Sendable, Equatable {
    case loudnessTimeline
    case spectrumComparison
    case spectrumDelta
    case waveformComparison
}

struct CompletionReportChartPoint: Sendable, Equatable {
    let x: Double
    let y: Double
    let lowerY: Double?
}

struct CompletionReportChartSeries: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let points: [CompletionReportChartPoint]
}

struct CompletionReportChart: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let kind: CompletionReportChartKind
    let horizontalAxisTitle: String
    let verticalAxisTitle: String
    let series: [CompletionReportChartSeries]
}

struct CompletionReportComparisonRow: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let inputValue: String
    let processedValue: String
    let masteredValue: String
}

struct CompletionReportStageDeltaRow: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let inputToProcessedValue: String
    let processedToMasteredValue: String
}

struct CompletionReportSubsection: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let paragraphs: [String]
    let stageDeltaRows: [CompletionReportStageDeltaRow]

    init(
        id: String,
        title: String,
        paragraphs: [String],
        stageDeltaRows: [CompletionReportStageDeltaRow] = []
    ) {
        self.id = id
        self.title = title
        self.paragraphs = paragraphs
        self.stageDeltaRows = stageDeltaRows
    }
}

struct CompletionReportSection: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let subsections: [CompletionReportSubsection]
}

struct CompletionReport: Sendable, Equatable {
    let loudnessRows: [CompletionReportRow]
    let noiseRows: [CompletionReportRow]
    let highFrequencyRows: [CompletionReportRow]
    let lowFrequencyRows: [CompletionReportRow]
    let qualityRows: [CompletionReportRow]
    let reminder: String
    let mode: CompletionReportMode
    let summary: [String]
    let comparisonRows: [CompletionReportComparisonRow]
    let comparisonNotes: [String]
    let sections: [CompletionReportSection]
    let charts: [CompletionReportChart]
    let safetyRows: [CompletionReportRow]

    init(
        loudnessRows: [CompletionReportRow],
        noiseRows: [CompletionReportRow],
        highFrequencyRows: [CompletionReportRow],
        lowFrequencyRows: [CompletionReportRow] = [],
        qualityRows: [CompletionReportRow] = [],
        reminder: String,
        mode: CompletionReportMode = .standard,
        summary: [String] = [],
        comparisonRows: [CompletionReportComparisonRow] = [],
        comparisonNotes: [String] = [],
        sections: [CompletionReportSection] = [],
        charts: [CompletionReportChart] = [],
        safetyRows: [CompletionReportRow] = []
    ) {
        self.loudnessRows = loudnessRows
        self.noiseRows = noiseRows
        self.highFrequencyRows = highFrequencyRows
        self.lowFrequencyRows = lowFrequencyRows
        self.qualityRows = qualityRows
        self.reminder = reminder
        self.mode = mode
        self.summary = summary
        self.comparisonRows = comparisonRows
        self.comparisonNotes = comparisonNotes
        self.sections = sections
        self.charts = charts
        self.safetyRows = safetyRows
    }

    var severity: CompletionReportSeverity {
        safetyRows
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
