import Foundation

enum ProcessingMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case stem

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "通常補正"
        case .stem:
            return "Stem Mode"
        }
    }
}

enum StemWorkflowStep: String, CaseIterable, Identifiable, Sendable {
    case validateInput
    case separate
    case validateSeparatedStems
    case evaluateStems
    case correctStems
    case validateCorrectedStems
    case correctedRemix
    case validateCorrectedRemix
    case mastering
    case finalizeMaster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .validateInput: "入力検証"
        case .separate: "4ステム分離"
        case .validateSeparatedStems: "分離結果検証"
        case .evaluateStems: "Stem別解析"
        case .correctStems: "Stem別補正"
        case .validateCorrectedStems: "補正後Stem検証"
        case .correctedRemix: "補正後再ミックス"
        case .validateCorrectedRemix: "補正後再ミックス検証"
        case .mastering: "マスタリング"
        case .finalizeMaster: "最終版解析・保存"
        }
    }
}

enum StemModeProcessDomain: String, Sendable {
    case correction
    case mastering
}

struct StemModeProcessStep: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let domain: StemModeProcessDomain

    static let inputPreparation = correction(id: "inputPreparation", title: "処理用入力準備")
    static let separation = correction(id: "separation", title: "4ステム分離")
    static let separatedValidation = correction(id: "separatedValidation", title: "分離結果検証")
    static let correctedRemix = correction(id: "correctedRemix", title: "補正後再ミックス")
    static let correctedRemixValidation = correction(id: "correctedRemixValidation", title: "再ミックス検証")
    static let finalization = mastering(id: "finalization", title: "最終版解析・保存")

    static func roleAnalysis(_ role: StemRole) -> StemModeProcessStep {
        correction(
            id: "role.\(role.rawValue).analysis",
            title: "\(role.stemModeDisplayTitle)：解析"
        )
    }

    static func roleCorrection(_ role: StemRole, stage: StemCorrectionStage) -> StemModeProcessStep {
        correction(
            id: "role.\(role.rawValue).stage.\(stage.rawValue)",
            title: "\(role.stemModeDisplayTitle)：\(stage.stemModeDisplayTitle)"
        )
    }

    static func roleSave(_ role: StemRole) -> StemModeProcessStep {
        correction(
            id: "role.\(role.rawValue).save",
            title: "\(role.stemModeDisplayTitle)：保存・検証"
        )
    }

    static func mastering(_ step: MasteringStep) -> StemModeProcessStep {
        mastering(id: "existing.\(step.eventID)", title: step.title)
    }

    static var correctionSteps: [StemModeProcessStep] {
        var steps: [StemModeProcessStep] = [
            .inputPreparation,
            .separation,
            .separatedValidation,
        ]
        for role in StemRole.allCases {
            steps.append(.roleAnalysis(role))
            steps.append(contentsOf: StemCorrectionStage.allCases.map {
                .roleCorrection(role, stage: $0)
            })
            steps.append(.roleSave(role))
        }
        steps.append(.correctedRemix)
        steps.append(.correctedRemixValidation)
        return steps
    }

    static var masteringSteps: [StemModeProcessStep] {
        MasteringStep.allCases.map(Self.mastering) + [.finalization]
    }

    private static func correction(id: String, title: String) -> StemModeProcessStep {
        StemModeProcessStep(id: "correction.\(id)", title: title, domain: .correction)
    }

    private static func mastering(id: String, title: String) -> StemModeProcessStep {
        StemModeProcessStep(id: "mastering.\(id)", title: title, domain: .mastering)
    }
}

enum StemModeProcessStepStatus: String, Equatable, Sendable {
    case pending
    case running
    case completed
    case skipped
    case failed
}

struct StemModeProcessStepProgress: Equatable, Sendable, Identifiable {
    let step: StemModeProcessStep
    let status: StemModeProcessStepStatus
    let fraction: Double
    let detail: String?

    var id: String { step.id }

    init(
        step: StemModeProcessStep,
        status: StemModeProcessStepStatus,
        fraction: Double,
        detail: String? = nil
    ) {
        self.step = step
        self.status = status
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        self.detail = detail
    }
}

struct StemModeProcessProgressEvent: Equatable, Sendable {
    let runID: UUID
    let step: StemModeProcessStep
    let status: StemModeProcessStepStatus
    let fraction: Double
    let detail: String?

    init(
        runID: UUID,
        step: StemModeProcessStep,
        status: StemModeProcessStepStatus,
        fraction: Double,
        detail: String? = nil
    ) {
        self.runID = runID
        self.step = step
        self.status = status
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        self.detail = detail
    }
}

enum StemWorkflowStepStatus: String, Equatable, Sendable {
    case pending
    case running
    case completed
    case failed
}

struct StemWorkflowStepProgress: Equatable, Sendable, Identifiable {
    let step: StemWorkflowStep
    let status: StemWorkflowStepStatus
    let fraction: Double
    let detail: String?

    var id: StemWorkflowStep { step }

    init(
        step: StemWorkflowStep,
        status: StemWorkflowStepStatus,
        fraction: Double,
        detail: String? = nil
    ) {
        self.step = step
        self.status = status
        self.fraction = min(max(fraction.isFinite ? fraction : 0, 0), 1)
        self.detail = detail
    }
}

enum StemWorkflowState: Equatable, Sendable {
    case idle
    case ready
    case readyForMastering(runID: UUID)
    case running(step: StemWorkflowStep)
    case completed(runID: UUID)
    case failed(runID: UUID?, message: String)
}

enum StemArtifactKind: Equatable, Hashable, Sendable {
    case input44100
    case rawStem(StemRole)
    case correctedStem(StemRole)
    case correctedRemix48000
    case finalMaster
}

struct StemAudioArtifact: Equatable, Sendable, Identifiable {
    let id: String
    let kind: StemArtifactKind
    let fileURL: URL
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
}

struct StemSeparationResult: Equatable, Sendable {
    let source: StemAudioArtifact
    let stems: [StemAudioArtifact]
}

enum StemModelRecoveryAction: String, CaseIterable, Identifiable, Sendable {
    case initialDownload
    case repair
    case redownload
    case revalidate

    var id: String { rawValue }
}
