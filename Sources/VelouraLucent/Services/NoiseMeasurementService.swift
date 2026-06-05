import Foundation

enum NoiseMeasurementService {
    static func analyze(signal: AudioSignal) -> NoiseMeasurementSnapshot {
        try! analyze(signal: signal, definitions: definitions, cancellationCheck: {})
    }

    static func analyze(signal: AudioSignal, ids requestedIDs: [String]) -> NoiseMeasurementSnapshot {
        let requestedIDSet = Set(requestedIDs)
        let selectedDefinitions = definitions.filter { requestedIDSet.contains($0.id) }
        return try! analyze(signal: signal, definitions: selectedDefinitions, cancellationCheck: {})
    }

    static func analyzeCancellable(signal: AudioSignal) throws -> NoiseMeasurementSnapshot {
        try analyze(signal: signal, definitions: definitions) {
            try Task.checkCancellation()
        }
    }

    private static func analyze(
        signal: AudioSignal,
        definitions selectedDefinitions: [NoiseMeasurementDefinition],
        cancellationCheck: @escaping () throws -> Void
    ) throws -> NoiseMeasurementSnapshot {
        try cancellationCheck()
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return NoiseMeasurementSnapshot(values: selectedDefinitions.map {
                NoiseMeasurementValue(
                    id: $0.id,
                    label: $0.label,
                    comparableLevelDB: -120,
                    measuredLevelDB: -120,
                    unitLabel: $0.unitLabel,
                    measurementDescription: $0.measurementDescription,
                    lowerIsBetter: $0.lowerIsBetter
                )
            })
        }

        let requestedIDs = Set(selectedDefinitions.map(\.id))
        let measuredLevels = try measure(
            mono: mono,
            sampleRate: signal.sampleRate,
            ids: requestedIDs,
            cancellationCheck: cancellationCheck
        )

