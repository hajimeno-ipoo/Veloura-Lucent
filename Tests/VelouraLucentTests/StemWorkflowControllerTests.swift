import Foundation
import Testing
@testable import VelouraLucent

private struct ReadyStemModelInspector: StemModelLocalInspecting {
    let inspection: StemModelLocalInspection
    func inspect() async -> StemModelLocalInspection { inspection }
}

private struct AutomaticStemInputInspector: StemWorkflowInputInspecting {
    func inspect(inputURL: URL) async throws -> StemInputInspection {
        let layout = StemInputLayoutIdentity(
            channelCount: 2,
            layoutTag: 0,
            channelBitmap: 0,
            channelDescriptions: []
        )
        return StemInputInspection(
            inputURL: inputURL,
            sampleRate: 44_100,
            channelCount: 2,
            frameCount: 32,
            layoutIdentity: layout,
            matrixResolution: .automatic(StemInputChannelMatrix(
                source: .stereoIdentity,
                inputLayout: layout,
                coefficients: [1, 0, 0, 1]
            ))
        )
    }
}

private struct EmptyStemDisplayAnalyzer: StemInputDisplayAnalyzing {
    func analyze(
        inputURL: URL,
        analysisMode: StemAudioAnalysisMode,
        logHandler: (@Sendable (String) -> Void)?
    ) async throws -> StemModeInputDisplayAnalysisResult {
        StemModeInputDisplayAnalysisResult(
            evaluation: nil,
            previewSnapshot: AudioPreviewSnapshot(
                waveform: [.zero, .zero],
                duration: 1,
                bandLevels: [:],
                bandLevelDBs: [:]
            ),
            spectrogram: .empty,
            warning: nil
        )
    }
}

@MainActor
private final class StemCompletionNotificationReporterSpy: StemCompletionNotificationReporting {
    struct Call: Equatable {
        let stage: StemCompletionNotificationStage
        let runContract: StemModelRunContract
    }

    private(set) var calls: [Call] = []

    func notifyStemCompletion(
        for stage: StemCompletionNotificationStage,
        runContract: StemModelRunContract
    ) {
        calls.append(Call(stage: stage, runContract: runContract))
    }
}

