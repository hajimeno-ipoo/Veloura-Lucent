import Accelerate
import Foundation

/// Guitar／Piano専用の活動判定と役割解析です。
///
/// Other用の空間・残響解析は呼び出しません。実Stemと劣化模擬で採用した
/// 4096 sample／1024 hop、左右別spectral power、complex-domain onset、
/// 調波・非調波性、onset基準の帯域別余韻、stereo量を製品信号へ直接適用します。
struct StemDedicatedInstrumentAnalysisService: Sendable {
    private static let frameSize = 4_096
    private static let hopSize = 1_024
    private static let activityFloorDecibelsFullScale = -70.0
    private static let numericalFloor = 1e-12

    func analyze(
        role: StemRole,
        processingSignal48000 signal: AudioSignal
    ) throws -> StemRoleAnalysisResult {
        precondition(role == .guitar || role == .piano)
        let frames = try Self.makeFrames(signal: signal)
        let activity = Self.makeActivity(frames: frames)
        let analyzed = Self.makeRoleFrames(frames: frames, activity: activity, sampleRate: signal.sampleRate)
        let onsets = Self.selectOnsets(
            values: analyzed.map(\.onsetEnergy),
            active: activity.mask,
            sampleRate: signal.sampleRate
        )
        let tails = Self.makeTailMeasurements(
            frames: analyzed,
            onsets: onsets,
            sampleRate: signal.sampleRate
        )
        let stereo = Self.wholeSignalStereo(signal)
        let metrics = Self.makeMetrics(
            frames: analyzed,
            activity: activity,
            tails: tails,
            stereo: stereo,
            onsetCount: onsets.count
        )
        let features = Self.makeFeatures(
            role: role,
            frames: analyzed,
            activity: activity,
            tails: tails,
            stereo: stereo
        )
        let protectionProfile = Self.makeProtectionProfile(
            role: role,
            signal: signal,
            frames: analyzed,
            activity: activity
        )

        return StemRoleAnalysisResult(
            snapshot: StemRoleAnalysisSnapshot(
                role: role,
                authoritativeSampleRate: signal.sampleRate,
                analysisSampleRate: signal.sampleRate,
                authoritativeFrameCount: signal.frameCount,
                analysisFrameCount: signal.frameCount,
                features: features,
                activity: StemRoleActivitySummary(
                    floorDecibelsFullScale: Self.activityFloorDecibelsFullScale,
                    thresholdDecibelsFullScale: activity.threshold,
                    totalFrameCount: frames.count,
                    activeFrameCount: activity.mask.filter { $0 }.count
                ),
                dedicatedMetrics: metrics
            ),
            protectionProfile: protectionProfile
        )
    }
}

private extension StemDedicatedInstrumentAnalysisService {
    struct SpectrumState {
        let leftReal: [Double]
        let leftImaginary: [Double]
        let rightReal: [Double]
        let rightImaginary: [Double]

        var magnitudeSum: Double {
            leftReal.indices.reduce(0) { partial, index in
                partial
                    + hypot(leftReal[index], leftImaginary[index])
                    + hypot(rightReal[index], rightImaginary[index])
            }
        }
    }

    struct RawFrame {
        let startFrame: Int
        let validFrameCount: Int
        let rms: Double
        let rmsDecibelsFullScale: Double
        let crestDecibels: Double
        let power: [Double]
        let complexOnsetStrength: Double
        let stereoSideRatio: Double
        let stereoCorrelation: Double
    }

    struct RoleFrame {
        let startFrame: Int
        let validFrameCount: Int
        let rms: Double
        let crestDecibels: Double
        let onsetEnergy: Double
        let harmonicEnergyRatio: Double
        let inharmonicity: Double
        let spectralCentroidHertz: Double
        let rolloff85Hertz: Double
        let highBandRatio: Double
        let lowBandRatio: Double
        let midBandRatio: Double
        let lowBandPower: Double
        let midBandPower: Double
        let highBandPower: Double
        let stereoSideRatio: Double
        let stereoCorrelation: Double
        var localDoubleDecaySlopeDelta: Double = 0
    }

    struct Activity {
        let mask: [Bool]
        let threshold: Double
    }

    struct TailMeasurements {
        let rmsDecibels: [Double]
        let lowDecibels: [Double]
        let midDecibels: [Double]
        let highDecibels: [Double]
        let doubleDecaySlopeDelta: [Double]
    }

    struct StereoMeasurement {
        let sideRatio: Double
        let correlation: Double
    }

    struct FeatureDefinition {
        let feature: StemRoleAnalysisFeature
        let rule: StemRoleFeaturePreservationRule
        let unit: StemRoleAnalysisUnit
        let values: [Double]
    }

