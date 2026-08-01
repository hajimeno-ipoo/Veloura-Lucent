import Foundation

struct StemWorkflowRequest: Sendable {
    let runID: UUID
    let sourceURL: URL
    let userConfirmedMatrix: StemUserConfirmedMixMatrix?
    let installation: ValidatedStemModelInstallation
    let manifest: StemModelManifest
    let separationSettings: StemSeparationSettings
    let correctionSettings: StemRoleCorrectionSettings
    let masteringSettings: MasteringSettings
    let analysisMode: StemAudioAnalysisMode

    init(
        runID: UUID,
        sourceURL: URL,
        userConfirmedMatrix: StemUserConfirmedMixMatrix?,
        installation: ValidatedStemModelInstallation,
        manifest: StemModelManifest,
        separationSettings: StemSeparationSettings,
        correctionSettings: StemRoleCorrectionSettings,
        masteringSettings: MasteringSettings,
        analysisMode: StemAudioAnalysisMode = .auto
    ) {
        self.runID = runID
        self.sourceURL = sourceURL
        self.userConfirmedMatrix = userConfirmedMatrix
        self.installation = installation
        self.manifest = manifest
        self.separationSettings = separationSettings
        self.correctionSettings = correctionSettings
        self.masteringSettings = masteringSettings
        self.analysisMode = analysisMode
    }
}

struct StemWorkflowMasteringRequest: Sendable {
    let remix: StemWorkflowRemixResult
    let masteringSettings: MasteringSettings

    var runID: UUID { remix.runID }
}

struct StemWorkflowExecutionProgress: Sendable, Equatable {
    let runID: UUID
    let step: StemWorkflowStep
    let fraction: Double
    let detail: String
}

struct StemWorkflowStemEvaluation: Sendable {
    let role: StemRole
    let rawArtifact: StemAudioArtifact
    let correctedArtifact: StemAudioArtifact?
    let rawEvaluation: StemAudioEvaluationSnapshot
    let roleAnalysisSnapshot: StemRoleAnalysisSnapshot?
    let executionPlan: StemCorrectionExecutionPlan?
    let stageGuards: [StemCorrectionStageGuardRecord]
    let correctedEvaluation: StemAudioEvaluationSnapshot?
    let usedRawFallback: Bool
    let fallbackReason: String?
}

struct StemWorkflowRemixArtifacts: Sendable {
    let correctedPureSum: StemAudioArtifact
}

enum StemWorkflowEvent: Sendable {
    case progress(StemWorkflowExecutionProgress)
    case displayProgress(StemModeProcessProgressEvent)
    case artifactCommitted(StemAudioArtifact)
    case validationCompleted(StemValidationResult)
    case stemEvaluationCompleted(StemWorkflowStemEvaluation)
    case log(runID: UUID, step: StemWorkflowStep, message: String)
}

struct StemWorkflowCorrectionResult: Sendable {
    let runID: UUID
    let sessionDirectory: URL
    let input: StemInputPreparedResult
    let canonicalInputEvaluation: StemAudioEvaluationSnapshot
    let separation: StemSeparationResult
    let separatedStemValidation: StemValidationResult
    let stemEvaluations: [StemWorkflowStemEvaluation]
    let remixArtifacts: StemWorkflowRemixArtifacts
    let rawRemixEvaluation: StemAudioEvaluationSnapshot
    let remixValidation: StemValidationResult
    let correctedRemixEvaluation: StemAudioEvaluationSnapshot
    let correctedRemixValidation: StemValidationResult
    let correctionSettings: StemRoleCorrectionSettings
    let analysisMode: StemAudioAnalysisMode
    let automaticRemixPlan: StemRemixAutomaticPlan
}

struct StemWorkflowRemixResult: Sendable {
    let correction: StemWorkflowCorrectionResult
    let artifact: StemAudioArtifact
    let evaluation: StemAudioEvaluationSnapshot
    let validation: StemValidationResult
    let appliedSettings: StemRemixSettings

    var runID: UUID { correction.runID }
}

struct StemWorkflowResult: Sendable {
    let runID: UUID
    let input: StemInputPreparedResult
    let canonicalInputEvaluation: StemAudioEvaluationSnapshot
    let separation: StemSeparationResult
    let separatedStemValidation: StemValidationResult
    let stemEvaluations: [StemWorkflowStemEvaluation]
    let remixArtifacts: StemWorkflowRemixArtifacts
    let rawRemixEvaluation: StemAudioEvaluationSnapshot
    let remixValidation: StemValidationResult
    let correctedRemixEvaluation: StemAudioEvaluationSnapshot
    let correctedRemixValidation: StemValidationResult
    let correctionSettings: StemRoleCorrectionSettings
    let remixedArtifact: StemAudioArtifact
    let remixEvaluation: StemAudioEvaluationSnapshot
    let processedRemixValidation: StemValidationResult
    let appliedRemixSettings: StemRemixSettings
    let masteringSource: StemMasteringSource
    let mastering: StemMasteringResult
}

enum StemWorkflowExecutionResult: Sendable {
    case correction(StemWorkflowCorrectionResult)
    case remix(StemWorkflowRemixResult)
    case mastered(StemWorkflowResult)
}

enum StemWorkflowServiceError: LocalizedError, Equatable, Sendable {
    case missingStem(StemRole)
    case correctionIncomplete
    case remixIncomplete
    case validationFailed(phase: StemValidationPhase, failures: [StemValidationFailure])
    case cleanupFailed(originalFailure: String, failures: [String])