private actor SuspendedCorrectionWorkflow: StemWorkflowExecuting {
    private(set) var correctionStarted = false
    private(set) var discardedSessionIDs: [UUID] = []

    func processCorrection(
        _ request: StemWorkflowRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowCorrectionResult {
        correctionStarted = true
        while true {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func processMastering(
        _ request: StemWorkflowMasteringRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowResult {
        throw CancellationError()
    }

    func processRemix(
        correction: StemWorkflowCorrectionResult,
        settings: StemRemixSettings,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowRemixResult {
        let artifact = makeControllerArtifact(
            id: "stem-remix",
            kind: .remixed48000,
            baseURL: correction.sessionDirectory
        )
        let result = StemWorkflowRemixResult(
            correction: correction,
            artifact: artifact,
            evaluation: makeControllerEvaluation(purpose: .remix),
            validation: StemValidationResult(
                phase: .processedRemix,
                failedChecks: [],
                measurements: []
            ),
            appliedSettings: settings,
            rawFallbackReasons: [:]
        )
        await eventHandler(.artifactCommitted(runID: correction.runID, artifact: artifact))
        await eventHandler(.validationCompleted(runID: correction.runID, result: result.validation))
        return result
    }

    func discardSession(runID: UUID) async throws {
        discardedSessionIDs.append(runID)
    }
}

private struct ImmediateCorrectionWorkflow: StemWorkflowExecuting {
    func processCorrection(
        _ request: StemWorkflowRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowCorrectionResult {
        let result = makeImmediateCorrectionResult(request: request)
        await eventHandler(.displayProgress(.init(
            runID: request.runID,
            step: .inputPreparation,
            status: .completed,
            fraction: 1,
            detail: "入力準備完了"
        )))
        await eventHandler(.log(
            runID: request.runID,
            step: .correctStems,
            message: ProcessingProgressEvent.correction(
                step: .analyze,
                state: .started,
                detail: nil
            ).encodedMessage
        ))
        await eventHandler(.artifactCommitted(runID: request.runID, artifact: result.input.artifact))
        for artifact in result.separation.stems {
            await eventHandler(.artifactCommitted(runID: request.runID, artifact: artifact))
        }
        for role in request.runContract.activeRoles {
            let artifact = makeControllerArtifact(
                id: "corrected-\(role.rawValue)",
                kind: .correctedStem(role),
                baseURL: result.sessionDirectory
            )
            await eventHandler(.artifactCommitted(runID: request.runID, artifact: artifact))
        }
        await eventHandler(.artifactCommitted(
            runID: request.runID,
            artifact: result.remixArtifacts.correctedPureSum
        ))
        return result
    }

    func processMastering(
        _ request: StemWorkflowMasteringRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowResult {
        throw CancellationError()
    }

    func processRemix(
        correction: StemWorkflowCorrectionResult,
        settings: StemRemixSettings,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowRemixResult {
        let artifact = makeControllerArtifact(
            id: "stem-remix",
            kind: .remixed48000,
            baseURL: correction.sessionDirectory
        )
        let result = StemWorkflowRemixResult(
            correction: correction,
            artifact: artifact,
            evaluation: makeControllerEvaluation(purpose: .remix),
            validation: StemValidationResult(
                phase: .processedRemix,
                failedChecks: [],
                measurements: []
            ),
            appliedSettings: settings,
            rawFallbackReasons: [:]
        )
        await eventHandler(.artifactCommitted(runID: correction.runID, artifact: artifact))
        await eventHandler(.validationCompleted(runID: correction.runID, result: result.validation))
        return result
    }

    func discardSession(runID: UUID) async throws {}
}

private enum IntentionalStemWorkflowError: LocalizedError {
    case correctionFailure
    case remixFailure
    case masteringFailure

    var errorDescription: String? {
        switch self {
        case .correctionFailure: "意図した補正失敗"
        case .remixFailure: "意図した再ミックス失敗"
        case .masteringFailure: "意図したマスタリング失敗"
        }
    }
}

private actor RetryAndStaleEventWorkflow: StemWorkflowExecuting {
    private(set) var runIDs: [UUID] = []
    private(set) var discardedSessionIDs: [UUID] = []
    private(set) var secondRunStarted = false

    func processCorrection(
        _ request: StemWorkflowRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowCorrectionResult {
        runIDs.append(request.runID)
        if runIDs.count == 1 {
            let input = makeControllerArtifact(
                id: "failed-input",
                kind: .input44100,
                baseURL: FileManager.default.temporaryDirectory
            )
            await eventHandler(.artifactCommitted(runID: request.runID, artifact: input))
            let stale = makeControllerArtifact(
                id: "stale-old-run",
                kind: .input44100,
                baseURL: FileManager.default.temporaryDirectory
            )
            Task {
                try? await Task.sleep(for: .milliseconds(120))
                await eventHandler(.artifactCommitted(runID: request.runID, artifact: stale))
            }
            throw IntentionalStemWorkflowError.correctionFailure
        }

        secondRunStarted = true
        let excluded = makeControllerArtifact(
            id: "contract-out-guitar",
            kind: .rawStem(.guitar),
            baseURL: FileManager.default.temporaryDirectory
        )
        await eventHandler(.artifactCommitted(runID: request.runID, artifact: excluded))
        while true {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func processMastering(
        _ request: StemWorkflowMasteringRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowResult {
        throw CancellationError()
    }

    func processRemix(
        correction: StemWorkflowCorrectionResult,
        settings: StemRemixSettings,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowRemixResult {
        throw CancellationError()
    }

    func discardSession(runID: UUID) async throws {
        discardedSessionIDs.append(runID)
    }
}

private actor FinalizationSuspendingWorkflow: StemWorkflowExecuting {
    private(set) var finalizationStarted = false

    func processCorrection(
        _ request: StemWorkflowRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowCorrectionResult {
        let result = makeImmediateCorrectionResult(request: request)
        await eventHandler(.artifactCommitted(runID: request.runID, artifact: result.input.artifact))
        for artifact in result.separation.stems {
            await eventHandler(.artifactCommitted(runID: request.runID, artifact: artifact))
        }
        for role in request.runContract.activeRoles {
            let artifact = makeControllerArtifact(
                id: "corrected-\(role.rawValue)",
                kind: .correctedStem(role),
                baseURL: result.sessionDirectory
            )
            await eventHandler(.artifactCommitted(runID: request.runID, artifact: artifact))
        }
        await eventHandler(.artifactCommitted(
            runID: request.runID,
            artifact: result.remixArtifacts.correctedPureSum
        ))
        return result
    }

    func processRemix(
        correction: StemWorkflowCorrectionResult,
        settings: StemRemixSettings,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowRemixResult {
        let artifact = makeControllerArtifact(
            id: "stem-remix",
            kind: .remixed48000,
            baseURL: correction.sessionDirectory
        )
        let result = StemWorkflowRemixResult(
            correction: correction,
            artifact: artifact,
            evaluation: makeControllerEvaluation(purpose: .remix),
            validation: StemValidationResult(
                phase: .processedRemix,
                failedChecks: [],
                measurements: []
            ),
            appliedSettings: settings,
            rawFallbackReasons: [:]
        )
        await eventHandler(.artifactCommitted(runID: correction.runID, artifact: artifact))
        return result
    }

    func processMastering(
        _ request: StemWorkflowMasteringRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowResult {
        finalizationStarted = true
        await eventHandler(.displayProgress(.init(
            runID: request.runID,
            step: .finalization,
            status: .running,
            fraction: 0,
            detail: "最終版を保存中"
        )))
        while true {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func discardSession(runID: UUID) async throws {}
}

private actor PostCorrectionStageWorkflow: StemWorkflowExecuting {
    private(set) var remixAttemptCount = 0
    private(set) var masteringAttemptCount = 0
    private(set) var remixCancellationAttemptStarted = false
    private(set) var masteringCancellationAttemptStarted = false

    func processCorrection(
        _ request: StemWorkflowRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowCorrectionResult {
        let result = makeImmediateCorrectionResult(request: request)
        await eventHandler(.artifactCommitted(runID: request.runID, artifact: result.input.artifact))
        for artifact in result.separation.stems {
            await eventHandler(.artifactCommitted(runID: request.runID, artifact: artifact))
        }
        for role in request.runContract.activeRoles {
            let artifact = makeControllerArtifact(
                id: "corrected-\(role.rawValue)",
                kind: .correctedStem(role),
                baseURL: result.sessionDirectory
            )
            await eventHandler(.artifactCommitted(runID: request.runID, artifact: artifact))
        }
        await eventHandler(.artifactCommitted(
            runID: request.runID,
            artifact: result.remixArtifacts.correctedPureSum
        ))
        return result
    }

    func processRemix(
        correction: StemWorkflowCorrectionResult,
        settings: StemRemixSettings,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowRemixResult {
        remixAttemptCount += 1
        if remixAttemptCount == 1 {
            throw IntentionalStemWorkflowError.remixFailure
        }
        if remixAttemptCount == 2 {
            remixCancellationAttemptStarted = true
            while true {
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        let artifact = makeControllerArtifact(
            id: "stage-remix",
            kind: .remixed48000,
            baseURL: correction.sessionDirectory
        )
        let result = StemWorkflowRemixResult(
            correction: correction,
            artifact: artifact,
            evaluation: makeControllerEvaluation(purpose: .remix),
            validation: StemValidationResult(
                phase: .processedRemix,
                failedChecks: [],
                measurements: []
            ),
            appliedSettings: settings,
            rawFallbackReasons: [:]
        )
        await eventHandler(.artifactCommitted(runID: correction.runID, artifact: artifact))
        return result
    }

    func processMastering(
        _ request: StemWorkflowMasteringRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowResult {
        masteringAttemptCount += 1
        if masteringAttemptCount == 1 {
            throw IntentionalStemWorkflowError.masteringFailure
        }
        masteringCancellationAttemptStarted = true
        while true {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    func discardSession(runID: UUID) async throws {}
}

@MainActor
struct StemWorkflowControllerTests {
    @Test("モデル未取得でも入力選択と表示解析を行い補正だけを無効にする")
    func missingModelKeepsInputInspectionAvailableAndCorrectionDisabled() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(
                path: "StemWorkflowControllerMissingModelTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try makeStemTestInstallation(rootURL: root)
        let runtime = StemBundledRuntimeValidationReport(
            contract: fixture.installation.snapshot.contract,
            assets: fixture.manifest.bundledRuntimeAssets.map { asset in
                ValidatedStemModelAsset(
                    kind: asset.kind,
                    fileURL: root.appending(path: asset.runtimeRelativePath),
                    byteCount: asset.byteCount,
                    sha256: asset.sha256
                )
            }
        )
        let manager = StemModelManager(
            inspector: ReadyStemModelInspector(
                inspection: StemModelLocalInspection(
                    platform: .supportedAppleSilicon,
                    manifest: .valid(fixture.manifest),
                    installedModel: .missing,
                    bundledRuntime: .ready(runtime)
                )
            )
        )
        await manager.inspectLocalResources()

        let session = StemWorkflowSession()
        let controller = StemWorkflowController(
            session: session,
            modelManager: manager,
            workflow: ImmediateCorrectionWorkflow(),
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            seedProvider: { 77 },
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)
        controller.synchronizeModelReadiness()

        let inputURL = root.appending(path: "source.wav")
        await workspace.inspectInput(inputURL)
        try await waitUntil {
            workspace.selectedInputURL == inputURL && !workspace.isInspectingInput
        }

        #expect(workspace.selectedInputURL == inputURL)
        #expect(workspace.modelPresentation == nil)
        #expect(workspace.separationSettings == nil)
        #expect(!workspace.canRunCorrection)
        #expect(workspace.presentedError == nil)
    }

    @Test
    func correctionAndRemixCompletionConnectPureSumAndRemixToABPreview() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemWorkflowControllerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = try await makeReadyManager(root: root)
        let session = StemWorkflowSession()
        let controller = StemWorkflowController(
            session: session,
            modelManager: manager,
            workflow: ImmediateCorrectionWorkflow(),
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            seedProvider: { 77 },
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)
        controller.synchronizeModelReadiness()
        let inputURL = root.appending(path: "source.wav")
        await workspace.inspectInput(inputURL)
        try await waitUntil { workspace.selectedInputURL == inputURL && !workspace.isInspectingInput }

        try await controller.actions.beginCorrection(StemModeStartRequest(
            inputURL: inputURL,
            separationSettings: .metaHTDemucsProduction(seed: 77),
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringProfile: .streaming,
            masteringSettings: MasteringProfile.streaming.settings
        ))
        try await waitUntil {
            if case .readyForRemix = session.state { return true }
            return false
        }

        let pureSum = try #require(workspace.correctedPureSumPreviewArtifact)
        #expect(pureSum.kind == .correctedPureSum48000)
        #expect(workspace.previewController.cardState(for: .corrected).sourceURL == pureSum.fileURL)
        #expect(workspace.previewController.comparisonPair == .inputVsCorrected)
        #expect(workspace.remixAnalysisPresentation != nil)
        #expect(session.progress(for: .correctedPureSum).status == .completed)
        #expect(session.progress(for: .validateCorrectedPureSum).status == .completed)
        #expect(session.displayProgress(for: .inputPreparation).status == .completed)
        #expect(!session.logs.contains { $0.message.contains("__veloura_progress__") })
        #expect(workspace.canRunRemix)

        await workspace.beginRemix()
        try await waitUntil {
            if case .readyForMastering = session.state { return true }
            return false
        }
        let remixed = try #require(workspace.remixedPreviewArtifact)
        #expect(remixed.kind == .remixed48000)
        #expect(workspace.remixPreviewController.cardState(for: .input).sourceURL == pureSum.fileURL)
        #expect(workspace.remixPreviewController.cardState(for: .corrected).sourceURL == remixed.fileURL)
        #expect(workspace.remixAnalysisPresentation?.processedRemixEvaluation?.purpose == .remix)
        #expect(session.recentActivityEvents.filter { $0.domain == .correction }.map(\.title) == [
            "補正処理が完了しました",
            "補正後を解析しました",
        ])
        #expect(session.recentActivityEvents.filter { $0.domain == .remix }.map(\.title) == [
            "再ミックスが完了しました",
        ])

        try await controller.actions.beginMastering(StemModeMasteringRequest(
            masteringSettings: MasteringProfile.streaming.settings
        ))
        try await waitUntil { session.lastError != nil }

        let currentRunID = try #require(session.runID)
        #expect(session.state == .readyForMastering(runID: currentRunID))
        #expect(workspace.correctedRemixPreviewArtifact == remixed)
        #expect(workspace.finalPreviewArtifact == nil)
        #expect(workspace.previewController.cardState(for: .corrected).sourceURL == remixed.fileURL)
    }

    @Test
    func bsRoformerReadyResourcesPrepareModelSpecificSettingsInExistingWorkspace() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemWorkflowControllerBSRoformerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try makeStemTestInstallation(rootURL: root, model: .bsRoformerSW)
        let runtime = StemBundledRuntimeValidationReport(
            contract: fixture.installation.snapshot.contract,
            assets: fixture.manifest.bundledRuntimeAssets.map { asset in
                ValidatedStemModelAsset(
                    kind: asset.kind,
                    fileURL: root.appending(path: asset.runtimeRelativePath),
                    byteCount: asset.byteCount,
                    sha256: asset.sha256
                )
            }
        )
        let manager = StemModelManager(inspector: ReadyStemModelInspector(inspection: .init(
            platform: .supportedAppleSilicon,
            manifest: .valid(fixture.manifest),
            installedModel: .ready(fixture.installation),
            bundledRuntime: .ready(runtime)
        )))
        await manager.selectModel(.bsRoformerSW)

        let session = StemWorkflowSession()
        let notificationReporter = StemCompletionNotificationReporterSpy()
        let controller = StemWorkflowController(
            session: session,
            modelManager: manager,
            workflow: ImmediateCorrectionWorkflow(),
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: notificationReporter,
            seedProvider: { 77 },
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)
        controller.synchronizeModelReadiness()
        let inputURL = root.appending(path: "source.wav")
        await workspace.inspectInput(inputURL)
        try await waitUntil {
            workspace.selectedInputURL == inputURL && !workspace.isInspectingInput
        }

        #expect(workspace.separationSettings == .bsRoformerSWProduction)
        #expect(workspace.modelPresentation?.modelName == "BS-RoFormer-SW")
        #expect(workspace.canRunCorrection)

        try await controller.actions.beginCorrection(StemModeStartRequest(
            inputURL: inputURL,
            separationSettings: .bsRoformerSWProduction,
            correctionSettings: StemRoleCorrectionSettings(
                all: DenoiseStrength.balanced.settings
            ),
            masteringProfile: .streaming,
            masteringSettings: MasteringProfile.streaming.settings
        ))
        try await waitUntil { workspace.canRunRemix }
        let capturedContract = try #require(session.runContract)

        await manager.selectModel(.htdemucs)

        #expect(capturedContract.stemCount == 6)
        #expect(session.runContract == capturedContract)
        #expect(workspace.runContract == capturedContract)
        #expect(notificationReporter.calls == [
            .init(stage: .correction, runContract: capturedContract),
        ])
    }

    @Test
    func correctionCancellationKeepsSelectedInputAndDiscardsOnlyStemSession() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemWorkflowControllerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = try makeStemTestInstallation(rootURL: root)
        let runtime = StemBundledRuntimeValidationReport(
            contract: fixture.installation.snapshot.contract,
            assets: fixture.manifest.bundledRuntimeAssets.map { asset in
                ValidatedStemModelAsset(
                    kind: asset.kind,
                    fileURL: root.appending(path: asset.runtimeRelativePath),
                    byteCount: asset.byteCount,
                    sha256: asset.sha256
                )
            }
        )
        let manager = StemModelManager(inspector: ReadyStemModelInspector(inspection: .init(
            platform: .supportedAppleSilicon,
            manifest: .valid(fixture.manifest),
            installedModel: .ready(fixture.installation),
            bundledRuntime: .ready(runtime)
        )))
        await manager.inspectLocalResources()

        let workflow = SuspendedCorrectionWorkflow()
        let session = StemWorkflowSession()
        let controller = StemWorkflowController(
            session: session,
            modelManager: manager,
            workflow: workflow,
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            seedProvider: { 77 },
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)
        controller.synchronizeModelReadiness()
        let inputURL = root.appending(path: "source.wav")
        await workspace.inspectInput(inputURL)
        try await waitUntil { workspace.selectedInputURL == inputURL && !workspace.isInspectingInput }

        let settings = StemSeparationSettings.metaHTDemucsProduction(seed: 77)
        try await controller.actions.beginCorrection(StemModeStartRequest(
            inputURL: inputURL,
            separationSettings: settings,
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringProfile: .streaming,
            masteringSettings: MasteringProfile.streaming.settings
        ))
        try await waitUntil { await workflow.correctionStarted }
        let sessionID = try #require(session.runID)

        try await controller.actions.cancelCorrection()

        #expect(workspace.selectedInputURL == inputURL)
        #expect(session.state == .idle)
        #expect(await workflow.discardedSessionIDs == [sessionID])
    }

    @Test
    func inputChangeDiscardsPreviousCompletedStemSession() async throws {
        let workflow = SuspendedCorrectionWorkflow()
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
        try completeCorrection(in: session, sessionID: sessionID)
        try session.completeCorrection(runID: sessionID)
        let controller = StemWorkflowController(
            session: session,
            modelManager: StemModelManager(),
            workflow: workflow,
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            revealInFinder: { _ in }
        )

        try await controller.actions.resetForInputChange()

        #expect(await workflow.discardedSessionIDs == [sessionID])
        #expect(session.state == .idle)
        #expect(session.runID == nil)
    }

    @Test("入力変更のController境界は再ミックス手動下書きも初期化する")
    func inputChangeResetsWorkspaceManualRemixDraft() async throws {
        let session = StemWorkflowSession()
        let controller = StemWorkflowController(
            session: session,
            modelManager: StemModelManager(),
            workflow: SuspendedCorrectionWorkflow(),
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)

        await workspace.inspectInput(URL(fileURLWithPath: "/tmp/remix-draft-first.wav"))
        try await waitUntil { workspace.selectedInputURL != nil && !workspace.isInspectingInput }
        try workspace.setRemixManualEditingEnabled(true)
        try workspace.setRemixPan(0.45, for: .vocals)

        let replacementURL = URL(fileURLWithPath: "/tmp/remix-draft-second.wav")
        await workspace.inspectInput(replacementURL)
        try await waitUntil {
            workspace.selectedInputURL == replacementURL && !workspace.isInspectingInput
        }

        #expect(workspace.manualRemixOverrides == StemRemixManualOverrides())
        #expect(!workspace.isRemixManualEditingEnabled)
        #expect(workspace.automaticRemixPlan == nil)
    }

    @Test("同じ入力を選び直しても再ミックス手動下書きを保持する")
    func sameInputSelectionPreservesWorkspaceManualRemixDraft() async throws {
        let session = StemWorkflowSession()
        let controller = StemWorkflowController(
            session: session,
            modelManager: StemModelManager(),
            workflow: SuspendedCorrectionWorkflow(),
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)
        let inputURL = URL(fileURLWithPath: "/tmp/remix-draft-same.wav")

        await workspace.inspectInput(inputURL)
        try await waitUntil { workspace.selectedInputURL == inputURL && !workspace.isInspectingInput }
        try workspace.setRemixManualEditingEnabled(true)
        try workspace.setRemixPan(0.45, for: .vocals)

        await workspace.inspectInput(inputURL)
        try await waitUntil { workspace.selectedInputURL == inputURL && !workspace.isInspectingInput }

        #expect(workspace.isRemixManualEditingEnabled)
        #expect(workspace.manualRemixOverrides.overrides(for: .vocals).pan == 0.45)
    }

    @Test
    func correctionFailureCleanupRetryAndStaleEventsFollowTheCurrentRunContract() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemWorkflowControllerRetryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = try await makeReadyManager(root: root)
        let workflow = RetryAndStaleEventWorkflow()
        let session = StemWorkflowSession()
        let controller = StemWorkflowController(
            session: session,
            modelManager: manager,
            workflow: workflow,
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            seedProvider: { 77 },
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)
        controller.synchronizeModelReadiness()
        let inputURL = root.appending(path: "source.wav")
        await workspace.inspectInput(inputURL)
        try await waitUntil { workspace.selectedInputURL == inputURL && !workspace.isInspectingInput }
        let request = StemModeStartRequest(
            inputURL: inputURL,
            separationSettings: .metaHTDemucsProduction(seed: 77),
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringProfile: .streaming,
            masteringSettings: MasteringProfile.streaming.settings
        )

        try await controller.actions.beginCorrection(request)
        try await waitUntil {
            if case .failed = session.state { return true }
            return false
        }
        let firstRunID = try #require(await workflow.runIDs.first)
        #expect(workspace.selectedInputURL == inputURL)
        #expect(session.artifactStates.isEmpty)
        #expect(await workflow.discardedSessionIDs.contains(firstRunID))

        try await controller.actions.beginCorrection(request)
        try await waitUntil { await workflow.secondRunStarted }
        let secondRunID = try #require(session.runID)
        #expect(secondRunID != firstRunID)
        try await Task.sleep(for: .milliseconds(180))

        #expect(!session.artifactStates.contains { $0.id == "stale-old-run" })
        #expect(!session.artifactStates.contains { $0.id == "contract-out-guitar" })
        #expect(session.logs.contains { $0.message.contains("画面表示の更新を省略しました") })

        try await controller.actions.cancelCorrection()
        #expect(session.state == .idle)
    }

    @Test
    func finalCommitLocksCancellationFromFinalSaveUntilControllerStops() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemWorkflowControllerFinalCommitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = try await makeReadyManager(root: root)
        let workflow = FinalizationSuspendingWorkflow()
        let session = StemWorkflowSession()
        let controller = StemWorkflowController(
            session: session,
            modelManager: manager,
            workflow: workflow,
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            seedProvider: { 77 },
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)
        controller.synchronizeModelReadiness()
        let inputURL = root.appending(path: "source.wav")
        await workspace.inspectInput(inputURL)
        try await waitUntil { workspace.selectedInputURL == inputURL && !workspace.isInspectingInput }

        try await controller.actions.beginCorrection(StemModeStartRequest(
            inputURL: inputURL,
            separationSettings: .metaHTDemucsProduction(seed: 77),
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringProfile: .streaming,
            masteringSettings: MasteringProfile.streaming.settings
        ))
        try await waitUntil { workspace.canRunRemix }
        await workspace.beginRemix()
        try await waitUntil { workspace.canRunMastering }
        await workspace.beginMastering()
        try await waitUntil {
            await workflow.finalizationStarted && workspace.finalCommitLockState == .locked
        }

        #expect(!workspace.canCancelProcessing)
        await workspace.cancelMastering()
        #expect(workspace.finalCommitLockState == .locked)
        controller.shutdown()
    }

    @Test
    func remixAndMasteringFailureCancellationAndRetryKeepTheRequiredBaseline() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemWorkflowControllerStageTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let manager = try await makeReadyManager(root: root)
        let workflow = PostCorrectionStageWorkflow()
        let session = StemWorkflowSession()
        let controller = StemWorkflowController(
            session: session,
            modelManager: manager,
            workflow: workflow,
            inputInspector: AutomaticStemInputInspector(),
            inputDisplayAnalyzer: EmptyStemDisplayAnalyzer(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            seedProvider: { 77 },
            revealInFinder: { _ in }
        )
        let workspace = StemModeWorkspaceModel(session: session, actions: controller.actions)
        controller.attachWorkspaceModel(workspace)
        controller.synchronizeModelReadiness()
        let inputURL = root.appending(path: "source.wav")
        await workspace.inspectInput(inputURL)
        try await waitUntil { workspace.selectedInputURL == inputURL && !workspace.isInspectingInput }
        try await controller.actions.beginCorrection(StemModeStartRequest(
            inputURL: inputURL,
            separationSettings: .metaHTDemucsProduction(seed: 77),
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringProfile: .streaming,
            masteringSettings: MasteringProfile.streaming.settings
        ))
        try await waitUntil { workspace.canRunRemix }
        let runID = try #require(session.runID)

        await workspace.beginRemix()
        try await waitUntil {
            session.state == .readyForRemix(runID: runID) && session.lastError != nil
        }
        #expect(session.artifactStates.filter {
            if case .correctedStem = $0.kind { return true }
            return false
        }.count == 4)
        #expect(session.artifactStates.contains { $0.kind == .correctedPureSum48000 })
        #expect(!session.artifactStates.contains { $0.kind == .remixed48000 })

        await workspace.beginRemix()
        try await waitUntil { await workflow.remixCancellationAttemptStarted }
        await workspace.cancelRemix()
        #expect(session.state == .readyForRemix(runID: runID))
        #expect(session.lastError == nil)

        await workspace.beginRemix()
        try await waitUntil { workspace.canRunMastering }
        let remixedArtifact = try #require(workspace.remixedPreviewArtifact)

        await workspace.beginMastering()
        try await waitUntil {
            session.state == .readyForMastering(runID: runID) && session.lastError != nil
        }
        #expect(workspace.remixedPreviewArtifact == remixedArtifact)
        #expect(workspace.finalPreviewArtifact == nil)

        await workspace.beginMastering()
        try await waitUntil { await workflow.masteringCancellationAttemptStarted }
        await workspace.cancelMastering()
        #expect(session.state == .readyForMastering(runID: runID))
        #expect(session.lastError == nil)
        #expect(workspace.remixedPreviewArtifact == remixedArtifact)
        #expect(workspace.finalPreviewArtifact == nil)
    }

    @Test
    func shutdownRemovesCurrentSessionTemporaryAudio() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
        let sessionDirectory = StemWorkflowService.temporaryRootURL.appending(
            path: sessionID.uuidString.lowercased(),
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: sessionDirectory) }
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        try Data([0x52, 0x49, 0x46, 0x46]).write(
            to: sessionDirectory.appending(path: "incomplete.wav")
        )
        let controller = StemWorkflowController(
            session: session,
            modelManager: StemModelManager(),
            notificationReporter: NoOpStemCompletionNotificationReporter.shared,
            revealInFinder: { _ in }
        )

        controller.shutdown()

        #expect(!FileManager.default.fileExists(atPath: sessionDirectory.path))
    }

    private func completeCorrection(
        in session: StemWorkflowSession,
        sessionID: UUID
    ) throws {
        for step in [
            StemWorkflowStep.validateInput,
            .separate,
            .validateSeparatedStems,
            .evaluateStems,
            .correctStems,
            .validateCorrectedStems,
            .correctedPureSum,
            .validateCorrectedPureSum,
        ] {
            try session.beginStep(runID: sessionID, step: step)
            try session.completeStep(runID: sessionID, step: step)
        }
        let input = StemAudioArtifact(
            id: "input",
            kind: .input44100,
            fileURL: FileManager.default.temporaryDirectory.appending(path: "input.wav"),
            sampleRate: 44_100,
            channelCount: 2,
            frameCount: 32
        )
        try session.updateArtifactState(.init(
            id: input.id,
            runID: sessionID,
            kind: input.kind,
            artifact: input,
            status: .valid
        ))
        for role in try #require(session.runContract).activeRoles {
            let raw = StemAudioArtifact(
                id: "raw-\(role.rawValue)",
                kind: .rawStem(role),
                fileURL: FileManager.default.temporaryDirectory.appending(
                    path: "raw-\(role.rawValue).wav"
                ),
                sampleRate: 44_100,
                channelCount: 2,
                frameCount: 32
            )
            try session.updateArtifactState(.init(
                id: raw.id,
                runID: sessionID,
                kind: raw.kind,
                artifact: raw,
                status: .valid
            ))
            let artifact = StemAudioArtifact(
                id: "corrected-\(role.rawValue)",
                kind: .correctedStem(role),
                fileURL: FileManager.default.temporaryDirectory.appending(
                    path: "corrected-\(role.rawValue).wav"
                ),
                sampleRate: 48_000,
                channelCount: 2,
                frameCount: 32
            )
            try session.updateArtifactState(.init(
                id: artifact.id,
                runID: sessionID,
                kind: artifact.kind,
                artifact: artifact,
                status: .valid
            ))
        }
        let pureSum = StemAudioArtifact(
            id: "corrected-pure-sum",
            kind: .correctedPureSum48000,
            fileURL: FileManager.default.temporaryDirectory.appending(
                path: "corrected-pure-sum-48000.wav"
            ),
            sampleRate: 48_000,
            channelCount: 2,
            frameCount: 32
        )
        try session.updateArtifactState(.init(
            id: pureSum.id,
            runID: sessionID,
            kind: pureSum.kind,
            artifact: pureSum,
            status: .valid
        ))
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () async -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("待機条件が成立しませんでした")
    }

    private func makeReadyManager(root: URL) async throws -> StemModelManager {
        let fixture = try makeStemTestInstallation(rootURL: root)
        let runtime = StemBundledRuntimeValidationReport(
            contract: fixture.installation.snapshot.contract,
            assets: fixture.manifest.bundledRuntimeAssets.map { asset in
                ValidatedStemModelAsset(
                    kind: asset.kind,
                    fileURL: root.appending(path: asset.runtimeRelativePath),
                    byteCount: asset.byteCount,
                    sha256: asset.sha256
                )
            }
        )
        let manager = StemModelManager(inspector: ReadyStemModelInspector(inspection: .init(
            platform: .supportedAppleSilicon,
            manifest: .valid(fixture.manifest),
            installedModel: .ready(fixture.installation),
            bundledRuntime: .ready(runtime)
        )))
        await manager.inspectLocalResources()
        return manager
    }
}

private func makeImmediateCorrectionResult(
    request: StemWorkflowRequest
) -> StemWorkflowCorrectionResult {
    let directory = FileManager.default.temporaryDirectory.appending(
        path: request.runID.uuidString.lowercased(),
        directoryHint: .isDirectory
    )
    let input = makeControllerArtifact(
        id: "input",
        kind: .input44100,
        baseURL: directory
    )
    let rawStems = request.runContract.activeRoles.map { role in
        makeControllerArtifact(id: "raw-\(role.rawValue)", kind: .rawStem(role), baseURL: directory)
    }
    let correctedRemix = makeControllerArtifact(
        id: "corrected-remix",
        kind: .correctedPureSum48000,
        baseURL: directory
    )
    return StemWorkflowCorrectionResult(
        runID: request.runID,
        runContract: request.runContract,
        sessionDirectory: directory,
        sourceDisplayName: request.sourceURL.deletingPathExtension().lastPathComponent,
        sourceFileInfo: try? AudioFileService.fileInfo(for: request.sourceURL),
        separationModelDisplayName: StemProductionModelProfile.identify(request.manifest)?.displayName
            ?? request.manifest.model.name,
        input: StemInputPreparedResult(
            artifact: input,
            channelMatrix: StemInputChannelMatrix(
                source: .stereoIdentity,
                inputLayout: StemInputLayoutIdentity(
                    channelCount: 2,
                    layoutTag: 0,
                    channelBitmap: 0,
                    channelDescriptions: []
                ),
                coefficients: [1, 0, 0, 1]
            ),
            sourceFrameCount: 32
        ),
        canonicalInputEvaluation: makeControllerEvaluation(purpose: .canonicalInput),
        separation: StemSeparationResult(source: input, stems: rawStems),
        separatedStemValidation: StemValidationResult(
            phase: .separatedStems,
            failedChecks: [],
            measurements: []
        ),
        stemEvaluations: [],
        remixArtifacts: StemWorkflowRemixArtifacts(correctedPureSum: correctedRemix),
        rawRemixEvaluation: makeControllerEvaluation(purpose: .rawRemix),
        remixValidation: StemValidationResult(
            phase: .remix,
            failedChecks: [],
            measurements: []
        ),
        correctedRemixEvaluation: makeControllerEvaluation(purpose: .correctedPureSum),
        correctedRemixValidation: StemValidationResult(
            phase: .correctedPureSum,
            failedChecks: [],
            measurements: []
        ),
        correctionSettings: request.correctionSettings,
        analysisMode: request.analysisMode,
        automaticRemixPlan: StemRemixAutomaticPlan(
            settings: StemRemixSettings(),
            gainEvidenceDB: [:],
            panEvidence: [:],
            reverbLossEvidence: [:],
            drumsBassCollision: 0,
            vocalsAccompanimentCollision: 0
        )
    )
}

private func makeControllerArtifact(
    id: String,
    kind: StemArtifactKind,
    baseURL: URL
) -> StemAudioArtifact {
    StemAudioArtifact(
        id: id,
        kind: kind,
        fileURL: baseURL.appending(path: "\(id).wav"),
        sampleRate: kind == .input44100 || {
            if case .rawStem = kind { return true }
            return false
        }() ? 44_100 : 48_000,
        channelCount: 2,
        frameCount: 32
    )
}

private func makeControllerEvaluation(
    purpose: StemAudioEvaluationPurpose
) -> StemAudioEvaluationSnapshot {
    let request = StemAudioEvaluationRequest(
        purpose: purpose,
        includeAudioAnalyzerSnapshot: false,
        includeMasteringAnalysisSnapshot: false
    )
    return StemAudioEvaluationSnapshot(
        request: request,
        completedMeasurements: request.requestedMeasurements,
        audioMetrics: AudioMetricSnapshot(
            duration: 1,
            peakDBFS: -1,
            rmsDBFS: -18,
            crestFactorDB: 9,
            loudnessRangeLU: 4,
            integratedLoudnessLUFS: -18,
            truePeakDBFS: -1,
            stereoWidth: 0.7,
            stereoCorrelation: 0.8,
            stereoCorrelationTimeline: [],
            stereoCorrelationTimelineStatus: .available,
            harshnessScore: 0.2,
            centroidHz: 2_000,
            hf12Ratio: 0.05,
            hf16Ratio: 0.02,
            hf18Ratio: 0.01,
            bandEnergies: [],
            masteringBandEnergies: [],
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: []
        ),
        noiseMeasurements: NoiseMeasurementSnapshot(values: []),
        audioAnalysis: nil,
        masteringAnalysis: nil
    )
}
