import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct StemModeWorkspaceModelTests {
    @Test("入力選択直後に表示解析を開始し、解析中でも補正を開始できる")
    func inputSelectionStartsDisplayAnalysisWithoutBlockingCorrection() async throws {
        let gate = WorkspaceInputAnalysisGate()
        let recorder = WorkspaceActionRecorder()
        recorder.inputDisplayAnalysisHandler = { _, _, _ in
            try await gate.wait()
        }
        let model = makeModel(recorder: recorder)
        let inputURL = URL(fileURLWithPath: "/tmp/input-display.wav")

        await model.inspectInput(inputURL)

        #expect(model.selectedInputURL == inputURL)
        #expect(model.inputPreviewURL == inputURL)
        #expect(model.isAnalyzingInput)
        try model.setProductionSeparationSettings(.metaHTDemucsProduction(seed: 1))
        model.setModelPresentation(try makeModelPresentationFixture().presentation)
        #expect(model.canRunCorrection)

        await model.beginCorrection()
        #expect(recorder.beginRequests.count == 1)

        await gate.finish(with: makeInputDisplayAnalysisResult(duration: 2))
        try await waitForWorkspaceCondition { !model.isAnalyzingInput }
        #expect(model.inputEvaluation != nil)
        #expect(model.inputSpectrogram != nil)
        #expect(model.previewController.durationText(for: .input) == "00:02")
    }

    @Test("入力表示解析の一部だけ成功しても成功済み測定値を保持する")
    func partialInputDisplayAnalysisKeepsSuccessfulMeasurements() async throws {
        let recorder = WorkspaceActionRecorder()
        let complete = makeInputDisplayAnalysisResult(duration: 4)
        let metrics = try #require(complete.evaluation?.audioMetrics)
        recorder.inputDisplayAnalysisResult = StemModeInputDisplayAnalysisResult(
            evaluation: nil,
            metrics: metrics,
            noiseMeasurements: nil,
            audioAnalysis: nil,
            previewSnapshot: complete.previewSnapshot,
            spectrogram: complete.spectrogram,
            warning: "ノイズ測定を表示できませんでした。"
        )
        let model = makeModel(recorder: recorder)

        await model.inspectInput(URL(fileURLWithPath: "/tmp/partial-input.wav"))
        try await waitForWorkspaceCondition { !model.isAnalyzingInput }

        #expect(model.inputEvaluation == nil)
        #expect(model.inputMetrics?.duration == 4)
        #expect(model.inputNoiseMeasurements == nil)
        #expect(model.inputAnalysisError == "ノイズ測定を表示できませんでした。")
        #expect(model.previewController.durationText(for: .input) == "00:04")
    }

    @Test("補正開始と補正キャンセル表示初期化で入力解析と試聴を維持する")
    func runPresentationResetPreservesSelectedInputDisplayAnalysis() async throws {
        let recorder = WorkspaceActionRecorder()
        recorder.inputDisplayAnalysisResult = makeInputDisplayAnalysisResult(duration: 3)
        let model = makeModel(recorder: recorder)
        let inputURL = URL(fileURLWithPath: "/tmp/preserved-input.wav")

        await model.inspectInput(inputURL)
        try await waitForWorkspaceCondition { !model.isAnalyzingInput }
        let evaluation = try #require(model.inputEvaluation)
        let spectrogram = try #require(model.inputSpectrogram)

        model.acceptSessionStart()
        model.resetRunPresentationAfterCorrectionCancellation()

        #expect(model.selectedInputURL == inputURL)
        #expect(model.inputPreviewURL == inputURL)
        #expect(model.inputEvaluation?.audioMetrics.duration == evaluation.audioMetrics.duration)
        #expect(model.inputSpectrogram?.duration == spectrogram.duration)
        #expect(model.previewController.durationText(for: .input) == "00:03")
    }

    @Test("入力変更後に遅れて完了した旧解析結果で新入力を上書きしない")
    func staleInputDisplayAnalysisCannotOverwriteReplacementInput() async throws {
        let firstGate = WorkspaceInputAnalysisGate()
        let recorder = WorkspaceActionRecorder()
        let firstURL = URL(fileURLWithPath: "/tmp/first-input.wav")
        let secondURL = URL(fileURLWithPath: "/tmp/second-input.wav")
        recorder.inputDisplayAnalysisHandler = { URL, _, logHandler in
            if URL == firstURL {
                let result = try await firstGate.wait()
                logHandler("旧入力の遅延ログ")
                return result
            }
            logHandler("表示解析/計測: ファイル読み込み: 0.01秒")
            return makeInputDisplayAnalysisResult(duration: 5)
        }
        let model = makeModel(recorder: recorder)

        await model.inspectInput(firstURL)
        await model.inspectInput(secondURL)
        try await waitForWorkspaceCondition {
            !model.isAnalyzingInput && model.inputEvaluation != nil
        }

        await firstGate.finish(with: makeInputDisplayAnalysisResult(duration: 9))
        await Task.yield()

        #expect(model.selectedInputURL == secondURL)
        #expect(model.inputEvaluation?.audioMetrics.duration == 5)
        #expect(model.previewController.durationText(for: .input) == "00:05")
        #expect(model.session.correctionLogLines == ["表示解析/計測: ファイル読み込み: 0.01秒"])
    }

    @Test("入力選択時の表示解析ログを補正開始前の詳細ログへ表示する")
    func inputDisplayAnalysisLogsAppearBeforeCorrectionStarts() async throws {
        let recorder = WorkspaceActionRecorder()
        recorder.inputDisplayLogMessages = [
            "表示解析/計測: ファイル読み込み: 0.01秒",
            "表示解析/計測: プレビュー/スペクトログラム生成: 0.02秒",
        ]
        let model = makeModel(recorder: recorder)

        await model.inspectInput(URL(fileURLWithPath: "/tmp/input-log.wav"))
        try await waitForWorkspaceCondition {
            model.session.correctionLogLines.count == 2
        }

        #expect(model.session.runID == nil)
        #expect(model.session.correctionLogLines == recorder.inputDisplayLogMessages)
    }

    @Test
    func productionSettingsAndSeedAreRequiredAndPassedWithoutChanges() async throws {
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(recorder: recorder)
        let inputURL = URL(fileURLWithPath: "/tmp/input.wav")

        await model.inspectInput(inputURL)
        #expect(!model.canRunCorrection)

        let settings = StemSeparationSettings.metaHTDemucsProduction(seed: 987_654)
        try model.setProductionSeparationSettings(settings)
        #expect(!model.canRunCorrection)
        model.setModelPresentation(try makeModelPresentationFixture().presentation)
        #expect(model.canRunCorrection)

        model.selectedMasteringProfile = .natural
        model.selectedAnalysisMode = .cpu
        try model.applyCorrectionProfile(.strong)
        try model.updateCorrectionSettings { settings in
            settings.airRepair = 0.57
            settings.stereoProtection = 0.83
        }
        let expectedCorrectionSettings = model.correctionSettings
        await model.beginCorrection()

        let request = try #require(recorder.beginRequests.first)
        #expect(request.inputURL == inputURL)
        #expect(request.confirmedMixMatrix == nil)
        #expect(request.separationSettings == settings)
        #expect(request.separationSettings.seed == 987_654)
        #expect(request.correctionSettings == expectedCorrectionSettings)
        #expect(request.correctionSettings.settings(for: .vocals).profile == .strong)
        #expect(request.correctionSettings.settings(for: .drums).profile == .balanced)
        #expect(request.masteringProfile == .natural)
        #expect(request.masteringSettings == MasteringProfile.natural.settings)
        #expect(request.analysisMode == .cpu)
    }

    @Test
    func rejectedStartRestoresThePreviousRunPresentation() async throws {
        let recorder = WorkspaceActionRecorder()
        recorder.beginError = .rejected
        let model = makeModel(recorder: recorder)
        await model.inspectInput(URL(fileURLWithPath: "/tmp/input.wav"))
        try model.setProductionSeparationSettings(
            .metaHTDemucsProduction(seed: 55)
        )
        model.setModelPresentation(try makeModelPresentationFixture().presentation)

        await model.beginCorrection()

        #expect(model.presentedError?.title == "Stem Modeを開始できません")
        #expect(!model.isStartingRun)
    }

    @Test
    func unapprovedSeparationSettingsAreRejected() throws {
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(recorder: recorder)
        let unapproved = StemSeparationSettings(
            shifts: 1,
            overlap: 0.25,
            split: true,
            segmentLength: .modelContract,
            batchSize: 1,
            seed: 42
        )

        #expect(throws: StemModeWorkspaceSettingsError.unapprovedProductionSettings) {
            try model.setProductionSeparationSettings(unapproved)
        }
        #expect(model.separationSettings == nil)
    }

    @Test
    func unknownLayoutRequiresExactUserConfirmationBeforeSelection() async throws {
        let layout = makeLayout(channelCount: 3)
        let recorder = WorkspaceActionRecorder()
        recorder.inspectionOutcome = .matrixConfirmationRequired(layout)
        let model = makeModel(recorder: recorder)
        let inputURL = URL(fileURLWithPath: "/tmp/discrete.wav")

        await model.inspectInput(inputURL)

        #expect(model.selectedInputURL == nil)
        #expect(model.pendingMatrixConfirmation?.inputURL == inputURL)
        #expect(model.pendingMatrixConfirmation?.inputLayout == layout)

        let confirmation = StemUserConfirmedMixMatrix(
            inputLayout: layout,
            coefficients: [1, 0, 0, 1, 0.5, 0.5],
            confirmedAt: Date(timeIntervalSince1970: 100)
        )
        await model.confirmMixMatrix(confirmation)

        #expect(model.selectedInputURL == inputURL)
        #expect(model.confirmedMixMatrix == confirmation)
        #expect(model.pendingMatrixConfirmation == nil)
    }

    @Test
    func masteringProfileAndCustomSettingsRemainExplicit() {
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(recorder: recorder)

        model.selectedMasteringProfile = .youtubeSpotify
        #expect(model.masteringSettings == MasteringProfile.youtubeSpotify.settings)
        #expect(!model.isUsingCustomMasteringSettings)

        model.masteringSettings.targetLoudness = -15
        #expect(model.isUsingCustomMasteringSettings)

        model.resetMasteringSettingsToProfile()
        #expect(model.masteringSettings == MasteringProfile.youtubeSpotify.settings)
        #expect(!model.isUsingCustomMasteringSettings)
    }

    @Test("再ミックス完了後だけマスタリングを実行でき、実行時点の最新設定を渡す")
    func masteringActionRequiresRemixCompletionAndForwardsLatestSettings() async throws {
        let recorder = WorkspaceActionRecorder()
        let session = StemWorkflowSession()
        let model = makeModel(session: session, recorder: recorder)

        #expect(!model.canRunMastering)

        let runID = UUID()
        try session.startRun(runID: runID)
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
            try session.beginStep(runID: runID, step: step)
            try session.completeStep(runID: runID, step: step)
        }
        for role in StemRole.allCases {
            let artifact = makeArtifact(
                id: "corrected-\(role.rawValue)",
                kind: .correctedStem(role)
            )
            try session.updateArtifactState(.init(
                id: artifact.id,
                runID: runID,
                kind: artifact.kind,
                artifact: artifact,
                status: .valid
            ))
        }
        let correctedRemix = makeArtifact(
            id: "corrected-remix",
            kind: .correctedPureSum48000
        )
        try session.updateArtifactState(.init(
            id: correctedRemix.id,
            runID: runID,
            kind: correctedRemix.kind,
            artifact: correctedRemix,
            status: .valid
        ))
        try session.completeCorrection(runID: runID)
        #expect(!model.canRunMastering)
        try session.startRemix(runID: runID)
        let remix = makeArtifact(id: "stem-remix", kind: .remixed48000)
        try session.updateArtifactState(.init(
            id: remix.id,
            runID: runID,
            kind: remix.kind,
            artifact: remix,
            status: .valid
        ))
        try session.completeRemix(runID: runID)

        #expect(model.canRunMastering)
        #expect(!model.canRunCorrection)
        #expect(model.canChooseInput)
        #expect(!model.isCorrectionSettingsDisabled)
        #expect(!model.isMasteringSettingsDisabled)

        model.masteringSettings.targetLoudness = -15.25
        let expectedSettings = model.masteringSettings
        await model.beginMastering()

        #expect(recorder.masteringRequests.count == 1)
        #expect(recorder.masteringRequests.first?.masteringSettings == expectedSettings)
    }

    @Test("再ミックスは自動値を保ち、変更した項目だけ手動値で上書きする")
    func remixManualOverridesPreserveUneditedAutomaticValues() throws {
        let recorder = WorkspaceActionRecorder()
        let session = StemWorkflowSession()
        let model = makeModel(session: session, recorder: recorder)
        let runID = UUID()
        try session.startRun(runID: runID)
        for role in StemRole.allCases {
            let artifact = makeArtifact(
                id: "corrected-\(role.rawValue)",
                kind: .correctedStem(role)
            )
            try session.updateArtifactState(.init(
                id: artifact.id,
                runID: runID,
                kind: artifact.kind,
                artifact: artifact,
                status: .valid
            ))
        }
        let pureSum = makeArtifact(id: "pure-sum", kind: .correctedPureSum48000)
        try session.updateArtifactState(.init(
            id: pureSum.id,
            runID: runID,
            kind: pureSum.kind,
            artifact: pureSum,
            status: .valid
        ))
        try session.completeCorrection(runID: runID)

        var automatic = StemRemixSettings(reverbReturnLevel: 0.18)
        automatic.setSettings(
            StemRemixRoleSettings(gainDB: 1.5, pan: -0.1, reverbSend: 0.2),
            for: .vocals
        )
        model.setAutomaticRemixPlan(StemRemixAutomaticPlan(
            settings: automatic,
            gainEvidenceDB: [.vocals: 1.5],
            panEvidence: [.vocals: -0.1],
            reverbLossEvidence: [.vocals: 0.4],
            drumsBassCollision: 0.2,
            vocalsOtherCollision: 0.3
        ))

        #expect(!model.isRemixManualEditingEnabled)
        #expect(throws: StemModeWorkspaceSettingsError.remixManualModeRequired) {
            try model.setRemixPan(0.35, for: .vocals)
        }
        try model.setRemixManualEditingEnabled(true)
        try model.setRemixPan(0.35, for: .vocals)
        let effective = try #require(model.effectiveRemixSettings)
        #expect(effective.settings(for: .vocals).gainDB == 1.5)
        #expect(effective.settings(for: .vocals).pan == 0.35)
        #expect(effective.settings(for: .vocals).reverbSend == 0.2)
        #expect(effective.reverbReturnLevel == 0.18)

        var updatedAutomatic = StemRemixSettings(
            masking: StemRemixMaskingSettings(
                drumsToBassEnabled: true,
                drumsToBassAmount: 0.25
            ),
            reverbReturnLevel: 0.22
        )
        updatedAutomatic.setSettings(
            StemRemixRoleSettings(gainDB: 2.5, pan: -0.2, reverbSend: 0.3),
            for: .vocals
        )
        try model.setDrumsToBassMaskingEnabled(false)
        model.setAutomaticRemixPlan(StemRemixAutomaticPlan(
            settings: updatedAutomatic,
            gainEvidenceDB: [.vocals: 2.5],
            panEvidence: [.vocals: -0.2],
            reverbLossEvidence: [.vocals: 0.5],
            drumsBassCollision: 0.4,
            vocalsOtherCollision: 0.1
        ))

        let updatedEffective = try #require(model.effectiveRemixSettings)
        #expect(updatedEffective.settings(for: .vocals).gainDB == 2.5)
        #expect(updatedEffective.settings(for: .vocals).pan == 0.35)
        #expect(updatedEffective.settings(for: .vocals).reverbSend == 0.3)
        #expect(!updatedEffective.masking.drumsToBassEnabled)
        #expect(updatedEffective.masking.drumsToBassAmount == 0.25)
        #expect(updatedEffective.reverbReturnLevel == 0.22)

        try model.setRemixManualEditingEnabled(false)
        let automaticEffective = try #require(model.effectiveRemixSettings)
        #expect(automaticEffective.settings(for: .vocals).pan == -0.2)
        #expect(automaticEffective.masking.drumsToBassEnabled)

        try model.setRemixManualEditingEnabled(true)
        let restoredManual = try #require(model.effectiveRemixSettings)
        #expect(restoredManual.settings(for: .vocals).pan == 0.35)
        #expect(!restoredManual.masking.drumsToBassEnabled)

        model.acceptSessionStart()
        #expect(model.automaticRemixPlan == nil)
        #expect(model.manualRemixOverrides == StemRemixManualOverrides())
        #expect(!model.isRemixManualEditingEnabled)
    }

    @Test("完了後も3工程を再実行でき、設定は処理中だけ無効になる")
    func completedStagesRemainRerunnableAndSettingsLockOnlyDuringProcessing() async throws {
        let recorder = WorkspaceActionRecorder()
        let session = StemWorkflowSession()
        let model = makeModel(session: session, recorder: recorder)

        await model.inspectInput(URL(fileURLWithPath: "/tmp/rerun-input.wav"))
        try model.setProductionSeparationSettings(.metaHTDemucsProduction(seed: 42))
        model.setModelPresentation(try makeModelPresentationFixture().presentation)

        let runID = UUID()
        try session.startRun(runID: runID)
        for role in StemRole.allCases {
            let artifact = makeArtifact(
                id: "rerun-corrected-\(role.rawValue)",
                kind: .correctedStem(role)
            )
            try session.updateArtifactState(.init(
                id: artifact.id,
                runID: runID,
                kind: artifact.kind,
                artifact: artifact,
                status: .valid
            ))
        }
        let pureSum = makeArtifact(id: "rerun-pure-sum", kind: .correctedPureSum48000)
        try session.updateArtifactState(.init(
            id: pureSum.id,
            runID: runID,
            kind: pureSum.kind,
            artifact: pureSum,
            status: .valid
        ))
        try session.completeCorrection(runID: runID)
        model.setAutomaticRemixPlan(StemRemixAutomaticPlan(
            settings: StemRemixSettings(),
            gainEvidenceDB: [:],
            panEvidence: [:],
            reverbLossEvidence: [:],
            drumsBassCollision: 0,
            vocalsOtherCollision: 0
        ))

        #expect(model.canRunCorrection)
        #expect(model.canRunRemix)
        #expect(!model.canRunMastering)
        #expect(!model.isCorrectionSettingsDisabled)
        #expect(!model.isRemixSettingsDisabled)
        #expect(!model.isMasteringSettingsDisabled)

        try session.startRemix(runID: runID)
        #expect(model.isCorrectionSettingsDisabled)
        #expect(model.isRemixSettingsDisabled)
        #expect(model.isMasteringSettingsDisabled)

        let remix = makeArtifact(id: "rerun-remix", kind: .remixed48000)
        try session.updateArtifactState(.init(
            id: remix.id,
            runID: runID,
            kind: remix.kind,
            artifact: remix,
            status: .valid
        ))
        try session.completeRemix(runID: runID)

        #expect(model.canRunCorrection)
        #expect(model.canRunRemix)
        #expect(model.canRunMastering)
        #expect(!model.isCorrectionSettingsDisabled)
        #expect(!model.isRemixSettingsDisabled)
        #expect(!model.isMasteringSettingsDisabled)

        try session.startMastering(runID: runID)
        let final = makeArtifact(id: "rerun-final", kind: .finalMaster)
        try session.updateArtifactState(.init(
            id: final.id,
            runID: runID,
            kind: final.kind,
            artifact: final,
            status: .valid
        ))
        try session.completeRun(runID: runID)

        #expect(model.canRunCorrection)
        #expect(model.canRunRemix)
        #expect(model.canRunMastering)
        #expect(!model.isCorrectionSettingsDisabled)
        #expect(!model.isRemixSettingsDisabled)
        #expect(!model.isMasteringSettingsDisabled)

        await model.beginRemix()
        #expect(recorder.invalidateRemixCount == 1)
        #expect(recorder.remixRequests.count == 1)
    }

    @Test
    func correctionSettingsAreIndependentByRoleAndCannotChangeDuringARun() throws {
        let recorder = WorkspaceActionRecorder()
        let session = StemWorkflowSession()
        let model = makeModel(session: session, recorder: recorder)

        #expect(model.selectedDenoiseStrength == .balanced)
        #expect(model.selectedCorrectionRole == .vocals)
        #expect(model.selectedRoleCorrectionSettings == DenoiseStrength.balanced.settings)
        #expect(!model.isUsingCustomCorrectionSettings)

        try model.applyCorrectionProfile(.gentle)
        #expect(model.selectedDenoiseStrength == .gentle)
        #expect(model.selectedRoleCorrectionSettings == DenoiseStrength.gentle.settings)
        #expect(model.correctionSettings.settings(for: .drums) == DenoiseStrength.balanced.settings)

        try model.updateCorrectionSettings { settings in
            settings.noiseDetectionSensitivity = 0.41
        }
        #expect(model.selectedRoleCorrectionSettings.profile == .gentle)
        #expect(model.selectedRoleCorrectionSettings.noiseDetectionSensitivity == 0.41)
        #expect(model.isUsingCustomCorrectionSettings)

        model.selectCorrectionRole(.drums)
        #expect(model.selectedDenoiseStrength == .balanced)
        #expect(model.selectedRoleCorrectionSettings == DenoiseStrength.balanced.settings)
        #expect(!model.isUsingCustomCorrectionSettings)

        model.selectCorrectionRole(.vocals)
        try model.resetCorrectionSettingsToProfile()
        #expect(model.selectedRoleCorrectionSettings == DenoiseStrength.gentle.settings)
        #expect(!model.isUsingCustomCorrectionSettings)

        let runID = UUID()
        try session.startRun(runID: runID)
        #expect(model.isCorrectionSettingsDisabled)
        #expect(throws: StemModeWorkspaceSettingsError.settingsCannotChangeDuringRun) {
            try model.applyCorrectionProfile(.strong)
        }
        #expect(throws: StemModeWorkspaceSettingsError.settingsCannotChangeDuringRun) {
            try model.updateCorrectionSettings { $0.airRepair = 0.4 }
        }
        #expect(throws: StemModeWorkspaceSettingsError.settingsCannotChangeDuringRun) {
            try model.resetCorrectionSettingsToProfile()
        }
        #expect(model.selectedDenoiseStrength == .gentle)
        #expect(model.selectedRoleCorrectionSettings == DenoiseStrength.gentle.settings)
    }

    @Test("Stem試聴対象と補正設定対象は独立し、選択中役割の検証済み音源だけを使用する")
    func stemPreviewUsesOnlyValidatedArtifactsForSelectedRole() throws {
        let session = StemWorkflowSession()
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(session: session, recorder: recorder)
        let runID = UUID()
        try session.startRun(runID: runID)

        let rawVocals = makeArtifact(id: "raw-vocals", kind: .rawStem(.vocals))
        let correctedVocals = makeArtifact(
            id: "corrected-vocals",
            kind: .correctedStem(.vocals)
        )
        let rawDrums = makeArtifact(id: "raw-drums", kind: .rawStem(.drums))
        let unvalidatedDrums = makeArtifact(
            id: "corrected-drums",
            kind: .correctedStem(.drums)
        )

        for artifact in [rawVocals, correctedVocals, rawDrums] {
            try session.updateArtifactState(.init(
                id: artifact.id,
                runID: runID,
                kind: artifact.kind,
                artifact: artifact,
                status: .valid
            ))
        }
        try session.updateArtifactState(.init(
            id: unvalidatedDrums.id,
            runID: runID,
            kind: unvalidatedDrums.kind,
            artifact: unvalidatedDrums,
            status: .available
        ))

        #expect(model.selectedCorrectionRole == .vocals)
        #expect(model.selectedStemPreviewRole == .vocals)
        #expect(model.selectedRawStemPreviewURL == rawVocals.fileURL)
        #expect(model.selectedCorrectedStemPreviewURL == correctedVocals.fileURL)

        model.refreshSelectedStemPreviewSources()
        #expect(model.stemPreviewController.cardState(for: .input).sourceURL == rawVocals.fileURL)
        #expect(
            model.stemPreviewController.cardState(for: .corrected).sourceURL
                == correctedVocals.fileURL
        )

        model.stemPreviewController.activeTarget = .input
        model.selectCorrectionRole(.bass)
        #expect(model.selectedCorrectionRole == .bass)
        #expect(model.selectedStemPreviewRole == .vocals)
        #expect(model.selectedRawStemPreviewURL == rawVocals.fileURL)
        #expect(model.selectedCorrectedStemPreviewURL == correctedVocals.fileURL)
        #expect(model.stemPreviewController.activeTarget == .input)

        model.selectStemPreviewRole(.drums)
        #expect(model.selectedCorrectionRole == .bass)
        #expect(model.selectedStemPreviewRole == .drums)
        #expect(model.selectedRawStemPreviewURL == rawDrums.fileURL)
        #expect(model.selectedCorrectedStemPreviewURL == nil)
        #expect(model.stemPreviewController.cardState(for: .input).sourceURL == rawDrums.fileURL)
        #expect(model.stemPreviewController.cardState(for: .corrected).sourceURL == nil)
        #expect(model.stemPreviewController.activeTarget == nil)

        model.stopPreviewPlayback()
    }

    @Test("Stem試聴は補正キャンセルと入力変更で一時成果物と一緒に消去する")
    func stemPreviewClearsWithTemporaryArtifacts() throws {
        let session = StemWorkflowSession()
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(session: session, recorder: recorder)

        let cancelledRunID = UUID()
        try session.startRun(runID: cancelledRunID)
        let cancelledRaw = makeArtifact(id: "cancelled-raw", kind: .rawStem(.vocals))
        try session.updateArtifactState(.init(
            id: cancelledRaw.id,
            runID: cancelledRunID,
            kind: cancelledRaw.kind,
            artifact: cancelledRaw,
            status: .valid
        ))
        model.refreshSelectedStemPreviewSources()
        #expect(model.stemPreviewController.cardState(for: .input).sourceURL == cancelledRaw.fileURL)

        session.resetAfterCorrectionCancellation(runID: cancelledRunID)
        model.resetRunPresentationAfterCorrectionCancellation()
        #expect(model.selectedRawStemPreviewURL == nil)
        #expect(model.stemPreviewController.cardState(for: .input).sourceURL == nil)

        let replacedRunID = UUID()
        try session.startRun(runID: replacedRunID)
        let replacedCorrected = makeArtifact(
            id: "replaced-corrected",
            kind: .correctedStem(.vocals)
        )
        try session.updateArtifactState(.init(
            id: replacedCorrected.id,
            runID: replacedRunID,
            kind: replacedCorrected.kind,
            artifact: replacedCorrected,
            status: .valid
        ))
        model.refreshSelectedStemPreviewSources()
        #expect(
            model.stemPreviewController.cardState(for: .corrected).sourceURL
                == replacedCorrected.fileURL
        )

        session.resetForInputChange()
        model.resetRunPresentationAfterCorrectionCancellation()
        #expect(model.selectedCorrectedStemPreviewURL == nil)
        #expect(model.stemPreviewController.cardState(for: .corrected).sourceURL == nil)
    }

    @Test("2mix試聴とStem試聴は独立状態で、一括停止時だけ両方を停止する")
    func twoMixAndStemPreviewStatesAreIndependent() {
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(recorder: recorder)

        model.previewController.activeTarget = .input
        model.stemPreviewController.activeTarget = .corrected

        model.stopStemPreviewPlayback()
        #expect(model.previewController.activeTarget == .input)
        #expect(model.stemPreviewController.activeTarget == nil)

        model.stemPreviewController.activeTarget = .input
        model.stopTwoMixPreviewPlayback()
        #expect(model.previewController.activeTarget == nil)
        #expect(model.stemPreviewController.activeTarget == .input)

        model.stopPreviewPlayback()
        #expect(model.previewController.activeTarget == nil)
        #expect(model.stemPreviewController.activeTarget == nil)
    }

    @Test("3工程のキャンセルは確認選択を介さず専用actionへ直接渡す")
    func cancellationActionsUseDirectControllerBoundaries() async throws {
        let recorder = WorkspaceActionRecorder()
        let session = StemWorkflowSession()
        let model = makeModel(session: session, recorder: recorder)
        let runID = UUID()
        try session.startRun(runID: runID)
        try session.beginStep(runID: runID, step: .separate)

        #expect(model.canCancelProcessing)
        await model.cancelCorrection()
        await model.cancelRemix()
        await model.cancelMastering()

        #expect(recorder.correctionCancellationCount == 1)
        #expect(recorder.remixCancellationCount == 1)
        #expect(recorder.masteringCancellationCount == 1)
    }

    @Test("Stemの3工程はキャンセル受付中に同じ状態表示となり、二重操作を防ぐ")
    func cancellationStateMatchesStandardModeAndPreventsRepeatedRequests() async throws {
        for domain in [
            StemModeProcessDomain.correction,
            .remix,
            .mastering,
        ] {
            let gate = WorkspaceCancellationGate()
            let recorder = WorkspaceActionRecorder()
            recorder.cancellationHandler = { requestedDomain in
                #expect(requestedDomain == domain)
                await gate.wait()
            }
            let session = StemWorkflowSession()
            let model = makeModel(session: session, recorder: recorder)
            let runID = UUID()
            try session.startRun(runID: runID)
            try session.beginStep(runID: runID, step: .separate)

            let cancellationTask = Task { @MainActor in
                await cancel(domain, on: model)
            }
            try await waitForWorkspaceCondition {
                model.cancellingProcessDomain == domain
            }

            #expect(!model.canCancelProcessing)
            #expect(model.isCorrectionCancelling == (domain == .correction))
            #expect(model.isRemixCancelling == (domain == .remix))
            #expect(model.isMasteringCancelling == (domain == .mastering))

            await cancel(domain, on: model)
            #expect(recorder.cancellationCount(for: domain) == 1)

            await gate.finish()
            await cancellationTask.value

            #expect(model.cancellingProcessDomain == nil)
            #expect(model.canCancelProcessing)
            #expect(!model.isCorrectionCancelling)
            #expect(!model.isRemixCancelling)
            #expect(!model.isMasteringCancelling)
        }
    }

    @Test
    func exportPassesExactArtifactAndFormatToControllerBoundary() async {
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(recorder: recorder)
        let artifact = makeArtifact(id: "final", kind: .finalMaster)

        await model.exportArtifact(artifact, as: .deliveryWAV)

        #expect(recorder.exportCalls.count == 1)
        #expect(recorder.exportCalls[0].artifact == artifact)
        #expect(recorder.exportCalls[0].format == .deliveryWAV)
        #expect(!model.isExporting(artifact))
        #expect(model.session.lastExportedDestinationURL?.lastPathComponent == "final-export.wav")
        #expect(model.session.recentActivityEvents.last?.domain == .export)
    }

    @Test
    func exportableArtifactsPutPureSumThenRemixAndExcludeInternalOrInvalidFiles() throws {
        let session = StemWorkflowSession()
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(session: session, recorder: recorder)
        let runID = UUID()
        try session.startRun(runID: runID)

        let rawStem = makeArtifact(id: "raw-drums", kind: .rawStem(.drums))
        let selectedStem = makeArtifact(id: "drums", kind: .correctedStem(.drums))
        let final = makeArtifact(id: "final", kind: .finalMaster)
        let internalInput = makeArtifact(id: "input", kind: .input44100)
        let correctedRemix = makeArtifact(id: "remix", kind: .correctedPureSum48000)
        let processedRemix = makeArtifact(id: "processed-remix", kind: .remixed48000)
        let invalidRemix = makeArtifact(id: "invalid-remix", kind: .correctedPureSum48000)
        let unvalidatedRaw = makeArtifact(id: "raw-other", kind: .rawStem(.other))

        for artifact in [rawStem, selectedStem, final, internalInput, correctedRemix, processedRemix] {
            try session.updateArtifactState(
                StemWorkflowArtifactDisplayState(
                    id: artifact.id,
                    runID: runID,
                    kind: artifact.kind,
                    artifact: artifact,
                    status: .valid
                )
            )
        }
        try session.updateArtifactState(
            StemWorkflowArtifactDisplayState(
                id: invalidRemix.id,
                runID: runID,
                kind: invalidRemix.kind,
                artifact: invalidRemix,
                status: .invalid(message: "failed")
            )
        )
        try session.updateArtifactState(
            StemWorkflowArtifactDisplayState(
                id: unvalidatedRaw.id,
                runID: runID,
                kind: unvalidatedRaw.kind,
                artifact: unvalidatedRaw,
                status: .available
            )
        )

        #expect(model.exportableArtifacts.map(\.id) == [
            "remix", "processed-remix", "drums", "final",
        ])
    }

    @Test
    func modelPresentationUsesValidatedSourceRevisionSizeLicenseAndChecksums() throws {
        let fixture = try makeModelPresentationFixture()
        let manifest = fixture.manifest
        let contract = fixture.contract
        let generationID = fixture.generationID
        let modelRoot = fixture.modelRoot
        let modelAssets = fixture.modelAssets
        let receipt = fixture.receipt
        let runtimeReport = fixture.runtimeReport
        let presentation = fixture.presentation

        #expect(presentation.repository == manifest.model.repo)
        #expect(presentation.revision == manifest.model.revision)
        #expect(presentation.license == manifest.model.licenseMetadata)
        #expect(presentation.generationIdentifier == generationID)
        #expect(presentation.downloadableAssets.map(\.sha256) == modelAssets.map(\.sha256))
        #expect(presentation.bundledRuntimeAssets.map(\.sha256) == manifest.bundledRuntimeAssets.map(\.sha256))
        #expect(
            presentation.downloadableByteCount
                == manifest.downloadableModelAssets.map(\.byteCount).reduce(0, +)
        )

        let incompleteInstallation = ValidatedStemModelInstallation(
            snapshot: ValidatedStemModelSnapshot(
                contract: contract,
                installationRootURL: modelRoot,
                modelDirectoryURL: modelRoot,
                assets: Array(modelAssets.dropLast())
            ),
            receipt: receipt,
            generationDirectoryURL: modelRoot
        )
        #expect(throws: StemModeModelPresentationError.downloadableAssetSetIncomplete) {
            try StemModeModelPresentation(
                manifest: manifest,
                installation: incompleteInstallation,
                bundledRuntime: runtimeReport
            )
        }

        let recorder = WorkspaceActionRecorder()
        let model = makeModel(recorder: recorder)
        model.setModelPresentation(presentation)
        #expect(model.modelPresentation == presentation)
    }

    @Test
    func previewUsesDedicatedControllerAndOnlyOffersInputCorrectedRemixAndFinal() async {
        let firstRecorder = WorkspaceActionRecorder()
        let secondRecorder = WorkspaceActionRecorder()
        let first = makeModel(recorder: firstRecorder)
        let second = makeModel(recorder: secondRecorder)
        #expect(first.previewController !== second.previewController)

        let correctedRemix = makeArtifact(id: "corrected-remix", kind: .correctedPureSum48000)
        let final = makeArtifact(id: "final", kind: .finalMaster)
        let vocals = makeArtifact(id: "vocals", kind: .rawStem(.vocals))
        let input = makeArtifact(id: "input", kind: .input44100)
        let selectedVocals = makeArtifact(id: "corrected-vocals", kind: .correctedStem(.vocals))

        await first.inspectInput(input.fileURL)

        first.updatePreviewSources(
            from: [final, input, correctedRemix, selectedVocals, vocals]
        )
        defer { first.updatePreviewSources(from: []) }

        #expect(
            first.previewArtifacts.map(\.id)
                == ["input", "corrected-remix", "final"]
        )
        #expect(first.inputPreviewArtifact == input)
        #expect(first.correctedRemixPreviewArtifact == correctedRemix)
        #expect(first.finalPreviewArtifact == final)
        #expect(first.previewController.comparisonPair == .inputVsMastered)
        #expect(first.previewController.cardState(for: .input).sourceURL == input.fileURL)
        #expect(first.previewController.cardState(for: .mastered).sourceURL == final.fileURL)
        #expect(first.previewController.cardState(for: .corrected).sourceURL == correctedRemix.fileURL)
    }

    @Test
    func correctedOnlyPreviewSelectsInputVsCorrectedAfterCorrection() async {
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(recorder: recorder)
        let input = makeArtifact(id: "input", kind: .input44100)
        let correctedRemix = makeArtifact(id: "corrected-remix", kind: .correctedPureSum48000)
        await model.inspectInput(input.fileURL)

        model.updatePreviewSources(from: [input, correctedRemix])
        defer { model.updatePreviewSources(from: []) }

        #expect(model.previewController.comparisonPair == .inputVsCorrected)
        #expect(model.previewController.cardState(for: .input).sourceURL == input.fileURL)
        #expect(model.previewController.cardState(for: .corrected).sourceURL == correctedRemix.fileURL)
        #expect(model.previewController.cardState(for: .mastered).sourceURL == nil)
    }

    @Test
    func comparisonPairChangesOnlyThePlaybackPairAndNeverRemapsArtifacts() async {
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(recorder: recorder)
        let input = makeArtifact(id: "input", kind: .input44100)
        let correctedRemix = makeArtifact(id: "corrected-remix", kind: .correctedPureSum48000)
        let final = makeArtifact(id: "final", kind: .finalMaster)
        await model.inspectInput(input.fileURL)
        model.updatePreviewSources(from: [input, correctedRemix, final])
        defer { model.updatePreviewSources(from: []) }

        model.previewController.setComparisonPair(.correctedVsMastered)

        #expect(model.inputPreviewArtifact == input)
        #expect(model.correctedRemixPreviewArtifact == correctedRemix)
        #expect(model.finalPreviewArtifact == final)
        #expect(model.previewController.cardState(for: .input).sourceURL == input.fileURL)
        #expect(model.previewController.cardState(for: .corrected).sourceURL == correctedRemix.fileURL)
        #expect(model.previewController.cardState(for: .mastered).sourceURL == final.fileURL)
    }

    @Test
    func finalCommitLockDisablesCancellationUntilControllerUnlocksIt() throws {
        let session = StemWorkflowSession()
        let recorder = WorkspaceActionRecorder()
        let model = makeModel(session: session, recorder: recorder)
        let runID = UUID()
        try session.startRun(runID: runID)
        try session.beginStep(runID: runID, step: .mastering)
        #expect(model.canCancelProcessing)

        model.setFinalCommitLockState(.locked)
        #expect(!model.canCancelProcessing)
        #expect(model.finalCommitLockState == .locked)

        model.setFinalCommitLockState(.unlocked)
        #expect(model.canCancelProcessing)
    }

    private func makeModel(
        session: StemWorkflowSession = StemWorkflowSession(),
        recorder: WorkspaceActionRecorder
    ) -> StemModeWorkspaceModel {
        StemModeWorkspaceModel(
            session: session,
            actions: recorder.actions
        )
    }

    private func cancel(
        _ domain: StemModeProcessDomain,
        on model: StemModeWorkspaceModel
    ) async {
        switch domain {
        case .correction:
            await model.cancelCorrection()
        case .remix:
            await model.cancelRemix()
        case .mastering:
            await model.cancelMastering()
        }
    }

    private func makeLayout(channelCount: Int) -> StemInputLayoutIdentity {
        StemInputLayoutIdentity(
            channelCount: channelCount,
            layoutTag: 0,
            channelBitmap: 0,
            channelDescriptions: []
        )
    }

    private func makeArtifact(
        id: String,
        kind: StemArtifactKind
    ) -> StemAudioArtifact {
        StemAudioArtifact(
            id: id,
            kind: kind,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).wav"),
            sampleRate: 44_100,
            channelCount: 2,
            frameCount: 1_000
        )
    }

    private struct ModelPresentationFixture {
        let manifest: StemModelManifest
        let contract: StemModelContract
        let generationID: UUID
        let modelRoot: URL
        let modelAssets: [ValidatedStemModelAsset]
        let receipt: StemModelInstallationReceipt
        let runtimeReport: StemBundledRuntimeValidationReport
        let presentation: StemModeModelPresentation
    }

    private func makeModelPresentationFixture() throws -> ModelPresentationFixture {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repositoryRoot.appending(
            path: "Sources/VelouraLucent/Resources/StemModels/stem-model-manifest.json"
        )
        let validator = StemModelAssetValidator()
        let manifest = try validator.loadManifest(at: manifestURL)
        let contract = try validator.validateManifest(manifest)
        let generationID = UUID()
        let modelRoot = URL(fileURLWithPath: "/tmp/model-generation")
        let modelAssets = manifest.downloadableModelAssets.map { asset in
            ValidatedStemModelAsset(
                kind: asset.kind,
                fileURL: modelRoot.appending(path: asset.installationRelativePath),
                byteCount: asset.byteCount,
                sha256: asset.sha256
            )
        }
        let receipt = StemModelInstallationReceipt(
            schemaVersion: StemModelInstallationReceipt.currentSchemaVersion,
            assetSetIdentifier: manifest.assetSetIdentifier,
            modelIdentifier: contract.identifier,
            revision: manifest.model.revision,
            generationIdentifier: generationID,
            activatedAt: Date(timeIntervalSince1970: 10),
            assets: manifest.downloadableModelAssets.map { asset in
                StemModelInstallationReceiptAsset(
                    kind: asset.kind,
                    installationRelativePath: asset.installationRelativePath,
                    byteCount: asset.byteCount,
                    sha256: asset.sha256
                )
            },
            sourceEvidence: manifest.downloadableModelAssets.map { asset in
                StemModelInstallationSourceEvidence(
                    kind: asset.kind,
                    stableDownloadURL: asset.downloadURL,
                    responseHeaderName: manifest.downloadPolicy.revisionResponseHeader,
                    revision: manifest.model.revision
                )
            }
        )
        let installation = ValidatedStemModelInstallation(
            snapshot: ValidatedStemModelSnapshot(
                contract: contract,
                installationRootURL: modelRoot,
                modelDirectoryURL: modelRoot,
                assets: modelAssets
            ),
            receipt: receipt,
            generationDirectoryURL: modelRoot
        )
        let runtimeRoot = URL(fileURLWithPath: "/tmp/runtime")
        let runtimeReport = StemBundledRuntimeValidationReport(
            contract: contract,
            assets: manifest.bundledRuntimeAssets.map { asset in
                ValidatedStemModelAsset(
                    kind: asset.kind,
                    fileURL: runtimeRoot.appending(path: asset.resourceRelativePath),
                    byteCount: asset.byteCount,
                    sha256: asset.sha256
                )
            }
        )
        let presentation = try StemModeModelPresentation(
            manifest: manifest,
            installation: installation,
            bundledRuntime: runtimeReport
        )
        return ModelPresentationFixture(
            manifest: manifest,
            contract: contract,
            generationID: generationID,
            modelRoot: modelRoot,
            modelAssets: modelAssets,
            receipt: receipt,
            runtimeReport: runtimeReport,
            presentation: presentation
        )
    }
}

