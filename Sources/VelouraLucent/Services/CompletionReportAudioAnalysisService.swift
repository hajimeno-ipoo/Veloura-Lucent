import Foundation

enum CompletionReportAudioAnalysisService {
    private static let envelopeRateHz = 50.0
    private static let rms400MillisecondRateHz = 2.5
    private static let maximumDisplayWaveformPoints = 900

    static func analyze(
        signal: AudioSignal,
        mono: [Float],
        averageSpectrum: [SpectrumMetric]
    ) -> CompletionReportAudioAnalysis {
        analyze(
            signal: signal,
            mono: mono,
            averageSpectrum: averageSpectrum,
            cancellationCheck: {}
        )
    }

    static func analyze(
        signal: AudioSignal,
        mono: [Float],
        averageSpectrum: [SpectrumMetric],
        cancellationCheck: () throws -> Void
    ) rethrows -> CompletionReportAudioAnalysis {
        guard signal.sampleRate > 0, !mono.isEmpty else { return .unavailable }

        try cancellationCheck()
        let envelope = try rmsEnvelope(
            mono,
            sampleRate: signal.sampleRate,
            outputRate: envelopeRateHz,
            cancellationCheck: cancellationCheck
        )
        let tempo = try estimatedTempo(
            from: envelope,
            sampleRate: envelopeRateHz,
            cancellationCheck: cancellationCheck
        )
        try cancellationCheck()
        let key = estimatedKey(from: averageSpectrum)
        let peakCounts = try peakSampleCounts(
            signal: signal,
            cancellationCheck: cancellationCheck
        )
        let densityTransitionTimes = try densityTransitions(
            in: envelope,
            sampleRate: envelopeRateHz,
            cancellationCheck: cancellationCheck
        )
        let lowBandCorrelation = try lowBandStereoCorrelation(
            signal: signal,
            cancellationCheck: cancellationCheck
        )
        let sideMidRatio = try sideMidRatioDB(
            signal: signal,
            cancellationCheck: cancellationCheck
        )
        let lowBandSideMidRatio = try lowBandSideMidRatioDB(
            signal: signal,
            cancellationCheck: cancellationCheck
        )
        let waveformCorrelation = try leftRightWaveformCorrelation(
            signal: signal,
            cancellationCheck: cancellationCheck
        )
        let rms400MillisecondDB = try rmsEnvelope(
            mono,
            sampleRate: signal.sampleRate,
            outputRate: rms400MillisecondRateHz,
            cancellationCheck: cancellationCheck
        ).map(amplitudeDB)
        let waveform = try displayWaveform(
            mono,
            sampleRate: signal.sampleRate,
            maximumPointCount: maximumDisplayWaveformPoints,
            cancellationCheck: cancellationCheck
        )
        try cancellationCheck()

        return CompletionReportAudioAnalysis(
            estimatedTempoBPM: tempo.value,
            tempoConfidence: tempo.confidence,
            estimatedKey: key.value,
            keyConfidence: key.confidence,
            densityTransitionTimes: densityTransitionTimes,
            lowBandStereoCorrelation: lowBandCorrelation,
            sideMidRatioDB: sideMidRatio,
            lowBandSideMidRatioDB: lowBandSideMidRatio,
            leftRightWaveformCorrelation: waveformCorrelation,
            clippedSampleCount: peakCounts.clipped,
            nearPeakSampleCount: peakCounts.nearPeak,
            rms400MillisecondDB: rms400MillisecondDB,
            rms400MillisecondRateHz: rms400MillisecondRateHz,
            displayWaveform: waveform,
            waveformEnvelope: envelope,
            waveformEnvelopeRateHz: envelopeRateHz
        )
    }

    private static func amplitudeDB(_ amplitude: Float) -> Double {
        20 * log10(max(Double(amplitude), 1e-12))
    }

    private static func peakSampleCounts(
        signal: AudioSignal,
        cancellationCheck: () throws -> Void
    ) rethrows -> (clipped: Int, nearPeak: Int) {
        let nearPeakThreshold = pow(10, -0.9 / 20)
        var clipped = 0
        var nearPeak = 0
        for channel in signal.channels {
            for (index, sample) in channel.enumerated() {
                if index.isMultiple(of: 4_096) { try cancellationCheck() }
                let magnitude = abs(Double(sample))
                if magnitude >= 1 { clipped += 1 }
                if magnitude >= nearPeakThreshold { nearPeak += 1 }
            }
        }
        return (clipped, nearPeak)
    }

