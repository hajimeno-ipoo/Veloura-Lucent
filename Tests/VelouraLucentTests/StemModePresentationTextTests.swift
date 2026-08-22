import Testing
@testable import VelouraLucent

struct StemModePresentationTextTests {
    @Test
    func inputPureSumRemixAndFinalArePreviewable() {
        let corrected = StemArtifactKind.correctedPureSum48000

        #expect(corrected.stemModeDisplayTitle == "補正後")
        #expect(corrected.isStemModeUserExportable)
        #expect(corrected.isStemModePreviewable)
        #expect(StemArtifactKind.input44100.isStemModePreviewable)
        #expect(StemArtifactKind.finalMaster.isStemModePreviewable)
        #expect(StemArtifactKind.remixed48000.isStemModePreviewable)
        #expect(!StemArtifactKind.rawStem(.vocals).isStemModePreviewable)
        #expect(!StemArtifactKind.correctedStem(.vocals).isStemModePreviewable)
        #expect(!StemArtifactKind.input44100.isStemModeUserExportable)
        #expect(StemArtifactKind.correctedStem(.vocals).isStemModeUserExportable)
        #expect(StemArtifactKind.finalMaster.isStemModeUserExportable)
    }

    @Test
    func exportabilityIncludesCorrectedRemixSixCorrectedStemsAndFinalMaster() {
        let exportable = [
            StemArtifactKind.correctedPureSum48000,
            StemArtifactKind.remixed48000,
            StemArtifactKind.correctedStem(.drums),
            .correctedStem(.bass),
            .correctedStem(.other),
            .correctedStem(.vocals),
            .correctedStem(.guitar),
            .correctedStem(.piano),
            .finalMaster,
        ]
        let internalOnly = [
            StemArtifactKind.input44100,
            .rawStem(.drums),
        ]

        #expect(exportable.allSatisfy { $0.isStemModeUserExportable })
        #expect(internalOnly.allSatisfy { !$0.isStemModeUserExportable })
        #expect(StemArtifactKind.correctedStem(.guitar).stemModeExportMenuTitle == "ギター")
        #expect(StemArtifactKind.correctedStem(.piano).stemModeExportMenuTitle == "ピアノ")
        #expect(StemArtifactKind.correctedPureSum48000.stemModeExportMenuTitle == "補正後")
        #expect(StemArtifactKind.remixed48000.stemModeExportMenuTitle == "再ミックス済み")
        #expect(StemArtifactKind.finalMaster.stemModeExportMenuTitle == "マスタリング済み")
        #expect(StemArtifactKind.correctedStem(.guitar).isCorrectedStemArtifact)
        #expect(!StemArtifactKind.finalMaster.isCorrectedStemArtifact)
    }

