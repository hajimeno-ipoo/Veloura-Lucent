import Foundation
import Testing
@testable import VelouraLucent

private struct WorkflowInputPreparer: StemWorkflowInputPreparing {
    let signal: AudioSignal

    func resolveChannelMatrix(inputURL: URL) throws -> StemInputChannelMatrix {
        let layout = StemInputLayoutIdentity(
            channelCount: 2,
            layoutTag: 0,
            channelBitmap: 0,
            channelDescriptions: []
        )
        return StemInputChannelMatrix(
            source: .stereoIdentity,
            inputLayout: layout,
            coefficients: [1, 0, 0, 1]
        )
    }

    func prepare(
        inputURL: URL,
        outputURL: URL,
        resolvedChannelMatrix: StemInputChannelMatrix,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> StemInputPreparedResult {
        let artifact = try await StemTemporaryAudioStore().save(
            signal: signal,
            id: "canonical-input",
            kind: .input44100,
            to: outputURL
        )
        progress?(1)
        return StemInputPreparedResult(
            artifact: artifact,
            channelMatrix: resolvedChannelMatrix,
            sourceFrameCount: Int64(signal.frameCount)
        )
    }
}

private struct ContractStemSeparator: StemSeparating {
    let sourceSignal: AudioSignal
    var progressFractions: [Double] = [1]

    func separate(
        inputArtifact: StemAudioArtifact,
        installation: ValidatedStemModelInstallation,
        settings: StemSeparationSettings,
        outputDirectory: URL,
        progressHandler: @escaping @Sendable (StemSeparationProgress) -> Void
    ) async throws -> StemSeparationResult {
        let store = StemTemporaryAudioStore()
        var artifacts: [StemAudioArtifact] = []
        let roles = installation.snapshot.contract.runContract.validationRoles
        let stemGain = 1 / Float(roles.count)
        let quarter = AudioSignal(
            channels: sourceSignal.channels.map { channel in channel.map { $0 * stemGain } },
            sampleRate: sourceSignal.sampleRate
        )
        for role in roles {
            let artifact = try await store.save(
                signal: quarter,
                id: "raw-\(role.rawValue)",
                kind: .rawStem(role),
                to: outputDirectory.appending(path: "raw-\(role.rawValue).wav")
            )
            artifacts.append(artifact)
        }
        for fraction in progressFractions {
            progressHandler(.init(fraction: fraction, detail: "\(roles.count)Stem進捗"))
        }
        return StemSeparationResult(source: inputArtifact, stems: artifacts)
    }
}

private actor WorkflowCorrectedRoleRecorder {
    private var roles: [StemRole] = []

    func record(_ role: StemRole) {
        roles.append(role)
    }

    func values() -> [StemRole] {
        roles
    }
}

private actor WorkflowSeparationProgressRecorder {
    private var fractions: [Double] = []

    func record(_ event: StemWorkflowEvent) async {
        guard case .progress(let progress) = event,
              progress.step == .separate else { return }
        if progress.fraction == 0.1 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        fractions.append(progress.fraction)
    }

    func recordedFractions() -> [Double] {
        fractions
    }
}

private final class WorkflowStringRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    func values() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private struct PassThroughStemCorrector: StemCorrecting {
    let failingRole: StemRole?
    var roleRecorder: WorkflowCorrectedRoleRecorder? = nil

