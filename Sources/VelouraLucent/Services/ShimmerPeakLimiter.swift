import Foundation

struct ShimmerPeakLimiter: Sendable {
    let settings: CorrectionSettings

    func process(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot? = nil,
        logger: AudioProcessingLogger? = nil,
        maxPasses: Int = 5
    ) -> AudioSignal {
        let rules = InternalAudioJudgementPolicy.shimmerLimitRules(improvementDB: targetImprovementDB)
        let requiredIDs = rules.map(\.id)
        let referenceMeasurements = requiredIDs.allSatisfy { referenceMeasurements?.comparableLevel(for: $0) != nil }
            ? referenceMeasurements!
            : NoiseMeasurementService.analyze(signal: reference, ids: requiredIDs)
        return adaptiveLimit(
            signal: signal,
            referenceMeasurements: referenceMeasurements,
            rules: rules,
            logger: logger,
            maxPasses: maxPasses
        )
    }

    private var targetImprovementDB: Double {
        if settings.correctionIntensity >= 0.65 { return 1.0 }
        if settings.correctionIntensity >= 0.45 { return 0.35 }
        return -0.2
    }

    private func adaptiveLimit(
        signal: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        rules: [ShimmerLimitRule],
        logger: AudioProcessingLogger?,
        maxPasses: Int = 5
    ) -> AudioSignal {
        var currentSignal = signal
        var measurementCount = 0
        var previousExcessDB: Double?
        let adaptivePasses = min(maxPasses, settings.correctionIntensity >= 0.70 ? 3 : 2)
        let analysisPlan = shimmerProbePlan(for: signal)

        logger?.log("シマー制限: 短時間判定を開始")
        if analysisPlan.usesRepresentativeWindows {
            logger?.detail("\(analysisPlan.selectedWindowCount)/\(analysisPlan.totalWindowCount) 区間を確認中", for: .shimmerPeakLimit)
            logger?.log("シマー制限/軽量測定: \(analysisPlan.selectedWindowCount)/\(analysisPlan.totalWindowCount)区間")
        }
        for _ in 0..<adaptivePasses {
            let currentMeasurements = shimmerProbe(signal: currentSignal, plan: analysisPlan)
            measurementCount += 1
            logger?.detail("\(measurementCount)/\(adaptivePasses) 回目を確認中", for: .shimmerPeakLimit)
            logger?.log("シマー制限/測定: \(measurementCount)/\(adaptivePasses)")

            let strongestExcess = rules
                .compactMap { rule -> (rule: ShimmerLimitRule, excessDB: Double)? in
                    guard let reference = referenceMeasurements.comparableLevel(for: rule.id),
                          let current = currentMeasurements.comparableLevel(for: rule.id)
                    else { return nil }
                    let target = reference - rule.improvementDB
                    return (rule, max(0, current - target))
                }
                .max { $0.excessDB < $1.excessDB }

            guard let strongestExcess, strongestExcess.excessDB > 0.1 else {
                let residualSmoothed = residualShortEventLimit(signal: currentSignal, rules: rules)
                logger?.log("シマー制限/測定回数: \(measurementCount)")
                logger?.log("シマー制限: 目標到達 - 短時間シマーのみ確認")
                logger?.log("シマー制限: 完了")
                return residualSmoothed
            }
            if let previousExcessDB, previousExcessDB - strongestExcess.excessDB < 0.35 {
                logger?.log("シマー制限/測定回数: \(measurementCount)")
                logger?.log("シマー制限: 改善量が小さいため終了")
                return currentSignal
            }
            previousExcessDB = strongestExcess.excessDB

            let gain = powf(10, -Float(min(strongestExcess.excessDB * reductionScale, maxReductionPerPassDB)) / 20)
            let sampleRate = currentSignal.sampleRate
            let channels = mapChannelsConcurrently(currentSignal.channels) {
                processChannel(
                    $0,
                    sampleRate: sampleRate,
                    lower: strongestExcess.rule.lowerFrequency,
                    upper: strongestExcess.rule.upperFrequency,
                    gain: gain
                )
            }
            currentSignal = AudioSignal(channels: channels, sampleRate: sampleRate)
        }

        if settings.correctionIntensity >= 0.65,
           let finalCorrection = fullRangeCorrection(
            signal: currentSignal,
            referenceMeasurements: referenceMeasurements,
            rules: rules
           ) {
            logger?.log("シマー制限/最終確認: 全体測定")
            logger?.log("シマー制限: 最終確認で短時間シマーを追加補正")
            let sampleRate = currentSignal.sampleRate
            let channels = mapChannelsConcurrently(currentSignal.channels) {
                processChannel(
                    $0,
                    sampleRate: sampleRate,
                    lower: finalCorrection.rule.lowerFrequency,
                    upper: finalCorrection.rule.upperFrequency,
                    gain: finalCorrection.gain
                )
            }
            currentSignal = AudioSignal(channels: channels, sampleRate: sampleRate)
        }

        logger?.log("シマー制限/測定回数: \(measurementCount)")
        logger?.log("シマー制限: 安全上限に到達")
        return currentSignal
    }

