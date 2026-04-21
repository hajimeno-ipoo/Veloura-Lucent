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
        AudioBandDescriptor(id: "low", label: "低域", rangeDescription: "0-5kHz", lowerBound: 0, upperBound: 5_000),
        AudioBandDescriptor(id: "presence", label: "中高域", rangeDescription: "5-10kHz", lowerBound: 5_000, upperBound: 10_000),
        AudioBandDescriptor(id: "high", label: "高域", rangeDescription: "10-16kHz", lowerBound: 10_000, upperBound: 16_000),
        AudioBandDescriptor(id: "air", label: "超高域", rangeDescription: "16-24kHz", lowerBound: 16_000, upperBound: 24_000)
    ]

    static let masteringBands: [AudioBandDescriptor] = [
        AudioBandDescriptor(id: "low", label: "低域", rangeDescription: "20-180Hz", lowerBound: 20, upperBound: 180),
        AudioBandDescriptor(id: "lowMid", label: "中低域", rangeDescription: "180-500Hz", lowerBound: 180, upperBound: 500),
        AudioBandDescriptor(id: "presence", label: "プレゼンス帯域", rangeDescription: "2.5-5.5kHz", lowerBound: 2_500, upperBound: 5_500),
        AudioBandDescriptor(id: "air", label: "エアー帯域", rangeDescription: "10-20kHz", lowerBound: 10_000, upperBound: 20_000)
    ]
}

struct AudioSignal {
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

struct AnalysisData: Sendable {
    let cutoffFrequency: Double
    let dominantHarmonics: [HarmonicPeak]
    let harmonicConfidence: Float
    let hasShimmer: Bool
    let shimmerRatio: Float
    let brightnessRatio: Float
    let transientAmount: Float
    let noiseAmount: Float
}

struct NeuralFoldoverFeatures: Sendable {
    let harmonicConfidence: Float
    let shimmerRatio: Float
    let brightnessRatio: Float
    let transientAmount: Float
    let cutoffFrequency: Double
    let noiseAmount: Float
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
}

struct AudioMetricSnapshot: Sendable {
    let peakDBFS: Double
    let rmsDBFS: Double
    let crestFactorDB: Double
    let loudnessRangeLU: Double
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
