import Accelerate
import Foundation

struct StemRoleAnalysisService: Sendable {
    private static let processingSampleRate = 48_000.0
    private static let sampleRateTolerance = 0.5
    private static let frameSize = 4_096
    private static let hopSize = 2_048
    private static let numericalFloor = 1e-24

    func analyze(
        role: StemRole,
        processingSignal48000: AudioSignal
    ) throws -> StemRoleAnalysisSnapshot {
        try analyzeWithProtection(
            role: role,
            processingSignal48000: processingSignal48000
        ).snapshot
    }

    func analyzeWithProtection(
        role: StemRole,
        processingSignal48000: AudioSignal
    ) throws -> StemRoleAnalysisResult {
        let frameCount = try validateProcessingSignal(processingSignal48000)
        let analyzed = try Self.makeAnalysisFrames(analysisSignal: processingSignal48000)
        let distributions = try Self.makeFeatureDistributions(role: role, frames: analyzed.frames)
        let protectionProfile = try Self.makeProtectionProfile(
            role: role,
            analysisSignal: processingSignal48000,
            analyzed: analyzed
        )

        return StemRoleAnalysisResult(
            snapshot: StemRoleAnalysisSnapshot(
                role: role,
                authoritativeSampleRate: processingSignal48000.sampleRate,
                analysisSampleRate: processingSignal48000.sampleRate,
                authoritativeFrameCount: frameCount,
                analysisFrameCount: frameCount,
                features: distributions
            ),
            protectionProfile: protectionProfile
        )
    }

    private func validateProcessingSignal(_ signal: AudioSignal) throws -> Int {
        guard abs(signal.sampleRate - Self.processingSampleRate) < Self.sampleRateTolerance else {
            throw StemRoleAnalysisError.unsupportedAuthoritativeSampleRate(
                expected: Self.processingSampleRate,
                actual: signal.sampleRate
            )
        }
        guard signal.channels.count == 2 else {
            throw StemRoleAnalysisError.stereoRequired(actualChannelCount: signal.channels.count)
        }
        guard let first = signal.channels.first, !first.isEmpty else {
            throw StemRoleAnalysisError.emptySignal
        }
        for (channelIndex, channel) in signal.channels.enumerated() {
            guard channel.count == first.count else {
                throw StemRoleAnalysisError.inconsistentFrameCount(
                    channelIndex: channelIndex,
                    expected: first.count,
                    actual: channel.count
                )
            }
            if let frameIndex = channel.firstIndex(where: { !$0.isFinite }) {
                throw StemRoleAnalysisError.nonFiniteSample(
                    channelIndex: channelIndex,
                    frameIndex: frameIndex
                )
            }
        }
        return first.count
    }
}

private extension StemRoleAnalysisService {
    struct FeatureDefinition {
        let feature: StemRoleAnalysisFeature
        let rule: StemRoleFeaturePreservationRule
        let unit: StemRoleAnalysisUnit
    }

    struct FrameAnalysis {
        let rms: Double
        let crestDecibels: Double
        let highBandEnergy: Double
        let lowMidBandEnergy: Double
        let midHighBandEnergy: Double
        let spectralFlux: Double
        let spectralEntropy: Double
        let harmonicContinuity: Double
        let stereoSpatialBalance: Double
        let lowBandPhaseCoherence: Double
        let vocalsFundamental: Double
        let vocalsHarmonicStrength: Double
        let vocalsBreathConsonantBalance: Double
        let vocalsFormantCenter: Double
        let bassFundamental: Double
        let bassHarmonicStrength: Double
        let bassFiftyHertzPitchAlignment: Double
        let bassSixtyHertzPitchAlignment: Double
        let complexOnsetStrength: Double
        let vocalCoreEnergy: Double
        let vocalConsonantActivity: Double
        let vocalSibilanceEnergy: Double
        let vocalBreathEnergy: Double
        let bassFundamentalEnergy: Double
        let broadBandPhaseCoherence: Double
    }

    struct AnalyzedFrames {
        let starts: [Int]
        let validFrameCounts: [Int]
        let frames: [FrameAnalysis]
    }

