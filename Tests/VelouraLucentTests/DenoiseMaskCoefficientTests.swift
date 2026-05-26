import Foundation
import Testing
@testable import VelouraLucent

struct DenoiseMaskCoefficientTests {
    @Test
    func precomputedCoefficientsMatchInlineFormula() {
        let binCount = 1_025
        let lowBandFloor: Float = 0.16
        let highBandFloor: Float = 0.28
        let coefficients = DenoiseMaskCoefficients(
            binCount: binCount,
            lowBandFloor: lowBandFloor,
            highBandFloor: highBandFloor
        )

        for binIndex in stride(from: 0, to: binCount, by: 17) {
            let normalizedBand = Float(binIndex) / Float(max(binCount - 1, 1))
            expectClose(coefficients.highBandBias[binIndex], 0.90 + powf(normalizedBand, 1.25) * 0.08)
            expectClose(coefficients.granularProfileScale[binIndex], max(0, (normalizedBand - 0.42) / 0.58))
            expectClose(coefficients.thresholdScale[binIndex], 0.90 + powf(normalizedBand, 1.1) * 0.12)
            expectClose(
                coefficients.floor[binIndex],
                lowBandFloor + (highBandFloor - lowBandFloor) * powf(normalizedBand, 1.25)
            )
            expectClose(coefficients.granularThresholdScale[binIndex], 1.1 + normalizedBand * 0.6)
        }
    }

    @Test
    func precomputedMaskMatchesInlineMaskFormula() {
        let binCount = 1_025
        let lowBandFloor: Float = 0.16
        let highBandFloor: Float = 0.28
        let thresholdMultiplier: Float = 1.46
        let granularReduction: Float = 0.26
        let coefficients = DenoiseMaskCoefficients(
            binCount: binCount,
            lowBandFloor: lowBandFloor,
            highBandFloor: highBandFloor
        )

        for binIndex in stride(from: 0, to: binCount, by: 31) {
            let normalizedBand = Float(binIndex) / Float(max(binCount - 1, 1))
            let magnitude: Float = 0.08 + Float(binIndex % 13) * 0.004
            let noiseProfile: Float = 0.02 + Float(binIndex % 7) * 0.002
            let granularProfile: Float = 0.01 + Float(binIndex % 5) * 0.001
            let granularActivity: Float = 0.015 + Float(binIndex % 11) * 0.001
            let transientLift: Float = 0.03

            let inlineThreshold = noiseProfile * thresholdMultiplier * (0.90 + powf(normalizedBand, 1.1) * 0.12)
            let inlineFloor = lowBandFloor + (highBandFloor - lowBandFloor) * powf(normalizedBand, 1.25)
            let inlineRawMask = max(inlineFloor, min(1.0, (magnitude - inlineThreshold) / max(magnitude, 1e-6)))
            let inlineGranularThreshold = granularProfile * (1.1 + normalizedBand * 0.6)
            let inlineGranularExcess = max(0, granularActivity - inlineGranularThreshold)
            let inlineGranularMask = max(
                inlineFloor,
                1 - min(0.72, inlineGranularExcess / max(magnitude + inlineGranularThreshold, 1e-6)) * granularReduction
            )
            let inlineMask = min(1.0, max(inlineRawMask, inlineGranularMask) + transientLift)

            let precomputedThreshold = noiseProfile * thresholdMultiplier * coefficients.thresholdScale[binIndex]
            let precomputedFloor = coefficients.floor[binIndex]
            let precomputedRawMask = max(precomputedFloor, min(1.0, (magnitude - precomputedThreshold) / max(magnitude, 1e-6)))
            let precomputedGranularThreshold = granularProfile * coefficients.granularThresholdScale[binIndex]
            let precomputedGranularExcess = max(0, granularActivity - precomputedGranularThreshold)
            let precomputedGranularMask = max(
                precomputedFloor,
                1 - min(0.72, precomputedGranularExcess / max(magnitude + precomputedGranularThreshold, 1e-6)) * granularReduction
            )
            let precomputedMask = min(1.0, max(precomputedRawMask, precomputedGranularMask) + transientLift)

            expectClose(precomputedMask, inlineMask)
        }
    }

