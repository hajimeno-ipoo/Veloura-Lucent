import Foundation

extension NativeAudioProcessor {
    func noiseDelta(id: String, reference: NoiseMeasurementSnapshot, current: NoiseMeasurementSnapshot) -> Double {
        guard let referenceValue = reference.comparableLevel(for: id),
              let currentValue = current.comparableLevel(for: id)
        else { return 0 }
        return currentValue - referenceValue
    }

    func preserveCorrectionHighFloor(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        measurementCache: NoiseMeasurementRunCache,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        struct Rule {
            let label: String
            let lower: Double
            let upper: Double
            let maxAbsoluteDropDB: Double
            let maxBoostDB: Double
            let minimumUsefulBoostDB: Double
        }

        let rules = [
            Rule(label: "5-8kHz", lower: 5_000, upper: 8_000, maxAbsoluteDropDB: 3.0, maxBoostDB: 0.4, minimumUsefulBoostDB: 0.25),
            Rule(label: "8-12kHz", lower: 8_000, upper: 12_000, maxAbsoluteDropDB: 0.20, maxBoostDB: 1.0, minimumUsefulBoostDB: 0.20),
            Rule(label: "12-16kHz", lower: 12_000, upper: 16_000, maxAbsoluteDropDB: 0.20, maxBoostDB: 0.85, minimumUsefulBoostDB: 0.15),
            Rule(label: "16kHz以上", lower: 16_000, upper: 20_000, maxAbsoluteDropDB: 2.20, maxBoostDB: 0.30, minimumUsefulBoostDB: 0.25)
        ]
        let referenceMono = reference.monoMixdown()
        let referenceBandRMSDB = rules.map { rule in
            bandRMSDB(mono: referenceMono, sampleRate: reference.sampleRate, lower: rule.lower, upper: rule.upper)
        }

        var current = signal
        var currentMono = current.monoMixdown()
        var didApply = false
        for (ruleIndex, rule) in rules.enumerated() {
            let currentDB = bandRMSDB(mono: currentMono, sampleRate: current.sampleRate, lower: rule.lower, upper: rule.upper)
            let referenceDB = referenceBandRMSDB[ruleIndex]
            guard currentDB.isFinite, referenceDB.isFinite else { continue }

            let targetDB = referenceDB - rule.maxAbsoluteDropDB
            let neededBoostDB = targetDB - currentDB
            guard neededBoostDB > rule.minimumUsefulBoostDB else { continue }

            let boostDB = min(neededBoostDB, rule.maxBoostDB)
            let gain = powf(10, Float(boostDB) / 20)
            let sampleRate = current.sampleRate
            let channels = mapChannelsConcurrently(current.channels) {
                scaleCorrectionBand($0, sampleRate: sampleRate, lower: rule.lower, upper: rule.upper, gain: gain)
            }
            current = AudioSignal(channels: channels, sampleRate: sampleRate)
            if ruleIndex + 1 < rules.count {
                currentMono = current.monoMixdown()
            }
            didApply = true
            logger?.log("補正後高域保持/\(rule.label): +\(String(format: "%.1f", boostDB)) dB")
        }

        guard didApply else { return signal }
        return constrainCorrectionHighFloorNoiseReturn(
            signal: current,
            fallback: signal,
            referenceMeasurements: referenceMeasurements,
            measurementCache: measurementCache,
            logger: logger
        )
    }

