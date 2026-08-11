import Foundation

struct FrequencyBandDisplayComparison: Sendable, Equatable {
    let input: Double
    let corrected: Double?
    let mastered: Double?

    init(input: Double, corrected: Double?, mastered: Double?) {
        self.input = Self.roundedForDisplay(input)
        self.corrected = corrected.map(Self.roundedForDisplay)
        self.mastered = mastered.map(Self.roundedForDisplay)
    }

    var correctionDelta: Double? {
        corrected.map { Self.roundedForDisplay($0 - input) }
    }

    var masteringDelta: Double? {
        guard let corrected, let mastered else { return nil }
        return Self.roundedForDisplay(mastered - corrected)
    }

    var masteredDeltaFromInput: Double? {
        mastered.map { Self.roundedForDisplay($0 - input) }
    }

    private static func roundedForDisplay(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }
}