    static func makeFrames(signal: AudioSignal) throws -> [RawFrame] {
        guard let dft = try? vDSP.DiscreteFourierTransform<Float>(
            count: frameSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        ) else {
            throw StemRoleAnalysisError.unableToCreateFourierTransform
        }
        let window = vDSP.window(
            ofType: Float.self,
            usingSequence: .hanningDenormalized,
            count: frameSize,
            isHalfWindow: false
        )
        let left = signal.channels[0]
        let right = signal.channels[1]
        var result: [RawFrame] = []
        var previous: SpectrumState?
        var previousPrevious: SpectrumState?

        for start in frameStarts(frameCount: signal.frameCount) {
            let valid = min(frameSize, signal.frameCount - start)
            let leftFrame = paddedFrame(channel: left, start: start)
            let rightFrame = paddedFrame(channel: right, start: start)
            let spectrum = makeSpectrum(left: leftFrame, right: rightFrame, window: window, dft: dft)
            let power = spectrum.leftReal.indices.map { index in
                let leftPower = spectrum.leftReal[index] * spectrum.leftReal[index]
                    + spectrum.leftImaginary[index] * spectrum.leftImaginary[index]
                let rightPower = spectrum.rightReal[index] * spectrum.rightReal[index]
                    + spectrum.rightImaginary[index] * spectrum.rightImaginary[index]
                return (leftPower + rightPower) * 0.5
            }
            let onset = complexOnset(
                current: spectrum,
                previous: previous,
                previousPrevious: previousPrevious
            )
            let time = timeDomainMeasurements(left: leftFrame, right: rightFrame)
            result.append(RawFrame(
                startFrame: start,
                validFrameCount: valid,
                rms: time.rms,
                rmsDecibelsFullScale: decibels(time.rms),
                crestDecibels: time.crestDecibels,
                power: power,
                complexOnsetStrength: onset,
                stereoSideRatio: time.stereoSideRatio,
                stereoCorrelation: time.stereoCorrelation
            ))
            previousPrevious = previous
            previous = spectrum
        }
        return result
    }

    static func makeSpectrum(
        left: [Float],
        right: [Float],
        window: [Float],
        dft: vDSP.DiscreteFourierTransform<Float>
    ) -> SpectrumState {
        var leftWindowed = Array(repeating: Float.zero, count: frameSize)
        var rightWindowed = Array(repeating: Float.zero, count: frameSize)
        vDSP.multiply(left, window, result: &leftWindowed)
        vDSP.multiply(right, window, result: &rightWindowed)
        let zero = Array(repeating: Float.zero, count: frameSize)
        var leftReal = zero
        var leftImaginary = zero
        var rightReal = zero
        var rightImaginary = zero
        dft.transform(inputReal: leftWindowed, inputImaginary: zero, outputReal: &leftReal, outputImaginary: &leftImaginary)
        dft.transform(inputReal: rightWindowed, inputImaginary: zero, outputReal: &rightReal, outputImaginary: &rightImaginary)
        let halfCount = frameSize / 2 + 1
        return SpectrumState(
            leftReal: leftReal.prefix(halfCount).map(Double.init),
            leftImaginary: leftImaginary.prefix(halfCount).map(Double.init),
            rightReal: rightReal.prefix(halfCount).map(Double.init),
            rightImaginary: rightImaginary.prefix(halfCount).map(Double.init)
        )
    }

    static func complexOnset(
        current: SpectrumState,
        previous: SpectrumState?,
        previousPrevious: SpectrumState?
    ) -> Double {
        guard let previous, let previousPrevious else { return 0 }
        var difference = 0.0
        for index in current.leftReal.indices {
            difference += predictedComplexDifference(
                currentReal: current.leftReal[index],
                currentImaginary: current.leftImaginary[index],
                previousReal: previous.leftReal[index],
                previousImaginary: previous.leftImaginary[index],
                previousPreviousReal: previousPrevious.leftReal[index],
                previousPreviousImaginary: previousPrevious.leftImaginary[index]
            )
            difference += predictedComplexDifference(
                currentReal: current.rightReal[index],
                currentImaginary: current.rightImaginary[index],
                previousReal: previous.rightReal[index],
                previousImaginary: previous.rightImaginary[index],
                previousPreviousReal: previousPrevious.rightReal[index],
                previousPreviousImaginary: previousPrevious.rightImaginary[index]
            )
        }
        return difference / max(current.magnitudeSum + previous.magnitudeSum, numericalFloor)
    }