    static func makeAnalysisFrames(
        analysisSignal: AudioSignal
    ) throws -> AnalyzedFrames {
        guard analysisSignal.channels.count == 2,
              let left = analysisSignal.channels.first,
              let right = analysisSignal.channels.last,
              left.count == right.count,
              !left.isEmpty
        else {
            throw StemRoleAnalysisError.stereoRequired(
                actualChannelCount: analysisSignal.channels.count
            )
        }

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
        let starts = frameStarts(frameCount: left.count)
        let validFrameCounts = starts.map { min(frameSize, left.count - $0) }
        var frames: [FrameAnalysis] = []
        frames.reserveCapacity(starts.count)
        var previousNormalizedPower: [Double]?
        var previousNormalizedReal: [Double]?
        var previousNormalizedImaginary: [Double]?
        var previousVocalsFundamental: Double?
        var previousBassFundamental: Double?

        for start in starts {
            let leftFrame = paddedFrame(channel: left, start: start)
            let rightFrame = paddedFrame(channel: right, start: start)
            let analyzed = analyzeFrame(
                left: leftFrame,
                right: rightFrame,
                window: window,
                dft: dft,
                sampleRate: analysisSignal.sampleRate,
                previousNormalizedPower: previousNormalizedPower,
                previousNormalizedReal: previousNormalizedReal,
                previousNormalizedImaginary: previousNormalizedImaginary,
                previousVocalsFundamental: previousVocalsFundamental,
                previousBassFundamental: previousBassFundamental
            )
            frames.append(analyzed.frame)
            previousNormalizedPower = analyzed.normalizedPower
            previousNormalizedReal = analyzed.normalizedReal
            previousNormalizedImaginary = analyzed.normalizedImaginary
            previousVocalsFundamental = analyzed.frame.vocalsFundamental
            previousBassFundamental = analyzed.frame.bassFundamental
        }

        return AnalyzedFrames(
            starts: starts,
            validFrameCounts: validFrameCounts,
            frames: frames
        )
    }

    static func makeFeatureDistributions(
        role: StemRole,
        frames: [FrameAnalysis]
    ) throws -> [StemRoleFeatureDistribution] {
        let values = featureValues(role: role, frames: frames)
        return try featureDefinitions(for: role).map { definition in
            guard let featureValues = values[definition.feature], !featureValues.isEmpty else {
                throw StemRoleAnalysisError.unableToProduceFeature(definition.feature)
            }
            let finiteValues = featureValues.filter(\.isFinite)
            guard finiteValues.count == featureValues.count else {
                throw StemRoleAnalysisError.unableToProduceFeature(definition.feature)
            }
            let firstQuartile = percentile(finiteValues, probability: 0.25)
            let median = percentile(finiteValues, probability: 0.5)
            let thirdQuartile = percentile(finiteValues, probability: 0.75)
            return StemRoleFeatureDistribution(
                feature: definition.feature,
                preservationRule: definition.rule,
                unit: definition.unit,
                frameCount: finiteValues.count,
                firstQuartile: firstQuartile,
                median: median,
                thirdQuartile: thirdQuartile,
                interquartileRange: max(0, thirdQuartile - firstQuartile)
            )
        }
    }

