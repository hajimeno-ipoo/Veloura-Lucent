import Foundation

struct MasteringProcessor {
    func process(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings, logger: AudioProcessingLogger? = nil) -> AudioSignal {
        let dynamicsRetention = clamped(settings.dynamicsRetention, min: 0, max: 1)
        let finishingIntensity = clamped(settings.finishingIntensity, min: 0, max: 1)

        logger?.log(MasteringStep.tone.rawValue)
        var current = measure(label: "音色", logger: logger) {
            applyTone(signal: signal, analysis: analysis, settings: settings, finishingIntensity: finishingIntensity)
        }

        logger?.log(MasteringStep.deEss.rawValue)
        current = measure(label: "ディエッサー", logger: logger) {
            applyDeEsser(signal: current, analysis: analysis, settings: settings)
        }

        logger?.log(MasteringStep.dynamics.rawValue)
        current = measure(label: "ダイナミクス", logger: logger) {
            applyMultibandCompression(
                signal: current,
                analysis: analysis,
                settings: settings.multibandCompression,
                dynamicsRetention: dynamicsRetention,
                finishingIntensity: finishingIntensity
            )
        }

        logger?.log(MasteringStep.saturate.rawValue)
        current = measure(label: "倍音", logger: logger) {
            applySaturation(signal: current, amount: effectiveSaturation(settings.saturationAmount, dynamicsRetention: dynamicsRetention, finishingIntensity: finishingIntensity))
        }

        logger?.log(MasteringStep.stereo.rawValue)
        current = measure(label: "広がり", logger: logger) {
            applyStereoWidth(signal: current, targetWidth: settings.stereoWidth)
        }

        logger?.log(MasteringStep.loudness.rawValue)
        return measure(label: "音量", logger: logger) {
            applyLoudness(
                signal: current,
                targetLKFS: effectiveTargetLoudness(settings.targetLoudness, dynamicsRetention: dynamicsRetention, finishingIntensity: finishingIntensity),
                peakCeilingDB: settings.peakCeilingDB
            )
        }
    }