    func correct(
        runID: UUID,
        role: StemRole,
        rawSignal: AudioSignal,
        rawEvaluation: StemAudioEvaluationSnapshot,
        settings: CorrectionSettings,
        progressHandler: @escaping @Sendable (StemModeProcessProgressEvent) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StemCorrectionSignalResult {
        if let roleRecorder {
            await roleRecorder.record(role)
        }
        if role == failingRole { throw WorkflowServiceTestError.correctionFailed }
        let correctedEvaluation = try await StemAudioEvaluationService.evaluate(
            signal: rawSignal,
            request: StemAudioEvaluationRequest(
                purpose: .correctedStem(role: role),
                includeAudioAnalyzerSnapshot: true,
                includeMasteringAnalysisSnapshot: false,
                analysisMode: rawEvaluation.request.analysisMode
            )
        )
        return StemCorrectionSignalResult(
            role: role,
            executionPlan: StemCorrectionExecutionPlan(
                role: role,
                effectiveSettings: settings,
                stages: StemCorrectionStage.allCases.map {
                    StemCorrectionStagePlan(stage: $0, action: .skip, reason: "テスト")
                }
            ),
            stageGuards: StemCorrectionStage.allCases.map {
                StemCorrectionStageGuardRecord(
                    stage: $0,
                    action: .skip,
                    outcome: .notEvaluatedForSkippedStage,
                    reason: "テスト"
                )
            },
            correctedSignal: rawSignal,
            correctedEvaluation: correctedEvaluation
        )
    }
}

private struct BassRawFallbackSafetyGuard: StemRemixSafetyGuarding {
    func protect(
        rawStemsByRole: [StemRole: AudioSignal],
        correctedStemsByRole: [StemRole: AudioSignal]
    ) -> StemRemixSafetyGuardResult {
        var selected = correctedStemsByRole
        selected[.bass] = rawStemsByRole[.bass]
        return StemRemixSafetyGuardResult(
            stemsByRole: selected,
            rawFallbackReasons: [.bass: "テスト用の安全確認理由"]
        )
    }
}

private final class DropGuitarOnSecondSafetyCheck: StemRemixSafetyGuarding, @unchecked Sendable {
    private let lock = NSLock()
    private var invocationCount = 0

    func protect(
        rawStemsByRole: [StemRole: AudioSignal],
        correctedStemsByRole: [StemRole: AudioSignal]
    ) -> StemRemixSafetyGuardResult {
        lock.lock()
        invocationCount += 1
        let shouldDropGuitar = invocationCount == 2
        lock.unlock()

        var selected = correctedStemsByRole
        if shouldDropGuitar {
            selected.removeValue(forKey: .guitar)
        }
        return StemRemixSafetyGuardResult(
            stemsByRole: selected,
            rawFallbackReasons: [:]
        )
    }
}

private enum WorkflowServiceTestError: Error {
    case correctionFailed
    case masteringFailed
}

private actor RecordingFailingMasteringService: StemWorkflowMastering {
    private(set) var receivedInputURL: URL?
    private(set) var foundPreviousFinalArtifact = false
    private(set) var receivedReportContext: StemMasteringReportContext?
    private(set) var callCount = 0

    func process(
        _ request: StemMasteringRequest,
        finalizationProgressHandler: @escaping @Sendable (StemModeProcessStepStatus) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StemMasteringResult {
        callCount += 1
        receivedInputURL = request.masteringInput.artifact.fileURL
        receivedReportContext = request.reportContext
        foundPreviousFinalArtifact = FileManager.default.fileExists(
            atPath: request.sessionDirectory.appending(
                path: StemMasteringService.finalMasterFileName
            ).path
        )
        throw WorkflowServiceTestError.masteringFailed
    }
}

struct StemWorkflowServiceTests {
    @Test
    func correctionRejectsRunContractThatDiffersFromValidatedInstallation() async throws {
        let fixture = try await makeCorrectionFixture(failingRole: nil)
        defer {
            try? FileManager.default.removeItem(
                at: fixture.request.sourceURL.deletingLastPathComponent()
            )
        }
        let request = StemWorkflowRequest(
            runID: fixture.request.runID,
            runContract: makeStemTestRunContract(model: .bsRoformerSW),
            sourceURL: fixture.request.sourceURL,
            installation: fixture.request.installation,
            manifest: fixture.request.manifest,
            separationSettings: fixture.request.separationSettings,
            correctionSettings: fixture.request.correctionSettings,
            masteringSettings: fixture.request.masteringSettings,
            analysisMode: fixture.request.analysisMode
        )

        await #expect(throws: StemWorkflowServiceError.runContractMismatch) {
            _ = try await fixture.service.processCorrection(request)
        }
    }

    @Test
    func correctionDetailedLogContainsEveryWorkflowStageInProcessingOrder() async throws {
        let fixture = try await makeCorrectionFixture(failingRole: nil)
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let recorder = WorkflowStringRecorder()

        _ = try await fixture.service.processCorrection(fixture.request) { event in
            guard case .log(_, _, let message) = event else { return }
            recorder.append(message)
        }

        var expected = [
            "実行契約: HTDemucs / 4Stem / ドラム、ベース、その他、ボーカル",
            "処理用入力音声を準備します",
            "処理用入力音声の準備が完了しました",
            "処理用入力音声を解析・ノイズ測定します",
            "処理用入力音声の解析・ノイズ測定が完了しました",
            "HTDemucsで4Stem分離を開始します",
            "HTDemucsで4Stem分離が完了しました",
            "分離結果を検証します",
            "分離結果の検証が完了しました",
        ]
        for role in [StemRole.drums, .bass, .other, .vocals] {
            expected.append(contentsOf: [
                "\(role.stemModeDisplayTitle)を解析・ノイズ測定します",
                "\(role.stemModeDisplayTitle)の解析・ノイズ測定が完了しました",
                "\(role.stemModeDisplayTitle)の補正後音声を解析・ノイズ測定しました",
                "\(role.stemModeDisplayTitle)の補正結果を保存・検証します",
                "\(role.stemModeDisplayTitle)の補正結果を保存・検証しました",
            ])
        }
        expected.append(contentsOf: [
            "補正済み4Stemの保存を確認しました",
            "分離後4Stemを純粋加算します",
            "raw再ミックスを解析・ノイズ測定します",
            "raw再ミックスを入力2mixと検証します",
            "raw再ミックスの検証が完了しました",
            "補正済み純粋加算の安全確認を行います",
            "純粋加算安全確認: raw Stemへの差し替えなし",
            "補正済み4Stemをgain・pan・reverbなしで純粋加算します",
            "補正済み純粋加算を保存します",
            "補正済み純粋加算を解析・ノイズ測定します",
            "補正済み純粋加算を検証します",
            "補正済み純粋加算の検証が完了しました",
            "補正処理が完了しました",
        ])

        #expect(recorder.values() == expected)
    }

    @Test
    func correctionDetailedLogReportsRawStemFallbackReason() async throws {
        let fixture = try await makeCorrectionFixture(failingRole: nil)
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let recorder = WorkflowStringRecorder()
        let service = StemWorkflowService(
            inputPreparer: WorkflowInputPreparer(signal: fixture.signal),
            separator: ContractStemSeparator(sourceSignal: fixture.signal),
            corrector: PassThroughStemCorrector(failingRole: nil),
            remixSafetyGuard: BassRawFallbackSafetyGuard()
        )

        _ = try await service.processCorrection(fixture.request) { event in
            guard case .log(_, _, let message) = event else { return }
            recorder.append(message)
        }

        #expect(recorder.values().contains(
            "純粋加算安全確認: ベースをraw Stemへ戻しました"
        ))
        #expect(recorder.values().contains("理由: テスト用の安全確認理由"))
    }