    static func analyzeFrame(
        left: [Float],
        right: [Float],
        window: [Float],
        dft: vDSP.DiscreteFourierTransform<Float>,
        sampleRate: Double,
        previousNormalizedPower: [Double]?,
        previousNormalizedReal: [Double]?,
        previousNormalizedImaginary: [Double]?,
        previousVocalsFundamental: Double?,
        previousBassFundamental: Double?
    ) -> (
        frame: FrameAnalysis,
        normalizedPower: [Double],
        normalizedReal: [Double],
        normalizedImaginary: [Double]
    ) {
        var leftWindowed = Array(repeating: Float.zero, count: frameSize)
        var rightWindowed = Array(repeating: Float.zero, count: frameSize)
        vDSP.multiply(left, window, result: &leftWindowed)
        vDSP.multiply(right, window, result: &rightWindowed)

        let inputImaginary = Array(repeating: Float.zero, count: frameSize)
        var leftReal = Array(repeating: Float.zero, count: frameSize)
        var leftImaginary = Array(repeating: Float.zero, count: frameSize)
        var rightReal = Array(repeating: Float.zero, count: frameSize)
        var rightImaginary = Array(repeating: Float.zero, count: frameSize)
        dft.transform(
            inputReal: leftWindowed,
            inputImaginary: inputImaginary,
            outputReal: &leftReal,
            outputImaginary: &leftImaginary
        )
        dft.transform(
            inputReal: rightWindowed,
            inputImaginary: inputImaginary,
            outputReal: &rightReal,
            outputImaginary: &rightImaginary
        )

        let halfCount = frameSize / 2 + 1
        var monoPower = Array(repeating: 0.0, count: halfCount)
        var leftPower = Array(repeating: 0.0, count: halfCount)
        var rightPower = Array(repeating: 0.0, count: halfCount)
        var crossReal = Array(repeating: 0.0, count: halfCount)
        var monoRealSpectrum = Array(repeating: 0.0, count: halfCount)
        var monoImaginarySpectrum = Array(repeating: 0.0, count: halfCount)
        var midEnergy = 0.0
        var sideEnergy = 0.0

        for index in 0..<halfCount {
            let leftRealValue = Double(leftReal[index])
            let leftImaginaryValue = Double(leftImaginary[index])
            let rightRealValue = Double(rightReal[index])
            let rightImaginaryValue = Double(rightImaginary[index])
            let monoReal = (leftRealValue + rightRealValue) * 0.5
            let monoImaginary = (leftImaginaryValue + rightImaginaryValue) * 0.5
            let sideReal = (leftRealValue - rightRealValue) * 0.5
            let sideImaginary = (leftImaginaryValue - rightImaginaryValue) * 0.5

            monoPower[index] = monoReal * monoReal + monoImaginary * monoImaginary
            monoRealSpectrum[index] = monoReal
            monoImaginarySpectrum[index] = monoImaginary
            leftPower[index] = leftRealValue * leftRealValue + leftImaginaryValue * leftImaginaryValue
            rightPower[index] = rightRealValue * rightRealValue + rightImaginaryValue * rightImaginaryValue
            crossReal[index] = leftRealValue * rightRealValue + leftImaginaryValue * rightImaginaryValue
            midEnergy += monoPower[index]
            sideEnergy += sideReal * sideReal + sideImaginary * sideImaginary
        }

        let totalPower = max(monoPower.reduce(0, +), numericalFloor)
        let normalizedPower = monoPower.map { $0 / totalPower }
        let magnitudeNormalization = sqrt(totalPower)
        let normalizedReal = monoRealSpectrum.map { $0 / magnitudeNormalization }
        let normalizedImaginary = monoImaginarySpectrum.map { $0 / magnitudeNormalization }
        let frequencyStep = sampleRate / Double(frameSize)
        let highBandEnergy = bandEnergy(
            power: normalizedPower,
            lowerHz: 6_000,
            upperHz: 18_000,
            frequencyStep: frequencyStep
        )
        let vocalCoreEnergy = bandEnergy(
            power: normalizedPower,
            lowerHz: 120,
            upperHz: 4_000,
            frequencyStep: frequencyStep
        )
        let lowMidBandEnergy = bandEnergy(
            power: normalizedPower,
            lowerHz: 80,
            upperHz: 1_000,
            frequencyStep: frequencyStep
        )
        let midHighBandEnergy = bandEnergy(
            power: normalizedPower,
            lowerHz: 1_000,
            upperHz: 8_000,
            frequencyStep: frequencyStep
        )
        let vocalConsonantActivity = positiveBandFlux(
            current: normalizedPower,
            previous: previousNormalizedPower ?? normalizedPower,
            lowerHz: 2_500,
            upperHz: 8_000,
            frequencyStep: frequencyStep
        )
        let vocalSibilanceEnergy = bandEnergy(
            power: normalizedPower,
            lowerHz: 5_500,
            upperHz: 10_000,
            frequencyStep: frequencyStep
        )
        let spectralFlux = zip(normalizedPower, previousNormalizedPower ?? normalizedPower)
            .reduce(0.0) { partial, pair in
                partial + max(0, pair.0 - pair.1)
            }
        let complexOnsetStrength: Double
        if let previousNormalizedReal,
           let previousNormalizedImaginary,
           previousNormalizedReal.count == normalizedReal.count,
           previousNormalizedImaginary.count == normalizedImaginary.count {
            complexOnsetStrength = normalizedReal.indices.reduce(0.0) { partial, index in
                let realDelta = normalizedReal[index] - previousNormalizedReal[index]
                let imaginaryDelta = normalizedImaginary[index] - previousNormalizedImaginary[index]
                return partial + hypot(realDelta, imaginaryDelta)
            }
        } else {
            complexOnsetStrength = 0
        }
        let entropyDenominator = log(Double(max(normalizedPower.count, 2)))
        let spectralEntropy = -normalizedPower.reduce(0.0) { partial, value in
            guard value > 0 else { return partial }
            return partial + value * log(value)
        } / entropyDenominator

        let mono = zip(left, right).map { (Double($0) + Double($1)) * 0.5 }
        let meanSquare = mono.reduce(0.0) { $0 + $1 * $1 } / Double(max(mono.count, 1))
        let rms = sqrt(max(meanSquare, numericalFloor))
        let peak = mono.reduce(0.0) { max($0, abs($1)) }
        let crestDecibels = 20 * log10(max(peak / rms, sqrt(numericalFloor)))

        let vocalsFundamental = fundamentalFrequency(
            power: monoPower,
            lowerHz: 70,
            upperHz: 500,
            frequencyStep: frequencyStep,
            previousFrequency: previousVocalsFundamental
        )
        let bassFundamental = fundamentalFrequency(
            power: monoPower,
            lowerHz: 30,
            upperHz: 300,
            frequencyStep: frequencyStep,
            previousFrequency: previousBassFundamental
        )

        let harmonicContinuity = previousNormalizedPower.map {
            spectralSimilarity(
                $0,
                normalizedPower,
                lowerHz: 70,
                upperHz: 6_000
            )
        } ?? 1

        return (FrameAnalysis(
            rms: rms,
            crestDecibels: crestDecibels,
            highBandEnergy: highBandEnergy,
            lowMidBandEnergy: lowMidBandEnergy,
            midHighBandEnergy: midHighBandEnergy,
            spectralFlux: spectralFlux,
            spectralEntropy: spectralEntropy,
            harmonicContinuity: harmonicContinuity,
            stereoSpatialBalance: sideEnergy / max(midEnergy + sideEnergy, numericalFloor),
            lowBandPhaseCoherence: phaseCoherence(
                leftPower: leftPower,
                rightPower: rightPower,
                crossReal: crossReal,
                lowerHz: 20,
                upperHz: 250,
                frequencyStep: frequencyStep
            ),
            vocalsFundamental: vocalsFundamental,
            vocalsHarmonicStrength: harmonicStrength(
                power: monoPower,
                fundamentalHz: vocalsFundamental,
                upperHz: 6_000,
                frequencyStep: frequencyStep
            ),
            vocalsBreathConsonantBalance: decibelBandRatio(
                power: monoPower,
                numeratorLowerHz: 4_000,
                numeratorUpperHz: 14_000,
                denominatorLowerHz: 120,
                denominatorUpperHz: 4_000,
                frequencyStep: frequencyStep
            ),
            vocalsFormantCenter: spectralEnvelopeCenter(
                power: monoPower,
                lowerHz: 300,
                upperHz: 4_000,
                frequencyStep: frequencyStep
            ),
            bassFundamental: bassFundamental,
            bassHarmonicStrength: harmonicStrength(
                power: monoPower,
                fundamentalHz: bassFundamental,
                upperHz: 1_200,
                frequencyStep: frequencyStep
            ),
            bassFiftyHertzPitchAlignment: pitchAlignment(
                targetHz: 50,
                fundamentalHz: bassFundamental,
                power: monoPower,
                frequencyStep: frequencyStep
            ),
            bassSixtyHertzPitchAlignment: pitchAlignment(
                targetHz: 60,
                fundamentalHz: bassFundamental,
                power: monoPower,
                frequencyStep: frequencyStep
            ),
            complexOnsetStrength: complexOnsetStrength,
            vocalCoreEnergy: vocalCoreEnergy,
            vocalConsonantActivity: vocalConsonantActivity,
            vocalSibilanceEnergy: vocalSibilanceEnergy,
            vocalBreathEnergy: highBandEnergy * max(0, 1 - harmonicStrength(
                power: monoPower,
                fundamentalHz: vocalsFundamental,
                upperHz: 6_000,
                frequencyStep: frequencyStep
            )),
            bassFundamentalEnergy: bandEnergy(
                power: normalizedPower,
                lowerHz: 30,
                upperHz: 300,
                frequencyStep: frequencyStep
            ),
            broadBandPhaseCoherence: phaseCoherence(
                leftPower: leftPower,
                rightPower: rightPower,
                crossReal: crossReal,
                lowerHz: 20,
                upperHz: 20_000,
                frequencyStep: frequencyStep
            )
        ), normalizedPower, normalizedReal, normalizedImaginary)
    }

