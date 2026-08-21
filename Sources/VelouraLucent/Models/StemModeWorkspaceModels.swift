import Foundation

enum StemModeModelPresentationError: LocalizedError, Equatable, Sendable {
    case manifestInstallationMismatch
    case downloadableAssetSetIncomplete
    case assetEvidenceMissing(StemModelAssetKind)
    case bundledRuntimeAssetSetIncomplete
    case bundledRuntimeMismatch(StemModelAssetKind)

    var errorDescription: String? {
        switch self {
        case .manifestInstallationMismatch:
            "表示対象のモデルmanifestと検証済みactive世代が一致しません。"
        case .downloadableAssetSetIncomplete:
            "検証済みactive世代のAIモデル資産一式がmanifestと一致しません。"
        case .assetEvidenceMissing(let kind):
            "検証済みモデル資産の取得元またはchecksum証跡がありません（\(kind.rawValue)）。"
        case .bundledRuntimeAssetSetIncomplete:
            "検証済みの同梱MLX実行資産一式がmanifestと一致しません。"
        case .bundledRuntimeMismatch(let kind):
            "同梱MLX実行資産の検証結果がmanifestと一致しません（\(kind.rawValue)）。"
        }
    }
}

struct StemModeModelPresentation: Equatable, Sendable {
    enum AssetScope: String, Equatable, Sendable {
        case downloadedModel
        case bundledRuntime
    }

    struct Asset: Identifiable, Equatable, Sendable {
        let scope: AssetScope
        let kind: StemModelAssetKind
        let fileName: String
        let byteCount: Int64
        let sha256: String
        let source: String

        var id: String { "\(scope.rawValue)-\(kind.rawValue)" }
    }

    let modelName: String
    let repository: String
    let revision: String
    let license: String
    let assetSetIdentifier: String
    /// 入力選択前のUIも、検証済み選択モデルの4／6Stem契約を表示するための正本です。
    let runContract: StemModelRunContract
    let generationIdentifier: UUID
    let activatedAt: Date
    let downloadableAssets: [Asset]
    let bundledRuntimeAssets: [Asset]

    var downloadableByteCount: Int64 {
        downloadableAssets.reduce(0) { $0 + $1.byteCount }
    }

    init(
        manifest: StemModelManifest,
        installation: ValidatedStemModelInstallation,
        bundledRuntime: StemBundledRuntimeValidationReport
    ) throws {
        guard manifest.assetSetIdentifier == installation.receipt.assetSetIdentifier,
              installation.snapshot.contract.identifier == installation.receipt.modelIdentifier,
              manifest.model.revision == installation.receipt.revision,
              manifest.assetSetIdentifier == installation.snapshot.contract.assetSetIdentifier,
              manifest.model.revision == installation.snapshot.contract.version,
              bundledRuntime.contract == installation.snapshot.contract else {
            throw StemModeModelPresentationError.manifestInstallationMismatch
        }

        let expectedDownloadableKinds = manifest.downloadableModelAssets
            .map(\.kind.rawValue)
            .sorted()
        guard installation.snapshot.assets.map(\.kind.rawValue).sorted()
                == expectedDownloadableKinds,
              installation.receipt.assets.map(\.kind.rawValue).sorted()
                == expectedDownloadableKinds,
              installation.receipt.sourceEvidence.map(\.kind.rawValue).sorted()
                == expectedDownloadableKinds else {
            throw StemModeModelPresentationError.downloadableAssetSetIncomplete
        }

        let expectedRuntimeKinds = manifest.bundledRuntimeAssets
            .map(\.kind.rawValue)
            .sorted()
        guard bundledRuntime.assets.map(\.kind.rawValue).sorted()
                == expectedRuntimeKinds else {
            throw StemModeModelPresentationError.bundledRuntimeAssetSetIncomplete
        }

        let downloadableAssets = try installation.snapshot.assets.map { validated in
            guard let expected = manifest.downloadableModelAssets.first(where: {
                $0.kind == validated.kind
            }),
            let receipt = installation.receipt.assets.first(where: {
                $0.kind == validated.kind
            }),
            let sourceEvidence = installation.receipt.sourceEvidence.first(where: {
                $0.kind == validated.kind
            }),
            expected.byteCount == validated.byteCount,
            expected.sha256 == validated.sha256,
            receipt.byteCount == validated.byteCount,
            receipt.sha256 == validated.sha256,
            sourceEvidence.revision == manifest.model.revision else {
                throw StemModeModelPresentationError.assetEvidenceMissing(validated.kind)
            }
            return Asset(
                scope: .downloadedModel,
                kind: validated.kind,
                fileName: validated.fileURL.lastPathComponent,
                byteCount: validated.byteCount,
                sha256: validated.sha256,
                source: sourceEvidence.stableDownloadURL
            )
        }

        let bundledRuntimeAssets = try bundledRuntime.assets.map { validated in
            guard let expected = manifest.bundledRuntimeAssets.first(where: {
                $0.kind == validated.kind
            }),
            expected.byteCount == validated.byteCount,
            expected.sha256 == validated.sha256 else {
                throw StemModeModelPresentationError.bundledRuntimeMismatch(validated.kind)
            }
            return Asset(
                scope: .bundledRuntime,
                kind: validated.kind,
                fileName: validated.fileURL.lastPathComponent,
                byteCount: validated.byteCount,
                sha256: validated.sha256,
                source: "アプリ同梱"
            )
        }

        self.modelName = manifest.model.name
        repository = manifest.model.repo
        revision = manifest.model.revision
        license = manifest.model.licenseMetadata
        assetSetIdentifier = manifest.assetSetIdentifier
        runContract = installation.snapshot.contract.runContract
        generationIdentifier = installation.receipt.generationIdentifier
        activatedAt = installation.receipt.activatedAt
        self.downloadableAssets = downloadableAssets
        self.bundledRuntimeAssets = bundledRuntimeAssets
    }
}

