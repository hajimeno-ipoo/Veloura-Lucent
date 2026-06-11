import Foundation

struct DenoiseMaskBreakdown: Equatable, Sendable {
    let pass: Int
    let bandOrder: Int
    let band: String
    let sampleCount: Int
    let rawMaskDB: Double
    let granularMaskDB: Double
    let shimmerMaskDB: Double
    let combinedNoiseMaskDB: Double
    let finalMaskDB: Double

    var logMessage: String {
        String(
            format: "ノイズ除去/マスク内訳/pass %d/%@: raw %.2f dB, granular %.2f dB, shimmer %.2f dB, combined %.2f dB, final %.2f dB",
            pass,
            band,
            rawMaskDB,
            granularMaskDB,
            shimmerMaskDB,
            combinedNoiseMaskDB,
            finalMaskDB
        )
    }
}

final class DenoiseMaskBreakdownCollector: @unchecked Sendable {
    private struct Key: Hashable {
        let pass: Int
        let bandOrder: Int
        let band: String
    }

    private struct Aggregate {
        var sampleCount = 0
        var rawMaskDB = 0.0
        var granularMaskDB = 0.0
        var shimmerMaskDB = 0.0
        var combinedNoiseMaskDB = 0.0
        var finalMaskDB = 0.0

        mutating func add(_ breakdown: DenoiseMaskBreakdown) {
            sampleCount += breakdown.sampleCount
            rawMaskDB += breakdown.rawMaskDB * Double(breakdown.sampleCount)
            granularMaskDB += breakdown.granularMaskDB * Double(breakdown.sampleCount)
            shimmerMaskDB += breakdown.shimmerMaskDB * Double(breakdown.sampleCount)
            combinedNoiseMaskDB += breakdown.combinedNoiseMaskDB * Double(breakdown.sampleCount)
            finalMaskDB += breakdown.finalMaskDB * Double(breakdown.sampleCount)
        }

        func average(pass: Int, bandOrder: Int, band: String) -> DenoiseMaskBreakdown? {
            guard sampleCount > 0 else { return nil }
            let count = Double(sampleCount)
            return DenoiseMaskBreakdown(
                pass: pass,
                bandOrder: bandOrder,
                band: band,
                sampleCount: sampleCount,
                rawMaskDB: rawMaskDB / count,
                granularMaskDB: granularMaskDB / count,
                shimmerMaskDB: shimmerMaskDB / count,
                combinedNoiseMaskDB: combinedNoiseMaskDB / count,
                finalMaskDB: finalMaskDB / count
            )
        }
    }

    private let lock = NSLock()
    private var storage: [Key: Aggregate] = [:]

    func record(_ breakdown: DenoiseMaskBreakdown) {
        let key = Key(pass: breakdown.pass, bandOrder: breakdown.bandOrder, band: breakdown.band)
        lock.lock()
        var aggregate = storage[key] ?? Aggregate()
        aggregate.add(breakdown)
        storage[key] = aggregate
        lock.unlock()
    }

    var summaries: [DenoiseMaskBreakdown] {
        lock.lock()
        defer { lock.unlock() }
        return storage.compactMap { key, aggregate in
            aggregate.average(pass: key.pass, bandOrder: key.bandOrder, band: key.band)
        }
        .sorted { lhs, rhs in
            if lhs.pass != rhs.pass { return lhs.pass < rhs.pass }
            return lhs.bandOrder < rhs.bandOrder
        }
    }
}

struct SpectralGateDenoiser: Sendable {
    let settings: CorrectionSettings
    let maskBreakdownCollector: DenoiseMaskBreakdownCollector?