    @Test
    func separationProgressEventsRemainInEmissionOrderAcrossAsyncHandler() async throws {
        let fixture = try await makeCorrectionFixture(failingRole: nil)
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let recorder = WorkflowSeparationProgressRecorder()
        let service = StemWorkflowService(
            inputPreparer: WorkflowInputPreparer(signal: fixture.signal),
            separator: ContractStemSeparator(
                sourceSignal: fixture.signal,
                progressFractions: [0.1, 0.2, 1]
            ),
            corrector: PassThroughStemCorrector(failingRole: nil)
        )

        _ = try await service.processCorrection(fixture.request) { event in
            await recorder.record(event)
        }

        #expect(await recorder.recordedFractions() == [0.1, 0.2, 1])
    }

    @Test
    func oneStemCorrectionFailureUsesOnlyThatRawStemAndCompletesCorrectionStage() async throws {
        let fixture = try await makeCorrectionFixture(failingRole: .bass)
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }

        let result = try await fixture.service.processCorrection(fixture.request)

        #expect(result.stemEvaluations.count == 4)
        #expect(result.stemEvaluations.first(where: { $0.role == .bass })?.usedRawFallback == true)
        #expect(result.stemEvaluations.filter(\.usedRawFallback).count == 1)
        #expect(result.stemEvaluations.allSatisfy { evaluation in
            guard let artifact = evaluation.correctedArtifact else { return false }
            return FileManager.default.fileExists(atPath: artifact.fileURL.path)
        })
        #expect(result.correctedRemixEvaluation.purpose == .correctedPureSum)
        #expect(result.correctedRemixValidation.canContinue)
        #expect(FileManager.default.fileExists(
            atPath: result.remixArtifacts.correctedPureSum.fileURL.path
        ))
    }

    @Test
    func bsCorrectionUsesAllSixContractRolesAndWritesSixCorrectedArtifacts() async throws {
        let fixture = try await makeCorrectionFixture(
            model: .bsRoformerSW,
            failingRole: nil
        )
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let recorder = WorkflowCorrectedRoleRecorder()
        let service = StemWorkflowService(
            inputPreparer: WorkflowInputPreparer(signal: fixture.signal),
            separator: ContractStemSeparator(sourceSignal: fixture.signal),
            corrector: PassThroughStemCorrector(failingRole: nil, roleRecorder: recorder)
        )

        let result = try await service.processCorrection(fixture.request)
        let roles = fixture.request.runContract.validationRoles

        #expect(await recorder.values() == roles)
        #expect(result.stemEvaluations.map(\.role) == roles)
        #expect(result.stemEvaluations.count == 6)
        #expect(result.stemEvaluations.allSatisfy { evaluation in
            guard let artifact = evaluation.correctedArtifact else { return false }
            return artifact.fileURL.lastPathComponent == "corrected-\(evaluation.role.rawValue).wav"
                && FileManager.default.fileExists(atPath: artifact.fileURL.path)
        })

        let store = StemTemporaryAudioStore()
        var correctedInputs: [StemMixInput] = []
        for role in roles {
            let artifact = try #require(
                result.stemEvaluations.first(where: { $0.role == role })?.correctedArtifact
            )
            let signal = try await store.load(
                artifact: artifact,
                expectedURL: artifact.fileURL,
                expectedKind: .correctedStem(role)
            )
            correctedInputs.append(StemMixInput(role: role, signal: signal))
        }
        let expected = try StemMixService().pureSum(
            stems: correctedInputs,
            validationRoles: roles,
            order: fixture.request.runContract.pureSumOrder
        ).signal
        let actual = try await store.load(
            artifact: result.remixArtifacts.correctedPureSum,
            expectedURL: result.remixArtifacts.correctedPureSum.fileURL,
            expectedKind: .correctedPureSum48000
        )
        #expect(actual.sampleRate == expected.sampleRate)
        #expect(actual.channels == expected.channels)
    }

    @Test
    func bsWorkflowConnectsGuitarAndPianoToDedicatedAnalysisAndRoleGuards() async throws {
        let fixture = try await makeCorrectionFixture(
            model: .bsRoformerSW,
            failingRole: nil
        )
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let service = StemWorkflowService(
            inputPreparer: WorkflowInputPreparer(signal: fixture.signal),
            separator: ContractStemSeparator(sourceSignal: fixture.signal),
            corrector: StemCorrectionService()
        )
        let recorder = WorkflowStringRecorder()

        let result = try await service.processCorrection(fixture.request) { event in
            guard case .log(_, _, let message) = event else { return }
            recorder.append(message)
        }

        #expect(recorder.values().first == (
            "実行契約: BS-RoFormer-SW / 6Stem / ベース、ドラム、その他、ボーカル、ギター、ピアノ"
        ))

        for role in [StemRole.guitar, .piano] {
            let evaluation = try #require(
                result.stemEvaluations.first(where: { $0.role == role })
            )
            let analysis = try #require(evaluation.roleAnalysisSnapshot)
            #expect(analysis.role == role)
            #expect(analysis.activity != nil)
            #expect(analysis.dedicatedMetrics != nil)
            #expect(!analysis.features.isEmpty)
            #expect(evaluation.stageGuards.map(\.stage) == StemCorrectionStage.allCases)
            #expect(evaluation.stageGuards.flatMap(\.protectedComponents).allSatisfy {
                $0.role == role
            })
            #expect(!analysis.features.contains { feature in
                feature.feature.rawValue.hasPrefix("other")
            })
        }
    }

    @Test
    func bsGuitarCorrectionFailureFallsBackOnlyThatStemAndKeepsSixStemResult() async throws {
        let fixture = try await makeCorrectionFixture(
            model: .bsRoformerSW,
            failingRole: .guitar
        )
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }

        let result = try await fixture.service.processCorrection(fixture.request)
        let guitar = try #require(result.stemEvaluations.first(where: { $0.role == .guitar }))

        #expect(result.stemEvaluations.count == 6)
        #expect(guitar.usedRawFallback)
        #expect(guitar.fallbackReason != nil)
        #expect(result.stemEvaluations.filter(\.usedRawFallback).map(\.role) == [.guitar])
        #expect(result.stemEvaluations.allSatisfy { evaluation in
            guard let artifact = evaluation.correctedArtifact else { return false }
            return FileManager.default.fileExists(atPath: artifact.fileURL.path)
        })
        #expect(FileManager.default.fileExists(
            atPath: result.remixArtifacts.correctedPureSum.fileURL.path
        ))
    }

    @Test
    func bsRemixConsumesAllSixCorrectedStemsAndLogsTheSharedAccompanimentBus() async throws {
        let fixture = try await makeCorrectionFixture(
            model: .bsRoformerSW,
            failingRole: nil
        )
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let correction = try await fixture.service.processCorrection(fixture.request)
        let logs = WorkflowStringRecorder()

        let remix = try await fixture.service.processRemix(
            correction: correction,
            settings: StemRemixSettings()
        ) { event in
            guard case .log(_, _, let message) = event else { return }
            logs.append(message)
        }

        let store = StemTemporaryAudioStore()
        let correctedPureSum = try await store.load(
            artifact: correction.remixArtifacts.correctedPureSum,
            expectedURL: correction.remixArtifacts.correctedPureSum.fileURL,
            expectedKind: .correctedPureSum48000
        )
        let remixed = try await store.load(
            artifact: remix.artifact,
            expectedURL: remix.artifact.fileURL,
            expectedKind: .remixed48000
        )
        let recordedLogs = logs.values()

        #expect(remixed.channels == correctedPureSum.channels)
        #expect(remix.validation.canContinue)
        #expect(recordedLogs.contains { $0.hasPrefix("自動判定根拠（ギター）") })
        #expect(recordedLogs.contains { $0.hasPrefix("自動判定根拠（ピアノ）") })
        #expect(recordedLogs.contains {
            $0.hasPrefix("ボーカル→伴奏（その他／ギター／ピアノ）衝突回避")
        })
    }

    @Test
    func bsRemixFailureKeepsAllSixCorrectedStemsAndThePureSum() async throws {
        let fixture = try await makeCorrectionFixture(
            model: .bsRoformerSW,
            failingRole: nil
        )
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let guardService = DropGuitarOnSecondSafetyCheck()
        let service = StemWorkflowService(
            inputPreparer: WorkflowInputPreparer(signal: fixture.signal),
            separator: ContractStemSeparator(sourceSignal: fixture.signal),
            corrector: PassThroughStemCorrector(failingRole: nil),
            remixSafetyGuard: guardService
        )
        let correction = try await service.processCorrection(fixture.request)
        let remixURL = correction.sessionDirectory.appending(path: "stem-remix-48000.wav")
        let finalURL = correction.sessionDirectory.appending(
            path: StemMasteringService.finalMasterFileName
        )

        await #expect(throws: StemWorkflowServiceError.missingStem(.guitar)) {
            _ = try await service.processRemix(
                correction: correction,
                settings: correction.automaticRemixPlan.settings
            )
        }

        #expect(correction.stemEvaluations.count == 6)
        #expect(correction.stemEvaluations.allSatisfy { evaluation in
            guard let artifact = evaluation.correctedArtifact else { return false }
            return FileManager.default.fileExists(atPath: artifact.fileURL.path)
        })
        #expect(FileManager.default.fileExists(
            atPath: correction.remixArtifacts.correctedPureSum.fileURL.path
        ))
        #expect(!FileManager.default.fileExists(atPath: remixURL.path))
        #expect(!FileManager.default.fileExists(atPath: finalURL.path))
    }

    @Test
    func masteringUsesStemRemixDirectlyAndFailureKeepsCorrectionAndRemixArtifacts() async throws {
        let fixture = try await makeCorrectionFixture(failingRole: nil)
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let correction = try await fixture.service.processCorrection(fixture.request)
        let recorder = RecordingFailingMasteringService()
        let masteringWorkflow = StemWorkflowService(
            inputPreparer: WorkflowInputPreparer(signal: fixture.signal),
            separator: ContractStemSeparator(sourceSignal: fixture.signal),
            corrector: PassThroughStemCorrector(failingRole: nil),
            remixSafetyGuard: BassRawFallbackSafetyGuard(),
            masteringService: recorder
        )
        let remix = try await masteringWorkflow.processRemix(
            correction: correction,
            settings: correction.automaticRemixPlan.settings
        )
        let previousFinalURL = correction.sessionDirectory.appending(
            path: StemMasteringService.finalMasterFileName
        )
        try Data("previous final".utf8).write(to: previousFinalURL)

        await #expect(throws: WorkflowServiceTestError.masteringFailed) {
            _ = try await masteringWorkflow.processMastering(.init(
                remix: remix,
                masteringSettings: MasteringProfile.streaming.settings
            ))
        }

        let inputURL = await recorder.receivedInputURL
        #expect(inputURL?.lastPathComponent == "stem-remix-48000.wav")
        #expect(await !recorder.foundPreviousFinalArtifact)
        let reportContext = try #require(await recorder.receivedReportContext)
        let bassEvidence = try #require(reportContext.roleEvidence.first { $0.role == .bass })
        #expect(bassEvidence.usedRawFallback)
        #expect(bassEvidence.effectiveCorrectionSettings == nil)
        #expect(bassEvidence.fallbackReason == "再ミックス安全確認: テスト用の安全確認理由")
        #expect(bassEvidence.stageGuards.count == StemCorrectionStage.allCases.count)
        #expect(!FileManager.default.fileExists(atPath: previousFinalURL.path))
        #expect(!FileManager.default.fileExists(
            atPath: correction.sessionDirectory.appending(path: "mastering-input-48000.wav").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: correction.sessionDirectory.appending(path: "corrected-pure-sum-48000.wav").path
        ))
        #expect(FileManager.default.fileExists(atPath: remix.artifact.fileURL.path))
        #expect(correction.stemEvaluations.allSatisfy { evaluation in
            guard let artifact = evaluation.correctedArtifact else { return false }
            return FileManager.default.fileExists(atPath: artifact.fileURL.path)
        })
    }

    @Test
    func bsMasteringAcceptsSixRoleContractAndRejectsUnvalidatedRemixBeforeServiceCall() async throws {
        let fixture = try await makeCorrectionFixture(
            model: .bsRoformerSW,
            failingRole: nil
        )
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let correction = try await fixture.service.processCorrection(fixture.request)
        let recorder = RecordingFailingMasteringService()
        let workflow = StemWorkflowService(
            inputPreparer: WorkflowInputPreparer(signal: fixture.signal),
            separator: ContractStemSeparator(sourceSignal: fixture.signal),
            corrector: PassThroughStemCorrector(failingRole: nil),
            masteringService: recorder
        )
        let remix = try await workflow.processRemix(
            correction: correction,
            settings: correction.automaticRemixPlan.settings
        )

        await #expect(throws: WorkflowServiceTestError.masteringFailed) {
            _ = try await workflow.processMastering(.init(
                remix: remix,
                masteringSettings: MasteringProfile.streaming.settings
            ))
        }

        let context = try #require(await recorder.receivedReportContext)
        #expect(context.runContract.separationModel == .bsRoformerSW)
        #expect(context.runContract.stemCount == 6)
        #expect(context.roleEvidence.count == 6)
        #expect(Set(context.roleEvidence.map(\.role)) == Set(StemRole.allCases))
        #expect(context.roleEvidence.allSatisfy {
            $0.effectiveCorrectionSettings != nil
                && $0.stageGuards.count == StemCorrectionStage.allCases.count
                && !$0.usedRawFallback
        })
        #expect(await recorder.callCount == 1)

        let invalidValidation = StemValidationResult(
            phase: .processedRemix,
            failedChecks: [
                StemValidationFailure(
                    check: .finiteSamples,
                    subject: "Stem再ミックス",
                    detail: "テスト用の有限値失敗"
                )
            ],
            measurements: []
        )
        let invalidRemix = StemWorkflowRemixResult(
            correction: remix.correction,
            artifact: remix.artifact,
            evaluation: remix.evaluation,
            validation: invalidValidation,
            appliedSettings: remix.appliedSettings,
            rawFallbackReasons: remix.rawFallbackReasons
        )

        await #expect(throws: StemWorkflowServiceError.remixIncomplete) {
            _ = try await workflow.processMastering(.init(
                remix: invalidRemix,
                masteringSettings: MasteringProfile.streaming.settings
            ))
        }
        #expect(await recorder.callCount == 1)
    }

    @Test
    func remixDisplayProgressAndDetailedLogsFollowTheAudioRenderOrder() async throws {
        let fixture = try await makeCorrectionFixture(failingRole: nil)
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let correction = try await fixture.service.processCorrection(fixture.request)
        let completedSteps = WorkflowStringRecorder()
        let logLines = WorkflowStringRecorder()
        var appliedSettings = correction.automaticRemixPlan.settings
        appliedSettings.setSettings(
            StemRemixRoleSettings(gainDB: 1.3, pan: -0.2, reverbSend: 0.3),
            for: .drums
        )
        appliedSettings.reverbReturnLevel = 0.2
        appliedSettings.reverbDecaySeconds = 1.5

        _ = try await fixture.service.processRemix(
            correction: correction,
            settings: appliedSettings
        ) { event in
            switch event {
            case .displayProgress(let progress) where progress.status == .completed:
                completedSteps.append(progress.step.id)
            case .log(_, _, let message):
                logLines.append(message)
            default:
                break
            }
        }

        #expect(completedSteps.values() == StemModeProcessStep.remixSteps.map(\.id))
        let expectedStageLogs = StemRemixRenderStage.allCases.map(\.stemModeCompletedDetail)
        let expectedRunningLogs = StemRemixRenderStage.allCases.map(\.stemModeRunningDetail)
        let recordedLogs = logLines.values()
        #expect(expectedStageLogs.allSatisfy { recordedLogs.contains($0) })
        #expect(expectedRunningLogs.allSatisfy { recordedLogs.contains($0) })
        #expect(recordedLogs.contains("自動再ミックス設定と適用値を確認します"))
        #expect(recordedLogs.contains { $0.hasPrefix("衝突判定値: ドラム／ベース ") })
        #expect(recordedLogs.contains { $0.hasPrefix("ドラム→ベース衝突回避: 自動値 ") })
        #expect(recordedLogs.contains { $0.hasPrefix("ボーカル→その他衝突回避: 自動値 ") })
        #expect(recordedLogs.contains { $0.hasPrefix("共通reverb: return 自動値 ") })
        let roleTitles = ["ドラム", "ベース", "その他", "ボーカル"]
        #expect(roleTitles.allSatisfy { title in
            recordedLogs.contains { $0.hasPrefix("自動判定根拠（\(title)）") }
                && recordedLogs.contains { $0.hasPrefix("\(title)のgain: 自動値") }
                && recordedLogs.contains { $0.hasPrefix("\(title)のpan: 自動値") }
                && recordedLogs.contains { $0.hasPrefix("\(title)のreverb send: 自動値") }
        })
        #expect(recordedLogs.contains {
            $0.contains("ドラムのgain: 自動値") && $0.contains("適用値 +1.3 dB")
        })
        #expect(recordedLogs.contains {
            $0.contains("ドラムのpan: 自動値") && $0.contains("適用値 L 20%")
        })
        #expect(recordedLogs.contains {
            $0.contains("ドラムのreverb send: 自動値") && $0.contains("適用値 30%")
        })
        #expect(recordedLogs.contains {
            $0.contains("共通reverb: return 自動値")
                && $0.contains("適用値 20%")
                && $0.contains("適用値 1.50 秒")
        })
        #expect(recordedLogs.contains("Stem再ミックスを保存します"))
        #expect(recordedLogs.contains("Stem再ミックスを解析・ノイズ測定します"))
        #expect(recordedLogs.contains("再ミックスの構造・有限値・ピークを検証します"))
        #expect(logLines.values().contains(
            "再ミックスの構造・有限値・ピーク検証が完了しました"
        ))
    }

    private func makeCorrectionFixture(
        model: StemSeparationModel = .htdemucs,
        failingRole: StemRole?
    ) async throws -> (
        signal: AudioSignal,
        request: StemWorkflowRequest,
        service: StemWorkflowService
    ) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemWorkflowServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let modelFixture = try makeStemTestInstallation(rootURL: root, model: model)
        let frameCount = 16_384
        let left = (0..<frameCount).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / 44_100)) * 0.1
        }
        let signal = AudioSignal(channels: [left, left], sampleRate: 44_100)
        let request = StemWorkflowRequest(
            runID: UUID(),
            runContract: modelFixture.installation.snapshot.contract.runContract,
            sourceURL: root.appending(path: "source.wav"),
            installation: modelFixture.installation,
            manifest: modelFixture.manifest,
            separationSettings: model == .htdemucs
                ? StemSeparationSettings.metaHTDemucsProduction(seed: 42)
                : .bsRoformerSWProduction,
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringSettings: MasteringProfile.streaming.settings,
            analysisMode: .cpu
        )
        return (
            signal,
            request,
            StemWorkflowService(
                inputPreparer: WorkflowInputPreparer(signal: signal),
                separator: ContractStemSeparator(sourceSignal: signal),
                corrector: PassThroughStemCorrector(
                    failingRole: failingRole,
                    roleRecorder: nil
                )
            )
        )
    }
}
