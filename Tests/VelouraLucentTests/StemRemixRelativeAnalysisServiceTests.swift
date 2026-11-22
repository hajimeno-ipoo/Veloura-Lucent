import Foundation
import Testing
@testable import VelouraLucent

struct StemRemixRelativeAnalysisServiceTests {
    @Test(arguments: 0..<5)
    func sharedMonoKeepsPairwiseDoubleResultsAndSkippedPairs(caseIndex: Int) {
        var raw: [StemRole: AudioSignal] = [:]
        var corrected: [StemRole: AudioSignal] = [:]
        for (roleIndex, role) in StemRole.allCases.enumerated() {
            let mono: [Float]
            switch caseIndex {
            case 1:
                mono = roleIndex.isMultiple(of: 2) ? [1, -1e-8, -1] : [1, 1, 1]
            case 2:
                mono = [1e-23, -2e-23, 3e-23]
            case 3:
                mono = [0, -0.0, 0]
            default:
                mono = (0..<257).map { frame in
                    Float(sin(Double(frame * (roleIndex + 1)) * 0.013) * 0.2)
                }
            }
            var signal = AudioSignal(channels: [mono, mono.map { $0 * 0.73 }], sampleRate: 48_000)
            if caseIndex == 4 {
                if roleIndex == 0 { signal.sampleRate = 44_100 }
                if roleIndex == 1 { signal.channels = [mono] }
                if roleIndex == 2 { signal.channels = signal.channels.map { Array($0.dropLast()) } }
            }
            raw[role] = signal
            corrected[role] = AudioSignal(
                channels: signal.channels.map { $0.map { $0 * Float(roleIndex + 1) * 0.11 } },
                sampleRate: signal.sampleRate
            )
        }
        let actual = StemRemixRelativeAnalysisService().measurements(
            rawStemsByRole: raw,
            correctedStemsByRole: corrected,
            evaluations: []
        ).filter { $0.id.contains(".shared-component.") }
        let expected = scalarPairMeasurements(raw: raw, corrected: corrected)
        #expect(actual.map(\.id) == expected.map(\.id))
        #expect(actual.map(\.unit) == expected.map(\.unit))
        #expect(actual.map { $0.value.bitPattern } == expected.map { $0.value.bitPattern })
    }

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

/// Reference for the original pair-by-pair mixdown and frame-ordered Double accumulation.
private func scalarPairMeasurements(
    raw: [StemRole: AudioSignal],
    corrected: [StemRole: AudioSignal]
) -> [StemValidationMeasurement] {
    func correlation(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Double? {
        guard lhs.sampleRate == rhs.sampleRate,
              lhs.channels.count == rhs.channels.count,
              lhs.frameCount == rhs.frameCount,
              !lhs.channels.isEmpty else { return nil }
        let left = lhs.monoMixdown()
        let right = rhs.monoMixdown()
        guard left.count == right.count, !left.isEmpty else { return nil }
        var dot = 0.0
        var leftEnergy = 0.0
        var rightEnergy = 0.0
        for index in left.indices {
            let l = Double(left[index])
            let r = Double(right[index])
            guard l.isFinite, r.isFinite else { return nil }
            dot += l * r
            leftEnergy += l * l
            rightEnergy += r * r
        }
        guard leftEnergy > 0, rightEnergy > 0 else { return nil }
        return abs(max(-1, min(1, dot / sqrt(leftEnergy * rightEnergy))))
    }
    var result: [StemValidationMeasurement] = []
    let roles = StemRole.allCases
    for firstIndex in roles.indices {
        for secondIndex in roles.indices where secondIndex > firstIndex {
            let firstRole = roles[firstIndex]
            let secondRole = roles[secondIndex]
            guard let rawFirst = raw[firstRole], let rawSecond = raw[secondRole],
                  let correctedFirst = corrected[firstRole], let correctedSecond = corrected[secondRole],
                  let rawValue = correlation(rawFirst, rawSecond),
                  let correctedValue = correlation(correctedFirst, correctedSecond) else { continue }
            let prefix = "corrected-remix.shared-component.\(firstRole.rawValue)-\(secondRole.rawValue)"
            result.append(StemValidationMeasurement(id: "\(prefix).raw", value: rawValue, unit: "ratio"))
            result.append(StemValidationMeasurement(id: "\(prefix).corrected", value: correctedValue, unit: "ratio"))
            result.append(StemValidationMeasurement(id: "\(prefix).change", value: correctedValue - rawValue, unit: "ratio"))
        }
    }
    return result
}

private func makeRelativeSignal(frequency: Double) -> AudioSignal {
    let sampleRate = 48_000.0
    let mono = (0..<4_096).map { index in
        Float(0.2 * sin(2 * .pi * frequency * Double(index) / sampleRate))
    }
    return AudioSignal(channels: [mono, mono], sampleRate: sampleRate)
}
