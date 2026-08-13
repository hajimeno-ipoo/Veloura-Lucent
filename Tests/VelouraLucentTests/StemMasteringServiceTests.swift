import Foundation
import Testing
@testable import VelouraLucent

private actor RecordingMasteringProcessor: StemMasteringProcessing {
    let outputURL: URL
    private(set) var receivedInputURL: URL?

    init(outputURL: URL) { self.outputURL = outputURL }

    func process(
        inputFile: URL,
        settings: MasteringSettings,
        initialAnalysis: MasteringAnalysis,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot,
        originalReferenceFile: URL,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        receivedInputURL = inputFile
        logHandler("既存マスタリングログ")
        return outputURL
    }
}

private actor RecordingStemFinalEvaluator: StemFinalAudioEvaluating {
    let snapshot: StemAudioEvaluationSnapshot
    private(set) var callCount = 0

    init(snapshot: StemAudioEvaluationSnapshot) {
        self.snapshot = snapshot
    }

    func evaluate(
        signal: AudioSignal,
        request: StemAudioEvaluationRequest
    ) async throws -> StemAudioEvaluationSnapshot {
        callCount += 1
        return snapshot
    }
}

private final class StemMasteringStringRecorder: @unchecked Sendable {
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

struct StemMasteringServiceTests {
    @Test
    func passesValidatedRemixDirectlyToExistingMasteringAndPublishesFinalTemporaryWAV() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = StemTemporaryAudioStore()
        let canonicalSignal = testSignal(sampleRate: 44_100)
        let masteringSignal = testSignal(sampleRate: 48_000)
        let canonicalArtifact = try await store.save(
            signal: canonicalSignal,
            id: "canonical-input",
            kind: .input44100,
            to: root.appending(path: "canonical-input-44100.wav")
        )
        let masteringArtifact = try await store.save(
            signal: masteringSignal,
            id: "stem-remix",
            kind: .remixed48000,
            to: root.appending(path: "stem-remix-48000.wav")
        )
        let processorOutput = PreviewFileStore.temporaryOutputURL(
            baseName: "stem-mastering-service-test-\(UUID().uuidString)",
            suffix: "mas"
        )
        _ = try await store.save(
            signal: masteringSignal,
            id: "processor-output",
            kind: .remixed48000,
            to: processorOutput
        )
        let canonicalEvaluation = try await evaluate(
            canonicalSignal,
            purpose: .canonicalInput
        )
        let masteringEvaluation = try await evaluate(
            masteringSignal,
            purpose: .remix
        )
        let finalEvaluation = try await evaluate(
            masteringSignal,
            purpose: .finalMaster
        )
        let processor = RecordingMasteringProcessor(outputURL: processorOutput)
        let finalEvaluator = RecordingStemFinalEvaluator(snapshot: finalEvaluation)
        let request = StemMasteringRequest(
            runID: UUID(),
            sessionDirectory: root,
            sourceDisplayName: "test-source",
            sourceFileInfo: nil,
            separationModelDisplayName: "HTDemucs",
            canonicalReference: try StemCanonicalMasteringReference(
                artifact: canonicalArtifact,
                evaluation: canonicalEvaluation
            ),
            masteringInput: try StemMasteringInputMaterial(
                artifact: masteringArtifact,
                evaluation: masteringEvaluation
            ),
            reportContext: try reportContext(model: .htdemucs),
            settings: MasteringProfile.streaming.settings
        )
        let logRecorder = StemMasteringStringRecorder()

        let result = try await StemMasteringService(
            masteringProcessor: processor,
            finalEvaluator: finalEvaluator,
            artifactStore: store
        ).process(
            request,
            finalizationProgressHandler: { _ in },
            logHandler: { logRecorder.append($0) }
        )

        #expect(await processor.receivedInputURL == masteringArtifact.fileURL)
        #expect(await finalEvaluator.callCount == 1)
        #expect(result.finalArtifact.kind == .finalMaster)
        #expect(result.finalArtifact.fileURL.lastPathComponent == StemMasteringService.finalMasterFileName)
        #expect(FileManager.default.fileExists(atPath: result.finalArtifact.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: processorOutput.path))
        #expect(!FileManager.default.fileExists(atPath: root.appending(path: "mastering-input-48000.wav").path))
        #expect(result.noiseCheckReport.recommendedActions.allSatisfy { $0.stage == .mastering })
        #expect(result.completionReport.sections.contains { $0.id == "stem-run-contract" })
        #expect(result.completionReport.sections.filter { $0.id.hasPrefix("stem-role-") }.count == 4)
        #expect(logRecorder.values() == [
            "既存マスタリングログ",
            "マスタリング済み音声を読み込みます",
            "Stem Mode最終版を保存します",
            "Stem Mode最終版を検証します",
            "Stem Mode最終版を解析・ノイズ測定します",
            "最終品質レポートを作成します",
            "マスタリングが完了しました",
        ])
    }

    @Test
    func typedMasteringInputRejectsAnythingOtherThanValidatedRemix() async throws {
        let signal = testSignal(sampleRate: 48_000)
        let evaluation = try await evaluate(signal, purpose: .remix)
        let wrong = StemAudioArtifact(
            id: "raw-vocals",
            kind: .rawStem(.vocals),
            fileURL: FileManager.default.temporaryDirectory.appending(path: "raw-vocals.wav"),
            sampleRate: 48_000,
            channelCount: 2,
            frameCount: signal.frameCount
        )

        #expect(throws: StemMasteringError.unexpectedArtifactKind(
            label: "mastering input",
            expected: .remixed48000,
            actual: .rawStem(.vocals)
        )) {
            _ = try StemMasteringInputMaterial(artifact: wrong, evaluation: evaluation)
        }
    }

    private func evaluate(
        _ signal: AudioSignal,
        purpose: StemAudioEvaluationPurpose
    ) async throws -> StemAudioEvaluationSnapshot {
        try await StemAudioEvaluationService.evaluate(
            signal: signal,
            request: StemAudioEvaluationRequest(
                purpose: purpose,
                includeAudioAnalyzerSnapshot: true,
                includeMasteringAnalysisSnapshot: true,
                analysisMode: .cpu
            )
        )
    }

    private func reportContext(
        model: StemSeparationModel
    ) throws -> StemMasteringReportContext {
        let contract = makeStemTestRunContract(model: model)
        let settings = DenoiseStrength.balanced.settings
        let guards = StemCorrectionStage.allCases.map { stage in
            StemCorrectionStageGuardRecord(
                stage: stage,
                action: .run,
                outcome: .completed,
                reason: "テストで完了を確認"
            )
        }
        return try StemMasteringReportContext(
            runContract: contract,
            appliedRemixSettings: StemRemixSettings(),
            roleEvidence: contract.pureSumOrder.map { role in
                StemMasteringRoleReportEvidence(
                    role: role,
                    selectedCorrectionSettings: settings,
                    effectiveCorrectionSettings: settings,
                    stageGuards: guards,
                    usedRawFallback: false,
                    fallbackReason: nil
                )
            }
        )
    }

    private func testSignal(sampleRate: Double) -> AudioSignal {
        let frameCount = 16_384
        let channel = (0..<frameCount).map { index in
            Float(sin(2 * Double.pi * 220 * Double(index) / sampleRate)) * 0.08
        }
        return AudioSignal(channels: [channel, channel], sampleRate: sampleRate)
    }

    private func temporaryDirectory() throws -> URL {
        let URL = FileManager.default.temporaryDirectory
            .appending(path: "StemMasteringServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: URL, withIntermediateDirectories: true)
        return URL
    }
}