    static func featureValues(
        role: StemRole,
        frames: [FrameAnalysis]
    ) -> [StemRoleAnalysisFeature: [Double]] {
        switch role {
        case .vocals:
            return [
                .vocalsVoicedHarmonicStrength: frames.map(\.vocalsHarmonicStrength),
                .vocalsBreathConsonantBalance: frames.map(\.vocalsBreathConsonantBalance),
                .vocalsFormantCenter: frames.map(\.vocalsFormantCenter),
                .vocalsHarmonicContinuity: frames.map(\.harmonicContinuity)
            ]
        case .drums:
            let cymbalDecay = decayContinuityProfile(frames.map(\.highBandEnergy))
            let medianRMS = percentile(frames.map(\.rms), probability: 0.5)
            let quietGapContrast = frames.map { frame in
                guard frame.rms <= medianRMS else { return 0.0 }
                return 20 * log10(max(medianRMS, numericalFloor) / max(frame.rms, numericalFloor))
            }
            return [
                .drumsOnsetStrength: frames.map(\.complexOnsetStrength),
                .drumsAttackCrest: frames.map(\.crestDecibels),
                .drumsCymbalDecayContinuity: cymbalDecay,
                .drumsQuietGapContrast: quietGapContrast
            ]
        case .bass:
            return [
                .bassFundamentalHarmonicStrength: frames.map(\.bassHarmonicStrength),
                .bassFiftyHertzPitchAlignment: frames.map(\.bassFiftyHertzPitchAlignment),
                .bassSixtyHertzPitchAlignment: frames.map(\.bassSixtyHertzPitchAlignment),
                .bassLowBandPhaseCoherence: frames.map(\.lowBandPhaseCoherence)
            ]
        case .other:
            let ambience = decayContinuityProfile(frames.map(\.rms))
            return [
                .otherPolyphonicSpectralSpread: frames.map(\.spectralEntropy),
                .otherTransientStrength: frames.map(\.spectralFlux),
                .otherAmbienceContinuity: ambience,
                .otherStereoSpatialBalance: frames.map(\.stereoSpatialBalance)
            ]
        }
    }

