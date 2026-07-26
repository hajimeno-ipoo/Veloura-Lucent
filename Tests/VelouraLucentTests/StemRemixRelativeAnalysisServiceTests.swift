import Foundation
import Testing
@testable import VelouraLucent

struct StemRemixRelativeAnalysisServiceTests {
    @Test("絶対漏れ量ではなく今回のrawからのStem間共有成分変化を記録する")
    func recordsRelativeSharedComponentChange() throws {
        let first = makeRelativeSignal(frequency: 220)
        let second = makeRelativeSignal(frequency: 330)
        let correctedSecond = AudioSignal(
            channels: zip(second.channels, first.channels).map { secondChannel, firstChannel in
                zip(secondChannel, firstChannel).map { $0 + $1 * 0.2 }
            },
            sampleRate: second.sampleRate
        )

        let measurements = StemRemixRelativeAnalysisService().measurements(
            rawStemsByRole: [.vocals: first, .other: second],
            correctedStemsByRole: [.vocals: first, .other: correctedSecond],
            evaluations: []
        )
        let change = try #require(measurements.first {
            $0.id == "corrected-remix.shared-component.other-vocals.change"
        })

        #expect(change.value > 0)
        #expect(change.unit == "ratio")
        #expect(measurements.allSatisfy { !$0.id.contains("absolute-leakage") })
    }
}

private func makeRelativeSignal(frequency: Double) -> AudioSignal {
    let sampleRate = 48_000.0
    let mono = (0..<4_096).map { index in
        Float(0.2 * sin(2 * .pi * frequency * Double(index) / sampleRate))
    }
    return AudioSignal(channels: [mono, mono], sampleRate: sampleRate)
}
