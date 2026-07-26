import Foundation

struct StemRemixSafetyGuardResult: Sendable {
    let stemsByRole: [StemRole: AudioSignal]
    let rawFallbackReasons: [StemRole: String]
}

protocol StemRemixSafetyGuarding: Sendable {
    func protect(
        rawStemsByRole: [StemRole: AudioSignal],
        correctedStemsByRole: [StemRole: AudioSignal]
    ) -> StemRemixSafetyGuardResult
}

/// 再ミックス直前に、明確な全体極性反転だけをStem単位で防ぎます。
///
/// 相関値の大小で音質を順位付けしません。符号が反転した場合だけ、当該Stemをrawへ戻します。
/// 曖昧な相関変化、ステレオ幅の変化、帯域差は自動fallbackの根拠にしません。
struct StemRemixSafetyGuardService: StemRemixSafetyGuarding, Sendable {
    func protect(
        rawStemsByRole: [StemRole: AudioSignal],
        correctedStemsByRole: [StemRole: AudioSignal]
    ) -> StemRemixSafetyGuardResult {
        var selected = correctedStemsByRole
        var reasons: [StemRole: String] = [:]

        for role in StemRole.allCases {
            guard let raw = rawStemsByRole[role],
                  let corrected = correctedStemsByRole[role] else {
                continue
            }
            guard structurallyMatches(raw, corrected) else {
                selected[role] = raw
                reasons[role] = "補正後Stemの構造がraw Stemと一致しないためrawを使用"
                continue
            }
            guard hasClearPolarityInversion(raw: raw, corrected: corrected) else {
                continue
            }
            selected[role] = raw
            reasons[role] = "raw Stemに対するチャンネルまたはmid/sideの全体極性反転を検出したためrawを使用"
        }
        return StemRemixSafetyGuardResult(
            stemsByRole: selected,
            rawFallbackReasons: reasons
        )
    }

    private func hasClearPolarityInversion(raw: AudioSignal, corrected: AudioSignal) -> Bool {
        for channelIndex in raw.channels.indices {
            if let correlation = normalizedDot(
                raw.channels[channelIndex],
                corrected.channels[channelIndex]
            ), correlation < 0 {
                return true
            }
        }

        let rawMid = zip(raw.channels[0], raw.channels[1]).map { ($0 + $1) * 0.5 }
        let correctedMid = zip(corrected.channels[0], corrected.channels[1]).map { ($0 + $1) * 0.5 }
        if let correlation = normalizedDot(rawMid, correctedMid), correlation < 0 {
            return true
        }
        let rawSide = zip(raw.channels[0], raw.channels[1]).map { ($0 - $1) * 0.5 }
        let correctedSide = zip(corrected.channels[0], corrected.channels[1]).map { ($0 - $1) * 0.5 }
        return normalizedDot(rawSide, correctedSide).map { $0 < 0 } ?? false
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
            && lhs.channels.count == 2
            && rhs.channels.count == 2
            && lhs.frameCount == rhs.frameCount
            && lhs.channels.enumerated().allSatisfy { index, channel in
                channel.count == rhs.channels[index].count
                    && channel.allSatisfy(\.isFinite)
                    && rhs.channels[index].allSatisfy(\.isFinite)
            }
    }
}
