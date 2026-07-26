import Testing
@testable import VelouraLucent

struct StemModePresentationTextTests {
    @Test
    func onlyInputCorrectedRemixAndFinalArePreviewable() {
        let corrected = StemArtifactKind.correctedRemix48000

        #expect(corrected.stemModeDisplayTitle == "補正後再ミックス")
        #expect(corrected.isStemModeUserExportable)
        #expect(corrected.isStemModePreviewable)
        #expect(StemArtifactKind.input44100.isStemModePreviewable)
        #expect(StemArtifactKind.finalMaster.isStemModePreviewable)
        #expect(!StemArtifactKind.rawStem(.vocals).isStemModePreviewable)
        #expect(!StemArtifactKind.correctedStem(.vocals).isStemModePreviewable)
        #expect(!StemArtifactKind.input44100.isStemModeUserExportable)
        #expect(StemArtifactKind.correctedStem(.vocals).isStemModeUserExportable)
        #expect(StemArtifactKind.finalMaster.isStemModeUserExportable)
    }

    @Test
    func exportabilityIncludesCorrectedRemixFourCorrectedStemsAndFinalMaster() {
        let exportable = [
            StemArtifactKind.correctedRemix48000,
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
        #expect(StemWorkflowStep.correctedRemix.title == "補正後再ミックス")
        #expect(StemWorkflowStep.validateCorrectedRemix.title == "補正後再ミックス検証")
        #expect(StemWorkflowValidationSubject.rawRemix.stemModeDisplayTitle == "raw再ミックス")
        #expect(
            StemWorkflowValidationSubject.correctedRemix.stemModeDisplayTitle
                == "補正後再ミックス"
        )
    }

    @Test
    func stageOutcomesDescribeStraightLineProcessing() {
        #expect(StemCorrectionStageGuardOutcome.completed.stemModeDisplayTitle == "工程内guardを含めて完了")
        #expect(StemCorrectionStageGuardOutcome.unchanged.stemModeDisplayTitle == "工程内判断により音声を維持")
        #expect(StemCorrectionStageGuardOutcome.notEvaluatedForSkippedStage.stemModeDisplayTitle == "工程省略・guard未評価")
    }
}
