import Foundation

enum LowBandPhaseSafetyOrigin: Sendable, Equatable {
    case input
    case processing
    case inputAndProcessing
}

enum LowBandPhaseSafetyOutcome: Sendable, Equatable {
    case skippedMono
    case skippedUnsupportedLayout
    case skippedNoDestructivePhase
    case repaired(LowBandPhaseSafetyOrigin)
    case rejectedSafety
}

struct LowBandPhaseSafetyResult: Sendable {
    let signal: AudioSignal
    let outcome: LowBandPhaseSafetyOutcome
    let inputMetrics: LowBandPhaseSafetyMetrics?
    let beforeMetrics: LowBandPhaseSafetyMetrics
    let afterMetrics: LowBandPhaseSafetyMetrics

    var affectedTimeFrequencyCells: Int {
        beforeMetrics.affectedTimeFrequencyCells
    }

    var riskBefore: Double {
        beforeMetrics.riskScore
    }

    var riskAfter: Double {
        afterMetrics.riskScore
    }
}

struct LowBandPhaseSafetyMetrics: Sendable, Equatable {
    let riskScore: Double
    let affectedTimeFrequencyCells: Int
    let affectedDurationSeconds: Double
    let monoCompatibilityLossDB: Double?

    static let empty = LowBandPhaseSafetyMetrics(
        riskScore: 0,
        affectedTimeFrequencyCells: 0,
        affectedDurationSeconds: 0,
        monoCompatibilityLossDB: nil
    )
}

/// Repairs only destructive low-band inter-channel phase by building a phase-aligned
/// mono component from the current signal. The ordinary L+R mono sum remains the
/// compatibility reference; the generated mono component is never persisted.
struct LowBandPhaseSafetyGuard: Sendable {
    static let lowerFrequency: Double = 20
    static let upperFrequency: Double = 180
    private static let relativeBinEnergyFloor: Double = 1e-6
    private static let relativeLowBandEnergyFloor: Double = 1e-4
    private static let numericalFloor: Double = 1e-12
    private static let meaningfulRiskFloor: Double = 1e-6
    private static let comparisonTolerance: Double = 1e-6
    private static let energyTolerance: Double = 1.01

    func process(
        signal: AudioSignal,
        reference: AudioSignal
    ) throws -> LowBandPhaseSafetyResult {
        guard signal.channels.count > 1 else {
            return unchanged(signal, outcome: .skippedMono)
        }
        guard signal.channels.count == 2,
              signal.channels[0].count == signal.channels[1].count,
              !signal.channels[0].isEmpty
        else {
            return unchanged(signal, outcome: .skippedUnsupportedLayout)
        }

        let plan = try makePlan(for: signal)
        guard plan.affectedTimeFrequencyCells > 0,
              plan.riskScore > Self.meaningfulRiskFloor
        else {
            return unchanged(
                signal,
                outcome: .skippedNoDestructivePhase,
                beforeMetrics: plan.metrics
            )
        }

        let repaired = render(signal: signal, plan: plan)
        guard repaired.channels.prefix(2).allSatisfy({ $0.allSatisfy(\.isFinite) }) else {
            return unchanged(
                signal,
                outcome: .rejectedSafety,
                beforeMetrics: plan.metrics
            )
        }

        let verifiedPlan = try makePlan(for: repaired)
        let riskImproved = verifiedPlan.riskScore + Self.comparisonTolerance < plan.riskScore
        let monoDidNotRegress = verifiedPlan.passiveMonoEnergy + Self.numericalFloor
            >= plan.passiveMonoEnergy * (1 - Self.comparisonTolerance)
        let stereoEnergyStayedBounded = verifiedPlan.stereoEnergy
            <= plan.stereoEnergy * Self.energyTolerance + Self.numericalFloor
        guard riskImproved, monoDidNotRegress, stereoEnergyStayedBounded else {
            return unchanged(
                signal,
                outcome: .rejectedSafety,
                beforeMetrics: plan.metrics
            )
        }

        let referencePlan = try compatibleReferencePlan(reference, for: signal)
        let origin = repairOrigin(referencePlan: referencePlan, currentPlan: plan)
        return LowBandPhaseSafetyResult(
            signal: repaired,
            outcome: .repaired(origin),
            inputMetrics: referencePlan?.metrics,
            beforeMetrics: plan.metrics,
            afterMetrics: verifiedPlan.metrics
        )
    }