    static func predictedComplexDifference(
        currentReal: Double,
        currentImaginary: Double,
        previousReal: Double,
        previousImaginary: Double,
        previousPreviousReal: Double,
        previousPreviousImaginary: Double
    ) -> Double {
        let magnitude = hypot(previousReal, previousImaginary)
        let predictedPhase = 2 * atan2(previousImaginary, previousReal)
            - atan2(previousPreviousImaginary, previousPreviousReal)
        return hypot(
            currentReal - magnitude * cos(predictedPhase),
            currentImaginary - magnitude * sin(predictedPhase)
        )
    }

    static func timeDomainMeasurements(left: [Float], right: [Float]) -> (
        rms: Double,
        crestDecibels: Double,
        stereoSideRatio: Double,
        stereoCorrelation: Double
    ) {
        var sumSquares = 0.0
        var peak = 0.0
        var midEnergy = 0.0
        var sideEnergy = 0.0
        var leftMean = 0.0
        var rightMean = 0.0
        for index in left.indices {
            let lhs = Double(left[index])
            let rhs = Double(right[index])
            sumSquares += lhs * lhs + rhs * rhs
            peak = max(peak, abs(lhs), abs(rhs))
            let mid = (lhs + rhs) * 0.5
            let side = (lhs - rhs) * 0.5
            midEnergy += mid * mid
            sideEnergy += side * side
            leftMean += lhs
            rightMean += rhs
        }
        let count = Double(max(left.count, 1))
        leftMean /= count
        rightMean /= count
        var covariance = 0.0
        var leftVariance = 0.0
        var rightVariance = 0.0
        for index in left.indices {
            let lhs = Double(left[index]) - leftMean
            let rhs = Double(right[index]) - rightMean
            covariance += lhs * rhs
            leftVariance += lhs * lhs
            rightVariance += rhs * rhs
        }
        let rms = sqrt(sumSquares / (2 * count) + numericalFloor)
        let correlation = leftVariance > numericalFloor && rightVariance > numericalFloor
            ? max(-1, min(1, covariance / sqrt(leftVariance * rightVariance)))
            : 1
        return (
            rms,
            decibels(peak / max(rms, numericalFloor)),
            sideEnergy / max(midEnergy + sideEnergy, numericalFloor),
            correlation
        )
    }

    static func makeActivity(frames: [RawFrame]) -> Activity {
        let levels = frames.map(\.rmsDecibelsFullScale).filter(\.isFinite)
        guard let maximum = levels.max(), maximum >= -100 else {
            return Activity(mask: Array(repeating: false, count: frames.count), threshold: activityFloorDecibelsFullScale)
        }
        let threshold = max(activityFloorDecibelsFullScale, percentile(levels, probability: 0.95) - 36)
        return Activity(mask: frames.map { $0.rmsDecibelsFullScale >= threshold }, threshold: threshold)
    }

    static func makeRoleFrames(
        frames: [RawFrame],
        activity: Activity,
        sampleRate: Double
    ) -> [RoleFrame] {
        let frequencyStep = sampleRate / Double(frameSize)
        var result = frames.enumerated().map { index, frame -> RoleFrame in
            guard activity.mask[index] else {
                return RoleFrame(
                    startFrame: frame.startFrame,
                    validFrameCount: frame.validFrameCount,
                    rms: frame.rms,
                    crestDecibels: frame.crestDecibels,
                    onsetEnergy: frame.complexOnsetStrength * frame.rms,
                    harmonicEnergyRatio: 0,
                    inharmonicity: 0,
                    spectralCentroidHertz: 0,
                    rolloff85Hertz: 0,
                    highBandRatio: 0,
                    lowBandRatio: 0,
                    midBandRatio: 0,
                    lowBandPower: bandPower(frame.power, lowerHz: 80, upperHz: 500, frequencyStep: frequencyStep),
                    midBandPower: bandPower(frame.power, lowerHz: 500, upperHz: 4_000, frequencyStep: frequencyStep),
                    highBandPower: bandPower(frame.power, lowerHz: 4_000, upperHz: 12_000, frequencyStep: frequencyStep),
                    stereoSideRatio: frame.stereoSideRatio,
                    stereoCorrelation: frame.stereoCorrelation
                )
            }
            let harmonic = harmonicMetrics(power: frame.power, frequencyStep: frequencyStep)
            let audibleRange = binRange(lowerHz: 20, upperHz: min(20_000, sampleRate * 0.5), frequencyStep: frequencyStep, binCount: frame.power.count)
            let audibleTotal = max(frame.power[audibleRange].reduce(0, +), numericalFloor)
            let centroid = audibleRange.reduce(0.0) { partial, bin in
                partial + Double(bin) * frequencyStep * frame.power[bin]
            } / audibleTotal
            let rolloff = rolloff85(power: frame.power, range: audibleRange, frequencyStep: frequencyStep)
            let highDetail = bandPower(frame.power, lowerHz: 6_000, upperHz: 18_000, frequencyStep: frequencyStep) / audibleTotal
            let low = bandPower(frame.power, lowerHz: 80, upperHz: 500, frequencyStep: frequencyStep)
            let mid = bandPower(frame.power, lowerHz: 500, upperHz: 4_000, frequencyStep: frequencyStep)
            let high = bandPower(frame.power, lowerHz: 4_000, upperHz: 12_000, frequencyStep: frequencyStep)
            return RoleFrame(
                startFrame: frame.startFrame,
                validFrameCount: frame.validFrameCount,
                rms: frame.rms,
                crestDecibels: frame.crestDecibels,
                onsetEnergy: frame.complexOnsetStrength * frame.rms,
                harmonicEnergyRatio: harmonic.ratio,
                inharmonicity: harmonic.inharmonicity,
                spectralCentroidHertz: centroid,
                rolloff85Hertz: rolloff,
                highBandRatio: highDetail,
                lowBandRatio: low / audibleTotal,
                midBandRatio: mid / audibleTotal,
                lowBandPower: low,
                midBandPower: mid,
                highBandPower: high,
                stereoSideRatio: frame.stereoSideRatio,
                stereoCorrelation: frame.stereoCorrelation
            )
        }

        for index in result.indices where activity.mask[index] {
            result[index].localDoubleDecaySlopeDelta = localDoubleDecaySlopeDelta(
                rms: frames.map(\.rms),
                start: index,
                sampleRate: sampleRate
            )
        }
        return result
    }

