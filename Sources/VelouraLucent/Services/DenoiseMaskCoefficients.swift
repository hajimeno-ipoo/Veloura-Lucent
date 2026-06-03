import Foundation

struct DenoiseMaskCoefficients: Sendable {
    let highBandBias: [Float]
    let granularProfileScale: [Float]
    let thresholdScale: [Float]
    let floor: [Float]
    let granularThresholdScale: [Float]

    init(binCount: Int, lowBandFloor: Float, highBandFloor: Float) {
        let denominator = Float(max(binCount - 1, 1))
        var highBandBias: [Float] = []
        var granularProfileScale: [Float] = []
        var thresholdScale: [Float] = []
        var floor: [Float] = []
        var granularThresholdScale: [Float] = []
        highBandBias.reserveCapacity(binCount)
        granularProfileScale.reserveCapacity(binCount)
        thresholdScale.reserveCapacity(binCount)
        floor.reserveCapacity(binCount)
        granularThresholdScale.reserveCapacity(binCount)

        for binIndex in 0..<binCount {
            let normalizedBand = Float(binIndex) / denominator
            highBandBias.append(0.90 + powf(normalizedBand, 1.25) * 0.08)
            granularProfileScale.append(max(0, (normalizedBand - 0.42) / 0.58))
            thresholdScale.append(0.90 + powf(normalizedBand, 1.1) * 0.12)
            floor.append(lowBandFloor + (highBandFloor - lowBandFloor) * powf(normalizedBand, 1.25))
            granularThresholdScale.append(1.1 + normalizedBand * 0.6)
        }

        self.highBandBias = highBandBias
        self.granularProfileScale = granularProfileScale
        self.thresholdScale = thresholdScale
        self.floor = floor
        self.granularThresholdScale = granularThresholdScale
    }

    static func protectedFloor(
        baseFloor: Float,
        frequency: Double,
        magnitude: Float,
        noiseLevel: Float,
        granularActivity: Float,
        granularBaseline: Float,
        coreProtection: Float
    ) -> Float {
        guard coreProtection > 0, frequency <= 5_000 else { return baseFloor }
        guard magnitude > noiseLevel * 1.2 else { return baseFloor }

        let bandWeight: Float
        if frequency <= 1_200 {
            bandWeight = 1
        } else {
            bandWeight = max(0, Float((5_000 - frequency) / 3_800))
        }

        let stabilityRatio = granularActivity / max(magnitude + granularBaseline, 1e-6)
        let stableWeight = max(0, 1 - min(1, stabilityRatio * 2.2))
        let lift = (1 - baseFloor) * coreProtection * bandWeight * stableWeight * 0.22
        return min(0.46, baseFloor + lift)
    }

    static func activeMusicLowBandFloor(
        baseFloor: Float,
        frequency: Double,
        magnitude: Float,
        noiseLevel: Float,
        isActiveMusicFrame: Bool,
        minimumFloor: Float
    ) -> Float {
        guard isActiveMusicFrame, frequency >= 20, frequency < 1_000 else {
            return baseFloor
        }
        guard magnitude > noiseLevel * 1.2 else {
            return baseFloor
        }

        return max(baseFloor, minimumFloor)
    }

    static func decayMusicLowBandFloor(
        baseFloor: Float,
        frequency: Double,
        magnitude: Float,
        noiseLevel: Float,
        isDecayMusicFrame: Bool,
        minimumLowBodyFloor: Float,
        minimumLowMidFloor: Float
    ) -> Float {
        guard isDecayMusicFrame, magnitude > noiseLevel * 1.2 else {
            return baseFloor
        }

        if frequency >= 60, frequency < 150 {
            return max(baseFloor, minimumLowBodyFloor)
        }
        if frequency >= 150, frequency < 250 {
            return max(baseFloor, minimumLowMidFloor)
        }
        return baseFloor
    }
}
