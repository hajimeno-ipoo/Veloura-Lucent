import Foundation

struct NoiseReturnHighBandReferenceLevel {
    let lower: Double
    let upper: Double
    let maxDropDB: Double
    let referenceDB: Double
}

struct NoiseReturnProbePlan {
    let ranges: [Range<Int>]
    let totalWindowCount: Int

    var selectedWindowCount: Int { ranges.count }
    var usesRepresentativeWindows: Bool {
        totalWindowCount > ranges.count
    }
}

struct NoiseReturnProbe {
    let hiss: Double
    let sibilance: Double
    let shimmer: Double

    func comparableLevel(for id: String) -> Double? {
        switch id {
        case "hiss": hiss
        case "sibilance": sibilance
        case "shimmer": shimmer
        default: nil
        }
    }
}

enum MasteringNoiseReturnSupport {
    static func noiseReturnGain(for rule: NoiseReturnLimit, excessDB: Double) -> Float {
        powf(10, -Float(min(excessDB * rule.reductionMultiplier, rule.maxReductionDB)) / 20)
    }

    static func constrainedNoiseReturnCandidate(
        signal: AudioSignal,
        guardReferenceLevels: [NoiseReturnHighBandReferenceLevel],
        rule: NoiseReturnLimit,
        gain: Float,
        logger: AudioProcessingLogger?
    ) -> AudioSignal? {
        for mix in [Float(1.0), 0.75, 0.50, 0.25, 0.10] {
            let candidateGain = 1 - (1 - gain) * mix
            let sampleRate = signal.sampleRate
            let channels = mapChannelsConcurrently(signal.channels) {
                MasteringSignalMath.scaleBand(
                    channel: $0,
                    sampleRate: sampleRate,
                    lower: rule.lowerFrequency,
                    upper: rule.upperFrequency,
                    gain: candidateGain
                )
            }
            let candidate = AudioSignal(channels: channels, sampleRate: sampleRate)
            guard noiseReturnHighBandDropIsAllowed(candidate: candidate, referenceLevels: guardReferenceLevels) else {
                continue
            }
            if mix < 1 {
                logger?.log("ノイズ戻り: 高域保護 mix \(String(format: "%.2f", mix))")
            }
            return candidate
        }
        logger?.log("ノイズ戻り: 高域保護で削減見送り")
        return nil
    }

    static func noiseReturnHighBandReferenceLevels(signal: AudioSignal) -> [NoiseReturnHighBandReferenceLevel] {
        [
            (lower: 8_000.0, upper: 12_000.0, maxDropDB: 0.50),
            (lower: 12_000.0, upper: 16_000.0, maxDropDB: 0.50),
            (lower: 16_000.0, upper: 20_000.0, maxDropDB: 0.60)
        ].map { band in
            NoiseReturnHighBandReferenceLevel(
                lower: band.lower,
                upper: band.upper,
                maxDropDB: band.maxDropDB,
                referenceDB: MasteringSignalMath.bandRMSDB(signal: signal, lower: band.lower, upper: band.upper)
            )
        }
    }

    static func resolvedNoiseReturnHighBandReferenceLevels(
        _ levels: inout [NoiseReturnHighBandReferenceLevel]?,
        signal: AudioSignal
    ) -> [NoiseReturnHighBandReferenceLevel] {
        if let levels {
            return levels
        }
        let measuredLevels = noiseReturnHighBandReferenceLevels(signal: signal)
        levels = measuredLevels
        return measuredLevels
    }

    static func noiseReturnHighBandDropIsAllowed(
        candidate: AudioSignal,
        referenceLevels: [NoiseReturnHighBandReferenceLevel]
    ) -> Bool {
        referenceLevels.allSatisfy { band in
            let candidateDB = MasteringSignalMath.bandRMSDB(signal: candidate, lower: band.lower, upper: band.upper)
            return candidateDB >= band.referenceDB - band.maxDropDB
        }
    }

    static func noiseReturnDisplayName(for id: String) -> String {
        switch id {
        case NoiseMeasurementID.hiss: "hiss"
        case NoiseMeasurementID.sibilance: "sibilance"
        case NoiseMeasurementID.shimmer: "shimmer"
        default: id
        }
    }

    static func noiseReturnProbePlan(for signal: AudioSignal) -> NoiseReturnProbePlan {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return NoiseReturnProbePlan(ranges: [], totalWindowCount: 0)
        }
        let windowSize = max(Int(signal.sampleRate), 1)
        let totalWindowCount = max(1, Int(ceil(Double(mono.count) / Double(windowSize))))
        guard totalWindowCount > 45 else {
            return NoiseReturnProbePlan(ranges: [mono.indices], totalWindowCount: 1)
        }

