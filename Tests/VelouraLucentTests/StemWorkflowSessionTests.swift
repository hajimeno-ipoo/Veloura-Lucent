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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())

        let input = artifact(id: "input", kind: .input44100)
        try session.updateArtifactState(.init(
            id: input.id,
            runID: sessionID,
            kind: input.kind,
            artifact: input,
            status: .valid
        ))
        for role in makeStemTestRunContract().activeRoles {
            let raw = artifact(id: "raw-\(role.rawValue)", kind: .rawStem(role))
            try session.updateArtifactState(.init(
                id: raw.id,
                runID: sessionID,
                kind: raw.kind,
                artifact: raw,
                status: .valid
            ))
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
    func correctionCompletionUsesTheCapturedSixStemRunContract() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        let contract = makeStemTestRunContract(model: .bsRoformerSW)
        try session.startRun(runID: sessionID, runContract: contract)

        try completeCorrection(in: session, sessionID: sessionID)
        try session.completeCorrection(runID: sessionID)

        #expect(session.runContract == contract)
        #expect(session.state == .readyForRemix(runID: sessionID))
        #expect(session.artifactStates.filter {
            if case .correctedStem = $0.kind { return true }
            return false
        }.count == 6)
    }

    @Test
    func runContractDeterminesArtifactCountsAndDetailedProgressDenominator() throws {
        let htSession = StemWorkflowSession()
        let bsSession = StemWorkflowSession()
        let htRunID = UUID()
        let bsRunID = UUID()
        try htSession.startRun(
            runID: htRunID,
            runContract: makeStemTestRunContract(model: .htdemucs)
        )
        try bsSession.startRun(
            runID: bsRunID,
            runContract: makeStemTestRunContract(model: .bsRoformerSW)
        )

        #expect(htSession.expectedCorrectionArtifactCount == 10)
        #expect(htSession.expectedCompletedArtifactCount == 12)
        #expect(bsSession.expectedCorrectionArtifactCount == 14)
        #expect(bsSession.expectedCompletedArtifactCount == 16)
        #expect(bsSession.correctionDisplayProgress.count > htSession.correctionDisplayProgress.count)

        try bsSession.applyDisplayProgress(.init(
            runID: bsRunID,
            step: .inputPreparation,
            status: .completed,
            fraction: 1
        ))
        #expect(
            bsSession.displayProgressValue(for: .correction)
                == 1 / Double(bsSession.correctionDisplayProgress.count)
        )
        #expect(
            bsSession.displayProgress(for: .separation(stemCount: 6)).step.title
                == "6Stem分離"
        )
    }

    @Test
    func staleRunAndContractExcludedEventsDoNotChangeSessionState() throws {
        let session = StemWorkflowSession()
        let runID = UUID()
        try session.startRun(
            runID: runID,
            runContract: makeStemTestRunContract(model: .htdemucs)
        )
        let excluded = artifact(id: "raw-guitar", kind: .rawStem(.guitar))

        #expect(throws: StemWorkflowSessionError.artifactOutsideRunContract("ギター（raw）")) {
            try session.updateArtifactState(.init(
                id: excluded.id,
                runID: runID,
                kind: excluded.kind,
                artifact: excluded,
                status: .valid
            ))
        }
        let staleRunID = UUID()
        #expect(throws: StemWorkflowSessionError.runMismatch(expected: runID, actual: staleRunID)) {
            try session.appendLog(
                runID: staleRunID,
                level: .info,
                step: .separate,
                message: "古いevent"
            )
        }
        #expect(throws: StemWorkflowSessionError.progressOutsideRunContract(
            StemModeProcessStep.roleAnalysis(.guitar).id
        )) {
            try session.applyDisplayProgress(.init(
                runID: runID,
                step: .roleAnalysis(.guitar),
                status: .running,
                fraction: 0.5
            ))
        }

        #expect(session.artifactStates.isEmpty)
        #expect(session.logs.isEmpty)
        #expect(!session.displayProgress.contains { $0.step == .roleAnalysis(.guitar) })
    }

    @Test
    func correctionFailureClearsCurrentRunArtifactsForFourAndSixStemContracts() throws {
        for model in [StemSeparationModel.htdemucs, .bsRoformerSW] {
            let session = StemWorkflowSession()
            let runID = UUID()
            let contract = makeStemTestRunContract(model: model)
            try session.startRun(runID: runID, runContract: contract)
            let input = artifact(id: "input-\(model.rawValue)", kind: .input44100)
            try session.updateArtifactState(.init(
                id: input.id,
                runID: runID,
                kind: input.kind,
                artifact: input,
                status: .valid
            ))

            try session.fail(runID: runID, step: .separate, message: "分離失敗")

            #expect(session.state == .failed(runID: runID, message: "分離失敗"))
            #expect(session.artifactStates.isEmpty)
            #expect(session.validationStates.isEmpty)
            #expect(session.runContract == contract)
        }
    }

    @Test
    func postCorrectionFailureAndCancellationRetentionUsesFourAndSixStemContracts() throws {
        for model in [StemSeparationModel.htdemucs, .bsRoformerSW] {
            let session = StemWorkflowSession()
            let runID = UUID()
            let contract = makeStemTestRunContract(model: model)
            try session.startRun(runID: runID, runContract: contract)
            try completeCorrection(in: session, sessionID: runID)
            try session.completeCorrection(runID: runID)

            try session.startRemix(runID: runID)
            let failedRemix = artifact(id: "failed-remix-\(model.rawValue)", kind: .remixed48000)
            try session.updateArtifactState(.init(
                id: failedRemix.id,
                runID: runID,
                kind: failedRemix.kind,
                artifact: failedRemix,
                status: .valid
            ))
            try session.restoreRemixReadyAfterFailure(runID: runID, message: "再ミックス失敗")
            #expect(session.state == .readyForRemix(runID: runID))
            #expect(session.artifactStates.filter {
                if case .correctedStem = $0.kind { return true }
                return false
            }.count == contract.stemCount)
            #expect(session.artifactStates.contains { $0.kind == .correctedPureSum48000 })
            #expect(!session.artifactStates.contains { $0.kind == .remixed48000 })

            try session.startRemix(runID: runID)
            try session.restoreRemixReadyAfterCancellation(runID: runID)
            #expect(session.state == .readyForRemix(runID: runID))
            #expect(session.lastError == nil)

            try completeRemix(in: session, sessionID: runID)
            try session.startMastering(runID: runID)
            let failedFinal = artifact(id: "failed-final-\(model.rawValue)", kind: .finalMaster)
            try session.updateArtifactState(.init(
                id: failedFinal.id,
                runID: runID,
                kind: failedFinal.kind,
                artifact: failedFinal,
                status: .valid
            ))
            try session.restoreMasteringReadyAfterFailure(runID: runID, message: "マスタリング失敗")
            #expect(session.state == .readyForMastering(runID: runID))
            #expect(session.artifactStates.contains { $0.kind == .remixed48000 })
            #expect(!session.artifactStates.contains { $0.kind == .finalMaster })

            try session.startMastering(runID: runID)
            try session.restoreMasteringReadyAfterCancellation(runID: runID)
            #expect(session.state == .readyForMastering(runID: runID))
            #expect(session.lastError == nil)
            #expect(session.artifactStates.filter {
                if case .correctedStem = $0.kind { return true }
                return false
            }.count == contract.stemCount)
        }
    }

    @Test
    func processingStateRemainsActiveBetweenDetailedStepsUntilTheDomainFinishes() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()

        #expect(!session.isCorrectionProcessing)
        #expect(!session.isMasteringProcessing)

        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())

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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())

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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())

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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
        try completeCorrection(in: session, sessionID: sessionID)

        try session.completeCorrection(runID: sessionID)
        session.recordCorrectedRemixAnalysis(makeMetrics())

        #expect(session.recentActivityEvents.suffix(2).map(\.title) == [
            "補正処理が完了しました",
            "補正後を解析しました",
        ])
        #expect(session.recentActivityEvents.last?.detail == "ラウドネス: -18.0 LUFS / ピーク: -1.0 dBTP")
    }

    @Test
    func recentLogSeparatesMasteringCompletionFromFinalAnalysis() throws {
        let session = StemWorkflowSession()
        let sessionID = UUID()
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())
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
        try session.startRun(runID: sessionID, runContract: makeStemTestRunContract())

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
        let input = artifact(id: "input", kind: .input44100)
        try session.updateArtifactState(.init(
            id: input.id,
            runID: sessionID,
            kind: input.kind,
            artifact: input,
            status: .valid
        ))
        for role in try #require(session.runContract).activeRoles {
            let raw = artifact(id: "raw-\(role.rawValue)", kind: .rawStem(role))
            try session.updateArtifactState(.init(
                id: raw.id,
                runID: sessionID,
                kind: raw.kind,
                artifact: raw,
                status: .valid
            ))
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
