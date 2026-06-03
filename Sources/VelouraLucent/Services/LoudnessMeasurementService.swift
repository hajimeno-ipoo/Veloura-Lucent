import Foundation

enum LoudnessMeasurementService {
    struct Measurement: Sendable {
        let integratedLoudnessLUFS: Double
        let truePeakDBFS: Double
        let truePeakLinear: Float
        let loudnessRangeLU: Double?
        let shortTermLoudness: [TimedLevelMetric]
    }

    static func measure(signal: AudioSignal, includeLoudnessRange: Bool = true) -> Measurement {
        let channels = signal.channels.filter { !$0.isEmpty }
        guard !channels.isEmpty else {
            return Measurement(
                integratedLoudnessLUFS: -70,
                truePeakDBFS: -120,
                truePeakLinear: 0,
                loudnessRangeLU: nil,
                shortTermLoudness: []
            )
        }

        let energyPrefixes = channels.map { energyPrefix(for: kWeighted($0, sampleRate: signal.sampleRate)) }
        let gatedBlocks = gatedBlockLoudness(forEnergyPrefixes: energyPrefixes, sampleRate: signal.sampleRate)
        let shortTerm = shortTermLoudnessTimeline(forEnergyPrefixes: energyPrefixes, sampleRate: signal.sampleRate)
        let truePeak = truePeakLinear(signal.channels)

        return Measurement(
            integratedLoudnessLUFS: integratedLoudness(from: gatedBlocks),
            truePeakDBFS: 20 * log10(max(Double(truePeak), 1e-12)),
            truePeakLinear: truePeak,
            loudnessRangeLU: includeLoudnessRange ? loudnessRange(signal: signal) : nil,
            shortTermLoudness: shortTerm
        )
    }

    static func integratedLoudness(signal: AudioSignal) -> Float {
        let channels = signal.channels.filter { !$0.isEmpty }
        guard !channels.isEmpty else { return -70 }

        let energyPrefixes = channels.map { energyPrefix(for: kWeighted($0, sampleRate: signal.sampleRate)) }
        let gatedBlocks = gatedBlockLoudness(forEnergyPrefixes: energyPrefixes, sampleRate: signal.sampleRate)
        return Float(integratedLoudness(from: gatedBlocks))
    }

    static func truePeakLinear(_ channels: [[Float]]) -> Float {
        var peak: Float = 0
        for channel in channels {
            peak = max(peak, oversampledPeak(channel))
        }
        return peak
    }

    private static func gatedBlockLoudness(forEnergyPrefixes prefixes: [[Double]], sampleRate: Double) -> [Double] {
        let sampleCount = prefixes.map { max($0.count - 1, 0) }.min() ?? 0
        guard sampleCount > 0 else { return [] }

        let windowSize = max(Int(sampleRate * 0.4), 1)
        let hopSize = max(Int(sampleRate * 0.1), 1)
        var blockLoudness: [Double] = []
        var start = 0

        while start < sampleCount {
            let end = min(sampleCount, start + windowSize)
            let meanEnergy = prefixes.reduce(0.0) { $0 + meanSquare(in: $1, start: start, end: end) }
            let rms = sqrt(max(meanEnergy, 1e-9))
            blockLoudness.append(20 * log10(max(rms, 1e-12)))
            start += hopSize
        }

        let absoluteGated = blockLoudness.filter { $0 > -70 }
        guard !absoluteGated.isEmpty else { return [] }
        let preliminary = energyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return relativeGated.isEmpty ? absoluteGated : relativeGated
    }

    private static func integratedLoudness(from gatedBlocks: [Double]) -> Double {
        gatedBlocks.isEmpty ? -70 : energyAverage(gatedBlocks)
    }

