import Foundation

enum StemMasteringSource: String, Equatable, Sendable {
    case remix
}

enum StemMasteringReportKind: String, Equatable, Sendable {
    case audioQuality
    case completion
    case noiseCheck
}

enum StemMasteringError: Error, Equatable, LocalizedError, Sendable {
    case unexpectedArtifactKind(
        label: String,
        expected: StemArtifactKind,
        actual: StemArtifactKind
    )
    case unexpectedEvaluationPurpose(
        label: String,
        expected: StemAudioEvaluationPurpose,
        actual: StemAudioEvaluationPurpose
    )
    case missingMasteringAnalysis
    case invalidSessionDirectory(String)
    case finalArtifactAlreadyExists(String)
    case temporaryOutputMissing(String)
    case unsafeTemporaryOutputURL(String)
    case invalidReportContext
    case reportUnavailable(StemMasteringReportKind)

    var errorDescription: String? {
        switch self {
        case let .unexpectedArtifactKind(label, expected, actual):
            "\(label)の成果物種別が一致しません（期待: \(expected)、実際: \(actual)）。"
        case let .unexpectedEvaluationPurpose(label, expected, actual):
            "\(label)の評価目的が一致しません（期待: \(expected)、実際: \(actual)）。"
        case .missingMasteringAnalysis:
            "マスタリング入力の既存解析結果がありません。"
        case .invalidSessionDirectory(let path):
            "Stem一時セッションの保存先が安全なローカルdirectoryではありません（\(path)）。"
        case .finalArtifactAlreadyExists(let path):
            "Stem最終成果物がすでに存在します（\(path)）。"
        case .temporaryOutputMissing(let path):
            "通常モードのマスタリング一時出力が見つかりません（\(path)）。"
        case .unsafeTemporaryOutputURL(let path):
            "通常モードのマスタリング一時出力が入力または最終成果物と重複しています（\(path)）。"
        case .invalidReportContext:
            "Stem最終報告のrun契約と役割別実行記録が一致しません。"
        case .reportUnavailable(let kind):
            "Stem最終品質レポートを生成できませんでした（\(kind.rawValue)）。"
        }
    }
}

/// The only reference type accepted by Stem mastering.
///
/// A raw user-selected URL cannot be represented here. The reference must already be
/// the canonical, layout-confirmed `.input44100` Stem artifact and its matching
/// Standard-mode evaluation snapshot.
struct StemCanonicalMasteringReference: Sendable {
    let artifact: StemAudioArtifact
    let evaluation: StemAudioEvaluationSnapshot

    init(
        artifact: StemAudioArtifact,
        evaluation: StemAudioEvaluationSnapshot
    ) throws {
        guard artifact.kind == .input44100 else {
            throw StemMasteringError.unexpectedArtifactKind(
                label: "canonical input",
                expected: .input44100,
                actual: artifact.kind
            )
        }
        guard evaluation.purpose == .canonicalInput else {
            throw StemMasteringError.unexpectedEvaluationPurpose(
                label: "canonical input",
                expected: .canonicalInput,
                actual: evaluation.purpose
            )
        }
        self.artifact = artifact
        self.evaluation = evaluation
    }
}

/// The exact 48 kHz stereo material and existing analysis passed to Standard mastering.
struct StemMasteringInputMaterial: Sendable {
    let artifact: StemAudioArtifact
    let evaluation: StemAudioEvaluationSnapshot

    init(
        artifact: StemAudioArtifact,
        evaluation: StemAudioEvaluationSnapshot
    ) throws {
        guard artifact.kind == .remixed48000 else {
            throw StemMasteringError.unexpectedArtifactKind(
                label: "mastering input",
                expected: .remixed48000,
                actual: artifact.kind
            )
        }
        guard evaluation.purpose == .remix else {
            throw StemMasteringError.unexpectedEvaluationPurpose(
                label: "mastering input",
                expected: .remix,
                actual: evaluation.purpose
            )
        }
        guard evaluation.masteringAnalysis != nil else {
            throw StemMasteringError.missingMasteringAnalysis
        }
        self.artifact = artifact
        self.evaluation = evaluation
    }
}

struct StemMasteringRoleReportEvidence: Sendable {
    let role: StemRole
    let selectedCorrectionSettings: CorrectionSettings
    let effectiveCorrectionSettings: CorrectionSettings?
    let stageGuards: [StemCorrectionStageGuardRecord]
    let usedRawFallback: Bool
    let fallbackReason: String?
}

struct StemMasteringReportContext: Sendable {
    let runContract: StemModelRunContract
    let appliedRemixSettings: StemRemixSettings
    let roleEvidence: [StemMasteringRoleReportEvidence]

    init(
        runContract: StemModelRunContract,
        appliedRemixSettings: StemRemixSettings,
        roleEvidence: [StemMasteringRoleReportEvidence]
    ) throws {
        let roles = runContract.activeRoles
        let evidenceRoles = roleEvidence.map(\.role)
        guard !roles.isEmpty,
              Set(roles).count == roles.count,
              Set(roles) == Set(runContract.validationRoles),
              Set(roles) == Set(runContract.pureSumOrder),
              Set(runContract.pureSumOrder).count == runContract.pureSumOrder.count,
              roleEvidence.count == roles.count,
              Set(evidenceRoles).count == evidenceRoles.count,
              Set(evidenceRoles) == Set(roles),
              roleEvidence.allSatisfy({ evidence in
                  if evidence.usedRawFallback {
                      let guardStages = evidence.stageGuards.map(\.stage)
                      return evidence.effectiveCorrectionSettings == nil
                          && evidence.fallbackReason?.isEmpty == false
                          && (guardStages.isEmpty || (
                              guardStages.count == StemCorrectionStage.allCases.count
                                  && Set(guardStages) == Set(StemCorrectionStage.allCases)
                          ))
                  }
                  let guardStages = evidence.stageGuards.map(\.stage)
                  return evidence.effectiveCorrectionSettings != nil
                      && evidence.fallbackReason == nil
                      && guardStages.count == StemCorrectionStage.allCases.count
                      && Set(guardStages) == Set(StemCorrectionStage.allCases)
              }) else {
            throw StemMasteringError.invalidReportContext
        }
        self.runContract = runContract
        self.appliedRemixSettings = appliedRemixSettings
        self.roleEvidence = roleEvidence
    }
}

struct StemMasteringRequest: Sendable {
    let runID: UUID
    let sessionDirectory: URL
    let sourceDisplayName: String
    let sourceFileInfo: AudioFileInfo?
    let separationModelDisplayName: String
    let canonicalReference: StemCanonicalMasteringReference
    let masteringInput: StemMasteringInputMaterial
    let reportContext: StemMasteringReportContext
    let settings: MasteringSettings
}

struct StemMasteringReports: Sendable {
    let audioQuality: AudioQualityReport
    let completion: CompletionReport
    let noiseCheck: NoiseCheckReport
}

struct StemMasteringResult: Sendable {
    let finalArtifact: StemAudioArtifact
    let finalEvaluation: StemAudioEvaluationSnapshot
    let masteringSettings: MasteringSettings
    let audioQualityReport: AudioQualityReport
    let completionReport: CompletionReport
    let noiseCheckReport: NoiseCheckReport
}
