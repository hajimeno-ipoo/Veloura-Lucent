import Foundation

enum StemRoleAnalysisFeature: String, CaseIterable, Sendable {
    case vocalsVoicedHarmonicStrength
    case vocalsBreathConsonantBalance
    case vocalsFormantCenter
    case vocalsHarmonicContinuity

    case drumsOnsetStrength
    case drumsAttackCrest
    case drumsCymbalDecayContinuity
    case drumsQuietGapContrast

    case bassFundamentalHarmonicStrength
    case bassFiftyHertzPitchAlignment
    case bassSixtyHertzPitchAlignment
    case bassLowBandPhaseCoherence

    case otherPolyphonicSpectralSpread
    case otherTransientStrength
    case otherAmbienceContinuity
    case otherStereoSpatialBalance

    case guitarPickingOnsetEnergy
    case guitarAttackCrest
    case guitarHarmonicEnergyRatio
    case guitarInharmonicity
    case guitarHighBandDetail
    case guitarSpectralCentroid
    case guitarRolloff85
    case guitarLowTailRetention
    case guitarMidTailRetention
    case guitarHighTailRetention
    case guitarStereoSideRatio
    case guitarStereoCorrelation

    case pianoHammerOnsetEnergy
    case pianoAttackCrest
    case pianoPartialEnergyRatio
    case pianoInharmonicity
    case pianoLowTailRetention
    case pianoMidTailRetention
    case pianoHighTailRetention
    case pianoDoubleDecaySlopeDelta
    case pianoLowBandBalance
    case pianoMidBandBalance
    case pianoSpectralCentroid
    case pianoRolloff85
    case pianoStereoSideRatio
    case pianoStereoCorrelation
}

/// 役割別解析の集約表示で、変化方向を説明するメタデータです。
/// 本番guardの固定閾値や音質スコアには使用しません。
enum StemRoleFeaturePreservationRule: String, Sendable {
    case preserveMinimum

    case preserveStability
}

enum StemRoleAnalysisUnit: String, Sendable {
    case ratio
    case normalized
    case hertz
    case decibels
    case decibelsPerSecond
}

struct StemRoleFeatureDistribution: Equatable, Sendable {
    let feature: StemRoleAnalysisFeature
    let preservationRule: StemRoleFeaturePreservationRule
    let unit: StemRoleAnalysisUnit
    let frameCount: Int
    let firstQuartile: Double
    let median: Double
    let thirdQuartile: Double
    let interquartileRange: Double
}

/// Guitar／Piano専用解析が、無音を正規化特徴量として誤判定しないための活動結果です。
struct StemRoleActivitySummary: Equatable, Sendable {
    let floorDecibelsFullScale: Double
    let thresholdDecibelsFullScale: Double
    let totalFrameCount: Int
    let activeFrameCount: Int

    var activeFraction: Double {
        guard totalFrameCount > 0 else { return 0 }
        return Double(activeFrameCount) / Double(totalFrameCount)
    }

    var hasActivity: Bool {
        activeFrameCount > 0
    }
}

/// 実Guitar／Pianoと劣化模擬で採用した専用解析量です。
///
/// 値は音質の合否点ではなく、同じStemのDSP前後を比べるための観測量です。
/// Pianoの`highBandRatio`は補助観測に留め、Pianoの保護対象には使用しません。
struct StemDedicatedRoleMetrics: Equatable, Sendable {
    let onsetEnergy90thPercentile: Double
    let attackCrest90thPercentileDecibels: Double
    let harmonicEnergyRatioMedian: Double
    let inharmonicityMedian: Double
    let spectralCentroidMedianHertz: Double
    let rolloff85MedianHertz: Double
    let highBandRatioMedian: Double
    let highBandRatio90thPercentile: Double
    let lowBandRatioMedian: Double
    let midBandRatioMedian: Double
    let tailRMSRatioMedianDecibels: Double
    let tailLowRatioMedianDecibels: Double
    let tailMidRatioMedianDecibels: Double
    let tailHighRatioMedianDecibels: Double
    let doubleDecaySlopeDeltaMedianDecibelsPerSecond: Double
    let stereoSideRatio: Double
    let stereoCorrelation: Double
    let detectedOnsetCount: Int
}

struct StemRoleAnalysisSnapshot: Equatable, Sendable {
    let role: StemRole
    let authoritativeSampleRate: Double
    let analysisSampleRate: Double
    let authoritativeFrameCount: Int
    let analysisFrameCount: Int
    let features: [StemRoleFeatureDistribution]
    let activity: StemRoleActivitySummary?
    let dedicatedMetrics: StemDedicatedRoleMetrics?

    init(
        role: StemRole,
        authoritativeSampleRate: Double,
        analysisSampleRate: Double,
        authoritativeFrameCount: Int,
        analysisFrameCount: Int,
        features: [StemRoleFeatureDistribution],
        activity: StemRoleActivitySummary? = nil,
        dedicatedMetrics: StemDedicatedRoleMetrics? = nil
    ) {
        self.role = role
        self.authoritativeSampleRate = authoritativeSampleRate
        self.analysisSampleRate = analysisSampleRate
        self.authoritativeFrameCount = authoritativeFrameCount
        self.analysisFrameCount = analysisFrameCount
        self.features = features
        self.activity = activity
        self.dedicatedMetrics = dedicatedMetrics
    }
}