    var errorDescription: String? {
        switch self {
        case .missingStem(let role): "Stem Modeに\(role.rawValue)がありません。"
        case .correctionIncomplete: "補正済み4Stemが揃っていないため、次の工程を開始できません。"
        case .remixIncomplete: "検証済みのStem再ミックスがないため、マスタリングを開始できません。"
        case let .validationFailed(phase, failures):
            "Stem Modeの\(phase.rawValue)構造検証に失敗しました（\(failures.count)件）。"
        case let .cleanupFailed(originalFailure, failures):
            "Stem工程失敗後の未完成ファイルを削除できませんでした（元の失敗: \(originalFailure)、削除失敗: \(failures.joined(separator: "; "))）。"
        }
    }
}

protocol StemWorkflowInputPreparing: Sendable {
    func resolveChannelMatrix(
        inputURL: URL,
        userConfirmedMatrix: StemUserConfirmedMixMatrix?
    ) throws -> StemInputChannelMatrix
    func prepare(
        inputURL: URL,
        outputURL: URL,
        resolvedChannelMatrix: StemInputChannelMatrix,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> StemInputPreparedResult
}

extension StemInputConversionService: StemWorkflowInputPreparing {}

protocol StemCorrecting: Sendable {
    func correct(
        runID: UUID,
        role: StemRole,
        rawSignal: AudioSignal,
        rawEvaluation: StemAudioEvaluationSnapshot,
        settings: CorrectionSettings,
        progressHandler: @escaping @Sendable (StemModeProcessProgressEvent) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StemCorrectionSignalResult
}

protocol StemWorkflowMastering: Sendable {
    func process(
        _ request: StemMasteringRequest,
        finalizationProgressHandler: @escaping @Sendable (StemModeProcessStepStatus) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StemMasteringResult
}

extension StemMasteringService: StemWorkflowMastering {}

private struct OrderedStemSeparationProgressSink: Sendable {
    private let continuation: AsyncStream<StemWorkflowExecutionProgress>.Continuation
    private let consumer: Task<Void, Never>

    init(eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void) {
        let (stream, continuation) = AsyncStream<StemWorkflowExecutionProgress>.makeStream()
        self.continuation = continuation
        consumer = Task {
            for await progress in stream {
                await eventHandler(.progress(progress))
                await eventHandler(.displayProgress(.init(
                    runID: progress.runID,
                    step: .separation,
                    status: progress.fraction >= 1 ? .completed : .running,
                    fraction: progress.fraction,
                    detail: progress.detail
                )))
            }
        }
    }

    func send(_ progress: StemWorkflowExecutionProgress) {
        continuation.yield(progress)
    }

    func finish() async {
        continuation.finish()
        await consumer.value
    }
}

private struct OrderedStemWorkflowEventSink: Sendable {
    private let continuation: AsyncStream<StemWorkflowEvent>.Continuation
    private let consumer: Task<Void, Never>

    init(eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void) {
        let (stream, continuation) = AsyncStream<StemWorkflowEvent>.makeStream()
        self.continuation = continuation
        consumer = Task {
            for await event in stream {
                await eventHandler(event)
            }
        }
    }

    func send(_ event: StemWorkflowEvent) {
        continuation.yield(event)
    }

    func finish() async {
        continuation.finish()
        await consumer.value
    }
}

/// Stem Modeの補正・再ミックス・マスタリング処理。状態は呼び出し側の現在セッションが保持し、
/// ディスクには処理に必要なWAVだけを置く。
struct StemWorkflowService: Sendable {
    static let temporaryRootURL = FileManager.default.temporaryDirectory
        .appending(path: "VelouraLucentStemPreview", directoryHint: .isDirectory)

    private static let roleOrder: [StemRole] = [.drums, .bass, .other, .vocals]
    private static let correctedFileNames: [StemRole: String] = [
        .drums: "corrected-drums.wav",
        .bass: "corrected-bass.wav",
        .other: "corrected-other.wav",
        .vocals: "corrected-vocals.wav",
    ]

    private let inputPreparer: any StemWorkflowInputPreparing
    private let separator: any StemSeparating
    private let store: StemTemporaryAudioStore
    private let corrector: any StemCorrecting
    private let validator: StemValidationService
    private let mixer: StemMixService
    private let remixSafetyGuard: any StemRemixSafetyGuarding
    private let remixRelativeAnalyzer: StemRemixRelativeAnalysisService
    private let remixService: StemRemixService
    private let masteringService: any StemWorkflowMastering

    init(
        inputPreparer: any StemWorkflowInputPreparing = StemInputConversionService(),
        separator: any StemSeparating = StemSeparationService(),
        store: StemTemporaryAudioStore = StemTemporaryAudioStore(),
        corrector: any StemCorrecting = StemCorrectionService(),
        validator: StemValidationService = StemValidationService(),
        mixer: StemMixService = StemMixService(),
        remixSafetyGuard: any StemRemixSafetyGuarding = StemRemixSafetyGuardService(),
        remixRelativeAnalyzer: StemRemixRelativeAnalysisService = StemRemixRelativeAnalysisService(),
        remixService: StemRemixService = StemRemixService(),
        masteringService: any StemWorkflowMastering = StemMasteringService()
    ) {
        self.inputPreparer = inputPreparer
        self.separator = separator
        self.store = store
        self.corrector = corrector
        self.validator = validator
        self.mixer = mixer
        self.remixSafetyGuard = remixSafetyGuard
        self.remixRelativeAnalyzer = remixRelativeAnalyzer
        self.remixService = remixService
        self.masteringService = masteringService
    }