struct StemModeStartRequest: Sendable {
    let inputURL: URL
    let separationSettings: StemSeparationSettings
    let correctionSettings: StemRoleCorrectionSettings
    let masteringProfile: MasteringProfile
    let masteringSettings: MasteringSettings
    let analysisMode: StemAudioAnalysisMode

    init(
        inputURL: URL,
        separationSettings: StemSeparationSettings,
        correctionSettings: StemRoleCorrectionSettings,
        masteringProfile: MasteringProfile,
        masteringSettings: MasteringSettings,
        analysisMode: StemAudioAnalysisMode = .auto
    ) {
        self.inputURL = inputURL
        self.separationSettings = separationSettings
        self.correctionSettings = correctionSettings
        self.masteringProfile = masteringProfile
        self.masteringSettings = masteringSettings
        self.analysisMode = analysisMode
    }
}

struct StemModeMasteringRequest: Sendable {
    let masteringSettings: MasteringSettings
}

struct StemModeRemixRequest: Sendable {
    let settings: StemRemixSettings
}

/// 入力選択直後に作る、Stem Mode専用の表示・試聴用解析結果です。
///
/// 補正workflowが保存するcanonical input評価とは分離し、選択した入力ファイルそのものの
/// 波形・試聴・測定値だけを画面へ渡します。
struct StemModeInputDisplayAnalysisResult: Sendable {
    let evaluation: StemAudioEvaluationSnapshot?
    let metrics: AudioMetricSnapshot?
    let noiseMeasurements: NoiseMeasurementSnapshot?
    let audioAnalysis: AnalysisData?
    let previewSnapshot: AudioPreviewSnapshot
    let spectrogram: SpectrogramSnapshot
    let warning: String?

    init(
        evaluation: StemAudioEvaluationSnapshot?,
        metrics: AudioMetricSnapshot? = nil,
        noiseMeasurements: NoiseMeasurementSnapshot? = nil,
        audioAnalysis: AnalysisData? = nil,
        previewSnapshot: AudioPreviewSnapshot,
        spectrogram: SpectrogramSnapshot,
        warning: String?
    ) {
        self.evaluation = evaluation
        self.metrics = metrics ?? evaluation?.audioMetrics
        self.noiseMeasurements = noiseMeasurements ?? evaluation?.noiseMeasurements
        self.audioAnalysis = audioAnalysis ?? evaluation?.audioAnalysis
        self.previewSnapshot = previewSnapshot
        self.spectrogram = spectrogram
        self.warning = warning
    }
}

enum StemModeWorkspaceSettingsError: LocalizedError, Equatable, Sendable {
    case settingsCannotChangeDuringRun
    case remixInputRequired
    case remixManualModeRequired
    case unapprovedProductionSettings

    var errorDescription: String? {
        switch self {
        case .settingsCannotChangeDuringRun:
            "Stem Mode処理の実行中は設定を変更できません。"
        case .remixInputRequired:
            "入力音源を選んでから再ミックス設定を変更してください。"
        case .remixManualModeRequired:
            "再ミックスを手動へ切り替えてから設定を変更してください。"
        case .unapprovedProductionSettings:
            "Stem分離設定が選択モデルの承認済み本番設定と一致しません。"
        }
    }
}