        let probeCount = min(24, totalWindowCount)
        let selectedCount = min(8, probeCount)
        let windowStride = max(1, totalWindowCount / probeCount)
        let candidates = stride(from: 0, to: totalWindowCount, by: windowStride).prefix(probeCount).map { windowIndex in
            let start = min(windowIndex * windowSize, mono.count)
            let end = min(start + windowSize, mono.count)
            return (range: start..<end, score: MasteringSignalMath.rmsEnergy(mono[start..<end]))
        }
        let quietCount = max(1, selectedCount / 2)
        let loudCount = max(1, selectedCount - quietCount)
        let selected = Array(
            Set(
                candidates.sorted { $0.score < $1.score }.prefix(quietCount).map(\.range)
                    + candidates.sorted { $0.score > $1.score }.prefix(loudCount).map(\.range)
            )
        )
            .sorted { $0.lowerBound < $1.lowerBound }
        return NoiseReturnProbePlan(ranges: selected, totalWindowCount: totalWindowCount)
    }

    static func fullRangeNoiseReturnProbePlan(for signal: AudioSignal) -> NoiseReturnProbePlan {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return NoiseReturnProbePlan(ranges: [], totalWindowCount: 0)
        }
        let windowSize = max(Int(signal.sampleRate), 1)
        let totalWindowCount = max(1, Int(ceil(Double(mono.count) / Double(windowSize))))
        return NoiseReturnProbePlan(ranges: [mono.indices], totalWindowCount: totalWindowCount)
    }

    static func noiseReturnProbe(signal: AudioSignal, plan: NoiseReturnProbePlan) -> NoiseReturnProbe {
        let mono = signal.monoMixdown()
        let analysisMono = representativeSamples(from: mono, ranges: plan.ranges)
        guard !analysisMono.isEmpty else {
            return NoiseReturnProbe(hiss: -120, sibilance: 0, shimmer: -120)
        }

        let hissBand = MasteringSignalMath.steepBandPass(analysisMono, lower: 8_000, upper: min(20_000, signal.sampleRate * 0.5 - 100), sampleRate: signal.sampleRate)
        let sibilanceBand = MasteringSignalMath.steepBandPass(analysisMono, lower: 5_000, upper: min(9_000, signal.sampleRate * 0.5 - 100), sampleRate: signal.sampleRate)
        return NoiseReturnProbe(
            hiss: quietBandNoiseFloorDB(band: hissBand, reference: analysisMono, sampleRate: signal.sampleRate),
            sibilance: transientExcessDB(sibilanceBand, sampleRate: signal.sampleRate),
            shimmer: shimmerInstabilityDB(analysisMono, sampleRate: signal.sampleRate)
        )
    }

    static func representativeSamples(from mono: [Float], ranges: [Range<Int>]) -> [Float] {
        guard !mono.isEmpty else { return [] }
        guard !(ranges.count == 1 && ranges[0] == mono.indices) else { return mono }

        var samples: [Float] = []
        samples.reserveCapacity(ranges.reduce(0) { $0 + $1.count })
        for range in ranges {
            let lower = min(max(range.lowerBound, mono.startIndex), mono.endIndex)
            let upper = min(max(range.upperBound, lower), mono.endIndex)
            guard lower < upper else { continue }
            samples.append(contentsOf: mono[lower..<upper])
        }
        return samples
    }

    static func quietBandNoiseFloorDB(band: [Float], reference: [Float], sampleRate: Double) -> Double {
        let frameSize = max(512, Int(sampleRate * 0.100))
        let hopSize = max(256, Int(sampleRate * 0.050))
        let referenceFrames = frameRMS(reference, frameSize: frameSize, hopSize: hopSize)
        let bandFrames = frameRMS(band, frameSize: frameSize, hopSize: hopSize)
        guard !referenceFrames.isEmpty, referenceFrames.count == bandFrames.count else {
            return MasteringSignalMath.rmsDB(band)
        }

        let threshold = MasteringSignalMath.percentile(referenceFrames, 0.20)
        let quietValues = zip(referenceFrames, bandFrames).compactMap { reference, band -> Double? in
            reference <= threshold ? band : nil
        }
        return MasteringSignalMath.percentile(quietValues.isEmpty ? bandFrames : quietValues, 0.20)
    }

    static func shimmerInstabilityDB(_ samples: [Float], sampleRate: Double) -> Double {
        let upperBound = min(16_000, sampleRate * 0.5 - 100)
        guard 8_000 < upperBound else { return 0 }
        let shimmerBand = MasteringSignalMath.steepBandPass(samples, lower: 8_000, upper: upperBound, sampleRate: sampleRate)
        let bodyBand = MasteringSignalMath.bandPass(samples, lower: 200, upper: min(5_000, sampleRate * 0.5 - 100), sampleRate: sampleRate)
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        let shimmerFrames = frameRMS(shimmerBand, frameSize: frameSize, hopSize: hopSize)
        let bodyFrames = frameRMS(bodyBand, frameSize: frameSize, hopSize: hopSize)
        let count = min(shimmerFrames.count, bodyFrames.count)
        guard count >= 9 else { return 0 }

        let relativeHigh = (0..<count).map { shimmerFrames[$0] - bodyFrames[$0] }
        let residuals = relativeHigh.indices.map { index -> Double in
            let start = max(0, index - 8)
            let end = min(relativeHigh.count - 1, index + 8)
            let localMedian = MasteringSignalMath.percentile(Array(relativeHigh[start...end]), 0.50)
            return max(0, relativeHigh[index] - localMedian)
        }
        return MasteringSignalMath.percentile(residuals, 0.95)
    }

    static func transientExcessDB(_ samples: [Float], sampleRate: Double) -> Double {
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        let frames = frameRMS(samples, frameSize: frameSize, hopSize: hopSize).sorted()
        guard frames.count >= 4 else { return 0 }
        return MasteringSignalMath.percentile(frames, 0.95) - MasteringSignalMath.percentile(frames, 0.50)
    }

    static func transientPeakDB(_ samples: [Float], sampleRate: Double) -> Double {
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        let frames = frameRMS(samples, frameSize: frameSize, hopSize: hopSize)
        guard frames.count >= 4 else { return MasteringSignalMath.rmsDB(samples) }
        return MasteringSignalMath.percentile(frames, 0.95)
    }

    static func frameRMS(_ samples: [Float], frameSize: Int, hopSize: Int) -> [Double] {
        guard !samples.isEmpty else { return [] }
        if samples.count <= frameSize {
            return [MasteringSignalMath.rmsDB(samples)]
        }

        var values: [Double] = []
        var start = 0
        while start + frameSize <= samples.count {
            values.append(10 * log10(max(MasteringSignalMath.rmsEnergy(samples[start..<(start + frameSize)]), 1e-12)))
            start += hopSize
        }
        return values
    }
}
