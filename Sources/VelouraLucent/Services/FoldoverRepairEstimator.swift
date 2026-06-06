import Foundation

struct FoldoverRepairEstimator {
    func predict(features: FoldoverRepairFeatures) -> FoldoverRepairPrediction {
        let cutoffDeficit = normalizedCutoffDeficit(features.cutoffFrequency)
        let harmonic = clipped(features.harmonicConfidence, min: 0, max: 1.2) / 1.2
        let shimmer = clipped(features.shimmerRatio, min: 0, max: 0.55) / 0.55
        let brightness = clipped(features.brightnessRatio, min: 0.18, max: 0.82)
        let transient = clipped(features.transientAmount, min: 0, max: 1.5) / 1.5
        let noise = clipped(features.noiseAmount, min: 0, max: 1.0)
        let rolloff = clipped(features.rolloffDepth, min: 0, max: 1.0)
        let airPresent = clipped(features.airBandEnergyRatio, min: 0, max: 0.45) / 0.45
        let artifact = clipped(features.artifactBandRatio, min: 0, max: 0.35) / 0.35

        // Small fixed-weight MLP-style estimator. This keeps the logic deterministic
        // while making the foldover mix react to multiple analysis features.
        let hidden1 = relu(0.62 * harmonic + 0.74 * cutoffDeficit + 0.45 * rolloff - 0.36 * shimmer - 0.28 * noise - 0.20 * airPresent - 0.38 * artifact + 0.18 * transient - 0.12)
        let hidden2 = relu(0.55 * transient + 0.34 * cutoffDeficit + 0.22 * rolloff - 0.18 * brightness - 0.22 * noise - 0.15 * artifact + 0.08)
        let hidden3 = relu(0.48 * shimmer + 0.41 * noise + 0.36 * artifact + 0.10 * airPresent + 0.24 * brightness - 0.22 * harmonic - 0.16 * rolloff + 0.06)

        let rawFoldover = 0.09 + hidden1 * 0.18 + hidden2 * 0.10 + rolloff * 0.07 - airPresent * 0.04 - artifact * 0.08 - hidden3 * 0.14
        let rawAirBias = 0.03 + hidden1 * 0.16 + rolloff * 0.05 - airPresent * 0.04 - artifact * 0.06 - hidden3 * 0.12 + (0.5 - brightness) * 0.06
        let rawTransientBias = 0.01 + hidden2 * 0.18 + transient * 0.05 - noise * 0.08
        let rawHarshnessGuard = 0.16 + hidden3 * 0.34 + shimmer * 0.22 + noise * 0.24 + artifact * 0.28 - rolloff * 0.08 - harmonic * 0.08

        return FoldoverRepairPrediction(
            foldoverMix: clipped(rawFoldover, min: 0.04, max: 0.32),
            airGainBias: clipped(rawAirBias, min: -0.06, max: 0.16),
            transientBoostBias: clipped(rawTransientBias, min: -0.04, max: 0.12),
            harshnessGuard: clipped(rawHarshnessGuard, min: 0.0, max: 0.72)
        )
    }

    private func normalizedCutoffDeficit(_ cutoffFrequency: Double) -> Float {
        let deficit = max(0, 16_000 - cutoffFrequency)
        return clipped(Float(deficit / 4_000), min: 0, max: 1)
    }

    private func relu(_ value: Float) -> Float {
        max(0, value)
    }

    private func clipped(_ value: Float, min lower: Float, max upper: Float) -> Float {
        Swift.max(lower, Swift.min(upper, value))
    }
}