/// Stem専用Viewと実処理をつなぐ境界です。
///
/// 補正段・再ミックス段・マスタリング段の開始要求は処理Taskを開始した時点で戻し、長時間の処理状態は
/// `StemWorkflowSession` へ通知してください。View側は実処理の具象型を所有しません。
struct StemModeWorkspaceActions {
    let inspectInput: @MainActor (URL) async throws -> Void
    let analyzeInputForDisplay: @MainActor (
        URL,
        StemAudioAnalysisMode,
        @escaping @Sendable (String) -> Void
    ) async throws -> StemModeInputDisplayAnalysisResult
    let releaseInspectedInput: @MainActor (URL) -> Void
    let resetForInputChange: @MainActor () async throws -> Void
    let beginCorrection: @MainActor (StemModeStartRequest) async throws -> Void
    let beginRemix: @MainActor (StemModeRemixRequest) async throws -> Void
    let invalidateRemix: @MainActor () throws -> Void
    let beginMastering: @MainActor (StemModeMasteringRequest) async throws -> Void
    let cancelCorrection: @MainActor () async throws -> Void
    let cancelRemix: @MainActor () async throws -> Void
    let cancelMastering: @MainActor () async throws -> Void
    let exportArtifact: @MainActor (StemAudioArtifact, AudioExportFormat) async throws -> URL
    let revealArtifact: @MainActor (URL) -> Void

    init(
        inspectInput: @escaping @MainActor (URL) async throws -> Void,
        analyzeInputForDisplay: @escaping @MainActor (
            URL,
            StemAudioAnalysisMode,
            @escaping @Sendable (String) -> Void
        ) async throws -> StemModeInputDisplayAnalysisResult,
        releaseInspectedInput: @escaping @MainActor (URL) -> Void,
        resetForInputChange: @escaping @MainActor () async throws -> Void,
        beginCorrection: @escaping @MainActor (StemModeStartRequest) async throws -> Void,
        beginRemix: @escaping @MainActor (StemModeRemixRequest) async throws -> Void,
        invalidateRemix: @escaping @MainActor () throws -> Void,
        beginMastering: @escaping @MainActor (StemModeMasteringRequest) async throws -> Void,
        cancelCorrection: @escaping @MainActor () async throws -> Void,
        cancelRemix: @escaping @MainActor () async throws -> Void,
        cancelMastering: @escaping @MainActor () async throws -> Void,
        exportArtifact: @escaping @MainActor (StemAudioArtifact, AudioExportFormat) async throws -> URL,
        revealArtifact: @escaping @MainActor (URL) -> Void
    ) {
        self.inspectInput = inspectInput
        self.analyzeInputForDisplay = analyzeInputForDisplay
        self.releaseInspectedInput = releaseInspectedInput
        self.resetForInputChange = resetForInputChange
        self.beginCorrection = beginCorrection
        self.beginRemix = beginRemix
        self.invalidateRemix = invalidateRemix
        self.beginMastering = beginMastering
        self.cancelCorrection = cancelCorrection
        self.cancelRemix = cancelRemix
        self.cancelMastering = cancelMastering
        self.exportArtifact = exportArtifact
        self.revealArtifact = revealArtifact
    }
}

enum StemModeRemixAnalysisPresentationError: LocalizedError, Equatable, Sendable {
    case evaluationPurposeMismatch
    case validationMismatch

    var errorDescription: String? {
        switch self {
        case .evaluationPurposeMismatch:
            "再ミックス採用表示へ渡されたrawまたは補正後の解析目的が一致しません。"
        case .validationMismatch:
            "補正済み純粋加算またはStem再ミックスの構造検証結果が一致しません。"
        }
    }
}

struct StemModeRemixAnalysisPresentation: Sendable {
    let masteringSource: StemMasteringSource
    let validation: StemValidationResult
    let rawRemixEvaluation: StemAudioEvaluationSnapshot
    let correctedRemixEvaluation: StemAudioEvaluationSnapshot
    let processedRemixEvaluation: StemAudioEvaluationSnapshot?
    let processedRemixValidation: StemValidationResult?
    let correctionSettings: StemRoleCorrectionSettings