    static func makeProtectionProfile(
        role: StemRole,
        analysisSignal: AudioSignal,
        analyzed: AnalyzedFrames
    ) throws -> StemRoleProtectionProfile {
        let values = protectionValues(role: role, frames: analyzed.frames)
        let expectedComponents = StemRoleProtectedComponent.allCases.filter { $0.role == role }
        guard Set(values.keys) == Set(expectedComponents) else {
            throw StemRoleAnalysisError.unableToProduceProtectionProfile(role)
        }
        for component in expectedComponents {
            guard let componentValues = values[component],
                  componentValues.count == analyzed.frames.count,
                  componentValues.allSatisfy(\.isFinite) else {
                throw StemRoleAnalysisError.unableToProduceProtectionProfile(role)
            }
        }

        let protectionFrames = analyzed.frames.indices.map { index in
            StemRoleProtectionFrame(
                startFrame: analyzed.starts[index],
                validFrameCount: analyzed.validFrameCounts[index],
                values: Dictionary(uniqueKeysWithValues: expectedComponents.map { component in
                    (component, values[component]![index])
                })
            )
        }
        return StemRoleProtectionProfile(
            role: role,
            sampleRate: analysisSignal.sampleRate,
            signalFrameCount: analysisSignal.frameCount,
            analysisFrameSize: frameSize,
            hopSize: hopSize,
            frames: protectionFrames
        )
    }

    static func protectionValues(
        role: StemRole,
        frames: [FrameAnalysis]
    ) -> [StemRoleProtectedComponent: [Double]] {
        switch role {
        case .vocals:
            let breath = frames.map { $0.vocalBreathEnergy * $0.rms }
            let consonants = frames.map { $0.vocalConsonantActivity * $0.rms }
            let sibilance = frames.map { $0.vocalSibilanceEnergy * $0.rms }
            let formant = frames.map(\.vocalsFormantCenter)
            let harmonics = frames.map { $0.vocalsHarmonicStrength * $0.rms }
            let core = frames.map { $0.vocalCoreEnergy * $0.rms }
            return [
                .vocalsBreath: breath,
                .vocalsConsonants: consonants,
                .vocalsSibilance: sibilance,
                .vocalsFormant: formant,
                .vocalsHarmonics: harmonics,
                .vocalsCore: core,
            ]
        case .drums:
            let attack = frames.map { pow(10, $0.crestDecibels / 20) * $0.rms }
            let transient = frames.map { $0.complexOnsetStrength * $0.rms }
            let decay = decayContinuityProfile(frames.map(\.highBandEnergy))
            let cymbalDecay = zip(decay, frames).map { decayValue, frame in
                decayValue * sqrt(max(frame.highBandEnergy, 0)) * frame.rms
            }
            return [
                .drumsAttack: attack,
                .drumsTransient: transient,
                .drumsCymbalDecay: cymbalDecay,
            ]
        case .bass:
            let fundamental = frames.map { $0.bassFundamentalEnergy * $0.rms }
            let harmonics = frames.map { $0.bassHarmonicStrength * $0.rms }
            let mainsPitch = frames.map { frame in
                max(frame.bassFiftyHertzPitchAlignment, frame.bassSixtyHertzPitchAlignment)
                    * frame.rms
            }
            let phase = frames.map(\.lowBandPhaseCoherence)
            return [
                .bassFundamental: fundamental,
                .bassHarmonics: harmonics,
                .bassMainsRegionPitchContent: mainsPitch,
                .bassLowPhase: phase,
            ]
        case .other:
            let rmsDecay = decayContinuityProfile(frames.map(\.rms))
            let lowMidDecay = decayContinuityProfile(frames.map(\.lowMidBandEnergy))
            let midHighDecay = decayContinuityProfile(frames.map(\.midHighBandEnergy))
            let bandedDecay = frames.indices.map { index in
                (rmsDecay[index] + lowMidDecay[index] + midHighDecay[index]) / 3
            }
            let reverb = zip(bandedDecay, frames).map { $0 * $1.rms }
            let ambience = frames.map { $0.harmonicContinuity * $0.rms }
            let space = frames.map(\.stereoSpatialBalance)
            let stereo = frames.map(\.broadBandPhaseCoherence)
            return [
                .otherReverb: reverb,
                .otherAmbience: ambience,
                .otherSpace: space,
                .otherStereo: stereo,
            ]
        }
    }

