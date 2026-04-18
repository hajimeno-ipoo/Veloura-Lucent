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
        AudioBandDescriptor(id: "low", label: "低域", rangeDescription: "0-5kHz", lowerBound: 0, upperBound: 5_000),
        AudioBandDescriptor(id: "presence", label: "中高域", rangeDescription: "5-10kHz", lowerBound: 5_000, upperBound: 10_000),
        AudioBandDescriptor(id: "high", label: "高域", rangeDescription: "10-16kHz", lowerBound: 10_000, upperBound: 16_000),
        AudioBandDescriptor(id: "air", label: "超高域", rangeDescription: "16-24kHz", lowerBound: 16_000, upperBound: 24_000)
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
    let hasShimmer: Bool
    let shimmerRatio: Float
    let brightnessRatio: Float
    let transientAmount: Float
}

struct AudioMetricSnapshot: Sendable {
    let peakDBFS: Double
    let rmsDBFS: Double
    let centroidHz: Double
    let hf12Ratio: Double
    let hf16Ratio: Double
    let hf18Ratio: Double
    let bandEnergies: [BandEnergyMetric]
}

struct BandEnergyMetric: Sendable, Identifiable {
    let id: String
    let label: String
    let rangeDescription: String
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
