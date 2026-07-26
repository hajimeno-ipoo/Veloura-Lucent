import Foundation

/// raw／補正後Stemの関係を、今回のrunだけを基準に記録します。
///
/// 正解isolated Stemを持たないため絶対漏れ量は名乗らず、Stem間の共有成分が補正前後で
/// どう変化したかだけを測定します。測定値から候補選択や音質合否は行いません。
struct StemRemixRelativeAnalysisService: Sendable {
    func measurements(
        rawStemsByRole: [StemRole: AudioSignal],
        correctedStemsByRole: [StemRole: AudioSignal],
        evaluations: [StemWorkflowStemEvaluation]
    ) -> [StemValidationMeasurement] {
        var measurements: [StemValidationMeasurement] = []
        let roles = StemRole.allCases

        for role in roles {
            guard let raw = rawStemsByRole[role],
                  let corrected = correctedStemsByRole[role],
                  structurallyMatches(raw, corrected) else {
                continue
            }
            measurements.append(StemValidationMeasurement(
                id: "corrected-remix.role-delta.\(role.rawValue).rms-db",
                value: rmsDeltaDB(raw: raw, corrected: corrected),
                unit: "dB"
            ))
            if let evaluation = evaluations.first(where: { $0.role == role }) {
                for record in evaluation.stageGuards where record.outcome != .completed
                    && record.outcome != .unchanged
                    && record.outcome != .notEvaluatedForSkippedStage {
                    measurements.append(StemValidationMeasurement(
                        id: "corrected-remix.guard-action.\(role.rawValue).\(record.stage.rawValue).\(record.outcome.rawValue)",
                        value: 1,
                        unit: "flag"
                    ))
                }
            }
        }

        for firstIndex in roles.indices {
            for secondIndex in roles.indices where secondIndex > firstIndex {
                let firstRole = roles[firstIndex]
                let secondRole = roles[secondIndex]
                guard let rawFirst = rawStemsByRole[firstRole],
                      let rawSecond = rawStemsByRole[secondRole],
                      let correctedFirst = correctedStemsByRole[firstRole],
                      let correctedSecond = correctedStemsByRole[secondRole],
                      let rawShared = sharedComponentCorrelation(rawFirst, rawSecond),
                      let correctedShared = sharedComponentCorrelation(correctedFirst, correctedSecond) else {
                    continue
                }
                let prefix = "corrected-remix.shared-component.\(firstRole.rawValue)-\(secondRole.rawValue)"
                measurements.append(StemValidationMeasurement(
                    id: "\(prefix).raw",
                    value: rawShared,
                    unit: "ratio"
                ))
                measurements.append(StemValidationMeasurement(
                    id: "\(prefix).corrected",
                    value: correctedShared,
                    unit: "ratio"
                ))
                measurements.append(StemValidationMeasurement(
                    id: "\(prefix).change",
                    value: correctedShared - rawShared,
                    unit: "ratio"
                ))
            }
        }
        return measurements
    }

    private func sharedComponentCorrelation(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Double? {
        guard structurallyMatches(lhs, rhs) else { return nil }
        let lhsMono = lhs.monoMixdown()
        let rhsMono = rhs.monoMixdown()
        return normalizedDot(lhsMono, rhsMono).map(abs)
    }

    private func rmsDeltaDB(raw: AudioSignal, corrected: AudioSignal) -> Double {
        var rawEnergy = 0.0
        var correctedEnergy = 0.0
        for channel in raw.channels {
            for sample in channel {
                rawEnergy += Double(sample) * Double(sample)
            }
        }
        for channel in corrected.channels {
            for sample in channel {
                correctedEnergy += Double(sample) * Double(sample)
            }
        }
        return 10 * log10(max(correctedEnergy, Double.leastNormalMagnitude)
            / max(rawEnergy, Double.leastNormalMagnitude))
    }

    private func normalizedDot(_ lhs: [Float], _ rhs: [Float]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot = 0.0
        var lhsEnergy = 0.0
        var rhsEnergy = 0.0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            guard left.isFinite, right.isFinite else { return nil }
            dot += left * right
            lhsEnergy += left * left
            rhsEnergy += right * right
        }
        guard lhsEnergy > 0, rhsEnergy > 0 else { return nil }
        return max(-1, min(1, dot / sqrt(lhsEnergy * rhsEnergy)))
    }

    private func structurallyMatches(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channels.count == rhs.channels.count
            && lhs.frameCount == rhs.frameCount
            && !lhs.channels.isEmpty
    }
}