    private init(
        masteringSource: StemMasteringSource,
        validation: StemValidationResult,
        rawRemixEvaluation: StemAudioEvaluationSnapshot,
        correctedRemixEvaluation: StemAudioEvaluationSnapshot,
        processedRemixEvaluation: StemAudioEvaluationSnapshot?,
        processedRemixValidation: StemValidationResult?,
        correctionSettings: StemRoleCorrectionSettings
    ) {
        self.masteringSource = masteringSource
        self.validation = validation
        self.rawRemixEvaluation = rawRemixEvaluation
        self.correctedRemixEvaluation = correctedRemixEvaluation
        self.processedRemixEvaluation = processedRemixEvaluation
        self.processedRemixValidation = processedRemixValidation
        self.correctionSettings = correctionSettings
    }

    func removingProcessedRemix() -> Self {
        Self(
            masteringSource: masteringSource,
            validation: validation,
            rawRemixEvaluation: rawRemixEvaluation,
            correctedRemixEvaluation: correctedRemixEvaluation,
            processedRemixEvaluation: nil,
            processedRemixValidation: nil,
            correctionSettings: correctionSettings
        )
    }

    init(correctionResult: StemWorkflowCorrectionResult) throws {
        guard correctionResult.rawRemixEvaluation.purpose == .rawRemix,
              correctionResult.correctedRemixEvaluation.purpose == .correctedPureSum else {
            throw StemModeRemixAnalysisPresentationError.evaluationPurposeMismatch
        }

        guard correctionResult.correctedRemixValidation.phase == .correctedPureSum,
              correctionResult.correctedRemixValidation.canContinue else {
            throw StemModeRemixAnalysisPresentationError.validationMismatch
        }

        masteringSource = .remix
        validation = correctionResult.correctedRemixValidation
        rawRemixEvaluation = correctionResult.rawRemixEvaluation
        correctedRemixEvaluation = correctionResult.correctedRemixEvaluation
        processedRemixEvaluation = nil
        processedRemixValidation = nil
        correctionSettings = correctionResult.correctionSettings
    }

    init(remixResult: StemWorkflowRemixResult) throws {
        let correction = remixResult.correction
        guard correction.rawRemixEvaluation.purpose == .rawRemix,
              correction.correctedRemixEvaluation.purpose == .correctedPureSum,
              remixResult.evaluation.purpose == .remix else {
            throw StemModeRemixAnalysisPresentationError.evaluationPurposeMismatch
        }
        guard correction.correctedRemixValidation.phase == .correctedPureSum,
              correction.correctedRemixValidation.canContinue,
              remixResult.validation.phase == .processedRemix,
              remixResult.validation.canContinue else {
            throw StemModeRemixAnalysisPresentationError.validationMismatch
        }
        masteringSource = .remix
        validation = correction.correctedRemixValidation
        rawRemixEvaluation = correction.rawRemixEvaluation
        correctedRemixEvaluation = correction.correctedRemixEvaluation
        processedRemixEvaluation = remixResult.evaluation
        processedRemixValidation = remixResult.validation
        correctionSettings = correction.correctionSettings
    }

    init(result: StemWorkflowResult) throws {
        guard result.rawRemixEvaluation.purpose == .rawRemix,
              result.correctedRemixEvaluation.purpose == .correctedPureSum else {
            throw StemModeRemixAnalysisPresentationError.evaluationPurposeMismatch
        }

        guard result.masteringSource == .remix,
              result.correctedRemixValidation.phase == .correctedPureSum,
              result.correctedRemixValidation.canContinue else {
            throw StemModeRemixAnalysisPresentationError.validationMismatch
        }

        masteringSource = result.masteringSource
        validation = result.correctedRemixValidation
        rawRemixEvaluation = result.rawRemixEvaluation
        correctedRemixEvaluation = result.correctedRemixEvaluation
        processedRemixEvaluation = result.remixEvaluation
        processedRemixValidation = result.processedRemixValidation
        correctionSettings = result.correctionSettings
    }
}

enum StemModeFinalCommitLockState: Equatable, Sendable {
    case unlocked
    case locked
}

enum StemModeStemEvaluationPresentationError: LocalizedError, Equatable, Sendable {
    case rawEvaluationPurposeMismatch
    case correctedEvaluationPurposeMismatch
    case correctionEvidenceMismatch

    var errorDescription: String? {
        switch self {
        case .rawEvaluationPurposeMismatch:
            "Stem表示へ渡された解析結果がraw Stem用ではありません。"
        case .correctedEvaluationPurposeMismatch:
            "Stem表示へ渡された補正済み解析結果が対象Stemと一致しません。"
        case .correctionEvidenceMismatch:
            "Stem表示へ渡された補正計画、工程guard、成果物の証跡が一致しません。"
        }
    }
}

