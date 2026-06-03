import Foundation

struct DenoiseShimmerStabilizer: Sendable {
    static func exceptionRelaxation(airEnergy: Float, shimmerEnergy: Float, maximum: Float) -> Float {
        guard maximum > 0, shimmerEnergy > 1e-6 else { return 0 }

        let airRatio = airEnergy / max(shimmerEnergy, 1e-6)
        let normalized = max(0, min(1, (airRatio - 0.28) / 0.55))
        return normalized * maximum
    }

    static func mask(
        temporalExcessRatio: Float,
        bandPosition: Float,
        transientLift: Float,
        stabilization: Float,
        exceptionRelaxation: Float
    ) -> Float {
        guard temporalExcessRatio > 0, stabilization > 0 else { return 1 }

        let bandWeight = 0.75 + sinf(bandPosition * .pi) * 0.25
        let transientProtection = max(0.35, 1 - transientLift * 1.6)
        let effectiveStabilization = stabilization * max(0, 1 - exceptionRelaxation)
        let reduction = min(0.42, temporalExcessRatio * effectiveStabilization * bandWeight * transientProtection)
        return 1 - reduction
    }
}