    private func measure<T>(label: String, logger: AudioProcessingLogger?, work: () -> T) -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = work()
        let end = DispatchTime.now().uptimeNanoseconds
        logger?.log("\(label): \(formatProcessingDuration(Double(end - start) / 1_000_000_000))")
        return result
    }

    private func applyTone(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings, finishingIntensity: Float) -> AudioSignal {
        let lowAdjustmentDB = settings.lowShelfGain + clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 18), min: -0.25, max: 1.2)
        let lowMidAdjustmentDB = settings.lowMidGain - clamped(Float((analysis.lowBandLevelDB - analysis.midBandLevelDB) / 16), min: -0.2, max: 0.7)
        let presenceAdjustmentDB = settings.presenceGain + clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 16), min: -0.2, max: 0.8) - analysis.harshnessScore * 0.32
        let highAdjustmentDB = settings.highShelfGain + clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 18), min: -0.25, max: 0.9) - analysis.harshnessScore * 0.55
        let toneScale = 0.72 + finishingIntensity * 0.46

        let lowDelta = gainDelta(forDB: lowAdjustmentDB) * toneScale
        let lowMidDelta = gainDelta(forDB: lowMidAdjustmentDB) * toneScale
        let presenceDelta = gainDelta(forDB: presenceAdjustmentDB) * toneScale
        let highDelta = gainDelta(forDB: highAdjustmentDB) * toneScale

        let channels = signal.channels.map { channel in
            let low = SpectralDSP.lowPass(channel, cutoff: 120, sampleRate: signal.sampleRate)
            let lowMid = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 120, sampleRate: signal.sampleRate),
                cutoff: 420,
                sampleRate: signal.sampleRate
            )
            let presence = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 2_500, sampleRate: signal.sampleRate),
                cutoff: 5_500,
                sampleRate: signal.sampleRate
            )
            let high = SpectralDSP.highPass(channel, cutoff: 10_000, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                channel[index]
                    + low[index] * lowDelta
                    + lowMid[index] * lowMidDelta
                    + presence[index] * presenceDelta
                    + high[index] * highDelta
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyDeEsser(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings) -> AudioSignal {
        guard settings.deEsserAmount > 0.001 else { return signal }

        let threshold = powf(10, settings.deEsserThresholdDB / 20)
        let attackCoeff = expf(-1 / max(Float(signal.sampleRate) * 0.002, 1))
        let releaseCoeff = expf(-1 / max(Float(signal.sampleRate) * 0.090, 1))
        let adaptiveAmount = settings.deEsserAmount * (0.55 + analysis.harshnessScore * 0.75)
        let maxReduction = min(0.68, 0.18 + analysis.harshnessScore * 0.28 + settings.deEsserAmount * 0.20)

        let channels = signal.channels.map { channel in
            let detectionBand = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 4_500, sampleRate: signal.sampleRate),
                cutoff: 9_000,
                sampleRate: signal.sampleRate
            )
            let reductionBand = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 5_500, sampleRate: signal.sampleRate),
                cutoff: 11_000,
                sampleRate: signal.sampleRate
            )

            var envelope: Float = 0
            return channel.indices.map { index in
                let detectorSample = detectionBand[index]
                let level = abs(detectorSample)
                if level > envelope {
                    envelope = attackCoeff * envelope + (1 - attackCoeff) * level
                } else {
                    envelope = releaseCoeff * envelope + (1 - releaseCoeff) * level
                }

                guard envelope > threshold else { return channel[index] }
                let excess = min(3.0, max(0, (envelope - threshold) / max(threshold, 1e-6)))
                let reduction = min(maxReduction, excess * adaptiveAmount * 0.30)
                return channel[index] - reductionBand[index] * reduction
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyMultibandCompression(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MultibandCompressionSettings,
        dynamicsRetention: Float,
        finishingIntensity: Float
    ) -> AudioSignal {
        let adjustedSettings = tunedCompressionSettings(
            base: settings,
            analysis: analysis,
            dynamicsRetention: dynamicsRetention,
            finishingIntensity: finishingIntensity
        )
        let channels = signal.channels.map { channel in
            let low = SpectralDSP.lowPass(channel, cutoff: 160, sampleRate: signal.sampleRate)
            let mid = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 160, sampleRate: signal.sampleRate),
                cutoff: 3_200,
                sampleRate: signal.sampleRate
            )
            let high = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 3_200, sampleRate: signal.sampleRate),
                cutoff: 9_000,
                sampleRate: signal.sampleRate
            )
            let air = SpectralDSP.highPass(channel, cutoff: 9_000, sampleRate: signal.sampleRate)
            let compressedLow = compressBand(low, sampleRate: signal.sampleRate, settings: adjustedSettings.low)
            let compressedMid = compressBand(mid, sampleRate: signal.sampleRate, settings: adjustedSettings.mid)
            let compressedHigh = compressBand(high, sampleRate: signal.sampleRate, settings: adjustedSettings.high)

            return channel.indices.map { index in
                compressedLow[index] + compressedMid[index] + compressedHigh[index] + air[index]
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func tunedCompressionSettings(
        base: MultibandCompressionSettings,
        analysis: MasteringAnalysis,
        dynamicsRetention: Float,
        finishingIntensity: Float
    ) -> MultibandCompressionSettings {
        let compressionScale = clamped(0.56 + finishingIntensity * 0.58 - dynamicsRetention * 0.24, min: 0.35, max: 1.10)
        let makeupScale = clamped(0.62 + finishingIntensity * 0.46 - dynamicsRetention * 0.22, min: 0.35, max: 1.00)
        let thresholdOffset = dynamicsRetention * 1.4 - finishingIntensity * 0.45
        let lowMakeup = (base.low.makeupGainDB + clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 20), min: -0.15, max: 0.25)) * makeupScale
        let midMakeup = (base.mid.makeupGainDB + clamped(Float((analysis.highBandLevelDB - analysis.midBandLevelDB) / 24), min: -0.10, max: 0.12)) * makeupScale
        let highThreshold = base.high.thresholdDB - analysis.harshnessScore * 1.2
        let highRatio = scaledRatio(base.high.ratio + analysis.harshnessScore * 0.18, scale: compressionScale)
        let highMakeup = max(-0.2, (base.high.makeupGainDB - analysis.harshnessScore * 0.14) * makeupScale)

        return MultibandCompressionSettings(
            low: BandCompressorSettings(
                thresholdDB: base.low.thresholdDB + thresholdOffset,
                ratio: scaledRatio(base.low.ratio, scale: compressionScale),
                attackMs: base.low.attackMs,
                releaseMs: base.low.releaseMs,
                makeupGainDB: lowMakeup
            ),
            mid: BandCompressorSettings(
                thresholdDB: base.mid.thresholdDB + thresholdOffset,
                ratio: scaledRatio(base.mid.ratio, scale: compressionScale),
                attackMs: base.mid.attackMs,
                releaseMs: base.mid.releaseMs,
                makeupGainDB: midMakeup
            ),
            high: BandCompressorSettings(
                thresholdDB: highThreshold + thresholdOffset,
                ratio: highRatio,
                attackMs: base.high.attackMs,
                releaseMs: base.high.releaseMs,
                makeupGainDB: highMakeup
            )
        )
    }

    private func compressBand(_ samples: [Float], sampleRate: Double, settings: BandCompressorSettings) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let threshold = powf(10, settings.thresholdDB / 20)
        let makeupGain = powf(10, settings.makeupGainDB / 20)
        let attackCoeff = expf(-1 / max(Float(sampleRate) * settings.attackMs * 0.001, 1))
        let releaseCoeff = expf(-1 / max(Float(sampleRate) * settings.releaseMs * 0.001, 1))

        var envelope: Float = 0
        var result = Array(repeating: Float.zero, count: samples.count)

        let kneeWidth: Float = 3

        for index in samples.indices {
            let input = samples[index]
            let level = abs(input)
            if level > envelope {
                envelope = attackCoeff * envelope + (1 - attackCoeff) * level
            } else {
                envelope = releaseCoeff * envelope + (1 - releaseCoeff) * level
            }

            var gain: Float = 1
            if envelope > threshold {
                let envelopeDB = 20 * log10f(max(envelope, 1e-6))
                let gainReductionDB = compressionGainReductionDB(
                    envelopeDB: envelopeDB,
                    thresholdDB: settings.thresholdDB,
                    ratio: settings.ratio,
                    kneeWidthDB: kneeWidth
                )
                gain = powf(10, gainReductionDB / 20)
            }

            result[index] = input * gain * makeupGain
        }

        return result
    }

    private func applySaturation(signal: AudioSignal, amount: Float) -> AudioSignal {
        let drive = 1 + amount * 2.8
        let mix = min(max(amount * 0.75, 0), 0.4)

        let channels = signal.channels.map { channel in
            channel.map { sample in
                let saturated = tanhf(sample * drive)
                return sample * (1 - mix) + saturated * mix
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyStereoWidth(signal: AudioSignal, targetWidth: Float) -> AudioSignal {
        guard signal.channels.count >= 2 else { return signal }
        let left = signal.channels[0]
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return signal }

        let lowLeft = SpectralDSP.lowPass(left, cutoff: 180, sampleRate: signal.sampleRate)
        let lowRight = SpectralDSP.lowPass(right, cutoff: 180, sampleRate: signal.sampleRate)
        let highLeft = zip(left, lowLeft).map(-)
        let highRight = zip(right, lowRight).map(-)

        var widenedLeft = Array(repeating: Float.zero, count: count)
        var widenedRight = Array(repeating: Float.zero, count: count)
        for index in 0..<count {
            let highMid = (highLeft[index] + highRight[index]) * 0.5
            let highSide = (highLeft[index] - highRight[index]) * 0.5 * targetWidth
            widenedLeft[index] = lowLeft[index] + highMid + highSide
            widenedRight[index] = lowRight[index] + highMid - highSide
        }

        var channels = signal.channels
        channels[0] = widenedLeft
        channels[1] = widenedRight
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyLoudness(signal: AudioSignal, targetLKFS: Float, peakCeilingDB: Float) -> AudioSignal {
        let currentLoudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        let gain = powf(10, (targetLKFS - currentLoudness) / 20)
        let peakCeiling = powf(10, peakCeilingDB / 20)
        let gainedChannels = signal.channels.map { channel in channel.map { $0 * gain } }
        var channels = applyLookaheadLimiter(gainedChannels, peakCeiling: peakCeiling, sampleRate: signal.sampleRate)

        let peak = MasteringAnalysisService.approximateTruePeak(channels)
        if peak > peakCeiling {
            let trim = peakCeiling / peak
            channels = channels.map { $0.map { $0 * trim } }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyLookaheadLimiter(_ channels: [[Float]], peakCeiling: Float, sampleRate: Double) -> [[Float]] {
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

    private func effectiveSaturation(_ amount: Float, dynamicsRetention: Float, finishingIntensity: Float) -> Float {
        amount * clamped(0.64 + finishingIntensity * 0.52 - dynamicsRetention * 0.24, min: 0.35, max: 1.10)
    }

    private func effectiveTargetLoudness(_ target: Float, dynamicsRetention: Float, finishingIntensity: Float) -> Float {
        target + (finishingIntensity - 0.5) * 0.9 - dynamicsRetention * 0.45
    }

    private func scaledRatio(_ ratio: Float, scale: Float) -> Float {
        1 + (max(ratio, 1) - 1) * scale
    }

    private func compressionGainReductionDB(envelopeDB: Float, thresholdDB: Float, ratio: Float, kneeWidthDB: Float) -> Float {
        let safeRatio = max(ratio, 1)
        let lowerKnee = thresholdDB - kneeWidthDB * 0.5
        let upperKnee = thresholdDB + kneeWidthDB * 0.5

        if envelopeDB <= lowerKnee {
            return 0
        }

        if envelopeDB >= upperKnee {
            let compressedDB = thresholdDB + (envelopeDB - thresholdDB) / safeRatio
            return compressedDB - envelopeDB
        }

        let over = envelopeDB - lowerKnee
        let gainReductionDB = (1 / safeRatio - 1) * over * over / (2 * kneeWidthDB)
        return gainReductionDB
    }

    private func framePeakEnvelope(_ channels: [[Float]], frameCount: Int) -> [Float] {
        (0..<frameCount).map { index in
            channels.reduce(Float.zero) { partial, channel in
                guard index < channel.count else { return partial }
                return max(partial, abs(channel[index]))
            }
        }
    }

    private func slidingMaximum(_ values: [Float], windowSize: Int) -> [Float] {
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

    private func gainDelta(forDB value: Float) -> Float {
        powf(10, value / 20) - 1
    }

    private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.max(minValue, Swift.min(value, maxValue))
    }
}
