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
            return "聞きやすさと音量感のバランスを取ります"
        case .forward:
            return "存在感を前に出して仕上げます"
        }
    }

    var settings: MasteringSettings {
        switch self {
        case .natural:
            return MasteringSettings(
                targetLoudness: -15.5,
                peakCeilingDB: -1.2,
                lowShelfGain: 0.8,
                highShelfGain: 0.6,
                bandControlAmount: 0.24,
                stereoWidth: 1.04,
                saturationAmount: 0.10
            )
        case .streaming:
            return MasteringSettings(
                targetLoudness: -14.0,
                peakCeilingDB: -1.0,
                lowShelfGain: 1.2,
                highShelfGain: 0.8,
                bandControlAmount: 0.34,
                stereoWidth: 1.08,
                saturationAmount: 0.16
            )
        case .forward:
            return MasteringSettings(
                targetLoudness: -12.8,
                peakCeilingDB: -0.9,
                lowShelfGain: 1.6,
                highShelfGain: 1.1,
                bandControlAmount: 0.42,
                stereoWidth: 1.12,
                saturationAmount: 0.22
            )
        }
    }
}

struct MasteringSettings: Sendable {
    let targetLoudness: Float
    let peakCeilingDB: Float
    let lowShelfGain: Float
    let highShelfGain: Float
    let bandControlAmount: Float
    let stereoWidth: Float
    let saturationAmount: Float
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

enum MasteringStep: String, CaseIterable, Hashable {
    case analyze = "補正済み音源を解析します"
    case tone = "トーンを整えます"
    case dynamics = "帯域のバランスを整えます"
    case saturate = "音の密度を整えます"
    case stereo = "広がりを整えます"
    case loudness = "音量を整えます"
    case save = "マスタリング済みファイルを書き出します"

    var title: String {
        switch self {
        case .analyze:
            return "解析"
        case .tone:
            return "トーン"
        case .dynamics:
            return "帯域制御"
        case .saturate:
            return "密度調整"
        case .stereo:
            return "広がり"
        case .loudness:
            return "音量"
        case .save:
            return "書き出し"
        }
    }
}
