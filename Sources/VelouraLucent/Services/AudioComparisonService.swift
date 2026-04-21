import Accelerate
import Foundation

enum AudioComparisonService {
    static func analyze(fileURL: URL) throws -> AudioMetricSnapshot {
        let signal = try AudioFileService.loadAudio(from: fileURL)
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return AudioMetricSnapshot(
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

        let masteringAnalysis = MasteringAnalysisService.analyze(signal: signal)
        let peak = mono.map { abs($0) }.max() ?? 0
        let rms = sqrt(max(mono.reduce(0) { $0 + $1 * $1 } / Float(mono.count), 1e-12))
        let peakDBFS = 20 * log10(max(Double(peak), 1e-12))
        let rmsDBFS = 20 * log10(max(Double(rms), 1e-12))
        let frameSize = 16_384
        let hopSize = 8_192
        let window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: frameSize, isHalfWindow: false)
        let dft = try vDSP.DiscreteFourierTransform<Float>(
            count: frameSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )
        let freqs = (0...(frameSize / 2)).map { Double($0) * signal.sampleRate / Double(frameSize) }
        let spectrumBands = spectrumBandTemplate(sampleRate: signal.sampleRate, frameSize: frameSize)

        var centroidSum = 0.0
        var frameCount = 0
        var hf12Sum = 0.0
        var hf16Sum = 0.0
        var hf18Sum = 0.0
        var bandEnergySum = Array(repeating: 0.0, count: bandTemplate.count)
        var masteringBandEnergySum = Array(repeating: 0.0, count: masteringBandTemplate.count)
        var spectrumEnergySum = Array(repeating: 0.0, count: spectrumBands.count)

        if mono.count < frameSize {
            let padded = mono + Array(repeating: Float.zero, count: frameSize - mono.count)
            accumulateMetrics(
                frame: padded,
                window: window,
                dft: dft,
                freqs: freqs,
                centroidSum: &centroidSum,
                frameCount: &frameCount,
                hf12Sum: &hf12Sum,
                hf16Sum: &hf16Sum,
                hf18Sum: &hf18Sum,
                bandEnergySum: &bandEnergySum,
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
                    freqs: freqs,
                    centroidSum: &centroidSum,
                    frameCount: &frameCount,
                    hf12Sum: &hf12Sum,
                    hf16Sum: &hf16Sum,
                    hf18Sum: &hf18Sum,
                    bandEnergySum: &bandEnergySum,
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

        return AudioMetricSnapshot(
            peakDBFS: peakDBFS,
            rmsDBFS: rmsDBFS,
            crestFactorDB: peakDBFS - rmsDBFS,
            loudnessRangeLU: loudnessRange(for: mono, sampleRate: signal.sampleRate),
            integratedLoudnessLUFS: Double(masteringAnalysis.integratedLoudness),
            truePeakDBFS: masteringAnalysis.truePeakDBFS,
            stereoWidth: Double(masteringAnalysis.stereoWidth),
            stereoCorrelation: stereoCorrelation(for: signal),
            harshnessScore: Double(masteringAnalysis.harshnessScore),
            centroidHz: centroidSum / safeFrameCount,
            hf12Ratio: hf12Sum / safeFrameCount,
            hf16Ratio: hf16Sum / safeFrameCount,
            hf18Ratio: hf18Sum / safeFrameCount,
            bandEnergies: bandMetrics,
            masteringBandEnergies: masteringBandMetrics,
            shortTermLoudness: shortTermLoudnessTimeline(for: signal),
            dynamics: dynamicsTimeline(for: mono, sampleRate: signal.sampleRate),
            averageSpectrum: spectrumMetrics
        )
    }

    private static let bandTemplate: [(id: String, label: String, range: String, lower: Double, upper: Double)] = AudioBandCatalog.comparisonBands.map {
        ($0.id, $0.label, $0.rangeDescription, $0.lowerBound, $0.upperBound)
    }

    private static let masteringBandTemplate: [(id: String, label: String, range: String, lower: Double, upper: Double)] = AudioBandCatalog.masteringBands.map {
        ($0.id, $0.label, $0.rangeDescription, $0.lowerBound, $0.upperBound)
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

    private static func loudnessRange(for mono: [Float], sampleRate: Double) -> Double {
        let windowSize = max(Int(sampleRate * 0.4), 1)
        let hopSize = max(Int(sampleRate * 0.1), 1)
        var blockLevels: [Double] = []
        var start = 0

        while start < mono.count {
            let end = min(mono.count, start + windowSize)
            let block = mono[start..<end]
            let rms = sqrt(max(block.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(block.count, 1)), 1e-12))
            blockLevels.append(20 * log10(max(Double(rms), 1e-12)))
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
        freqs: [Double],
        centroidSum: inout Double,
        frameCount: inout Int,
        hf12Sum: inout Double,
        hf16Sum: inout Double,
        hf18Sum: inout Double,
        bandEnergySum: inout [Double],
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

        centroidSum += zip(freqs, power).reduce(0.0) { $0 + ($1.0 * $1.1 / total) }
        hf12Sum += ratio(power: power, freqs: freqs, cutoff: 12_000, total: total)
        hf16Sum += ratio(power: power, freqs: freqs, cutoff: 16_000, total: total)
        hf18Sum += ratio(power: power, freqs: freqs, cutoff: 18_000, total: total)

        for (index, band) in bandTemplate.enumerated() {
            let values = zip(freqs, power).filter { $0.0 >= band.lower && $0.0 < band.upper }.map(\.1)
            let mean = values.isEmpty ? 1e-12 : values.reduce(0.0, +) / Double(values.count)
            bandEnergySum[index] += sqrt(mean)
        }

        for (index, band) in masteringBandTemplate.enumerated() {
            let values = zip(freqs, power).filter { $0.0 >= band.lower && $0.0 < band.upper }.map(\.1)
            let mean = values.isEmpty ? 1e-12 : values.reduce(0.0, +) / Double(values.count)
            masteringBandEnergySum[index] += sqrt(mean)
        }

        for (index, band) in spectrumBands.enumerated() {
            let values = power[band.lower...band.upper]
            let mean = values.reduce(0.0, +) / Double(max(values.count, 1))
            spectrumEnergySum[index] += sqrt(mean)
        }

        frameCount += 1
    }

    private static func ratio(power: [Double], freqs: [Double], cutoff: Double, total: Double) -> Double {
        zip(freqs, power)
            .filter { $0.0 >= cutoff }
            .map(\.1)
            .reduce(0.0, +) / total
    }

    private static func shortTermLoudnessTimeline(for signal: AudioSignal) -> [TimedLevelMetric] {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else { return [] }

        let weighted = kWeighted(mono, sampleRate: signal.sampleRate)
        let duration = Double(weighted.count) / signal.sampleRate
        let windowDuration = min(3.0, max(0.4, duration))
        let hopDuration = max(0.25, duration / 96.0)
        let windowSize = max(1, Int(signal.sampleRate * windowDuration))
        let hopSize = max(1, Int(signal.sampleRate * hopDuration))

        var values: [TimedLevelMetric] = []
        var start = 0
        var index = 0
        while start < weighted.count {
            let end = min(weighted.count, start + windowSize)
            guard start < end else { break }
            let slice = weighted[start..<end]
            let rms = sqrt(max(slice.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(slice.count, 1)), 1e-12))
            let time = (Double(start + end) * 0.5) / signal.sampleRate
            values.append(TimedLevelMetric(id: "loudness-\(index)", time: time, levelDB: Double(20 * log10f(rms))))
            start += hopSize
            index += 1
        }
        return values
    }

    private static func dynamicsTimeline(for mono: [Float], sampleRate: Double) -> [DynamicsMetric] {
        guard !mono.isEmpty else { return [] }

        let duration = Double(mono.count) / sampleRate
        let bucketCount = min(120, max(1, Int(ceil(duration / 0.5))))
        let bucketSize = max(1, Int(ceil(Double(mono.count) / Double(bucketCount))))

        return (0..<bucketCount).compactMap { bucketIndex in
            let start = bucketIndex * bucketSize
            let end = min(mono.count, start + bucketSize)
            guard start < end else { return nil }

            let slice = mono[start..<end]
            let peak = slice.map { abs($0) }.max() ?? 0
            let rms = sqrt(max(slice.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(slice.count, 1)), 1e-12))
            let peakDBFS = 20 * log10(max(Double(peak), 1e-12))
            let rmsDBFS = 20 * log10(max(Double(rms), 1e-12))
            let time = (Double(start + end) * 0.5) / sampleRate
            return DynamicsMetric(
                id: "dynamics-\(bucketIndex)",
                time: time,
                peakDBFS: peakDBFS,
                rmsDBFS: rmsDBFS,
                crestFactorDB: peakDBFS - rmsDBFS
            )
        }
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
}