    static func loudnessRange(signal: AudioSignal) -> Double? {
        guard abs(signal.sampleRate - 48_000) < 0.5,
              (1...2).contains(signal.channels.count),
              let sampleCount = signal.channels.map(\.count).min(),
              sampleCount > 0
        else {
            return nil
        }

        let trailingSilenceCount = Int(signal.sampleRate * 1.5)
        let prefixes = signal.channels.map {
            officialKWeightedEnergyPrefix(
                for: $0,
                sampleCount: sampleCount,
                trailingSilenceCount: trailingSilenceCount
            )
        }
        let totalSampleCount = sampleCount + trailingSilenceCount
        let windowSize = Int(signal.sampleRate * 3.0)
        let hopSize = Int(signal.sampleRate * 0.1)
        guard totalSampleCount >= windowSize else { return nil }

        var loudnessValues: [Double] = []
        var start = 0
        while start + windowSize <= totalSampleCount {
            let end = start + windowSize
            let meanEnergy = prefixes.reduce(0.0) {
                $0 + meanSquare(in: $1, start: start, end: end)
            }
            loudnessValues.append(-0.691 + 10 * log10(max(meanEnergy, 1e-12)))
            start += hopSize
        }

        let absoluteGated = loudnessValues.filter { $0 >= -70 }
        guard !absoluteGated.isEmpty else { return nil }
        let relativeGate = energyAverage(absoluteGated) - 20
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }.sorted()
        guard !relativeGated.isEmpty else { return nil }
        return percentile(relativeGated, 0.95) - percentile(relativeGated, 0.10)
    }

    private static func officialKWeightedEnergyPrefix(
        for channel: [Float],
        sampleCount: Int,
        trailingSilenceCount: Int
    ) -> [Double] {
        var preFilter = BiquadFilter(coefficients: officialPreFilterCoefficients)
        var rlbFilter = BiquadFilter(coefficients: officialRLBFilterCoefficients)
        let totalSampleCount = sampleCount + trailingSilenceCount
        var prefix = Array(repeating: 0.0, count: totalSampleCount + 1)

        for index in 0..<totalSampleCount {
            let sample = index < sampleCount ? Double(channel[index]) : 0
            let weighted = rlbFilter.process(preFilter.process(sample))
            prefix[index + 1] = prefix[index] + weighted * weighted
        }
        return prefix
    }

    private static func shortTermLoudnessTimeline(forEnergyPrefixes prefixes: [[Double]], sampleRate: Double) -> [TimedLevelMetric] {
        let sampleCount = prefixes.map { max($0.count - 1, 0) }.min() ?? 0
        guard sampleCount > 0 else { return [] }

        let duration = Double(sampleCount) / sampleRate
        let windowDuration = min(3.0, max(0.4, duration))
        let hopDuration = max(0.25, duration / 96.0)
        let windowSize = max(1, Int(sampleRate * windowDuration))
        let hopSize = max(1, Int(sampleRate * hopDuration))

        var values: [TimedLevelMetric] = []
        var start = 0
        var index = 0
        while start < sampleCount {
            let end = min(sampleCount, start + windowSize)
            guard start < end else { break }
            let meanEnergy = prefixes.reduce(0.0) { $0 + meanSquare(in: $1, start: start, end: end) }
            let rms = sqrt(max(meanEnergy, 1e-12))
            let time = (Double(start + end) * 0.5) / sampleRate
            values.append(TimedLevelMetric(id: "loudness-\(index)", time: time, levelDB: 20 * log10(max(rms, 1e-12))))
            start += hopSize
            index += 1
        }
        return values
    }

    private static func kWeighted(_ signal: [Float], sampleRate: Double) -> [Float] {
        let highPassed = SpectralDSP.highPass(signal, cutoff: 60, sampleRate: sampleRate)
        let shelfBase = SpectralDSP.highPass(signal, cutoff: 1_500, sampleRate: sampleRate)
        return zip(highPassed, shelfBase).map { $0 + $1 * 0.25 }
    }

    private static func energyPrefix(for values: [Float]) -> [Double] {
        var prefix = Array(repeating: 0.0, count: values.count + 1)
        for index in values.indices {
            let value = Double(values[index])
            prefix[index + 1] = prefix[index] + value * value
        }
        return prefix
    }

    private static func meanSquare(in prefix: [Double], start: Int, end: Int) -> Double {
        guard start < end, start >= 0, end < prefix.count else { return 0 }
        return (prefix[end] - prefix[start]) / Double(max(end - start, 1))
    }

    private static func energyAverage(_ loudnessValues: [Double]) -> Double {
        let meanEnergy = loudnessValues.map { pow(10, $0 / 10) }.reduce(0, +) / Double(max(loudnessValues.count, 1))
        return 10 * log10(max(meanEnergy, 1e-9))
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        let index = max(0, min(values.count - 1, Int(round(Double(values.count - 1) * percentile))))
        return values[index]
    }

    private struct BiquadCoefficients {
        let b0: Double
        let b1: Double
        let b2: Double
        let a1: Double
        let a2: Double
    }

    private struct BiquadFilter {
        let coefficients: BiquadCoefficients
        var x1 = 0.0
        var x2 = 0.0
        var y1 = 0.0
        var y2 = 0.0

        mutating func process(_ input: Double) -> Double {
            let output = coefficients.b0 * input
                + coefficients.b1 * x1
                + coefficients.b2 * x2
                - coefficients.a1 * y1
                - coefficients.a2 * y2
            x2 = x1
            x1 = input
            y2 = y1
            y1 = output
            return output
        }
    }

    private static let officialPreFilterCoefficients = BiquadCoefficients(
        b0: 1.53512485958697,
        b1: -2.69169618940638,
        b2: 1.19839281085285,
        a1: -1.69065929318241,
        a2: 0.73248077421585
    )

    private static let officialRLBFilterCoefficients = BiquadCoefficients(
        b0: 1,
        b1: -2,
        b2: 1,
        a1: -1.99004745483398,
        a2: 0.99007225036621
    )

    private static func oversampledPeak(_ channel: [Float]) -> Float {
        guard channel.count > 1 else { return channel.map { abs($0) }.max() ?? 0 }
        var peak: Float = 0
        for index in 0..<(channel.count - 1) {
            let p0 = index > 0 ? channel[index - 1] : channel[index]
            let p1 = channel[index]
            let p2 = channel[index + 1]
            let p3 = index + 2 < channel.count ? channel[index + 2] : p2
            peak = max(peak, abs(p1))
            for step in 1...7 {
                let t = Float(step) / 8
                peak = max(peak, abs(catmullRom(p0: p0, p1: p1, p2: p2, p3: p3, t: t)))
            }
        }
        peak = max(peak, abs(channel[channel.count - 1]))
        return peak
    }

    @inline(__always)
    private static func catmullRom(p0: Float, p1: Float, p2: Float, p3: Float, t: Float) -> Float {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (
            (2 * p1)
                + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
        )
    }
}
