import Testing
@testable import VelouraLucent

struct StemModePresentationTextTests {
    @Test
    func inputPureSumRemixAndFinalArePreviewable() {
        let corrected = StemArtifactKind.correctedPureSum48000

        #expect(corrected.stemModeDisplayTitle == "補正済み純粋加算")
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
    func exportabilityIncludesCorrectedRemixFourCorrectedStemsAndFinalMaster() {
        let exportable = [
            StemArtifactKind.correctedPureSum48000,
            StemArtifactKind.remixed48000,
            StemArtifactKind.correctedStem(.drums),
            .correctedStem(.bass),
            .correctedStem(.other),
            .correctedStem(.vocals),
            .finalMaster,
        ]
        let internalOnly = [
            StemArtifactKind.input44100,
            .rawStem(.drums),
        ]

        #expect(exportable.allSatisfy { $0.isStemModeUserExportable })
        #expect(internalOnly.allSatisfy { !$0.isStemModeUserExportable })
    }

    @Test
    func correctionAndRemixWorkflowStepsHaveDistinctUserFacingTitles() {
        #expect(StemWorkflowStep.correctStems.title == "Stem別補正")
        #expect(StemWorkflowStep.validateCorrectedStems.title == "補正後Stem検証")
        #expect(StemWorkflowStep.correctedPureSum.title == "補正済み純粋加算")
        #expect(StemWorkflowStep.validateCorrectedPureSum.title == "補正済み純粋加算検証")
        #expect(StemWorkflowStep.remix.title == "Stem再ミックス")
        #expect(StemWorkflowStep.validateRemix.title == "Stem再ミックス検証")
        #expect(StemWorkflowValidationSubject.rawRemix.stemModeDisplayTitle == "raw再ミックス")
        #expect(
            StemWorkflowValidationSubject.correctedPureSum.stemModeDisplayTitle
                == "補正済み純粋加算"
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
}