    func processCorrection(
        _ request: StemWorkflowRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void = { _ in }
    ) async throws -> StemWorkflowCorrectionResult {
        let directory = Self.temporaryRootURL.appending(
            path: request.runID.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        do {
            await eventHandler(.log(
                runID: request.runID,
                step: .validateInput,
                message: "処理用入力音声を準備します"
            ))
            await eventHandler(.displayProgress(.init(
                runID: request.runID,
                step: .inputPreparation,
                status: .running,
                fraction: 0,
                detail: "入力変換・解析中"
            )))
            try store.removeDirectoryIfPresent(directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let matrix = try inputPreparer.resolveChannelMatrix(
                inputURL: request.sourceURL,
                userConfirmedMatrix: request.userConfirmedMatrix
            )
            let inputURL = directory.appending(path: "canonical-input-44100.wav")
            let prepared = try await inputPreparer.prepare(
                inputURL: request.sourceURL,
                outputURL: inputURL,
                resolvedChannelMatrix: matrix,
                progress: nil
            )
            await eventHandler(.artifactCommitted(prepared.artifact))
            let canonicalSignal = try await store.load(
                artifact: prepared.artifact,
                expectedURL: inputURL,
                expectedKind: .input44100
            )
            await eventHandler(.log(
                runID: request.runID,
                step: .validateInput,
                message: "処理用入力音声の準備が完了しました"
            ))
            await eventHandler(.log(
                runID: request.runID,
                step: .validateInput,
                message: "処理用入力音声を解析・ノイズ測定します"
            ))
            let canonicalEvaluation = try await evaluate(
                canonicalSignal,
                purpose: .canonicalInput,
                analysisMode: request.analysisMode,
                includeMastering: true
            )
            await eventHandler(.log(
                runID: request.runID,
                step: .validateInput,
                message: "処理用入力音声の解析・ノイズ測定が完了しました"
            ))
            await eventHandler(.displayProgress(.init(
                runID: request.runID,
                step: .inputPreparation,
                status: .completed,
                fraction: 1,
                detail: "入力変換・解析完了"
            )))
            try await progress(request.runID, .validateInput, 1, "入力変換・解析完了", eventHandler)

            await eventHandler(.log(
                runID: request.runID,
                step: .separate,
                message: "\(request.installation.snapshot.contract.separationModel.displayName)で4Stem分離を開始します"
            ))
            let separationProgress = OrderedStemSeparationProgressSink(eventHandler: eventHandler)
            let separation: StemSeparationResult
            do {
                separation = try await separator.separate(
                    inputArtifact: prepared.artifact,
                    installation: request.installation,
                    settings: request.separationSettings,
                    outputDirectory: directory.appending(path: "separated-stems", directoryHint: .isDirectory),
                    progressHandler: { update in
                        separationProgress.send(StemWorkflowExecutionProgress(
                            runID: request.runID,
                            step: .separate,
                            fraction: update.fraction,
                            detail: update.detail
                        ))
                    }
                )
                await separationProgress.finish()
            } catch {
                await separationProgress.finish()
                throw error
            }
            await eventHandler(.log(
                runID: request.runID,
                step: .separate,
                message: "\(request.installation.snapshot.contract.separationModel.displayName)で4Stem分離が完了しました"
            ))
            for artifact in separation.stems { await eventHandler(.artifactCommitted(artifact)) }
            let raw44 = try await loadRawStems(separation.stems)
            await eventHandler(.log(
                runID: request.runID,
                step: .validateSeparatedStems,
                message: "分離結果を検証します"
            ))
            await eventHandler(.displayProgress(.init(
                runID: request.runID,
                step: .separatedValidation,
                status: .running,
                fraction: 0,
                detail: "分離結果を検証中"
            )))
            let separatedValidation = validator.validateSeparatedStems(
                source: canonicalSignal,
                stems: Self.roleOrder.compactMap { role in
                    raw44[role].map { StemMixInput(role: role, signal: $0) }
                },
                expectedSampleRate: 44_100,
                expectedChannelCount: 2
            )
            await eventHandler(.validationCompleted(separatedValidation))
            guard separatedValidation.canContinue else {
                throw StemWorkflowServiceError.validationFailed(
                    phase: separatedValidation.phase,
                    failures: separatedValidation.failedChecks
                )
            }
            await eventHandler(.log(
                runID: request.runID,
                step: .validateSeparatedStems,
                message: "分離結果の検証が完了しました"
            ))
            await eventHandler(.displayProgress(.init(
                runID: request.runID,
                step: .separatedValidation,
                status: .completed,
                fraction: 1,
                detail: "分離結果検証完了"
            )))
            try await progress(request.runID, .validateSeparatedStems, 1, "分離結果検証完了", eventHandler)

            var evaluations: [StemWorkflowStemEvaluation] = []
            for (index, role) in Self.roleOrder.enumerated() {
                try Task.checkCancellation()
                guard let rawArtifact = separation.stems.first(where: { $0.kind == .rawStem(role) }),
                      let rawSignal44 = raw44[role] else {
                    throw StemWorkflowServiceError.missingStem(role)
                }
                await eventHandler(.log(
                    runID: request.runID,
                    step: .evaluateStems,
                    message: "\(role.stemModeDisplayTitle)を解析・ノイズ測定します"
                ))
                await eventHandler(.displayProgress(.init(
                    runID: request.runID,
                    step: .roleAnalysis(role),
                    status: .running,
                    fraction: 0,
                    detail: "\(role.stemModeDisplayTitle)を解析中"
                )))
                let rawSignal48 = try await convert(rawSignal44, to: 48_000)
                let rawEvaluation = try await evaluate(
                    rawSignal48,
                    purpose: .rawStem(role: role),
                    analysisMode: request.analysisMode,
                    includeMastering: false
                )
                await eventHandler(.log(
                    runID: request.runID,
                    step: .evaluateStems,
                    message: "\(role.stemModeDisplayTitle)の解析・ノイズ測定が完了しました"
                ))
                try await progress(
                    request.runID,
                    .evaluateStems,
                    Double(index + 1) / Double(Self.roleOrder.count),
                    "\(role.rawValue)解析完了",
                    eventHandler
                )

                let correctedSignal: AudioSignal
                let roleAnalysisSnapshot: StemRoleAnalysisSnapshot?
                let plan: StemCorrectionExecutionPlan?
                let guards: [StemCorrectionStageGuardRecord]
                let correctedEvaluation: StemAudioEvaluationSnapshot
                let usedRaw: Bool
                let fallbackReason: String?
                let correctionEventSink = OrderedStemWorkflowEventSink(eventHandler: eventHandler)
                do {
                    let result = try await corrector.correct(
                        runID: request.runID,
                        role: role,
                        rawSignal: rawSignal48,
                        rawEvaluation: rawEvaluation,
                        settings: request.correctionSettings.settings(for: role),
                        progressHandler: { progress in
                            correctionEventSink.send(.displayProgress(progress))
                        },
                        logHandler: { message in
                            correctionEventSink.send(.log(runID: request.runID, step: .correctStems, message: message))
                        }
                    )
                    await correctionEventSink.finish()
                    correctedSignal = result.correctedSignal
                    roleAnalysisSnapshot = result.roleAnalysisSnapshot
                    plan = result.executionPlan
                    guards = result.stageGuards
                    correctedEvaluation = result.correctedEvaluation
                    usedRaw = false
                    fallbackReason = nil
                } catch is CancellationError {
                    await correctionEventSink.finish()
                    throw CancellationError()
                } catch {
                    await correctionEventSink.finish()
                    await eventHandler(.displayProgress(.init(
                        runID: request.runID,
                        step: .roleAnalysis(role),
                        status: .skipped,
                        fraction: 1,
                        detail: "役割別解析または補正を完了できないためraw Stemを維持"
                    )))
                    for stage in StemCorrectionStage.allCases {
                        await eventHandler(.displayProgress(.init(
                            runID: request.runID,
                            step: .roleCorrection(role, stage: stage),
                            status: .skipped,
                            fraction: 1,
                            detail: "当該Stemをrawで維持"
                        )))
                    }
                    if role == .drums {
                        await eventHandler(.displayProgress(.init(
                            runID: request.runID,
                            step: .roleTransientRecovery(role),
                            status: .skipped,
                            fraction: 1,
                            detail: "当該Stemをrawで維持"
                        )))
                    }
                    correctedSignal = rawSignal48
                    roleAnalysisSnapshot = nil
                    plan = nil
                    guards = []
                    correctedEvaluation = try await evaluate(
                        rawSignal48,
                        purpose: .correctedStem(role: role),
                        analysisMode: request.analysisMode,
                        includeMastering: false
                    )
                    usedRaw = true
                    fallbackReason = error.localizedDescription
                    await eventHandler(.log(
                        runID: request.runID,
                        step: .correctStems,
                        message: "\(role.stemModeDisplayTitle)は補正処理を継続できないためraw Stemを使用"
                    ))
                }

                await eventHandler(.log(
                    runID: request.runID,
                    step: .correctStems,
                    message: "\(role.stemModeDisplayTitle)の補正後音声を解析・ノイズ測定しました"
                ))
                await eventHandler(.log(
                    runID: request.runID,
                    step: .correctStems,
                    message: "\(role.stemModeDisplayTitle)の補正結果を保存・検証します"
                ))
                await eventHandler(.displayProgress(.init(
                    runID: request.runID,
                    step: .roleSave(role),
                    status: .running,
                    fraction: 0,
                    detail: "\(role.stemModeDisplayTitle)を保存・検証中"
                )))
                let correctedURL = directory.appending(path: Self.correctedFileNames[role]!)
                let correctedArtifact = try await store.save(
                    signal: correctedSignal,
                    id: "corrected-\(role.rawValue)",
                    kind: .correctedStem(role),
                    to: correctedURL
                )
                _ = try await store.validate(
                    artifact: correctedArtifact,
                    expectedURL: correctedURL,
                    expectedKind: .correctedStem(role)
                )
                let evaluation = StemWorkflowStemEvaluation(
                    role: role,
                    rawArtifact: rawArtifact,
                    correctedArtifact: correctedArtifact,
                    rawEvaluation: rawEvaluation,
                    roleAnalysisSnapshot: roleAnalysisSnapshot,
                    executionPlan: plan,
                    stageGuards: guards,
                    correctedEvaluation: correctedEvaluation,
                    usedRawFallback: usedRaw,
                    fallbackReason: fallbackReason
                )
                evaluations.append(evaluation)
                await eventHandler(.artifactCommitted(correctedArtifact))
                await eventHandler(.stemEvaluationCompleted(evaluation))
                await eventHandler(.log(
                    runID: request.runID,
                    step: .correctStems,
                    message: "\(role.stemModeDisplayTitle)の補正結果を保存・検証しました"
                ))
                await eventHandler(.displayProgress(.init(
                    runID: request.runID,
                    step: .roleSave(role),
                    status: .completed,
                    fraction: 1,
                    detail: "\(role.stemModeDisplayTitle)保存・検証完了"
                )))
                try await progress(
                    request.runID,
                    .correctStems,
                    Double(index + 1) / Double(Self.roleOrder.count),
                    "\(role.rawValue)補正・保存完了",
                    eventHandler
                )
            }
            guard evaluations.count == Self.roleOrder.count,
                  evaluations.allSatisfy({ $0.correctedArtifact != nil }) else {
                throw StemWorkflowServiceError.correctionIncomplete
            }
            await eventHandler(.log(
                runID: request.runID,
                step: .validateCorrectedStems,
                message: "補正済み4Stemの保存を確認しました"
            ))
            try await progress(request.runID, .validateCorrectedStems, 1, "補正済み4Stem検証完了", eventHandler)

            await eventHandler(.log(
                runID: request.runID,
                step: .correctedPureSum,
                message: "分離後4Stemを純粋加算します"
            ))
            await eventHandler(.displayProgress(.init(
                runID: request.runID,
                step: .correctedPureSum,
                status: .running,
                fraction: 0,
                detail: "補正済み4Stemを純粋加算中"
            )))
            let rawRemix = try mixer.pureSum(stems: Self.roleOrder.compactMap { role in
                raw44[role].map { StemMixInput(role: role, signal: $0) }
            }).signal
            await eventHandler(.log(
                runID: request.runID,
                step: .correctedPureSum,
                message: "raw再ミックスを解析・ノイズ測定します"
            ))
            let rawRemixEvaluation = try await evaluate(
                rawRemix,
                purpose: .rawRemix,
                analysisMode: request.analysisMode,
                includeMastering: false
            )
            await eventHandler(.log(
                runID: request.runID,
                step: .validateCorrectedPureSum,
                message: "raw再ミックスを入力2mixと検証します"
            ))
            let remixValidation = validator.validateRemix(
                reference: canonicalSignal,
                remix: rawRemix,
                noiseContext: StemRemixNoiseValidationContext(
                    canonicalInput: canonicalEvaluation.noiseMeasurements,
                    rawRemix: rawRemixEvaluation.noiseMeasurements
                ),
                expectedSampleRate: 44_100,
                expectedChannelCount: 2
            )
            await eventHandler(.validationCompleted(remixValidation))
            guard remixValidation.canContinue else {
                throw StemWorkflowServiceError.validationFailed(
                    phase: remixValidation.phase,
                    failures: remixValidation.failedChecks
                )
            }
            await eventHandler(.log(
                runID: request.runID,
                step: .validateCorrectedPureSum,
                message: "raw再ミックスの検証が完了しました"
            ))

            let raw48 = try await convertSignals(raw44, to: 48_000)
            let corrected48 = try await loadCorrectedStems(evaluations)
            await eventHandler(.log(
                runID: request.runID,
                step: .validateCorrectedPureSum,
                message: "補正済み純粋加算の安全確認を行います"
            ))
            let guarded = remixSafetyGuard.protect(
                rawStemsByRole: raw48,
                correctedStemsByRole: corrected48
            )
            if guarded.rawFallbackReasons.isEmpty {
                await eventHandler(.log(
                    runID: request.runID,
                    step: .validateCorrectedPureSum,
                    message: "純粋加算安全確認: raw Stemへの差し替えなし"
                ))
            } else {
                for role in Self.roleOrder {
                    guard let reason = guarded.rawFallbackReasons[role] else { continue }
                    await eventHandler(.log(
                        runID: request.runID,
                        step: .validateCorrectedPureSum,
                        message: "純粋加算安全確認: \(role.stemModeDisplayTitle)をraw Stemへ戻しました"
                    ))
                    await eventHandler(.log(
                        runID: request.runID,
                        step: .validateCorrectedPureSum,
                        message: "理由: \(reason)"
                    ))
                }
            }
            await eventHandler(.log(
                runID: request.runID,
                step: .correctedPureSum,
                message: "補正済み4Stemをgain・pan・reverbなしで純粋加算します"
            ))
            let correctedPureSum = try mixer.pureSum(stems: Self.roleOrder.compactMap { role in
                guarded.stemsByRole[role].map { StemMixInput(role: role, signal: $0) }
            }).signal
            let correctedPureSumURL = directory.appending(path: "corrected-pure-sum-48000.wav")
            await eventHandler(.log(
                runID: request.runID,
                step: .correctedPureSum,
                message: "補正済み純粋加算を保存します"
            ))
            let correctedArtifact = try await store.save(
                signal: correctedPureSum,
                id: "corrected-pure-sum",
                kind: .correctedPureSum48000,
                to: correctedPureSumURL
            )
            await eventHandler(.log(
                runID: request.runID,
                step: .correctedPureSum,
                message: "補正済み純粋加算を解析・ノイズ測定します"
            ))
            let correctedEvaluation = try await evaluate(
                correctedPureSum,
                purpose: .correctedPureSum,
                analysisMode: request.analysisMode,
                includeMastering: true
            )
            await eventHandler(.log(
                runID: request.runID,
                step: .validateCorrectedPureSum,
                message: "補正済み純粋加算を検証します"
            ))
            await eventHandler(.displayProgress(.init(
                runID: request.runID,
                step: .correctedPureSumValidation,
                status: .running,
                fraction: 0,
                detail: "補正済み純粋加算を検証中"
            )))
            let canonical48 = try await convert(canonicalSignal, to: 48_000)
            let rawRemix48 = try await convert(rawRemix, to: 48_000)
            var correctedValidation = validator.validateCorrectedRemix(
                canonicalReference: canonical48,
                rawRemix: rawRemix48,
                correctedRemix: correctedPureSum,
                noiseContext: StemCorrectedRemixNoiseValidationContext(
                    canonicalInput: canonicalEvaluation.noiseMeasurements,
                    rawRemix: rawRemixEvaluation.noiseMeasurements,
                    correctedPureSum: correctedEvaluation.noiseMeasurements
                ),
                expectedSampleRate: 48_000,
                expectedChannelCount: 2
            )
            correctedValidation = StemValidationResult(
                phase: correctedValidation.phase,
                failedChecks: correctedValidation.failedChecks,
                measurements: correctedValidation.measurements + remixRelativeAnalyzer.measurements(
                    rawStemsByRole: raw48,
                    correctedStemsByRole: guarded.stemsByRole,
                    evaluations: evaluations
                )
            )
            await eventHandler(.validationCompleted(correctedValidation))
            guard correctedValidation.canContinue else {
                throw StemWorkflowServiceError.validationFailed(
                    phase: correctedValidation.phase,
                    failures: correctedValidation.failedChecks
                )
            }
            await eventHandler(.log(
                runID: request.runID,
                step: .validateCorrectedPureSum,
                message: "補正済み純粋加算の検証が完了しました"
            ))
            await eventHandler(.artifactCommitted(correctedArtifact))
            await eventHandler(.displayProgress(.init(
                runID: request.runID,
                step: .correctedPureSum,
                status: .completed,
                fraction: 1,
                detail: "補正済み4Stemの純粋加算完了"
            )))
            await eventHandler(.displayProgress(.init(
                runID: request.runID,
                step: .correctedPureSumValidation,
                status: .completed,
                fraction: 1,
                detail: "純粋加算検証完了"
            )))
            try await progress(request.runID, .correctedPureSum, 1, "補正済み4Stemの純粋加算完了", eventHandler)
            try await progress(request.runID, .validateCorrectedPureSum, 1, "純粋加算検証完了", eventHandler)
            await eventHandler(.log(
                runID: request.runID,
                step: .validateCorrectedPureSum,
                message: "補正処理が完了しました"
            ))
            let automaticRemixPlan = try remixService.makeAutomaticPlan(
                stems: try Self.roleOrder.map { role in
                    guard let raw = raw48[role],
                          let corrected = guarded.stemsByRole[role] else {
                        throw StemWorkflowServiceError.missingStem(role)
                    }
                    return StemRemixSignal(
                        role: role,
                        raw: raw,
                        corrected: corrected
                    )
                }
            )

            return StemWorkflowCorrectionResult(
                runID: request.runID,
                sessionDirectory: directory,
                input: prepared,
                canonicalInputEvaluation: canonicalEvaluation,
                separation: separation,
                separatedStemValidation: separatedValidation,
                stemEvaluations: evaluations,
                remixArtifacts: StemWorkflowRemixArtifacts(correctedPureSum: correctedArtifact),
                rawRemixEvaluation: rawRemixEvaluation,
                remixValidation: remixValidation,
                correctedRemixEvaluation: correctedEvaluation,
                correctedRemixValidation: correctedValidation,
                correctionSettings: request.correctionSettings,
                analysisMode: request.analysisMode,
                automaticRemixPlan: automaticRemixPlan
            )
        } catch {
            let originalFailure = error.localizedDescription
            do { try store.removeDirectoryIfPresent(directory) }
            catch let cleanupError {
                throw StemWorkflowServiceError.cleanupFailed(
                    originalFailure: originalFailure,
                    failures: [cleanupError.localizedDescription]
                )
            }
            throw error
        }
    }

    func processRemix(
        correction: StemWorkflowCorrectionResult,
        settings: StemRemixSettings,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void = { _ in }
    ) async throws -> StemWorkflowRemixResult {
        guard correction.stemEvaluations.count == Self.roleOrder.count,
              correction.stemEvaluations.allSatisfy({ $0.correctedArtifact != nil }) else {
            throw StemWorkflowServiceError.correctionIncomplete
        }
        let remixURL = correction.sessionDirectory.appending(path: "stem-remix-48000.wav")
        let finalURL = correction.sessionDirectory.appending(
            path: StemMasteringService.finalMasterFileName
        )
        var didComplete = false
        defer {
            if !didComplete {
                try? store.removeIfPresent(remixURL)
                try? store.removeIfPresent(finalURL)
            }
        }
        try Task.checkCancellation()
        await eventHandler(.displayProgress(.init(
            runID: correction.runID,
            step: .automaticRemixPlan,
            status: .completed,
            fraction: 1,
            detail: "今回のraw／補正済みStemから自動値を算出済み"
        )))
        await eventHandler(.log(
            runID: correction.runID,
            step: .remix,
            message: "今回のraw／補正済みStemから自動gain・pan・衝突回避・reverb値を確認しました"
        ))
        await eventHandler(.log(
            runID: correction.runID,
            step: .remix,
            message: "自動設定とユーザー上書きを確定してStem再ミックスを開始します"
        ))

        let raw44 = try await loadRawStems(correction.separation.stems)
        let raw48 = try await convertSignals(raw44, to: 48_000)
        let corrected48 = try await loadCorrectedStems(correction.stemEvaluations)
        let guarded = remixSafetyGuard.protect(
            rawStemsByRole: raw48,
            correctedStemsByRole: corrected48
        )
        let remixSignals = try Self.roleOrder.map { role in
            guard let raw = raw48[role],
                  let corrected = guarded.stemsByRole[role] else {
                throw StemWorkflowServiceError.missingStem(role)
            }
            return StemRemixSignal(role: role, raw: raw, corrected: corrected)
        }
        let remixEventSink = OrderedStemWorkflowEventSink(eventHandler: eventHandler)
        let render: StemRemixRenderResult
        do {
            render = try remixService.render(
                stems: remixSignals,
                settings: settings
            ) { stage, state in
                let status: StemModeProcessStepStatus = state == .running
                    ? .running
                    : .completed
                remixEventSink.send(.displayProgress(.init(
                    runID: correction.runID,
                    step: stage.stemModeProcessStep,
                    status: status,
                    fraction: state == .running ? 0 : 1,
                    detail: state == .running
                        ? stage.stemModeRunningDetail
                        : stage.stemModeCompletedDetail
                )))
                if state == .completed {
                    remixEventSink.send(.log(
                        runID: correction.runID,
                        step: .remix,
                        message: stage.stemModeCompletedDetail
                    ))
                }
            }
            await remixEventSink.finish()
        } catch {
            await remixEventSink.finish()
            throw error
        }
        await eventHandler(.displayProgress(.init(
            runID: correction.runID,
            step: .remixSave,
            status: .running,
            fraction: 0,
            detail: "再ミックス成果物を保存中"
        )))
        try store.removeIfPresent(remixURL)
        try store.removeIfPresent(finalURL)
        let artifact = try await store.save(
            signal: render.signal,
            id: "stem-remix",
            kind: .remixed48000,
            to: remixURL
        )
        await eventHandler(.displayProgress(.init(
            runID: correction.runID,
            step: .remixSave,
            status: .completed,
            fraction: 1,
            detail: "Stem再ミックスを保存"
        )))
        let evaluation = try await evaluate(
            render.signal,
            purpose: .remix,
            analysisMode: correction.analysisMode,
            includeMastering: true
        )
        let pureSum = try await store.load(
            artifact: correction.remixArtifacts.correctedPureSum,
            expectedURL: correction.remixArtifacts.correctedPureSum.fileURL,
            expectedKind: .correctedPureSum48000
        )
        await eventHandler(.displayProgress(.init(
            runID: correction.runID,
            step: .remixValidation,
            status: .running,
            fraction: 0,
            detail: "再ミックスの構造・有限値・ピークを検証中"
        )))
        let validation = validator.validateProcessedRemix(
            correctedPureSum: pureSum,
            remixed: render.signal,
            expectedSampleRate: 48_000,
            expectedChannelCount: 2
        )
        await eventHandler(.validationCompleted(validation))
        guard validation.canContinue else {
            try store.removeIfPresent(remixURL)
            throw StemWorkflowServiceError.validationFailed(
                phase: validation.phase,
                failures: validation.failedChecks
            )
        }
        await eventHandler(.artifactCommitted(artifact))
        await eventHandler(.displayProgress(.init(
            runID: correction.runID,
            step: .remixValidation,
            status: .completed,
            fraction: 1,
            detail: "再ミックス検証完了"
        )))
        await eventHandler(.log(
            runID: correction.runID,
            step: .validateRemix,
            message: "再ミックスの構造・有限値・ピーク検証を完了しました"
        ))
        try await progress(correction.runID, .remix, 1, "Stem再ミックス完了", eventHandler)
        try await progress(correction.runID, .validateRemix, 1, "Stem再ミックス検証完了", eventHandler)
        let result = StemWorkflowRemixResult(
            correction: correction,
            artifact: artifact,
            evaluation: evaluation,
            validation: validation,
            appliedSettings: settings
        )
        didComplete = true
        return result
    }

    func processMastering(
        _ request: StemWorkflowMasteringRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void = { _ in }
    ) async throws -> StemWorkflowResult {
        let remix = request.remix
        let correction = remix.correction
        guard correction.stemEvaluations.count == Self.roleOrder.count,
              correction.stemEvaluations.allSatisfy({ $0.correctedArtifact != nil }) else {
            throw StemWorkflowServiceError.correctionIncomplete
        }
        let canonicalReference = try StemCanonicalMasteringReference(
            artifact: correction.input.artifact,
            evaluation: correction.canonicalInputEvaluation
        )
        let masteringInput = try StemMasteringInputMaterial(
            artifact: remix.artifact,
            evaluation: remix.evaluation
        )
        let masteringEventSink = OrderedStemWorkflowEventSink(eventHandler: eventHandler)
        let mastering: StemMasteringResult
        do {
            mastering = try await masteringService.process(
                StemMasteringRequest(
                runID: request.runID,
                sessionDirectory: correction.sessionDirectory,
                canonicalReference: canonicalReference,
                masteringInput: masteringInput,
                correctionSettings: correction.correctionSettings,
                settings: request.masteringSettings
                ),
                finalizationProgressHandler: { status in
                    masteringEventSink.send(.displayProgress(.init(
                        runID: request.runID,
                        step: .finalization,
                        status: status,
                        fraction: status == .completed ? 1 : 0,
                        detail: status == .completed ? "最終版解析・保存完了" : "最終版を解析・保存中"
                    )))
                },
                logHandler: { message in
                    masteringEventSink.send(.log(runID: request.runID, step: .mastering, message: message))
                }
            )
            await masteringEventSink.finish()
        } catch {
            await masteringEventSink.finish()
            throw error
        }
        await eventHandler(.artifactCommitted(mastering.finalArtifact))
        try await progress(request.runID, .mastering, 1, "既存マスタリング完了", eventHandler)
        try await progress(request.runID, .finalizeMaster, 1, "Stem Mode最終版解析・保存完了", eventHandler)
        return StemWorkflowResult(
            runID: request.runID,
            input: correction.input,
            canonicalInputEvaluation: correction.canonicalInputEvaluation,
            separation: correction.separation,
            separatedStemValidation: correction.separatedStemValidation,
            stemEvaluations: correction.stemEvaluations,
            remixArtifacts: correction.remixArtifacts,
            rawRemixEvaluation: correction.rawRemixEvaluation,
            remixValidation: correction.remixValidation,
            correctedRemixEvaluation: correction.correctedRemixEvaluation,
            correctedRemixValidation: correction.correctedRemixValidation,
            correctionSettings: correction.correctionSettings,
            remixedArtifact: remix.artifact,
            remixEvaluation: remix.evaluation,
            processedRemixValidation: remix.validation,
            appliedRemixSettings: remix.appliedSettings,
            masteringSource: .remix,
            mastering: mastering
        )
    }

    func discardTemporarySession(runID: UUID) throws {
        try store.removeDirectoryIfPresent(Self.temporaryRootURL.appending(
            path: runID.uuidString.lowercased(),
            directoryHint: .isDirectory
        ))
    }

    private func loadRawStems(_ artifacts: [StemAudioArtifact]) async throws -> [StemRole: AudioSignal] {
        var result: [StemRole: AudioSignal] = [:]
        for role in Self.roleOrder {
            guard let artifact = artifacts.first(where: { $0.kind == .rawStem(role) }) else {
                throw StemWorkflowServiceError.missingStem(role)
            }
            result[role] = try await store.load(
                artifact: artifact,
                expectedURL: artifact.fileURL,
                expectedKind: .rawStem(role)
            )
        }
        return result
    }

    private func loadCorrectedStems(
        _ evaluations: [StemWorkflowStemEvaluation]
    ) async throws -> [StemRole: AudioSignal] {
        var result: [StemRole: AudioSignal] = [:]
        for role in Self.roleOrder {
            guard let artifact = evaluations.first(where: { $0.role == role })?.correctedArtifact else {
                throw StemWorkflowServiceError.missingStem(role)
            }
            result[role] = try await store.load(
                artifact: artifact,
                expectedURL: artifact.fileURL,
                expectedKind: .correctedStem(role)
            )
        }
        return result
    }

    private func convertSignals(
        _ signals: [StemRole: AudioSignal],
        to sampleRate: Double
    ) async throws -> [StemRole: AudioSignal] {
        var converted: [StemRole: AudioSignal] = [:]
        for role in Self.roleOrder {
            guard let signal = signals[role] else { throw StemWorkflowServiceError.missingStem(role) }
            converted[role] = try await convert(signal, to: sampleRate)
        }
        return converted
    }

    private func convert(_ signal: AudioSignal, to sampleRate: Double) async throws -> AudioSignal {
        if signal.sampleRate == sampleRate { return signal }
        return try await Task.detached(priority: .userInitiated) {
            try AudioSignalSampleRateConverter.convert(signal, to: sampleRate)
        }.value
    }

    private func evaluate(
        _ signal: AudioSignal,
        purpose: StemAudioEvaluationPurpose,
        analysisMode: StemAudioAnalysisMode,
        includeMastering: Bool
    ) async throws -> StemAudioEvaluationSnapshot {
        try await StemAudioEvaluationService.evaluate(
            signal: signal,
            request: StemAudioEvaluationRequest(
                purpose: purpose,
                includeAudioAnalyzerSnapshot: true,
                includeMasteringAnalysisSnapshot: includeMastering,
                analysisMode: analysisMode
            )
        )
    }

    private func progress(
        _ runID: UUID,
        _ step: StemWorkflowStep,
        _ fraction: Double,
        _ detail: String,
        _ handler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws {
        guard fraction.isFinite, (0...1).contains(fraction) else { return }
        try Task.checkCancellation()
        await handler(.progress(StemWorkflowExecutionProgress(
            runID: runID,
            step: step,
            fraction: fraction,
            detail: detail
        )))
    }
}
