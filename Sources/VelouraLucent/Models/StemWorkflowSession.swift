import Foundation
import Observation

enum StemWorkflowSessionError: LocalizedError, Equatable, Sendable {
    case runAlreadyActive(UUID)
    case noActiveRun
    case runMismatch(expected: UUID, actual: UUID)
    case runIsTerminal
    case artifactIdentifierMismatch(expected: String, actual: String)
    case artifactKindMismatch
    case artifactOutsideRunContract(String)
    case progressOutsideRunContract(String)
    case validationOutsideRunContract(String)
    case completionRequiresCompletedExport
    case correctionCompletionRequiresCorrectedStems
    case remixRequiresCorrectionCompletion
    case masteringRequiresRemixCompletion

    var errorDescription: String? {
        switch self {
        case .runAlreadyActive(let runID):
            return "別のStem Mode処理が実行中です（セッション: \(runID.uuidString)）。"
        case .noActiveRun:
            return "対象となるStem Mode処理がありません。"
        case .runMismatch(let expected, let actual):
            return "Stem Mode処理の識別子が一致しません（現在: \(expected.uuidString)、受信: \(actual.uuidString)）。"
        case .runIsTerminal:
            return "完了・失敗したStem Mode処理は更新できません。"
        case .artifactIdentifierMismatch(let expected, let actual):
            return "Stem Mode成果物の識別子が一致しません（表示: \(expected)、成果物: \(actual)）。"
        case .artifactKindMismatch:
            return "Stem Mode成果物の種類が表示状態と一致しません。"
        case .artifactOutsideRunContract(let description):
            return "現在のモデル契約に含まれないStem Mode成果物は反映しません（\(description)）。"
        case .progressOutsideRunContract(let identifier):
            return "現在のモデル契約に含まれない進捗工程は反映しません（\(identifier)）。"
        case .validationOutsideRunContract(let description):
            return "現在のモデル契約に含まれない検証結果は反映しません（\(description)）。"
        case .completionRequiresCompletedExport:
            return "Stem Modeの完了には最終版生成工程の完了が必要です。"
        case .correctionCompletionRequiresCorrectedStems:
            return "Stem Modeの補正完了には契約対象の補正済みStemと補正済み純粋加算の検証・保存完了が必要です。"
        case .remixRequiresCorrectionCompletion:
            return "契約対象の補正済みStemと純粋加算が揃った現在セッションだけ再ミックスを開始できます。"
        case .masteringRequiresRemixCompletion:
            return "検証済みStem再ミックスが揃った現在セッションだけマスタリングを開始できます。"
        }
    }
}

enum StemWorkflowArtifactDisplayStatus: Equatable, Sendable {
    case preparing
    case available
    case validating
    case valid
    case invalid(message: String)
}

struct StemWorkflowArtifactDisplayState: Identifiable, Equatable, Sendable {
    let id: String
    let runID: UUID
    let kind: StemArtifactKind
    let artifact: StemAudioArtifact?
    let status: StemWorkflowArtifactDisplayStatus
    let updatedAt: Date

    init(
        id: String,
        runID: UUID,
        kind: StemArtifactKind,
        artifact: StemAudioArtifact? = nil,
        status: StemWorkflowArtifactDisplayStatus,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.runID = runID
        self.kind = kind
        self.artifact = artifact
        self.status = status
        self.updatedAt = updatedAt
    }
}

enum StemWorkflowValidationSubject: Equatable, Hashable, Sendable {
    case input
    case separatedStems
    case stem(String)
    case rawRemix
    case correctedPureSum
    case remix
    case finalMaster
}

enum StemWorkflowValidationStatus: Equatable, Sendable {
    case pending
    case running(detail: String?)
    case passed(summary: String?)
    case failed(message: String)
}

struct StemWorkflowValidationDisplayState: Identifiable, Equatable, Sendable {
    let runID: UUID
    let subject: StemWorkflowValidationSubject
    let status: StemWorkflowValidationStatus
    let updatedAt: Date

    var id: StemWorkflowValidationSubject { subject }

    init(
        runID: UUID,
        subject: StemWorkflowValidationSubject,
        status: StemWorkflowValidationStatus,
        updatedAt: Date = Date()
    ) {
        self.runID = runID
        self.subject = subject
        self.status = status
        self.updatedAt = updatedAt
    }
}

struct StemWorkflowErrorDisplayState: Equatable, Sendable {
    let runID: UUID
    let timestamp: Date
    let step: StemWorkflowStep?
    let message: String
    let recoverySuggestion: String?
}

/// Stem Modeだけの表示状態を所有します。非同期処理から届く更新は必ずrun ID付きで受け、
/// 通常モードの処理状態や通知処理には触れません。
@MainActor
@Observable
final class StemWorkflowSession {
    private static let correctionSteps: [StemWorkflowStep] = [
        .validateInput,
        .separate,
        .validateSeparatedStems,
        .evaluateStems,
        .correctStems,
        .validateCorrectedStems,
        .correctedPureSum,
        .validateCorrectedPureSum,
    ]
    private static let remixSteps: [StemWorkflowStep] = [
        .remix,
        .validateRemix,
    ]
    private static let masteringSteps: [StemWorkflowStep] = [
        .mastering,
        .finalizeMaster,
    ]