    static func featureDefinitions(for role: StemRole) -> [FeatureDefinition] {
        switch role {
        case .vocals:
            [
                .init(feature: .vocalsVoicedHarmonicStrength, rule: .preserveMinimum, unit: .ratio),
                .init(feature: .vocalsBreathConsonantBalance, rule: .preserveMinimum, unit: .decibels),
                .init(feature: .vocalsFormantCenter, rule: .preserveStability, unit: .hertz),
                .init(feature: .vocalsHarmonicContinuity, rule: .preserveMinimum, unit: .normalized)
            ]
        case .drums:
            [
                .init(feature: .drumsOnsetStrength, rule: .preserveMinimum, unit: .ratio),
                .init(feature: .drumsAttackCrest, rule: .preserveMinimum, unit: .decibels),
                .init(feature: .drumsCymbalDecayContinuity, rule: .preserveMinimum, unit: .normalized),
                .init(feature: .drumsQuietGapContrast, rule: .preserveMinimum, unit: .decibels)
            ]
        case .bass:
            [
                .init(feature: .bassFundamentalHarmonicStrength, rule: .preserveMinimum, unit: .ratio),
                .init(feature: .bassFiftyHertzPitchAlignment, rule: .preserveStability, unit: .normalized),
                .init(feature: .bassSixtyHertzPitchAlignment, rule: .preserveStability, unit: .normalized),
                .init(feature: .bassLowBandPhaseCoherence, rule: .preserveMinimum, unit: .normalized)
            ]
        case .other:
            [
                .init(feature: .otherPolyphonicSpectralSpread, rule: .preserveStability, unit: .normalized),
                .init(feature: .otherTransientStrength, rule: .preserveMinimum, unit: .ratio),
                .init(feature: .otherAmbienceContinuity, rule: .preserveMinimum, unit: .normalized),
                .init(feature: .otherStereoSpatialBalance, rule: .preserveStability, unit: .normalized)
            ]
        }
    }