    private func unchanged(
        _ signal: AudioSignal,
        outcome: LowBandPhaseSafetyOutcome,
        inputMetrics: LowBandPhaseSafetyMetrics? = nil,
        beforeMetrics: LowBandPhaseSafetyMetrics = .empty
    ) -> LowBandPhaseSafetyResult {
        LowBandPhaseSafetyResult(
            signal: signal,
            outcome: outcome,
            inputMetrics: inputMetrics,
            beforeMetrics: beforeMetrics,
            afterMetrics: beforeMetrics
        )
    }

    private func compatibleReferencePlan(
        _ reference: AudioSignal,
        for signal: AudioSignal
    ) throws -> LowBandPhasePlan? {
        guard reference.channels.count == 2,
              reference.channels[0].count == reference.channels[1].count,
              reference.channels[0].count == signal.channels[0].count,
              reference.sampleRate == signal.sampleRate
        else {
            return nil
        }
        return try makePlan(for: reference)
    }

    private func repairOrigin(
        referencePlan: LowBandPhasePlan?,
        currentPlan: LowBandPhasePlan
    ) -> LowBandPhaseSafetyOrigin {
        guard let referencePlan,
              referencePlan.amount.count == currentPlan.amount.count
        else {
            return .processing
        }

        var containsInputOrigin = false
        var containsProcessingOrigin = false
        for index in currentPlan.amount.indices
        where currentPlan.amount[index] > Float(Self.comparisonTolerance) {
            let referenceAmount = referencePlan.amount[index]
            if referenceAmount > Float(Self.comparisonTolerance) {
                containsInputOrigin = true
            }
            if currentPlan.amount[index]
                > referenceAmount + Float(Self.comparisonTolerance)
            {
                containsProcessingOrigin = true
            }
            if containsInputOrigin, containsProcessingOrigin {
                return .inputAndProcessing
            }
        }

        if containsInputOrigin {
            return .input
        }
        if containsProcessingOrigin {
            return .processing
        }
        return .processing
    }

