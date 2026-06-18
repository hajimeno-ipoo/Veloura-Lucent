import Foundation

enum MasteringProfile: String, CaseIterable, Identifiable, Sendable {
    case natural
    case streaming
    case forward
    case safeAIStreaming
    case youtubeSpotify
    case releaseLoud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural:
            return "自然"
        case .streaming:
            return "聴きやすく整える"
        case .forward:
            return "押し出し強め"
        case .safeAIStreaming:
            return "安全AI配信"
        case .youtubeSpotify:
            return "YouTube / Spotify向け"
        case .releaseLoud:
            return "リリース音圧重視"
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
        case .safeAIStreaming:
            return "ノイズ戻りを抑えながら配信向けの音量を狙います"
        case .youtubeSpotify:
            return "YouTubeやSpotify向けに音量を明確に狙います"
        case .releaseLoud:
            return "音圧を重視して、強く前に出る仕上げにします"
        }
    }

    var presetTargetText: String {
        let settings = settings
        return String(
            format: "目安: %.1f LUFS / True Peak上限: %.1f dBTP",
            Double(settings.targetLoudness),
            Double(settings.peakCeilingDB)
        )
    }

    var presetHelpText: String {
        switch self {
        case .natural:
            return "原音の雰囲気を残しながら、音量を控えめに整えます。"
        case .streaming:
            return "聞きやすさを優先し、ラウドネスと帯域のバランスを整えます。"
        case .forward:
            return "密度と前に出る感じを少し強めます。"
        case .safeAIStreaming:
            return "ノイズ戻りを抑えながら、配信向けの音量を狙います。"
        case .youtubeSpotify:
            return "YouTubeやSpotify向けに、扱いやすい音量を狙います。"
        case .releaseLoud:
            return "音圧を重視します。強弱が少なくなる場合があります。"
        }
    }

    var settings: MasteringSettings {
        switch self {
        case .natural:
            return MasteringSettings(
                targetLoudness: -17.4,
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
                targetLoudness: -16.7,
                peakCeilingDB: -1.5,
                lowShelfGain: 0.72,
                lowMidGain: -0.34,
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
                targetLoudness: -14.8,
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
        case .safeAIStreaming:
            return makeMasteringSettings(
                basedOn: .streaming,
                targetLoudness: -14.5,
                peakCeilingDB: -1.2,
                finishingIntensity: 0.65
            )
        case .youtubeSpotify:
            return makeMasteringSettings(
                basedOn: .forward,
                targetLoudness: -14.0,
                peakCeilingDB: -1.0,
                finishingIntensity: 0.85
            )
        case .releaseLoud:
            return makeMasteringSettings(
                basedOn: .forward,
                targetLoudness: -12.0,
                peakCeilingDB: -1.0,
                finishingIntensity: 0.95
            )
        }
    }

}

