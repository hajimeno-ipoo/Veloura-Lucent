import Foundation

enum NoiseMeasurementID {
    static let hiss = "hiss"
    static let sibilance = "sibilance"
    static let shimmer = "shimmer"
    static let mud = "mud"
    static let hum = "hum"
    static let rumble = "rumble"
    static let room = "room"
}

struct NoiseSeverityLimit: Sendable, Equatable {
    let id: String
    let cautionDB: Double
    let warningDB: Double
    let masteringWorseningCautionDB: Double
}

struct NoiseReturnLimit: Sendable, Equatable {
    let id: String
    let lowerFrequency: Double
    let upperFrequency: Double
    let allowedReturnDB: Double
    let reductionMultiplier: Double
    let maxReductionDB: Double
}

struct ShimmerLimitRule: Sendable, Equatable {
    let id: String
    let lowerFrequency: Double
    let upperFrequency: Double
    let improvementDB: Double
}

enum InternalAudioJudgementPolicy {
    static let routeLowNoiseQuietRumbleDB = -12.0
    static let routeLowNoiseQuietHumDB = 5.0
    static let routeHighNoiseQuietHissDB = -58.0
    static let routeHighNoiseQuietShimmerDB = -46.0
    static let routeHighNoiseCareHissDB = -52.0
    static let routeHighNoiseCareShimmerDB = -42.0
    static let routeLowMidCleanMudDB = -9.0
    static let routeSibilanceLowDB = 7.0
    static let routeShimmerRatioLow: Float = 0.18
    static let routeRepairShimmerRatioLow: Float = 0.16
    static let routeRepairArtifactRatioLow: Float = 0.12

    static let masteringDeEssHarshnessLow: Float = 0.24
    static let masteringSibilanceLowDB = 7.0
    static let masteringSaturationOffAmount: Float = 0.015
    static let masteringAirEnoughHighToMidGapDB = -2.5
    static let masteringAirLowShelfGain: Float = 0.18
    static let masteringStereoCloseTolerance: Float = 0.035
    static let masteringHighReturnHarshnessLow: Float = 0.30
    static let masteringHighReturnShelfLow: Float = 0.34
    static let masteringHighReturnShimmerLowDB = -44.0
    static let masteringNoiseCleanHissDB = -58.0
    static let masteringNoiseCleanShimmerDB = -46.0

    static let noiseSeverityLimits: [NoiseSeverityLimit] = [
        NoiseSeverityLimit(id: NoiseMeasurementID.hiss, cautionDB: -54, warningDB: -48, masteringWorseningCautionDB: 2.0),
        NoiseSeverityLimit(id: NoiseMeasurementID.sibilance, cautionDB: 8, warningDB: 12, masteringWorseningCautionDB: 2.0),
        NoiseSeverityLimit(id: NoiseMeasurementID.shimmer, cautionDB: -42, warningDB: -36, masteringWorseningCautionDB: 1.5),
        NoiseSeverityLimit(id: NoiseMeasurementID.mud, cautionDB: -7, warningDB: -4, masteringWorseningCautionDB: 1.8),
        NoiseSeverityLimit(id: NoiseMeasurementID.hum, cautionDB: 6, warningDB: 10, masteringWorseningCautionDB: 2.0),
        NoiseSeverityLimit(id: NoiseMeasurementID.rumble, cautionDB: -9, warningDB: -5, masteringWorseningCautionDB: 1.8),
        NoiseSeverityLimit(id: NoiseMeasurementID.room, cautionDB: -42, warningDB: -36, masteringWorseningCautionDB: 2.0)
    ]

    static let masteringNoiseReturnLimits: [NoiseReturnLimit] = [
        NoiseReturnLimit(
            id: NoiseMeasurementID.hiss,
            lowerFrequency: 8_000,
            upperFrequency: 20_000,
            allowedReturnDB: -2.0,
            reductionMultiplier: 2.2,
            maxReductionDB: 18.0
        ),
        NoiseReturnLimit(
            id: NoiseMeasurementID.sibilance,
            lowerFrequency: 5_000,
            upperFrequency: 12_000,
            allowedReturnDB: 0.6,
            reductionMultiplier: 0.9,
            maxReductionDB: 6.0
        ),
        NoiseReturnLimit(
            id: NoiseMeasurementID.shimmer,
            lowerFrequency: 8_000,
            upperFrequency: 16_000,
            allowedReturnDB: 0.7,
            reductionMultiplier: 0.9,
            maxReductionDB: 6.0
        )
    ]

    static func shimmerLimitRules(improvementDB: Double) -> [ShimmerLimitRule] {
        [
            ShimmerLimitRule(id: NoiseMeasurementID.shimmer, lowerFrequency: 5_000, upperFrequency: 14_000, improvementDB: improvementDB),
            ShimmerLimitRule(id: NoiseMeasurementID.hiss, lowerFrequency: 5_000, upperFrequency: 20_000, improvementDB: improvementDB)
        ]
    }

    static func shimmerMaxReductionPerPassDB(correctionIntensity: Float) -> Double {
        if correctionIntensity >= 0.70 { return 24 }
        if correctionIntensity >= 0.50 { return 12 }
        return 8
    }

    static func shimmerReductionScale(correctionIntensity: Float) -> Double {
        if correctionIntensity >= 0.70 { return 1.25 }
        if correctionIntensity >= 0.50 { return 0.82 }
        return 0.65
    }

    static func severityLimit(for id: String) -> NoiseSeverityLimit? {
        noiseSeverityLimits.first { $0.id == id }
    }
}