@MainActor
private final class WorkspaceActionRecorder {
    enum BeginError: Error {
        case rejected
    }

    struct ExportCall {
        let artifact: StemAudioArtifact
        let format: AudioExportFormat
    }

    var inspectionOutcome: StemModeInputSelectionOutcome = .ready
    var inputDisplayAnalysisResult = makeInputDisplayAnalysisResult(duration: 1)
    var inputDisplayAnalysisHandler: (@MainActor (
        URL,
        StemAudioAnalysisMode,
        @escaping @Sendable (String) -> Void
    ) async throws -> StemModeInputDisplayAnalysisResult)?
    var inputDisplayLogMessages: [String] = []
    var beginError: BeginError?
    var beginRequests: [StemModeStartRequest] = []
    var remixRequests: [StemModeRemixRequest] = []
    var masteringRequests: [StemModeMasteringRequest] = []
    var resetForInputChangeCount = 0
    var invalidateRemixCount = 0
    var correctionCancellationCount = 0
    var remixCancellationCount = 0
    var masteringCancellationCount = 0
    var cancellationHandler: (@MainActor (StemModeProcessDomain) async throws -> Void)?
    var exportCalls: [ExportCall] = []
    var revealedURLs: [URL] = []

    func cancellationCount(for domain: StemModeProcessDomain) -> Int {
        switch domain {
        case .correction:
            correctionCancellationCount
        case .remix:
            remixCancellationCount
        case .mastering:
            masteringCancellationCount
        }
    }