    static func frameStarts(frameCount: Int) -> [Int] {
        guard frameCount > frameSize else { return [0] }
        var starts = Array(stride(from: 0, through: frameCount - frameSize, by: hopSize))
        let lastStart = frameCount - frameSize
        if starts.last != lastStart {
            starts.append(lastStart)
        }
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

    static func bandEnergy(
        power: [Double],
        lowerHz: Double,
        upperHz: Double,
        frequencyStep: Double
    ) -> Double {
        let range = binRange(
            lowerHz: lowerHz,
            upperHz: upperHz,
            frequencyStep: frequencyStep,
            binCount: power.count
        )
        return power[range].reduce(0, +)
    }

    static func decibelBandRatio(
        power: [Double],
        numeratorLowerHz: Double,
        numeratorUpperHz: Double,
        denominatorLowerHz: Double,
        denominatorUpperHz: Double,
        frequencyStep: Double
    ) -> Double {
        let numerator = bandEnergy(
            power: power,
            lowerHz: numeratorLowerHz,
            upperHz: numeratorUpperHz,
            frequencyStep: frequencyStep
        )
        let denominator = bandEnergy(
            power: power,
            lowerHz: denominatorLowerHz,
            upperHz: denominatorUpperHz,
            frequencyStep: frequencyStep
        )
        return 10 * log10(max(numerator, numericalFloor) / max(denominator, numericalFloor))
    }

    static func positiveBandFlux(
        current: [Double],
        previous: [Double],
        lowerHz: Double,
        upperHz: Double,
        frequencyStep: Double
    ) -> Double {
        let range = binRange(
            lowerHz: lowerHz,
            upperHz: upperHz,
            frequencyStep: frequencyStep,
            binCount: min(current.count, previous.count)
        )
        return range.reduce(0.0) { partial, index in
            partial + max(0, current[index] - previous[index])
        }
    }

    static func fundamentalFrequency(
        power: [Double],
        lowerHz: Double,
        upperHz: Double,
        frequencyStep: Double,
        previousFrequency: Double?
    ) -> Double {
        let range = binRange(
            lowerHz: lowerHz,
            upperHz: upperHz,
            frequencyStep: frequencyStep,
            binCount: power.count
        )
        var bestBin: Int?
        var bestScore = 0.0
        for candidate in range {
            let candidateFrequency = Double(candidate) * frequencyStep
            var harmonicScore = 0.0
            var harmonic = 1
            while candidate * harmonic < power.count {
                let center = candidate * harmonic
                let local = power[max(1, center - 1)...min(power.count - 1, center + 1)].reduce(0, +)
                harmonicScore += local / Double(harmonic)
                harmonic += 1
            }
            if let previousFrequency, previousFrequency > 0 {
                let octaveDistance = abs(log2(candidateFrequency / previousFrequency))
                harmonicScore /= 1 + octaveDistance
            }
            if harmonicScore > bestScore {
                bestScore = harmonicScore
                bestBin = candidate
            }
        }
        guard let bestBin, bestScore > numericalFloor else {
            return 0
        }
        return Double(bestBin) * frequencyStep
    }

    static func harmonicStrength(
        power: [Double],
        fundamentalHz: Double,
        upperHz: Double,
        frequencyStep: Double
    ) -> Double {
        guard fundamentalHz > 0 else { return 0 }
        let upperBin = min(power.count - 1, Int(floor(upperHz / frequencyStep)))
        let total = power[1...upperBin].reduce(0, +)
        guard total > numericalFloor else { return 0 }

        var harmonicPower = 0.0
        var harmonic = 1
        while Double(harmonic) * fundamentalHz <= upperHz {
            let center = Int(round(Double(harmonic) * fundamentalHz / frequencyStep))
            let lower = max(1, center - 1)
            let upper = min(upperBin, center + 1)
            harmonicPower += power[lower...upper].reduce(0, +)
            harmonic += 1
        }
        return min(1, harmonicPower / total)
    }

    static func spectralCenter(
        power: [Double],
        lowerHz: Double,
        upperHz: Double,
        frequencyStep: Double
    ) -> Double {
        let range = binRange(
            lowerHz: lowerHz,
            upperHz: upperHz,
            frequencyStep: frequencyStep,
            binCount: power.count
        )
        let total = max(power[range].reduce(0, +), numericalFloor)
        return range.reduce(0.0) { partial, index in
            partial + Double(index) * frequencyStep * power[index]
        } / total
    }

    /// 周波数binそのものではなく、対数powerを平滑化したスペクトル包絡の重心を返します。
    /// これは声道共鳴の時間変化を追うための量で、曲全体の単一重心は使用しません。
    static func spectralEnvelopeCenter(
        power: [Double],
        lowerHz: Double,
        upperHz: Double,
        frequencyStep: Double
    ) -> Double {
        let range = binRange(
            lowerHz: lowerHz,
            upperHz: upperHz,
            frequencyStep: frequencyStep,
            binCount: power.count
        )
        let smoothingRadius = max(1, Int(round(100 / frequencyStep)))
        var envelope: [(index: Int, value: Double)] = []
        envelope.reserveCapacity(range.count)
        for index in range {
            let lower = max(range.lowerBound, index - smoothingRadius)
            let upper = min(range.upperBound - 1, index + smoothingRadius)
            let meanLogPower = power[lower...upper].reduce(0.0) {
                $0 + log(max($1, numericalFloor))
            } / Double(upper - lower + 1)
            envelope.append((index, exp(meanLogPower)))
        }
        let total = max(envelope.reduce(0.0) { $0 + $1.value }, numericalFloor)
        return envelope.reduce(0.0) {
            $0 + Double($1.index) * frequencyStep * $1.value
        } / total
    }

    static func phaseCoherence(
        leftPower: [Double],
        rightPower: [Double],
        crossReal: [Double],
        lowerHz: Double,
        upperHz: Double,
        frequencyStep: Double
    ) -> Double {
        let range = binRange(
            lowerHz: lowerHz,
            upperHz: upperHz,
            frequencyStep: frequencyStep,
            binCount: leftPower.count
        )
        let left = leftPower[range].reduce(0, +)
        let right = rightPower[range].reduce(0, +)
        let cross = crossReal[range].reduce(0, +)
        guard left > numericalFloor, right > numericalFloor else { return 1 }
        return max(-1, min(1, cross / sqrt(left * right)))
    }

    static func pitchAlignment(
        targetHz: Double,
        fundamentalHz: Double,
        power: [Double],
        frequencyStep: Double
    ) -> Double {
        guard fundamentalHz > 0 else { return 0 }
        let harmonicNumber = max(1, Int(round(targetHz / fundamentalHz)))
        let harmonicHz = Double(harmonicNumber) * fundamentalHz
        let normalizedDistance = abs(targetHz - harmonicHz) / max(fundamentalHz * 0.5, frequencyStep)
        let pitchCloseness = max(0, 1 - normalizedDistance)
        let targetBin = min(power.count - 1, max(0, Int(round(targetHz / frequencyStep))))
        let bassRange = binRange(
            lowerHz: 20,
            upperHz: 300,
            frequencyStep: frequencyStep,
            binCount: power.count
        )
        let strongestBassBinPower = bassRange.map { power[$0] }.max() ?? 0
        let targetPower = power[max(0, targetBin - 1)...min(power.count - 1, targetBin + 1)].reduce(0, +)
        let spectralEvidence = min(1, targetPower / max(strongestBassBinPower, numericalFloor))
        return pitchCloseness * spectralEvidence
    }

    static func spectralSimilarity(
        _ lhs: [Double],
        _ rhs: [Double],
        lowerHz: Double,
        upperHz: Double
    ) -> Double {
        let frequencyStep = processingSampleRate / Double(frameSize)
        let range = binRange(
            lowerHz: lowerHz,
            upperHz: upperHz,
            frequencyStep: frequencyStep,
            binCount: min(lhs.count, rhs.count)
        )
        var dot = 0.0
        var lhsEnergy = 0.0
        var rhsEnergy = 0.0
        for index in range {
            dot += lhs[index] * rhs[index]
            lhsEnergy += lhs[index] * lhs[index]
            rhsEnergy += rhs[index] * rhs[index]
        }
        guard lhsEnergy > numericalFloor, rhsEnergy > numericalFloor else { return 1 }
        return max(0, min(1, dot / sqrt(lhsEnergy * rhsEnergy)))
    }

    static func adjacentValues(
        _ frames: [FrameAnalysis],
        transform: (FrameAnalysis, FrameAnalysis) -> Double
    ) -> [Double] {
        guard frames.count > 1 else { return [1] }
        return zip(frames, frames.dropFirst()).map(transform)
    }

    static func descendingContinuity(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return [1] }
        let descending = zip(values, values.dropFirst()).compactMap { previous, current -> Double? in
            guard current <= previous else { return nil }
            let denominator = max(previous, current, numericalFloor)
            return min(previous, current) / denominator
        }
        return descending.isEmpty ? [1] : descending
    }