    private(set) var state: StemWorkflowState = .idle
    private(set) var runID: UUID?
    private(set) var runContract: StemModelRunContract?
    private(set) var stepProgress: [StemWorkflowStepProgress] = StemWorkflowSession.pendingSteps()
    private(set) var displayProgress: [StemModeProcessStepProgress] = StemWorkflowSession.pendingDisplaySteps()
    private(set) var logs: [StemWorkflowLogEntry] = []
    private(set) var inputDisplayLogLines: [String] = []
    private(set) var activityEvents: [RecentActivityEvent] = []
    private(set) var lastError: StemWorkflowErrorDisplayState?
    private(set) var artifactStates: [StemWorkflowArtifactDisplayState] = []
    private(set) var validationStates: [StemWorkflowValidationDisplayState] = []
    private(set) var correctionStartedAt: Date?
    private(set) var correctionFinishedAt: Date?
    private(set) var remixStartedAt: Date?
    private(set) var remixFinishedAt: Date?
    private(set) var masteringStartedAt: Date?
    private(set) var masteringFinishedAt: Date?
    private(set) var lastExportedDestinationURL: URL?

    var isCorrectionProcessing: Bool {
        correctionStartedAt != nil && correctionFinishedAt == nil
    }

    var isMasteringProcessing: Bool {
        masteringStartedAt != nil && masteringFinishedAt == nil
    }

    var isRemixProcessing: Bool {
        remixStartedAt != nil && remixFinishedAt == nil
    }

    var currentStep: StemWorkflowStep? {
        stepProgress.first(where: { $0.status == .running })?.step
            ?? stepProgress.last(where: { $0.status == .completed || $0.status == .failed })?.step
    }

    var recentActivityEvents: [RecentActivityEvent] {
        Array(activityEvents.suffix(4))
    }

    var correctionLogLines: [String] {
        inputDisplayLogLines + logLines(for: Self.correctionLogSteps)
    }

    var masteringLogLines: [String] {
        logLines(for: Self.masteringLogSteps)
    }

    var remixLogLines: [String] {
        logLines(for: Self.remixLogSteps)
    }

    var expectedCorrectionArtifactCount: Int {
        guard let runContract else { return 0 }
        return runContract.activeRoles.count + runContract.validationRoles.count + 2
    }

    var expectedCompletedArtifactCount: Int {
        guard runContract != nil else { return 0 }
        return expectedCorrectionArtifactCount + 2
    }

    func progress(for step: StemWorkflowStep) -> StemWorkflowStepProgress {
        // `pendingSteps` guarantees one entry for every case.
        stepProgress.first(where: { $0.step == step })!
    }

    func displayProgress(for step: StemModeProcessStep) -> StemModeProcessStepProgress {
        displayProgress.first(where: { $0.step == step })
            ?? StemModeProcessStepProgress(step: step, status: .pending, fraction: 0)
    }

    var correctionDisplayProgress: [StemModeProcessStepProgress] {
        displayProgress.filter { $0.step.domain == .correction }
    }

    var masteringDisplayProgress: [StemModeProcessStepProgress] {
        displayProgress.filter { $0.step.domain == .mastering }
    }

    var remixDisplayProgress: [StemModeProcessStepProgress] {
        displayProgress.filter { $0.step.domain == .remix }
    }

    func displayProgressValue(for domain: StemModeProcessDomain) -> Double {
        let values = displayProgress.filter { $0.step.domain == domain }
        guard !values.isEmpty else { return 0 }
        return values.map(\.fraction).reduce(0, +) / Double(values.count)
    }

    func recordInputSelection(
        URL: URL,
        fileInfo: AudioFileInfo?,
        at timestamp: Date = Date()
    ) {
        activityEvents = []
        inputDisplayLogLines = []
        appendActivity(
            timestamp: timestamp,
            domain: .input,
            title: "ファイルを読み込みました",
            fileURL: URL,
            fileInfo: fileInfo
        )
    }

    func recordInputAnalysis(
        evaluation: StemAudioEvaluationSnapshot?,
        warning: String?,
        at timestamp: Date = Date()
    ) {
        let detail: String?
        if let metrics = evaluation?.audioMetrics {
            detail = String(
                format: "ラウドネス: %.1f LUFS / ピーク: %.1f dBTP",
                metrics.integratedLoudnessLUFS,
                metrics.truePeakDBFS
            )
        } else {
            detail = warning ?? "表示用解析を完了しました"
        }
        appendActivity(
            timestamp: timestamp,
            domain: .input,
            title: warning == nil ? "入力音源を解析しました" : "入力解析を完了しました（警告あり）",
            detail: detail
        )
    }

    func recordInputAnalysisFailure(_ message: String, at timestamp: Date = Date()) {
        appendActivity(
            timestamp: timestamp,
            domain: .input,
            title: "入力音源を解析できませんでした",
            detail: message,
            hasFailed: true
        )
    }

    func recordInputDisplayAnalysisLog(
        _ message: String,
        at timestamp: Date = Date()
    ) {
        if let runID {
            appendLogUnchecked(
                runID: runID,
                timestamp: timestamp,
                level: .info,
                step: .validateInput,
                message: message
            )
        } else {
            inputDisplayLogLines.append(message)
        }
    }

