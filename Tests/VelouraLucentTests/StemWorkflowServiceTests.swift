import Foundation
import Testing
@testable import VelouraLucent

private struct WorkflowInputPreparer: StemWorkflowInputPreparing {
    let signal: AudioSignal

    func resolveChannelMatrix(
        inputURL: URL,
        userConfirmedMatrix: StemUserConfirmedMixMatrix?
    ) throws -> StemInputChannelMatrix {
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

private struct QuarterStemSeparator: StemSeparating {
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
        let quarter = AudioSignal(
            channels: sourceSignal.channels.map { channel in channel.map { $0 * 0.25 } },
            sampleRate: sourceSignal.sampleRate
        )
        for role in StemRole.allCases {
            let artifact = try await store.save(
                signal: quarter,
                id: "raw-\(role.rawValue)",
                kind: .rawStem(role),
                to: outputDirectory.appending(path: "raw-\(role.rawValue).wav")
            )
            artifacts.append(artifact)
        }
        for fraction in progressFractions {
            progressHandler(.init(fraction: fraction, detail: "4Stem進捗"))
        }
        return StemSeparationResult(source: inputArtifact, stems: artifacts)
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

    func correct(
        runID: UUID,
        role: StemRole,
        rawSignal: AudioSignal,
        rawEvaluation: StemAudioEvaluationSnapshot,
        settings: CorrectionSettings,
        progressHandler: @escaping @Sendable (StemModeProcessProgressEvent) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StemCorrectionSignalResult {
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

private enum WorkflowServiceTestError: Error {
    case correctionFailed
    case masteringFailed
}

private actor RecordingFailingMasteringService: StemWorkflowMastering {
    private(set) var receivedInputURL: URL?

    func process(
        _ request: StemMasteringRequest,
        finalizationProgressHandler: @escaping @Sendable (StemModeProcessStepStatus) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StemMasteringResult {
        receivedInputURL = request.masteringInput.artifact.fileURL
        throw WorkflowServiceTestError.masteringFailed
    }
}

struct StemWorkflowServiceTests {
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
            "処理用入力音声を準備します",
            "処理用入力音声の準備が完了しました",
            "処理用入力音声を解析・ノイズ測定します",
            "処理用入力音声の解析・ノイズ測定が完了しました",
            "4Stem分離を開始します",
            "4Stem分離が完了しました",
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
            "補正後再ミックスの安全確認を行います",
            "再ミックス安全確認: raw Stemへの差し替えなし",
            "補正済み4Stemを再ミックスします",
            "補正後再ミックスを保存します",
            "補正後再ミックスを解析・ノイズ測定します",
            "補正後再ミックスを検証します",
            "補正後再ミックスの検証が完了しました",
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
            separator: QuarterStemSeparator(sourceSignal: fixture.signal),
            corrector: PassThroughStemCorrector(failingRole: nil),
            remixSafetyGuard: BassRawFallbackSafetyGuard()
        )

        _ = try await service.processCorrection(fixture.request) { event in
            guard case .log(_, _, let message) = event else { return }
            recorder.append(message)
        }

        #expect(recorder.values().contains(
            "再ミックス安全確認: ベースをraw Stemへ戻しました"
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
            separator: QuarterStemSeparator(
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
        #expect(result.correctedRemixEvaluation.purpose == .correctedRemix)
        #expect(result.correctedRemixValidation.canContinue)
        #expect(FileManager.default.fileExists(
            atPath: result.remixArtifacts.correctedRemix.fileURL.path
        ))
    }

    @Test
    func masteringUsesCorrectedRemixDirectlyAndFailureKeepsFourCorrectedStems() async throws {
        let fixture = try await makeCorrectionFixture(failingRole: nil)
        defer { try? StemWorkflowService().discardTemporarySession(runID: fixture.request.runID) }
        let correction = try await fixture.service.processCorrection(fixture.request)
        let recorder = RecordingFailingMasteringService()
        let masteringWorkflow = StemWorkflowService(
            inputPreparer: WorkflowInputPreparer(signal: fixture.signal),
            separator: QuarterStemSeparator(sourceSignal: fixture.signal),
            corrector: PassThroughStemCorrector(failingRole: nil),
            masteringService: recorder
        )

        await #expect(throws: WorkflowServiceTestError.masteringFailed) {
            _ = try await masteringWorkflow.processMastering(.init(
                correction: correction,
                masteringSettings: MasteringProfile.streaming.settings
            ))
        }

        let inputURL = await recorder.receivedInputURL
        #expect(inputURL?.lastPathComponent == "corrected-remix-48000.wav")
        #expect(!FileManager.default.fileExists(
            atPath: correction.sessionDirectory.appending(path: "mastering-input-48000.wav").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: correction.sessionDirectory.appending(path: "corrected-remix-48000.wav").path
        ))
        #expect(correction.stemEvaluations.allSatisfy { evaluation in
            guard let artifact = evaluation.correctedArtifact else { return false }
            return FileManager.default.fileExists(atPath: artifact.fileURL.path)
        })
    }

    private func makeCorrectionFixture(
        failingRole: StemRole?
    ) async throws -> (
        signal: AudioSignal,
        request: StemWorkflowRequest,
        service: StemWorkflowService
    ) {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemWorkflowServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let model = try makeStemTestInstallation(rootURL: root)
        let frameCount = 16_384
        let left = (0..<frameCount).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / 44_100)) * 0.1
        }
        let signal = AudioSignal(channels: [left, left], sampleRate: 44_100)
        let request = StemWorkflowRequest(
            runID: UUID(),
            sourceURL: root.appending(path: "source.wav"),
            userConfirmedMatrix: nil,
            installation: model.installation,
            manifest: model.manifest,
            separationSettings: StemSeparationSettings.metaHTDemucsProduction(seed: 42),
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringSettings: MasteringProfile.streaming.settings,
            analysisMode: .cpu
        )
        return (
            signal,
            request,
            StemWorkflowService(
                inputPreparer: WorkflowInputPreparer(signal: signal),
                separator: QuarterStemSeparator(sourceSignal: signal),
                corrector: PassThroughStemCorrector(failingRole: failingRole)
            )
        )
    }
}
