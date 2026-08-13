import Foundation

/// Exact correction settings for every separated Stem role.
///
/// Explicit stored properties make incomplete role coverage unrepresentable. The type is owned by
/// Stem Mode and does not change Standard Mode's `CorrectionSettings` model.
struct StemRoleCorrectionSettings: Equatable, Sendable {
    let vocals: CorrectionSettings
    let drums: CorrectionSettings
    let bass: CorrectionSettings
    let other: CorrectionSettings
    let guitar: CorrectionSettings
    let piano: CorrectionSettings

    init(
        vocals: CorrectionSettings,
        drums: CorrectionSettings,
        bass: CorrectionSettings,
        other: CorrectionSettings,
        guitar: CorrectionSettings,
        piano: CorrectionSettings
    ) {
        self.vocals = vocals
        self.drums = drums
        self.bass = bass
        self.other = other
        self.guitar = guitar
        self.piano = piano
    }

    init(all settings: CorrectionSettings) {
        self.init(
            vocals: settings,
            drums: settings,
            bass: settings,
            other: settings,
            guitar: settings,
            piano: settings
        )
    }

    func settings(for role: StemRole) -> CorrectionSettings {
        switch role {
        case .vocals: vocals
        case .drums: drums
        case .bass: bass
        case .other: other
        case .guitar: guitar
        case .piano: piano
        }
    }

    var allRoleSettings: [CorrectionSettings] {
        [vocals, drums, bass, other, guitar, piano]
    }

    func replacing(
        _ settings: CorrectionSettings,
        for role: StemRole
    ) -> StemRoleCorrectionSettings {
        switch role {
        case .vocals:
            StemRoleCorrectionSettings(
                vocals: settings,
                drums: drums,
                bass: bass,
                other: other,
                guitar: guitar,
                piano: piano
            )
        case .drums:
            StemRoleCorrectionSettings(
                vocals: vocals,
                drums: settings,
                bass: bass,
                other: other,
                guitar: guitar,
                piano: piano
            )
        case .bass:
            StemRoleCorrectionSettings(
                vocals: vocals,
                drums: drums,
                bass: settings,
                other: other,
                guitar: guitar,
                piano: piano
            )
        case .other:
            StemRoleCorrectionSettings(
                vocals: vocals,
                drums: drums,
                bass: bass,
                other: settings,
                guitar: guitar,
                piano: piano
            )
        case .guitar:
            StemRoleCorrectionSettings(
                vocals: vocals,
                drums: drums,
                bass: bass,
                other: other,
                guitar: settings,
                piano: piano
            )
        case .piano:
            StemRoleCorrectionSettings(
                vocals: vocals,
                drums: drums,
                bass: bass,
                other: other,
                guitar: guitar,
                piano: settings
            )
        }
    }
}

/// Audio-changing stages available to Stem Mode.
///
/// The order mirrors Standard Mode's proven lower-DSP order. `peakSafety` is intentionally
/// absent: limiting individual stems can change their relative balance, so peak control remains
/// after the pure-sum remix in the existing mastering path.
enum StemCorrectionStage: String, CaseIterable, Hashable, Sendable {
    case lowNoiseCleanup
    case denoise
    case sibilanceShimmerProtection
    case harmonicRepair
    case repairShimmerProtection
    case lowMidResidueControl
    case shimmerPeakControl
    case highFloorPreservation
    case mudIncreaseControl
}

enum StemCorrectionStageAction: String, Equatable, Sendable {
    case run
    case light
    case skip
}

struct StemCorrectionStagePlan: Equatable, Sendable {
    let stage: StemCorrectionStage
    let action: StemCorrectionStageAction
    let reason: String
}

/// One deterministic role plan selected before the first audio-changing stage runs.
/// The effective settings are exactly the role-specific settings fixed at correction start.
struct StemCorrectionExecutionPlan: Equatable, Sendable {
    let role: StemRole
    let effectiveSettings: CorrectionSettings
    let stages: [StemCorrectionStagePlan]

    func decision(for stage: StemCorrectionStage) -> StemCorrectionStagePlan? {
        stages.first { $0.stage == stage }
    }
}

enum StemCorrectionStageGuardOutcome: String, Equatable, Sendable {
    /// The Standard Mode lower DSP completed and returned the signal for the next stage.
    case completed

    /// The lower DSP and its internal guard returned the exact stage input unchanged.
    case unchanged

    /// Stem役割別guardが、問題区間だけDSP差分を連続的に弱めた。
    case weakenedByStemProtection

    /// Stem役割別guardが、当該DSPの直前音声を維持した。
    case restoredStageInputByStemProtection