    var actions: StemModeWorkspaceActions {
        StemModeWorkspaceActions(
            inspectInput: { [weak self] _ in
                self?.inspectionOutcome ?? .ready
            },
            analyzeInputForDisplay: { [weak self] URL, mode, logHandler in
                self?.inputDisplayLogMessages.forEach(logHandler)
                if let handler = self?.inputDisplayAnalysisHandler {
                    return try await handler(URL, mode, logHandler)
                }
                return self?.inputDisplayAnalysisResult
                    ?? makeInputDisplayAnalysisResult(duration: 1)
            },
            releaseInspectedInput: { _ in },
            resetForInputChange: { [weak self] in
                self?.resetForInputChangeCount += 1
            },
            beginCorrection: { [weak self] request in
                if let error = self?.beginError {
                    throw error
                }
                self?.beginRequests.append(request)
            },
            beginRemix: { [weak self] request in
                self?.remixRequests.append(request)
            },
            invalidateRemix: { [weak self] in
                self?.invalidateRemixCount += 1
            },
            beginMastering: { [weak self] request in
                self?.masteringRequests.append(request)
            },
            cancelCorrection: { [weak self] in
                guard let self else { return }
                self.correctionCancellationCount += 1
                try await self.cancellationHandler?(.correction)
            },
            cancelRemix: { [weak self] in
                guard let self else { return }
                self.remixCancellationCount += 1
                try await self.cancellationHandler?(.remix)
            },
            cancelMastering: { [weak self] in
                guard let self else { return }
                self.masteringCancellationCount += 1
                try await self.cancellationHandler?(.mastering)
            },
            exportArtifact: { [weak self] artifact, format in
                self?.exportCalls.append(
                    ExportCall(artifact: artifact, format: format)
                )
                return URL(fileURLWithPath: "/tmp/\(artifact.id)-export.wav")
            },
            revealArtifact: { [weak self] URL in
                self?.revealedURLs.append(URL)
            }
        )
    }
}