    private func makePlan(for signal: AudioSignal) throws -> LowBandPhasePlan {
        let fftSize = SpectralDSP.fftSize
        let hopSize = SpectralDSP.hopSize
        let binCount = fftSize / 2 + 1
        let frequencyStep = signal.sampleRate / Double(fftSize)
        let lowerBin = max(1, Int(ceil(Self.lowerFrequency / frequencyStep)))
        let upperBin = min(binCount - 1, Int(floor(Self.upperFrequency / frequencyStep)))
        guard lowerBin <= upperBin else {
            return .empty
        }

        let activeBins = Array(lowerBin...upperBin)
        var leftReal: [Float] = []
        var leftImag: [Float] = []
        var leftFrameEnergy: [Double] = []
        var leftFrameCount = 0
        try SpectralDSP.forEachSTFTFrameThrowing(
            signal.channels[0],
            fftSize: fftSize,
            hopSize: hopSize
        ) { frameIndex, _, real, imag in
            if frameIndex.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            for bin in activeBins {
                leftReal.append(real[bin])
                leftImag.append(imag[bin])
            }
            leftFrameEnergy.append(
                (0..<binCount).reduce(0.0) { partial, bin in
                    partial + squaredMagnitude(real: real[bin], imag: imag[bin])
                }
            )
            leftFrameCount += 1
        }

        var safeReal: [Float] = []
        var safeImag: [Float] = []
        var amount: [Float] = []
        safeReal.reserveCapacity(leftReal.count)
        safeImag.reserveCapacity(leftImag.count)
        amount.reserveCapacity(leftReal.count)

        var rightFrameCount = 0
        var affectedTimeFrequencyCells = 0
        var affectedFrameCount = 0
        var weightedRisk = 0.0
        var meaningfulEnergy = 0.0
        var stereoEnergy = 0.0
        var passiveMonoEnergy = 0.0
        var displayPassiveMonoEnergy = 0.0
        var displayAlignedMonoEnergy = 0.0

        try SpectralDSP.forEachSTFTFrameThrowing(
            signal.channels[1],
            fftSize: fftSize,
            hopSize: hopSize
        ) { frameIndex, _, rightReal, rightImag in
            if frameIndex.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            guard frameIndex < leftFrameCount else { return }
            let frameOffset = frameIndex * activeBins.count
            let rightFrameEnergy = (0..<binCount).reduce(0.0) { partial, bin in
                partial + squaredMagnitude(real: rightReal[bin], imag: rightImag[bin])
            }
            let lowBandEnergy = activeBins.indices.reduce(0.0) { partial, localIndex in
                let bin = activeBins[localIndex]
                let leftIndex = frameOffset + localIndex
                return partial
                    + squaredMagnitude(real: leftReal[leftIndex], imag: leftImag[leftIndex])
                    + squaredMagnitude(real: rightReal[bin], imag: rightImag[bin])
            }
            let frameEnergy = leftFrameEnergy[frameIndex] + rightFrameEnergy
            let lowBandIsMeaningful = lowBandEnergy
                > frameEnergy * Self.relativeLowBandEnergyFloor
            let frameCenter = frameIndex * hopSize
            let frameIsFullyObserved = frameCenter >= fftSize / 2
                && frameCenter + fftSize / 2 < signal.channels[0].count
            let activeEnergyFloor = max(
                Self.numericalFloor,
                frameEnergy * Self.relativeBinEnergyFloor
            )
            var frameHasAffectedCell = false

            for localIndex in activeBins.indices {
                let bin = activeBins[localIndex]
                let leftIndex = frameOffset + localIndex
                let leftRealValue = Double(leftReal[leftIndex])
                let leftImagValue = Double(leftImag[leftIndex])
                let rightRealValue = Double(rightReal[bin])
                let rightImagValue = Double(rightImag[bin])
                let leftPower = leftRealValue * leftRealValue + leftImagValue * leftImagValue
                let rightPower = rightRealValue * rightRealValue + rightImagValue * rightImagValue
                let combinedEnergy = leftPower + rightPower
                let crossReal = leftRealValue * rightRealValue + leftImagValue * rightImagValue
                let passiveReal = (leftRealValue + rightRealValue) * 0.5
                let passiveImag = (leftImagValue + rightImagValue) * 0.5
                let passivePower = passiveReal * passiveReal + passiveImag * passiveImag

                stereoEnergy += combinedEnergy
                passiveMonoEnergy += passivePower

                let leftMagnitude = sqrt(leftPower)
                let rightMagnitude = sqrt(rightPower)
                let safeMagnitude = (leftMagnitude + rightMagnitude) * 0.5
                let unitReal: Double
                let unitImag: Double
                if leftMagnitude > Self.numericalFloor {
                    unitReal = leftRealValue / leftMagnitude
                    unitImag = leftImagValue / leftMagnitude
                } else if rightMagnitude > Self.numericalFloor {
                    unitReal = -rightRealValue / rightMagnitude
                    unitImag = -rightImagValue / rightMagnitude
                } else {
                    unitReal = 1
                    unitImag = 0
                }
                let alignedReal = unitReal * safeMagnitude
                let alignedImag = unitImag * safeMagnitude
                safeReal.append(Float(alignedReal))
                safeImag.append(Float(alignedImag))

                guard frameIsFullyObserved,
                      lowBandIsMeaningful,
                      combinedEnergy > activeEnergyFloor
                else {
                    amount.append(0)
                    continue
                }

                displayPassiveMonoEnergy += passivePower
                displayAlignedMonoEnergy += safeMagnitude * safeMagnitude
                let severity = min(
                    1,
                    max(0, -2 * crossReal / max(combinedEnergy, Self.numericalFloor))
                )
                meaningfulEnergy += combinedEnergy
                weightedRisk += severity * combinedEnergy
                guard severity > Self.comparisonTolerance else {
                    amount.append(0)
                    continue
                }

                let mixedLeftReal = leftRealValue + severity * (alignedReal - leftRealValue)
                let mixedLeftImag = leftImagValue + severity * (alignedImag - leftImagValue)
                let mixedRightReal = rightRealValue + severity * (alignedReal - rightRealValue)
                let mixedRightImag = rightImagValue + severity * (alignedImag - rightImagValue)
                let mixedMonoReal = (mixedLeftReal + mixedRightReal) * 0.5
                let mixedMonoImag = (mixedLeftImag + mixedRightImag) * 0.5
                let mixedMonoPower = mixedMonoReal * mixedMonoReal + mixedMonoImag * mixedMonoImag
                let mixedStereoEnergy = mixedLeftReal * mixedLeftReal
                    + mixedLeftImag * mixedLeftImag
                    + mixedRightReal * mixedRightReal
                    + mixedRightImag * mixedRightImag
                guard mixedMonoPower + Self.numericalFloor >= passivePower,
                      mixedStereoEnergy <= combinedEnergy * Self.energyTolerance + Self.numericalFloor
                else {
                    amount.append(0)
                    continue
                }

                amount.append(Float(severity))
                affectedTimeFrequencyCells += 1
                frameHasAffectedCell = true
            }
            if frameHasAffectedCell {
                affectedFrameCount += 1
            }
            rightFrameCount += 1
        }

        guard rightFrameCount == leftFrameCount,
              safeReal.count == leftReal.count,
              safeImag.count == leftImag.count,
              amount.count == leftReal.count
        else {
            return .empty
        }

        return LowBandPhasePlan(
            activeBins: activeBins,
            frameCount: leftFrameCount,
            safeReal: safeReal,
            safeImag: safeImag,
            amount: amount,
            affectedTimeFrequencyCells: affectedTimeFrequencyCells,
            affectedDurationSeconds: Double(affectedFrameCount * hopSize) / signal.sampleRate,
            riskScore: weightedRisk / max(meaningfulEnergy, Self.numericalFloor),
            monoCompatibilityLossDB: monoCompatibilityLossDB(
                passiveEnergy: displayPassiveMonoEnergy,
                alignedEnergy: displayAlignedMonoEnergy
            ),
            stereoEnergy: stereoEnergy,
            passiveMonoEnergy: passiveMonoEnergy
        )
    }

