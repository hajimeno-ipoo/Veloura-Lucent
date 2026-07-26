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

struct StemRoleAnalysisSnapshot: Equatable, Sendable {
    let role: StemRole
    let authoritativeSampleRate: Double
    let analysisSampleRate: Double
    let authoritativeFrameCount: Int
    let analysisFrameCount: Int
    let features: [StemRoleFeatureDistribution]

    init(
        role: StemRole,
        authoritativeSampleRate: Double,
        analysisSampleRate: Double,
        authoritativeFrameCount: Int,
        analysisFrameCount: Int,
        features: [StemRoleFeatureDistribution]
    ) {
        self.role = role
        self.authoritativeSampleRate = authoritativeSampleRate
        self.analysisSampleRate = analysisSampleRate
        self.authoritativeFrameCount = authoritativeFrameCount
        self.analysisFrameCount = analysisFrameCount
        self.features = features
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
