import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

enum StemWorkflowControllerError: LocalizedError {
    case workspaceUnavailable
    case workflowAlreadyActive
    case remixNotReady
    case masteringNotReady
    case modelOperationInProgress
    case validatedResourcesUnavailable
    case eventRunMismatch(expected: UUID, actual: UUID)
    case artifactIsNotValidated(String)
    case artifactIsNotExportable(StemArtifactKind)
    case unsafeExportDestination(String)

    var errorDescription: String? {
        switch self {
        case .workspaceUnavailable:
            "Stem Mode専用画面の状態を準備できていません。"
        case .workflowAlreadyActive:
            "別のStem Mode処理が進行中です。"
        case .remixNotReady:
            "契約対象の補正済みStemと純粋加算が確定していないため、再ミックスを開始できません。"
        case .masteringNotReady:
            "検証済みStem再ミックスが確定していないため、マスタリングを開始できません。"
        case .modelOperationInProgress:
            "AIモデルの取得・削除・再検証が進行中のため、Stem Mode処理を開始できません。"
        case .validatedResourcesUnavailable:
            "右サイドのStem分離で使用可能と確認されたStem Mode資産がありません。"
        case let .eventRunMismatch(expected, actual):
            "Stem Modeの処理IDが一致しません（現在: \(expected.uuidString)、受信: \(actual.uuidString)）。"
        case .artifactIsNotValidated(let identifier):
            "成果物「\(identifier)」は現在の音声検証を通過していないため、書き出しません。"
        case .artifactIsNotExportable(let kind):
            "成果物「\(kind.stemModeDisplayTitle)」はユーザー書き出し対象ではありません。"
        case .unsafeExportDestination(let path):
            "Stem Modeの内部一時保存先や内部成果物へは書き出せません（\(path)）。"
        }
    }
}