/// Stem固有guardが、同じ時間位置のDSP前後を比較するために使う保護対象です。
///
/// これは音質スコアではありません。各値は今回のStem自身から取得した解析量であり、
/// 他曲や評価用サンプルから作った固定基準を持ちません。
enum StemRoleProtectedComponent: String, CaseIterable, Hashable, Sendable {
    case vocalsBreath
    case vocalsConsonants
    case vocalsSibilance
    case vocalsFormant
    case vocalsHarmonics
    case vocalsCore

    case drumsAttack
    case drumsTransient
    case drumsCymbalDecay

    case bassFundamental
    case bassHarmonics
    case bassMainsRegionPitchContent
    case bassLowPhase

    case otherReverb
    case otherAmbience
    case otherSpace
    case otherStereo

    case guitarAttack
    case guitarHarmonics
    case guitarInharmonicity
    case guitarHighDetail
    case guitarDecay
    case guitarStereoSide
    case guitarStereoCorrelation

    case pianoAttack
    case pianoPartials
    case pianoInharmonicity
    case pianoLowDecay
    case pianoMidDecay
    case pianoHighDecay
    case pianoDoubleDecay
    case pianoLowBandBalance
    case pianoMidBandBalance
    case pianoStereoSide
    case pianoStereoCorrelation

    var role: StemRole {
        switch self {
        case .vocalsBreath, .vocalsConsonants, .vocalsSibilance, .vocalsFormant,
             .vocalsHarmonics, .vocalsCore:
            .vocals
        case .drumsAttack, .drumsTransient, .drumsCymbalDecay:
            .drums
        case .bassFundamental, .bassHarmonics, .bassMainsRegionPitchContent, .bassLowPhase:
            .bass
        case .otherReverb, .otherAmbience, .otherSpace, .otherStereo:
            .other
        case .guitarAttack, .guitarHarmonics, .guitarInharmonicity,
             .guitarHighDetail, .guitarDecay, .guitarStereoSide,
             .guitarStereoCorrelation:
            .guitar
        case .pianoAttack, .pianoPartials, .pianoInharmonicity,
             .pianoLowDecay, .pianoMidDecay, .pianoHighDecay,
             .pianoDoubleDecay, .pianoLowBandBalance, .pianoMidBandBalance,
             .pianoStereoSide, .pianoStereoCorrelation:
            .piano
        }
    }

}

struct StemRoleProtectionFrame: Equatable, Sendable {
    let startFrame: Int
    let validFrameCount: Int
    let values: [StemRoleProtectedComponent: Double]
}

/// 今回のStemだけを基準にした、時系列の役割別保護解析です。
///
/// DSP処理中だけ保持し、今回の入力自身を基準にします。
/// 別音源の集約値やIQRを本番guardの固定基準へ転用しません。
struct StemRoleProtectionProfile: Equatable, Sendable {
    let role: StemRole
    let sampleRate: Double
    let signalFrameCount: Int
    let analysisFrameSize: Int
    let hopSize: Int
    let frames: [StemRoleProtectionFrame]
}

struct StemRoleAnalysisResult: Equatable, Sendable {
    let snapshot: StemRoleAnalysisSnapshot
    let protectionProfile: StemRoleProtectionProfile
}

enum StemRoleAnalysisError: LocalizedError, Equatable, Sendable {
    case unsupportedAuthoritativeSampleRate(expected: Double, actual: Double)
    case stereoRequired(actualChannelCount: Int)
    case emptySignal
    case inconsistentFrameCount(channelIndex: Int, expected: Int, actual: Int)
    case nonFiniteSample(channelIndex: Int, frameIndex: Int)
    case unableToCreateFourierTransform
    case unableToProduceFeature(StemRoleAnalysisFeature)
    case unableToProduceProtectionProfile(StemRole)

    var errorDescription: String? {
        switch self {
        case let .unsupportedAuthoritativeSampleRate(expected, actual):
            "Stem役割解析の音声正本は\(expected) Hzである必要があります（実際: \(actual) Hz）。"
        case let .stereoRequired(actualChannelCount):
            "Stem役割解析にはステレオ音声が必要です（実際: \(actualChannelCount)チャンネル）。"
        case .emptySignal:
            "Stem役割解析の音声が空です。"
        case let .inconsistentFrameCount(channelIndex, expected, actual):
            "Stem役割解析のチャンネル\(channelIndex + 1)の長さが一致しません（期待: \(expected)、実際: \(actual)）。"
        case let .nonFiniteSample(channelIndex, frameIndex):
            "Stem役割解析のチャンネル\(channelIndex + 1)、frame \(frameIndex)にNaNまたはInfinityがあります。"
        case .unableToCreateFourierTransform:
            "Stem役割解析用の周波数変換を作成できません。"
        case let .unableToProduceFeature(feature):
            "Stem役割解析の特徴量を作成できません（\(feature.rawValue)）。"
        case let .unableToProduceProtectionProfile(role):
            "\(role.rawValue)の時系列保護解析を作成できません。"
        }
    }
}
