import Foundation

struct AudioBandDescriptor: Sendable, Identifiable {
    let id: String
    let label: String
    let rangeDescription: String
    let lowerBound: Double
    let upperBound: Double
}

enum AudioBandCatalog {
    static let previewBands: [AudioBandDescriptor] = [
        AudioBandDescriptor(id: "sub", label: "超低", rangeDescription: "0-160Hz", lowerBound: 0, upperBound: 160),
        AudioBandDescriptor(id: "low", label: "低域", rangeDescription: "160-400Hz", lowerBound: 160, upperBound: 400),
        AudioBandDescriptor(id: "lowMid", label: "中低", rangeDescription: "400-1.2kHz", lowerBound: 400, upperBound: 1_200),
        AudioBandDescriptor(id: "mid", label: "中域", rangeDescription: "1.2-3kHz", lowerBound: 1_200, upperBound: 3_000),
        AudioBandDescriptor(id: "upperMid", label: "中高", rangeDescription: "3-6kHz", lowerBound: 3_000, upperBound: 6_000),
        AudioBandDescriptor(id: "presence", label: "明瞭", rangeDescription: "6-10kHz", lowerBound: 6_000, upperBound: 10_000),
        AudioBandDescriptor(id: "high", label: "高域", rangeDescription: "10-16kHz", lowerBound: 10_000, upperBound: 16_000),
        AudioBandDescriptor(id: "air", label: "超高", rangeDescription: "16-24kHz", lowerBound: 16_000, upperBound: 24_000)
    ]

    static let comparisonBands: [AudioBandDescriptor] = [
        AudioBandDescriptor(id: "rumble", label: "低域ノイズ", rangeDescription: "20-150Hz", lowerBound: 20, upperBound: 150),
        AudioBandDescriptor(id: "warmth", label: "太さ", rangeDescription: "150-300Hz", lowerBound: 150, upperBound: 300),
        AudioBandDescriptor(id: "mud", label: "こもり", rangeDescription: "300Hz-1kHz", lowerBound: 300, upperBound: 1_000),
        AudioBandDescriptor(id: "core", label: "声の芯", rangeDescription: "1-4kHz", lowerBound: 1_000, upperBound: 4_000),
        AudioBandDescriptor(id: "presence", label: "刺さり", rangeDescription: "4-8kHz", lowerBound: 4_000, upperBound: 8_000),
        AudioBandDescriptor(id: "sparkle", label: "煌びやかさ", rangeDescription: "8-12kHz", lowerBound: 8_000, upperBound: 12_000),
        AudioBandDescriptor(id: "air", label: "空気感", rangeDescription: "12-16kHz", lowerBound: 12_000, upperBound: 16_000),
        AudioBandDescriptor(id: "ultraAir", label: "超高域", rangeDescription: "16-20kHz", lowerBound: 16_000, upperBound: 20_000)
    ]

    static let masteringBands: [AudioBandDescriptor] = [
        AudioBandDescriptor(id: "low", label: "低域", rangeDescription: "20-180Hz", lowerBound: 20, upperBound: 180),
        AudioBandDescriptor(id: "lowMid", label: "中低域", rangeDescription: "180-500Hz", lowerBound: 180, upperBound: 500),
        AudioBandDescriptor(id: "presence", label: "プレゼンス帯域", rangeDescription: "2.5-5.5kHz", lowerBound: 2_500, upperBound: 5_500),
        AudioBandDescriptor(id: "air", label: "エアー帯域", rangeDescription: "10-20kHz", lowerBound: 10_000, upperBound: 20_000)
    ]
}

struct AudioSignal: Sendable {
    var channels: [[Float]]
    var sampleRate: Double

    var frameCount: Int {
        channels.first?.count ?? 0
    }

    func monoMixdown() -> [Float] {
        guard let first = channels.first else { return [] }
        guard channels.count > 1 else { return first }

        let scale = 1.0 / Float(channels.count)
        var mono = Array(repeating: Float.zero, count: first.count)
        for channel in channels {
            for index in channel.indices {
                mono[index] += channel[index] * scale
            }
        }
        return mono
    }
}

struct HarmonicPeak: Sendable {
    let frequency: Double
    let magnitude: Float
}

struct DenoiseEffectMetrics: Sendable, Equatable {
    let shimmerFlicker: Float
    let hf12Magnitude: Float
    let hf16Magnitude: Float
    let hf18Magnitude: Float

    init(shimmerFlicker: Float, hf12Magnitude: Float, hf16Magnitude: Float, hf18Magnitude: Float) {
        self.shimmerFlicker = shimmerFlicker
        self.hf12Magnitude = hf12Magnitude
        self.hf16Magnitude = hf16Magnitude
        self.hf18Magnitude = hf18Magnitude
    }
}

