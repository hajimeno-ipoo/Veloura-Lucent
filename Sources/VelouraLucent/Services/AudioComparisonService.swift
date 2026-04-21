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
                }
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

        var centroidSum = 0.0
        var frameCount = 0
        var hf12Sum = 0.0
        var hf16Sum = 0.0
        var hf18Sum = 0.0
        var bandEnergySum = Array(repeating: 0.0, count: bandTemplate.count)
        var masteringBandEnergySum = Array(repeating: 0.0, count: masteringBandTemplate.count)

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
                masteringBandEnergySum: &masteringBandEnergySum
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
                    masteringBandEnergySum: &masteringBandEnergySum
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

        return AudioMetricSnapshot(
            peakDBFS: peakDBFS,
            rmsDBFS: rmsDBFS,
            crestFactorDB: peakDBFS - rmsDBFS,
            loudnessRangeLU: loudnessRange(for: mono, sampleRate: signal.sampleRate),
            integratedLoudnessLUFS: Double(masteringAnalysis.integratedLoudness),
            truePeakDBFS: masteringAnalysis.truePeakDBFS,
            stereoWidth: Double(masteringAnalysis.stereoWidth),
            harshnessScore: Double(masteringAnalysis.harshnessScore),
            centroidHz: centroidSum / safeFrameCount,
            hf12Ratio: hf12Sum / safeFrameCount,
            hf16Ratio: hf16Sum / safeFrameCount,
            hf18Ratio: hf18Sum / safeFrameCount,
            bandEnergies: bandMetrics,
            masteringBandEnergies: masteringBandMetrics
        )
    }

    private static let bandTemplate: [(id: String, label: String, range: String, lower: Double, upper: Double)] = AudioBandCatalog.comparisonBands.map {
        ($0.id, $0.label, $0.rangeDescription, $0.lowerBound, $0.upperBound)
    }

    private static let masteringBandTemplate: [(id: String, label: String, range: String, lower: Double, upper: Double)] = AudioBandCatalog.masteringBands.map {
        ($0.id, $0.label, $0.rangeDescription, $0.lowerBound, $0.upperBound)
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
        masteringBandEnergySum: inout [Double]
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

        frameCount += 1
    }

    private static func ratio(power: [Double], freqs: [Double], cutoff: Double, total: Double) -> Double {
        zip(freqs, power)
            .filter { $0.0 >= cutoff }
            .map(\.1)
            .reduce(0.0, +) / total
    }
}