    @Test
    func coreProtectionRaisesStableLowMidFloorForStrongDenoise() {
        let baseFloor: Float = 0.11

        let protectedFloor = DenoiseMaskCoefficients.protectedFloor(
            baseFloor: baseFloor,
            frequency: 1_000,
            magnitude: 0.42,
            noiseLevel: 0.06,
            granularActivity: 0.004,
            granularBaseline: 0.006,
            coreProtection: 0.58
        )

        #expect(protectedFloor > baseFloor + 0.08)
        #expect(protectedFloor <= 0.46)
    }

    @Test
    func coreProtectionDoesNotLiftUnstableOrHighFrequencyBins() {
        let baseFloor: Float = 0.11

        let unstableFloor = DenoiseMaskCoefficients.protectedFloor(
            baseFloor: baseFloor,
            frequency: 2_500,
            magnitude: 0.42,
            noiseLevel: 0.06,
            granularActivity: 0.35,
            granularBaseline: 0.006,
            coreProtection: 0.58
        )
        let highFrequencyFloor = DenoiseMaskCoefficients.protectedFloor(
            baseFloor: baseFloor,
            frequency: 7_000,
            magnitude: 0.42,
            noiseLevel: 0.06,
            granularActivity: 0.004,
            granularBaseline: 0.006,
            coreProtection: 0.58
        )

        expectClose(unstableFloor, baseFloor)
        expectClose(highFrequencyFloor, baseFloor)
    }

