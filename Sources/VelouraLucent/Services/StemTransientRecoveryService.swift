import Foundation

enum StemTransientRecoveryError: LocalizedError, Equatable, Sendable {
    case structuralMismatch

    var errorDescription: String? {
        switch self {
        case .structuralMismatch:
            "トランジェント回復へ渡されたraw Stemと補正済みStemの構造が一致しません。"
        }
    }
}

/// raw Stemに実在するドラムの短いアタックだけを比較基準にし、
/// 補正で失われた高域差分をrawの包絡線を超えない範囲で戻します。
struct StemTransientRecoveryService: Sendable {
    func recover(
        role: StemRole,
        rawSignal: AudioSignal,
        correctedSignal: AudioSignal
    ) throws -> AudioSignal {
        guard structurallyMatches(rawSignal, correctedSignal) else {
            throw StemTransientRecoveryError.structuralMismatch
        }
        guard role == .drums, rawSignal.channels != correctedSignal.channels else {
            return correctedSignal
        }

        let rawMono = rawSignal.monoMixdown()
        let correctedMono = correctedSignal.monoMixdown()
        let rawTransient = transientBand(rawMono, sampleRate: rawSignal.sampleRate)
        let correctedTransient = transientBand(correctedMono, sampleRate: rawSignal.sampleRate)
        let rawEnvelope = peakEnvelope(rawTransient, sampleRate: rawSignal.sampleRate)
        let correctedEnvelope = peakEnvelope(correctedTransient, sampleRate: rawSignal.sampleRate)
        let activeFloor = percentile(rawEnvelope, 65)
        guard activeFloor > Float.leastNormalMagnitude else {
            return correctedSignal
        }

        var recoveryRatio = Array(repeating: Float.zero, count: rawSignal.frameCount)
        for index in recoveryRatio.indices {
            let rawLevel = rawEnvelope[index]
            guard rawLevel > activeFloor else { continue }
            let missing = max(0, rawLevel - correctedEnvelope[index])
            recoveryRatio[index] = min(1, missing / max(rawLevel, 1e-9))
        }
        guard recoveryRatio.contains(where: { $0 > 0 }) else {
            return correctedSignal
        }

        let smoothedRatio = smoothRecoveryRatio(
            recoveryRatio,
            sampleRate: rawSignal.sampleRate
        )
        let channels = rawSignal.channels.indices.map { channelIndex in
            let rawChannel = rawSignal.channels[channelIndex]
            let correctedChannel = correctedSignal.channels[channelIndex]
            let rawBand = transientBand(rawChannel, sampleRate: rawSignal.sampleRate)
            let correctedBand = transientBand(
                correctedChannel,
                sampleRate: rawSignal.sampleRate
            )
            return rawChannel.indices.map { index in
                let missingComponent = rawBand[index] - correctedBand[index]
                guard abs(rawBand[index]) > abs(correctedBand[index]),
                      rawBand[index] * missingComponent > 0 else {
                    return correctedChannel[index]
                }
                let proposed = correctedChannel[index]
                    + missingComponent * smoothedRatio[index]
                let rawLimit = max(abs(rawChannel[index]), abs(correctedChannel[index]))
                return min(max(proposed, -rawLimit), rawLimit)
            }
        }
        return AudioSignal(channels: channels, sampleRate: rawSignal.sampleRate)
    }

    private func structurallyMatches(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channels.count == rhs.channels.count
            && lhs.frameCount == rhs.frameCount
            && lhs.channels.allSatisfy { $0.count == lhs.frameCount }
            && rhs.channels.allSatisfy { $0.count == rhs.frameCount }
    }

    private func transientBand(_ samples: [Float], sampleRate: Double) -> [Float] {
        let upper = min(12_000, sampleRate * 0.5 - 100)
        guard upper > 1_200 else { return samples }
        return SpectralDSP.lowPass(
            SpectralDSP.highPass(samples, cutoff: 1_200, sampleRate: sampleRate),
            cutoff: upper,
            sampleRate: sampleRate
        )
    }

    private func peakEnvelope(_ samples: [Float], sampleRate: Double) -> [Float] {
        let release = expf(-1 / max(Float(sampleRate) * 0.012, 1))
        var envelope = Array(repeating: Float.zero, count: samples.count)
        var current: Float = 0
        for index in samples.indices {
            let level = abs(samples[index])
            current = level >= current ? level : current * release
            envelope[index] = current
        }
        return envelope
    }

    private func smoothRecoveryRatio(_ values: [Float], sampleRate: Double) -> [Float] {
        let attack = expf(-1 / max(Float(sampleRate) * 0.0015, 1))
        let release = expf(-1 / max(Float(sampleRate) * 0.018, 1))
        var output = Array(repeating: Float.zero, count: values.count)
        var current: Float = 0
        for index in values.indices {
            let coefficient = values[index] > current ? attack : release
            current = coefficient * current + (1 - coefficient) * values[index]
            output[index] = current
        }
        return output
    }

    private func percentile(_ values: [Float], _ percentile: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = min(
            max(Int(Float(sorted.count - 1) * percentile / 100), 0),
            sorted.count - 1
        )
        return sorted[position]
    }
}