    func recordCorrectedRemixAnalysis(
        _ metrics: AudioMetricSnapshot,
        at timestamp: Date = Date()
    ) {
        appendMetricActivity(
            timestamp: timestamp,
            domain: .correction,
            title: "補正済み純粋加算を解析しました",
            metrics: metrics
        )
    }

    func recordFinalAnalysis(
        _ metrics: AudioMetricSnapshot,
        at timestamp: Date = Date()
    ) {
        appendMetricActivity(
            timestamp: timestamp,
            domain: .mastering,
            title: "Stem Mode最終版を解析しました",
            metrics: metrics
        )
    }

    func startRun(
        runID: UUID,
        runContract: StemModelRunContract,
        at timestamp: Date = Date()
    ) throws {
        if let activeRunID = self.runID {
            if case .completed = state {
                resetRunDisplayState()
            } else if case .failed = state {
                resetRunDisplayState()
            } else {
                throw StemWorkflowSessionError.runAlreadyActive(activeRunID)
            }
        }

        self.runID = runID
        self.runContract = runContract
        state = .ready
        stepProgress = Self.pendingSteps()
        displayProgress = Self.pendingDisplaySteps(roles: runContract.activeRoles)
        logs = []
        inputDisplayLogLines = []
        lastError = nil
        artifactStates = []
        validationStates = []
        correctionStartedAt = timestamp
        correctionFinishedAt = nil
        remixStartedAt = nil
        remixFinishedAt = nil
        masteringStartedAt = nil
        masteringFinishedAt = nil
        lastExportedDestinationURL = nil
        appendActivity(
            timestamp: timestamp,
            domain: .correction,
            title: "補正処理を実行中",
            detail: "処理用入力準備",
            progress: 0,
            isRunning: true
        )
    }

    func applyDisplayProgress(
        _ event: StemModeProcessProgressEvent,
        at timestamp: Date = Date()
    ) throws {
        try requireRun(event.runID)
        guard let existing = displayProgress.first(where: { $0.step == event.step }) else {
            throw StemWorkflowSessionError.progressOutsideRunContract(event.step.id)
        }
        if existing.status == .completed || existing.status == .skipped || existing.status == .failed {
            return
        }
        let progress = StemModeProcessStepProgress(
            step: event.step,
            status: event.status,
            fraction: event.status == .completed || event.status == .skipped ? 1 : event.fraction,
            detail: event.detail
        )
        let index = displayProgress.firstIndex(where: { $0.step == event.step })!
        displayProgress[index] = progress

        let activityDomain: RecentActivityDomain = switch event.step.domain {
        case .correction: .correction
        case .remix: .remix
        case .mastering: .mastering
        }
        let activityTitle = switch event.step.domain {
        case .correction: "補正処理を実行中"
        case .remix: "再ミックスを実行中"
        case .mastering: "マスタリングを実行中"
        }
        updateRunningActivity(
            timestamp: timestamp,
            domain: activityDomain,
            title: activityTitle,
            detail: [event.step.title, event.detail].compactMap { $0 }.joined(separator: ": "),
            progress: displayProgressValue(for: event.step.domain)
        )
    }

    func beginStep(
        runID: UUID,
        step: StemWorkflowStep,
        detail: String? = nil,
        at _: Date = Date()
    ) throws {
        try requireMutableRun(runID)
        if let runningStep = stepProgress.first(where: { $0.status == .running })?.step {
            if runningStep == step {
                let existing = progress(for: step)
                replaceProgress(StemWorkflowStepProgress(
                    step: step,
                    status: .running,
                    fraction: existing.fraction,
                    detail: detail ?? existing.detail
                ))
                return
            }
            let running = progress(for: runningStep)
            replaceProgress(StemWorkflowStepProgress(
                step: runningStep,
                status: .completed,
                fraction: 1,
                detail: running.detail
            ))
        }

        let existing = progress(for: step)
        if existing.status == .completed || existing.status == .failed {
            return
        }

        replaceProgress(
            StemWorkflowStepProgress(
                step: step,
                status: .running,
                fraction: existing.fraction,
                detail: detail
            )
        )
        state = .running(step: step)

    }

    func updateProgress(
        runID: UUID,
        step: StemWorkflowStep,
        fraction: Double,
        detail: String? = nil
    ) throws {
        try requireMutableRun(runID)
        let existing = progress(for: step)
        if existing.status == .completed || existing.status == .failed {
            return
        }
        replaceProgress(
            StemWorkflowStepProgress(
                step: step,
                status: .running,
                fraction: fraction,
                detail: detail ?? existing.detail
            )
        )
        state = .running(step: step)
    }

    func completeStep(
        runID: UUID,
        step: StemWorkflowStep,
        detail: String? = nil,
        at _: Date = Date()
    ) throws {
        try requireMutableRun(runID)
        let existing = progress(for: step)
        if existing.status == .completed || existing.status == .failed {
            return
        }
        replaceProgress(
            StemWorkflowStepProgress(
                step: step,
                status: .completed,
                fraction: 1,
                detail: detail ?? existing.detail
            )
        )
        state = .ready

    }