    static func harmonicMetrics(power: [Double], frequencyStep: Double) -> (ratio: Double, inharmonicity: Double) {
        let fullRange = binRange(lowerHz: 50, upperHz: 12_000, frequencyStep: frequencyStep, binCount: power.count)
        let total = power[fullRange].reduce(0, +)
        guard total > numericalFloor else { return (0, 0) }
        let fundamental = estimateFundamental(power: power, frequencyStep: frequencyStep)
        guard fundamental > 0 else { return (0, 0) }
        var harmonicEnergy = 0.0
        var harmonic = 1
        while Double(harmonic) * fundamental <= 12_000 {
            let center = Int(round(Double(harmonic) * fundamental / frequencyStep))
            harmonicEnergy += power[max(1, center - 1)...min(power.count - 1, center + 1)].reduce(0, +)
            harmonic += 1
        }
        let regionMaximum = fullRange.map { power[$0] }.max() ?? 0
        var weightedDeviation = 0.0
        var weight = 0.0
        if fullRange.count >= 3 {
            for bin in (fullRange.lowerBound + 1)..<(fullRange.upperBound - 1) {
                guard power[bin] > power[bin - 1],
                      power[bin] >= power[bin + 1],
                      power[bin] >= regionMaximum * 0.01 else { continue }
                let frequency = Double(bin) * frequencyStep
                let nearest = max(1, round(frequency / fundamental)) * fundamental
                weightedDeviation += abs(frequency - nearest) / nearest * power[bin]
                weight += power[bin]
            }
        }
        return (min(1, harmonicEnergy / total), weight > numericalFloor ? weightedDeviation / weight : 0)
    }

    static func estimateFundamental(power: [Double], frequencyStep: Double) -> Double {
        let lower = max(1, Int(ceil(50 / frequencyStep)))
        let upper = min(power.count - 1, Int(floor(1_200 / frequencyStep)))
        var bestBin = 0
        var bestScore = 0.0
        guard lower <= upper else { return 0 }
        for candidate in lower...upper {
            var score = 0.0
            var harmonic = 1
            while candidate * harmonic < power.count,
                  Double(candidate * harmonic) * frequencyStep <= 12_000 {
                let center = candidate * harmonic
                score += power[max(1, center - 1)...min(power.count - 1, center + 1)].reduce(0, +)
                    / sqrt(Double(harmonic))
                harmonic += 1
            }
            if score > bestScore {
                bestScore = score
                bestBin = candidate
            }
        }
        return bestScore > numericalFloor ? Double(bestBin) * frequencyStep : 0
    }

    static func selectOnsets(values: [Double], active: [Bool], sampleRate: Double) -> [Int] {
        let activeValues = values.indices.filter { active[$0] }.map { values[$0] }
        guard activeValues.count >= 3, (activeValues.max() ?? 0) > numericalFloor else { return [] }
        let threshold = percentile(activeValues, probability: 0.8)
        let minimumDistance = max(1, Int(round(0.15 * sampleRate / Double(hopSize))))
        var selected: [Int] = []
        for index in values.indices where active[index] && values[index] >= threshold {
            let previous = values[max(0, index - 1)]
            let next = values[min(values.count - 1, index + 1)]
            guard values[index] >= previous, values[index] >= next else { continue }
            if let last = selected.last, index - last < minimumDistance {
                if values[index] > values[last] { selected[selected.count - 1] = index }
            } else {
                selected.append(index)
            }
        }
        return selected
    }

