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

        let sampleCount = channels.map(\.count).min() ?? 0
        let gatedBlocks = officialGatedBlockLoudness(
            for: channels,
            sampleCount: sampleCount,
            sampleRate: signal.sampleRate
        )
        let shortTerm = shortTermLoudnessTimeline(
            for: channels,
            sampleCount: sampleCount,
            sampleRate: signal.sampleRate
        )
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

        let sampleCount = channels.map(\.count).min() ?? 0
        let energyPrefixes = channels.map {
            officialKWeightedEnergyPrefix(for: $0, sampleCount: sampleCount, trailingSilenceCount: 0)
        }
        let gatedBlocks = officialGatedBlockLoudness(forEnergyPrefixes: energyPrefixes, sampleRate: signal.sampleRate)
        return Float(integratedLoudness(from: gatedBlocks))
    }

    static func truePeakLinear(_ channels: [[Float]]) -> Float {
        var peak: Float = 0
        for channel in channels {
            peak = max(peak, oversampledPeak(channel))
        }
        return peak
    }

    static func ungatedLoudnessLUFS(for channels: [[Float]], sampleRate: Double) -> Double {
        let channels = channels.filter { !$0.isEmpty }
        guard !channels.isEmpty else { return -70 }

        let sampleCount = channels.map(\.count).min() ?? 0
        guard sampleCount > 0 else { return -70 }

        let prefixes = channels.map {
            officialKWeightedEnergyPrefix(for: $0, sampleCount: sampleCount, trailingSilenceCount: 0)
        }
        let meanEnergy = prefixes.reduce(0.0) {
            $0 + meanSquare(in: $1, start: 0, end: sampleCount)
        }
        return loudnessLUFS(fromMeanEnergy: meanEnergy)
    }

    private static func integratedLoudness(from gatedBlocks: [Double]) -> Double {
        gatedBlocks.isEmpty ? -70 : energyAverage(gatedBlocks)
    }

    private static func officialGatedBlockLoudness(forEnergyPrefixes prefixes: [[Double]], sampleRate: Double) -> [Double] {
        let sampleCount = prefixes.map { max($0.count - 1, 0) }.min() ?? 0
        guard sampleCount > 0 else { return [] }

        let windowSize = max(Int(sampleRate * 0.4), 1)
        let hopSize = max(Int(sampleRate * 0.1), 1)
        var blockLoudness: [Double] = []
        var start = 0

        while start + windowSize <= sampleCount {
            let end = start + windowSize
            let meanEnergy = prefixes.reduce(0.0) { $0 + meanSquare(in: $1, start: start, end: end) }
            blockLoudness.append(-0.691 + 10 * log10(max(meanEnergy, 1e-12)))
            start += hopSize
        }

        let absoluteGated = blockLoudness.filter { $0 >= -70 }
        guard !absoluteGated.isEmpty else { return [] }
        let preliminary = energyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return relativeGated.isEmpty ? absoluteGated : relativeGated
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
        let totalSampleCount = sampleCount + trailingSilenceCount
        let windowSize = Int(signal.sampleRate * 3.0)
        let hopSize = Int(signal.sampleRate * 0.1)
        guard totalSampleCount >= windowSize else { return nil }

        let windows = fixedWindows(
            sampleCount: totalSampleCount,
            windowSize: windowSize,
            hopSize: hopSize,
            includePartialFinalWindow: false
        )
        let requiredIndices = requiredPrefixIndices(for: windows)
        let prefixes = signal.channels.map {
            sparseOfficialKWeightedEnergyPrefix(
                for: $0,
                sampleCount: sampleCount,
                trailingSilenceCount: trailingSilenceCount,
                requiredIndices: requiredIndices
            )
        }
        let loudnessValues = windows.map { window in
            let meanEnergy = prefixes.reduce(0.0) {
                $0 + meanSquare(in: $1, start: window.start, end: window.end)
            }
            return -0.691 + 10 * log10(max(meanEnergy, 1e-12))
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

    private static func officialGatedBlockLoudness(
        for channels: [[Float]],
        sampleCount: Int,
        sampleRate: Double
    ) -> [Double] {
        guard sampleCount > 0 else { return [] }

        let windowSize = max(Int(sampleRate * 0.4), 1)
        let hopSize = max(Int(sampleRate * 0.1), 1)
        let windows = fixedWindows(
            sampleCount: sampleCount,
            windowSize: windowSize,
            hopSize: hopSize,
            includePartialFinalWindow: false
        )
        let requiredIndices = requiredPrefixIndices(for: windows)
        let prefixes = channels.map {
            sparseOfficialKWeightedEnergyPrefix(
                for: $0,
                sampleCount: sampleCount,
                trailingSilenceCount: 0,
                requiredIndices: requiredIndices
            )
        }
        let blockLoudness = windows.map { window in
            let meanEnergy = prefixes.reduce(0.0) {
                $0 + meanSquare(in: $1, start: window.start, end: window.end)
            }
            return -0.691 + 10 * log10(max(meanEnergy, 1e-12))
        }

        let absoluteGated = blockLoudness.filter { $0 >= -70 }
        guard !absoluteGated.isEmpty else { return [] }
        let preliminary = energyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return relativeGated.isEmpty ? absoluteGated : relativeGated
    }

    private static func sparseOfficialKWeightedEnergyPrefix(
        for channel: [Float],
        sampleCount: Int,
        trailingSilenceCount: Int,
        requiredIndices: [Int]
    ) -> [Int: Double] {
        var preFilter = BiquadFilter(coefficients: officialPreFilterCoefficients)
        var rlbFilter = BiquadFilter(coefficients: officialRLBFilterCoefficients)
        let totalSampleCount = sampleCount + trailingSilenceCount
        var prefix: [Int: Double] = [:]
        prefix.reserveCapacity(requiredIndices.count)
        var requiredIndex = 0
        var cumulativeEnergy = 0.0

        while requiredIndex < requiredIndices.count, requiredIndices[requiredIndex] == 0 {
            prefix[0] = 0
            requiredIndex += 1
        }
        for index in 0..<totalSampleCount {
            let sample = index < sampleCount ? Double(channel[index]) : 0
            let weighted = rlbFilter.process(preFilter.process(sample))
            cumulativeEnergy += weighted * weighted
            let prefixIndex = index + 1
            while requiredIndex < requiredIndices.count, requiredIndices[requiredIndex] == prefixIndex {
                prefix[prefixIndex] = cumulativeEnergy
                requiredIndex += 1
            }
        }
        return prefix
    }

    private static func shortTermLoudnessTimeline(
        for channels: [[Float]],
        sampleCount: Int,
        sampleRate: Double
    ) -> [TimedLevelMetric] {
        guard sampleCount > 0 else { return [] }

        let duration = Double(sampleCount) / sampleRate
        let windowDuration = min(3.0, max(0.4, duration))
        let hopDuration = max(0.25, duration / 96.0)
        let windowSize = max(1, Int(sampleRate * windowDuration))
        let hopSize = max(1, Int(sampleRate * hopDuration))
        let windows = fixedWindows(
            sampleCount: sampleCount,
            windowSize: windowSize,
            hopSize: hopSize,
            includePartialFinalWindow: true
        )
        let requiredIndices = requiredPrefixIndices(for: windows)
        let prefixes = channels.map {
            sparseOfficialKWeightedEnergyPrefix(
                for: $0,
                sampleCount: sampleCount,
                trailingSilenceCount: 0,
                requiredIndices: requiredIndices
            )
        }

        return windows.enumerated().map { index, window in
            let meanEnergy = prefixes.reduce(0.0) {
                $0 + meanSquare(in: $1, start: window.start, end: window.end)
            }
            let time = (Double(window.start + window.end) * 0.5) / sampleRate
            return TimedLevelMetric(id: "loudness-\(index)", time: time, levelDB: loudnessLUFS(fromMeanEnergy: meanEnergy))
        }
    }

    private static func fixedWindows(
        sampleCount: Int,
        windowSize: Int,
        hopSize: Int,
        includePartialFinalWindow: Bool
    ) -> [(start: Int, end: Int)] {
        var windows: [(start: Int, end: Int)] = []
        var start = 0
        while includePartialFinalWindow ? start < sampleCount : start + windowSize <= sampleCount {
            windows.append((start: start, end: min(sampleCount, start + windowSize)))
            start += hopSize
        }
        return windows
    }

    private static func requiredPrefixIndices(for windows: [(start: Int, end: Int)]) -> [Int] {
        Array(Set(windows.flatMap { [$0.start, $0.end] })).sorted()
    }

    private static func meanSquare(in prefix: [Double], start: Int, end: Int) -> Double {
        guard start < end, start >= 0, end < prefix.count else { return 0 }
        return (prefix[end] - prefix[start]) / Double(max(end - start, 1))
    }

    private static func meanSquare(in prefix: [Int: Double], start: Int, end: Int) -> Double {
        guard start < end, start >= 0, let startValue = prefix[start], let endValue = prefix[end] else { return 0 }
        return (endValue - startValue) / Double(max(end - start, 1))
    }

    private static func energyAverage(_ loudnessValues: [Double]) -> Double {
        let meanEnergy = loudnessValues.map { pow(10, $0 / 10) }.reduce(0, +) / Double(max(loudnessValues.count, 1))
        return 10 * log10(max(meanEnergy, 1e-9))
    }

    private static func loudnessLUFS(fromMeanEnergy meanEnergy: Double) -> Double {
        -0.691 + 10 * log10(max(meanEnergy, 1e-12))
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
        var peak = channel.map { abs($0) }.max() ?? 0
        for sampleIndex in channel.indices {
            for phase in truePeakOversamplingPhases {
                var interpolated = 0.0
                for tapIndex in phase.indices {
                    let inputIndex = sampleIndex + tapIndex - truePeakFilterCenter
                    guard channel.indices.contains(inputIndex) else { continue }
                    interpolated += Double(channel[inputIndex]) * phase[tapIndex]
                }
                peak = max(peak, Float(abs(interpolated)))
            }
        }
        return peak
    }

    private static let truePeakFilterCenter = 6

    private static let truePeakOversamplingPhases: [[Double]] = [
        [
            0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000,
            -0.0594482421875, 0.1373291015625, 0.9721679687500, -0.1022949218750,
            0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500
        ],
        [
            -0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250,
            -0.1665039062500, 0.4650878906250, 0.7797851562500, -0.2003173828125,
            0.1015625000000, -0.0582275390625, 0.0330810546875, -0.0189208984375
        ],
        [
            -0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000,
            -0.2003173828125, 0.7797851562500, 0.4650878906250, -0.1665039062500,
            0.0891113281250, -0.0517578125000, 0.0292968750000, -0.0291748046875
        ],
        [
            -0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750,
            -0.1022949218750, 0.9721679687500, 0.1373291015625, -0.0594482421875,
            0.0332031250000, -0.0196533203125, 0.0109863281250, 0.0017089843750
        ]
    ]
}