    @Test
    func correctionAndRemixWorkflowStepsHaveDistinctUserFacingTitles() {
        #expect(StemWorkflowStep.correctStems.title == "Stem別補正")
        #expect(StemWorkflowStep.validateCorrectedStems.title == "補正後Stem検証")
        #expect(StemWorkflowStep.correctedPureSum.title == "補正後")
        #expect(StemWorkflowStep.validateCorrectedPureSum.title == "補正後検証")
        #expect(StemModeProcessStep.correctedPureSum.title == "補正後")
        #expect(StemModeProcessStep.correctedPureSumValidation.title == "補正後検証")
        #expect(StemWorkflowStep.remix.title == "Stem再ミックス")
        #expect(StemWorkflowStep.validateRemix.title == "Stem再ミックス検証")
        #expect(StemWorkflowValidationSubject.rawRemix.stemModeDisplayTitle == "raw再ミックス")
        #expect(
            StemWorkflowValidationSubject.correctedPureSum.stemModeDisplayTitle
                == "補正後"
        )
        #expect(StemWorkflowValidationSubject.remix.stemModeDisplayTitle == "Stem再ミックス")
    }

    @Test
    func stageOutcomesDescribeStraightLineProcessing() {
        #expect(StemCorrectionStageGuardOutcome.completed.stemModeDisplayTitle == "工程内guardを含めて完了")
        #expect(StemCorrectionStageGuardOutcome.unchanged.stemModeDisplayTitle == "工程内判断により音声を維持")
        #expect(StemCorrectionStageGuardOutcome.notEvaluatedForSkippedStage.stemModeDisplayTitle == "工程省略・guard未評価")
    }

    @Test
    func remixStageDetailsUseCompleteSentences() {
        #expect(StemRemixRenderStage.allCases.map(\.stemModeRunningDetail) == [
            "補正後の相対変化を基準にStem別gainを適用します",
            "実測衝突区間だけdynamic EQ／duckingを適用します",
            "rawから変化した左右バランスだけを補正します",
            "pan後の各Stemから共通reverbへのsendを生成します",
            "一つの共通reverb returnを生成します",
            "dry Stem合計へ共通reverb returnを加算します",
        ])
        #expect(StemRemixRenderStage.allCases.map(\.stemModeCompletedDetail) == [
            "Stem別gainを適用しました",
            "条件付き帯域制御を完了しました",
            "Stem別panを適用しました",
            "Stem別reverb sendを生成しました",
            "共通reverb returnを生成しました",
            "dry／reverb加算を完了しました",
        ])
    }

    @Test
    func sidebarKeepsOnlyCompactAdditionalProgressInformation() {
        #expect(sidebarDetail(
            step: .inputPreparation,
            detail: "入力変換・解析中"
        ) == "入力変換・解析中")
        #expect(sidebarDetail(
            step: .separation(stemCount: 6),
            detail: "HTDemucs Encoder 3/4"
        ) == "HTDemucs Encoder 3/4")
        #expect(sidebarDetail(
            step: .separation(stemCount: 6),
            detail: "bassを保存・検証済み"
        ) == "ベース保存済み")
        #expect(sidebarDetail(
            step: .roleCorrection(.guitar, stage: .denoise),
            detail: "ギターのノイズ除去を実行中"
        ) == nil)
        #expect(sidebarDetail(
            step: .roleTransientRecovery(.drums),
            detail: "raw Stemと補正後のアタックを比較中"
        ) == "アタック比較中")
        #expect(sidebarDetail(
            step: .correctedPureSum,
            detail: "補正済みStemを純粋加算中"
        ) == "6Stem加算中")

        let remixDetails: [(StemModeProcessStep, String, String?)] = [
            (.remixGain, StemRemixRenderStage.gain.stemModeRunningDetail, "相対変化基準"),
            (.remixMasking, StemRemixRenderStage.masking.stemModeRunningDetail, "衝突区間のみ"),
            (.remixPan, StemRemixRenderStage.pan.stemModeRunningDetail, "左右変化分のみ"),
            (.remixReverbSend, StemRemixRenderStage.reverbSend.stemModeRunningDetail, "共通returnへ送信中"),
            (.remixSharedReverb, StemRemixRenderStage.sharedReverb.stemModeRunningDetail, "共通return生成中"),
            (.remixDryReturnMix, StemRemixRenderStage.dryReturnMix.stemModeRunningDetail, "dry＋return加算中"),
        ]
        for (step, detail, expected) in remixDetails {
            #expect(sidebarDetail(step: step, detail: detail) == expected)
        }

        #expect(sidebarDetail(step: .remixSave, detail: "再ミックスを保存中") == nil)
        #expect(sidebarDetail(
            step: .mastering(.noiseReturnGuard),
            detail: "3/8区間"
        ) == "3/8区間")
        #expect(sidebarDetail(step: .finalization, detail: "最終版を解析・保存中") == nil)

        let completed = StemModeProcessStepProgress(
            step: .remixGain,
            status: .completed,
            fraction: 1,
            detail: StemRemixRenderStage.gain.stemModeCompletedDetail
        )
        #expect(completed.stemModeSidebarDetail(stemCount: 6) == nil)
    }

    private func sidebarDetail(
        step: StemModeProcessStep,
        detail: String
    ) -> String? {
        StemModeProcessStepProgress(
            step: step,
            status: .running,
            fraction: 0.5,
            detail: detail
        )
        .stemModeSidebarDetail(stemCount: 6)
    }
}
