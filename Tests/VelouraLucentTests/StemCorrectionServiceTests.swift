import Foundation
import Testing
@testable import VelouraLucent

struct StemCorrectionServiceTests {
    @Test("raw Stem以外の評価purposeを拒否する")
    func rejectsNonRawEvaluationPurpose() async {
        let signal = makeCorrectionSignal()
        let service = makeCorrectionService()

        await #expect(throws: StemCorrectionError.invalidEvaluationPurpose(role: .vocals)) {
            _ = try await service.correct(
                runID: UUID(),
                role: .vocals,
                rawSignal: signal,
                rawEvaluation: makeCorrectionEvaluation(
                    purpose: .correctedStem(role: .vocals)
                ),
                settings: DenoiseStrength.balanced.settings,
                progressHandler: { _ in },
                logHandler: { _ in }
            )
        }
    }

    @Test("Stem補正に必要な共通解析がない場合は補正を開始しない")
    func rejectsMissingAudioAnalysis() async {
        let signal = makeCorrectionSignal()
        let service = makeCorrectionService()
        let request = StemAudioEvaluationRequest(
            purpose: .rawStem(role: .bass),
            includeAudioAnalyzerSnapshot: false,
            includeMasteringAnalysisSnapshot: false
        )
        let evaluation = StemAudioEvaluationSnapshot(
            request: request,
            completedMeasurements: request.requestedMeasurements,
            audioMetrics: makeCorrectionMetrics(),
            noiseMeasurements: makeCorrectionNoise(),
            audioAnalysis: nil,
            masteringAnalysis: nil
        )

        let error = StemCorrectionError.missingAudioAnalysis(role: .bass)
        #expect(error.errorDescription == "bassのStem補正に必要な共通解析結果がありません。")

        await #expect(throws: error) {
            _ = try await service.correct(
                runID: UUID(),
                role: .bass,
                rawSignal: signal,
                rawEvaluation: evaluation,
                settings: DenoiseStrength.balanced.settings,
                progressHandler: { _ in },
                logHandler: { _ in }
            )
        }
    }

    @Test(
        "既存4Stemは既存資産由来の全工程を一度の一本道として通す",
        arguments: StemProductionModelProfile.profile(for: .htdemucs).sourceOrder
    )
    func returnsOneCorrectedSignalWithCompleteStageEvidence(role: StemRole) async throws {
        let signal = makeCorrectionSignal()
        let result = try await makeCorrectionService().correct(
            runID: UUID(),
            role: role,
            rawSignal: signal,
            rawEvaluation: makeCorrectionEvaluation(purpose: .rawStem(role: role)),
            settings: DenoiseStrength.balanced.settings,
            progressHandler: { _ in },
            logHandler: { _ in }
        )

        #expect(result.role == role)
        #expect(result.executionPlan.role == role)
        #expect(result.executionPlan.stages.map(\.stage) == StemCorrectionStage.allCases)
        #expect(result.stageGuards.map(\.stage) == StemCorrectionStage.allCases)
        let roleAnalysis = try #require(result.roleAnalysisSnapshot)
        #expect(roleAnalysis.role == role)
        #expect(!roleAnalysis.features.isEmpty)
        #expect(result.correctedSignal.sampleRate == 48_000)
        #expect(result.correctedSignal.channels.count == signal.channels.count)
        #expect(result.correctedSignal.frameCount == signal.frameCount)
        #expect(result.correctedSignal.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        #expect(result.correctedEvaluation.purpose == .correctedStem(role: role))

        for record in result.stageGuards {
            let plannedAction = try #require(
                result.executionPlan.decision(for: record.stage)?.action
            )
            #expect(record.action == plannedAction)
            #expect(!record.reason.isEmpty)
            #expect(!record.reason.contains("通常モード"))
            switch (record.action, record.outcome) {
            case (.skip, .notEvaluatedForSkippedStage),
                 (.run, .completed),
                 (.run, .unchanged),
                 (.run, .weakenedByStemProtection),
                 (.run, .restoredStageInputByStemProtection),
                 (.run, .restoredStageInputAfterDSPFailure),
                 (.run, .restoredStageInputAfterGuardFailure),
                 (.light, .completed),
                 (.light, .unchanged),
                 (.light, .weakenedByStemProtection),
                 (.light, .restoredStageInputByStemProtection),
                 (.light, .restoredStageInputAfterDSPFailure),
                 (.light, .restoredStageInputAfterGuardFailure):
                break
            default:
                Issue.record("一本道の工程actionと結果が一致しません: \(record)")
            }
        }
    }

    @Test("Stem補正ログは役割ごとに共通の補正判定とDSPを短い行で表示する")
    func logsGroupedHumanReadableRouteDSPAndGuardLines() async throws {
        let recorder = StemCorrectionLogRecorder()
        _ = try await makeCorrectionService().correct(
            runID: UUID(),
            role: .drums,
            rawSignal: makeCorrectionSignal(),
            rawEvaluation: makeCorrectionEvaluation(purpose: .rawStem(role: .drums)),
            settings: DenoiseStrength.balanced.settings,
            progressHandler: { _ in },
            logHandler: { recorder.append($0) }
        )

        let humanReadableLines = recorder.messages.filter {
            ProcessingProgressEvent.decode($0) == nil
        }
        let routeLines = humanReadableLines.filter { $0.hasPrefix("ルート/補正: ") }
        let guardLines = humanReadableLines.filter { $0.hasPrefix("Stem役割保護: ") }

        #expect(humanReadableLines.first == "【ドラム】")
        #expect(humanReadableLines.contains("役割別解析を完了しました"))
        #expect(humanReadableLines.contains("役割別保護: アタック・トランジェント・シンバルの余韻"))
        #expect(routeLines.count == 10)
        #expect(routeLines.contains { $0.contains("ノイズ除去 = 実行") })
        #expect(routeLines.contains {
            $0.contains("補正後高域保持") && $0.contains("既存の補正後高域保持を使用")
        })
        #expect(routeLines.contains {
            $0.contains("補正後mud guard") && $0.contains("既存の処理前後mud増加guardを使用")
        })
        #expect(humanReadableLines.contains("ノイズを除去します"))
        #expect(guardLines.count == StemCorrectionStage.allCases.count)
        #expect(!humanReadableLines.contains { $0.contains("通常モード") })
        #expect(!humanReadableLines.contains { $0.contains("今回のStem自身との相対比較") })
        #expect(!humanReadableLines.contains { line in
            StemCorrectionStage.allCases.contains { line.contains($0.rawValue) }
        })
        #expect(!humanReadableLines.contains { line in
            StemRoleProtectedComponent.allCases.contains { line.contains($0.rawValue) }
        })
    }

    @Test("省略表示はrouteが処理不要と判断した工程だけに使用する")
    func onlyRouteSkipUsesSkippedProgressState() async throws {
        let runID = UUID()
        let recorder = StemCorrectionProgressRecorder()
        let service = StemCorrectionService(
            evaluator: RecordingCorrectionEvaluator(recorder: CorrectionEvaluationRecorder()),
            roleAnalyzer: CorrectionRoleAnalyzerFake(),
            roleProtector: FailingStemRoleProtector()
        )
        let result = try await service.correct(
            runID: runID,
            role: .drums,
            rawSignal: makeCorrectionSignal(),
            rawEvaluation: makeCorrectionEvaluation(purpose: .rawStem(role: .drums)),
            settings: DenoiseStrength.strong.settings,
            progressHandler: { recorder.append($0) },
            logHandler: { _ in }
        )

        for stage in StemCorrectionStage.allCases {
            let step = StemModeProcessStep.roleCorrection(.drums, stage: stage)
            let terminalEvent = try #require(
                recorder.events.last {
                    $0.step == step && $0.status != .running
                }
            )
            let plannedAction = try #require(
                result.executionPlan.decision(for: stage)?.action
            )
            #expect(terminalEvent.status == (plannedAction == .skip ? .skipped : .completed))
        }
        #expect(result.stageGuards.contains {
            $0.outcome == .restoredStageInputAfterGuardFailure
        })
    }

    @Test("補正結果の解析はcorrected Stem purposeで一度だけ要求する")
    func evaluatesChangedOutputAsCorrectedStem() async throws {
        let recorder = CorrectionEvaluationRecorder()
        let service = StemCorrectionService(
            evaluator: RecordingCorrectionEvaluator(recorder: recorder),
            roleAnalyzer: CorrectionRoleAnalyzerFake()
        )
        let result = try await service.correct(
            runID: UUID(),
            role: .vocals,
            rawSignal: makeCorrectionSignal(),
            rawEvaluation: makeCorrectionEvaluation(
                purpose: .rawStem(role: .vocals),
                request: StemAudioEvaluationRequest(
                    purpose: .rawStem(role: .vocals),
                    includeAudioAnalyzerSnapshot: true,
                    includeMasteringAnalysisSnapshot: false,
                    analysisMode: .cpu
                )
            ),
            settings: DenoiseStrength.strong.settings,
            progressHandler: { _ in },
            logHandler: { _ in }
        )

        #expect(result.correctedEvaluation.purpose == .correctedStem(role: .vocals))
        let requests = await recorder.requests
        #expect(requests.count <= 1)
        #expect(requests.allSatisfy { $0.purpose == .correctedStem(role: .vocals) })
        #expect(requests.allSatisfy { $0.analysisMode == .cpu })
    }

    @Test("役割別raw解析が失敗した場合は補正DSPへ進まず失敗を返す")
    func propagatesRoleAnalysisFailure() async {
        let service = StemCorrectionService(
            evaluator: RecordingCorrectionEvaluator(recorder: CorrectionEvaluationRecorder()),
            roleAnalyzer: FailingCorrectionRoleAnalyzer()
        )

        await #expect(throws: StemRoleAnalysisError.unableToProduceFeature(.vocalsVoicedHarmonicStrength)) {
            _ = try await service.correct(
                runID: UUID(),
                role: .vocals,
                rawSignal: makeCorrectionSignal(),
                rawEvaluation: makeCorrectionEvaluation(purpose: .rawStem(role: .vocals)),
                settings: DenoiseStrength.balanced.settings,
                progressHandler: { _ in },
                logHandler: { _ in }
            )
        }
    }
}

