import Accelerate
import Foundation

enum MasteringAnalysisService {
    static func analyze(fileURL: URL) throws -> MasteringAnalysis {
        let signal = try AudioFileService.loadAudio(from: fileURL)
        return analyze(signal: signal)
    }

    static func analyze(signal: AudioSignal) -> MasteringAnalysis {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return MasteringAnalysis(
                integratedLoudness: -70,
                truePeakDBFS: -120,
                lowBandLevelDB: -120,
                midBandLevelDB: -120,
                highBandLevelDB: -120,
                harshnessScore: 0,
                stereoWidth: 0
            )
        }

        let loudness = integratedLoudness(signal: signal)
        let peak = approximateTruePeak(signal.channels)
        let bandLevels = bandLevels(for: mono, sampleRate: signal.sampleRate)
        let harshness = harshnessScore(for: mono, sampleRate: signal.sampleRate)
        let width = stereoWidth(for: signal)

        return MasteringAnalysis(
            integratedLoudness: loudness,
            truePeakDBFS: 20 * log10(max(Double(peak), 1e-12)),
            lowBandLevelDB: bandLevels.low,
            midBandLevelDB: bandLevels.mid,
            highBandLevelDB: bandLevels.high,
            harshnessScore: harshness,
            stereoWidth: width
        )
    }

    static func integratedLoudness(signal: AudioSignal) -> Float {
        let weighted = kWeight(signal.monoMixdown(), sampleRate: signal.sampleRate)
        let windowSize = max(Int(signal.sampleRate * 0.4), 1)
        let hopSize = max(Int(signal.sampleRate * 0.1), 1)
        var blockLoudness: [Float] = []
        var start = 0

        while start < weighted.count {
            let end = min(weighted.count, start + windowSize)
            let block = Array(weighted[start..<end])
            let rms = sqrt(max(block.reduce(0) { $0 + $1 * $1 } / Float(max(block.count, 1)), 1e-9))
            blockLoudness.append(20 * log10f(rms))
            start += hopSize
        }

        let absoluteGated = blockLoudness.filter { $0 > -70 }
        guard !absoluteGated.isEmpty else { return -70 }
        let preliminary = energyAverage(absoluteGated)
        let relativeGate = preliminary - 10
        let relativeGated = absoluteGated.filter { $0 >= relativeGate }
        return energyAverage(relativeGated.isEmpty ? absoluteGated : relativeGated)
    }

    static func approximateTruePeak(_ channels: [[Float]]) -> Float {
        channels.map(oversampledPeak).max() ?? 0
    }

    private static func bandLevels(for mono: [Float], sampleRate: Double) -> (low: Double, mid: Double, high: Double) {
        let spectrogram = SpectralDSP.stft(mono)
        guard spectrogram.frameCount > 0 else {
            return (-120, -120, -120)
        }

        let magnitudes = spectrogram.magnitudes()
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let low = meanBandLevel(magnitudes: magnitudes, range: 20...180, frequencyStep: frequencyStep)
        let mid = meanBandLevel(magnitudes: magnitudes, range: 180...5_000, frequencyStep: frequencyStep)
        let high = meanBandLevel(magnitudes: magnitudes, range: 5_000...20_000, frequencyStep: frequencyStep)
        return (low, mid, high)
    }

    private static func meanBandLevel(magnitudes: [[Float]], range: ClosedRange<Double>, frequencyStep: Double) -> Double {
        guard let firstFrame = magnitudes.first, !firstFrame.isEmpty else { return -120 }
        let lower = max(0, min(Int(range.lowerBound / frequencyStep), firstFrame.count - 1))
        let upper = max(lower, min(Int(range.upperBound / frequencyStep), firstFrame.count - 1))
        let values = magnitudes.flatMap { frame in frame[lower...upper] }
        guard !values.isEmpty else { return -120 }
        let rms = sqrt(values.reduce(0) { $0 + $1 * $1 } / Float(values.count))
        return 20 * log10(max(Double(rms), 1e-12))
    }

    private static func harshnessScore(for mono: [Float], sampleRate: Double) -> Float {
        let spectrogram = SpectralDSP.stft(mono)
        guard spectrogram.frameCount > 0 else { return 0 }
        let meanSpectrum = spectrogram.meanMagnitudes()
        let step = sampleRate / Double(spectrogram.fftSize)
        let upperMidStart = max(0, min(Int(3_000 / step), meanSpectrum.count - 1))
        let upperMidEnd = max(upperMidStart, min(Int(8_000 / step), meanSpectrum.count - 1))
        let airStart = max(upperMidEnd, min(Int(12_000 / step), meanSpectrum.count - 1))
        let upperMid = meanSpectrum[upperMidStart...upperMidEnd].reduce(0, +)
        let air = meanSpectrum[airStart...(meanSpectrum.count - 1)].reduce(0, +)
        return min(1.0, upperMid / max(upperMid + air, 1e-6))
    }

    private static func stereoWidth(for signal: AudioSignal) -> Float {
        guard signal.channels.count >= 2 else { return 0 }
        let left = signal.channels[0]
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return 0 }
        var midEnergy: Float = 0
        var sideEnergy: Float = 0
        for index in 0..<count {
            let mid = (left[index] + right[index]) * 0.5
            let side = (left[index] - right[index]) * 0.5
            midEnergy += mid * mid
            sideEnergy += side * side
        }
        return min(2.0, sqrt(sideEnergy / max(midEnergy, 1e-9)))
    }

    private static func energyAverage(_ loudnessValues: [Float]) -> Float {
        let meanEnergy = loudnessValues.map { powf(10, $0 / 10) }.reduce(0, +) / Float(max(loudnessValues.count, 1))
        return 10 * log10f(max(meanEnergy, 1e-9))
    }

    private static func kWeight(_ signal: [Float], sampleRate: Double) -> [Float] {
        let highPassed = SpectralDSP.highPass(signal, cutoff: 60, sampleRate: sampleRate)
        let shelfBase = SpectralDSP.highPass(signal, cutoff: 1_500, sampleRate: sampleRate)
        return zip(highPassed, shelfBase).map { $0 + $1 * 0.25 }
    }

    private static func oversampledPeak(_ channel: [Float]) -> Float {
        guard channel.count > 1 else { return channel.map { abs($0) }.max() ?? 0 }
        var peak: Float = 0
        for index in 0..<(channel.count - 1) {
            let a = channel[index]
            let b = channel[index + 1]
            for step in 0...3 {
                let t = Float(step) / 4
                peak = max(peak, abs(a * (1 - t) + b * t))
            }
        }
        return peak
    }
}