struct AnalysisData: Sendable {
    let cutoffFrequency: Double
    let dominantHarmonics: [HarmonicPeak]
    let harmonicConfidence: Float
    let hasShimmer: Bool
    let shimmerRatio: Float
    let brightnessRatio: Float
    let transientAmount: Float
    let noiseAmount: Float
    let rolloffDepth: Float
    let airBandEnergyRatio: Float
    let artifactBandRatio: Float
    let denoiseEffectMetrics: DenoiseEffectMetrics?
}

struct NeuralFoldoverFeatures: Sendable {
    let harmonicConfidence: Float
    let shimmerRatio: Float
    let brightnessRatio: Float
    let transientAmount: Float
    let cutoffFrequency: Double
    let noiseAmount: Float
    let rolloffDepth: Float
    let airBandEnergyRatio: Float
    let artifactBandRatio: Float
}

struct NeuralFoldoverPrediction: Sendable, Equatable {
    let foldoverMix: Float
    let airGainBias: Float
    let transientBoostBias: Float
    let harshnessGuard: Float
}

enum DenoiseStrength: String, CaseIterable, Identifiable, Sendable {
    case gentle
    case balanced
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gentle:
            return "弱い"
        case .balanced:
            return "標準"
        case .strong:
            return "強い"
        }
    }

    var summary: String {
        switch self {
        case .gentle:
            return "音の芯を優先して、軽くノイズを減らします"
        case .balanced:
            return "音の自然さとノイズ低減のバランスを取ります"
        case .strong:
            return "ノイズをしっかり減らしますが、効き方も強めです"
        }
    }

    var settings: CorrectionSettings {
        switch self {
        case .gentle:
            return CorrectionSettings(
                profile: self,
                correctionIntensity: 0.32,
                originalRetention: 0.78,
                lowCleanup: 0.34,
                lowMidCleanup: 0.36,
                presenceRepair: 0.34,
                airRepair: 0.36,
                highNaturalness: 0.62,
                noiseDetectionSensitivity: 0.36,
                harmonicRepairAmount: 0.36,
                foldoverRepairAmount: 0.30,
                coreProtection: 0.70,
                stereoProtection: 0.86
            )
        case .balanced:
            return CorrectionSettings(
                profile: self,
                correctionIntensity: 0.50,
                originalRetention: 0.66,
                lowCleanup: 0.50,
                lowMidCleanup: 0.50,
                presenceRepair: 0.50,
                airRepair: 0.50,
                highNaturalness: 0.58,
                noiseDetectionSensitivity: 0.50,
                harmonicRepairAmount: 0.50,
                foldoverRepairAmount: 0.50,
                coreProtection: 0.62,
                stereoProtection: 0.80
            )
        case .strong:
            return CorrectionSettings(
                profile: self,
                correctionIntensity: 0.72,
                originalRetention: 0.54,
                lowCleanup: 0.68,
                lowMidCleanup: 0.64,
                presenceRepair: 0.58,
                airRepair: 0.58,
                highNaturalness: 0.70,
                noiseDetectionSensitivity: 0.70,
                harmonicRepairAmount: 0.62,
                foldoverRepairAmount: 0.58,
                coreProtection: 0.72,
                stereoProtection: 0.76
            )
        }
    }
}

struct CorrectionSettings: Sendable, Equatable {
    var profile: DenoiseStrength
    var correctionIntensity: Float
    var originalRetention: Float
    var lowCleanup: Float
    var lowMidCleanup: Float
    var presenceRepair: Float
    var airRepair: Float
    var highNaturalness: Float
    var noiseDetectionSensitivity: Float
    var harmonicRepairAmount: Float
    var foldoverRepairAmount: Float
    var coreProtection: Float
    var stereoProtection: Float
}

struct AudioMetricSnapshot: Sendable {
    let peakDBFS: Double
    let rmsDBFS: Double
    let crestFactorDB: Double
    let loudnessRangeLU: Double?
    let integratedLoudnessLUFS: Double
    let truePeakDBFS: Double
    let stereoWidth: Double
    let stereoCorrelation: Double
    let harshnessScore: Double
    let centroidHz: Double
    let hf12Ratio: Double
    let hf16Ratio: Double
    let hf18Ratio: Double
    let bandEnergies: [BandEnergyMetric]
    let masteringBandEnergies: [BandEnergyMetric]
    let shortTermLoudness: [TimedLevelMetric]
    let dynamics: [DynamicsMetric]
    let averageSpectrum: [SpectrumMetric]
}

struct DenoiseEffectReport: Sendable, Equatable {
    let shimmerFlickerChangeDB: Double
    let hf12ChangeDB: Double
    let hf16ChangeDB: Double
    let hf18ChangeDB: Double

    static let empty = DenoiseEffectReport(
        shimmerFlickerChangeDB: 0,
        hf12ChangeDB: 0,
        hf16ChangeDB: 0,
        hf18ChangeDB: 0
    )
}

struct NoiseMeasurementSnapshot: Sendable, Equatable {
    let values: [NoiseMeasurementValue]