private final class StemCorrectionLogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var messages: [String] {
        lock.withLock { storage }
    }

    func append(_ message: String) {
        lock.withLock {
            storage.append(message)
        }
    }
}

private final class StemCorrectionProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StemModeProcessProgressEvent] = []

    var events: [StemModeProcessProgressEvent] {
        lock.withLock { storage }
    }

    func append(_ event: StemModeProcessProgressEvent) {
        lock.withLock {
            storage.append(event)
        }
    }
}

private actor CorrectionEvaluationRecorder {
    private(set) var requests: [StemAudioEvaluationRequest] = []

    func append(_ request: StemAudioEvaluationRequest) {
        requests.append(request)
    }
}

private struct RecordingCorrectionEvaluator: StemCorrectionAudioEvaluating {
    let recorder: CorrectionEvaluationRecorder

    func evaluate(
        signal: AudioSignal,
        request: StemAudioEvaluationRequest
    ) async throws -> StemAudioEvaluationSnapshot {
        await recorder.append(request)
        return makeCorrectionEvaluation(purpose: request.purpose, request: request)
    }
}

private struct CorrectionRoleAnalyzerFake: StemRoleAnalyzing {
    func analyzeWithProtection(
        role: StemRole,
        processingSignal48000: AudioSignal
    ) throws -> StemRoleAnalysisResult {
        try StemRoleAnalysisService().analyzeWithProtection(
            role: role,
            processingSignal48000: processingSignal48000
        )
    }
}