protocol StemWorkflowExecuting: Sendable {
    func processCorrection(
        _ request: StemWorkflowRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowCorrectionResult
    func processRemix(
        correction: StemWorkflowCorrectionResult,
        settings: StemRemixSettings,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowRemixResult
    func processMastering(
        _ request: StemWorkflowMasteringRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowResult
    func discardSession(runID: UUID) async throws
}

extension StemWorkflowService: StemWorkflowExecuting {
    func discardSession(runID: UUID) async throws {
        try discardTemporarySession(runID: runID)
    }
}

protocol StemWorkflowInputInspecting: Sendable {
    func inspect(inputURL: URL) async throws -> StemInputInspection
}

struct ProductionStemWorkflowInputInspector: StemWorkflowInputInspecting {
    private let service = AudioInputConversionService()

    func inspect(inputURL: URL) async throws -> StemInputInspection {
        try await Task.detached(priority: .userInitiated) { [service] in
            try service.inspect(inputURL: inputURL)
        }.value
    }
}

protocol StemWorkflowArtifactValidating: Sendable {
    func validate(
        artifact: StemAudioArtifact,
        expectedURL: URL,
        expectedKind: StemArtifactKind
    ) async throws -> StemAudioArtifactValidationReport
}

extension StemTemporaryAudioStore: StemWorkflowArtifactValidating {}

protocol StemWorkflowArtifactExporting: Sendable {
    func export(
        sourceURL: URL,
        destinationURL: URL,
        format: AudioExportFormat
    ) async throws
}

struct ProductionStemWorkflowArtifactExporter: StemWorkflowArtifactExporting {
    func export(
        sourceURL: URL,
        destinationURL: URL,
        format: AudioExportFormat
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try AudioFileService.exportAudio(
                from: sourceURL,
                to: destinationURL,
                format: format
            )
        }.value
    }
}

@MainActor
protocol StemWorkflowExportDestinationChoosing: AnyObject {
    func chooseDestination(
        suggestedFileName: String,
        contentType: UTType
    ) async -> URL?
}

@MainActor
final class ProductionStemWorkflowExportDestinationChooser: StemWorkflowExportDestinationChoosing {
    func chooseDestination(
        suggestedFileName: String,
        contentType: UTType
    ) async -> URL? {
        await withCheckedContinuation { continuation in
            FilePanelService.chooseSaveLocation(
                suggestedFileName: suggestedFileName,
                allowedContentTypes: [contentType]
            ) { destinationURL in
                continuation.resume(returning: destinationURL)
            }
        }
    }
}

@MainActor
protocol StemSecurityScopedResourceAccessing: AnyObject {
    func startAccessing(_ URL: URL) -> Bool
    func stopAccessing(_ URL: URL)
}

@MainActor
final class ProductionStemSecurityScopedResourceAccessor: StemSecurityScopedResourceAccessing {
    func startAccessing(_ URL: URL) -> Bool {
        URL.startAccessingSecurityScopedResource()
    }

    func stopAccessing(_ URL: URL) {
        URL.stopAccessingSecurityScopedResource()
    }
}

/// Stem専用UI、メモリ上の三段階workflow、確認済みモデル状態、security-scoped入力の寿命を接続します。
/// 通常モードの`ProcessingJob`や通知domainは所有せず、モード切替後も実行Taskを保持します。
@MainActor
@Observable
final class StemWorkflowController {
    private struct ReadyResources {
        let manifest: StemModelManifest
        let installation: ValidatedStemModelInstallation
        let bundledRuntime: StemBundledRuntimeValidationReport
    }

    private enum ExecutionKind {
        case newRun
        case remix
        case mastering
    }

    private struct SecurityScopedLease {
        let URL: URL
        let didStartAccessing: Bool
    }

    private(set) var isProcessingRun = false

    @ObservationIgnored private let session: StemWorkflowSession
    @ObservationIgnored private let modelManager: StemModelManager
    @ObservationIgnored private let workflow: any StemWorkflowExecuting
    @ObservationIgnored private let inputInspector: any StemWorkflowInputInspecting
    @ObservationIgnored private let inputDisplayAnalyzer: any StemInputDisplayAnalyzing
    @ObservationIgnored private let artifactValidator: any StemWorkflowArtifactValidating
    @ObservationIgnored private let artifactExporter: any StemWorkflowArtifactExporting
    @ObservationIgnored private let destinationChooser: any StemWorkflowExportDestinationChoosing
    @ObservationIgnored private let securityScopedAccessor: any StemSecurityScopedResourceAccessing
    @ObservationIgnored private let notificationReporter: any StemCompletionNotificationReporting
    @ObservationIgnored private let seedProvider: () -> Int
    @ObservationIgnored private let revealInFinder: (URL) -> Void
    @ObservationIgnored private weak var workspaceModel: StemModeWorkspaceModel?

    @ObservationIgnored private var workflowTask: Task<Void, Never>?
    @ObservationIgnored private var activeRunID: UUID?
    @ObservationIgnored private var executionKind: ExecutionKind?
    @ObservationIgnored private var isExpectedCancellation = false
    @ObservationIgnored private var inputLease: SecurityScopedLease?
    @ObservationIgnored private var isShuttingDown = false
    @ObservationIgnored private var notifiedCompletionStages: Set<StemCompletionNotificationStage> = []
    @ObservationIgnored private var correctionResult: StemWorkflowCorrectionResult?
    @ObservationIgnored private var remixResult: StemWorkflowRemixResult?
    @ObservationIgnored private var runContract: StemModelRunContract?

    init(
        session: StemWorkflowSession,
        modelManager: StemModelManager,
        workflow: any StemWorkflowExecuting = StemWorkflowService(),
        inputInspector: any StemWorkflowInputInspecting = ProductionStemWorkflowInputInspector(),
        inputDisplayAnalyzer: any StemInputDisplayAnalyzing = ProductionStemInputDisplayAnalyzer(),
        artifactValidator: any StemWorkflowArtifactValidating = StemTemporaryAudioStore(),
        artifactExporter: any StemWorkflowArtifactExporting = ProductionStemWorkflowArtifactExporter(),
        destinationChooser: any StemWorkflowExportDestinationChoosing = ProductionStemWorkflowExportDestinationChooser(),
        securityScopedAccessor: any StemSecurityScopedResourceAccessing = ProductionStemSecurityScopedResourceAccessor(),
        notificationReporter: any StemCompletionNotificationReporting = StemCompletionNotificationService.shared,
        seedProvider: @escaping () -> Int = { Int.random(in: 0...Int.max) },
        revealInFinder: @escaping (URL) -> Void = {
            NSWorkspace.shared.activateFileViewerSelecting([$0])
        }
    ) {
        self.session = session
        self.modelManager = modelManager
        self.workflow = workflow
        self.inputInspector = inputInspector
        self.inputDisplayAnalyzer = inputDisplayAnalyzer
        self.artifactValidator = artifactValidator
        self.artifactExporter = artifactExporter
        self.destinationChooser = destinationChooser
        self.securityScopedAccessor = securityScopedAccessor
        self.notificationReporter = notificationReporter
        self.seedProvider = seedProvider
        self.revealInFinder = revealInFinder
    }

    var actions: StemModeWorkspaceActions {
        StemModeWorkspaceActions(
            inspectInput: { [weak self] inputURL in
                guard let self else { throw CancellationError() }
                try await self.inspectInput(inputURL)
            },
            analyzeInputForDisplay: { [weak self] inputURL, analysisMode, logHandler in
                guard let self else { throw CancellationError() }
                return try await self.inputDisplayAnalyzer.analyze(
                    inputURL: inputURL,
                    analysisMode: analysisMode,
                    logHandler: logHandler
                )
            },
            releaseInspectedInput: { [weak self] inputURL in
                self?.releaseInspectedInput(inputURL)
            },
            resetForInputChange: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.resetForInputChange()
            },
            beginCorrection: { [weak self] request in
                guard let self else { throw CancellationError() }
                try await self.beginCorrection(request)
            },
            beginRemix: { [weak self] request in
                guard let self else { throw CancellationError() }
                try await self.beginRemix(request)
            },
            invalidateRemix: { [weak self] in
                guard let self else { throw CancellationError() }
                try self.invalidateRemix()
            },
            beginMastering: { [weak self] request in
                guard let self else { throw CancellationError() }
                try await self.beginMastering(request)
            },
            cancelCorrection: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.cancelCorrection()
            },
            cancelRemix: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.cancelRemix()
            },
            cancelMastering: { [weak self] in
                guard let self else { throw CancellationError() }
                try await self.cancelMastering()
            },
            exportArtifact: { [weak self] artifact, format in
                guard let self else { throw CancellationError() }
                return try await self.exportArtifact(artifact, format: format)
            },
            revealArtifact: { [weak self] URL in
                self?.revealInFinder(URL)
            }
        )
    }

    func attachWorkspaceModel(_ model: StemModeWorkspaceModel) {
        workspaceModel = model
    }

    func synchronizeModelReadiness() {
        guard let workspaceModel else { return }
        if modelManager.isModelOperationInProgress {
            workspaceModel.setModelOperationInProgress(true)
            return
        }
        workspaceModel.setModelOperationInProgress(false)
        guard let resources = readyResourcesFromCurrentInspection() else {
            if !isProcessingRun {
                workspaceModel.clearModelPresentation()
                workspaceModel.clearSeparationSettings()
            }
            return
        }
        do {
            try updateModelPresentation(resources)
            try prepareSeparationSettingsIfNeeded(resources)
        } catch {
            workspaceModel.clearModelPresentation()
            workspaceModel.presentControllerFailure(
                title: "モデル情報を表示できません",
                message: error.localizedDescription
            )
        }
    }

    func shutdown() {
        isShuttingDown = true
        isExpectedCancellation = true
        workflowTask?.cancel()
        workflowTask = nil
        workspaceModel?.stopPreviewPlayback()
        releaseInputLease()
        if let runID = session.runID {
            try? StemWorkflowService().discardTemporarySession(runID: runID)
        }
        correctionResult = nil
        remixResult = nil
        runContract = nil
        resetExecutionState()
    }

    private func inspectInput(_ inputURL: URL) async throws {
        guard !isProcessingRun else {
            throw StemWorkflowControllerError.workflowAlreadyActive
        }
        let newLease = beginSecurityScopedLease(for: inputURL)
        do {
            let inspection = try await inputInspector.inspect(inputURL: inputURL)
            guard let workspaceModel else {
                throw StemWorkflowControllerError.workspaceUnavailable
            }
            if !modelManager.isModelOperationInProgress,
               let resources = readyResourcesFromCurrentInspection() {
                let settings = try StemSeparationSettings
                    .production(
                        for: resources.installation.snapshot.contract.separationModel,
                        seed: seedProvider()
                    )
                    .validated(modelContract: resources.installation.snapshot.contract)
                try workspaceModel.setProductionSeparationSettings(settings)
            }
            _ = try AudioInputConversionService.selectChannelMatrix(
                resolution: inspection.matrixResolution
            )
            replaceInputLease(with: newLease)
            workspaceModel.setFinalCommitLockState(.unlocked)
        } catch {
            endSecurityScopedLease(newLease)
            throw error
        }
    }

    private func releaseInspectedInput(_ inputURL: URL) {
        guard inputLease?.URL.standardizedFileURL == inputURL.standardizedFileURL else {
            return
        }
        releaseInputLease()
    }

    private func resetForInputChange() async throws {
        try requireNoActiveWorkflow()
        let isSameSelectedInput = workspaceModel?.selectedInputURL?.standardizedFileURL
            == inputLease?.URL.standardizedFileURL
        try await discardInactiveSessionRunIfPresent()
        session.resetForInputChange()
        if isSameSelectedInput {
            workspaceModel?.resetRunPresentationAfterCorrectionCancellation()
        } else {
            workspaceModel?.resetRunPresentationForInputChange()
        }
    }

    private func beginCorrection(_ startRequest: StemModeStartRequest) async throws {
        try requireNoActiveWorkflow()
        try await discardInactiveSessionRunIfPresent()
        isProcessingRun = true
        do {
            let resources = try currentReadyResources()
            _ = try startRequest.separationSettings.validated(
                modelContract: resources.installation.snapshot.contract
            )
            try updateModelPresentation(resources)
            ensureInputLease(for: startRequest.inputURL)

            let runID = UUID()
            let runContract = resources.installation.snapshot.contract.runContract
            guard resources.bundledRuntime.contract.runContract == runContract else {
                throw StemWorkflowServiceError.runContractMismatch
            }
            prepareExecution(kind: .newRun, runID: runID)
            guard let workspaceModel else { throw StemWorkflowControllerError.workspaceUnavailable }
            workspaceModel.acceptSessionStart(runContract: runContract)
            try session.startRun(runID: runID, runContract: runContract)
            self.runContract = runContract
            let request = StemWorkflowRequest(
                runID: runID,
                runContract: runContract,
                sourceURL: startRequest.inputURL,
                installation: resources.installation,
                manifest: resources.manifest,
                separationSettings: startRequest.separationSettings,
                correctionSettings: startRequest.correctionSettings,
                masteringSettings: startRequest.masteringSettings,
                analysisMode: startRequest.analysisMode
            )
            try await startWorkflowTask(runID: runID) { [workflow] handler in
                .correction(try await workflow.processCorrection(request, eventHandler: handler))
            }
        } catch {
            if activeRunID == nil {
                isProcessingRun = false
            }
            throw error
        }
    }

    private func beginMastering(_ request: StemModeMasteringRequest) async throws {
        try requireNoActiveWorkflow()
        guard let runID = session.runID,
              let remixResult,
              remixResult.runID == runID else {
            throw StemWorkflowControllerError.masteringNotReady
        }
        switch session.state {
        case .readyForMastering(let readyRunID), .completed(let readyRunID):
            guard readyRunID == runID else {
                throw StemWorkflowControllerError.masteringNotReady
            }
        default:
            throw StemWorkflowControllerError.masteringNotReady
        }
        isProcessingRun = true
        do {
            prepareExecution(kind: .mastering, runID: runID, usesExistingSession: true)
            try session.startMastering(runID: runID)
            workspaceModel?.clearMasteringResult()
            updatePreviewSourcesFromValidatedArtifacts()
            let workflowRequest = StemWorkflowMasteringRequest(
                remix: remixResult,
                masteringSettings: request.masteringSettings
            )
            try await startWorkflowTask(runID: runID) { [workflow] handler in
                .mastered(try await workflow.processMastering(
                    workflowRequest,
                    eventHandler: handler
                ))
            }
        } catch {
            if activeRunID == nil {
                isProcessingRun = false
            }
            throw error
        }
    }

    private func beginRemix(_ request: StemModeRemixRequest) async throws {
        try requireNoActiveWorkflow()
        guard let runID = session.runID,
              case .readyForRemix(runID) = session.state,
              let correctionResult,
              correctionResult.runID == runID else {
            throw StemWorkflowControllerError.remixNotReady
        }
        isProcessingRun = true
        do {
            prepareExecution(kind: .remix, runID: runID, usesExistingSession: true)
            try session.startRemix(runID: runID)
            try await startWorkflowTask(runID: runID) { [workflow] handler in
                .remix(try await workflow.processRemix(
                    correction: correctionResult,
                    settings: request.settings,
                    eventHandler: handler
                ))
            }
        } catch {
            if activeRunID == nil {
                isProcessingRun = false
            }
            throw error
        }
    }

    private func invalidateRemix() throws {
        try requireNoActiveWorkflow()
        guard let runID = session.runID else {
            throw StemWorkflowSessionError.noActiveRun
        }
        try session.invalidateRemix(runID: runID)
        remixResult = nil
        workspaceModel?.clearRemixResult()
        updatePreviewSourcesFromValidatedArtifacts()
        workspaceModel?.setFinalCommitLockState(.unlocked)
    }

    private func cancelCorrection() async throws {
        guard executionKind == .newRun,
              let runID = activeRunID,
              workflowTask != nil else {
            throw StemWorkflowSessionError.noActiveRun
        }
        isExpectedCancellation = true
        workflowTask?.cancel()
        await workflowTask?.value

        var discardFailure: (any Error)?
        do {
            try await workflow.discardSession(runID: runID)
        } catch {
            discardFailure = error
        }
        correctionResult = nil
        remixResult = nil
        runContract = nil
        session.resetAfterCorrectionCancellation(runID: runID)
        workspaceModel?.resetRunPresentationAfterCorrectionCancellation()
        workspaceModel?.setFinalCommitLockState(.unlocked)
        resetExecutionState()
        if let discardFailure {
            throw discardFailure
        }
    }

    private func cancelRemix() async throws {
        guard executionKind == .remix,
              let runID = activeRunID,
              workflowTask != nil else {
            throw StemWorkflowSessionError.noActiveRun
        }
        isExpectedCancellation = true
        workflowTask?.cancel()
        await workflowTask?.value
        remixResult = nil
        do {
            try session.restoreRemixReadyAfterCancellation(runID: runID)
            updatePreviewSourcesFromValidatedArtifacts()
            workspaceModel?.setFinalCommitLockState(.unlocked)
            resetExecutionState()
        } catch {
            workspaceModel?.setFinalCommitLockState(.unlocked)
            resetExecutionState()
            throw error
        }
    }

    private func cancelMastering() async throws {
        guard executionKind == .mastering,
              let runID = activeRunID,
              workflowTask != nil else {
            throw StemWorkflowSessionError.noActiveRun
        }
        isExpectedCancellation = true
        workflowTask?.cancel()
        await workflowTask?.value
        do {
            try session.restoreMasteringReadyAfterCancellation(runID: runID)
            updatePreviewSourcesFromValidatedArtifacts()
            workspaceModel?.setFinalCommitLockState(.unlocked)
            resetExecutionState()
        } catch {
            workspaceModel?.setFinalCommitLockState(.unlocked)
            resetExecutionState()
            throw error
        }
    }

    private func exportArtifact(
        _ artifact: StemAudioArtifact,
        format: AudioExportFormat
    ) async throws -> URL {
        guard artifact.kind.isStemModeUserExportable else {
            throw StemWorkflowControllerError.artifactIsNotExportable(artifact.kind)
        }
        guard let displayState = session.artifactStates.first(where: {
            $0.id == artifact.id && $0.artifact == artifact
        }), case .valid = displayState.status else {
            throw StemWorkflowControllerError.artifactIsNotValidated(artifact.id)
        }
        do {
            _ = try await artifactValidator.validate(
                artifact: artifact,
                expectedURL: artifact.fileURL,
                expectedKind: artifact.kind
            )
        } catch {
            try session.updateArtifactState(
                StemWorkflowArtifactDisplayState(
                    id: artifact.id,
                    runID: displayState.runID,
                    kind: artifact.kind,
                    artifact: artifact,
                    status: .invalid(message: error.localizedDescription)
                )
            )
            throw error
        }

        let suggestedName = suggestedExportFileName(artifact: artifact, format: format)
        guard let destinationURL = await destinationChooser.chooseDestination(
            suggestedFileName: suggestedName,
            contentType: format.contentType
        ) else {
            throw CancellationError()
        }
        guard isSafeExternalExportDestination(destinationURL, sourceURL: artifact.fileURL) else {
            throw StemWorkflowControllerError.unsafeExportDestination(destinationURL.path)
        }
        try await artifactExporter.export(
            sourceURL: artifact.fileURL,
            destinationURL: destinationURL,
            format: format
        )
        return destinationURL
    }

    private func startWorkflowTask(
        runID: UUID,
        operation: @escaping @Sendable (
            @escaping @Sendable (StemWorkflowEvent) async -> Void
        ) async throws -> StemWorkflowExecutionResult
    ) async throws {
        workflowTask = Task { [weak self] in
            do {
                let result = try await operation { [weak self] event in
                    await self?.receive(event, expectedRunID: runID)
                }
                await self?.workflowSucceeded(result, runID: runID)
            } catch {
                await self?.workflowFailed(error, runID: runID)
            }
        }
    }

    private func receive(_ event: StemWorkflowEvent, expectedRunID: UUID) {
        guard !isShuttingDown else { return }
        let receivedRunID = eventRunID(event)
        guard receivedRunID == expectedRunID,
              activeRunID == expectedRunID else { return }
        do {
            try apply(event)
        } catch {
            try? session.appendLog(
                runID: expectedRunID,
                level: .warning,
                step: session.currentStep,
                message: "画面表示の更新を省略しました: \(error.localizedDescription)"
            )
        }
    }

    private func apply(_ event: StemWorkflowEvent) throws {
        switch event {
        case .progress(let progress):
            guard isWorkflowStepAllowed(progress.step, during: executionKind) else {
                throw StemWorkflowSessionError.progressOutsideRunContract(progress.step.rawValue)
            }
            try applyProgress(progress)

        case .displayProgress(let progress):
            guard isDisplayDomainAllowed(progress.step.domain, during: executionKind) else {
                throw StemWorkflowSessionError.progressOutsideRunContract(progress.step.id)
            }
            try session.applyDisplayProgress(progress)
            if progress.step == .finalization {
                switch progress.status {
                case .running:
                    workspaceModel?.setFinalCommitLockState(.locked)
                case .pending, .completed, .skipped, .failed:
                    break
                }
            }

        case .artifactCommitted(_, let artifact):
            guard let runID = activeRunID else {
                throw StemWorkflowSessionError.noActiveRun
            }
            guard let runContract,
                  isArtifactAllowed(
                    artifact.kind,
                    during: executionKind,
                    runContract: runContract
                  ) else {
                throw StemWorkflowSessionError.artifactOutsideRunContract(
                    artifact.kind.stemModeDisplayTitle
                )
            }
            try session.updateArtifactState(
                StemWorkflowArtifactDisplayState(
                    id: artifact.id,
                    runID: runID,
                    kind: artifact.kind,
                    artifact: artifact,
                    status: .valid
                )
            )
            updatePreviewSourcesFromValidatedArtifacts()

        case .validationCompleted(_, let validation):
            guard let runID = activeRunID else {
                throw StemWorkflowSessionError.noActiveRun
            }
            guard isValidationPhaseAllowed(validation.phase, during: executionKind) else {
                throw StemWorkflowSessionError.validationOutsideRunContract(
                    validation.phase.rawValue
                )
            }
            let subject: StemWorkflowValidationSubject = switch validation.phase {
            case .separatedStems: .separatedStems
            case .remix: .rawRemix
            case .correctedPureSum: .correctedPureSum
            case .processedRemix: .remix
            }
            let status: StemWorkflowValidationStatus = validation.canContinue
                ? .passed(
                    summary: validation.analysisIssues.isEmpty
                        ? "\(validation.measurements.count)項目を検証済み"
                        : "構造検証済み・解析警告 \(validation.analysisIssues.count)件"
                )
                : .failed(message: validationFailureSummary(validation))
            try session.updateValidationState(
                StemWorkflowValidationDisplayState(
                    runID: runID,
                    subject: subject,
                    status: status
                )
            )

        case .stemEvaluationCompleted(_, let evaluation):
            guard let runID = activeRunID else {
                throw StemWorkflowSessionError.noActiveRun
            }
            guard executionKind == .newRun,
                  let runContract,
                  runContract.validationRoles.contains(evaluation.role),
                  evaluation.rawArtifact.kind == .rawStem(evaluation.role),
                  evaluation.correctedArtifact?.kind == .correctedStem(evaluation.role) else {
                throw StemWorkflowSessionError.validationOutsideRunContract(
                    evaluation.role.rawValue
                )
            }
            let presentation = try StemModeStemEvaluationPresentation(
                workflowEvaluation: evaluation
            )
            var current = workspaceModel?.stemEvaluations ?? []
            current.removeAll { $0.role == presentation.role }
            current.append(presentation)
            workspaceModel?.replaceStemEvaluations(current)
            try session.updateValidationState(
                StemWorkflowValidationDisplayState(
                    runID: runID,
                    subject: .stem(presentation.role.rawValue),
                    status: .passed(
                        summary: presentation.usedRawFallback
                            ? "補正を完了できず、このStemのみrawを維持"
                            : presentation.hasCorrectionEvidence
                                ? "一本道のStem補正完了"
                                : "raw Stem解析完了"
                    )
                )
            )

        case let .log(runID, step, message):
            guard isWorkflowStepAllowed(step, during: executionKind) else {
                throw StemWorkflowSessionError.progressOutsideRunContract(step.rawValue)
            }
            if let progressEvent = ProcessingProgressEvent.decode(message) {
                try applyProcessingProgressEvent(progressEvent, runID: runID)
                return
            }
            try session.appendLog(
                runID: runID,
                level: .info,
                step: step,
                message: message
            )
        }
    }

    private func applyProcessingProgressEvent(
        _ event: ProcessingProgressEvent,
        runID: UUID
    ) throws {
        switch event {
        case .correction:
            // Stem補正はroleとDSPを保持した専用progressを別経路で受け取ります。
            return
        case let .mastering(step, state, detail):
            let displayStep = StemModeProcessStep.mastering(step)
            let current = session.displayProgress(for: displayStep)
            let status: StemModeProcessStepStatus
            let fraction: Double
            switch state {
            case .started:
                status = .running
                fraction = 0
            case .detail:
                status = .running
                fraction = current.fraction
            case .completed:
                status = .completed
                fraction = 1
            case .skipped:
                status = .skipped
                fraction = 1
            case .failed:
                status = .failed
                fraction = current.fraction
            }
            try session.applyDisplayProgress(.init(
                runID: runID,
                step: displayStep,
                status: status,
                fraction: fraction,
                detail: detail
            ))
        }
    }

    private func applyProgress(_ progress: StemWorkflowExecutionProgress) throws {
        let current = session.progress(for: progress.step)
        switch current.status {
        case .pending:
            try session.beginStep(
                runID: progress.runID,
                step: progress.step,
                detail: progress.detail
            )
            if progress.fraction > 0 {
                try session.updateProgress(
                    runID: progress.runID,
                    step: progress.step,
                    fraction: progress.fraction,
                    detail: progress.detail
                )
            }
            if progress.fraction == 1 {
                try session.completeStep(
                    runID: progress.runID,
                    step: progress.step,
                    detail: progress.detail
                )
            }

        case .running:
            try session.updateProgress(
                runID: progress.runID,
                step: progress.step,
                fraction: progress.fraction,
                detail: progress.detail
            )
            if progress.fraction == 1 {
                try session.completeStep(
                    runID: progress.runID,
                    step: progress.step,
                    detail: progress.detail
                )
            }

        case .completed:
            return
        case .failed:
            return
        }
    }

    private func workflowSucceeded(_ result: StemWorkflowExecutionResult, runID: UUID) async {
        guard activeRunID == runID, !isShuttingDown else { return }
        do {
            try finalizeSuccessfulExecution(result)
        } catch {
            await finishFailedRun(error, runID: runID)
        }
    }

    private func workflowFailed(_ error: any Error, runID: UUID) async {
        guard activeRunID == runID, !isShuttingDown else { return }
        if isExpectedCancellation, error is CancellationError {
            return
        }
        await finishFailedRun(error, runID: runID)
    }

    private func finalizeSuccessfulExecution(
        _ result: StemWorkflowExecutionResult
    ) throws {
        switch result {
        case .correction(let correction):
            try finalizeSuccessfulCorrection(correction)
        case .remix(let remix):
            try finalizeSuccessfulRemix(remix)
        case .mastered(let mastered):
            try finalizeSuccessfulMastering(mastered)
        }
    }

    private func finalizeSuccessfulCorrection(
        _ result: StemWorkflowCorrectionResult
    ) throws {
        guard result.runID == activeRunID else {
            throw StemWorkflowControllerError.eventRunMismatch(
                expected: activeRunID ?? result.runID,
                actual: result.runID
            )
        }
        guard result.runContract == runContract,
              result.runContract == session.runContract else {
            throw StemWorkflowServiceError.runContractMismatch
        }
        do {
            workspaceModel?.replaceStemEvaluations(
                try result.stemEvaluations.map {
                    try StemModeStemEvaluationPresentation(workflowEvaluation: $0)
                }
            )
        } catch {
            try? session.appendLog(
                runID: result.runID,
                level: .warning,
                step: .validateCorrectedStems,
                message: "Stem別結果の画面表示を省略しました: \(error.localizedDescription)"
            )
        }
        workspaceModel?.setWorkflowInputEvaluation(result.canonicalInputEvaluation)
        workspaceModel?.setAutomaticRemixPlan(result.automaticRemixPlan)
        do {
            workspaceModel?.setRemixAnalysisPresentation(
                try StemModeRemixAnalysisPresentation(correctionResult: result)
            )
        } catch {
            try? session.appendLog(
                runID: result.runID,
                level: .warning,
                step: .validateCorrectedPureSum,
                message: "純粋加算解析の画面表示を省略しました: \(error.localizedDescription)"
            )
        }
        for evaluation in result.stemEvaluations {
            if let artifact = evaluation.correctedArtifact {
                try session.updateArtifactState(StemWorkflowArtifactDisplayState(
                    id: artifact.id,
                    runID: result.runID,
                    kind: artifact.kind,
                    artifact: artifact,
                    status: .valid
                ))
            }
        }
        let correctedRemix = result.remixArtifacts.correctedPureSum
        try session.updateArtifactState(StemWorkflowArtifactDisplayState(
            id: correctedRemix.id,
            runID: result.runID,
            kind: correctedRemix.kind,
            artifact: correctedRemix,
            status: .valid
        ))
        correctionResult = result
        updatePreviewSourcesFromValidatedArtifacts()
        try session.completeCorrection(runID: result.runID)
        session.recordCorrectedRemixAnalysis(result.correctedRemixEvaluation.audioMetrics)
        notifyCompletionIfNeeded(.correction, runContract: result.runContract)
        finishStoppedRun()
    }

    private func finalizeSuccessfulRemix(_ result: StemWorkflowRemixResult) throws {
        guard result.runID == activeRunID else {
            throw StemWorkflowControllerError.eventRunMismatch(
                expected: activeRunID ?? result.runID,
                actual: result.runID
            )
        }
        guard result.runContract == runContract,
              result.runContract == session.runContract else {
            throw StemWorkflowServiceError.runContractMismatch
        }
        try session.updateArtifactState(StemWorkflowArtifactDisplayState(
            id: result.artifact.id,
            runID: result.runID,
            kind: result.artifact.kind,
            artifact: result.artifact,
            status: .valid
        ))
        workspaceModel?.setRemixResult(result)
        remixResult = result
        updatePreviewSourcesFromValidatedArtifacts()
        try session.completeRemix(runID: result.runID)
        finishStoppedRun()
    }

    private func finalizeSuccessfulMastering(_ result: StemWorkflowResult) throws {
        guard result.runID == activeRunID else {
            throw StemWorkflowControllerError.eventRunMismatch(
                expected: activeRunID ?? result.runID,
                actual: result.runID
            )
        }
        guard result.runContract == runContract,
              result.runContract == session.runContract else {
            throw StemWorkflowServiceError.runContractMismatch
        }
        do {
            workspaceModel?.setRemixAnalysisPresentation(
                try StemModeRemixAnalysisPresentation(result: result)
            )
        } catch {
            try? session.appendLog(
                runID: result.runID,
                level: .warning,
                step: .validateRemix,
                message: "再ミックス解析の画面表示を省略しました: \(error.localizedDescription)"
            )
        }
        workspaceModel?.setWorkflowInputEvaluation(result.canonicalInputEvaluation)
        do {
            workspaceModel?.replaceStemEvaluations(
                try result.stemEvaluations.map {
                    try StemModeStemEvaluationPresentation(
                        workflowEvaluation: $0
                    )
                }
            )
        } catch {
            try? session.appendLog(
                runID: result.runID,
                level: .warning,
                step: .validateCorrectedStems,
                message: "Stem別結果の画面表示を省略しました: \(error.localizedDescription)"
            )
        }
        workspaceModel?.setMasteringResult(result.mastering)
        let finalArtifact = result.mastering.finalArtifact
        try session.updateArtifactState(StemWorkflowArtifactDisplayState(
            id: finalArtifact.id,
            runID: result.runID,
            kind: finalArtifact.kind,
            artifact: finalArtifact,
            status: .valid
        ))
        updatePreviewSourcesFromValidatedArtifacts()
        try session.completeRun(runID: result.runID)
        session.recordFinalAnalysis(result.mastering.finalEvaluation.audioMetrics)
        notifyCompletionIfNeeded(.mastering, runContract: result.runContract)
        finishStoppedRun(keepFinalCommitLocked: true)
    }

    private func finishFailedRun(_ error: any Error, runID: UUID) async {
        if executionKind == .remix {
            remixResult = nil
            do {
                try session.restoreRemixReadyAfterFailure(
                    runID: runID,
                    message: error.localizedDescription
                )
                updatePreviewSourcesFromValidatedArtifacts()
            } catch let sessionError {
                workspaceModel?.presentControllerFailure(
                    title: "再ミックスを停止しました",
                    message: "\(error.localizedDescription)\n補正結果保持状態の表示更新にも失敗しました: \(sessionError.localizedDescription)"
                )
                finishStoppedRun()
                return
            }
            workspaceModel?.presentControllerFailure(
                title: "再ミックスを停止しました",
                message: "補正済み\(session.runContract?.stemCount ?? 0)Stemと純粋加算は保持しています。\n\(error.localizedDescription)"
            )
            finishStoppedRun()
            return
        } else if executionKind == .mastering {
            do {
                try session.restoreMasteringReadyAfterFailure(
                    runID: runID,
                    message: error.localizedDescription
                )
                updatePreviewSourcesFromValidatedArtifacts()
            } catch let sessionError {
                workspaceModel?.presentControllerFailure(
                    title: "マスタリングを停止しました",
                    message: "\(error.localizedDescription)\n補正済みStem保持状態の表示更新にも失敗しました: \(sessionError.localizedDescription)"
                )
                finishStoppedRun()
                return
            }
            workspaceModel?.presentControllerFailure(
                title: "マスタリングを停止しました",
                message: "補正済み\(session.runContract?.stemCount ?? 0)Stem、純粋加算、Stem再ミックスは保持しています。\n\(error.localizedDescription)"
            )
            finishStoppedRun()
            return
        } else {
            var failureMessage = error.localizedDescription
            do {
                try await workflow.discardSession(runID: runID)
            } catch {
                failureMessage += "\n一時成果物の削除にも失敗しました: \(error.localizedDescription)"
            }
            do {
                try session.fail(
                    runID: runID,
                    step: session.currentStep,
                    message: failureMessage,
                    recoverySuggestion: "入力音源と右サイドのStem分離にあるモデル状態を確認してください。"
                )
                correctionResult = nil
                remixResult = nil
                workspaceModel?.resetRunPresentationAfterCorrectionFailure()
                updatePreviewSourcesFromValidatedArtifacts()
            } catch let sessionError {
                workspaceModel?.presentControllerFailure(
                    title: "Stem Mode処理を停止しました",
                    message: "\(error.localizedDescription)\n表示状態の記録にも失敗しました: \(sessionError.localizedDescription)"
                )
                finishStoppedRun()
                return
            }
        }
        workspaceModel?.presentControllerFailure(
            title: "Stem Mode処理を停止しました",
            message: session.lastError?.message ?? error.localizedDescription
        )
        finishStoppedRun()
    }

    private func finishStoppedRun(keepFinalCommitLocked: Bool = false) {
        workspaceModel?.stopPreviewPlayback()
        if !keepFinalCommitLocked {
            workspaceModel?.setFinalCommitLockState(.unlocked)
        }
        releaseInputLease()
        resetExecutionState()
    }

    private func prepareExecution(
        kind: ExecutionKind,
        runID: UUID,
        usesExistingSession: Bool = false
    ) {
        switch kind {
        case .newRun:
            notifiedCompletionStages = []
        case .mastering:
            notifiedCompletionStages.remove(.mastering)
        case .remix:
            break
        }
        activeRunID = runID
        executionKind = kind
        isExpectedCancellation = false
        workspaceModel?.setFinalCommitLockState(.unlocked)
    }

    private func notifyCompletionIfNeeded(
        _ stage: StemCompletionNotificationStage,
        runContract: StemModelRunContract
    ) {
        guard notifiedCompletionStages.insert(stage).inserted else { return }
        notificationReporter.notifyStemCompletion(
            for: stage,
            runContract: runContract
        )
    }

    private func resetExecutionState() {
        workflowTask = nil
        activeRunID = nil
        executionKind = nil
        isExpectedCancellation = false
        isProcessingRun = false
    }

    private func requireNoActiveWorkflow() throws {
        guard !isProcessingRun, activeRunID == nil, workflowTask == nil else {
            throw StemWorkflowControllerError.workflowAlreadyActive
        }
    }

    private func discardInactiveSessionRunIfPresent() async throws {
        guard let runID = session.runID else { return }
        switch session.state {
        case .readyForRemix, .readyForMastering, .completed, .failed:
            try await workflow.discardSession(runID: runID)
            correctionResult = nil
            remixResult = nil
            runContract = nil
            session.resetForInputChange()
        case .idle:
            runContract = nil
            session.resetForInputChange()
        case .ready,
             .running:
            throw StemWorkflowControllerError.workflowAlreadyActive
        }
    }

    private func currentReadyResources() throws -> ReadyResources {
        guard !modelManager.isModelOperationInProgress else {
            throw StemWorkflowControllerError.modelOperationInProgress
        }
        guard let resources = readyResourcesFromCurrentInspection() else {
            throw StemWorkflowControllerError.validatedResourcesUnavailable
        }
        return resources
    }

    private func readyResourcesFromCurrentInspection() -> ReadyResources? {
        guard let inspection = modelManager.localInspection,
              case .supportedAppleSilicon = inspection.platform,
              case .valid(let manifest) = inspection.manifest,
              case .ready(let installation) = inspection.installedModel,
              case .ready(let bundledRuntime) = inspection.bundledRuntime else {
            return nil
        }
        return ReadyResources(
            manifest: manifest,
            installation: installation,
            bundledRuntime: bundledRuntime
        )
    }

    private func updateModelPresentation(_ resources: ReadyResources) throws {
        guard let workspaceModel else {
            throw StemWorkflowControllerError.workspaceUnavailable
        }
        workspaceModel.setModelPresentation(
            try StemModeModelPresentation(
                manifest: resources.manifest,
                installation: resources.installation,
                bundledRuntime: resources.bundledRuntime
            )
        )
    }

    private func prepareSeparationSettingsIfNeeded(
        _ resources: ReadyResources
    ) throws {
        guard let workspaceModel else {
            throw StemWorkflowControllerError.workspaceUnavailable
        }
        guard workspaceModel.selectedInputURL != nil else {
            return
        }
        if workspaceModel.separationSettings?.model
            == resources.installation.snapshot.contract.separationModel {
            return
        }
        workspaceModel.clearSeparationSettings()
        let settings = try StemSeparationSettings
            .production(
                for: resources.installation.snapshot.contract.separationModel,
                seed: seedProvider()
            )
            .validated(modelContract: resources.installation.snapshot.contract)
        try workspaceModel.setProductionSeparationSettings(settings)
    }

    private func updatePreviewSourcesFromValidatedArtifacts() {
        let artifacts = session.artifactStates.compactMap { state -> StemAudioArtifact? in
            guard case .valid = state.status else { return nil }
            return state.artifact
        }
        workspaceModel?.updatePreviewSources(from: artifacts)
    }

    private func beginSecurityScopedLease(for URL: URL) -> SecurityScopedLease {
        SecurityScopedLease(
            URL: URL,
            didStartAccessing: securityScopedAccessor.startAccessing(URL)
        )
    }

    private func ensureInputLease(for URL: URL) {
        if inputLease?.URL.standardizedFileURL == URL.standardizedFileURL {
            return
        }
        replaceInputLease(with: beginSecurityScopedLease(for: URL))
    }

    private func replaceInputLease(with lease: SecurityScopedLease) {
        releaseInputLease()
        inputLease = lease
    }

    private func releaseInputLease() {
        guard let lease = inputLease else { return }
        inputLease = nil
        endSecurityScopedLease(lease)
    }

    private func endSecurityScopedLease(_ lease: SecurityScopedLease) {
        if lease.didStartAccessing {
            securityScopedAccessor.stopAccessing(lease.URL)
        }
    }

    private func eventRunID(_ event: StemWorkflowEvent) -> UUID {
        switch event {
        case let .log(runID, _, _):
            runID
        case .progress(let progress):
            progress.runID
        case .displayProgress(let progress):
            progress.runID
        case .artifactCommitted(let runID, _):
            runID
        case .validationCompleted(let runID, _):
            runID
        case .stemEvaluationCompleted(let runID, _):
            runID
        }
    }

    private func isArtifactAllowed(
        _ kind: StemArtifactKind,
        during executionKind: ExecutionKind?,
        runContract: StemModelRunContract
    ) -> Bool {
        switch (executionKind, kind) {
        case (.newRun, .input44100),
             (.newRun, .correctedPureSum48000),
             (.remix, .remixed48000),
             (.mastering, .finalMaster):
            return true
        case (.newRun, .rawStem(let role)):
            return runContract.activeRoles.contains(role)
        case (.newRun, .correctedStem(let role)):
            return runContract.validationRoles.contains(role)
        default:
            return false
        }
    }

    private func isWorkflowStepAllowed(
        _ step: StemWorkflowStep,
        during executionKind: ExecutionKind?
    ) -> Bool {
        switch executionKind {
        case .newRun:
            return switch step {
            case .validateInput, .separate, .validateSeparatedStems,
                 .evaluateStems, .correctStems, .validateCorrectedStems,
                 .correctedPureSum, .validateCorrectedPureSum:
                true
            case .remix, .validateRemix, .mastering, .finalizeMaster:
                false
            }
        case .remix:
            return step == .remix || step == .validateRemix
        case .mastering:
            return step == .mastering || step == .finalizeMaster
        case nil:
            return false
        }
    }

    private func isDisplayDomainAllowed(
        _ domain: StemModeProcessDomain,
        during executionKind: ExecutionKind?
    ) -> Bool {
        switch (executionKind, domain) {
        case (.newRun, .correction), (.remix, .remix), (.mastering, .mastering):
            true
        default:
            false
        }
    }

    private func isValidationPhaseAllowed(
        _ phase: StemValidationPhase,
        during executionKind: ExecutionKind?
    ) -> Bool {
        switch (executionKind, phase) {
        case (.newRun, .separatedStems),
             (.newRun, .remix),
             (.newRun, .correctedPureSum),
             (.remix, .processedRemix):
            true
        default:
            false
        }
    }

    private func validationFailureSummary(_ result: StemValidationResult) -> String {
        result.failedChecks
            .map { "\($0.check.rawValue): \($0.subject) — \($0.detail)" }
            .joined(separator: " / ")
    }

    private func suggestedExportFileName(
        artifact: StemAudioArtifact,
        format: AudioExportFormat
    ) -> String {
        let baseName = artifact.fileURL.deletingPathExtension().lastPathComponent
        return "\(baseName)-export.\(format.fileExtension)"
    }

    private func isSafeExternalExportDestination(
        _ destinationURL: URL,
        sourceURL: URL
    ) -> Bool {
        guard destinationURL.isFileURL,
              destinationURL.query == nil,
              destinationURL.fragment == nil else {
            return false
        }
        let normalizedDestination = resolvedDestinationURL(destinationURL)
        let normalizedSource = sourceURL.resolvingSymlinksInPath().standardizedFileURL
        guard normalizedDestination != normalizedSource else { return false }
        return !isURL(normalizedDestination, inside: StemWorkflowService.temporaryRootURL)
    }

    private func resolvedDestinationURL(_ URL: URL) -> URL {
        let parent = URL.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return parent.appending(path: URL.lastPathComponent).standardizedFileURL
    }

    private func isURL(_ candidate: URL, inside directory: URL) -> Bool {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let path = candidate.resolvingSymlinksInPath().standardizedFileURL.path
        return path == root || path.hasPrefix(root + "/")
    }
}
