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
            return "配信向け"
        case .forward:
            return "前に出す"
        }
    }

    var summary: String {
        switch self {
        case .natural:
            return "原音の雰囲気を残しながら整えます"
        case .streaming:
            return "ラウドネスとトゥルーピークを配信向けに整えます"
        case .forward:
            return "プレゼンス帯域とラウドネスを前に出して仕上げます"
        }
    }

    var settings: MasteringSettings {
        switch self {
        case .natural:
            return MasteringSettings(
                targetLoudness: -15.5,
                peakCeilingDB: -1.2,
                lowShelfGain: 0.8,
                lowMidGain: 0.18,
                presenceGain: 0.18,
                highShelfGain: 0.52,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -23, ratio: 1.7, attackMs: 30, releaseMs: 180, makeupGainDB: 0.4),
                    mid: BandCompressorSettings(thresholdDB: -22, ratio: 1.5, attackMs: 18, releaseMs: 140, makeupGainDB: 0.2),
                    high: BandCompressorSettings(thresholdDB: -24, ratio: 1.8, attackMs: 8, releaseMs: 110, makeupGainDB: 0.1)
                ),
                deEsserAmount: 0.22,
                deEsserThresholdDB: -26,
                stereoWidth: 1.04,
                saturationAmount: 0.10
            )
        case .streaming:
            return MasteringSettings(
                targetLoudness: -14.0,
                peakCeilingDB: -1.0,
                lowShelfGain: 1.12,
                lowMidGain: 0.26,
                presenceGain: 0.26,
                highShelfGain: 0.72,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -25, ratio: 2.2, attackMs: 26, releaseMs: 170, makeupGainDB: 0.7),
                    mid: BandCompressorSettings(thresholdDB: -23, ratio: 1.9, attackMs: 14, releaseMs: 130, makeupGainDB: 0.4),
                    high: BandCompressorSettings(thresholdDB: -25, ratio: 2.1, attackMs: 6, releaseMs: 90, makeupGainDB: 0.2)
                ),
                deEsserAmount: 0.34,
                deEsserThresholdDB: -27,
                stereoWidth: 1.08,
                saturationAmount: 0.16
            )
        case .forward:
            return MasteringSettings(
                targetLoudness: -12.8,
                peakCeilingDB: -0.9,
                lowShelfGain: 1.45,
                lowMidGain: 0.34,
                presenceGain: 0.34,
                highShelfGain: 0.94,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -27, ratio: 2.6, attackMs: 22, releaseMs: 160, makeupGainDB: 1.0),
                    mid: BandCompressorSettings(thresholdDB: -24, ratio: 2.2, attackMs: 10, releaseMs: 110, makeupGainDB: 0.7),
                    high: BandCompressorSettings(thresholdDB: -26, ratio: 2.4, attackMs: 4, releaseMs: 80, makeupGainDB: 0.4)
                ),
                deEsserAmount: 0.40,
                deEsserThresholdDB: -28,
                stereoWidth: 1.12,
                saturationAmount: 0.22
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