    static func makeTailMeasurements(
        frames: [RoleFrame],
        onsets: [Int],
        sampleRate: Double
    ) -> TailMeasurements {
        let tailStart = max(1, Int(round(0.25 * sampleRate / Double(hopSize))))
        let tailEnd = max(tailStart + 1, Int(round(0.80 * sampleRate / Double(hopSize))))
        let lateStart = max(tailStart + 1, Int(round(0.40 * sampleRate / Double(hopSize))))
        let lateEnd = max(lateStart + 2, Int(round(1.00 * sampleRate / Double(hopSize))))
        var rms: [Double] = []
        var low: [Double] = []
        var mid: [Double] = []
        var high: [Double] = []
        var doubleDecay: [Double] = []
        let rmsValues = frames.map(\.rms)
        let lowValues = frames.map(\.lowBandPower)
        let midValues = frames.map(\.midBandPower)
        let highValues = frames.map(\.highBandPower)
        for onset in onsets where onset + tailEnd < frames.count {
            rms.append(tailRatio(values: rmsValues, onset: onset, tailStart: tailStart, tailEnd: tailEnd, isPower: false))
            low.append(tailRatio(values: lowValues, onset: onset, tailStart: tailStart, tailEnd: tailEnd, isPower: true))
            mid.append(tailRatio(values: midValues, onset: onset, tailStart: tailStart, tailEnd: tailEnd, isPower: true))
            high.append(tailRatio(values: highValues, onset: onset, tailStart: tailStart, tailEnd: tailEnd, isPower: true))
            if onset + lateEnd < frames.count {
                let early = Array(rmsValues[onset..<(onset + lateStart)]).map(decibels)
                let late = Array(rmsValues[(onset + lateStart)..<(onset + lateEnd)]).map(decibels)
                if early.count >= 3, late.count >= 3 {
                    let seconds = Double(hopSize) / sampleRate
                    doubleDecay.append(linearSlope(late, step: seconds) - linearSlope(early, step: seconds))
                }
            }
        }
        return TailMeasurements(
            rmsDecibels: rms,
            lowDecibels: low,
            midDecibels: mid,
            highDecibels: high,
            doubleDecaySlopeDelta: doubleDecay
        )
    }

    static func tailRatio(values: [Double], onset: Int, tailStart: Int, tailEnd: Int, isPower: Bool) -> Double {
        let reference = max(values[onset..<min(values.count, onset + 2)].max() ?? 0, numericalFloor)
        let tail = percentile(Array(values[(onset + tailStart)..<(onset + tailEnd)]), probability: 0.5)
        let ratio = isPower ? sqrt(max(tail, numericalFloor) / reference) : tail / reference
        return decibels(ratio)
    }

    static func localDoubleDecaySlopeDelta(rms: [Double], start: Int, sampleRate: Double) -> Double {
        let lateStart = max(2, Int(round(0.40 * sampleRate / Double(hopSize))))
        let lateEnd = max(lateStart + 3, Int(round(1.00 * sampleRate / Double(hopSize))))
        guard start + lateEnd < rms.count else { return 0 }
        let early = Array(rms[start..<(start + lateStart)]).map(decibels)
        let late = Array(rms[(start + lateStart)..<(start + lateEnd)]).map(decibels)
        let seconds = Double(hopSize) / sampleRate
        return linearSlope(late, step: seconds) - linearSlope(early, step: seconds)
    }

    static func wholeSignalStereo(_ signal: AudioSignal) -> StereoMeasurement {
        let measurement = timeDomainMeasurements(left: signal.channels[0], right: signal.channels[1])
        return StereoMeasurement(sideRatio: measurement.stereoSideRatio, correlation: measurement.stereoCorrelation)
    }