private func makeMasteringSettings(
    basedOn profile: MasteringProfile,
    targetLoudness: Float,
    peakCeilingDB: Float,
    finishingIntensity: Float
) -> MasteringSettings {
    var settings = profile.settings
    settings.targetLoudness = targetLoudness
    settings.peakCeilingDB = peakCeilingDB
    settings.finishingIntensity = finishingIntensity
    return settings
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

struct LoudnessAdjustmentPolicy: Sendable, Equatable {
    let label: String
    let maxBoostDB: Double
    let maxCutDB: Double
    let deadbandDB: Double
    let finalRestoreLimitDB: Double
    let targetOvershootLimitDB: Double
}

extension MasteringSettings {
    var loudnessAdjustmentPolicy: LoudnessAdjustmentPolicy {
        if finishingIntensity <= 0.45 {
            return LoudnessAdjustmentPolicy(
                label: "自然",
                maxBoostDB: 1.5,
                maxCutDB: 1.0,
                deadbandDB: 0.5,
                finalRestoreLimitDB: 1.5,
                targetOvershootLimitDB: 0.75
            )
        }
        if finishingIntensity < 0.60 {
            return LoudnessAdjustmentPolicy(
                label: "聴きやすく整える",
                maxBoostDB: 3.0,
                maxCutDB: 1.5,
                deadbandDB: 0.5,
                finalRestoreLimitDB: 2.0,
                targetOvershootLimitDB: 1.0
            )
        }
        if finishingIntensity < 0.70 {
            return LoudnessAdjustmentPolicy(
                label: "安全AI配信",
                maxBoostDB: 4.0,
                maxCutDB: 1.5,
                deadbandDB: 0.5,
                finalRestoreLimitDB: 2.5,
                targetOvershootLimitDB: 0.75
            )
        }
        if finishingIntensity < 0.80 {
            return LoudnessAdjustmentPolicy(
                label: "押し出し強め",
                maxBoostDB: 4.5,
                maxCutDB: 2.0,
                deadbandDB: 0.5,
                finalRestoreLimitDB: 2.0,
                targetOvershootLimitDB: 1.5
            )
        }
        if finishingIntensity < 0.90 {
            return LoudnessAdjustmentPolicy(
                label: "YouTube / Spotify向け",
                maxBoostDB: 5.0,
                maxCutDB: 2.0,
                deadbandDB: 0.5,
                finalRestoreLimitDB: 3.0,
                targetOvershootLimitDB: 1.25
            )
        }
        return LoudnessAdjustmentPolicy(
            label: "リリース音圧重視",
            maxBoostDB: 6.0,
            maxCutDB: 2.0,
            deadbandDB: 0.5,
            finalRestoreLimitDB: 3.0,
            targetOvershootLimitDB: 2.0
        )
    }

    var aggressiveSettingWarnings: [String] {
        var warnings: [String] = []
        if targetLoudness >= -12 {
            warnings.append("音圧重視。強弱が少なくなる場合があります。")
        }
        if peakCeilingDB >= -0.7 {
            warnings.append("歪みやすい設定です。配信や再生環境によって音割れする可能性があります。")
        }
        return warnings
    }
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
    case loadAudio = "補正済み音源を読み込みます"
    case analyze = "補正済み音源を解析します"
    case routeNoiseMeasurement = "ノイズ戻りの基準を測定します"
    case tone = "帯域バランスを整えます"
    case deEss = "ハーシュネスを抑えます"
    case dynamics = "帯域のバランスを整えます"
    case saturate = "音の密度を整えます"
    case air = "空気感を整えます"
    case stereo = "ステレオ幅を整えます"
    case loudness = "ラウドネスを整えます"
    case highReturnGuard = "高域戻りを抑えます"
    case noiseReturnGuard = "ノイズ戻りを抑えます"
    case highPreserve = "高域保持を確認します"
    case finalNoiseCeiling = "最終ノイズ上限を確認します"
    case finalHighPreserve = "最終高域保持を確認します"
    case finalLoudnessRestore = "最終音量を復帰します"
    case finalNoiseConfirm = "最終ノイズを確認します"
    case finalLoudnessBounds = "最終音量上限を確認します"
    case save = "マスタリング済みファイルを書き出します"

    var title: String {
        switch self {
        case .loadAudio:
            return "読み込み"
        case .analyze:
            return "解析"
        case .routeNoiseMeasurement:
            return "ノイズ基準"
        case .tone:
            return "帯域バランス"
        case .deEss:
            return "ハーシュネス抑制"
        case .dynamics:
            return "帯域制御"
        case .saturate:
            return "密度調整"
        case .air:
            return "空気感"
        case .stereo:
            return "ステレオ幅"
        case .loudness:
            return "ラウドネス"
        case .highReturnGuard:
            return "高域戻り"
        case .noiseReturnGuard:
            return "ノイズ戻り"
        case .highPreserve:
            return "高域保持"
        case .finalNoiseCeiling:
            return "最終ノイズ上限"
        case .finalHighPreserve:
            return "最終高域保持"
        case .finalLoudnessRestore:
            return "最終音量復帰"
        case .finalNoiseConfirm:
            return "最終ノイズ確認"
        case .finalLoudnessBounds:
            return "最終音量上限"
        case .save:
            return "書き出し"
        }
    }

    var eventID: String {
        switch self {
        case .loadAudio: "loadAudio"
        case .analyze: "analyze"
        case .routeNoiseMeasurement: "routeNoiseMeasurement"
        case .tone: "tone"
        case .deEss: "deEss"
        case .dynamics: "dynamics"
        case .saturate: "saturate"
        case .air: "air"
        case .stereo: "stereo"
        case .loudness: "loudness"
        case .highReturnGuard: "highReturnGuard"
        case .noiseReturnGuard: "noiseReturnGuard"
        case .highPreserve: "highPreserve"
        case .finalNoiseCeiling: "finalNoiseCeiling"
        case .finalHighPreserve: "finalHighPreserve"
        case .finalLoudnessRestore: "finalLoudnessRestore"
        case .finalNoiseConfirm: "finalNoiseConfirm"
        case .finalLoudnessBounds: "finalLoudnessBounds"
        case .save: "save"
        }
    }

    static func step(eventID: String) -> MasteringStep? {
        allCases.first { $0.eventID == eventID }
    }
}
