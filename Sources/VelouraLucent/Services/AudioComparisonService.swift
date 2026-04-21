import Accelerate
import Foundation

enum AudioComparisonService {
    static func analyze(fileURL: URL) throws -> AudioMetricSnapshot {
        let signal = try AudioFileService.loadAudio(from: fileURL)
        return try analyze(signal: signal)
    }

    static func analyze(signal: AudioSignal) throws -> AudioMetricSnapshot {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return emptySnapshot()
        }

        let waveformMetrics = waveformMetrics(for: mono, sampleRate: signal.sampleRate)
        let channelMetrics = channelMetrics(for: signal)
        let frequencyMetrics = try frequencyMetrics(for: mono, sampleRate: signal.sampleRate)
        return snapshot(
            waveformMetrics: waveformMetrics,
            channelMetrics: channelMetrics,
            frequencyMetrics: frequencyMetrics
        )
    }

    static func analyzeConcurrently(signal: AudioSignal) async throws -> AudioMetricSnapshot {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return emptySnapshot()
        }

        let waveformTask = Task.detached(priority: .utility) {
            Self.waveformMetrics(for: mono, sampleRate: signal.sampleRate)
        }
        let channelTask = Task.detached(priority: .utility) {
            Self.channelMetrics(for: signal)
        }
        let frequencyTask = Task.detached(priority: .utility) {
            try Self.frequencyMetrics(for: mono, sampleRate: signal.sampleRate)
        }

        let waveformResult = await waveformTask.value
        let channelResult = await channelTask.value
        let frequencyResult = try await frequencyTask.value
        return snapshot(
            waveformMetrics: waveformResult,
            channelMetrics: channelResult,
            frequencyMetrics: frequencyResult
        )
    }

    private static func emptySnapshot() -> AudioMetricSnapshot {
        AudioMetricSnapshot(
            peakDBFS: -120,
            rmsDBFS: -120,
            crestFactorDB: 0,
            loudnessRangeLU: 0,
            integratedLoudnessLUFS: -70,
            truePeakDBFS: -120,
            stereoWidth: 0,
            stereoCorrelation: 1,
            harshnessScore: 0,
            centroidHz: 0,
            hf12Ratio: 0,
            hf16Ratio: 0,
            hf18Ratio: 0,
            bandEnergies: bandTemplate.map {
                BandEnergyMetric(id: $0.id, label: $0.label, rangeDescription: $0.range, levelDB: -120)
            },
            masteringBandEnergies: masteringBandTemplate.map {
                BandEnergyMetric(id: $0.id, label: $0.label, rangeDescription: $0.range, levelDB: -120)
            },
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: []
        )
    }

    private static func snapshot(
        waveformMetrics: WaveformMetrics,
        channelMetrics: ChannelMetrics,
        frequencyMetrics: FrequencyMetrics
    ) -> AudioMetricSnapshot {
        AudioMetricSnapshot(
            peakDBFS: waveformMetrics.peakDBFS,
            rmsDBFS: waveformMetrics.rmsDBFS,
            crestFactorDB: waveformMetrics.peakDBFS - waveformMetrics.rmsDBFS,
            loudnessRangeLU: waveformMetrics.loudnessRangeLU,
            integratedLoudnessLUFS: waveformMetrics.integratedLoudnessLUFS,
            truePeakDBFS: channelMetrics.truePeakDBFS,
            stereoWidth: channelMetrics.stereoWidth,
            stereoCorrelation: channelMetrics.stereoCorrelation,
            harshnessScore: frequencyMetrics.harshnessScore,
            centroidHz: frequencyMetrics.centroidHz,
            hf12Ratio: frequencyMetrics.hf12Ratio,
            hf16Ratio: frequencyMetrics.hf16Ratio,
            hf18Ratio: frequencyMetrics.hf18Ratio,
            bandEnergies: frequencyMetrics.bandEnergies,
            masteringBandEnergies: frequencyMetrics.masteringBandEnergies,
            shortTermLoudness: waveformMetrics.shortTermLoudness,
            dynamics: waveformMetrics.dynamics,
            averageSpectrum: frequencyMetrics.averageSpectrum
        )
    }

    private static func frequencyMetrics(for mono: [Float], sampleRate: Double) throws -> FrequencyMetrics {
        let frameSize = 16_384
        let hopSize = 8_192
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameSize, isHalfWindow: false)
        let frequencyStep = sampleRate / Double(frameSize)
        let dft = try vDSP.DiscreteFourierTransform<Float>(
            count: frameSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
        let bandRanges = frequencyBandRanges(for: bandTemplate, frequencyStep: frequencyStep, maxBin: frameSize / 2)
        let masteringBandRanges = frequencyBandRanges(for: masteringBandTemplate, frequencyStep: frequencyStep, maxBin: frameSize / 2)
        let spectrumBands = spectrumBandTemplate(sampleRate: sampleRate, frameSize: frameSize)
        let hf12Start = lowerBin(for: 12_000, frequencyStep: frequencyStep, maxBin: frameSize / 2)
        let hf16Start = lowerBin(for: 16_000, frequencyStep: frequencyStep, maxBin: frameSize / 2)
        let hf18Start = lowerBin(for: 18_000, frequencyStep: frequencyStep, maxBin: frameSize / 2)
        let harshnessUpperMidRange = FrequencyBandRange(
            lower: lowerBin(for: 3_000, frequencyStep: frequencyStep, maxBin: frameSize / 2),
            upperExclusive: lowerBin(for: 8_000, frequencyStep: frequencyStep, maxBin: frameSize / 2)
        )
        let harshnessAirRange = FrequencyBandRange(
            lower: lowerBin(for: 12_000, frequencyStep: frequencyStep, maxBin: frameSize / 2),
            upperExclusive: frameSize / 2 + 1
        )

        var centroidSum = 0.0
        var frameCount = 0
        var hf12Sum = 0.0
        var hf16Sum = 0.0
        var hf18Sum = 0.0
        var harshnessUpperMidSum = 0.0
        var harshnessAirSum = 0.0
        var bandEnergySum = Array(repeating: 0.0, count: bandTemplate.count)
        var masteringBandEnergySum = Array(repeating: 0.0, count: masteringBandTemplate.count)
        var spectrumEnergySum = Array(repeating: 0.0, count: spectrumBands.count)

        if mono.count < frameSize {
            let padded = mono + Array(repeating: Float.zero, count: frameSize - mono.count)
            accumulateMetrics(
                frame: padded,
                window: window,
                dft: dft,
                frequencyStep: frequencyStep,
                hf12Start: hf12Start,
                hf16Start: hf16Start,
                hf18Start: hf18Start,
                centroidSum: &centroidSum,
                frameCount: &frameCount,
                hf12Sum: &hf12Sum,
                hf16Sum: &hf16Sum,
                hf18Sum: &hf18Sum,
                harshnessUpperMidRange: harshnessUpperMidRange,
                harshnessAirRange: harshnessAirRange,
                harshnessUpperMidSum: &harshnessUpperMidSum,
                harshnessAirSum: &harshnessAirSum,
                bandRanges: bandRanges,
                bandEnergySum: &bandEnergySum,
                masteringBandRanges: masteringBandRanges,
                masteringBandEnergySum: &masteringBandEnergySum,
                spectrumBands: spectrumBands,
                spectrumEnergySum: &spectrumEnergySum
            )
        } else {
            var start = 0
            while start + frameSize <= mono.count {
                let frame = Array(mono[start..<(start + frameSize)])
                accumulateMetrics(
                    frame: frame,
                    window: window,
                    dft: dft,
                    frequencyStep: frequencyStep,
                    hf12Start: hf12Start,
                    hf16Start: hf16Start,
                    hf18Start: hf18Start,
                    centroidSum: &centroidSum,
                    frameCount: &frameCount,
                    hf12Sum: &hf12Sum,
                    hf16Sum: &hf16Sum,
                    hf18Sum: &hf18Sum,
                    harshnessUpperMidRange: harshnessUpperMidRange,
                    harshnessAirRange: harshnessAirRange,
                    harshnessUpperMidSum: &harshnessUpperMidSum,
                    harshnessAirSum: &harshnessAirSum,
                    bandRanges: bandRanges,
                    bandEnergySum: &bandEnergySum,
                    masteringBandRanges: masteringBandRanges,
                    masteringBandEnergySum: &masteringBandEnergySum,
                    spectrumBands: spectrumBands,
                    spectrumEnergySum: &spectrumEnergySum
                )
                start += hopSize
            }
        }

        let safeFrameCount = Double(max(frameCount, 1))
        let bandMetrics = zip(bandTemplate, bandEnergySum).map { template, value in
            BandEnergyMetric(
                id: template.id,
                label: template.label,
                rangeDescription: template.range,
                levelDB: 20 * log10(max(value / safeFrameCount, 1e-12))
            )
        }
        let masteringBandMetrics = zip(masteringBandTemplate, masteringBandEnergySum).map { template, value in
            BandEnergyMetric(
                id: template.id,
                label: template.label,
                rangeDescription: template.range,
                levelDB: 20 * log10(max(value / safeFrameCount, 1e-12))
            )
        }
        let spectrumMetrics = zip(spectrumBands, spectrumEnergySum).map { band, value in
            SpectrumMetric(
                id: band.id,
                frequencyHz: band.center,
                levelDB: 20 * log10(max(value / safeFrameCount, 1e-12))
            )
        }
        let harshnessScore = min(1.0, harshnessUpperMidSum / max(harshnessUpperMidSum + harshnessAirSum, 1e-9))

        return FrequencyMetrics(
            harshnessScore: harshnessScore,
            centroidHz: centroidSum / safeFrameCount,
            hf12Ratio: hf12Sum / safeFrameCount,
            hf16Ratio: hf16Sum / safeFrameCount,
            hf18Ratio: hf18Sum / safeFrameCount,
            bandEnergies: bandMetrics,
            masteringBandEnergies: masteringBandMetrics,
            averageSpectrum: spectrumMetrics
        )
    }

    private static let bandTemplate: [(id: String, label: String, range: String, lower: Double, upper: Double)] = AudioBandCatalog.comparisonBands.map {
        ($0.id, $0.label, $0.rangeDescription, $0.lowerBound, $0.upperBound)
    }

    private static let masteringBandTemplate: [(id: String, label: String, range: String, lower: Double, upper: Double)] = AudioBandCatalog.masteringBands.map {
        ($0.id, $0.label, $0.rangeDescription, $0.lowerBound, $0.upperBound)
    }

    private struct FrequencyBandRange {
        let lower: Int
        let upperExclusive: Int
    }

    private struct WaveformMetrics: Sendable {
        let peakDBFS: Double
        let rmsDBFS: Double
        let loudnessRangeLU: Double
        let integratedLoudnessLUFS: Double
        let shortTermLoudness: [TimedLevelMetric]
        let dynamics: [DynamicsMetric]
    }

    private struct ChannelMetrics: Sendable {
        let truePeakDBFS: Double
        let stereoWidth: Double
        let stereoCorrelation: Double
    }

    private struct FrequencyMetrics: Sendable {
        let harshnessScore: Double
        let centroidHz: Double
        let hf12Ratio: Double
        let hf16Ratio: Double
        let hf18Ratio: Double
        let bandEnergies: [BandEnergyMetric]
        let masteringBandEnergies: [BandEnergyMetric]
        let averageSpectrum: [SpectrumMetric]
    }

    private static func frequencyBandRanges(
        for templates: [(id: String, label: String, range: String, lower: Double, upper: Double)],
        frequencyStep: Double,
        maxBin: Int
    ) -> [FrequencyBandRange] {
        templates.map { band in
            let lower = lowerBin(for: band.lower, frequencyStep: frequencyStep, maxBin: maxBin)
            let upperExclusive = max(lower, min(Int(ceil(band.upper / frequencyStep)), maxBin + 1))
            return FrequencyBandRange(lower: lower, upperExclusive: upperExclusive)
        }
    }

    private static func lowerBin(for frequency: Double, frequencyStep: Double, maxBin: Int) -> Int {
        max(0, min(Int(ceil(frequency / frequencyStep)), maxBin + 1))
    }

    private static func spectrumBandTemplate(sampleRate: Double, frameSize: Int) -> [(id: String, center: Double, lower: Int, upper: Int)] {
        let bandCount = 32
        let minFrequency = 80.0
        let maxFrequency = min(20_000.0, sampleRate * 0.5)
        let frequencyStep = sampleRate / Double(frameSize)

        return (0..<bandCount).map { index in
            let lowerRatio = Double(index) / Double(bandCount)
            let upperRatio = Double(index + 1) / Double(bandCount)
            let lowerFrequency = minFrequency * pow(maxFrequency / minFrequency, lowerRatio)
            let upperFrequency = minFrequency * pow(maxFrequency / minFrequency, upperRatio)
            let centerFrequency = sqrt(lowerFrequency * upperFrequency)
            let lowerBin = max(0, min(Int(floor(lowerFrequency / frequencyStep)), frameSize / 2))
            let upperBin = max(lowerBin, min(Int(ceil(upperFrequency / frequencyStep)), frameSize / 2))
            return (
                id: "spectrum-\(index)",
                center: centerFrequency,
                lower: lowerBin,
                upper: upperBin
            )
        }
    }

    private struct WaveformSummary {
        let peak: Float
        let rms: Float
        let dynamics: [DynamicsMetric]
    }

    private static func waveformMetrics(for mono: [Float], sampleRate: Double) -> WaveformMetrics {
        let summary = waveformSummary(for: mono, sampleRate: sampleRate)
        let monoEnergyPrefix = energyPrefix(for: mono)
        let weighted = kWeighted(mono, sampleRate: sampleRate)
        let weightedEnergyPrefix = energyPrefix(for: weighted)
        let peakDBFS = 20 * log10(max(Double(summary.peak), 1e-12))
        let rmsDBFS = 20 * log10(max(Double(summary.rms), 1e-12))

        return WaveformMetrics(
            peakDBFS: peakDBFS,
            rmsDBFS: rmsDBFS,
            loudnessRangeLU: loudnessRange(forEnergyPrefix: monoEnergyPrefix, sampleRate: sampleRate),
            integratedLoudnessLUFS: integratedLoudness(forEnergyPrefix: weightedEnergyPrefix, sampleRate: sampleRate),
            shortTermLoudness: shortTermLoudnessTimeline(forEnergyPrefix: weightedEnergyPrefix, sampleRate: sampleRate),
            dynamics: summary.dynamics
        )
    }

    private static func channelMetrics(for signal: AudioSignal) -> ChannelMetrics {
        ChannelMetrics(
            truePeakDBFS: 20 * log10(max(Double(MasteringAnalysisService.approximateTruePeak(signal.channels)), 1e-12)),
            stereoWidth: Double(MasteringAnalysisService.stereoWidth(for: signal)),
            stereoCorrelation: stereoCorrelation(for: signal)
        )
    }

    private static func waveformSummary(for mono: [Float], sampleRate: Double) -> WaveformSummary {
        guard !mono.isEmpty else {
            return WaveformSummary(peak: 0, rms: 0, dynamics: [])
        }

        let duration = Double(mono.count) / sampleRate
        let bucketCount = min(120, max(1, Int(ceil(duration / 0.5))))
        let bucketSize = max(1, Int(ceil(Double(mono.count) / Double(bucketCount))))
        var globalPeak: Float = 0
        var globalEnergy: Float = 0
        var dynamics: [DynamicsMetric] = []
        dynamics.reserveCapacity(bucketCount)

        for bucketIndex in 0..<bucketCount {
            let start = bucketIndex * bucketSize
            let end = min(mono.count, start + bucketSize)
            guard start < end else { continue }

            var peak: Float = 0
            var energy: Float = 0
            for index in start..<end {
                let sample = mono[index]
                let magnitude = abs(sample)
                peak = max(peak, magnitude)
                energy += sample * sample
            }
            globalPeak = max(globalPeak, peak)
            globalEnergy += energy

            let rms = sqrt(max(energy / Float(max(end - start, 1)), 1e-12))
            let peakDBFS = 20 * log10(max(Double(peak), 1e-12))
            let rmsDBFS = 20 * log10(max(Double(rms), 1e-12))
            let time = (Double(start + end) * 0.5) / sampleRate
            dynamics.append(
                DynamicsMetric(
                    id: "dynamics-\(bucketIndex)",
                    time: time,
                    peakDBFS: peakDBFS,
                    rmsDBFS: rmsDBFS,
                    crestFactorDB: peakDBFS - rmsDBFS
                )
            )
        }

        let rms = sqrt(max(globalEnergy / Float(mono.count), 1e-12))
        return WaveformSummary(peak: globalPeak, rms: rms, dynamics: dynamics)
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

    private static func integratedLoudness(forEnergyPrefix prefix: [Double], sampleRate: Double) -> Double {
        let sampleCount = max(prefix.count - 1, 0)
        guard sampleCount > 0 else { return -70 }

        let windowSize = max(Int(sampleRate * 0.4), 1)
        let hopSize = max(Int(sampleRate * 0.1), 1)
        var blockLoudness: [Double] = []
        var start = 0

        while start < sampleCount {
            let end = min(sampleCount, start + windowSize)
            let rms = sqrt(max(meanSquare(in: prefix, start: start, end: end), 1e-9))
            blockLoudness.append(20 * log10(max(rms, 1e-12)))
            start += hopSize
        }

        let absoluteGated = blockLoudness.filter { $0 > -70 }
        guard !absoluteGated.isEmpty else { return -70 }
        let preliminary = energyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return energyAverage(relativeGated.isEmpty ? absoluteGated : relativeGated)
    }

    private static func loudnessRange(forEnergyPrefix prefix: [Double], sampleRate: Double) -> Double {
        let sampleCount = max(prefix.count - 1, 0)
        guard sampleCount > 0 else { return 0 }

        let windowSize = max(Int(sampleRate * 0.4), 1)
        let hopSize = max(Int(sampleRate * 0.1), 1)
        var blockLevels: [Double] = []
        var start = 0

        while start < sampleCount {
            let end = min(sampleCount, start + windowSize)
            let rms = sqrt(max(meanSquare(in: prefix, start: start, end: end), 1e-12))
            blockLevels.append(20 * log10(max(rms, 1e-12)))
            start += hopSize
        }

        let gated = blockLevels.filter { $0 > -70 }.sorted()
        guard gated.count > 5 else { return 0 }
        return percentile(gated, 0.95) - percentile(gated, 0.10)
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        let index = max(0, min(values.count - 1, Int(round(Double(values.count - 1) * percentile))))
        return values[index]
    }

    private static func accumulateMetrics(
        frame: [Float],
        window: [Float],
        dft: vDSP.DiscreteFourierTransform<Float>,
        frequencyStep: Double,
        hf12Start: Int,
        hf16Start: Int,
        hf18Start: Int,
        centroidSum: inout Double,
        frameCount: inout Int,
        hf12Sum: inout Double,
        hf16Sum: inout Double,
        hf18Sum: inout Double,
        harshnessUpperMidRange: FrequencyBandRange,
        harshnessAirRange: FrequencyBandRange,
        harshnessUpperMidSum: inout Double,
        harshnessAirSum: inout Double,
        bandRanges: [FrequencyBandRange],
        bandEnergySum: inout [Double],
        masteringBandRanges: [FrequencyBandRange],
        masteringBandEnergySum: inout [Double],
        spectrumBands: [(id: String, center: Double, lower: Int, upper: Int)],
        spectrumEnergySum: inout [Double]
    ) {
        var windowed = Array(repeating: Float.zero, count: frame.count)
        vDSP.multiply(frame, window, result: &windowed)

        let inputImag = Array(repeating: Float.zero, count: frame.count)
        var outputReal = Array(repeating: Float.zero, count: frame.count)
        var outputImag = Array(repeating: Float.zero, count: frame.count)
        dft.transform(inputReal: windowed, inputImaginary: inputImag, outputReal: &outputReal, outputImaginary: &outputImag)

        let halfCount = frame.count / 2 + 1
        var power = Array(repeating: 0.0, count: halfCount)
        var total = 1e-18
        for index in 0..<halfCount {
            let value = Double(outputReal[index] * outputReal[index] + outputImag[index] * outputImag[index])
            power[index] = value
            total += value
        }

        var weightedFrequencySum = 0.0
        for index in 0..<halfCount {
            weightedFrequencySum += Double(index) * frequencyStep * power[index]
        }
        centroidSum += weightedFrequencySum / total
        hf12Sum += ratio(power: power, startIndex: hf12Start, total: total)
        hf16Sum += ratio(power: power, startIndex: hf16Start, total: total)
        hf18Sum += ratio(power: power, startIndex: hf18Start, total: total)
        harshnessUpperMidSum += magnitudeSum(power, lower: harshnessUpperMidRange.lower, upperExclusive: harshnessUpperMidRange.upperExclusive)
        harshnessAirSum += magnitudeSum(power, lower: harshnessAirRange.lower, upperExclusive: harshnessAirRange.upperExclusive)

        for (index, band) in bandRanges.enumerated() {
            let mean = meanPower(power, lower: band.lower, upperExclusive: band.upperExclusive)
            bandEnergySum[index] += sqrt(mean)
        }

        for (index, band) in masteringBandRanges.enumerated() {
            let mean = meanPower(power, lower: band.lower, upperExclusive: band.upperExclusive)
            masteringBandEnergySum[index] += sqrt(mean)
        }

        for (index, band) in spectrumBands.enumerated() {
            let mean = meanPower(power, lower: band.lower, upperInclusive: band.upper)
            spectrumEnergySum[index] += sqrt(mean)
        }

        frameCount += 1
    }

    private static func meanPower(_ power: [Double], lower: Int, upperExclusive: Int) -> Double {
        guard lower < upperExclusive, lower < power.count else { return 1e-12 }
        let upper = min(upperExclusive, power.count)
        var sum = 0.0
        for index in lower..<upper {
            sum += power[index]
        }
        return sum / Double(max(upper - lower, 1))
    }

    private static func meanPower(_ power: [Double], lower: Int, upperInclusive: Int) -> Double {
        guard lower <= upperInclusive, lower < power.count else { return 1e-12 }
        let upper = min(upperInclusive, power.count - 1)
        var sum = 0.0
        for index in lower...upper {
            sum += power[index]
        }
        return sum / Double(max(upper - lower + 1, 1))
    }

    private static func magnitudeSum(_ power: [Double], lower: Int, upperExclusive: Int) -> Double {
        guard lower < upperExclusive, lower < power.count else { return 0 }
        let upper = min(upperExclusive, power.count)
        var sum = 0.0
        for index in lower..<upper {
            sum += sqrt(power[index])
        }
        return sum
    }

    private static func ratio(power: [Double], startIndex: Int, total: Double) -> Double {
        guard startIndex < power.count else { return 0 }
        var sum = 0.0
        for index in startIndex..<power.count {
            sum += power[index]
        }
        return sum / total
    }

    private static func shortTermLoudnessTimeline(forEnergyPrefix prefix: [Double], sampleRate: Double) -> [TimedLevelMetric] {
        let sampleCount = max(prefix.count - 1, 0)
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
            let rms = sqrt(max(meanSquare(in: prefix, start: start, end: end), 1e-12))
            let time = (Double(start + end) * 0.5) / sampleRate
            values.append(TimedLevelMetric(id: "loudness-\(index)", time: time, levelDB: 20 * log10(max(rms, 1e-12))))
            start += hopSize
            index += 1
        }
        return values
    }

    private static func stereoCorrelation(for signal: AudioSignal) -> Double {
        guard signal.channels.count >= 2 else { return 1 }
        let left = signal.channels[0]
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return 1 }

        var leftEnergy = 0.0
        var rightEnergy = 0.0
        var sharedEnergy = 0.0
        for index in 0..<count {
            let leftValue = Double(left[index])
            let rightValue = Double(right[index])
            leftEnergy += leftValue * leftValue
            rightEnergy += rightValue * rightValue
            sharedEnergy += leftValue * rightValue
        }

        let denominator = sqrt(leftEnergy * rightEnergy)
        guard denominator > 1e-12 else { return 1 }
        return max(-1, min(1, sharedEnergy / denominator))
    }

    private static func kWeighted(_ signal: [Float], sampleRate: Double) -> [Float] {
        let highPassed = SpectralDSP.highPass(signal, cutoff: 60, sampleRate: sampleRate)
        let shelfBase = SpectralDSP.highPass(signal, cutoff: 1_500, sampleRate: sampleRate)
        return zip(highPassed, shelfBase).map { $0 + $1 * 0.25 }
    }

    private static func energyAverage(_ loudnessValues: [Double]) -> Double {
        let meanEnergy = loudnessValues.map { pow(10, $0 / 10) }.reduce(0, +) / Double(max(loudnessValues.count, 1))
        return 10 * log10(max(meanEnergy, 1e-9))
    }
}