    static func descendingContinuityAligned(_ values: [Double]) -> [Double] {
        guard values.count > 1 else { return [1] }
        return [1] + zip(values, values.dropFirst()).map { previous, current in
            guard current <= previous else { return 0 }
            return min(previous, current) / max(previous, current, numericalFloor)
        }
    }

    /// 短い時間窓の対数energyへ最小二乗直線を当て、減衰尾の連続性を追跡します。
    /// 固定の合否閾値は持たず、各入力自身の時系列値としてguardへ渡します。
    static func decayContinuityProfile(_ values: [Double]) -> [Double] {
        guard !values.isEmpty else { return [] }
        return values.indices.map { start in
            let end = min(values.count, start + 4)
            let window = values[start..<end].map { log(max($0, numericalFloor)) }
            guard window.count > 1 else { return 1 }
            let meanX = Double(window.count - 1) * 0.5
            let meanY = window.reduce(0, +) / Double(window.count)
            var numerator = 0.0
            var denominator = 0.0
            for (offset, value) in window.enumerated() {
                let centeredX = Double(offset) - meanX
                numerator += centeredX * (value - meanY)
                denominator += centeredX * centeredX
            }
            guard denominator > 0 else { return 1 }
            let slope = numerator / denominator
            return slope < 0 ? exp(slope) : 0
        }
    }

    static func percentile(_ values: [Double], probability: Double) -> Double {
        let sorted = values.sorted()
        guard let first = sorted.first else { return 0 }
        guard sorted.count > 1 else { return first }
        let position = max(0, min(1, probability)) * Double(sorted.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else { return sorted[lowerIndex] }
        let fraction = position - Double(lowerIndex)
        return sorted[lowerIndex] + (sorted[upperIndex] - sorted[lowerIndex]) * fraction
    }

    static func binRange(
        lowerHz: Double,
        upperHz: Double,
        frequencyStep: Double,
        binCount: Int
    ) -> Range<Int> {
        let lower = min(binCount - 1, max(0, Int(floor(lowerHz / frequencyStep))))
        let upperExclusive = min(binCount, max(lower + 1, Int(ceil(upperHz / frequencyStep))))
        return lower..<upperExclusive
    }

    static func uniqueFeature(
        _ feature: StemRoleAnalysisFeature,
        in features: [StemRoleFeatureDistribution]
    ) -> StemRoleFeatureDistribution? {
        let matches = features.filter { $0.feature == feature }
        return matches.count == 1 ? matches[0] : nil
    }

    static func isValidDistribution(_ distribution: StemRoleFeatureDistribution) -> Bool {
        distribution.frameCount > 0
            && distribution.firstQuartile.isFinite
            && distribution.median.isFinite
            && distribution.thirdQuartile.isFinite
            && distribution.interquartileRange.isFinite
            && distribution.firstQuartile <= distribution.median
            && distribution.median <= distribution.thirdQuartile
            && distribution.interquartileRange >= 0
    }
}
