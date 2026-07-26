import Foundation
import Testing
@testable import VelouraLucent

struct StemRemixSafetyGuardServiceTests {
    @Test("相関値が変わっただけではrawへ戻さない")
    func keepsNonInvertedCorrection() {
        let raw = makeSafetySignal()
        let corrected = AudioSignal(
            channels: [
                raw.channels[0].map { $0 * 0.8 },
                raw.channels[1].map { $0 * 0.7 },
            ],
            sampleRate: raw.sampleRate
        )
        let result = StemRemixSafetyGuardService().protect(
            rawStemsByRole: [.vocals: raw],
            correctedStemsByRole: [.vocals: corrected]
        )

        #expect(result.rawFallbackReasons.isEmpty)
        #expect(result.stemsByRole[.vocals]?.channels == corrected.channels)
    }

    @Test("明確な全体極性反転だけを該当Stemのrawへ戻す")
    func restoresOnlyInvertedRole() {
        let raw = makeSafetySignal()
        let inverted = AudioSignal(
            channels: raw.channels.map { $0.map { -$0 } },
            sampleRate: raw.sampleRate
        )
        let result = StemRemixSafetyGuardService().protect(
            rawStemsByRole: [.bass: raw],
            correctedStemsByRole: [.bass: inverted]
        )

        #expect(result.rawFallbackReasons[.bass] != nil)
        #expect(result.stemsByRole[.bass]?.channels == raw.channels)
    }
}

private func makeSafetySignal() -> AudioSignal {
    let sampleRate = 48_000.0
    let left = (0..<4_096).map { index in
        Float(sin(2 * .pi * 220 * Double(index) / sampleRate))
    }
    let right = (0..<4_096).map { index in
        Float(0.8 * sin(2 * .pi * 330 * Double(index) / sampleRate + 0.1))
    }
    return AudioSignal(channels: [left, right], sampleRate: sampleRate)
}