    private func fullRangeCorrection(
        signal: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        rules: [ShimmerLimitRule]
    ) -> (rule: ShimmerLimitRule, gain: Float)? {
        let currentMeasurements = NoiseMeasurementService.analyze(signal: signal, ids: rules.map(\.id))
        guard let strongestExcess = rules
            .compactMap({ rule -> (rule: ShimmerLimitRule, excessDB: Double)? in
                guard let reference = referenceMeasurements.comparableLevel(for: rule.id),
                      let current = currentMeasurements.comparableLevel(for: rule.id)
                else { return nil }
                let target = reference - rule.improvementDB
                return (rule, max(0, current - target))
            })
            .max(by: { $0.excessDB < $1.excessDB }),
            strongestExcess.excessDB > 0.1
        else {
            return nil
        }
        let gain = powf(10, -Float(min(strongestExcess.excessDB * reductionScale, maxReductionPerPassDB)) / 20)
        return (strongestExcess.rule, gain)
    }

    private func residualShortEventLimit(signal: AudioSignal, rules: [ShimmerLimitRule]) -> AudioSignal {
        let residualReductionDB = min(max(1.2, targetImprovementDB), maxReductionPerPassDB)
        let gain = powf(10, -Float(residualReductionDB) / 20)
        let sampleRate = signal.sampleRate
        var currentSignal = signal
        for rule in rules {
            let channels = mapChannelsConcurrently(currentSignal.channels) {
                processChannel(
                    $0,
                    sampleRate: sampleRate,
                    lower: rule.lowerFrequency,
                    upper: rule.upperFrequency,
                    gain: gain
                )
            }
            currentSignal = AudioSignal(channels: channels, sampleRate: sampleRate)
        }
        return currentSignal
    }

    private var maxReductionPerPassDB: Double {
        InternalAudioJudgementPolicy.shimmerMaxReductionPerPassDB(correctionIntensity: settings.correctionIntensity)
    }

    private var reductionScale: Double {
        InternalAudioJudgementPolicy.shimmerReductionScale(correctionIntensity: settings.correctionIntensity)
    }

    private struct ShimmerProbePlan {
        let ranges: [Range<Int>]
        let totalWindowCount: Int

        var selectedWindowCount: Int { ranges.count }
        var usesRepresentativeWindows: Bool {
            totalWindowCount > ranges.count
        }
    }

    private struct ShimmerProbe {
        let hiss: Double
        let shimmer: Double

        func comparableLevel(for id: String) -> Double? {
            switch id {
            case "hiss": hiss
            case "shimmer": shimmer
            default: nil
            }
        }
    }

    private func shimmerProbePlan(for signal: AudioSignal) -> ShimmerProbePlan {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return ShimmerProbePlan(ranges: [], totalWindowCount: 0)
        }
        let windowSize = max(Int(signal.sampleRate), 1)
        let totalWindowCount = max(1, Int(ceil(Double(mono.count) / Double(windowSize))))
        guard totalWindowCount > 45 else {
            return ShimmerProbePlan(ranges: [mono.indices], totalWindowCount: 1)
        }