private struct FailingCorrectionRoleAnalyzer: StemRoleAnalyzing {
    func analyzeWithProtection(
        role: StemRole,
        processingSignal48000: AudioSignal
    ) throws -> StemRoleAnalysisResult {
        throw StemRoleAnalysisError.unableToProduceFeature(.vocalsVoicedHarmonicStrength)
    }
}

private struct FailingStemRoleProtector: StemRoleProtectionGuarding {
    func protect(
        role: StemRole,
        stageInput: AudioSignal,
        proposedOutput: AudioSignal,
        rawProfile: StemRoleProtectionProfile,
        inputProfile: StemRoleProtectionProfile
    ) throws -> StemRoleProtectionGuardResult {
        throw StemRoleProtectionGuardError.profileMismatch
    }
}

private func makeCorrectionService() -> StemCorrectionService {
    StemCorrectionService(
        evaluator: RecordingCorrectionEvaluator(recorder: CorrectionEvaluationRecorder()),
        roleAnalyzer: CorrectionRoleAnalyzerFake()
    )
}

private func makeCorrectionSignal(frameCount: Int = 4_096) -> AudioSignal {
    let sampleRate = 48_000.0
    let left = (0..<frameCount).map { index -> Float in
        let time = Double(index) / sampleRate
        return Float(
            0.22 * sin(2 * Double.pi * 220 * time)
                + 0.12 * sin(2 * Double.pi * 2_400 * time)
                + 0.035 * sin(2 * Double.pi * 9_137 * time)
        )
    }
    let right = left.enumerated().map { index, sample in
        sample * 0.96
            + Float(0.01 * sin(2 * Double.pi * 1_131 * Double(index) / sampleRate))
    }
    return AudioSignal(channels: [left, right], sampleRate: sampleRate)
}