    @Test
    func activeMusicLowBandFloorOnlyProtectsActiveLowAndLowMidBins() {
        let baseFloor: Float = 0.18
        let activeMinimum: Float = 0.866_025_4

        let lowBodyFloor = DenoiseMaskCoefficients.activeMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 120,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isActiveMusicFrame: true,
            minimumFloor: activeMinimum
        )
        let lowMidFloor = DenoiseMaskCoefficients.activeMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 520,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isActiveMusicFrame: true,
            minimumFloor: activeMinimum
        )
        let quietFloor = DenoiseMaskCoefficients.activeMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 120,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isActiveMusicFrame: false,
            minimumFloor: activeMinimum
        )
        let subsonicFloor = DenoiseMaskCoefficients.activeMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 12,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isActiveMusicFrame: true,
            minimumFloor: activeMinimum
        )
        let highFloor = DenoiseMaskCoefficients.activeMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 1_400,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isActiveMusicFrame: true,
            minimumFloor: activeMinimum
        )
        let noiseFloor = DenoiseMaskCoefficients.activeMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 120,
            magnitude: 0.06,
            noiseLevel: 0.06,
            isActiveMusicFrame: true,
            minimumFloor: activeMinimum
        )

        expectClose(lowBodyFloor, activeMinimum)
        expectClose(lowMidFloor, activeMinimum)
        expectClose(quietFloor, baseFloor)
        expectClose(subsonicFloor, baseFloor)
        expectClose(highFloor, baseFloor)
        expectClose(noiseFloor, baseFloor)
    }

    @Test
    func decayMusicLowBandFloorOnlyProtectsTailLowBodyAndLowMidBins() {
        let baseFloor: Float = 0.18
        let lowBodyMinimum: Float = 0.60
        let lowMidMinimum: Float = 0.65

        let subLowFloor = DenoiseMaskCoefficients.decayMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 45,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isDecayMusicFrame: true,
            minimumLowBodyFloor: lowBodyMinimum,
            minimumLowMidFloor: lowMidMinimum
        )
        let lowBodyFloor = DenoiseMaskCoefficients.decayMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 120,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isDecayMusicFrame: true,
            minimumLowBodyFloor: lowBodyMinimum,
            minimumLowMidFloor: lowMidMinimum
        )
        let lowMidFloor = DenoiseMaskCoefficients.decayMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 220,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isDecayMusicFrame: true,
            minimumLowBodyFloor: lowBodyMinimum,
            minimumLowMidFloor: lowMidMinimum
        )
        let upperMidFloor = DenoiseMaskCoefficients.decayMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 320,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isDecayMusicFrame: true,
            minimumLowBodyFloor: lowBodyMinimum,
            minimumLowMidFloor: lowMidMinimum
        )
        let quietFloor = DenoiseMaskCoefficients.decayMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 120,
            magnitude: 0.24,
            noiseLevel: 0.06,
            isDecayMusicFrame: false,
            minimumLowBodyFloor: lowBodyMinimum,
            minimumLowMidFloor: lowMidMinimum
        )
        let noiseFloor = DenoiseMaskCoefficients.decayMusicLowBandFloor(
            baseFloor: baseFloor,
            frequency: 120,
            magnitude: 0.06,
            noiseLevel: 0.06,
            isDecayMusicFrame: true,
            minimumLowBodyFloor: lowBodyMinimum,
            minimumLowMidFloor: lowMidMinimum
        )

        expectClose(subLowFloor, baseFloor)
        expectClose(lowBodyFloor, lowBodyMinimum)
        expectClose(lowMidFloor, lowMidMinimum)
        expectClose(upperMidFloor, baseFloor)
        expectClose(quietFloor, baseFloor)
        expectClose(noiseFloor, baseFloor)
    }

    @Test
    func humRemovalFrameAttenuationKeepsQuietFramesAndWeakensActiveMusicFrames() {
        let quietScale = HumRemovalFrameAttenuation.scale(
            frameEnergy: 0.10,
            quietThreshold: 0.20,
            activeThreshold: 0.50,
            activeScale: 0.35
        )
        let activeScale = HumRemovalFrameAttenuation.scale(
            frameEnergy: 0.60,
            quietThreshold: 0.20,
            activeThreshold: 0.50,
            activeScale: 0.35
        )
        let transitionScale = HumRemovalFrameAttenuation.scale(
            frameEnergy: 0.35,
            quietThreshold: 0.20,
            activeThreshold: 0.50,
            activeScale: 0.35
        )

        expectClose(quietScale, 1.0)
        expectClose(activeScale, 0.35)
        #expect(transitionScale > activeScale)
        #expect(transitionScale < quietScale)
    }

    @Test
    func rumbleFrameAttenuationOnlyProtectsLowBodyDuringMusicFrames() {
        let quietLowBodyScale = RumbleFrameAttenuation.scale(
            frequency: 90,
            frameEnergy: 0.10,
            quietThreshold: 0.20,
            activeThreshold: 0.50
        )
        let activeLowBodyScale = RumbleFrameAttenuation.scale(
            frequency: 90,
            frameEnergy: 0.60,
            quietThreshold: 0.20,
            activeThreshold: 0.50
        )
        let tailLowBodyScale = RumbleFrameAttenuation.scale(
            frequency: 90,
            frameEnergy: 0.35,
            quietThreshold: 0.20,
            activeThreshold: 0.50
        )
        let subRumbleScale = RumbleFrameAttenuation.scale(
            frequency: 40,
            frameEnergy: 0.60,
            quietThreshold: 0.20,
            activeThreshold: 0.50
        )
        let warmthScale = RumbleFrameAttenuation.scale(
            frequency: 170,
            frameEnergy: 0.60,
            quietThreshold: 0.20,
            activeThreshold: 0.50
        )

        expectClose(quietLowBodyScale, 1.0)
        expectClose(activeLowBodyScale, RumbleFrameAttenuation.activeMusicScale)
        #expect(tailLowBodyScale > activeLowBodyScale)
        #expect(tailLowBodyScale < quietLowBodyScale)
        expectClose(subRumbleScale, 1.0)
        expectClose(warmthScale, 1.0)
    }

    @Test
    func rumbleFrameAttenuationKeepsStrongCorrectionRumbleReduction() {
        expectClose(RumbleFrameAttenuation.activeMusicScale(correctionIntensity: 0.50), 0.60)
        let transitionScale = RumbleFrameAttenuation.activeMusicScale(correctionIntensity: 0.61)
        #expect(transitionScale > 0.60)
        #expect(transitionScale < 1.0)
        expectClose(RumbleFrameAttenuation.activeMusicScale(correctionIntensity: 0.72), 1.0)
    }

    @Test
    func humRemovalFrameAttenuationKeepsMoreReductionForProminentHum() {
        let spectrogram = Spectrogram(
            real: [
                1.0, 1.0, 10.0, 1.0, 1.0,
                1.0, 1.0, 1.4, 1.0, 1.0
            ],
            imag: Array(repeating: Float.zero, count: 10),
            fftSize: 8,
            hopSize: 4,
            originalLength: 8,
            leadingPadding: 0,
            trailingPadding: 0,
            frameCount: 2
        )

        let prominentScale = HumRemovalFrameAttenuation.scale(
            spectrogram: spectrogram,
            frameIndex: 0,
            centerBin: 2,
            frameEnergy: 0.60,
            quietThreshold: 0.20,
            activeThreshold: 0.50
        )
        let musicalScale = HumRemovalFrameAttenuation.scale(
            spectrogram: spectrogram,
            frameIndex: 1,
            centerBin: 2,
            frameEnergy: 0.60,
            quietThreshold: 0.20,
            activeThreshold: 0.50
        )

        expectClose(prominentScale, 0.85)
        expectClose(musicalScale, 0.35)
    }

    @Test
    func exceptionRelaxationWeakensShimmerStabilizationWhenAirBandIsStrong() {
        let normalRelaxation = DenoiseShimmerStabilizer.exceptionRelaxation(
            airEnergy: 0.12,
            shimmerEnergy: 1.0,
            maximum: 0.58
        )
        let exceptionRelaxation = DenoiseShimmerStabilizer.exceptionRelaxation(
            airEnergy: 0.95,
            shimmerEnergy: 1.0,
            maximum: 0.58
        )

        let normalMask = DenoiseShimmerStabilizer.mask(
            temporalExcessRatio: 0.72,
            bandPosition: 0.5,
            transientLift: 0,
            stabilization: 0.18,
            exceptionRelaxation: normalRelaxation
        )
        let relaxedMask = DenoiseShimmerStabilizer.mask(
            temporalExcessRatio: 0.72,
            bandPosition: 0.5,
            transientLift: 0,
            stabilization: 0.18,
            exceptionRelaxation: exceptionRelaxation
        )

        #expect(normalRelaxation == 0)
        #expect(exceptionRelaxation > 0.5)
        #expect(relaxedMask > normalMask)
    }

    @Test
    func highFloorLiftTableMatchesPerBinFunctionForEachPass() {
        let sampleRate = 48_000.0
        let signal = (0..<12_000).map { index -> Float in
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.22
            let sparkle = sin(2 * Double.pi * 9_500 * time) * 0.035
            let air = sin(2 * Double.pi * 14_000 * time) * 0.025
            return Float(body + sparkle + air)
        }
        let spectrogram = SpectralDSP.stft(signal)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let protection = HighBandMusicalProtection(
            spectrogram: spectrogram,
            frequencyStep: frequencyStep,
            frameEnergy: spectrogram.frameAverageMagnitudes()
        )

        for pass in [1, 2] {
            let table = protection.floorLiftTable(
                frameCount: spectrogram.frameCount,
                binCount: spectrogram.binCount,
                pass: pass
            )

            #expect(table.activeIndexByBin.count == spectrogram.binCount)
            #expect(table.activeBinCount < spectrogram.binCount)
            #expect(table.values.count == spectrogram.frameCount * table.activeBinCount)
            for frameIndex in 0..<spectrogram.frameCount {
                for binIndex in 0..<spectrogram.binCount {
                    #expect(table.value(frameIndex: frameIndex, binIndex: binIndex) == protection.floorLift(frameIndex: frameIndex, binIndex: binIndex, pass: pass))
                }
            }
        }
    }

    private func expectClose(_ actual: Float, _ expected: Float, tolerance: Float = 0.000_001) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