    /// 当該DSPだけが失敗または構造契約に違反したため、直前音声を維持した。
    case restoredStageInputAfterDSPFailure

    /// 役割別guardを安全に完了できなかったため、不確実時は音を変えず直前音声を維持した。
    case restoredStageInputAfterGuardFailure

    case notEvaluatedForSkippedStage
}

/// Execution evidence for one stage in the fixed Standard Mode route.
///
/// 完成候補の比較結果ではなく、通常モードDSP内部guardとStem役割別guardが一本道の中で
/// 実際に採った処置を記録します。
struct StemCorrectionProtectionEvidence: Equatable, Sendable {
    let label: String
    let summary: StemRoleProtectionGuardSummary
}

struct StemCorrectionStageGuardRecord: Equatable, Sendable {
    let stage: StemCorrectionStage
    let action: StemCorrectionStageAction
    let outcome: StemCorrectionStageGuardOutcome
    let reason: String
    let protectedComponents: Set<StemRoleProtectedComponent>
    let protectionEvidence: [StemCorrectionProtectionEvidence]

    init(
        stage: StemCorrectionStage,
        action: StemCorrectionStageAction,
        outcome: StemCorrectionStageGuardOutcome,
        reason: String,
        protectedComponents: Set<StemRoleProtectedComponent> = [],
        protectionEvidence: [StemCorrectionProtectionEvidence] = []
    ) {
        self.stage = stage
        self.action = action
        self.outcome = outcome
        self.reason = reason
        self.protectedComponents = protectedComponents
        self.protectionEvidence = protectionEvidence
    }
}

enum StemCorrectionError: Error, Equatable, LocalizedError, Sendable {
    case invalidPlanCoverage(role: StemRole)
    case duplicatePlanStage(role: StemRole, stage: StemCorrectionStage)
    case emptyPlanReason(role: StemRole, stage: StemCorrectionStage)
    case effectiveSettingsExceedUserMaximum(role: StemRole, field: String)
    case roleMismatch(expected: StemRole, actual: StemRole)
    case invalidEvaluationPurpose(role: StemRole)
    case missingAudioAnalysis(role: StemRole)
    case invalidCorrectedSignal(role: StemRole, stage: StemCorrectionStage)

    var errorDescription: String? {
        switch self {
        case .invalidPlanCoverage(let role):
            "\(role.rawValue)のStem補正計画に全工程が揃っていません。"
        case let .duplicatePlanStage(role, stage):
            "\(role.rawValue)のStem補正計画で\(stage.rawValue)が重複しています。"
        case let .emptyPlanReason(role, stage):
            "\(role.rawValue)のStem補正計画で\(stage.rawValue)の判断理由がありません。"
        case let .effectiveSettingsExceedUserMaximum(role, field):
            "\(role.rawValue)のStem補正がユーザー設定の上限を超えています（\(field)）。"
        case let .roleMismatch(expected, actual):
            "Stem補正の役割が一致しません（期待: \(expected.rawValue)、実際: \(actual.rawValue)）。"
        case .invalidEvaluationPurpose(let role):
            "\(role.rawValue)のStem補正にraw Stem解析結果が渡されていません。"
        case .missingAudioAnalysis(let role):
            "\(role.rawValue)のStem補正に必要な共通解析結果がありません。"
        case let .invalidCorrectedSignal(role, stage):
            "\(role.rawValue)の\(stage.rawValue)がStem補正後の構造契約を満たす音声を生成できません。"
        }
    }
}

/// 補正工程からworkflowへ返すメモリ上の結果です。
struct StemCorrectionSignalResult: Sendable {
    let role: StemRole
    let roleAnalysisSnapshot: StemRoleAnalysisSnapshot?
    let executionPlan: StemCorrectionExecutionPlan
    let stageGuards: [StemCorrectionStageGuardRecord]
    let correctedSignal: AudioSignal
    let correctedEvaluation: StemAudioEvaluationSnapshot

    init(
        role: StemRole,
        roleAnalysisSnapshot: StemRoleAnalysisSnapshot? = nil,
        executionPlan: StemCorrectionExecutionPlan,
        stageGuards: [StemCorrectionStageGuardRecord],
        correctedSignal: AudioSignal,
        correctedEvaluation: StemAudioEvaluationSnapshot
    ) {
        self.role = role
        self.roleAnalysisSnapshot = roleAnalysisSnapshot
        self.executionPlan = executionPlan
        self.stageGuards = stageGuards
        self.correctedSignal = correctedSignal
        self.correctedEvaluation = correctedEvaluation
    }
}
