enum ProcessingStep: String, CaseIterable, Hashable {
    case loadAudio = "入力音声を読み込みます"
    case analyze = "音声を解析します"
    case routeNoiseMeasurement = "ノイズの種類を測定します"
    case lowNoiseCleanup = "低域ノイズを先に整えます"
    case denoise = "ノイズを除去します"
    case sibilanceShimmerGuard = "サ行保護を行います"
    case analyzeDenoised = "ノイズ除去後の音を解析します"
    case analysisAssist = "高域補完の必要性を確認します"
    case harmonicRepair = "高域を補完します"
    case repairShimmerGuard = "修復後シマーを確認します"
    case lowMidResidueGuard = "低中域の残りを軽く整えます"
    case shimmerPeakLimit = "シマーを抑えます"
    case correctionHighPreserve = "高域を保持します"
    case correctionMudGuard = "低中域の残りを確認します"
    case peakSafety = "ピークを保護します"
    case save = "処理済みファイルを書き出します"

    var title: String {
        switch self {
        case .loadAudio: "読み込み"
        case .analyze: "解析"
        case .routeNoiseMeasurement: "ノイズ測定"
        case .lowNoiseCleanup: "低域整理"
        case .denoise: "ノイズ除去"
        case .sibilanceShimmerGuard: "サ行保護"
        case .analyzeDenoised: "再解析"
        case .analysisAssist: "解析補助"
        case .harmonicRepair: "高域修復"
        case .repairShimmerGuard: "修復後シマー"
        case .lowMidResidueGuard: "低中域整理"
        case .shimmerPeakLimit: "シマー制限"
        case .correctionHighPreserve: "高域保持"
        case .correctionMudGuard: "低中域確認"
        case .peakSafety: "ピーク保護"
        case .save: "書き出し"
        }
    }

    var eventID: String {
        switch self {
        case .loadAudio: "loadAudio"
        case .analyze: "analyze"
        case .routeNoiseMeasurement: "routeNoiseMeasurement"
        case .lowNoiseCleanup: "lowNoiseCleanup"
        case .denoise: "denoise"
        case .sibilanceShimmerGuard: "sibilanceShimmerGuard"
        case .analyzeDenoised: "analyzeDenoised"
        case .analysisAssist: "analysisAssist"
        case .harmonicRepair: "harmonicRepair"
        case .repairShimmerGuard: "repairShimmerGuard"
        case .lowMidResidueGuard: "lowMidResidueGuard"
        case .shimmerPeakLimit: "shimmerPeakLimit"
        case .correctionHighPreserve: "correctionHighPreserve"
        case .correctionMudGuard: "correctionMudGuard"
        case .peakSafety: "peakSafety"
        case .save: "save"
        }
    }

    static func step(eventID: String) -> ProcessingStep? {
        allCases.first { $0.eventID == eventID }
    }
}

enum ProcessingProgressEvent: Sendable, Equatable {
    enum Domain: String, Sendable, Equatable {
        case correction
        case mastering
    }

    enum State: String, Sendable, Equatable {
        case started
        case completed
        case skipped
        case failed
        case detail
    }

    private static let prefix = "__veloura_progress__"

    case correction(step: ProcessingStep, state: State, detail: String?)
    case mastering(step: MasteringStep, state: State, detail: String?)

    var encodedMessage: String {
        let parts: [String]
        switch self {
        case let .correction(step, state, detail):
            parts = [Self.prefix, Domain.correction.rawValue, state.rawValue, step.eventID, detail ?? ""]
        case let .mastering(step, state, detail):
            parts = [Self.prefix, Domain.mastering.rawValue, state.rawValue, step.eventID, detail ?? ""]
        }
        return parts.map(Self.encodePart).joined(separator: "|")
    }

    static func decode(_ message: String) -> ProcessingProgressEvent? {
        let parts = message.split(separator: "|", omittingEmptySubsequences: false).map { decodePart(String($0)) }
        guard parts.count == 5, parts[0] == prefix else { return nil }
        guard let domain = Domain(rawValue: parts[1]), let state = State(rawValue: parts[2]) else { return nil }
        let detail = parts[4].isEmpty ? nil : parts[4]
        switch domain {
        case .correction:
            guard let step = ProcessingStep.step(eventID: parts[3]) else { return nil }
            return .correction(step: step, state: state, detail: detail)
        case .mastering:
            guard let step = MasteringStep.step(eventID: parts[3]) else { return nil }
            return .mastering(step: step, state: state, detail: detail)
        }
    }

    private static func encodePart(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "|", with: "%7C")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    private static func decodePart(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%0A", with: "\n")
            .replacingOccurrences(of: "%7C", with: "|")
            .replacingOccurrences(of: "%25", with: "%")
    }
}
