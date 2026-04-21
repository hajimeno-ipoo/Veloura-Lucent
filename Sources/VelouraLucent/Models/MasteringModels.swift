import Foundation

enum MasteringProfile: String, CaseIterable, Identifiable, Sendable {
    case natural
    case streaming
    case forward

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural:
            return "自然"
        case .streaming:
            return "聴きやすく整える"
        case .forward:
            return "押し出し強め"
        }
    }

    var summary: String {
        switch self {
        case .natural:
            return "原音の雰囲気を残しながら整えます"
        case .streaming:
            return "ラウドネスと帯域のバランスを、聞きやすさ重視で整えます"
        case .forward:
            return "密度とプレゼンスを少し積極的に持ち上げて仕上げます"
        }
    }

    var settings: MasteringSettings {
        switch self {
        case .natural:
            return MasteringSettings(
                targetLoudness: -16.0,
                peakCeilingDB: -1.2,
                lowShelfGain: 0.55,
                lowMidGain: -0.18,
                presenceGain: 0.22,
                highShelfGain: 0.32,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -22, ratio: 1.6, attackMs: 34, releaseMs: 210, makeupGainDB: 0.2),
                    mid: BandCompressorSettings(thresholdDB: -21, ratio: 1.4, attackMs: 22, releaseMs: 170, makeupGainDB: 0.1),
                    high: BandCompressorSettings(thresholdDB: -24, ratio: 1.55, attackMs: 10, releaseMs: 130, makeupGainDB: 0.0)
                ),
                deEsserAmount: 0.18,
                deEsserThresholdDB: -24,
                stereoWidth: 1.00,
                saturationAmount: 0.08,
                dynamicsRetention: 0.82,
                finishingIntensity: 0.35
            )
        case .streaming:
            return MasteringSettings(
                targetLoudness: -14.5,
                peakCeilingDB: -1.0,
                lowShelfGain: 0.85,
                lowMidGain: -0.28,
                presenceGain: 0.38,
                highShelfGain: 0.48,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -23, ratio: 1.75, attackMs: 30, releaseMs: 205, makeupGainDB: 0.22),
                    mid: BandCompressorSettings(thresholdDB: -21.5, ratio: 1.55, attackMs: 18, releaseMs: 160, makeupGainDB: 0.12),
                    high: BandCompressorSettings(thresholdDB: -23.5, ratio: 1.55, attackMs: 9, releaseMs: 125, makeupGainDB: 0.0)
                ),
                deEsserAmount: 0.24,
                deEsserThresholdDB: -24.5,
                stereoWidth: 1.03,
                saturationAmount: 0.09,
                dynamicsRetention: 0.68,
                finishingIntensity: 0.55
            )
        case .forward:
            return MasteringSettings(
                targetLoudness: -13.8,
                peakCeilingDB: -0.9,
                lowShelfGain: 0.95,
                lowMidGain: -0.16,
                presenceGain: 0.52,
                highShelfGain: 0.58,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -24, ratio: 1.9, attackMs: 26, releaseMs: 195, makeupGainDB: 0.32),
                    mid: BandCompressorSettings(thresholdDB: -22, ratio: 1.75, attackMs: 14, releaseMs: 140, makeupGainDB: 0.18),
                    high: BandCompressorSettings(thresholdDB: -24, ratio: 1.7, attackMs: 8, releaseMs: 110, makeupGainDB: 0.02)
                ),
                deEsserAmount: 0.28,
                deEsserThresholdDB: -25,
                stereoWidth: 1.05,
                saturationAmount: 0.11,
                dynamicsRetention: 0.52,
                finishingIntensity: 0.75
            )
        }
    }
}

struct MasteringSettings: Sendable, Equatable {
    var targetLoudness: Float
    var peakCeilingDB: Float
    var lowShelfGain: Float
    var lowMidGain: Float
    var presenceGain: Float
    var highShelfGain: Float
    var multibandCompression: MultibandCompressionSettings
    var deEsserAmount: Float
    var deEsserThresholdDB: Float
    var stereoWidth: Float
    var saturationAmount: Float
    var dynamicsRetention: Float
    var finishingIntensity: Float
}

struct MultibandCompressionSettings: Sendable, Equatable {
    var low: BandCompressorSettings
    var mid: BandCompressorSettings
    var high: BandCompressorSettings
}

struct BandCompressorSettings: Sendable, Equatable {
    var thresholdDB: Float
    var ratio: Float
    var attackMs: Float
    var releaseMs: Float
    var makeupGainDB: Float
}

struct MasteringAnalysis: Sendable {
    let integratedLoudness: Float
    let truePeakDBFS: Double
    let lowBandLevelDB: Double
    let midBandLevelDB: Double
    let highBandLevelDB: Double
    let harshnessScore: Float
    let stereoWidth: Float
}

enum AudioComparisonPair: String, CaseIterable, Identifiable {
    case inputVsCorrected
    case inputVsMastered
    case correctedVsMastered

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inputVsCorrected:
            return "入力 vs 補正後"
        case .inputVsMastered:
            return "入力 vs 最終版"
        case .correctedVsMastered:
            return "補正後 vs 最終版"
        }
    }

    var summary: String {
        switch self {
        case .inputVsCorrected:
            return "補正でどれだけ整ったかを聴き比べます"
        case .inputVsMastered:
            return "最初の音と最終版をそのまま聴き比べます"
        case .correctedVsMastered:
            return "マスタリングでどれだけ仕上がったかを聴き比べます"
        }
    }

    var firstTarget: AudioPreviewTarget {
        switch self {
        case .inputVsCorrected:
            return .input
        case .inputVsMastered:
            return .input
        case .correctedVsMastered:
            return .corrected
        }
    }

    var secondTarget: AudioPreviewTarget {
        switch self {
        case .inputVsCorrected:
            return .corrected
        case .inputVsMastered:
            return .mastered
        case .correctedVsMastered:
            return .mastered
        }
    }

    var targets: [AudioPreviewTarget] {
        [firstTarget, secondTarget]
    }

    func title(for side: AudioComparisonSide) -> String {
        switch side {
        case .a:
            return "A"
        case .b:
            return "B"
        }
    }
}

enum AudioComparisonSide: String, CaseIterable, Identifiable {
    case a
    case b

    var id: String { rawValue }
}

enum MasteringStep: String, CaseIterable, Hashable {
    case analyze = "補正済み音源を解析します"
    case tone = "帯域バランスを整えます"
    case deEss = "ハーシュネスを抑えます"
    case dynamics = "帯域のバランスを整えます"
    case saturate = "音の密度を整えます"
    case stereo = "ステレオ幅を整えます"
    case loudness = "ラウドネスを整えます"
    case save = "マスタリング済みファイルを書き出します"

    var title: String {
        switch self {
        case .analyze:
            return "解析"
        case .tone:
            return "帯域バランス"
        case .deEss:
            return "ハーシュネス抑制"
        case .dynamics:
            return "帯域制御"
        case .saturate:
            return "密度調整"
        case .stereo:
            return "ステレオ幅"
        case .loudness:
            return "ラウドネス"
        case .save:
            return "書き出し"
        }
    }
}
