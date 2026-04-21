import Foundation

struct MasteringProcessor {
    func process(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings, logger: AudioProcessingLogger? = nil) -> AudioSignal {
        logger?.log(MasteringStep.tone.rawValue)
        var current = applyTone(signal: signal, analysis: analysis, settings: settings)

        logger?.log(MasteringStep.deEss.rawValue)
        current = applyDeEsser(signal: current, analysis: analysis, settings: settings)

        logger?.log(MasteringStep.dynamics.rawValue)
        current = applyMultibandCompression(signal: current, analysis: analysis, settings: settings.multibandCompression)

        logger?.log(MasteringStep.saturate.rawValue)
        current = applySaturation(signal: current, amount: settings.saturationAmount)

        logger?.log(MasteringStep.stereo.rawValue)
        current = applyStereoWidth(signal: current, targetWidth: settings.stereoWidth)

        logger?.log(MasteringStep.loudness.rawValue)
        return applyLoudness(signal: current, targetLKFS: settings.targetLoudness, peakCeilingDB: settings.peakCeilingDB)
    }

    private func applyTone(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings) -> AudioSignal {
        let lowAdjustmentDB = settings.lowShelfGain + clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 18), min: -0.25, max: 1.2)
        let lowMidAdjustmentDB = settings.lowMidGain - clamped(Float((analysis.lowBandLevelDB - analysis.midBandLevelDB) / 16), min: -0.2, max: 0.7)
        let presenceAdjustmentDB = settings.presenceGain + clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 16), min: -0.2, max: 0.8) - analysis.harshnessScore * 0.32
        let highAdjustmentDB = settings.highShelfGain + clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 18), min: -0.25, max: 0.9) - analysis.harshnessScore * 0.55

        let lowDelta = gainDelta(forDB: lowAdjustmentDB)
        let lowMidDelta = gainDelta(forDB: lowMidAdjustmentDB)
        let presenceDelta = gainDelta(forDB: presenceAdjustmentDB)
        let highDelta = gainDelta(forDB: highAdjustmentDB)

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

    private func applyMultibandCompression(signal: AudioSignal, analysis: MasteringAnalysis, settings: MultibandCompressionSettings) -> AudioSignal {
        let adjustedSettings = tunedCompressionSettings(base: settings, analysis: analysis)
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

    private func tunedCompressionSettings(base: MultibandCompressionSettings, analysis: MasteringAnalysis) -> MultibandCompressionSettings {
        let lowMakeup = base.low.makeupGainDB + clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 20), min: -0.15, max: 0.25)
        let midMakeup = base.mid.makeupGainDB + clamped(Float((analysis.highBandLevelDB - analysis.midBandLevelDB) / 24), min: -0.10, max: 0.12)
        let highThreshold = base.high.thresholdDB - analysis.harshnessScore * 1.2
        let highRatio = base.high.ratio + analysis.harshnessScore * 0.18
        let highMakeup = max(-0.2, base.high.makeupGainDB - analysis.harshnessScore * 0.14)

        return MultibandCompressionSettings(
            low: BandCompressorSettings(
                thresholdDB: base.low.thresholdDB,
                ratio: base.low.ratio,
                attackMs: base.low.attackMs,
                releaseMs: base.low.releaseMs,
                makeupGainDB: lowMakeup
            ),
            mid: BandCompressorSettings(
                thresholdDB: base.mid.thresholdDB,
                ratio: base.mid.ratio,
                attackMs: base.mid.attackMs,
                releaseMs: base.mid.releaseMs,
                makeupGainDB: midMakeup
            ),
            high: BandCompressorSettings(
                thresholdDB: highThreshold,
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