    private func render(signal: AudioSignal, plan: LowBandPhasePlan) -> AudioSignal {
        guard plan.frameCount > 0, !plan.activeBins.isEmpty else { return signal }
        var channels = signal.channels
        for channelIndex in 0..<2 {
            let delta = SpectralDSP.istftSparseHalfSpectrumFromSTFTFrames(
                signal.channels[channelIndex],
                activeBins: plan.activeBins
            ) { frameIndex, _, sourceReal, sourceImag, real, imag in
                guard frameIndex < plan.frameCount else { return }
                let frameOffset = frameIndex * plan.activeBins.count
                for localIndex in plan.activeBins.indices {
                    let bin = plan.activeBins[localIndex]
                    let planIndex = frameOffset + localIndex
                    let mix = plan.amount[planIndex]
                    guard mix > 0 else { continue }
                    real[bin] = mix * (plan.safeReal[planIndex] - sourceReal[bin])
                    imag[bin] = mix * (plan.safeImag[planIndex] - sourceImag[bin])
                }
            }
            channels[channelIndex] = zip(signal.channels[channelIndex], delta).map(+)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func squaredMagnitude(real: Float, imag: Float) -> Double {
        let realValue = Double(real)
        let imagValue = Double(imag)
        return realValue * realValue + imagValue * imagValue
    }

    private func monoCompatibilityLossDB(
        passiveEnergy: Double,
        alignedEnergy: Double
    ) -> Double? {
        guard alignedEnergy > Self.numericalFloor else { return nil }
        let ratio = max(passiveEnergy, alignedEnergy * 1e-12) / alignedEnergy
        return min(0, 10 * log10(ratio))
    }
}

private struct LowBandPhasePlan {
    let activeBins: [Int]
    let frameCount: Int
    let safeReal: [Float]
    let safeImag: [Float]
    let amount: [Float]
    let affectedTimeFrequencyCells: Int
    let affectedDurationSeconds: Double
    let riskScore: Double
    let monoCompatibilityLossDB: Double?
    let stereoEnergy: Double
    let passiveMonoEnergy: Double

    var metrics: LowBandPhaseSafetyMetrics {
        LowBandPhaseSafetyMetrics(
            riskScore: riskScore,
            affectedTimeFrequencyCells: affectedTimeFrequencyCells,
            affectedDurationSeconds: affectedDurationSeconds,
            monoCompatibilityLossDB: monoCompatibilityLossDB
        )
    }

    static let empty = LowBandPhasePlan(
        activeBins: [],
        frameCount: 0,
        safeReal: [],
        safeImag: [],
        amount: [],
        affectedTimeFrequencyCells: 0,
        affectedDurationSeconds: 0,
        riskScore: 0,
        monoCompatibilityLossDB: nil,
        stereoEnergy: 0,
        passiveMonoEnergy: 0
    )
}
