import Foundation

enum MasteringSignalMath {
    static func applyGain(signal: AudioSignal, gainDB: Double) -> AudioSignal {
        let gain = powf(10, Float(gainDB) / 20)
        let channels = signal.channels.map { channel in
            channel.map { $0 * gain }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    static func bandPass(_ samples: [Float], lower: Double, upper: Double, sampleRate: Double) -> [Float] {
        guard lower < upper, upper < sampleRate * 0.5 else {
            return Array(repeating: 0, count: samples.count)
        }
        return SpectralDSP.lowPass(
            SpectralDSP.highPass(samples, cutoff: lower, sampleRate: sampleRate),
            cutoff: upper,
            sampleRate: sampleRate
        )
    }

    static func steepBandPass(_ samples: [Float], lower: Double, upper: Double, sampleRate: Double) -> [Float] {
        guard lower < upper, upper < sampleRate * 0.5 else {
            return Array(repeating: 0, count: samples.count)
        }
        var filtered = samples
        for _ in 0..<4 {
            filtered = bandPass(filtered, lower: lower, upper: upper, sampleRate: sampleRate)
        }
        return filtered
    }

    static func rmsDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        return 10 * log10(max(rmsEnergy(samples[...]), 1e-12))
    }

    static func rmsEnergy(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
    }

    static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(round(Double(sorted.count - 1) * percentile))))
        return sorted[index]
    }

    static func bandRMSDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let upperBound = min(upper, signal.sampleRate * 0.5 - 100)
        guard lower < upperBound else { return -120 }
        let mono = signal.monoMixdown()
        let band = bandPass(mono, lower: lower, upper: upperBound, sampleRate: signal.sampleRate)
        return rmsDB(band)
    }

    static func bandBalanceDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        bandRMSDB(signal: signal, lower: lower, upper: upper) - rmsDB(signal.monoMixdown())
    }

    static func scaleBand(channel: [Float], sampleRate: Double, lower: Double, upper: Double, gain: Float) -> [Float] {
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(channel, cutoff: lower, sampleRate: sampleRate),
            cutoff: min(upper, sampleRate * 0.5 - 100),
            sampleRate: sampleRate
        )
        let reduction = 1 - gain
        return channel.indices.map { index in
            channel[index] - band[index] * reduction
        }
    }

    static func enforcePeakCeiling(signal: AudioSignal, peakCeilingDB: Float) -> AudioSignal {
        let peakCeiling = powf(10, peakCeilingDB / 20)
        var channels = applyLookaheadLimiter(signal.channels, peakCeiling: peakCeiling, sampleRate: signal.sampleRate)
        let peak = MasteringAnalysisService.approximateTruePeak(channels)
        if peak > peakCeiling {
            let trim = peakCeiling / peak
            channels = channels.map { $0.map { $0 * trim } }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    static func applyLookaheadLimiter(_ channels: [[Float]], peakCeiling: Float, sampleRate: Double) -> [[Float]] {
        guard let first = channels.first else { return channels }
        guard first.count > 0 else { return channels }

        let lookaheadSamples = max(16, Int(sampleRate * 0.003))
        let framePeaks = framePeakEnvelope(channels, frameCount: first.count)
        let futurePeaks = slidingMaximum(framePeaks, windowSize: lookaheadSamples + 1)
        var gain: Float = 1
        var limited = channels

        for index in 0..<first.count {
            let framePeak = futurePeaks[index]
            let desiredGain = framePeak > peakCeiling ? peakCeiling / max(framePeak, 1e-6) : 1
            if desiredGain < gain {
                gain = desiredGain
            } else {
                let reductionAmount = 1 - gain
                let releaseMs = 65 + reductionAmount * 240
                let releaseCoeff = expf(-1 / max(Float(sampleRate) * releaseMs * 0.001, 1))
                gain = min(1, gain * releaseCoeff + (1 - releaseCoeff))
            }

            for channelIndex in limited.indices where index < limited[channelIndex].count {
                limited[channelIndex][index] = limited[channelIndex][index] * gain
            }
        }

        return limited
    }

    static func framePeakEnvelope(_ channels: [[Float]], frameCount: Int) -> [Float] {
        (0..<frameCount).map { index in
            channels.reduce(Float.zero) { partial, channel in
                guard index < channel.count else { return partial }
                return max(partial, abs(channel[index]))
            }
        }
    }

    static func slidingMaximum(_ values: [Float], windowSize: Int) -> [Float] {
        guard !values.isEmpty else { return [] }
        let clampedWindow = max(1, windowSize)
        var deque: [Int] = []
        var maxima = Array(repeating: Float.zero, count: values.count)

        for index in stride(from: values.count - 1, through: 0, by: -1) {
            let upperBound = index + clampedWindow - 1
            while let first = deque.first, first > upperBound {
                deque.removeFirst()
            }
            while let last = deque.last, values[last] <= values[index] {
                deque.removeLast()
            }
            deque.append(index)
            maxima[index] = values[deque.first ?? index]
        }

        return maxima
    }

    static func gainDelta(forDB value: Float) -> Float {
        powf(10, value / 20) - 1
    }

    static func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.max(minValue, Swift.min(value, maxValue))
    }
}