struct StemModeStemEvaluationPresentation: Identifiable, Sendable {
    let role: StemRole
    let rawEvaluation: StemAudioEvaluationSnapshot
    let roleAnalysisSnapshot: StemRoleAnalysisSnapshot?
    let executionPlan: StemCorrectionExecutionPlan?
    let stageGuards: [StemCorrectionStageGuardRecord]
    let correctedEvaluation: StemAudioEvaluationSnapshot?
    let usedRawFallback: Bool
    let fallbackReason: String?

    var id: StemRole { role }
    var hasCorrectionEvidence: Bool { executionPlan != nil }

    init(workflowEvaluation: StemWorkflowStemEvaluation) throws {
        guard case let .rawStem(role) = workflowEvaluation.rawEvaluation.purpose,
              workflowEvaluation.role == role,
              workflowEvaluation.rawArtifact.kind == .rawStem(role) else {
            throw StemModeStemEvaluationPresentationError.rawEvaluationPurposeMismatch
        }
        if let executionPlan = workflowEvaluation.executionPlan {
            let expectedStages = StemCorrectionStage.allCases
            guard executionPlan.role == role,
                  executionPlan.stages.map(\.stage) == expectedStages,
                  Set(executionPlan.stages.map(\.stage)).count == expectedStages.count,
                  workflowEvaluation.stageGuards.map(\.stage) == expectedStages,
                  Set(workflowEvaluation.stageGuards.map(\.stage)).count == expectedStages.count,
                  zip(executionPlan.stages, workflowEvaluation.stageGuards).allSatisfy({
                      $0.stage == $1.stage && $0.action == $1.action
                  }),
                  workflowEvaluation.correctedArtifact?.kind == .correctedStem(role),
                  workflowEvaluation.correctedEvaluation?.purpose == .correctedStem(role: role) else {
                throw StemModeStemEvaluationPresentationError.correctionEvidenceMismatch
            }
        } else {
            guard workflowEvaluation.stageGuards.isEmpty,
                  workflowEvaluation.correctedArtifact == nil,
                  workflowEvaluation.correctedEvaluation == nil,
                  !workflowEvaluation.usedRawFallback,
                  workflowEvaluation.fallbackReason == nil else {
                throw StemModeStemEvaluationPresentationError.correctionEvidenceMismatch
            }
        }
        if let correctedEvaluation = workflowEvaluation.correctedEvaluation,
           correctedEvaluation.purpose != .correctedStem(role: role) {
            throw StemModeStemEvaluationPresentationError.correctedEvaluationPurposeMismatch
        }
        if workflowEvaluation.usedRawFallback {
            guard let reason = workflowEvaluation.fallbackReason,
                  !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StemModeStemEvaluationPresentationError.correctionEvidenceMismatch
            }
        } else if workflowEvaluation.fallbackReason != nil {
            throw StemModeStemEvaluationPresentationError.correctionEvidenceMismatch
        }

        self.role = role
        rawEvaluation = workflowEvaluation.rawEvaluation
        roleAnalysisSnapshot = workflowEvaluation.roleAnalysisSnapshot
        executionPlan = workflowEvaluation.executionPlan
        stageGuards = workflowEvaluation.stageGuards
        correctedEvaluation = workflowEvaluation.correctedEvaluation
        usedRawFallback = workflowEvaluation.usedRawFallback
        fallbackReason = workflowEvaluation.fallbackReason
    }
}

struct StemModeQualityReports: Sendable {
    let audioQuality: AudioQualityReport
    let completion: CompletionReport
    let noiseCheck: NoiseCheckReport
    let masteringSettings: MasteringSettings

    init(masteringResult: StemMasteringResult) {
        audioQuality = masteringResult.audioQualityReport
        completion = masteringResult.completionReport
        noiseCheck = masteringResult.noiseCheckReport
        masteringSettings = masteringResult.masteringSettings
    }

    init(
        audioQuality: AudioQualityReport,
        completion: CompletionReport,
        noiseCheck: NoiseCheckReport,
        masteringSettings: MasteringSettings
    ) {
        self.audioQuality = audioQuality
        self.completion = completion
        self.noiseCheck = noiseCheck
        self.masteringSettings = masteringSettings
    }
}

struct StemModeWorkspaceErrorPresentation: Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let message: String

    init(
        id: UUID = UUID(),
        title: String,
        message: String
    ) {
        self.id = id
        self.title = title
        self.message = message
    }
}
