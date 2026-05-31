import Foundation

enum LoudnessMeasurementService {
    struct Measurement: Sendable {
        let integratedLoudnessLUFS: Double
        let truePeakDBFS: Double
        let truePeakLinear: Float
        let loudnessRangeLU: Double
        let shortTermLoudness: [TimedLevelMetric]
    }

    static func measure(signal: AudioSignal) -> Measurement {
        let channels = signal.channels.filter { !$0.isEmpty }
        guard !channels.isEmpty else {
            return Measurement(
                integratedLoudnessLUFS: -70,
                truePeakDBFS: -120,
                truePeakLinear: 0,
                loudnessRangeLU: 0,
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
            loudnessRangeLU: loudnessRange(from: shortTerm.map(\.levelDB)),
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

    private static func loudnessRange(from shortTermLoudness: [Double]) -> Double {
        let gated = shortTermLoudness.filter { $0 > -70 }.sorted()
        guard gated.count > 5 else { return 0 }
        return percentile(gated, 0.95) - percentile(gated, 0.10)
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
