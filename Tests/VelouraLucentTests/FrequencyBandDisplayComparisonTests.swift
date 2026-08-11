import Testing
@testable import VelouraLucent

struct FrequencyBandDisplayComparisonTests {
    @Test
    func displayedValuesAndAllDeltasUseTheSameHundredths() throws {
        let comparison = FrequencyBandDisplayComparison(
            input: 19.07,
            corrected: 19.78,
            mastered: 19.25
        )

        #expect(comparison.input == 19.07)
        #expect(comparison.corrected == 19.78)
        #expect(comparison.mastered == 19.25)
        #expect(comparison.correctionDelta == 0.71)
        #expect(comparison.masteringDelta == -0.53)
        #expect(comparison.masteredDeltaFromInput == 0.18)
    }

    @Test
    func valuesAreRoundedBeforeDeltasAreCalculated() throws {
        let comparison = FrequencyBandDisplayComparison(
            input: 19.074,
            corrected: 19.786,
            mastered: 19.254
        )

        #expect(comparison.input == 19.07)
        #expect(comparison.corrected == 19.79)
        #expect(comparison.mastered == 19.25)
        #expect(comparison.correctionDelta == 0.72)
        #expect(comparison.masteringDelta == -0.54)
        #expect(comparison.masteredDeltaFromInput == 0.18)
    }

    @Test
    func missingStagesRemainUnavailable() throws {
        let comparison = FrequencyBandDisplayComparison(
            input: 19.07,
            corrected: nil,
            mastered: nil
        )

        #expect(comparison.corrected == nil)
        #expect(comparison.mastered == nil)
        #expect(comparison.correctionDelta == nil)
        #expect(comparison.masteringDelta == nil)
        #expect(comparison.masteredDeltaFromInput == nil)
    }
}