        let probeCount = min(24, totalWindowCount)
        let selectedCount = min(8, probeCount)
        let windowStride = max(1, totalWindowCount / probeCount)
        let candidates = stride(from: 0, to: totalWindowCount, by: windowStride).prefix(probeCount).map { windowIndex in
            let start = min(windowIndex * windowSize, mono.count)
            let end = min(start + windowSize, mono.count)
            return (range: start..<end, score: rmsEnergy(mono[start..<end]))
        }
        let selected = candidates
            .sorted { $0.score > $1.score }
            .prefix(selectedCount)
            .map { $0.range }
            .sorted { $0.lowerBound < $1.lowerBound }
        return ShimmerProbePlan(ranges: selected, totalWindowCount: totalWindowCount)
    }

    private func shimmerProbe(signal: AudioSignal, plan: ShimmerProbePlan) -> ShimmerProbe {
        let mono = signal.monoMixdown()
        let analysisMono = representativeSamples(from: mono, ranges: plan.ranges)
        guard !analysisMono.isEmpty else {
            return ShimmerProbe(hiss: -120, shimmer: -120)
        }

        let loudness = MasteringAnalysisService.integratedLoudness(
            signal: AudioSignal(channels: [analysisMono], sampleRate: signal.sampleRate)
        )
        let gain = loudness.isFinite && loudness > -69
            ? powf(10, (-23 - loudness) / 20)
            : 1
        let comparable = analysisMono.map { $0 * gain }
        let hissBand = bandPass(comparable, lower: 8_000, upper: min(20_000, signal.sampleRate * 0.5 - 100), sampleRate: signal.sampleRate)
        let shimmerBand = bandPass(comparable, lower: 8_000, upper: min(14_000, signal.sampleRate * 0.5 - 100), sampleRate: signal.sampleRate)
        return ShimmerProbe(
            hiss: rmsDB(hissBand),
            shimmer: transientPeakDB(shimmerBand, sampleRate: signal.sampleRate)
        )
    }

    private func representativeSamples(from mono: [Float], ranges: [Range<Int>]) -> [Float] {
        guard !mono.isEmpty else { return [] }
        guard !(ranges.count == 1 && ranges[0] == mono.indices) else { return mono }

        var samples: [Float] = []
        samples.reserveCapacity(ranges.reduce(0) { $0 + $1.count })
        for range in ranges {
            samples.append(contentsOf: mono[range])
        }
        return samples
    }

    private func bandPass(_ samples: [Float], lower: Double, upper: Double, sampleRate: Double) -> [Float] {
        guard lower < upper, upper < sampleRate * 0.5 else {
            return Array(repeating: 0, count: samples.count)
        }
        return SpectralDSP.lowPass(
            SpectralDSP.highPass(samples, cutoff: lower, sampleRate: sampleRate),
            cutoff: upper,
            sampleRate: sampleRate
        )
    }

    private func transientPeakDB(_ samples: [Float], sampleRate: Double) -> Double {
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        let frames = frameRMS(samples, frameSize: frameSize, hopSize: hopSize)
        guard frames.count >= 4 else { return rmsDB(samples) }
        return percentile(frames, 0.95)
    }

    private func frameRMS(_ samples: [Float], frameSize: Int, hopSize: Int) -> [Double] {
        guard !samples.isEmpty else { return [] }
        if samples.count <= frameSize {
            return [rmsDB(samples)]
        }

        var values: [Double] = []
        var start = 0
        while start + frameSize <= samples.count {
            values.append(10 * log10(max(rmsEnergy(samples[start..<(start + frameSize)]), 1e-12)))
            start += hopSize
        }
        return values
    }

    private func rmsDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        return 10 * log10(max(rmsEnergy(samples[...]), 1e-12))
    }

    private func rmsEnergy(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
    }

    private func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(round(Double(sorted.count - 1) * percentile))))
        return sorted[index]
    }

    private func processChannel(_ channel: [Float], sampleRate: Double, lower: Double, upper: Double, gain: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 2 else { return channel }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let startBin = bin(for: lower, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        let endBin = bin(for: min(upper, sampleRate * 0.5 - 100), frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        guard endBin > startBin else { return channel }

        let eventEnergy = smoothedEnergy(
            bandEnergy(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep),
            radius: 2
        )
        let threshold = transientThreshold(for: eventEnergy)
        guard threshold > 1e-9 else { return channel }

        let shortEventFrameLimit = max(3, Int((sampleRate * 0.16 / Double(spectrogram.hopSize)).rounded(.up)))
        let requestedReduction = clamped(1 - gain, min: 0, max: 0.60)
        var didReduce = false

        for frameIndex in 0..<spectrogram.frameCount {
            let eventAmount = shortEventPeakAmount(
                in: eventEnergy,
                frameIndex: frameIndex,
                threshold: threshold,
                maxEventFrames: shortEventFrameLimit
            )
            guard eventAmount > 0 else { continue }

            for binIndex in startBin...endBin {
                let frequency = Double(binIndex) * frequencyStep
                let reduction = requestedReduction
                    * (0.35 + eventAmount * 0.65)
                    * frequencyWeight(for: frequency)
                guard reduction > 0 else { continue }
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: max(0.25, 1 - reduction))
                didReduce = true
            }
        }

        guard didReduce else { return channel }
        return preserveUltraAir(original: channel, processed: SpectralDSP.istft(spectrogram), sampleRate: sampleRate)
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
        let upper = SpectralDSP.percentile(energy, 82)
        return max(median * 1.45, upper)
    }

    private func shortEventPeakAmount(in energy: [Float], frameIndex: Int, threshold: Float, maxEventFrames: Int) -> Float {
        guard energy.indices.contains(frameIndex), threshold > 1e-9 else { return 0 }
        let current = energy[frameIndex]
        guard current > threshold else { return 0 }
        let eventRange = aboveThresholdRange(in: energy, containing: frameIndex, threshold: threshold)
        guard eventRange.count <= maxEventFrames else { return 0 }
        let surroundingMean = surroundingMeanEnergy(in: energy, excluding: eventRange, radius: max(3, maxEventFrames))
        let localThreshold = max(threshold, surroundingMean * 1.22)
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

    private func frequencyWeight(for frequency: Double) -> Float {
        if frequency < 10_000 { return 0.45 }
        if frequency < 12_000 { return 0.80 }
        if frequency < 16_000 { return 1.00 }
        return 0.70
    }

    private func preserveUltraAir(original: [Float], processed: [Float], sampleRate: Double) -> [Float] {
        guard original.count == processed.count, sampleRate * 0.5 > 16_200 else { return processed }
        let originalUltra = SpectralDSP.highPass(original, cutoff: 16_000, sampleRate: sampleRate)
        let processedUltra = SpectralDSP.highPass(processed, cutoff: 16_000, sampleRate: sampleRate)
        return processed.indices.map { index in
            processed[index] - processedUltra[index] + originalUltra[index]
        }
    }

    private func bin(for frequency: Double, frequencyStep: Double, maxBin: Int) -> Int {
        min(max(Int(frequency / frequencyStep), 0), maxBin)
    }
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.min(maxValue, Swift.max(minValue, value))
}