    static func makeMetrics(
        frames: [RoleFrame],
        activity: Activity,
        tails: TailMeasurements,
        stereo: StereoMeasurement,
        onsetCount: Int
    ) -> StemDedicatedRoleMetrics {
        let active = frames.indices.filter { activity.mask[$0] }.map { frames[$0] }
        guard !active.isEmpty else {
            return StemDedicatedRoleMetrics(
                onsetEnergy90thPercentile: 0,
                attackCrest90thPercentileDecibels: 0,
                harmonicEnergyRatioMedian: 0,
                inharmonicityMedian: 0,
                spectralCentroidMedianHertz: 0,
                rolloff85MedianHertz: 0,
                highBandRatioMedian: 0,
                highBandRatio90thPercentile: 0,
                lowBandRatioMedian: 0,
                midBandRatioMedian: 0,
                tailRMSRatioMedianDecibels: -240,
                tailLowRatioMedianDecibels: -240,
                tailMidRatioMedianDecibels: -240,
                tailHighRatioMedianDecibels: -240,
                doubleDecaySlopeDeltaMedianDecibelsPerSecond: 0,
                stereoSideRatio: 0,
                stereoCorrelation: 1,
                detectedOnsetCount: 0
            )
        }
        return StemDedicatedRoleMetrics(
            onsetEnergy90thPercentile: percentile(active.map(\.onsetEnergy), probability: 0.9),
            attackCrest90thPercentileDecibels: percentile(active.map(\.crestDecibels), probability: 0.9),
            harmonicEnergyRatioMedian: percentile(active.map(\.harmonicEnergyRatio), probability: 0.5),
            inharmonicityMedian: percentile(active.map(\.inharmonicity), probability: 0.5),
            spectralCentroidMedianHertz: percentile(active.map(\.spectralCentroidHertz), probability: 0.5),
            rolloff85MedianHertz: percentile(active.map(\.rolloff85Hertz), probability: 0.5),
            highBandRatioMedian: percentile(active.map(\.highBandRatio), probability: 0.5),
            highBandRatio90thPercentile: percentile(active.map(\.highBandRatio), probability: 0.9),
            lowBandRatioMedian: percentile(active.map(\.lowBandRatio), probability: 0.5),
            midBandRatioMedian: percentile(active.map(\.midBandRatio), probability: 0.5),
            tailRMSRatioMedianDecibels: medianOrDefault(tails.rmsDecibels, default: -240),
            tailLowRatioMedianDecibels: medianOrDefault(tails.lowDecibels, default: -240),
            tailMidRatioMedianDecibels: medianOrDefault(tails.midDecibels, default: -240),
            tailHighRatioMedianDecibels: medianOrDefault(tails.highDecibels, default: -240),
            doubleDecaySlopeDeltaMedianDecibelsPerSecond: medianOrDefault(tails.doubleDecaySlopeDelta, default: 0),
            stereoSideRatio: stereo.sideRatio,
            stereoCorrelation: stereo.correlation,
            detectedOnsetCount: onsetCount
        )
    }

