import Foundation
import Testing
@testable import VelouraLucent

struct FoldoverRepairEstimatorTests {
    @Test
    func estimatorRaisesFoldoverForHarmonicDeficit() {
        let estimator = FoldoverRepairEstimator()
        let richPrediction = estimator.predict(
            features: FoldoverRepairFeatures(
                harmonicConfidence: 1.0,
                shimmerRatio: 0.10,
                brightnessRatio: 0.34,
                transientAmount: 0.55,
                cutoffFrequency: 12_200,
                noiseAmount: 0.08,
                rolloffDepth: 0.78,
                airBandEnergyRatio: 0.04,
                artifactBandRatio: 0.02
            )
        )
        let weakPrediction = estimator.predict(
            features: FoldoverRepairFeatures(
                harmonicConfidence: 0.18,
                shimmerRatio: 0.34,
                brightnessRatio: 0.58,
                transientAmount: 0.18,
                cutoffFrequency: 15_800,
                noiseAmount: 0.35,
                rolloffDepth: 0.08,
                airBandEnergyRatio: 0.28,
                artifactBandRatio: 0.18
            )
        )

        #expect(richPrediction.foldoverMix > weakPrediction.foldoverMix)
        #expect(richPrediction.harshnessGuard < weakPrediction.harshnessGuard)
    }

    @Test
    func estimatorClampsOutputsToSafeRange() {
        let estimator = FoldoverRepairEstimator()
        let prediction = estimator.predict(
            features: FoldoverRepairFeatures(
                harmonicConfidence: 3.0,
                shimmerRatio: 1.0,
                brightnessRatio: 1.0,
                transientAmount: 3.0,
                cutoffFrequency: 8_000,
                noiseAmount: 1.0,
                rolloffDepth: 2.0,
                airBandEnergyRatio: 1.0,
                artifactBandRatio: 1.0
            )
        )

        #expect((0.04...0.32).contains(prediction.foldoverMix))
        #expect((-0.06...0.16).contains(prediction.airGainBias))
        #expect((-0.04...0.12).contains(prediction.transientBoostBias))
        #expect((0.0...0.72).contains(prediction.harshnessGuard))
    }

    @Test
    func estimatorReducesFoldoverWhenAirAndArtifactsAlreadyExist() {
        let estimator = FoldoverRepairEstimator()
        let cleanDeficit = estimator.predict(
            features: FoldoverRepairFeatures(
                harmonicConfidence: 0.82,
                shimmerRatio: 0.10,
                brightnessRatio: 0.38,
                transientAmount: 0.44,
                cutoffFrequency: 13_200,
                noiseAmount: 0.10,
                rolloffDepth: 0.62,
                airBandEnergyRatio: 0.04,
                artifactBandRatio: 0.02
            )
        )
        let riskyHighBand = estimator.predict(
            features: FoldoverRepairFeatures(
                harmonicConfidence: 0.82,
                shimmerRatio: 0.10,
                brightnessRatio: 0.38,
                transientAmount: 0.44,
                cutoffFrequency: 13_200,
                noiseAmount: 0.10,
                rolloffDepth: 0.62,
                airBandEnergyRatio: 0.32,
                artifactBandRatio: 0.24
            )
        )

        #expect(cleanDeficit.foldoverMix > riskyHighBand.foldoverMix)
        #expect(cleanDeficit.airGainBias > riskyHighBand.airGainBias)
        #expect(cleanDeficit.harshnessGuard < riskyHighBand.harshnessGuard)
    }
}
