import Foundation

struct SibilanceShimmerGuard: Sendable {
    let settings: CorrectionSettings

    func process(signal: AudioSignal, intensityScale: Float = 1) -> AudioSignal {
        let defaults = settings.profile.settings
        let intensity = clamped(
            0.28
                + settings.highNaturalness * 0.34
                + settings.noiseDetectionSensitivity * 0.24
                + max(0, settings.correctionIntensity - defaults.correctionIntensity) * 0.44,
            min: 0.22,
            max: 0.86
        ) * clamped(intensityScale, min: 0.25, max: 1)
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate, intensity: intensity)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processChannel(_ channel: [Float], sampleRate: Double, intensity: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 2 else { return channel }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let affectedStartBin = bin(for: 5_000, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        let affectedEndBin = bin(for: 14_000, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        guard affectedEndBin > affectedStartBin else { return channel }

        let sibilanceEnergy = bandEnergy(in: spectrogram, lower: 5_000, upper: 9_000, frequencyStep: frequencyStep)
        let biteEnergy = bandEnergy(in: spectrogram, lower: 6_000, upper: 10_000, frequencyStep: frequencyStep)
        let shimmerEnergy = bandEnergy(in: spectrogram, lower: 10_000, upper: 14_000, frequencyStep: frequencyStep)
        let sibilanceEventEnergy = smoothedEnergy(sibilanceEnergy, radius: 3)
        let biteEventEnergy = smoothedEnergy(biteEnergy, radius: 3)
        let shimmerEventEnergy = smoothedEnergy(shimmerEnergy, radius: 3)
        let sibilanceThreshold = transientThreshold(for: sibilanceEventEnergy)
        let biteThreshold = transientThreshold(for: biteEventEnergy)
        let shimmerThreshold = transientThreshold(for: shimmerEventEnergy)
        guard sibilanceThreshold > 1e-9 || biteThreshold > 1e-9 || shimmerThreshold > 1e-9 else { return channel }
        let shortEventFrameLimit = max(3, Int((sampleRate * 0.16 / Double(spectrogram.hopSize)).rounded(.up)))

        var didReduce = false
        for frameIndex in 0..<spectrogram.frameCount {
            let sibilancePeak = shortEventPeakAmount(
                in: sibilanceEventEnergy,
                frameIndex: frameIndex,
                threshold: sibilanceThreshold,
                maxEventFrames: shortEventFrameLimit
            )
            let bitePeak = shortEventPeakAmount(
                in: biteEventEnergy,
                frameIndex: frameIndex,
                threshold: biteThreshold,
                maxEventFrames: shortEventFrameLimit
            )
            let shimmerPeak = shortEventPeakAmount(
                in: shimmerEventEnergy,
                frameIndex: frameIndex,
                threshold: shimmerThreshold,
                maxEventFrames: shortEventFrameLimit
            )
            guard sibilancePeak > 0 || bitePeak > 0 || shimmerPeak > 0 else { continue }

            for binIndex in affectedStartBin...affectedEndBin {
                let frequency = Double(binIndex) * frequencyStep
                let reduction = transientReduction(
                    frequency: frequency,
                    sibilancePeak: sibilancePeak,
                    bitePeak: bitePeak,
                    shimmerPeak: shimmerPeak,
                    intensity: intensity
                )
                guard reduction > 0 else { continue }
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: 1 - reduction)
                didReduce = true
            }
        }

        guard didReduce else { return channel }
        return SpectralDSP.istft(spectrogram)
    }

    private func bandEnergy(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> [Float] {
        let startBin = bin(for: lower, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        let endBin = bin(for: upper, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        guard endBin > startBin else {
            return Array(repeating: 0, count: spectrogram.frameCount)
        }

        var values = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            for binIndex in startBin...endBin {
                sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            values[frameIndex] = sum / Float(endBin - startBin + 1)
        }
        return values
    }

    private func smoothedEnergy(_ energy: [Float], radius: Int) -> [Float] {
        guard !energy.isEmpty, radius > 0 else { return energy }
        return energy.indices.map { index in
            let start = max(0, index - radius)
            let end = min(energy.count - 1, index + radius)
            let sum = energy[start...end].reduce(Float.zero, +)
            return sum / Float(end - start + 1)
        }
    }

    private func transientThreshold(for energy: [Float]) -> Float {
        guard !energy.isEmpty else { return 0 }
        let median = SpectralDSP.percentile(energy, 50)
        let upper = SpectralDSP.percentile(energy, 78)
        return max(median * 1.35, upper)
    }

    private func shortEventPeakAmount(in energy: [Float], frameIndex: Int, threshold: Float, maxEventFrames: Int) -> Float {
        guard energy.indices.contains(frameIndex), threshold > 1e-9 else { return 0 }
        let current = energy[frameIndex]
        guard current > threshold else { return 0 }
        let eventRange = aboveThresholdRange(in: energy, containing: frameIndex, threshold: threshold)
        guard eventRange.count <= maxEventFrames else { return 0 }
        let surroundingMean = surroundingMeanEnergy(in: energy, excluding: eventRange, radius: max(3, maxEventFrames / 2))
        let localThreshold = max(threshold, surroundingMean * 1.18)
        guard current > localThreshold else { return 0 }
        return min(1, (current - localThreshold) / max(current, 1e-6))
    }

    private func aboveThresholdRange(in energy: [Float], containing frameIndex: Int, threshold: Float) -> ClosedRange<Int> {
        var start = frameIndex
        while start > 0, energy[start - 1] > threshold {
            start -= 1
        }

        var end = frameIndex
        while end + 1 < energy.count, energy[end + 1] > threshold {
            end += 1
        }

        return start...end
    }

    private func surroundingMeanEnergy(in energy: [Float], excluding eventRange: ClosedRange<Int>, radius: Int) -> Float {
        guard !energy.isEmpty else { return 0 }
        var sum: Float = 0
        var count = 0
        let beforeStart = max(0, eventRange.lowerBound - radius)
        if beforeStart < eventRange.lowerBound {
            for index in beforeStart..<eventRange.lowerBound {
                sum += energy[index]
                count += 1
            }
        }

        let afterEnd = min(energy.count - 1, eventRange.upperBound + radius)
        if eventRange.upperBound < afterEnd {
            for index in (eventRange.upperBound + 1)...afterEnd {
                sum += energy[index]
                count += 1
            }
        }

        return count > 0 ? sum / Float(count) : 0
    }

    private func transientReduction(
        frequency: Double,
        sibilancePeak: Float,
        bitePeak: Float,
        shimmerPeak: Float,
        intensity: Float
    ) -> Float {
        let weightedPeak: Float
        let maxReduction: Float
        if frequency < 6_000 {
            weightedPeak = sibilancePeak * 0.90
            maxReduction = 0.42
        } else if frequency < 8_000 {
            weightedPeak = max(sibilancePeak * 1.08, bitePeak * 0.20)
            maxReduction = 0.58
        } else if frequency < 9_000 {
            weightedPeak = max(sibilancePeak * 0.12, bitePeak * 0.12)
            maxReduction = 0.04
        } else if frequency < 10_000 {
            weightedPeak = bitePeak * 0.22
            maxReduction = 0.08
        } else if frequency < 12_000 {
            weightedPeak = shimmerPeak * 0.24
            maxReduction = 0.08
        } else {
            weightedPeak = shimmerPeak * 0.46
            maxReduction = 0.14
        }
        return min(maxReduction, weightedPeak * intensity)
    }

    private func bin(for frequency: Double, frequencyStep: Double, maxBin: Int) -> Int {
        min(max(Int(frequency / frequencyStep), 0), maxBin)
    }
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.min(maxValue, Swift.max(minValue, value))
}