    static func makeFeatures(
        role: StemRole,
        frames: [RoleFrame],
        activity: Activity,
        tails: TailMeasurements,
        stereo: StereoMeasurement
    ) -> [StemRoleFeatureDistribution] {
        let active = frames.indices.filter { activity.mask[$0] }.map { frames[$0] }
        let activeValues: ([RoleFrame]) -> [RoleFrame] = { $0.isEmpty ? [RoleFrame.neutral] : $0 }
        let values = activeValues(active)
        let tailLow = tails.lowDecibels.isEmpty ? [-240] : tails.lowDecibels
        let tailMid = tails.midDecibels.isEmpty ? [-240] : tails.midDecibels
        let tailHigh = tails.highDecibels.isEmpty ? [-240] : tails.highDecibels
        let doubleDecay = tails.doubleDecaySlopeDelta.isEmpty ? [0] : tails.doubleDecaySlopeDelta
        let definitions: [FeatureDefinition]
        switch role {
        case .guitar:
            definitions = [
                .init(feature: .guitarPickingOnsetEnergy, rule: .preserveMinimum, unit: .ratio, values: values.map(\.onsetEnergy)),
                .init(feature: .guitarAttackCrest, rule: .preserveMinimum, unit: .decibels, values: values.map(\.crestDecibels)),
                .init(feature: .guitarHarmonicEnergyRatio, rule: .preserveMinimum, unit: .ratio, values: values.map(\.harmonicEnergyRatio)),
                .init(feature: .guitarInharmonicity, rule: .preserveStability, unit: .normalized, values: values.map(\.inharmonicity)),
                .init(feature: .guitarHighBandDetail, rule: .preserveMinimum, unit: .ratio, values: values.map(\.highBandRatio)),
                .init(feature: .guitarSpectralCentroid, rule: .preserveStability, unit: .hertz, values: values.map(\.spectralCentroidHertz)),
                .init(feature: .guitarRolloff85, rule: .preserveStability, unit: .hertz, values: values.map(\.rolloff85Hertz)),
                .init(feature: .guitarLowTailRetention, rule: .preserveMinimum, unit: .decibels, values: tailLow),
                .init(feature: .guitarMidTailRetention, rule: .preserveMinimum, unit: .decibels, values: tailMid),
                .init(feature: .guitarHighTailRetention, rule: .preserveMinimum, unit: .decibels, values: tailHigh),
                .init(feature: .guitarStereoSideRatio, rule: .preserveStability, unit: .ratio, values: [stereo.sideRatio]),
                .init(feature: .guitarStereoCorrelation, rule: .preserveStability, unit: .normalized, values: [stereo.correlation]),
            ]
        case .piano:
            definitions = [
                .init(feature: .pianoHammerOnsetEnergy, rule: .preserveMinimum, unit: .ratio, values: values.map(\.onsetEnergy)),
                .init(feature: .pianoAttackCrest, rule: .preserveMinimum, unit: .decibels, values: values.map(\.crestDecibels)),
                .init(feature: .pianoPartialEnergyRatio, rule: .preserveMinimum, unit: .ratio, values: values.map(\.harmonicEnergyRatio)),
                .init(feature: .pianoInharmonicity, rule: .preserveStability, unit: .normalized, values: values.map(\.inharmonicity)),
                .init(feature: .pianoLowTailRetention, rule: .preserveMinimum, unit: .decibels, values: tailLow),
                .init(feature: .pianoMidTailRetention, rule: .preserveMinimum, unit: .decibels, values: tailMid),
                .init(feature: .pianoHighTailRetention, rule: .preserveMinimum, unit: .decibels, values: tailHigh),
                .init(feature: .pianoDoubleDecaySlopeDelta, rule: .preserveStability, unit: .decibelsPerSecond, values: doubleDecay),
                .init(feature: .pianoLowBandBalance, rule: .preserveStability, unit: .ratio, values: values.map(\.lowBandRatio)),
                .init(feature: .pianoMidBandBalance, rule: .preserveStability, unit: .ratio, values: values.map(\.midBandRatio)),
                .init(feature: .pianoSpectralCentroid, rule: .preserveStability, unit: .hertz, values: values.map(\.spectralCentroidHertz)),
                .init(feature: .pianoRolloff85, rule: .preserveStability, unit: .hertz, values: values.map(\.rolloff85Hertz)),
                .init(feature: .pianoStereoSideRatio, rule: .preserveStability, unit: .ratio, values: [stereo.sideRatio]),
                .init(feature: .pianoStereoCorrelation, rule: .preserveStability, unit: .normalized, values: [stereo.correlation]),
            ]
        default:
            preconditionFailure("Dedicated instrument analysis only supports Guitar and Piano")
        }
        return definitions.map { definition in
            let finite = definition.values.filter(\.isFinite)
            let q1 = percentile(finite, probability: 0.25)
            let median = percentile(finite, probability: 0.5)
            let q3 = percentile(finite, probability: 0.75)
            return StemRoleFeatureDistribution(
                feature: definition.feature,
                preservationRule: definition.rule,
                unit: definition.unit,
                frameCount: finite.count,
                firstQuartile: q1,
                median: median,
                thirdQuartile: q3,
                interquartileRange: max(0, q3 - q1)
            )
        }
    }

    static func makeProtectionProfile(
        role: StemRole,
        signal: AudioSignal,
        frames: [RoleFrame],
        activity: Activity
    ) -> StemRoleProtectionProfile {
        let lowDecay = decayContinuityProfile(frames.map(\.lowBandPower))
        let midDecay = decayContinuityProfile(frames.map(\.midBandPower))
        let highDecay = decayContinuityProfile(frames.map(\.highBandPower))
        let protected = frames.indices.map { index -> StemRoleProtectionFrame in
            let frame = frames[index]
            let isActive = activity.mask[index]
            let values: [StemRoleProtectedComponent: Double]
            if !isActive {
                values = Dictionary(uniqueKeysWithValues: StemRoleProtectedComponent.allCases
                    .filter { $0.role == role }
                    .map { ($0, 0) })
            } else if role == .guitar {
                values = [
                    .guitarAttack: frame.onsetEnergy,
                    .guitarHarmonics: frame.harmonicEnergyRatio * frame.rms,
                    .guitarInharmonicity: frame.inharmonicity * frame.rms,
                    .guitarHighDetail: frame.highBandRatio * frame.rms,
                    .guitarDecay: (lowDecay[index] + midDecay[index] + highDecay[index]) / 3 * frame.rms,
                    .guitarStereoSide: frame.stereoSideRatio,
                    .guitarStereoCorrelation: frame.stereoCorrelation,
                ]
            } else {
                values = [
                    .pianoAttack: frame.onsetEnergy,
                    .pianoPartials: frame.harmonicEnergyRatio * frame.rms,
                    .pianoInharmonicity: frame.inharmonicity * frame.rms,
                    .pianoLowDecay: lowDecay[index] * frame.rms,
                    .pianoMidDecay: midDecay[index] * frame.rms,
                    .pianoHighDecay: highDecay[index] * frame.rms,
                    .pianoDoubleDecay: frame.localDoubleDecaySlopeDelta,
                    .pianoLowBandBalance: frame.lowBandRatio,
                    .pianoMidBandBalance: frame.midBandRatio,
                    .pianoStereoSide: frame.stereoSideRatio,
                    .pianoStereoCorrelation: frame.stereoCorrelation,
                ]
            }
            return StemRoleProtectionFrame(
                startFrame: frame.startFrame,
                validFrameCount: frame.validFrameCount,
                values: values
            )
        }
        return StemRoleProtectionProfile(
            role: role,
            sampleRate: signal.sampleRate,
            signalFrameCount: signal.frameCount,
            analysisFrameSize: frameSize,
            hopSize: hopSize,
            frames: protected
        )
    }

