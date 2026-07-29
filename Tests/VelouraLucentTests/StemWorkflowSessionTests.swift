import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct StemWorkflowSessionTests {
    @Test
    func inputDisplayLogsAppearBeforeRunAndFollowNormalModeResetAtCorrectionStart() throws {
        let session = StemWorkflowSession()
        session.recordInputSelection(
            URL: URL(fileURLWithPath: "/tmp/input.wav"),
            fileInfo: nil
        )
        session.recordInputDisplayAnalysisLog("表示解析/計測: ファイル読み込み: 0.01秒")
        session.recordInputDisplayAnalysisLog("表示解析/計測: 比較指標: 0.02秒")

        #expect(session.runID == nil)
        #expect(session.correctionLogLines == [
            "表示解析/計測: ファイル読み込み: 0.01秒",
            "表示解析/計測: 比較指標: 0.02秒",
        ])

        let sessionID = UUID()
        try session.startRun(runID: sessionID)
        #expect(session.correctionLogLines.isEmpty)

        session.recordInputDisplayAnalysisLog("表示解析/計測: ノイズ測定: 0.03秒")
        #expect(session.correctionLogLines == ["表示解析/計測: ノイズ測定: 0.03秒"])
        #expect(session.logs.last?.runID == sessionID)
        #expect(session.logs.last?.step == .validateInput)
    }

    @Test
    func selectingAnotherInputClearsPreviousInputDisplayLogs() {
        let session = StemWorkflowSession()
        session.recordInputSelection(
            URL: URL(fileURLWithPath: "/tmp/first.wav"),
            fileInfo: nil
        )
        session.recordInputDisplayAnalysisLog("旧入力ログ")

        session.recordInputSelection(
            URL: URL(fileURLWithPath: "/tmp/second.wav"),
            fileInfo: nil
        )

        #expect(session.correctionLogLines.isEmpty)
    }

    @Test
    func correctionCompletionUsesFourValidatedStemsAndCorrectedPureSum() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)

        for role in StemRole.allCases {
            let value = artifact(id: "corrected-\(role.rawValue)", kind: .correctedStem(role))
            try session.updateArtifactState(.init(
                id: value.id,
                runID: sessionID,
                kind: value.kind,
                artifact: value,
                status: .valid
            ))
        }
        let remix = artifact(id: "corrected-remix", kind: .correctedPureSum48000)
        try session.updateArtifactState(.init(
            id: remix.id,
            runID: sessionID,
            kind: remix.kind,
            artifact: remix,
            status: .valid
        ))

        try session.completeCorrection(runID: sessionID)

        #expect(session.state == .readyForRemix(runID: sessionID))
        let correctionSteps: [StemWorkflowStep] = [
            .validateInput, .separate, .validateSeparatedStems,
            .evaluateStems, .correctStems, .validateCorrectedStems,
            .correctedPureSum, .validateCorrectedPureSum,
        ]
        #expect(correctionSteps.allSatisfy {
            session.progress(for: $0).status == .completed
                && session.progress(for: $0).fraction == 1
        })
    }

    @Test
    func processingStateRemainsActiveBetweenDetailedStepsUntilTheDomainFinishes() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()

        #expect(!session.isCorrectionProcessing)
        #expect(!session.isMasteringProcessing)

        try session.startRun(runID: sessionID)
        #expect(session.isCorrectionProcessing)

        try session.applyDisplayProgress(.init(
            runID: sessionID,
            step: .inputPreparation,
            status: .running,
            fraction: 0
        ))
        try session.applyDisplayProgress(.init(
            runID: sessionID,
            step: .inputPreparation,
            status: .completed,
            fraction: 1
        ))

        #expect(!session.displayProgress.contains { $0.status == .running })
        #expect(session.isCorrectionProcessing)

        try completeCorrection(in: session, sessionID: sessionID)
        try session.completeCorrection(runID: sessionID)
        #expect(!session.isCorrectionProcessing)

        try completeRemix(in: session, sessionID: sessionID)
        try session.startMastering(runID: sessionID)
        #expect(!session.displayProgress.contains { $0.status == .running })
        #expect(session.isMasteringProcessing)

        try session.restoreMasteringReadyAfterCancellation(runID: sessionID)
        #expect(!session.isMasteringProcessing)
    }

    @Test
    func processingStateStopsAfterCorrectionFailure() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)

        #expect(session.isCorrectionProcessing)
        try session.fail(
            runID: sessionID,
            step: .separate,
            message: "分離に失敗しました"
        )

        #expect(!session.isCorrectionProcessing)
    }

    @Test
    func masteringCannotStartUntilRemixArtifactIsComplete() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)

        #expect(throws: StemWorkflowSessionError.masteringRequiresRemixCompletion) {
            try session.startMastering(runID: sessionID)
        }

        try completeCorrection(in: session, sessionID: sessionID)
        try session.completeCorrection(runID: sessionID)
        #expect(session.state == .readyForRemix(runID: sessionID))
        #expect(throws: StemWorkflowSessionError.masteringRequiresRemixCompletion) {
            try session.startMastering(runID: sessionID)
        }
        try completeRemix(in: session, sessionID: sessionID)
        try session.startMastering(runID: sessionID)
        #expect(session.state == .ready)
    }

    @Test
    func masteringCancellationKeepsCorrectionArtifactsAndRemovesOnlyFinalPresentation() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)
        try completeCorrection(in: session, sessionID: sessionID)
        try session.completeCorrection(runID: sessionID)
        try completeRemix(in: session, sessionID: sessionID)
        try session.startMastering(runID: sessionID)

        let final = artifact(id: "final", kind: .finalMaster)
        try session.updateArtifactState(.init(
            id: final.id,
            runID: sessionID,
            kind: final.kind,
            artifact: final,
            status: .valid
        ))
        try session.restoreMasteringReadyAfterCancellation(runID: sessionID)

        #expect(session.state == .readyForMastering(runID: sessionID))
        #expect(session.artifactStates.filter { state in
            if case .correctedStem = state.kind { return true }
            return false
        }.count == 4)
        #expect(session.artifactStates.contains { $0.kind == .correctedPureSum48000 })
        #expect(!session.artifactStates.contains { $0.kind == .finalMaster })
    }

    @Test
    func masteringCanRestartAfterCompletionAndKeepsTheValidatedRemix() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)
        try completeCorrection(in: session, sessionID: sessionID)
        try session.completeCorrection(runID: sessionID)
        try completeRemix(in: session, sessionID: sessionID)
        try session.startMastering(runID: sessionID)

        let final = artifact(id: "rerun-final", kind: .finalMaster)
        try session.updateArtifactState(.init(
            id: final.id,
            runID: sessionID,
            kind: final.kind,
            artifact: final,
            status: .valid
        ))
        try session.completeRun(runID: sessionID)

        try session.startMastering(runID: sessionID)

        #expect(session.state == .ready)
        #expect(session.isMasteringProcessing)
        #expect(session.artifactStates.contains { $0.kind == .remixed48000 })
        #expect(!session.artifactStates.contains { $0.kind == .finalMaster })
        #expect(session.masteringDisplayProgress.allSatisfy { $0.status == .pending })
    }

    @Test
    func remixSettingChangeInvalidatesRemixAndFinalButKeepsCorrectionBaseline() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)
        try completeCorrection(in: session, sessionID: sessionID)
        try session.completeCorrection(runID: sessionID)
        try completeRemix(in: session, sessionID: sessionID)

        let final = artifact(id: "final", kind: .finalMaster)
        try session.updateArtifactState(.init(
            id: final.id,
            runID: sessionID,
            kind: final.kind,
            artifact: final,
            status: .valid
        ))
        try session.invalidateRemix(runID: sessionID)

        #expect(session.state == .readyForRemix(runID: sessionID))
        #expect(!session.artifactStates.contains { $0.kind == .remixed48000 })
        #expect(!session.artifactStates.contains { $0.kind == .finalMaster })
        #expect(session.artifactStates.contains { $0.kind == .correctedPureSum48000 })
        #expect(session.artifactStates.filter {
            if case .correctedStem = $0.kind { return true }
            return false
        }.count == 4)
    }

    @Test
    func correctionCancellationResetsOnlyStemSessionPresentation() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)
        try session.beginStep(runID: sessionID, step: .validateInput)
        session.resetAfterCorrectionCancellation(runID: sessionID)

        #expect(session.state == .idle)
        #expect(session.runID == nil)
        #expect(session.artifactStates.isEmpty)
        #expect(session.stepProgress.allSatisfy { $0.status == .pending })
        #expect(session.recentActivityEvents.last?.title == "補正処理をキャンセルしました")
        #expect(session.logs.last?.message == "補正処理をキャンセルしました。")
    }

    @Test
    func displayProgressKeepsActualStemStageAndSkippedState() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)
        let step = StemModeProcessStep.roleCorrection(.vocals, stage: .denoise)

        try session.applyDisplayProgress(.init(
            runID: sessionID,
            step: step,
            status: .running,
            fraction: 0,
            detail: "ボーカルを処理中"
        ))
        try session.applyDisplayProgress(.init(
            runID: sessionID,
            step: step,
            status: .skipped,
            fraction: 1,
            detail: "処理不要"
        ))

        let progress = session.displayProgress(for: step)
        #expect(progress.status == .skipped)
        #expect(progress.fraction == 1)
        #expect(progress.detail == "処理不要")
        #expect(session.recentActivityEvents.last?.domain == .correction)
        #expect(session.recentActivityEvents.last?.detail?.contains("ボーカル：ノイズ除去") == true)
    }

    @Test
    func fullLogKeepsAllCurrentRunLinesBeyondVisibleLimit() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)

        for index in 0..<510 {
            try session.appendLog(
                runID: sessionID,
                level: .info,
                step: .correctStems,
                message: "log-\(index)"
            )
        }

        #expect(session.logs.count == 510)
        #expect(session.logs.last?.message == "log-509")
    }

    @Test
    func recentLogSeparatesCompletionFromCorrectedRemixAnalysis() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)
        try completeCorrection(in: session, sessionID: sessionID)

        try session.completeCorrection(runID: sessionID)
        session.recordCorrectedRemixAnalysis(makeMetrics())

        #expect(session.recentActivityEvents.suffix(2).map(\.title) == [
            "補正処理が完了しました",
            "補正済み純粋加算を解析しました",
        ])
        #expect(session.recentActivityEvents.last?.detail == "ラウドネス: -18.0 LUFS / ピーク: -1.0 dBTP")
    }

    @Test
    func recentLogSeparatesMasteringCompletionFromFinalAnalysis() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)
        try completeCorrection(in: session, sessionID: sessionID)
        try session.completeCorrection(runID: sessionID)
        try completeRemix(in: session, sessionID: sessionID)
        try session.startMastering(runID: sessionID)

        let final = artifact(id: "final", kind: .finalMaster)
        try session.updateArtifactState(.init(
            id: final.id,
            runID: sessionID,
            kind: final.kind,
            artifact: final,
            status: .valid
        ))
        try session.completeRun(runID: sessionID)
        session.recordFinalAnalysis(makeMetrics())

        #expect(session.recentActivityEvents.suffix(2).map(\.title) == [
            "マスタリングが完了しました",
            "Stem Mode最終版を解析しました",
        ])
    }

    @Test
    func detailedLogKeepsOnlyHumanReadableProcessingLinesWithoutFormatting() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID)

        try session.beginStep(runID: sessionID, step: .separate)
        try session.completeStep(runID: sessionID, step: .separate)
        let stem = artifact(id: "corrected-vocals", kind: .correctedStem(.vocals))
        try session.updateArtifactState(.init(
            id: stem.id,
            runID: sessionID,
            kind: stem.kind,
            artifact: stem,
            status: .valid
        ))
        try session.updateValidationState(.init(
            runID: sessionID,
            subject: .stem(StemRole.vocals.rawValue),
            status: .passed(summary: "検証完了")
        ))
        try session.appendLog(
            runID: sessionID,
            level: .info,
            step: .correctStems,
            message: "ボーカルのノイズ除去を完了しました"
        )
        try session.appendLog(
            runID: sessionID,
            level: .info,
            step: .mastering,
            message: "マスタリング前解析を完了しました"
        )

        #expect(session.correctionLogLines == ["ボーカルのノイズ除去を完了しました"])
        #expect(session.masteringLogLines == ["マスタリング前解析を完了しました"])
        #expect(!session.correctionLogLines.contains { $0.contains("valid") })
        #expect(!session.correctionLogLines.contains { $0.contains("[") })
    }

    @Test
    func externalExportIsRecordedSeparatelyFromFinalMasterGeneration() {
        let session = StemWorkflowSession()
        let final = artifact(id: "final", kind: .finalMaster)
        let destination = URL(fileURLWithPath: "/tmp/final-export.wav")

        #expect(session.lastExportedDestinationURL == nil)
        session.recordExportSuccess(
            artifact: final,
            destinationURL: destination,
            fileInfo: nil
        )

        #expect(session.lastExportedDestinationURL == destination)
        #expect(session.recentActivityEvents.last?.domain == .export)
        #expect(session.recentActivityEvents.last?.title == "成果物を書き出しました")
    }

    private func completeCorrection(in session: StemWorkflowSession, sessionID: UUID) throws {
        let correctionSteps: [StemWorkflowStep] = [
            .validateInput, .separate, .validateSeparatedStems,
            .evaluateStems, .correctStems, .validateCorrectedStems,
            .correctedPureSum, .validateCorrectedPureSum,
        ]
        for step in correctionSteps {
            try session.beginStep(runID: sessionID, step: step)
            try session.completeStep(runID: sessionID, step: step)
        }
        for role in StemRole.allCases {
            let value = artifact(id: "corrected-\(role.rawValue)", kind: .correctedStem(role))
            try session.updateArtifactState(.init(
                id: value.id,
                runID: sessionID,
                kind: value.kind,
                artifact: value,
                status: .valid
            ))
        }
        let remix = artifact(id: "corrected-remix", kind: .correctedPureSum48000)
        try session.updateArtifactState(.init(
            id: remix.id,
            runID: sessionID,
            kind: remix.kind,
            artifact: remix,
            status: .valid
        ))
    }

    private func completeRemix(in session: StemWorkflowSession, sessionID: UUID) throws {
        try session.startRemix(runID: sessionID)
        let remix = artifact(id: "stem-remix", kind: .remixed48000)
        try session.updateArtifactState(.init(
            id: remix.id,
            runID: sessionID,
            kind: remix.kind,
            artifact: remix,
            status: .valid
        ))
        try session.completeRemix(runID: sessionID)
    }

    private func artifact(id: String, kind: StemArtifactKind) -> StemAudioArtifact {
        StemAudioArtifact(
            id: id,
            kind: kind,
            fileURL: FileManager.default.temporaryDirectory.appending(path: "\(id).wav"),
            sampleRate: 48_000,
            channelCount: 2,
            frameCount: 32
        )
    }

    private func makeMetrics() -> AudioMetricSnapshot {
        AudioMetricSnapshot(
            duration: 1,
            peakDBFS: -1,
            rmsDBFS: -18,
            crestFactorDB: 12,
            loudnessRangeLU: 5,
            integratedLoudnessLUFS: -18,
            truePeakDBFS: -1,
            stereoWidth: 0.5,
            stereoCorrelation: 0.8,
            stereoCorrelationTimeline: [],
            stereoCorrelationTimelineStatus: .unavailable,
            harshnessScore: 0.2,
            centroidHz: 2_000,
            hf12Ratio: 0.1,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02,
            bandEnergies: [],
            masteringBandEnergies: [],
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: []
        )
    }
}