    private var tuning: DenoiseTuning {
        let base = Self.baseTuning(for: settings.profile)
        let defaults = settings.profile.settings
        return DenoiseTuning(
            passes: settings.correctionIntensity < 0.42 ? 1 : (settings.correctionIntensity > 0.66 ? 3 : 2),
            thresholdMultiplier: clamped(
                base.thresholdMultiplier
                    + (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 1.35
                    + (settings.correctionIntensity - defaults.correctionIntensity) * 0.90,
                min: 1.0,
                max: 2.5
            ),
            lowBandFloor: clamped(
                base.lowBandFloor
                    + (settings.originalRetention - defaults.originalRetention) * 0.14
                    - (settings.lowCleanup - defaults.lowCleanup) * 0.26
                    - (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 0.06,
                min: 0.04,
                max: 0.34
            ),
            highBandFloor: clamped(
                base.highBandFloor
                    + (settings.originalRetention - defaults.originalRetention) * 0.12
                    - (settings.correctionIntensity - defaults.correctionIntensity) * 0.18
                    - (settings.highNaturalness - defaults.highNaturalness) * 0.16,
                min: 0.12,
                max: 0.42
            ),
            quietPercentile: clamped(
                base.quietPercentile + (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 28,
                min: 10,
                max: 40
            ),
            transientProtection: clamped(
                base.transientProtection + (settings.originalRetention - defaults.originalRetention) * 0.22,
                min: 0.08,
                max: 0.42
            ),
            granularReduction: clamped(
                base.granularReduction
                    + (settings.correctionIntensity - defaults.correctionIntensity) * 0.40
                    + (settings.highNaturalness - defaults.highNaturalness) * 0.34
                    + (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 0.18,
                min: 0.10,
                max: 0.72
            ),
            shimmerStabilization: clamped(
                base.shimmerStabilization
                    + (settings.highNaturalness - defaults.highNaturalness) * 0.42
                    + (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 0.12,
                min: 0.04,
                max: 0.48
            ),
            coreProtection: clamped(
                base.coreProtection + (settings.coreProtection - defaults.coreProtection) * 0.35,
                min: 0.20,
                max: 0.78
            ),
            exceptionRelaxation: clamped(
                base.exceptionRelaxation
                    + (settings.originalRetention - defaults.originalRetention) * 0.20
                    + (settings.stereoProtection - defaults.stereoProtection) * 0.08,
                min: 0.25,
                max: 0.70
            )
        )
    }

    private static func baseTuning(for strength: DenoiseStrength) -> DenoiseTuning {
        switch strength {
        case .gentle:
            return DenoiseTuning(passes: 1, thresholdMultiplier: 1.28, lowBandFloor: 0.22, highBandFloor: 0.33, quietPercentile: 16, transientProtection: 0.28, granularReduction: 0.18, shimmerStabilization: 0.08, coreProtection: 0.30, exceptionRelaxation: 0.36)
        case .balanced:
            return DenoiseTuning(passes: 2, thresholdMultiplier: 1.46, lowBandFloor: 0.16, highBandFloor: 0.28, quietPercentile: 20, transientProtection: 0.22, granularReduction: 0.26, shimmerStabilization: 0.13, coreProtection: 0.42, exceptionRelaxation: 0.46)
        case .strong:
            return DenoiseTuning(passes: 3, thresholdMultiplier: 1.85, lowBandFloor: 0.10, highBandFloor: 0.14, quietPercentile: 30, transientProtection: 0.12, granularReduction: 0.48, shimmerStabilization: 0.24, coreProtection: 0.50, exceptionRelaxation: 0.40)
        }
    }

    func process(signal: AudioSignal) -> AudioSignal {
        let channels = mapChannelsConcurrently(signal.channels) { channel in
            var current = channel
            for passIndex in 0..<tuning.passes {
                current = processPass(current, sampleRate: signal.sampleRate, pass: passIndex + 1)
            }
            return current
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processPass(_ channel: [Float], sampleRate: Double, pass: Int) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }
        let binCount = spectrogram.binCount
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let shimmerStartBin = min(max(Int(10_000 / frequencyStep), 0), binCount - 1)
        let shimmerEndBin = min(max(Int(16_000 / frequencyStep), shimmerStartBin), binCount - 1)
        let airStartBin = min(max(Int(18_000 / frequencyStep), 0), binCount - 1)
        let hasAirBand = sampleRate * 0.5 >= 18_000
        let coefficients = DenoiseMaskCoefficients(
            binCount: binCount,
            lowBandFloor: tuning.lowBandFloor,
            highBandFloor: tuning.highBandFloor
        )
        var noiseProfile = Array(repeating: Float.zero, count: binCount)
        var granularProfile = Array(repeating: Float.zero, count: binCount)
        var maskBreakdowns = maskBreakdownCollector == nil ? [] : [
            DenoiseMaskBreakdownAccumulator(bandOrder: 0, band: "8-12kHz", lower: 8_000, upper: 12_000),
            DenoiseMaskBreakdownAccumulator(bandOrder: 1, band: "12-16kHz", lower: 12_000, upper: 16_000),
            DenoiseMaskBreakdownAccumulator(bandOrder: 2, band: "16-20kHz", lower: 16_000, upper: 20_000)
        ]
        let frameEnergy = spectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(frameEnergy, tuning.quietPercentile)
        let activeMusicThreshold = SpectralDSP.percentile(frameEnergy, 50)
        let quietFrameIndices = frameEnergy.enumerated().compactMap { index, value in
            value <= quietThreshold ? index : nil
        }
        let sourceFrameIndices = quietFrameIndices.isEmpty ? Array(0..<spectrogram.frameCount) : quietFrameIndices
        var isSourceFrame = Array(repeating: false, count: spectrogram.frameCount)
        for frameIndex in sourceFrameIndices {
            isSourceFrame[frameIndex] = true
        }
        var noiseSums = Array(repeating: Float.zero, count: binCount)
        var noiseMinimums = Array(repeating: Float.greatestFiniteMagnitude, count: binCount)
        var magnitudesByBin = Array(repeating: [Float](), count: binCount)
        var granularSums = Array(repeating: Float.zero, count: binCount)
        let smoothedFrameEnergy = SpectralDSP.movingAverage(frameEnergy, windowSize: 7)
        let highBandMusicalProtection = HighBandMusicalProtection(
            spectrogram: spectrogram,
            frequencyStep: frequencyStep,
            frameEnergy: frameEnergy
        )

        for frameIndex in 0..<spectrogram.frameCount {
            let frameStart = frameIndex * binCount
            let previousFrameStart = frameStart - binCount
            for binIndex in 0..<binCount {
                let index = frameStart + binIndex
                let magnitude = hypotf(spectrogram.real[index], spectrogram.imag[index])
                magnitudesByBin[binIndex].append(magnitude)
                if isSourceFrame[frameIndex] {
                    noiseSums[binIndex] += magnitude
                    noiseMinimums[binIndex] = min(noiseMinimums[binIndex], magnitude)
                }
                if frameIndex > 0 {
                    let previousIndex = previousFrameStart + binIndex
                    let previous = hypotf(spectrogram.real[previousIndex], spectrogram.imag[previousIndex])
                    granularSums[binIndex] += abs(magnitude - previous)
                }
            }
        }

        let sourceCount = Float(max(sourceFrameIndices.count, 1))
        var shimmerEnergy: Float = 0
        var airEnergy: Float = 0
        for binIndex in 0..<binCount {
            let averageNoise = noiseSums[binIndex] / sourceCount
            let minimumNoise = noiseMinimums[binIndex].isFinite ? noiseMinimums[binIndex] : averageNoise
            let percentileNoise = SpectralDSP.percentile(magnitudesByBin[binIndex], 12)
            let baseNoise = averageNoise * 0.55 + minimumNoise * 0.20 + percentileNoise * 0.25
            noiseProfile[binIndex] = baseNoise * coefficients.highBandBias[binIndex]
            let granularAverage = granularSums[binIndex] / Float(max(spectrogram.frameCount, 1))
            granularProfile[binIndex] = granularAverage * coefficients.granularProfileScale[binIndex]
            if binIndex >= shimmerStartBin, binIndex <= shimmerEndBin {
                shimmerEnergy += averageNoise
            } else if hasAirBand, binIndex >= airStartBin {
                airEnergy += averageNoise
            }
        }
        let shimmerExceptionRelaxation = DenoiseShimmerStabilizer.exceptionRelaxation(
            airEnergy: airEnergy,
            shimmerEnergy: shimmerEnergy,
            maximum: tuning.exceptionRelaxation
        )
        var frequencyByBin = Array(repeating: 0.0, count: binCount)
        var thresholdByBin = Array(repeating: Float.zero, count: binCount)
        var baseFloorByBin = Array(repeating: Float.zero, count: binCount)
        var granularThresholdByBin = Array(repeating: Float.zero, count: binCount)
        var highBandWeightByBin = Array(repeating: Float.zero, count: binCount)
        var transientLiftScaleByBin = Array(repeating: Float.zero, count: binCount)
        for binIndex in 0..<binCount {
            let frequency = Double(binIndex) * frequencyStep
            frequencyByBin[binIndex] = frequency
            thresholdByBin[binIndex] = noiseProfile[binIndex] * tuning.thresholdMultiplier * coefficients.thresholdScale[binIndex]
            baseFloorByBin[binIndex] = coefficients.floor[binIndex]
            granularThresholdByBin[binIndex] = granularProfile[binIndex] * coefficients.granularThresholdScale[binIndex]
            highBandWeightByBin[binIndex] = min(1, max(0, Float((frequency - 8_000) / 8_000)))
            transientLiftScaleByBin[binIndex] = Self.transientProtectionLiftScale(frequency: frequency)
        }
        let highFloorLiftByIndex = highBandMusicalProtection.floorLiftTable(
            frameCount: spectrogram.frameCount,
            binCount: binCount,
            pass: pass
        )
        let highFloorLiftActiveIndexByBin = highFloorLiftByIndex.activeIndexByBin
        let highFloorLiftValues = highFloorLiftByIndex.values
        let highFloorLiftActiveBinCount = highFloorLiftByIndex.activeBinCount
        let activeMusicLowBandFloor = powf(
            Self.activeMusicLowBandFinalFloor(for: settings.profile),
            1 / Float(max(tuning.passes, 1))
        )
        let decayMusicLowBandFloors = Self.decayMusicLowBandFinalFloors(for: settings.profile)
        let decayMusicLowBodyFloor = powf(
            decayMusicLowBandFloors.lowBody,
            1 / Float(max(tuning.passes, 1))
        )
        let decayMusicLowMidFloor = powf(
            decayMusicLowBandFloors.lowMid,
            1 / Float(max(tuning.passes, 1))
        )

        for frameIndex in 0..<spectrogram.frameCount {
            let currentFrameEnergy = frameEnergy[frameIndex]
            let isActiveMusicFrame = currentFrameEnergy > quietThreshold
                && currentFrameEnergy >= activeMusicThreshold
            let isDecayMusicFrame = currentFrameEnergy > quietThreshold
                && currentFrameEnergy < activeMusicThreshold
            let transientRatio = frameEnergy[frameIndex] / max(smoothedFrameEnergy[frameIndex], 1e-6)
            let frameTransientLift = max(0, min(0.35, (transientRatio - 1) * tuning.transientProtection))
            let frameStart = frameIndex * binCount
            let previousFrameStart = frameStart - binCount
            for binIndex in 0..<binCount {
                let index = frameStart + binIndex
                let magnitude = hypotf(spectrogram.real[index], spectrogram.imag[index])
                let threshold = thresholdByBin[binIndex]
                let baseFloor = baseFloorByBin[binIndex]
                let granularActivity: Float
                if frameIndex > 0 {
                    let previousIndex = previousFrameStart + binIndex
                    let previous = hypotf(spectrogram.real[previousIndex], spectrogram.imag[previousIndex])
                    granularActivity = abs(magnitude - previous)
                } else {
                    granularActivity = 0
                }
                let granularThreshold = granularThresholdByBin[binIndex]
                let granularExcess = max(0, granularActivity - granularThreshold)
                let frequency = frequencyByBin[binIndex]
                let coreProtectedFloor = frequency > 5_000 ? baseFloor : DenoiseMaskCoefficients.protectedFloor(
                    baseFloor: baseFloor,
                    frequency: frequency,
                    magnitude: magnitude,
                    noiseLevel: noiseProfile[binIndex],
                    granularActivity: granularActivity,
                    granularBaseline: granularProfile[binIndex],
                    coreProtection: tuning.coreProtection
                )
                let floor = DenoiseMaskCoefficients.activeMusicLowBandFloor(
                    baseFloor: coreProtectedFloor,
                    frequency: frequency,
                    magnitude: magnitude,
                    noiseLevel: noiseProfile[binIndex],
                    isActiveMusicFrame: isActiveMusicFrame,
                    minimumFloor: activeMusicLowBandFloor
                )
                let decayAwareFloor = DenoiseMaskCoefficients.decayMusicLowBandFloor(
                    baseFloor: floor,
                    frequency: frequency,
                    magnitude: magnitude,
                    noiseLevel: noiseProfile[binIndex],
                    isDecayMusicFrame: isDecayMusicFrame,
                    minimumLowBodyFloor: decayMusicLowBodyFloor,
                    minimumLowMidFloor: decayMusicLowMidFloor
                )
                let highFloorLiftActiveIndex = highFloorLiftActiveIndexByBin[binIndex]
                let highFloorLift = highFloorLiftActiveIndex < 0
                    ? 0
                    : highFloorLiftValues[frameIndex * highFloorLiftActiveBinCount + highFloorLiftActiveIndex]
                let protectedRawFloor = min(
                    0.995,
                    decayAwareFloor + highFloorLift
                )
                let rawMask = max(decayAwareFloor, min(1.0, (magnitude - threshold) / max(magnitude, 1e-6)))
                let granularMask = max(
                    decayAwareFloor,
                    1 - min(0.72, granularExcess / max(magnitude + granularThreshold, 1e-6)) * tuning.granularReduction
                )
                let shimmerMask: Float
                if binIndex < shimmerStartBin || binIndex > shimmerEndBin {
                    shimmerMask = 1
                } else {
                    shimmerMask = shimmerStabilizationMask(
                        spectrogram: spectrogram,
                        frameIndex: frameIndex,
                        binIndex: binIndex,
                        magnitude: magnitude,
                        shimmerStartBin: shimmerStartBin,
                        shimmerEndBin: shimmerEndBin,
                        transientLift: frameTransientLift * transientLiftScaleByBin[binIndex],
                        exceptionRelaxation: shimmerExceptionRelaxation
                    )
                }
                let highBandWeight = highBandWeightByBin[binIndex]
                let highProtectionWeight = min(1, highFloorLift / 0.30)
                let nonTonalHighReduction = highBandWeight * (1 - highProtectionWeight) * 0.03
                let nonTonalAwareRawMask = max(decayAwareFloor, rawMask - nonTonalHighReduction)
                let protectedRawMask = max(protectedRawFloor, nonTonalAwareRawMask)
                let combinedNoiseMask = protectedRawMask * (1 - highBandWeight) + min(protectedRawMask, granularMask) * highBandWeight
                let mask = min(
                    1.0,
                    max(decayAwareFloor, min(combinedNoiseMask, shimmerMask))
                        + frameTransientLift * transientLiftScaleByBin[binIndex]
                )
                if !maskBreakdowns.isEmpty {
                    for breakdownIndex in maskBreakdowns.indices where maskBreakdowns[breakdownIndex].contains(frequency) {
                        maskBreakdowns[breakdownIndex].record(
                            rawMask: protectedRawMask,
                            granularMask: granularMask,
                            shimmerMask: shimmerMask,
                            combinedNoiseMask: combinedNoiseMask,
                            finalMask: mask
                        )
                    }
                }
                spectrogram.real[index] *= mask
                spectrogram.imag[index] *= mask
            }
        }

        if let maskBreakdownCollector {
            for breakdown in maskBreakdowns.compactMap({ $0.summary(pass: pass) }) {
                maskBreakdownCollector.record(breakdown)
            }
        }

        return SpectralDSP.istft(spectrogram)
    }

    private func transientProtectionLift(frameLift: Float, frequency: Double) -> Float {
        frameLift * Self.transientProtectionLiftScale(frequency: frequency)
    }

    private static func transientProtectionLiftScale(frequency: Double) -> Float {
        if frequency < 5_000 {
            return 1
        }
        if frequency < 10_000 {
            return 0.5
        }
        if frequency < 16_000 {
            return 0.2
        }
        return 0
    }

    private static func activeMusicLowBandFinalFloor(for profile: DenoiseStrength) -> Float {
        switch profile {
        case .gentle:
            return 0.85
        case .balanced:
            return 0.60
        case .strong:
            return 0.48
        }
    }

    private static func decayMusicLowBandFinalFloors(for profile: DenoiseStrength) -> (lowBody: Float, lowMid: Float) {
        switch profile {
        case .gentle:
            return (lowBody: 0.78, lowMid: 0.82)
        case .balanced:
            return (lowBody: 0.60, lowMid: 0.65)
        case .strong:
            return (lowBody: 0.46, lowMid: 0.54)
        }
    }

    private func shimmerStabilizationMask(
        spectrogram: Spectrogram,
        frameIndex: Int,
        binIndex: Int,
        magnitude: Float,
        shimmerStartBin: Int,
        shimmerEndBin: Int,
        transientLift: Float,
        exceptionRelaxation: Float
    ) -> Float {
        guard tuning.shimmerStabilization > 0 else { return 1 }
        guard binIndex >= shimmerStartBin, binIndex <= shimmerEndBin else { return 1 }
        guard frameIndex > 0, frameIndex + 1 < spectrogram.frameCount else { return 1 }

        let previousIndex = spectrogram.storageIndex(frameIndex: frameIndex - 1, binIndex: binIndex)
        let nextIndex = spectrogram.storageIndex(frameIndex: frameIndex + 1, binIndex: binIndex)
        let previous = hypotf(spectrogram.real[previousIndex], spectrogram.imag[previousIndex])
        let next = hypotf(spectrogram.real[nextIndex], spectrogram.imag[nextIndex])
        let temporalAverage = (previous + next) * 0.5
        let temporalExcessRatio = max(0, (magnitude - temporalAverage) / max(magnitude + temporalAverage, 1e-6))
        guard temporalExcessRatio > 0 else { return 1 }

        let bandPosition = Float(binIndex - shimmerStartBin) / Float(max(shimmerEndBin - shimmerStartBin, 1))
        return DenoiseShimmerStabilizer.mask(
            temporalExcessRatio: temporalExcessRatio,
            bandPosition: bandPosition,
            transientLift: transientLift,
            stabilization: tuning.shimmerStabilization,
            exceptionRelaxation: exceptionRelaxation
        )
    }
}

private struct DenoiseMaskBreakdownAccumulator {
    let bandOrder: Int
    let band: String
    let lower: Double
    let upper: Double
    private var sampleCount = 0
    private var rawMaskDB = 0.0
    private var granularMaskDB = 0.0
    private var shimmerMaskDB = 0.0
    private var combinedNoiseMaskDB = 0.0
    private var finalMaskDB = 0.0

    init(bandOrder: Int, band: String, lower: Double, upper: Double) {
        self.bandOrder = bandOrder
        self.band = band
        self.lower = lower
        self.upper = upper
    }

    func contains(_ frequency: Double) -> Bool {
        frequency >= lower && frequency < upper
    }

    mutating func record(rawMask: Float, granularMask: Float, shimmerMask: Float, combinedNoiseMask: Float, finalMask: Float) {
        sampleCount += 1
        rawMaskDB += Self.decibels(rawMask)
        granularMaskDB += Self.decibels(granularMask)
        shimmerMaskDB += Self.decibels(shimmerMask)
        combinedNoiseMaskDB += Self.decibels(combinedNoiseMask)
        finalMaskDB += Self.decibels(finalMask)
    }

    func summary(pass: Int) -> DenoiseMaskBreakdown? {
        guard sampleCount > 0 else { return nil }
        let count = Double(sampleCount)
        return DenoiseMaskBreakdown(
            pass: pass,
            bandOrder: bandOrder,
            band: band,
            sampleCount: sampleCount,
            rawMaskDB: rawMaskDB / count,
            granularMaskDB: granularMaskDB / count,
            shimmerMaskDB: shimmerMaskDB / count,
            combinedNoiseMaskDB: combinedNoiseMaskDB / count,
            finalMaskDB: finalMaskDB / count
        )
    }

    private static func decibels(_ gain: Float) -> Double {
        20 * log10(max(Double(gain), 1e-6))
    }
}

struct HighBandMusicalProtection {
    struct FloorLiftTable {
        let values: [Float]
        let activeIndexByBin: [Int]
        let activeBinCount: Int

        func value(frameIndex: Int, binIndex: Int) -> Float {
            guard activeIndexByBin.indices.contains(binIndex) else { return 0 }
            let activeIndex = activeIndexByBin[binIndex]
            guard activeIndex >= 0 else { return 0 }
            return values[frameIndex * activeBinCount + activeIndex]
        }
    }

    private struct Band {
        let lower: Double
        let upper: Double
        let baseLift: Float
        let secondPassLift: Float
        let frameLift: [Float]

        func contains(_ frequency: Double) -> Bool {
            frequency >= lower && frequency < upper
        }
    }

    private let bands: [Band]
    private let bandIndexByBin: [Int?]

    init(spectrogram: Spectrogram, frequencyStep: Double, frameEnergy: [Float]) {
        let bodyEnergy = Self.bandEnergy(in: spectrogram, lower: 160, upper: 5_000, frequencyStep: frequencyStep)
        let bodyReference = max(SpectralDSP.percentile(bodyEnergy, 50), 1e-7)
        let frameReference = max(SpectralDSP.percentile(frameEnergy, 50), 1e-7)
        let quietFrameThreshold = SpectralDSP.percentile(frameEnergy, 20)
        let bodyWeights = bodyEnergy.indices.map { index -> Float in
            let bodyRatio = bodyEnergy[index] / bodyReference
            let frameRatio = frameEnergy[index] / frameReference
            let bodyWeight = clamped((bodyRatio - 0.20) / 0.55, min: 0, max: 1)
            let frameWeight = clamped((frameRatio - 0.30) / 0.50, min: 0, max: 1)
            return bodyWeight * frameWeight
        }

        let builtBands = [
            Self.makeBand(
                spectrogram: spectrogram,
                frequencyStep: frequencyStep,
                lower: 5_000,
                upper: 8_000,
                baseLift: 0.72,
                secondPassLift: 0.04,
                frameEnergy: frameEnergy,
                quietFrameThreshold: quietFrameThreshold,
                bodyWeights: bodyWeights
            ),
            Self.makeBand(
                spectrogram: spectrogram,
                frequencyStep: frequencyStep,
                lower: 8_000,
                upper: 12_000,
                baseLift: 0.98,
                secondPassLift: 0.05,
                frameEnergy: frameEnergy,
                quietFrameThreshold: quietFrameThreshold,
                bodyWeights: bodyWeights
            ),
            Self.makeBand(
                spectrogram: spectrogram,
                frequencyStep: frequencyStep,
                lower: 12_000,
                upper: 16_000,
                baseLift: 1.05,
                secondPassLift: 0.06,
                frameEnergy: frameEnergy,
                quietFrameThreshold: quietFrameThreshold,
                bodyWeights: bodyWeights
            ),
            Self.makeBand(
                spectrogram: spectrogram,
                frequencyStep: frequencyStep,
                lower: 16_000,
                upper: 20_000,
                baseLift: 0.94,
                secondPassLift: 0.04,
                frameEnergy: frameEnergy,
                quietFrameThreshold: quietFrameThreshold,
                bodyWeights: bodyWeights
            )
        ]
        bands = builtBands
        bandIndexByBin = (0..<spectrogram.binCount).map { binIndex in
            let frequency = Double(binIndex) * frequencyStep
            return builtBands.firstIndex(where: { $0.contains(frequency) })
        }
    }

    func floorLift(frameIndex: Int, binIndex: Int, pass: Int) -> Float {
        guard bandIndexByBin.indices.contains(binIndex),
              let bandIndex = bandIndexByBin[binIndex],
              bands.indices.contains(bandIndex),
              bands[bandIndex].frameLift.indices.contains(frameIndex)
        else {
            return 0
        }
        let band = bands[bandIndex]
        let passLift = pass > 1 ? band.secondPassLift : 0
        return band.frameLift[frameIndex] + passLift * min(1, band.frameLift[frameIndex] / max(band.baseLift, 1e-6))
    }

    func floorLiftTable(frameCount: Int, binCount: Int, pass: Int) -> FloorLiftTable {
        var activeIndexByBin = Array(repeating: -1, count: binCount)
        var activeBins: [(binIndex: Int, bandIndex: Int)] = []
        for binIndex in 0..<binCount {
            guard bandIndexByBin.indices.contains(binIndex),
                  let bandIndex = bandIndexByBin[binIndex],
                  bands.indices.contains(bandIndex)
            else {
                continue
            }
            activeIndexByBin[binIndex] = activeBins.count
            activeBins.append((binIndex: binIndex, bandIndex: bandIndex))
        }

        var values = Array(repeating: Float.zero, count: frameCount * activeBins.count)
        for activeIndex in activeBins.indices {
            let bandIndex = activeBins[activeIndex].bandIndex
            let band = bands[bandIndex]
            let passLift = pass > 1 ? band.secondPassLift : 0
            let baseLift = max(band.baseLift, 1e-6)
            let activeFrameCount = min(frameCount, band.frameLift.count)
            for frameIndex in 0..<activeFrameCount {
                let frameLift = band.frameLift[frameIndex]
                values[frameIndex * activeBins.count + activeIndex] = frameLift + passLift * min(1, frameLift / baseLift)
            }
        }
        return FloorLiftTable(values: values, activeIndexByBin: activeIndexByBin, activeBinCount: activeBins.count)
    }

    private static func makeBand(
        spectrogram: Spectrogram,
        frequencyStep: Double,
        lower: Double,
        upper: Double,
        baseLift: Float,
        secondPassLift: Float,
        frameEnergy: [Float],
        quietFrameThreshold: Float,
        bodyWeights: [Float]
    ) -> Band {
        let energy = bandEnergy(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep)
        let peakShare = bandPeakShare(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep)
        let smoothed = SpectralDSP.movingAverage(energy, windowSize: 9)
        let reference = max(SpectralDSP.percentile(energy, 50), 1e-7)
        let quietEnergy = energy.indices.compactMap { index -> Float? in
            frameEnergy.indices.contains(index) && frameEnergy[index] <= quietFrameThreshold ? energy[index] : nil
        }
        let quietReference = max(SpectralDSP.percentile(quietEnergy.isEmpty ? energy : quietEnergy, 50), 1e-7)
        let lift = energy.indices.map { index -> Float in
            let presence = clamped((energy[index] / reference - 0.20) / 0.50, min: 0, max: 1)
            let stability = clamped(
                1 - abs(energy[index] - smoothed[index]) / max(smoothed[index], 1e-7) * 1.2,
                min: 0,
                max: 1
            )
            let tonalWeight = clamped((peakShare[index] - 0.06) / 0.10, min: 0, max: 1)
            let quietExcessWeight = clamped((energy[index] / quietReference - 1.05) / 0.90, min: 0, max: 1)
            let musicalHighWeight = max(tonalWeight, quietExcessWeight)
            let bodyWeight = bodyWeights.indices.contains(index) ? bodyWeights[index] : 0
            return baseLift * bodyWeight * presence * stability * musicalHighWeight
        }

        return Band(lower: lower, upper: upper, baseLift: baseLift, secondPassLift: secondPassLift, frameLift: lift)
    }

    private static func bandEnergy(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> [Float] {
        let (startBin, endBin) = binRange(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep)
        guard endBin > startBin else {
            return Array(repeating: 0, count: spectrogram.frameCount)
        }

        var values = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            for binIndex in startBin...endBin {
                sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            values[frameIndex] = sum / Float(endBin - startBin + 1)
        }
        return values
    }

    private static func bandPeakShare(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> [Float] {
        let (startBin, endBin) = binRange(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep)
        guard endBin > startBin else {
            return Array(repeating: 0, count: spectrogram.frameCount)
        }

        var values = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            var peak: Float = 0
            for binIndex in startBin...endBin {
                let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
                sum += magnitude
                peak = max(peak, magnitude)
            }
            values[frameIndex] = peak / max(sum, 1e-7)
        }
        return values
    }

    private static func binRange(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> (Int, Int) {
        let maxBin = spectrogram.binCount - 1
        let startBin = min(max(Int(lower / frequencyStep), 0), maxBin)
        let endBin = min(max(Int(upper / frequencyStep), startBin), maxBin)
        return (startBin, endBin)
    }
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.min(maxValue, Swift.max(minValue, value))
}

private struct DenoiseTuning: Sendable {
    let passes: Int
    let thresholdMultiplier: Float
    let lowBandFloor: Float
    let highBandFloor: Float
    let quietPercentile: Float
    let transientProtection: Float
    let granularReduction: Float
    let shimmerStabilization: Float
    let coreProtection: Float
    let exceptionRelaxation: Float
}