    func appendLog(
        runID: UUID,
        level: StemWorkflowLogLevel,
        step: StemWorkflowStep?,
        message: String,
        at timestamp: Date = Date()
    ) throws {
        try requireRun(runID)
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: level,
            step: step,
            message: message
        )
    }

    func updateArtifactState(
        _ displayState: StemWorkflowArtifactDisplayState,
        at _: Date = Date()
    ) throws {
        try requireRun(displayState.runID)
        guard let runContract else {
            throw StemWorkflowSessionError.noActiveRun
        }
        if let artifact = displayState.artifact, artifact.id != displayState.id {
            throw StemWorkflowSessionError.artifactIdentifierMismatch(
                expected: displayState.id,
                actual: artifact.id
            )
        }
        if let artifact = displayState.artifact, artifact.kind != displayState.kind {
            throw StemWorkflowSessionError.artifactKindMismatch
        }
        guard Self.isAllowed(displayState.kind, by: runContract) else {
            throw StemWorkflowSessionError.artifactOutsideRunContract(
                displayState.kind.stemModeDisplayTitle
            )
        }
        Self.upsert(displayState, in: &artifactStates)
    }

    func updateValidationState(
        _ displayState: StemWorkflowValidationDisplayState,
        at _: Date = Date()
    ) throws {
        try requireRun(displayState.runID)
        guard let runContract else {
            throw StemWorkflowSessionError.noActiveRun
        }
        if case .stem(let rawRole) = displayState.subject {
            guard let role = StemRole(rawValue: rawRole),
                  runContract.activeRoles.contains(role) else {
                throw StemWorkflowSessionError.validationOutsideRunContract(rawRole)
            }
        }
        Self.upsert(displayState, in: &validationStates)
    }

    func fail(
        runID: UUID,
        step: StemWorkflowStep?,
        message: String,
        recoverySuggestion: String? = nil,
        at timestamp: Date = Date()
    ) throws {
        try requireMutableRun(runID)
        let runningProgress = stepProgress.first(where: { $0.status == .running })
        let failureStep = step ?? runningProgress?.step
        if let failureStep {
            let existing = progress(for: failureStep)
            replaceProgress(
                StemWorkflowStepProgress(
                    step: failureStep,
                    status: .failed,
                    fraction: existing.fraction,
                    detail: message
                )
            )
        }
        lastError = StemWorkflowErrorDisplayState(
            runID: runID,
            timestamp: timestamp,
            step: failureStep,
            message: message,
            recoverySuggestion: recoverySuggestion
        )
        artifactStates = []
        validationStates = []
        state = .failed(runID: runID, message: message)
        correctionFinishedAt = timestamp
        failRunningDisplayStep(domain: .correction, message: message)
        completeRunningActivity(
            timestamp: timestamp,
            domain: .correction,
            title: "補正処理に失敗しました",
            detail: message,
            progress: displayProgressValue(for: .correction),
            hasFailed: true
        )

        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .error,
            step: failureStep,
            message: message
        )
    }

    func completeCorrection(runID: UUID, at timestamp: Date = Date()) throws {
        try requireMutableRun(runID)
        guard let runContract else { throw StemWorkflowSessionError.noActiveRun }
        let validKinds = Set(artifactStates.compactMap { state -> StemArtifactKind? in
            guard case .valid = state.status else { return nil }
            return state.kind
        })
        let correctedRoles = Set(validKinds.compactMap { kind -> StemRole? in
            guard case .correctedStem(let role) = kind else { return nil }
            return role
        })
        let hasAllCorrectedStems = correctedRoles == Set(runContract.validationRoles)
        let hasAllCorrectionArtifacts = Self.requiredCorrectionArtifactKinds(
            for: runContract
        ).isSubset(of: validKinds)
        guard hasAllCorrectedStems, hasAllCorrectionArtifacts else {
            throw StemWorkflowSessionError.correctionCompletionRequiresCorrectedStems
        }
        for step in Self.correctionSteps {
            let existing = progress(for: step)
            replaceProgress(StemWorkflowStepProgress(
                step: step,
                status: .completed,
                fraction: 1,
                detail: existing.detail
            ))
        }
        correctionFinishedAt = timestamp
        state = .readyForRemix(runID: runID)
        completeRunningActivity(
            timestamp: timestamp,
            domain: .correction,
            title: "補正処理が完了しました",
            detail: "補正済み\(runContract.stemCount)Stemと純粋加算を保存しました",
            progress: 1
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .info,
            step: .validateCorrectedPureSum,
            message: "補正済み\(runContract.stemCount)Stemと純粋加算を一時保存しました。再ミックスは別操作で開始します。"
        )
    }

    func startRemix(runID: UUID, at timestamp: Date = Date()) throws {
        try requireRun(runID)
        guard let runContract else { throw StemWorkflowSessionError.noActiveRun }
        let correctedRoles = Set(artifactStates.compactMap { state -> StemRole? in
            guard case .valid = state.status,
                  case .correctedStem(let role) = state.kind else { return nil }
            return role
        })
        let hasAllCorrectedStems = correctedRoles == Set(runContract.validationRoles)
        let hasCorrectedPureSum = artifactStates.contains { state in
            guard case .valid = state.status else { return false }
            return state.kind == .correctedPureSum48000
        }
        guard case .readyForRemix(let readyRunID) = state,
              readyRunID == runID,
              hasAllCorrectedStems,
              hasCorrectedPureSum else {
            throw StemWorkflowSessionError.remixRequiresCorrectionCompletion
        }
        resetDisplayDomain(.remix)
        for step in Self.remixSteps {
            replaceProgress(StemWorkflowStepProgress(
                step: step,
                status: .pending,
                fraction: 0
            ))
        }
        artifactStates.removeAll { $0.kind == .remixed48000 || $0.kind == .finalMaster }
        validationStates.removeAll { $0.subject == .remix || $0.subject == .finalMaster }
        remixStartedAt = timestamp
        remixFinishedAt = nil
        masteringStartedAt = nil
        masteringFinishedAt = nil
        state = .ready
        appendActivity(
            timestamp: timestamp,
            domain: .remix,
            title: "再ミックスを実行中",
            detail: "自動設定とユーザー上書きを音声へ適用します",
            progress: 0,
            isRunning: true
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .info,
            step: .remix,
            message: "補正済み\(runContract.stemCount)Stemから再ミックス段を開始します。"
        )
    }

    func completeRemix(runID: UUID, at timestamp: Date = Date()) throws {
        try requireMutableRun(runID)
        guard let runContract else { throw StemWorkflowSessionError.noActiveRun }
        let validKinds = Set(artifactStates.compactMap { state -> StemArtifactKind? in
            guard case .valid = state.status else { return nil }
            return state.kind
        })
        let requiredKinds = Self.requiredCorrectionArtifactKinds(for: runContract)
            .union([.remixed48000])
        guard requiredKinds.isSubset(of: validKinds) else {
            throw StemWorkflowSessionError.masteringRequiresRemixCompletion
        }
        for step in Self.remixSteps {
            let existing = progress(for: step)
            replaceProgress(StemWorkflowStepProgress(
                step: step,
                status: .completed,
                fraction: 1,
                detail: existing.detail
            ))
        }
        remixFinishedAt = timestamp
        state = .readyForMastering(runID: runID)
        completeRunningActivity(
            timestamp: timestamp,
            domain: .remix,
            title: "再ミックスが完了しました",
            detail: "純粋加算とのA/B試聴とマスタリングが可能です",
            progress: 1
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .info,
            step: .validateRemix,
            message: "Stem再ミックスを検証・保存しました。"
        )
    }

    func restoreRemixReadyAfterFailure(
        runID: UUID,
        message: String,
        at timestamp: Date = Date()
    ) throws {
        try requireRun(runID)
        let failedStep = currentStep
        let failedProgress = displayProgressValue(for: .remix)
        for step in Self.remixSteps {
            replaceProgress(StemWorkflowStepProgress(step: step, status: .pending, fraction: 0))
        }
        resetDisplayDomain(.remix)
        artifactStates.removeAll { $0.kind == .remixed48000 || $0.kind == .finalMaster }
        validationStates.removeAll { $0.subject == .remix || $0.subject == .finalMaster }
        remixFinishedAt = timestamp
        state = .readyForRemix(runID: runID)
        lastError = StemWorkflowErrorDisplayState(
            runID: runID,
            timestamp: timestamp,
            step: failedStep,
            message: message,
            recoverySuggestion: "補正済みStem一式と純粋加算は保持されています。設定を確認して再実行してください。"
        )
        completeRunningActivity(
            timestamp: timestamp,
            domain: .remix,
            title: "再ミックスに失敗しました",
            detail: message,
            progress: failedProgress,
            hasFailed: true
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .error,
            step: .remix,
            message: "再ミックスを停止しました。補正済みStem一式と純粋加算は保持しています: \(message)"
        )
    }

    func restoreRemixReadyAfterCancellation(
        runID: UUID,
        at timestamp: Date = Date()
    ) throws {
        try requireRun(runID)
        let cancelledProgress = displayProgressValue(for: .remix)
        for step in Self.remixSteps {
            replaceProgress(StemWorkflowStepProgress(step: step, status: .pending, fraction: 0))
        }
        resetDisplayDomain(.remix)
        artifactStates.removeAll { $0.kind == .remixed48000 || $0.kind == .finalMaster }
        validationStates.removeAll { $0.subject == .remix || $0.subject == .finalMaster }
        remixFinishedAt = timestamp
        state = .readyForRemix(runID: runID)
        lastError = nil
        completeRunningActivity(
            timestamp: timestamp,
            domain: .remix,
            title: "再ミックスをキャンセルしました",
            detail: "補正済みStem一式と純粋加算は保持しています",
            progress: cancelledProgress
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .info,
            step: .remix,
            message: "再ミックスをキャンセルしました。補正済みStem一式と純粋加算は保持しています。"
        )
    }

    func invalidateRemix(runID: UUID) throws {
        try requireRun(runID)
        switch state {
        case .readyForMastering(let readyRunID) where readyRunID == runID:
            break
        case .completed(let completedRunID) where completedRunID == runID:
            break
        case .readyForRemix(let readyRunID) where readyRunID == runID:
            return
        default:
            throw StemWorkflowSessionError.remixRequiresCorrectionCompletion
        }
        artifactStates.removeAll { $0.kind == .remixed48000 || $0.kind == .finalMaster }
        validationStates.removeAll { $0.subject == .remix || $0.subject == .finalMaster }
        for step in Self.remixSteps + Self.masteringSteps {
            replaceProgress(StemWorkflowStepProgress(step: step, status: .pending, fraction: 0))
        }
        resetDisplayDomain(.remix)
        resetDisplayDomain(.mastering)
        remixFinishedAt = nil
        masteringStartedAt = nil
        masteringFinishedAt = nil
        state = .readyForRemix(runID: runID)
    }

    func startMastering(runID: UUID, at timestamp: Date = Date()) throws {
        try requireRun(runID)
        let hasRemix = artifactStates.contains { state in
            guard case .valid = state.status else { return false }
            return state.kind == .remixed48000
        }
        let isReady: Bool
        switch state {
        case .readyForMastering(let readyRunID), .completed(let readyRunID):
            isReady = readyRunID == runID
        default:
            isReady = false
        }
        guard isReady, hasRemix else {
            throw StemWorkflowSessionError.masteringRequiresRemixCompletion
        }
        for step in Self.masteringSteps {
            replaceProgress(StemWorkflowStepProgress(
                step: step,
                status: .pending,
                fraction: 0
            ))
        }
        resetDisplayDomain(.mastering)
        artifactStates.removeAll { $0.kind == .finalMaster }
        validationStates.removeAll { $0.subject == .finalMaster }
        masteringStartedAt = timestamp
        masteringFinishedAt = nil
        state = .ready
        appendActivity(
            timestamp: timestamp,
            domain: .mastering,
            title: "マスタリングを実行中",
            detail: "検証済みStem再ミックスを読み込みます",
            progress: 0,
            isRunning: true
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .info,
            step: .mastering,
            message: "検証済みStem再ミックスからマスタリング段を開始します。"
        )
    }

    func restoreMasteringReadyAfterFailure(
        runID: UUID,
        message: String,
        at timestamp: Date = Date()
    ) throws {
        try requireRun(runID)
        let failureStep = currentStep
        for step in Self.masteringSteps {
            replaceProgress(StemWorkflowStepProgress(step: step, status: .pending, fraction: 0))
        }
        artifactStates.removeAll { $0.kind == .finalMaster }
        validationStates.removeAll { $0.subject == .finalMaster }
        state = .readyForMastering(runID: runID)
        masteringFinishedAt = timestamp
        failRunningDisplayStep(domain: .mastering, message: message)
        lastError = StemWorkflowErrorDisplayState(
            runID: runID,
            timestamp: timestamp,
            step: failureStep,
            message: message,
            recoverySuggestion: "Stem再ミックスは保持されています。設定または警告を確認してマスタリングを再実行してください。"
        )
        completeRunningActivity(
            timestamp: timestamp,
            domain: .mastering,
            title: "マスタリングに失敗しました",
            detail: message,
            progress: displayProgressValue(for: .mastering),
            hasFailed: true
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .error,
            step: failureStep,
            message: "マスタリング段を停止しました。Stem再ミックスは保持しています: \(message)"
        )
    }

    func restoreMasteringReadyAfterCancellation(
        runID: UUID,
        at timestamp: Date = Date()
    ) throws {
        try requireRun(runID)
        for step in Self.masteringSteps {
            replaceProgress(StemWorkflowStepProgress(step: step, status: .pending, fraction: 0))
        }
        resetDisplayDomain(.mastering)
        masteringFinishedAt = timestamp
        state = .readyForMastering(runID: runID)
        lastError = nil
        artifactStates.removeAll { state in
            state.kind == .finalMaster
        }
        validationStates.removeAll { state in
            state.subject == .finalMaster
        }
        completeRunningActivity(
            timestamp: timestamp,
            domain: .mastering,
            title: "マスタリングをキャンセルしました",
            detail: "Stem再ミックスは保持しています",
            progress: displayProgressValue(for: .mastering)
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .info,
            step: .mastering,
            message: "マスタリングをキャンセルしました。Stem再ミックスは保持しています。"
        )
    }

    func resetAfterCorrectionCancellation(runID expectedRunID: UUID?) {
        if let expectedRunID, let runID, runID != expectedRunID {
            return
        }
        let cancelledRunID = runID ?? expectedRunID
        let retainedLogs = logs
        let progress = displayProgressValue(for: .correction)
        let timestamp = Date()
        resetRunDisplayState(clearActivities: false)
        logs = retainedLogs
        correctionFinishedAt = timestamp
        if let cancelledRunID {
            appendLogUnchecked(
                runID: cancelledRunID,
                timestamp: timestamp,
                level: .info,
                step: .validateInput,
                message: "補正処理をキャンセルしました。"
            )
        }
        completeRunningActivity(
            timestamp: timestamp,
            domain: .correction,
            title: "補正処理をキャンセルしました",
            detail: nil,
            progress: progress
        )
    }

    func resetForInputChange() {
        resetRunDisplayState(clearActivities: true)
    }

    func completeRun(
        runID: UUID,
        at timestamp: Date = Date()
    ) throws {
        try requireMutableRun(runID)
        guard let runContract else { throw StemWorkflowSessionError.noActiveRun }
        let validKinds = Set(artifactStates.compactMap { state -> StemArtifactKind? in
            guard case .valid = state.status else { return nil }
            return state.kind
        })
        let requiredKinds = Self.requiredCorrectionArtifactKinds(for: runContract)
            .union([.remixed48000, .finalMaster])
        guard requiredKinds.isSubset(of: validKinds) else {
            throw StemWorkflowSessionError.completionRequiresCompletedExport
        }
        for step in Self.masteringSteps {
            let existing = progress(for: step)
            replaceProgress(StemWorkflowStepProgress(
                step: step,
                status: .completed,
                fraction: 1,
                detail: existing.detail
            ))
        }
        masteringFinishedAt = timestamp
        state = .completed(runID: runID)
        completeRunningActivity(
            timestamp: timestamp,
            domain: .mastering,
            title: "マスタリングが完了しました",
            detail: "Stem Mode最終版を生成しました",
            progress: 1
        )
        appendLogUnchecked(
            runID: runID,
            timestamp: timestamp,
            level: .info,
            step: .finalizeMaster,
            message: "Stem Mode処理が完了しました。"
        )
    }

    func recordExportSuccess(
        artifact: StemAudioArtifact,
        destinationURL: URL,
        fileInfo: AudioFileInfo?,
        at timestamp: Date = Date()
    ) {
        lastExportedDestinationURL = destinationURL
        appendActivity(
            timestamp: timestamp,
            domain: .export,
            title: "成果物を書き出しました",
            detail: artifact.kind.stemModeDisplayTitle,
            fileURL: destinationURL,
            fileInfo: fileInfo,
            progress: 1
        )
    }

    func recordExportFailure(
        artifact: StemAudioArtifact,
        message: String,
        at timestamp: Date = Date()
    ) {
        appendActivity(
            timestamp: timestamp,
            domain: .export,
            title: "成果物を書き出せませんでした",
            detail: "\(artifact.fileURL.lastPathComponent): \(message)",
            hasFailed: true
        )
    }

    private func requireRun(_ receivedRunID: UUID) throws {
        guard let runID else {
            throw StemWorkflowSessionError.noActiveRun
        }
        guard runID == receivedRunID else {
            throw StemWorkflowSessionError.runMismatch(
                expected: runID,
                actual: receivedRunID
            )
        }
    }

    private func requireMutableRun(_ runID: UUID) throws {
        try requireRun(runID)
        switch state {
        case .completed, .failed:
            throw StemWorkflowSessionError.runIsTerminal
        case .idle, .ready, .readyForRemix, .readyForMastering,
             .running:
            return
        }
    }

    private func replaceProgress(_ progress: StemWorkflowStepProgress) {
        let index = Self.index(of: progress.step)
        stepProgress[index] = progress
    }

    private func appendLogUnchecked(
        runID: UUID,
        timestamp: Date,
        level: StemWorkflowLogLevel,
        step: StemWorkflowStep?,
        message: String
    ) {
        logs.append(
            StemWorkflowLogEntry(
                runID: runID,
                timestamp: timestamp,
                level: level,
                step: step,
                message: message
            )
        )
    }

    private static func upsert(
        _ displayState: StemWorkflowArtifactDisplayState,
        in states: inout [StemWorkflowArtifactDisplayState]
    ) {
        if let index = states.firstIndex(where: { $0.id == displayState.id }) {
            states[index] = displayState
        } else {
            states.append(displayState)
        }
    }

    private static func isAllowed(
        _ kind: StemArtifactKind,
        by runContract: StemModelRunContract
    ) -> Bool {
        switch kind {
        case .rawStem(let role):
            return runContract.activeRoles.contains(role)
        case .correctedStem(let role):
            return runContract.validationRoles.contains(role)
        case .input44100, .correctedPureSum48000, .remixed48000, .finalMaster:
            return true
        }
    }

    private static func requiredCorrectionArtifactKinds(
        for runContract: StemModelRunContract
    ) -> Set<StemArtifactKind> {
        var kinds: Set<StemArtifactKind> = [.input44100, .correctedPureSum48000]
        for role in runContract.activeRoles {
            kinds.insert(.rawStem(role))
        }
        for role in runContract.validationRoles {
            kinds.insert(.correctedStem(role))
        }
        return kinds
    }

    private static func upsert(
        _ displayState: StemWorkflowValidationDisplayState,
        in states: inout [StemWorkflowValidationDisplayState]
    ) {
        if let index = states.firstIndex(where: { $0.id == displayState.id }) {
            states[index] = displayState
        } else {
            states.append(displayState)
        }
    }

    private func resetRunDisplayState(clearActivities: Bool = false) {
        runID = nil
        runContract = nil
        state = .idle
        stepProgress = Self.pendingSteps()
        displayProgress = Self.pendingDisplaySteps()
        logs = []
        inputDisplayLogLines = []
        lastError = nil
        artifactStates = []
        validationStates = []
        correctionStartedAt = nil
        correctionFinishedAt = nil
        remixStartedAt = nil
        remixFinishedAt = nil
        masteringStartedAt = nil
        masteringFinishedAt = nil
        lastExportedDestinationURL = nil
        if clearActivities {
            activityEvents = []
        }
    }

    private static func pendingSteps() -> [StemWorkflowStepProgress] {
        StemWorkflowStep.allCases.map {
            StemWorkflowStepProgress(step: $0, status: .pending, fraction: 0)
        }
    }

    private static func pendingDisplaySteps(
        roles: [StemRole] = StemProductionModelProfile.profile(for: .htdemucs).sourceOrder
    ) -> [StemModeProcessStepProgress] {
        (
            StemModeProcessStep.correctionSteps(for: roles)
                + StemModeProcessStep.remixSteps
                + StemModeProcessStep.masteringSteps
        ).map {
            StemModeProcessStepProgress(step: $0, status: .pending, fraction: 0)
        }
    }

    private func resetDisplayDomain(_ domain: StemModeProcessDomain) {
        for index in displayProgress.indices where displayProgress[index].step.domain == domain {
            displayProgress[index] = StemModeProcessStepProgress(
                step: displayProgress[index].step,
                status: .pending,
                fraction: 0
            )
        }
    }

    private func failRunningDisplayStep(domain: StemModeProcessDomain, message: String) {
        guard let index = displayProgress.firstIndex(where: {
            $0.step.domain == domain && $0.status == .running
        }) else { return }
        displayProgress[index] = StemModeProcessStepProgress(
            step: displayProgress[index].step,
            status: .failed,
            fraction: displayProgress[index].fraction,
            detail: message
        )
    }

    private func appendActivity(
        timestamp: Date,
        domain: RecentActivityDomain,
        title: String,
        detail: String? = nil,
        fileURL: URL? = nil,
        fileInfo: AudioFileInfo? = nil,
        progress: Double? = nil,
        isRunning: Bool = false,
        hasFailed: Bool = false
    ) {
        activityEvents.append(RecentActivityEvent(
            timestamp: timestamp,
            domain: domain,
            title: title,
            detail: detail,
            fileName: fileURL?.lastPathComponent,
            audioSummary: fileInfo?.technicalSummary,
            progress: progress.map { min(max($0, 0), 1) },
            isRunning: isRunning,
            hasFailed: hasFailed
        ))
        if activityEvents.count > 20 {
            activityEvents.removeFirst(activityEvents.count - 20)
        }
    }

    private func appendMetricActivity(
        timestamp: Date,
        domain: RecentActivityDomain,
        title: String,
        metrics: AudioMetricSnapshot
    ) {
        appendActivity(
            timestamp: timestamp,
            domain: domain,
            title: title,
            detail: String(
                format: "ラウドネス: %.1f LUFS / ピーク: %.1f dBTP",
                metrics.integratedLoudnessLUFS,
                metrics.truePeakDBFS
            )
        )
    }

    private func logLines(for steps: Set<StemWorkflowStep>) -> [String] {
        logs.compactMap { entry in
            guard let step = entry.step, steps.contains(step) else { return nil }
            return entry.message
        }
    }

    private func updateRunningActivity(
        timestamp: Date,
        domain: RecentActivityDomain,
        title: String,
        detail: String?,
        progress: Double
    ) {
        guard let index = activityEvents.lastIndex(where: { $0.domain == domain && $0.isRunning }) else {
            appendActivity(
                timestamp: timestamp,
                domain: domain,
                title: title,
                detail: detail,
                progress: progress,
                isRunning: true
            )
            return
        }
        activityEvents[index].timestamp = timestamp
        activityEvents[index].title = title
        activityEvents[index].detail = detail
        activityEvents[index].progress = min(max(progress, 0), 1)
    }

    private func completeRunningActivity(
        timestamp: Date,
        domain: RecentActivityDomain,
        title: String,
        detail: String?,
        progress: Double,
        hasFailed: Bool = false
    ) {
        if let index = activityEvents.lastIndex(where: { $0.domain == domain && $0.isRunning }) {
            activityEvents[index].timestamp = timestamp
            activityEvents[index].title = title
            activityEvents[index].detail = detail
            activityEvents[index].progress = min(max(progress, 0), 1)
            activityEvents[index].isRunning = false
            activityEvents[index].hasFailed = hasFailed
            return
        }
        appendActivity(
            timestamp: timestamp,
            domain: domain,
            title: title,
            detail: detail,
            progress: progress,
            hasFailed: hasFailed
        )
    }

    private static func index(of step: StemWorkflowStep) -> Int {
        StemWorkflowStep.allCases.firstIndex(of: step)!
    }

    private static let correctionLogSteps: Set<StemWorkflowStep> = [
        .validateInput, .separate, .validateSeparatedStems,
        .evaluateStems, .correctStems, .validateCorrectedStems,
        .correctedPureSum, .validateCorrectedPureSum,
    ]

    private static let remixLogSteps: Set<StemWorkflowStep> = [
        .remix, .validateRemix,
    ]

    private static let masteringLogSteps: Set<StemWorkflowStep> = [
        .mastering, .finalizeMaster,
    ]
}
