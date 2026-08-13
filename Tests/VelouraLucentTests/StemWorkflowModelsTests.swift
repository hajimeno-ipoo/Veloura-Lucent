import Foundation
import Testing
@testable import VelouraLucent

struct StemWorkflowModelsTests {
    @Test
    func processingModesKeepStandardAndStemAsSeparateChoices() {
        #expect(ProcessingMode.allCases == [.standard, .stem])
        #expect(ProcessingMode.standard.title == "通常補正")
        #expect(ProcessingMode.stem.title == "Stem Mode")
    }

    @Test
    func stemProgressClampsOnlyDisplayFraction() {
        let below = StemWorkflowStepProgress(
            step: .separate,
            status: .running,
            fraction: -1
        )
        let above = StemWorkflowStepProgress(
            step: .separate,
            status: .running,
            fraction: 2
        )
        let invalid = StemWorkflowStepProgress(
            step: .separate,
            status: .running,
            fraction: .nan
        )

        #expect(below.fraction == 0)
        #expect(above.fraction == 1)
        #expect(invalid.fraction == 0)
    }

    @Test
    func artifactKindKeepsOnlyCurrentTemporaryAudioKindsDistinct() {
        let kinds: [StemArtifactKind] = [
            .input44100,
            .rawStem(.vocals),
            .correctedStem(.vocals),
            .correctedPureSum48000,
            .finalMaster,
        ]
        #expect(Set(kinds).count == 5)
    }

    @Test
    func displayStepsExposeTransientProtectionAndActualRemixOrder() {
        let roles = StemProductionModelProfile.profile(for: .htdemucs).sourceOrder
        #expect(
            StemModeProcessStep.correctionSteps(for: roles).contains(
                .roleTransientRecovery(.drums)
            )
        )
        #expect(
            !StemModeProcessStep.correctionSteps(for: roles).contains(
                .roleTransientRecovery(.vocals)
            )
        )
        #expect(StemModeProcessStep.remixSteps == [
            .automaticRemixPlan,
            .remixGain,
            .remixMasking,
            .remixPan,
            .remixReverbSend,
            .remixSharedReverb,
            .remixDryReturnMix,
            .remixSave,
            .remixValidation,
        ])
    }
}