    private static func displayWaveform(
        _ samples: [Float],
        sampleRate: Double,
        maximumPointCount: Int,
        cancellationCheck: () throws -> Void
    ) rethrows -> [CompletionReportWaveformPoint] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let blockSize = max(1, Int(ceil(Double(samples.count) / Double(maximumPointCount))))
        var result: [CompletionReportWaveformPoint] = []
        result.reserveCapacity(min(maximumPointCount, samples.count))
        var start = 0
        while start < samples.count {
            try cancellationCheck()
            let end = min(samples.count, start + blockSize)
            var minimum = Float.greatestFiniteMagnitude
            var maximum = -Float.greatestFiniteMagnitude
            for sample in samples[start..<end] {
                minimum = min(minimum, sample)
                maximum = max(maximum, sample)
            }
            result.append(CompletionReportWaveformPoint(
                time: Double(start + (end - start) / 2) / sampleRate,
                minimum: minimum,
                maximum: maximum
            ))
            start = end
        }
        return result
    }

    private static func rmsEnvelope(
        _ samples: [Float],
        sampleRate: Double,
        outputRate: Double,
        cancellationCheck: () throws -> Void
    ) rethrows -> [Float] {
        let blockSize = max(1, Int((sampleRate / outputRate).rounded()))
        var result: [Float] = []
        result.reserveCapacity((samples.count + blockSize - 1) / blockSize)

        var start = 0
        while start < samples.count {
            try cancellationCheck()
            let end = min(samples.count, start + blockSize)
            var energy = 0.0
            for index in start..<end {
                let sample = Double(samples[index])
                energy += sample * sample
            }
            result.append(Float(sqrt(energy / Double(max(end - start, 1)))))
            start = end
        }
        return result
    }

    private static func estimatedTempo(
        from envelope: [Float],
        sampleRate: Double,
        cancellationCheck: () throws -> Void
    ) rethrows -> (value: Double?, confidence: Double) {
        guard envelope.count >= Int(sampleRate * 8) else { return (nil, 0) }

        var onset = Array(repeating: 0.0, count: envelope.count)
        for index in 1..<envelope.count {
            onset[index] = max(0, Double(envelope[index] - envelope[index - 1]))
        }
        let mean = onset.reduce(0, +) / Double(onset.count)
        for index in onset.indices {
            onset[index] = max(0, onset[index] - mean)
        }
        let energy = onset.reduce(0) { $0 + $1 * $1 }
        guard energy > 1e-12 else { return (nil, 0) }

        let minimumLag = max(1, Int((sampleRate * 60 / 200).rounded()))
        let maximumLag = min(onset.count / 2, Int((sampleRate * 60 / 60).rounded()))
        guard minimumLag <= maximumLag else { return (nil, 0) }

        var bestLag = minimumLag
        var bestCorrelation = 0.0
        for lag in minimumLag...maximumLag {
            try cancellationCheck()
            var numerator = 0.0
            var leftEnergy = 0.0
            var rightEnergy = 0.0
            for index in lag..<onset.count {
                let left = onset[index]
                let right = onset[index - lag]
                numerator += left * right
                leftEnergy += left * left
                rightEnergy += right * right
            }
            let correlation = numerator / max(sqrt(leftEnergy * rightEnergy), 1e-12)
            if correlation > bestCorrelation {
                bestCorrelation = correlation
                bestLag = lag
            }
        }

        let confidence = min(max(bestCorrelation, 0), 1)
        guard confidence >= 0.18 else { return (nil, confidence) }
        return (60 * sampleRate / Double(bestLag), confidence)
    }

    private static func estimatedKey(
        from spectrum: [SpectrumMetric]
    ) -> (value: String?, confidence: Double) {
        guard !spectrum.isEmpty else { return (nil, 0) }
        var chroma = Array(repeating: 0.0, count: 12)
        for point in spectrum where point.frequencyHz >= 65 && point.frequencyHz <= 5_000 {
            let midi = 69 + 12 * log2(point.frequencyHz / 440)
            let pitchClass = (Int(midi.rounded()) % 12 + 12) % 12
            chroma[pitchClass] += pow(10, point.levelDB / 20)
        }
        let chromaEnergy = chroma.reduce(0, +)
        guard chromaEnergy > 1e-12 else { return (nil, 0) }

        let major = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
        let minor = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        var candidates: [(name: String, score: Double)] = []
        for root in 0..<12 {
            candidates.append(("\(names[root])メジャー", profileScore(chroma, profile: major, root: root)))
            candidates.append(("\(names[root])マイナー", profileScore(chroma, profile: minor, root: root)))
        }
        candidates.sort { $0.score > $1.score }
        guard let best = candidates.first else { return (nil, 0) }
        let second = candidates.dropFirst().first?.score ?? 0
        let confidence = max(0, min(1, (best.score - second) / max(abs(best.score), 1e-12) * 4))
        guard confidence >= 0.12 else { return (nil, confidence) }
        return (best.name, confidence)
    }

    private static func profileScore(_ chroma: [Double], profile: [Double], root: Int) -> Double {
        let chromaMean = chroma.reduce(0, +) / 12
        let profileMean = profile.reduce(0, +) / 12
        var cross = 0.0
        var chromaEnergy = 0.0
        var profileEnergy = 0.0
        for index in 0..<12 {
            let chromaValue = chroma[(index + root) % 12] - chromaMean
            let profileValue = profile[index] - profileMean
            cross += chromaValue * profileValue
            chromaEnergy += chromaValue * chromaValue
            profileEnergy += profileValue * profileValue
        }
        return cross / max(sqrt(chromaEnergy * profileEnergy), 1e-12)
    }

    private static func densityTransitions(
        in envelope: [Float],
        sampleRate: Double,
        cancellationCheck: () throws -> Void
    ) rethrows -> [TimeInterval] {
        let windowSize = max(1, Int(sampleRate * 2))
        guard envelope.count >= windowSize * 3 else { return [] }
        var windows: [(time: Double, level: Double)] = []
        var start = 0
        while start + windowSize <= envelope.count {
            try cancellationCheck()
            let slice = envelope[start..<(start + windowSize)]
            let mean = slice.reduce(0) { $0 + Double($1) } / Double(windowSize)
            windows.append((Double(start + windowSize / 2) / sampleRate, mean))
            start += windowSize
        }
        let mean = windows.reduce(0) { $0 + $1.level } / Double(windows.count)
        let variance = windows.reduce(0) { $0 + pow($1.level - mean, 2) } / Double(windows.count)
        let threshold = max(sqrt(variance) * 0.9, mean * 0.12)
        var candidates: [(time: Double, change: Double)] = []
        for index in 1..<windows.count {
            let change = abs(windows[index].level - windows[index - 1].level)
            if change >= threshold {
                candidates.append((windows[index].time, change))
            }
        }
        return candidates.sorted { $0.change > $1.change }.prefix(4).map(\.time).sorted()
    }

    private static func lowBandStereoCorrelation(
        signal: AudioSignal,
        cancellationCheck: () throws -> Void
    ) rethrows -> Double? {
        guard signal.channels.count >= 2,
              let left = signal.channels.first,
              left.count > 1
        else { return nil }
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        let alpha = 1 - exp(-2 * Double.pi * 150 / signal.sampleRate)
        var filteredLeft = 0.0
        var filteredRight = 0.0
        var leftEnergy = 0.0
        var rightEnergy = 0.0
        var cross = 0.0
        for index in 0..<count {
            if index.isMultiple(of: 4_096) { try cancellationCheck() }
            filteredLeft += alpha * (Double(left[index]) - filteredLeft)
            filteredRight += alpha * (Double(right[index]) - filteredRight)
            leftEnergy += filteredLeft * filteredLeft
            rightEnergy += filteredRight * filteredRight
            cross += filteredLeft * filteredRight
        }
        guard leftEnergy > 1e-12, rightEnergy > 1e-12 else { return nil }
        return max(-1, min(1, cross / sqrt(leftEnergy * rightEnergy)))
    }

    private static func sideMidRatioDB(
        signal: AudioSignal,
        cancellationCheck: () throws -> Void
    ) rethrows -> Double? {
        guard signal.channels.count >= 2,
              let left = signal.channels.first
        else { return nil }
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return nil }
        var midEnergy = 0.0
        var sideEnergy = 0.0
        for index in 0..<count {
            if index.isMultiple(of: 4_096) { try cancellationCheck() }
            let mid = (Double(left[index]) + Double(right[index])) * 0.5
            let side = (Double(left[index]) - Double(right[index])) * 0.5
            midEnergy += mid * mid
            sideEnergy += side * side
        }
        guard midEnergy > 1e-12 else { return nil }
        return 10 * log10(max(sideEnergy, 1e-12) / midEnergy)
    }

    private static func lowBandSideMidRatioDB(
        signal: AudioSignal,
        cancellationCheck: () throws -> Void
    ) rethrows -> Double? {
        guard signal.sampleRate > 0,
              signal.channels.count >= 2,
              let left = signal.channels.first else { return nil }
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return nil }
        let alpha = 1 - exp(-2 * Double.pi * 150 / signal.sampleRate)
        var filteredLeft = 0.0
        var filteredRight = 0.0
        var midEnergy = 0.0
        var sideEnergy = 0.0
        for index in 0..<count {
            if index.isMultiple(of: 4_096) { try cancellationCheck() }
            filteredLeft += alpha * (Double(left[index]) - filteredLeft)
            filteredRight += alpha * (Double(right[index]) - filteredRight)
            let mid = (filteredLeft + filteredRight) * 0.5
            let side = (filteredLeft - filteredRight) * 0.5
            midEnergy += mid * mid
            sideEnergy += side * side
        }
        guard midEnergy > 1e-12 else { return nil }
        return 10 * log10(max(sideEnergy, 1e-12) / midEnergy)
    }

    private static func leftRightWaveformCorrelation(
        signal: AudioSignal,
        cancellationCheck: () throws -> Void
    ) rethrows -> Double? {
        guard signal.channels.count >= 2,
              let left = signal.channels.first else { return nil }
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 1 else { return nil }
        var leftEnergy = 0.0
        var rightEnergy = 0.0
        var cross = 0.0
        for index in 0..<count {
            if index.isMultiple(of: 4_096) { try cancellationCheck() }
            let leftSample = Double(left[index])
            let rightSample = Double(right[index])
            leftEnergy += leftSample * leftSample
            rightEnergy += rightSample * rightSample
            cross += leftSample * rightSample
        }
        guard leftEnergy > 1e-12, rightEnergy > 1e-12 else { return nil }
        return max(-1, min(1, cross / sqrt(leftEnergy * rightEnergy)))
    }
}