        let values = selectedDefinitions.map { definition in
            let measured = measuredLevels[definition.id] ?? -120
            return NoiseMeasurementValue(
                id: definition.id,
                label: definition.label,
                comparableLevelDB: measured,
                measuredLevelDB: measured,
                unitLabel: definition.unitLabel,
                measurementDescription: definition.measurementDescription,
                lowerIsBetter: definition.lowerIsBetter
            )
        }
        return NoiseMeasurementSnapshot(values: values)
    }

    private static var definitions: [NoiseMeasurementDefinition] {
        [
            NoiseMeasurementDefinition(id: NoiseMeasurementID.hiss, label: "ヒス・シュワシュワ", unitLabel: "dBFS", measurementDescription: "静かな区間の8kHz以上の床"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.sibilance, label: "サ行・歯擦音", unitLabel: "dB", measurementDescription: "5〜9kHzの短時間突出"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.shimmer, label: "高域のチラつき", unitLabel: "dBFS", measurementDescription: "静かな区間の10〜16kHz床"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.mud, label: "こもり・低いザラつき", unitLabel: "dB", measurementDescription: "300Hz〜1kHzの全体比"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.hum, label: "ハム・電源ノイズ", unitLabel: "dB", measurementDescription: "50/60Hzと倍音の周辺比"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.rumble, label: "低域ゴロゴロ", unitLabel: "dBFS", measurementDescription: "静かな区間の20〜150Hz床"),
            NoiseMeasurementDefinition(id: NoiseMeasurementID.room, label: "環境音・部屋鳴り", unitLabel: "dBFS", measurementDescription: "静かな区間の100Hz〜8kHz床")
        ]
    }

    private static func measure(
        mono: [Float],
        sampleRate: Double,
        ids requestedIDs: Set<String>,
        cancellationCheck: @escaping () throws -> Void
    ) throws -> [String: Double] {
        var measured: [String: Double] = [:]
        var quietFloorContext = QuietFloorContext(reference: mono, sampleRate: sampleRate, cancellationCheck: cancellationCheck)

        if requestedIDs.contains(NoiseMeasurementID.hiss) {
            try cancellationCheck()
            let high = try bandPass(mono, lower: 8_000, upper: min(20_000, sampleRate * 0.5 - 100), sampleRate: sampleRate, cancellationCheck: cancellationCheck)
            measured[NoiseMeasurementID.hiss] = try quietFloorContext.quietBandNoiseFloorDB(band: high)
        }

        if requestedIDs.contains(NoiseMeasurementID.sibilance) {
            try cancellationCheck()
            let sibilance = try bandPass(mono, lower: 5_000, upper: min(9_000, sampleRate * 0.5 - 100), sampleRate: sampleRate, cancellationCheck: cancellationCheck)
            measured[NoiseMeasurementID.sibilance] = try transientExcessDB(band: sibilance, sampleRate: sampleRate, cancellationCheck: cancellationCheck)
        }

        if requestedIDs.contains(NoiseMeasurementID.shimmer) {
            try cancellationCheck()
            let shimmer = try bandPass(mono, lower: 10_000, upper: min(16_000, sampleRate * 0.5 - 100), sampleRate: sampleRate, cancellationCheck: cancellationCheck)
            measured[NoiseMeasurementID.shimmer] = try quietFloorContext.quietBandNoiseFloorDB(band: shimmer)
        }

        if requestedIDs.contains(NoiseMeasurementID.mud) {
            try cancellationCheck()
            let fullRMS = rmsDB(mono)
            let lowMid = try bandPass(mono, lower: 300, upper: 1_000, sampleRate: sampleRate, cancellationCheck: cancellationCheck)
            measured[NoiseMeasurementID.mud] = sustainedBandRatioDB(band: lowMid, fullRMSDB: fullRMS)
        }

        if requestedIDs.contains(NoiseMeasurementID.hum) {
            try cancellationCheck()
            measured[NoiseMeasurementID.hum] = try humProminenceDB(mono: mono, sampleRate: sampleRate, cancellationCheck: cancellationCheck)
        }

        if requestedIDs.contains(NoiseMeasurementID.rumble) {
            try cancellationCheck()
            let low = try bandPass(mono, lower: 20, upper: 150, sampleRate: sampleRate, cancellationCheck: cancellationCheck)
            measured[NoiseMeasurementID.rumble] = try quietFloorContext.quietBandNoiseFloorDB(band: low)
        }

        if requestedIDs.contains(NoiseMeasurementID.room) {
            try cancellationCheck()
            let room = try bandPass(mono, lower: 100, upper: min(8_000, sampleRate * 0.5 - 100), sampleRate: sampleRate, cancellationCheck: cancellationCheck)
            measured[NoiseMeasurementID.room] = try quietFloorContext.quietBandNoiseFloorDB(band: room)
        }

        return measured
    }

    private struct QuietFloorContext {
        let reference: [Float]
        let sampleRate: Double
        let cancellationCheck: () throws -> Void
        private var referenceFrames: [Double]?

        init(reference: [Float], sampleRate: Double, cancellationCheck: @escaping () throws -> Void) {
            self.reference = reference
            self.sampleRate = sampleRate
            self.cancellationCheck = cancellationCheck
            referenceFrames = nil
        }

        mutating func quietBandNoiseFloorDB(band: [Float]) throws -> Double {
            let frameSize = max(512, Int(sampleRate * 0.100))
            let hopSize = max(256, Int(sampleRate * 0.050))
            let referenceFrames = try cachedReferenceFrames(frameSize: frameSize, hopSize: hopSize)
            return try NoiseMeasurementService.quietBandNoiseFloorDB(
                band: band,
                referenceFrames: referenceFrames,
                frameSize: frameSize,
                hopSize: hopSize,
                cancellationCheck: cancellationCheck
            )
        }

        private mutating func cachedReferenceFrames(frameSize: Int, hopSize: Int) throws -> [Double] {
            if let referenceFrames {
                return referenceFrames
            }
            let frames = try NoiseMeasurementService.frameRMS(
                reference,
                frameSize: frameSize,
                hopSize: hopSize,
                cancellationCheck: cancellationCheck
            )
            referenceFrames = frames
            return frames
        }
    }

    private static func bandPass(
        _ samples: [Float],
        lower: Double,
        upper: Double,
        sampleRate: Double,
        cancellationCheck: @escaping () throws -> Void
    ) throws -> [Float] {
        guard lower < upper, upper < sampleRate * 0.5 else { return Array(repeating: 0, count: samples.count) }
        var input = samples
        var output = Array(repeating: Float.zero, count: samples.count)
        let highPassAlpha = highPassAlpha(cutoff: lower, sampleRate: sampleRate)
        let lowPassAlpha = lowPassAlpha(cutoff: upper, sampleRate: sampleRate)
        for _ in 0..<4 {
            try cancellationCheck()
            highPass(input, into: &output, alpha: highPassAlpha)
            swap(&input, &output)
            try cancellationCheck()
            lowPass(input, into: &output, alpha: lowPassAlpha)
            swap(&input, &output)
        }
        return input
    }

    private static func lowPassAlpha(cutoff: Double, sampleRate: Double) -> Float {
        let rc = 1.0 / (2.0 * Double.pi * cutoff)
        let dt = 1.0 / sampleRate
        return Float(dt / (rc + dt))
    }

    private static func highPassAlpha(cutoff: Double, sampleRate: Double) -> Float {
        let rc = 1.0 / (2.0 * Double.pi * cutoff)
        let dt = 1.0 / sampleRate
        return Float(rc / (rc + dt))
    }

    private static func lowPass(_ input: [Float], into output: inout [Float], alpha: Float) {
        guard input.count > 1 else {
            output = input
            return
        }
        output[0] = input[0]
        for index in 1..<input.count {
            output[index] = output[index - 1] + alpha * (input[index] - output[index - 1])
        }
    }

    private static func highPass(_ input: [Float], into output: inout [Float], alpha: Float) {
        guard input.count > 1 else {
            output = input
            return
        }
        output[0] = input[0]
        for index in 1..<input.count {
            output[index] = alpha * (output[index - 1] + input[index] - input[index - 1])
        }
    }

    private static func quietBandNoiseFloorDB(
        band: [Float],
        referenceFrames: [Double],
        frameSize: Int,
        hopSize: Int,
        cancellationCheck: @escaping () throws -> Void
    ) throws -> Double {
        let bandFrames = try frameRMS(band, frameSize: frameSize, hopSize: hopSize, cancellationCheck: cancellationCheck)
        guard !referenceFrames.isEmpty, referenceFrames.count == bandFrames.count else {
            return rmsDB(band)
        }

        let threshold = percentile(referenceFrames, 0.20)
        let quietValues = zip(referenceFrames, bandFrames).compactMap { reference, band -> Double? in
            reference <= threshold ? band : nil
        }
        return percentile(quietValues.isEmpty ? bandFrames : quietValues, 0.20)
    }

    private static func transientExcessDB(band: [Float], sampleRate: Double, cancellationCheck: @escaping () throws -> Void) throws -> Double {
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        let frames = try frameRMS(band, frameSize: frameSize, hopSize: hopSize, cancellationCheck: cancellationCheck).sorted()
        guard frames.count >= 4 else { return 0 }
        return percentile(frames, 0.95) - percentile(frames, 0.50)
    }

    private static func sustainedBandRatioDB(band: [Float], fullRMSDB: Double) -> Double {
        rmsDB(band) - fullRMSDB
    }

    private static func humProminenceDB(mono: [Float], sampleRate: Double, cancellationCheck: @escaping () throws -> Void) throws -> Double {
        let baseFrequencies = [50.0, 60.0]
        var harmonicFrequencies: [Double] = []

        for base in baseFrequencies {
            try cancellationCheck()
            var harmonic = base
            while harmonic <= min(360, sampleRate * 0.5 - 30) {
                try cancellationCheck()
                harmonicFrequencies.append(harmonic)
                harmonic += base
            }
        }

        let uniqueHarmonicFrequencies = Array(Set(harmonicFrequencies)).sorted()
        let spectralProminences = try harmonicProminencesDB(
            mono: mono,
            frequencies: uniqueHarmonicFrequencies,
            sampleRate: sampleRate,
            cancellationCheck: cancellationCheck
        )
        let sineProminences = try windowedSineProminencesDB(
            mono: mono,
            frequencies: harmonicFrequencies,
            sampleRate: sampleRate,
            cancellationCheck: cancellationCheck
        )
        var strongest = 0.0
        for harmonic in harmonicFrequencies {
            try cancellationCheck()
            let spectral = spectralProminences[harmonic] ?? 0
            let sine = sineProminences[harmonic] ?? 0
            strongest = max(strongest, spectral, sine)
        }

        return strongest
    }

    private static func windowedSineProminencesDB(
        mono: [Float],
        frequencies: [Double],
        sampleRate: Double,
        cancellationCheck: @escaping () throws -> Void
    ) throws -> [Double: Double] {
        let uniqueFrequencies = Array(Set(frequencies)).sorted()
        let frequencyPlan = HumSineFrequencyPlan(frequencies: uniqueFrequencies, sampleRate: sampleRate)
        let frameSize = max(2048, Int(sampleRate * 0.50))
        let hopSize = max(1024, frameSize / 2)
        guard mono.count >= frameSize else {
            return Dictionary(uniqueKeysWithValues: uniqueFrequencies.map { ($0, 0) })
        }

        var valuesByFrequency: [Double: [Double]] = Dictionary(uniqueKeysWithValues: uniqueFrequencies.map { ($0, []) })
        var start = 0
        while start + frameSize <= mono.count {
            try cancellationCheck()
            let frame = Array(mono[start..<(start + frameSize)])
            var magnitudes: [Double: Double] = [:]
            for frequency in frequencyPlan.uniqueMeasurementFrequencies {
                magnitudes[frequency] = sineMagnitudeDB(frame, frequency: frequency, sampleRate: sampleRate)
            }

            for frequency in uniqueFrequencies {
                guard let measurementFrequencies = frequencyPlan.measurementFrequenciesByHarmonic[frequency],
                      let center = magnitudes[measurementFrequencies.center]
                else { continue }
                let surrounding = measurementFrequencies.surrounding.compactMap { magnitudes[$0] }
                valuesByFrequency[frequency, default: []].append(center - median(surrounding))
            }

            start += hopSize
        }

        return Dictionary(uniqueKeysWithValues: valuesByFrequency.map { frequency, values in
            (frequency, max(0, percentile(values, 0.50)))
        })
    }

    private static func sineMagnitudeDB(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double {
        guard !samples.isEmpty else { return -120 }
        var real = 0.0
        var imag = 0.0
        let angular = 2 * Double.pi * frequency / sampleRate
        let cosStep = cos(angular)
        let sinStep = sin(angular)
        var cosine = 1.0
        var sine = 0.0
        for sampleValue in samples {
            let sample = Double(sampleValue)
            real += sample * cosine
            imag -= sample * sine
            let nextCosine = cosine * cosStep - sine * sinStep
            sine = sine * cosStep + cosine * sinStep
            cosine = nextCosine
        }
        let magnitude = sqrt(real * real + imag * imag) * 2 / Double(samples.count)
        return 20 * log10(max(magnitude, 1e-12))
    }

    private static func harmonicProminencesDB(
        mono: [Float],
        frequencies: [Double],
        sampleRate: Double,
        cancellationCheck: @escaping () throws -> Void
    ) throws -> [Double: Double] {
        let fftSize = 8192
        let hopSize = 4096
        let frequencyStep = sampleRate / Double(fftSize)
        var frameProminences = Dictionary(uniqueKeysWithValues: frequencies.map { ($0, [Double]()) })

        try SpectralDSP.forEachSTFTFrameThrowing(mono, fftSize: fftSize, hopSize: hopSize) { frameIndex, binCount, real, imag in
            if frameIndex.isMultiple(of: 32) {
                try cancellationCheck()
            }

            for frequency in frequencies {
                let centerBin = max(1, min(binCount - 2, Int(round(frequency / frequencyStep))))
                let centerRadius = max(1, Int(round(1.5 / frequencyStep)))
                let excludeRadius = max(centerRadius + 1, Int(round(3.0 / frequencyStep)))
                let searchRadius = max(excludeRadius + 1, Int(round(18.0 / frequencyStep)))
                var centerMagnitudes: [Double] = []
                var surroundingMagnitudes: [Double] = []
                let lower = max(1, centerBin - searchRadius)
                let upper = min(binCount - 1, centerBin + searchRadius)

                for bin in lower...upper {
                    let realValue = Double(real[bin])
                    let imagValue = Double(imag[bin])
                    let magnitude = sqrt(realValue * realValue + imagValue * imagValue)
                    let distance = abs(bin - centerBin)
                    if distance <= centerRadius {
                        centerMagnitudes.append(magnitude)
                    } else if distance > excludeRadius {
                        surroundingMagnitudes.append(magnitude)
                    }
                }

                guard !centerMagnitudes.isEmpty, surroundingMagnitudes.count >= 3 else { continue }
                let center = centerMagnitudes.reduce(0, +) / Double(centerMagnitudes.count)
                let surrounding = median(surroundingMagnitudes)
                frameProminences[frequency, default: []].append(20 * log10(max(center, 1e-12) / max(surrounding, 1e-12)))
            }
        }

        try cancellationCheck()
        return Dictionary(uniqueKeysWithValues: frameProminences.map { frequency, values in
            (frequency, values.isEmpty ? 0 : max(0, percentile(values, 0.75)))
        })
    }

    private static func frameRMS(
        _ samples: [Float],
        frameSize: Int,
        hopSize: Int,
        cancellationCheck: @escaping () throws -> Void
    ) throws -> [Double] {
        guard !samples.isEmpty else { return [] }
        if samples.count <= frameSize {
            return [rmsDB(samples)]
        }

        var values: [Double] = []
        var start = 0
        var frameIndex = 0
        while start + frameSize <= samples.count {
            if frameIndex.isMultiple(of: 64) {
                try cancellationCheck()
            }
            let frame = samples[start..<(start + frameSize)]
            let energy = frame.reduce(0.0) { partial, sample in
                partial + Double(sample * sample)
            } / Double(frameSize)
            values.append(10 * log10(max(energy, 1e-12)))
            start += hopSize
            frameIndex += 1
        }
        return values
    }

    private static func rmsDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        let energy = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        return 10 * log10(max(energy, 1e-12))
    }

    private static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(round(Double(sorted.count - 1) * percentile))))
        return sorted[index]
    }

    private static func median(_ values: [Double]) -> Double {
        percentile(values, 0.50)
    }
}