private func makeCorrectionEvaluation(
    purpose: StemAudioEvaluationPurpose,
    request suppliedRequest: StemAudioEvaluationRequest? = nil
) -> StemAudioEvaluationSnapshot {
    let request = suppliedRequest ?? StemAudioEvaluationRequest(
        purpose: purpose,
        includeAudioAnalyzerSnapshot: true,
        includeMasteringAnalysisSnapshot: false
    )
    return StemAudioEvaluationSnapshot(
        request: request,
        completedMeasurements: request.requestedMeasurements,
        audioMetrics: makeCorrectionMetrics(),
        noiseMeasurements: makeCorrectionNoise(),
        audioAnalysis: makeCorrectionAnalysis(),
        masteringAnalysis: nil
    )
}

private func makeCorrectionMetrics() -> AudioMetricSnapshot {
    AudioMetricSnapshot(
        duration: 0.1,
        peakDBFS: -3,
        rmsDBFS: -15,
        crestFactorDB: 12,
        loudnessRangeLU: 4,
        integratedLoudnessLUFS: -18,
        truePeakDBFS: -3,
        stereoWidth: 0.6,
        stereoCorrelation: 0.8,
        stereoCorrelationTimeline: [],
        stereoCorrelationTimelineStatus: .available,
        harshnessScore: 0.2,
        centroidHz: 2_400,
        hf12Ratio: 0.04,
        hf16Ratio: 0.02,
        hf18Ratio: 0.01,
        bandEnergies: [],
        masteringBandEnergies: [],
        shortTermLoudness: [],
        dynamics: [],
        averageSpectrum: []
    )
}

private func makeCorrectionNoise() -> NoiseMeasurementSnapshot {
    NoiseMeasurementSnapshot(
        values: InternalAudioJudgementPolicy.noiseSeverityLimits.map { limit in
            NoiseMeasurementValue(
                id: limit.id,
                label: limit.id,
                comparableLevelDB: -70,
                measuredLevelDB: -70,
                measurementDescription: limit.id
            )
        }
    )
}

private func makeCorrectionAnalysis() -> AnalysisData {
    AnalysisData(
        cutoffFrequency: 18_000,
        dominantHarmonics: [HarmonicPeak(frequency: 220, magnitude: 0.5)],
        harmonicConfidence: 0.8,
        hasShimmer: false,
        shimmerRatio: 0.03,
        brightnessRatio: 0.2,
        transientAmount: 0.3,
        noiseAmount: 0.4,
        rolloffDepth: 0.1,
        airBandEnergyRatio: 0.04,
        artifactBandRatio: 0.02,
        denoiseEffectMetrics: nil
    )
}
