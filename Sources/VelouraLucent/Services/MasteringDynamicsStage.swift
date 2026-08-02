import Foundation

extension MasteringProcessor {
    func applyMultibandCompression(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MultibandCompressionSettings,
        dynamicsRetention: Float,
        finishingIntensity: Float,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let inputMetrics = MasteringAnalysisService.dynamicMetrics(signal: signal)
        logger?.log(
            "密度調整/入力: Crest \(formatDynamicValue(inputMetrics.crestFactorDB, unit: "dB")) / "
                + "LRA \(formatOptionalDynamicValue(inputMetrics.loudnessRangeLU, unit: "LU"))"
        )
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
            let compressedBody = channel.indices.map {
                compressedLow[$0] + compressedMid[$0] + compressedHigh[$0]
            }
            let candidate = channel.indices.map { index in
                compressedBody[index] + air[index]
            }
            return matchHighBandGain(
                reference: channel,
                processed: candidate,
                sampleRate: signal.sampleRate
            )
        }

        let compressed = AudioSignal(channels: channels, sampleRate: signal.sampleRate)
        let constrained = constrainDynamicsChange(
            input: signal,
            compressed: compressed,
            inputMetrics: inputMetrics,
            logger: logger
        )
        logger?.log(
            "密度調整/結果: Crest \(formatDynamicValue(constrained.metrics.crestFactorDB, unit: "dB")) "
                + "(\(formatDynamicDelta(constrained.metrics.crestFactorDB - inputMetrics.crestFactorDB, unit: "dB"))) / "
                + "LRA \(formatOptionalDynamicValue(constrained.metrics.loudnessRangeLU, unit: "LU"))"
                + formatOptionalDynamicDelta(constrained.metrics.loudnessRangeLU, reference: inputMetrics.loudnessRangeLU, unit: "LU")
        )
        return constrained.signal
    }

    private func matchHighBandGain(reference: [Float], processed: [Float], sampleRate: Double) -> [Float] {
        guard !reference.isEmpty, reference.count == processed.count else { return processed }
        let referenceSpectrum = SpectralDSP.stft(reference)
        var processedSpectrum = SpectralDSP.stft(processed)
        let bodyGain = spectralBandGain(
            reference: referenceSpectrum,
            processed: processedSpectrum,
            lower: 20,
            upper: 2_000,
            sampleRate: sampleRate
        )
        let currentHighGain = spectralBandGain(
            reference: referenceSpectrum,
            processed: processedSpectrum,
            lower: 9_000,
            upper: sampleRate * 0.5,
            sampleRate: sampleRate
        )
        guard bodyGain.isFinite, currentHighGain.isFinite, currentHighGain > 0 else {
            return processed
        }

        let correction = bodyGain / currentHighGain
        let frequencyStep = sampleRate / Double(processedSpectrum.fftSize)
        for frameIndex in 0..<processedSpectrum.frameCount {
            for binIndex in 0..<processedSpectrum.binCount {
                let frequency = Double(binIndex) * frequencyStep
                let gain: Float
                if frequency < 8_500 {
                    continue
                } else if frequency < 9_000 {
                    let position = Float((frequency - 8_500) / 500)
                    gain = 1 + (correction - 1) * position
                } else {
                    gain = correction
                }
                processedSpectrum.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
            }
        }
        return SpectralDSP.istft(processedSpectrum)
    }

    private func spectralBandGain(
        reference: Spectrogram,
        processed: Spectrogram,
        lower: Double,
        upper: Double,
        sampleRate: Double
    ) -> Float {
        let frameCount = min(reference.frameCount, processed.frameCount)
        let binCount = min(reference.binCount, processed.binCount)
        guard frameCount > 0, binCount > 0 else { return 1 }

        let frequencyStep = sampleRate / Double(reference.fftSize)
        let lowerBin = max(0, Int(ceil(lower / frequencyStep)))
        let upperBin = min(binCount - 1, Int(floor(upper / frequencyStep)))
        guard lowerBin <= upperBin else { return 1 }

        var referenceEnergy = 0.0
        var processedEnergy = 0.0
        for frameIndex in 0..<frameCount {
            for binIndex in lowerBin...upperBin {
                let referenceMagnitude = Double(reference.magnitude(frameIndex: frameIndex, binIndex: binIndex))
                let processedMagnitude = Double(processed.magnitude(frameIndex: frameIndex, binIndex: binIndex))
                referenceEnergy += referenceMagnitude * referenceMagnitude
                processedEnergy += processedMagnitude * processedMagnitude
            }
        }
        guard referenceEnergy > Double.leastNormalMagnitude else { return 1 }
        return Float(sqrt(processedEnergy / referenceEnergy))
    }

    private func tunedCompressionSettings(
        base: MultibandCompressionSettings,
        analysis: MasteringAnalysis,
        dynamicsRetention: Float,
        finishingIntensity: Float
    ) -> MultibandCompressionSettings {
        let compressionScale = MasteringSignalMath.clamped(0.56 + finishingIntensity * 0.58 - dynamicsRetention * 0.24, min: 0.35, max: 1.10)
        let makeupScale = MasteringSignalMath.clamped(0.62 + finishingIntensity * 0.46 - dynamicsRetention * 0.22, min: 0.35, max: 1.00)
        let thresholdOffset = dynamicsRetention * 1.4 - finishingIntensity * 0.45
        let lowMakeup = (base.low.makeupGainDB + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 20), min: -0.15, max: 0.25)) * makeupScale
        let midMakeup = (base.mid.makeupGainDB + MasteringSignalMath.clamped(Float((analysis.highBandLevelDB - analysis.midBandLevelDB) / 24), min: -0.10, max: 0.12)) * makeupScale
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

    func scaledRatio(_ ratio: Float, scale: Float) -> Float {
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

    private func constrainDynamicsChange(
        input: AudioSignal,
        compressed: AudioSignal,
        inputMetrics: (crestFactorDB: Double, loudnessRangeLU: Double?),
        logger: AudioProcessingLogger?
    ) -> (signal: AudioSignal, metrics: (crestFactorDB: Double, loudnessRangeLU: Double?)) {
        let compressedMetrics = MasteringAnalysisService.dynamicMetrics(signal: compressed)
        let crestReductionDB = inputMetrics.crestFactorDB - compressedMetrics.crestFactorDB
        let maximumCrestReductionDB = 3.0
        let minimumLRARetention = 0.60
        var wetMix = 1.0

        if crestReductionDB > maximumCrestReductionDB {
            wetMix = min(wetMix, maximumCrestReductionDB / crestReductionDB)
        }
        if let inputLRA = inputMetrics.loudnessRangeLU,
           let compressedLRA = compressedMetrics.loudnessRangeLU,
           inputLRA > 0.1,
           compressedLRA < inputLRA * minimumLRARetention
        {
            wetMix = min(wetMix, compressedLRA / (inputLRA * minimumLRARetention))
        }

        guard wetMix < 0.999 else {
            logger?.log("密度調整/制限: 入力の強弱範囲内")
            return (compressed, compressedMetrics)
        }

        let mixed = blendDynamics(input: input, compressed: compressed, wetMix: Float(max(0, wetMix)))
        let mixedMetrics = MasteringAnalysisService.dynamicMetrics(signal: mixed)
        let mixedCrestReductionDB = inputMetrics.crestFactorDB - mixedMetrics.crestFactorDB
        let mixedLRARetention = lraRetention(output: mixedMetrics.loudnessRangeLU, input: inputMetrics.loudnessRangeLU)
        guard mixedCrestReductionDB <= maximumCrestReductionDB + 0.05,
              mixedLRARetention.map({ $0 >= minimumLRARetention - 0.02 }) ?? true
        else {
            logger?.log("密度調整/制限: 強弱の減少が大きいため工程入力を維持")
            return (input, inputMetrics)
        }

        logger?.log("密度調整/制限: 強弱を守るため圧縮mix \(String(format: "%.2f", wetMix))")
        return (mixed, mixedMetrics)
    }

    private func blendDynamics(input: AudioSignal, compressed: AudioSignal, wetMix: Float) -> AudioSignal {
        let channelCount = min(input.channels.count, compressed.channels.count)
        guard channelCount > 0 else { return input }
        let mix = MasteringSignalMath.clamped(wetMix, min: 0, max: 1)
        var channels = input.channels
        for channelIndex in 0..<channelCount {
            let frameCount = min(input.channels[channelIndex].count, compressed.channels[channelIndex].count)
            channels[channelIndex] = (0..<frameCount).map { frameIndex in
                input.channels[channelIndex][frameIndex] * (1 - mix)
                    + compressed.channels[channelIndex][frameIndex] * mix
            }
        }
        return AudioSignal(channels: channels, sampleRate: input.sampleRate)
    }

    private func lraRetention(output: Double?, input: Double?) -> Double? {
        guard let output, let input, input > 0.1 else { return nil }
        return output / input
    }

    private func formatDynamicValue(_ value: Double, unit: String) -> String {
        String(format: "%.2f %@", value, unit)
    }

    private func formatOptionalDynamicValue(_ value: Double?, unit: String) -> String {
        guard let value else { return "測定対象外" }
        return formatDynamicValue(value, unit: unit)
    }

    private func formatDynamicDelta(_ value: Double, unit: String) -> String {
        String(format: "%+.2f %@", value, unit)
    }

    private func formatOptionalDynamicDelta(_ value: Double?, reference: Double?, unit: String) -> String {
        guard let value, let reference else { return "" }
        return " (\(formatDynamicDelta(value - reference, unit: unit)))"
    }
}
