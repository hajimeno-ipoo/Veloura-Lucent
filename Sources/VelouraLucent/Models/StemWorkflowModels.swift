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
    case correctedPureSum
    case validateCorrectedPureSum
    case remix
    case validateRemix
    case mastering
    case finalizeMaster

    var id: String { rawValue }

    var title: String {
        switch self {
        case .validateInput: "入力検証"
        case .separate: "Stem分離"
        case .validateSeparatedStems: "分離結果検証"
        case .evaluateStems: "Stem別解析"
        case .correctStems: "Stem別補正"
        case .validateCorrectedStems: "補正後Stem検証"
        case .correctedPureSum: "補正済み純粋加算"
        case .validateCorrectedPureSum: "補正済み純粋加算検証"
        case .remix: "Stem再ミックス"
        case .validateRemix: "Stem再ミックス検証"
        case .mastering: "マスタリング"
        case .finalizeMaster: "最終版解析・保存"
        }
    }
}

enum StemModeProcessDomain: String, Sendable {
    case correction
    case remix
    case mastering
}

struct StemModeProcessStep: Hashable, Identifiable, Sendable {
    let id: String
    let title: String
    let domain: StemModeProcessDomain

    static let inputPreparation = correction(id: "inputPreparation", title: "処理用入力準備")
    static func separation(stemCount: Int) -> StemModeProcessStep {
        correction(id: "separation", title: "\(stemCount)Stem分離")
    }
    static let separatedValidation = correction(id: "separatedValidation", title: "分離結果検証")
    static let correctedPureSum = correction(id: "correctedPureSum", title: "補正済み純粋加算")
    static let correctedPureSumValidation = correction(id: "correctedPureSumValidation", title: "純粋加算検証")
    static let automaticRemixPlan = remix(id: "automaticPlan", title: "自動再ミックス設定")
    static let remixGain = remix(id: "gain", title: "Stem別gain")
    static let remixMasking = remix(id: "masking", title: "条件付き帯域制御")
    static let remixPan = remix(id: "pan", title: "Stem別pan")
    static let remixReverbSend = remix(id: "reverbSend", title: "Stem別reverb send")
    static let remixSharedReverb = remix(id: "sharedReverb", title: "共通reverb return")
    static let remixDryReturnMix = remix(id: "dryReturnMix", title: "dry／reverb加算")
    static let remixSave = remix(id: "save", title: "再ミックス保存")
    static let remixValidation = remix(id: "validation", title: "再ミックス検証")
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

    static func roleTransientRecovery(_ role: StemRole) -> StemModeProcessStep {
        correction(
            id: "role.\(role.rawValue).transientRecovery",
            title: "\(role.stemModeDisplayTitle)：raw基準アタック保護"
        )
    }

    static func mastering(_ step: MasteringStep) -> StemModeProcessStep {
        mastering(id: "existing.\(step.eventID)", title: step.title)
    }

    static func correctionSteps(for roles: [StemRole]) -> [StemModeProcessStep] {
        var steps: [StemModeProcessStep] = [
            .inputPreparation,
            .separation(stemCount: roles.count),
            .separatedValidation,
        ]
        for role in roles {
            steps.append(.roleAnalysis(role))
            steps.append(contentsOf: StemCorrectionStage.allCases.map {
                .roleCorrection(role, stage: $0)
            })
            if role == .drums {
                steps.append(.roleTransientRecovery(role))
            }
            steps.append(.roleSave(role))
        }
        steps.append(.correctedPureSum)
        steps.append(.correctedPureSumValidation)
        return steps
    }

    static var remixSteps: [StemModeProcessStep] {
        [
            .automaticRemixPlan,
            .remixGain,
            .remixMasking,
            .remixPan,
            .remixReverbSend,
            .remixSharedReverb,
            .remixDryReturnMix,
            .remixSave,
            .remixValidation,
        ]
    }

    static var masteringSteps: [StemModeProcessStep] {
        MasteringStep.allCases.map(Self.mastering) + [.finalization]
    }

    private static func correction(id: String, title: String) -> StemModeProcessStep {
        StemModeProcessStep(id: "correction.\(id)", title: title, domain: .correction)
    }

    private static func remix(id: String, title: String) -> StemModeProcessStep {
        StemModeProcessStep(id: "remix.\(id)", title: title, domain: .remix)
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
    case readyForRemix(runID: UUID)
    case readyForMastering(runID: UUID)
    case running(step: StemWorkflowStep)
    case completed(runID: UUID)
    case failed(runID: UUID?, message: String)
}

enum StemArtifactKind: Equatable, Hashable, Sendable {
    case input44100
    case rawStem(StemRole)
    case correctedStem(StemRole)
    case correctedPureSum48000
    case remixed48000
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

    var id: String { rawValue }
}
