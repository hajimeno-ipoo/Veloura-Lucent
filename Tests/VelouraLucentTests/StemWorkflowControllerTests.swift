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
        await eventHandler(.artifactCommitted(result.input.artifact))
        for role in StemRole.allCases {
            let artifact = makeControllerArtifact(
                id: "corrected-\(role.rawValue)",
                kind: .correctedStem(role),
                baseURL: result.sessionDirectory
            )
            await eventHandler(.artifactCommitted(artifact))
        }
        await eventHandler(.artifactCommitted(result.remixArtifacts.correctedRemix))
        return result
    }

    func processMastering(
        _ request: StemWorkflowMasteringRequest,
        eventHandler: @escaping @Sendable (StemWorkflowEvent) async -> Void
    ) async throws -> StemWorkflowResult {
        throw CancellationError()
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
    func correctionCompletionConnectsCorrectedRemixToPreviewAndAnalysis() async throws {
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
            confirmedMixMatrix: nil,
            separationSettings: .metaHTDemucsProduction(seed: 77),
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringProfile: .streaming,
            masteringSettings: MasteringProfile.streaming.settings
        ))
        try await waitUntil {
            if case .readyForMastering = session.state { return true }
            return false
        }

        let correctedRemix = try #require(workspace.correctedRemixPreviewArtifact)
        #expect(correctedRemix.kind == .correctedRemix48000)
        #expect(workspace.previewController.cardState(for: .corrected).sourceURL == correctedRemix.fileURL)
        #expect(workspace.previewController.comparisonPair == .inputVsCorrected)
        #expect(workspace.remixAnalysisPresentation != nil)
        #expect(session.progress(for: .correctedRemix).status == .completed)
        #expect(session.progress(for: .validateCorrectedRemix).status == .completed)
        #expect(session.displayProgress(for: .inputPreparation).status == .completed)
        #expect(!session.logs.contains { $0.message.contains("__veloura_progress__") })
        #expect(session.recentActivityEvents.filter { $0.domain == .correction }.map(\.title) == [
            "補正処理が完了しました",
            "補正後再ミックスを解析しました",
        ])

        try await controller.actions.beginMastering(StemModeMasteringRequest(
            masteringSettings: MasteringProfile.streaming.settings
        ))
        try await waitUntil { session.lastError != nil }

        let currentRunID = try #require(session.runID)
        #expect(session.state == .readyForMastering(runID: currentRunID))
        #expect(workspace.correctedRemixPreviewArtifact == correctedRemix)
        #expect(workspace.finalPreviewArtifact == nil)
        #expect(workspace.previewController.cardState(for: .corrected).sourceURL == correctedRemix.fileURL)
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
            confirmedMixMatrix: nil,
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
        try session.startRun(runID: sessionID)
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

    @Test
    func shutdownRemovesCurrentSessionTemporaryAudio() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)
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
            .correctedRemix,
            .validateCorrectedRemix,
        ] {
            try session.beginStep(runID: sessionID, step: step)
            try session.completeStep(runID: sessionID, step: step)
        }
        for role in StemRole.allCases {
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
        let remix = StemAudioArtifact(
            id: "corrected-remix",
            kind: .correctedRemix48000,
            fileURL: FileManager.default.temporaryDirectory.appending(
                path: "corrected-remix-48000.wav"
            ),
            sampleRate: 48_000,
            channelCount: 2,
            frameCount: 32
        )
        try session.updateArtifactState(.init(
            id: remix.id,
            runID: sessionID,
            kind: remix.kind,
            artifact: remix,
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
    let rawStems = StemRole.allCases.map { role in
        makeControllerArtifact(id: "raw-\(role.rawValue)", kind: .rawStem(role), baseURL: directory)
    }
    let correctedRemix = makeControllerArtifact(
        id: "corrected-remix",
        kind: .correctedRemix48000,
        baseURL: directory
    )
    return StemWorkflowCorrectionResult(
        runID: request.runID,
        sessionDirectory: directory,
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
        remixArtifacts: StemWorkflowRemixArtifacts(correctedRemix: correctedRemix),
        rawRemixEvaluation: makeControllerEvaluation(purpose: .rawRemix),
        remixValidation: StemValidationResult(
            phase: .remix,
            failedChecks: [],
            measurements: []
        ),
        correctedRemixEvaluation: makeControllerEvaluation(purpose: .correctedRemix),
        correctedRemixValidation: StemValidationResult(
            phase: .correctedRemix,
            failedChecks: [],
            measurements: []
        ),
        correctionSettings: request.correctionSettings,
        analysisMode: request.analysisMode
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