    static func decayContinuityProfile(_ values: [Double]) -> [Double] {
        values.indices.map { start in
            let end = min(values.count, start + 4)
            let window = values[start..<end].map { log(max($0, numericalFloor)) }
            guard window.count > 1 else { return 1 }
            let slope = linearSlope(window, step: 1)
            return slope < 0 ? exp(slope) : 0
        }
    }

    static func frameStarts(frameCount: Int) -> [Int] {
        guard frameCount > frameSize else { return [0] }
        var starts = Array(stride(from: 0, through: frameCount - frameSize, by: hopSize))
        let last = frameCount - frameSize
        if starts.last != last { starts.append(last) }
        return starts
    }

    static func paddedFrame(channel: [Float], start: Int) -> [Float] {
        let end = min(channel.count, start + frameSize)
        var result = Array(channel[start..<end])
        if result.count < frameSize {
            result.append(contentsOf: repeatElement(0, count: frameSize - result.count))
        }
        return result
    }

    static func bandPower(_ power: [Double], lowerHz: Double, upperHz: Double, frequencyStep: Double) -> Double {
        power[binRange(lowerHz: lowerHz, upperHz: upperHz, frequencyStep: frequencyStep, binCount: power.count)].reduce(0, +)
    }

    static func binRange(lowerHz: Double, upperHz: Double, frequencyStep: Double, binCount: Int) -> Range<Int> {
        let lower = min(binCount - 1, max(1, Int(floor(lowerHz / frequencyStep))))
        let upper = min(binCount, max(lower + 1, Int(ceil(upperHz / frequencyStep))))
        return lower..<upper
    }

    static func rolloff85(power: [Double], range: Range<Int>, frequencyStep: Double) -> Double {
        let total = power[range].reduce(0, +)
        guard total > numericalFloor else { return 0 }
        let target = total * 0.85
        var cumulative = 0.0
        for bin in range {
            cumulative += power[bin]
            if cumulative >= target { return Double(bin) * frequencyStep }
        }
        return Double(range.upperBound - 1) * frequencyStep
    }

    static func linearSlope(_ values: [Double], step: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let xMean = Double(values.count - 1) * step * 0.5
        let yMean = values.reduce(0, +) / Double(values.count)
        var numerator = 0.0
        var denominator = 0.0
        for (index, value) in values.enumerated() {
            let x = Double(index) * step - xMean
            numerator += x * (value - yMean)
            denominator += x * x
        }
        return denominator > 0 ? numerator / denominator : 0
    }

    static func percentile(_ values: [Double], probability: Double) -> Double {
        let sorted = values.sorted()
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = max(0, min(1, probability)) * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    static func medianOrDefault(_ values: [Double], default defaultValue: Double) -> Double {
        let finite = values.filter(\.isFinite)
        return finite.isEmpty ? defaultValue : percentile(finite, probability: 0.5)
    }

    static func decibels(_ value: Double) -> Double {
        20 * log10(max(value, numericalFloor))
    }
}

private extension StemDedicatedInstrumentAnalysisService.RoleFrame {
    static let neutral = Self(
        startFrame: 0,
        validFrameCount: 1,
        rms: 0,
        crestDecibels: 0,
        onsetEnergy: 0,
        harmonicEnergyRatio: 0,
        inharmonicity: 0,
        spectralCentroidHertz: 0,
        rolloff85Hertz: 0,
        highBandRatio: 0,
        lowBandRatio: 0,
        midBandRatio: 0,
        lowBandPower: 0,
        midBandPower: 0,
        highBandPower: 0,
        stereoSideRatio: 0,
        stereoCorrelation: 1
    )
}
