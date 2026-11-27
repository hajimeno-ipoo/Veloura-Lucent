import Foundation

enum MasteringProfile: String, CaseIterable, Identifiable, Sendable {
    case natural
    case streaming
    case forward
    case safeAIStreaming
    case youtubeSpotify
    case releaseLoud
    case brightAndClear
    case softHighs
    case strongBass
    case widerStereo
    case preserveDynamics

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
        case .brightAndClear:
            return "明るく澄んだ音"
        case .softHighs:
            return "高音をやわらかく"
        case .strongBass:
            return "低音をしっかり"
        case .widerStereo:
            return "音を左右に広げる"
        case .preserveDynamics:
            return "曲の強弱を残す"
        }
    }

    var menuTitle: String {
        "\(title) — \(recommendedUseText)"
    }

    var recommendedUseText: String {
        switch self {
        case .natural:
            return "原音の雰囲気を残したい時"
        case .streaming:
            return "聞きやすさを優先したい時"
        case .forward:
            return "密度と存在感を強めたい時"
        case .safeAIStreaming:
            return "AI生成音源を安全寄りに配信したい時"
        case .youtubeSpotify:
            return "YouTubeやSpotifyで公開する時"
        case .releaseLoud:
            return "音圧を強くして前に出したい時"
        case .brightAndClear:
            return "歌や楽器の輪郭をはっきりさせたい時"
        case .softHighs:
            return "高い音のきらつきを控えめにしたい時"
        case .strongBass:
            return "キックやベースの低い響きを足したい時"
        case .widerStereo:
            return "伴奏や残響の左右の広がりを強めたい時"
        case .preserveDynamics:
            return "静かなところと盛り上がるところの差を残したい時"
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
        case .brightAndClear:
            return "歌や楽器の輪郭がはっきりするように整えます"
        case .softHighs:
            return "高い音のきらつきを控えめに整えます"
        case .strongBass:
            return "キックやベースの低い響きを強めます"
        case .widerStereo:
            return "音源にある左右の広がりを強めます"
        case .preserveDynamics:
            return "曲の強弱が残るよう控えめに整えます"
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
        case .brightAndClear:
            return "音の輪郭を強め、明るい音を目指します。"
        case .softHighs:
            return "高い音のきらつきを抑え、やわらかい音を目指します。"
        case .strongBass:
            return "キックやベースに重みが出るように低音を整えます。"
        case .widerStereo:
            return "伴奏や残響が左右に広がって聞こえるように整えます。"
        case .preserveDynamics:
            return "静かなところと盛り上がるところの音量差を残して仕上げます。"
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
        case .brightAndClear:
            return MasteringSettings(
                targetLoudness: -20.0,
                peakCeilingDB: -1.5,
                lowShelfGain: 0.35,
                lowMidGain: -0.75,
                presenceGain: 1.20,
                highShelfGain: 2.50,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -20, ratio: 1.45, attackMs: 34, releaseMs: 200, makeupGainDB: 0),
                    mid: BandCompressorSettings(thresholdDB: -20, ratio: 1.35, attackMs: 25, releaseMs: 165, makeupGainDB: 0),
                    high: BandCompressorSettings(thresholdDB: -24, ratio: 1.45, attackMs: 12, releaseMs: 130, makeupGainDB: 0)
                ),
                deEsserAmount: 0.23,
                deEsserThresholdDB: -24.5,
                stereoWidth: 1.04,
                saturationAmount: 0.04,
                dynamicsRetention: 0.78,
                finishingIntensity: 0.45
            )
        case .softHighs:
            return MasteringSettings(
                targetLoudness: -17.5,
                peakCeilingDB: -1.5,
                lowShelfGain: 1.00,
                lowMidGain: 1.20,
                presenceGain: 0.00,
                highShelfGain: 0.00,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -22, ratio: 1.45, attackMs: 32, releaseMs: 205, makeupGainDB: 0.10),
                    mid: BandCompressorSettings(thresholdDB: -21, ratio: 1.35, attackMs: 25, releaseMs: 175, makeupGainDB: 0.30),
                    high: BandCompressorSettings(thresholdDB: -25, ratio: 1.70, attackMs: 8, releaseMs: 135, makeupGainDB: 0)
                ),
                deEsserAmount: 0.35,
                deEsserThresholdDB: -26.0,
                stereoWidth: 1.00,
                saturationAmount: 0.06,
                dynamicsRetention: 0.84,
                finishingIntensity: 0.43
            )
        case .strongBass:
            return MasteringSettings(
                targetLoudness: -15.5,
                peakCeilingDB: -1.5,
                lowShelfGain: 2.50,
                lowMidGain: -0.90,
                presenceGain: 0.00,
                highShelfGain: 0.00,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -18, ratio: 1.20, attackMs: 42, releaseMs: 210, makeupGainDB: 0.65),
                    mid: BandCompressorSettings(thresholdDB: -20, ratio: 1.45, attackMs: 25, releaseMs: 175, makeupGainDB: 0),
                    high: BandCompressorSettings(thresholdDB: -24, ratio: 1.55, attackMs: 12, releaseMs: 135, makeupGainDB: 0)
                ),
                deEsserAmount: 0.21,
                deEsserThresholdDB: -24.0,
                stereoWidth: 1.00,
                saturationAmount: 0.04,
                dynamicsRetention: 0.76,
                finishingIntensity: 0.64
            )
        case .widerStereo:
            return MasteringSettings(
                targetLoudness: -18.0,
                peakCeilingDB: -1.5,
                lowShelfGain: 0.40,
                lowMidGain: -0.20,
                presenceGain: 0.30,
                highShelfGain: 0.40,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -20, ratio: 1.35, attackMs: 35, releaseMs: 205, makeupGainDB: 0),
                    mid: BandCompressorSettings(thresholdDB: -20, ratio: 1.35, attackMs: 25, releaseMs: 175, makeupGainDB: 0),
                    high: BandCompressorSettings(thresholdDB: -23, ratio: 1.40, attackMs: 12, releaseMs: 125, makeupGainDB: 0)
                ),
                deEsserAmount: 0.20,
                deEsserThresholdDB: -24.0,
                stereoWidth: 1.30,
                saturationAmount: 0.04,
                dynamicsRetention: 0.78,
                finishingIntensity: 0.45
            )
        case .preserveDynamics:
            return MasteringSettings(
                targetLoudness: -18.0,
                peakCeilingDB: -1.5,
                lowShelfGain: 0.25,
                lowMidGain: 0.00,
                presenceGain: 0.18,
                highShelfGain: 0.20,
                multibandCompression: MultibandCompressionSettings(
                    low: BandCompressorSettings(thresholdDB: -18, ratio: 1.20, attackMs: 42, releaseMs: 200, makeupGainDB: 0),
                    mid: BandCompressorSettings(thresholdDB: -17, ratio: 1.15, attackMs: 32, releaseMs: 175, makeupGainDB: 0),
                    high: BandCompressorSettings(thresholdDB: -21, ratio: 1.25, attackMs: 18, releaseMs: 130, makeupGainDB: 0)
                ),
                deEsserAmount: 0.15,
                deEsserThresholdDB: -23.0,
                stereoWidth: 1.00,
                saturationAmount: 0.03,
                dynamicsRetention: 0.95,
                finishingIntensity: 0.36
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
    static let loudnessAggressiveWarning = "音圧重視。強弱が少なくなる場合があります。"
    static let peakCeilingAggressiveWarning = "歪みやすい設定です。配信や再生環境によって音割れする可能性があります。"
    static let allAggressiveSettingWarnings = [
        loudnessAggressiveWarning,
        peakCeilingAggressiveWarning
    ]

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
            warnings.append(Self.loudnessAggressiveWarning)
        }
        if peakCeilingDB >= -0.7 {
            warnings.append(Self.peakCeilingAggressiveWarning)
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
    let crestFactorDB: Double
    let loudnessRangeLU: Double?

    init(
        integratedLoudness: Float,
        truePeakDBFS: Double,
        lowBandLevelDB: Double,
        midBandLevelDB: Double,
        highBandLevelDB: Double,
        harshnessScore: Float,
        stereoWidth: Float,
        crestFactorDB: Double = 0,
        loudnessRangeLU: Double? = nil
    ) {
        self.integratedLoudness = integratedLoudness
        self.truePeakDBFS = truePeakDBFS
        self.lowBandLevelDB = lowBandLevelDB
        self.midBandLevelDB = midBandLevelDB
        self.highBandLevelDB = highBandLevelDB
        self.harshnessScore = harshnessScore
        self.stereoWidth = stereoWidth
        self.crestFactorDB = crestFactorDB
        self.loudnessRangeLU = loudnessRangeLU
    }
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
            return "入力と補正後を聴き比べます"
        case .inputVsMastered:
            return "入力と最終版を聴き比べます"
        case .correctedVsMastered:
            return "補正後と最終版を聴き比べます"
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