private actor WorkspaceCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor WorkspaceInputAnalysisGate {
    private var continuation: CheckedContinuation<StemModeInputDisplayAnalysisResult, any Error>?
    private var pendingResult: StemModeInputDisplayAnalysisResult?

    func wait() async throws -> StemModeInputDisplayAnalysisResult {
        if let pendingResult {
            self.pendingResult = nil
            return pendingResult
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with result: StemModeInputDisplayAnalysisResult) {
        if let continuation {
            continuation.resume(returning: result)
            self.continuation = nil
        } else {
            pendingResult = result
        }
    }
}

@MainActor
private func waitForWorkspaceCondition(
    _ condition: @MainActor () -> Bool
) async throws {
    for _ in 0..<200 {
        if condition() { return }
        await Task.yield()
    }
    throw CancellationError()
}

private func makeInputDisplayAnalysisResult(
    duration: TimeInterval
) -> StemModeInputDisplayAnalysisResult {
    let metrics = AudioMetricSnapshot(
        duration: duration,
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
    )
    let request = StemAudioEvaluationRequest(
        purpose: .canonicalInput,
        includeAudioAnalyzerSnapshot: false,
        includeMasteringAnalysisSnapshot: false
    )
    let evaluation = StemAudioEvaluationSnapshot(
        request: request,
        completedMeasurements: request.requestedMeasurements,
        audioMetrics: metrics,
        noiseMeasurements: NoiseMeasurementSnapshot(values: []),
        audioAnalysis: nil,
        masteringAnalysis: nil
    )
    return StemModeInputDisplayAnalysisResult(
        evaluation: evaluation,
        previewSnapshot: AudioPreviewSnapshot(
            waveform: [.zero, .symmetric(0.5), .zero],
            duration: duration,
            bandLevels: [:],
            bandLevelDBs: [:],
            realtimeSpectrumTimeline: []
        ),
        spectrogram: SpectrogramSnapshot(
            cells: [],
            timeBucketCount: 0,
            frequencyBucketCount: 0,
            duration: duration,
            minLevelDB: -100,
            maxLevelDB: 0
        ),
        warning: nil
    )
}