private struct NoiseMeasurementDefinition {
    let id: String
    let label: String
    let unitLabel: String
    let measurementDescription: String
    let lowerIsBetter: Bool

    init(
        id: String,
        label: String,
        unitLabel: String,
        measurementDescription: String,
        lowerIsBetter: Bool = true
    ) {
        self.id = id
        self.label = label
        self.unitLabel = unitLabel
        self.measurementDescription = measurementDescription
        self.lowerIsBetter = lowerIsBetter
    }
}

struct HumSineFrequencyPlan {
    let measurementFrequenciesByHarmonic: [Double: (center: Double, surrounding: [Double])]
    let uniqueMeasurementFrequencies: [Double]

    init(frequencies: [Double], sampleRate: Double) {
        var plannedFrequencies: [Double: (center: Double, surrounding: [Double])] = [:]
        var allMeasurementFrequencies: [Double] = []

        for frequency in frequencies {
            let center = frequency
            let surrounding = [
                max(20, frequency - 23),
                max(20, frequency - 17),
                min(sampleRate * 0.5 - 20, frequency + 17),
                min(sampleRate * 0.5 - 20, frequency + 23)
            ]
            plannedFrequencies[frequency] = (center: center, surrounding: surrounding)
            allMeasurementFrequencies.append(center)
            allMeasurementFrequencies.append(contentsOf: surrounding)
        }

        measurementFrequenciesByHarmonic = plannedFrequencies
        uniqueMeasurementFrequencies = Array(Set(allMeasurementFrequencies)).sorted()
    }
}