    func constrainCorrectionHighFloorNoiseReturn(
        signal: AudioSignal,
        fallback: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        measurementCache: NoiseMeasurementRunCache,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let highNoiseIDs = [NoiseMeasurementID.hiss, NoiseMeasurementID.shimmer, NoiseMeasurementID.sibilance]
        var measurementCount = 0
        let fallbackMeasurements = measurementCache.snapshot(
            signalID: "correctionHighPreserve.fallback",
            signal: fallback,
            ids: highNoiseIDs
        )
        measurementCount += 1
        let fallbackHissReturn = noiseDelta(id: NoiseMeasurementID.hiss, reference: referenceMeasurements, current: fallbackMeasurements)
        let fallbackShimmerReturn = noiseDelta(id: NoiseMeasurementID.shimmer, reference: referenceMeasurements, current: fallbackMeasurements)
        let fallbackSibilanceReturn = noiseDelta(id: NoiseMeasurementID.sibilance, reference: referenceMeasurements, current: fallbackMeasurements)
        let hissCeiling = max(2.0, fallbackHissReturn + 0.35)
        let shimmerCeiling = max(2.0, fallbackShimmerReturn + 0.35)
        let sibilanceCeiling = min(2.2, max(1.5, fallbackSibilanceReturn + 0.25))
        let fallbackUltraHighDB = bandRMSDB(signal: fallback, lower: 16_000, upper: 20_000)
        let ultraHighLiftCeilingDB = 0.25

        func allowedCandidate(index: Int, signal candidateSignal: AudioSignal) -> Bool {
            let measurements = measurementCache.snapshot(
                signalID: "correctionHighPreserve.candidate.\(index)",
                signal: candidateSignal,
                ids: highNoiseIDs
            )
            measurementCount += 1
            let hissReturn = noiseDelta(id: NoiseMeasurementID.hiss, reference: referenceMeasurements, current: measurements)
            let shimmerReturn = noiseDelta(id: NoiseMeasurementID.shimmer, reference: referenceMeasurements, current: measurements)
            let sibilanceReturn = noiseDelta(id: NoiseMeasurementID.sibilance, reference: referenceMeasurements, current: measurements)
            let ultraHighLift = bandRMSDB(signal: candidateSignal, lower: 16_000, upper: 20_000) - fallbackUltraHighDB
            return hissReturn <= hissCeiling
                && shimmerReturn <= shimmerCeiling
                && sibilanceReturn <= sibilanceCeiling
                && ultraHighLift <= ultraHighLiftCeilingDB
        }

        if allowedCandidate(index: 0, signal: signal) {
            logger?.log("補正後高域保持/測定回数: \(measurementCount)")
            return signal
        }

        let blendedCandidates: [(index: Int, mix: Float, signal: AudioSignal)] = [
            (1, 0.75, blendSignals(base: fallback, boosted: signal, mix: 0.75)),
            (2, 0.60, blendSignals(base: fallback, boosted: signal, mix: 0.60)),
            (3, 0.50, blendSignals(base: fallback, boosted: signal, mix: 0.50)),
            (4, 0.25, blendSignals(base: fallback, boosted: signal, mix: 0.25)),
            (5, 0.10, blendSignals(base: fallback, boosted: signal, mix: 0.10))
        ]

        for candidate in blendedCandidates where allowedCandidate(index: candidate.index, signal: candidate.signal) {
            if candidate.mix < 1 {
                logger?.log("補正後高域保持: ノイズ/超高域戻り抑制 mix \(String(format: "%.2f", candidate.mix))")
            }
            logger?.log("補正後高域保持/測定回数: \(measurementCount)")
            return candidate.signal
        }

        logger?.log("補正後高域保持/測定回数: \(measurementCount)")
        logger?.log("補正後高域保持: ノイズ/超高域戻り抑制で見送り")
        return fallback
    }

    func blendSignals(base: AudioSignal, boosted: AudioSignal, mix: Float) -> AudioSignal {
        let channelCount = min(base.channels.count, boosted.channels.count)
        guard channelCount > 0 else { return base }
        var channels = Array(base.channels.prefix(channelCount))
        for channelIndex in 0..<channelCount {
            let count = min(base.channels[channelIndex].count, boosted.channels[channelIndex].count)
            guard count > 0 else { continue }
            channels[channelIndex] = (0..<count).map { index in
                base.channels[channelIndex][index] * (1 - mix) + boosted.channels[channelIndex][index] * mix
            }
        }
        return AudioSignal(channels: channels, sampleRate: base.sampleRate)
    }

    func scaleCorrectionBand(_ channel: [Float], sampleRate: Double, lower: Double, upper: Double, gain: Float) -> [Float] {
        let upperBound = min(upper, sampleRate * 0.5 - 100)
        guard lower < upperBound else { return channel }
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(channel, cutoff: lower, sampleRate: sampleRate),
            cutoff: upperBound,
            sampleRate: sampleRate
        )
        return channel.indices.map { index in
            channel[index] + band[index] * (gain - 1)
        }
    }

    func scaleCorrectionSignalBand(signal: AudioSignal, lower: Double, upper: Double, gainDB: Double) -> AudioSignal {
        let gain = powf(10, Float(gainDB) / 20)
        let sampleRate = signal.sampleRate
        let channels = mapChannelsConcurrently(signal.channels) {
            scaleCorrectionBand($0, sampleRate: sampleRate, lower: lower, upper: upper, gain: gain)
        }
        return AudioSignal(channels: channels, sampleRate: sampleRate)
    }

    func bandRMSDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let mono = signal.monoMixdown()
        return bandRMSDB(mono: mono, sampleRate: signal.sampleRate, lower: lower, upper: upper)
    }

    func bandRMSDB(mono: [Float], sampleRate: Double, lower: Double, upper: Double) -> Double {
        let upperBound = min(upper, sampleRate * 0.5 - 100)
        guard lower < upperBound else { return -120 }
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(mono, cutoff: lower, sampleRate: sampleRate),
            cutoff: upperBound,
            sampleRate: sampleRate
        )
        let meanSquare = band.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(band.count, 1))
        return 10 * log10(max(meanSquare, 1e-12))
    }
}
