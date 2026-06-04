enum DisplayAnalysisTarget: Hashable, Sendable {
    case input
    case corrected
    case mastered

    static let allDisplayTargets: [DisplayAnalysisTarget] = [.input, .corrected, .mastered]
}

enum DisplayAnalysisKind: String, CaseIterable, Hashable, Sendable {
    case metrics
    case spectrogram
    case preview
    case noise
    case correctionAnalysis
    case masteringAnalysis

    var title: String {
        switch self {
        case .metrics: "比較"
        case .spectrogram: "スペクトログラム"
        case .preview: "プレビュー"
        case .noise: "ノイズ確認"
        case .correctionAnalysis: "補正解析"
        case .masteringAnalysis: "マスタリング解析"
        }
    }

    static func initialStates() -> [DisplayAnalysisKind: DisplayAnalysisState] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0, .idle) })
    }
}

enum DisplayAnalysisState: Hashable, Sendable {
    case idle
    case running
    case completed
    case failed
}

struct DisplayAnalysisStateStore {
    private var statesByTarget: [DisplayAnalysisTarget: [DisplayAnalysisKind: DisplayAnalysisState]]

    init() {
        statesByTarget = Dictionary(
            uniqueKeysWithValues: DisplayAnalysisTarget.allDisplayTargets.map {
                ($0, DisplayAnalysisKind.initialStates())
            }
        )
    }

    var isRunningAny: Bool {
        DisplayAnalysisKind.allCases.contains { isRunning($0) }
    }

    var runningStatusText: String? {
        let running = DisplayAnalysisKind.allCases
            .filter { isRunning($0) }
            .map(\.title)
        guard !running.isEmpty else { return nil }
        return "\(running.joined(separator: "・"))を更新中"
    }

    var failedStatusText: String? {
        let failed = DisplayAnalysisKind.allCases
            .filter { isFailed($0) }
            .map(\.title)
        guard !failed.isEmpty else { return nil }
        return "一部の表示解析を完了できませんでした: \(failed.joined(separator: "・"))"
    }

    mutating func begin(_ kind: DisplayAnalysisKind, for target: DisplayAnalysisTarget) {
        set(.running, for: target, kind: kind)
    }

    mutating func finish(_ kind: DisplayAnalysisKind, for target: DisplayAnalysisTarget) {
        set(.completed, for: target, kind: kind)
    }

    mutating func fail(_ kind: DisplayAnalysisKind, for target: DisplayAnalysisTarget) {
        set(.failed, for: target, kind: kind)
    }

    func state(_ kind: DisplayAnalysisKind, for target: DisplayAnalysisTarget) -> DisplayAnalysisState {
        statesByTarget[target]?[kind] ?? .idle
    }

    mutating func reset(for target: DisplayAnalysisTarget) {
        statesByTarget[target] = DisplayAnalysisKind.initialStates()
    }

    mutating func resetAll() {
        DisplayAnalysisTarget.allDisplayTargets.forEach { reset(for: $0) }
    }

    func isRunning(_ kind: DisplayAnalysisKind) -> Bool {
        DisplayAnalysisTarget.allDisplayTargets.contains {
            state(kind, for: $0) == .running
        }
    }

    func isFailed(_ kind: DisplayAnalysisKind) -> Bool {
        DisplayAnalysisTarget.allDisplayTargets.contains {
            state(kind, for: $0) == .failed
        }
    }

    private mutating func set(
        _ state: DisplayAnalysisState,
        for target: DisplayAnalysisTarget,
        kind: DisplayAnalysisKind
    ) {
        statesByTarget[target, default: DisplayAnalysisKind.initialStates()][kind] = state
    }
}