    func value(for id: String) -> NoiseMeasurementValue? {
        values.first { $0.id == id }
    }

    func comparableLevel(for id: String) -> Double? {
        value(for: id)?.comparableLevelDB
    }
}

struct NoiseMeasurementValue: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let comparableLevelDB: Double
    let measuredLevelDB: Double
    let unitLabel: String
    let measurementDescription: String
    let lowerIsBetter: Bool

    init(
        id: String,
        label: String,
        comparableLevelDB: Double,
        measuredLevelDB: Double,
        unitLabel: String = "dB",
        measurementDescription: String = "",
        lowerIsBetter: Bool = true
    ) {
        self.id = id
        self.label = label
        self.comparableLevelDB = comparableLevelDB
        self.measuredLevelDB = measuredLevelDB
        self.unitLabel = unitLabel
        self.measurementDescription = measurementDescription
        self.lowerIsBetter = lowerIsBetter
    }
}

enum NoiseCheckSeverity: Sendable, Equatable {
    case low
    case caution
    case warning
}

struct NoiseCheckReport: Sendable, Equatable {
    let rows: [NoiseCheckRow]
    let recommendedActions: [NoiseCheckAction]

    var severity: NoiseCheckSeverity {
        if rows.contains(where: { $0.severity == .warning }) {
            return .warning
        }
        if rows.contains(where: { $0.severity == .caution }) {
            return .caution
        }
        return .low
    }
}

struct NoiseCheckRow: Sendable, Equatable, Identifiable {
    let id: String
    let label: String
    let measurementDescription: String
    let displayDescription: String
    let unitLabel: String
    let displayScale: NoiseCheckDisplayScale
    let input: NoiseCheckValue?
    let corrected: NoiseCheckValue?
    let mastered: NoiseCheckValue?
    let correctionDeltaDB: Double?
    let masteringDeltaDB: Double?
    let severity: NoiseCheckSeverity
    let summaryText: String
    let correctionEffectText: String
    let masteringEffectText: String
    let recommendedActions: [NoiseCheckAction]
}

struct NoiseCheckAction: Sendable, Equatable, Identifiable {
    enum Stage: String, Sendable, Equatable {
        case correction
        case mastering
    }

    let id: String
    let stage: Stage
    let title: String
    let currentValue: String
    let recommendedValue: String
    let changeValue: String
    let reason: String
    let expectedEffect: String
    let caution: String
}

struct NoiseCheckValue: Sendable, Equatable {
    let levelDB: Double
    let measuredLevelDB: Double
    let unitLabel: String
    let lowerIsBetter: Bool
    let severity: NoiseCheckSeverity
}

struct NoiseCheckDisplayScale: Sendable, Equatable {
    let minimum: Double
    let maximum: Double
    let missingRatio: Double

    init(minimum: Double, maximum: Double, missingRatio: Double = 0.62) {
        self.minimum = minimum
        self.maximum = maximum
        self.missingRatio = missingRatio
    }

    func ratio(for value: Double?) -> Double {
        guard let value else { return missingRatio }
        let span = max(maximum - minimum, 1.0)
        let normalized = max(0, min(1.0, (value - minimum) / span))
        let softened = sqrt(normalized)
        return max(0.28, min(0.92, 0.28 + softened * 0.64))
    }
}

struct BandEnergyMetric: Sendable, Identifiable {
    let id: String
    let label: String
    let rangeDescription: String
    let levelDB: Double
}

struct TimedLevelMetric: Sendable, Identifiable {
    let id: String
    let time: Double
    let levelDB: Double
}

struct DynamicsMetric: Sendable, Identifiable {
    let id: String
    let time: Double
    let peakDBFS: Double
    let rmsDBFS: Double
    let crestFactorDB: Double
}

struct SpectrumMetric: Sendable, Identifiable {
    let id: String
    let frequencyHz: Double
    let levelDB: Double
}

struct AudioPreviewSnapshot: Sendable {
    let waveform: [Float]
    let duration: TimeInterval
    let bandLevels: [String: [Float]]
    let bandLevelDBs: [String: [Float]]
}

struct LiveBandSample: Sendable, Identifiable {
    let id: String
    let label: String
    let level: Double
}

struct SpectrogramCell: Sendable, Identifiable {
    let id: String
    let timeIndex: Int
    let bandIndex: Int
    let timeStart: Double
    let timeEnd: Double
    let frequencyStart: Double
    let frequencyEnd: Double
    let levelDB: Double
}

struct SpectrogramSnapshot: Sendable {
    let cells: [SpectrogramCell]
    let timeBucketCount: Int
    let frequencyBucketCount: Int
    let duration: TimeInterval
    let minLevelDB: Double
    let maxLevelDB: Double

    static let empty = SpectrogramSnapshot(cells: [], timeBucketCount: 0, frequencyBucketCount: 0, duration: 0, minLevelDB: -120, maxLevelDB: -120)
}
