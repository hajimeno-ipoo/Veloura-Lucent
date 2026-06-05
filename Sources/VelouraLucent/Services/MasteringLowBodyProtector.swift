import Foundation

enum MasteringLowBodyProtector {
    private static let minimumActiveFrameRatio: Float = 1.25
    private static let sustainedMusicFloorDB = -36.0
    private static let activeLowMidBodyLiftDB: Float = 0.5
    private static let activeLowMidBodyMaxDropDB = 0.05
    private static let activeLowMidBodyLowerFrequency = 150.0
    private static let activeLowMidBodyUpperFrequency = 500.0

    private struct ReferenceBand: Hashable {
        let startBin: Int
        let endBin: Int
    }

    private struct ReferenceFrameData {
        let frameCount: Int
        let frameAverageMagnitudes: [Float]?
        let frameBandLevelsDB: [[Double]]
        let bandLevelsDB: [Double]
    }

    static func process(
        signal: AudioSignal,
        reference: AudioSignal,
        activityReference: AudioSignal? = nil,
        musicalReference: AudioSignal? = nil
    ) -> AudioSignal {
        let channelCount = signal.channels.count
        let activitySignal = activityReference ?? reference
        let lowBodyReference = musicalReference ?? reference
        guard channelCount > 0,
              channelCount == reference.channels.count,
              channelCount == activitySignal.channels.count,
              channelCount == lowBodyReference.channels.count,
              signal.sampleRate == reference.sampleRate,
              signal.sampleRate == activitySignal.sampleRate,
              signal.sampleRate == lowBodyReference.sampleRate
        else { return signal }

        var didChange = false
        let channels = (0..<channelCount).map { channelIndex in
            let result = process(
                channel: signal.channels[channelIndex],
                correctedReference: reference.channels[channelIndex],
                lowBodyReference: lowBodyReference.channels[channelIndex],
                activityReference: activitySignal.channels[channelIndex],
                usesSeparateActivityReference: activityReference != nil,
                usesSeparateLowBodyReference: musicalReference != nil,
                sampleRate: signal.sampleRate
            )
            didChange = didChange || result.didChange
            return result.channel
        }
        guard didChange else { return signal }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    static func protectActiveLowMidMinimum(
        signal: AudioSignal,
        activityReference: AudioSignal
    ) -> AudioSignal? {
        let channelCount = signal.channels.count
        guard channelCount > 0,
              channelCount == activityReference.channels.count,
              signal.sampleRate == activityReference.sampleRate
        else { return nil }

        var didChange = false
        let channels = (0..<channelCount).map { channelIndex in
            let result = protectActiveLowMidMinimum(
                channel: signal.channels[channelIndex],
                activityReference: activityReference.channels[channelIndex],
                sampleRate: signal.sampleRate
            )
            didChange = didChange || result.didChange
            return result.channel
        }
        guard didChange else { return nil }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private static func process(
        channel: [Float],
        correctedReference: [Float],
        lowBodyReference: [Float],
        activityReference: [Float],
        usesSeparateActivityReference: Bool,
        usesSeparateLowBodyReference: Bool,
        sampleRate: Double
    ) -> (channel: [Float], didChange: Bool) {
        guard !channel.isEmpty,
              channel.count == correctedReference.count,
              channel.count == lowBodyReference.count
        else {
            return (channel, false)
        }
        let activityChannel = activityReference
        guard activityChannel.count == channel.count else {
            return (channel, false)
        }

        var currentSpectrogram = SpectralDSP.stft(channel)
        let frequencyStep = sampleRate / Double(currentSpectrogram.fftSize)
        let activeLowMidBand = ReferenceBand(
            startBin: max(1, Int(activeLowMidBodyLowerFrequency / frequencyStep)),
            endBin: min(currentSpectrogram.binCount - 1, Int(activeLowMidBodyUpperFrequency / frequencyStep))
        )
        let rules: [(band: ReferenceBand, maxDropDB: Double, maxBoostDB: Double)] = [
            (
                ReferenceBand(
                    startBin: max(1, Int(20 / frequencyStep)),
                    endBin: min(currentSpectrogram.binCount - 1, Int(60 / frequencyStep))
                ),
                0.15,
                0.80
            ),
            (
                ReferenceBand(
                    startBin: max(1, Int(60 / frequencyStep)),
                    endBin: min(currentSpectrogram.binCount - 1, Int(150 / frequencyStep))
                ),
                -0.35,
                1.20
            ),
            (
                ReferenceBand(
                    startBin: max(1, Int(150 / frequencyStep)),
                    endBin: min(currentSpectrogram.binCount - 1, Int(300 / frequencyStep))
                ),
                0.05,
                0.90
            ),
            (
                ReferenceBand(
                    startBin: max(1, Int(300 / frequencyStep)),
                    endBin: min(currentSpectrogram.binCount - 1, Int(1_000 / frequencyStep))
                ),
                0.10,
                0.65
            )
        ]
        let correctedReferenceBands = usesSeparateLowBodyReference ? [activeLowMidBand] : [activeLowMidBand] + rules.map(\.band)
        let correctedReferenceData = referenceFrameData(
            for: correctedReference,
            bands: correctedReferenceBands,
            includesFrameAverageMagnitudes: !usesSeparateActivityReference
        )
        let sharedLowBodyActivityData = usesSeparateLowBodyReference
            && usesSeparateActivityReference
            && sharesStorage(lowBodyReference, activityChannel)
            ? referenceFrameData(
                for: lowBodyReference,
                bands: rules.map(\.band),
                includesFrameAverageMagnitudes: true
            )
            : nil
        let lowBodyReferenceData = sharedLowBodyActivityData
            ?? (usesSeparateLowBodyReference
                ? referenceFrameData(
                    for: lowBodyReference,
                    bands: rules.map(\.band),
                    includesFrameAverageMagnitudes: false
                )
                : correctedReferenceData)
        let lowBodyRuleLevelOffset = usesSeparateLowBodyReference ? 0 : 1
        let activityReferenceData = sharedLowBodyActivityData
            ?? (usesSeparateActivityReference
                ? referenceFrameData(
                    for: activityChannel,
                    bands: [],
                    includesFrameAverageMagnitudes: true
                )
                : correctedReferenceData)
        let frameCount = min(
            min(currentSpectrogram.frameCount, activityReferenceData.frameCount),
            min(correctedReferenceData.frameCount, lowBodyReferenceData.frameCount)
        )
        guard frameCount > 0 else {
            return (channel, false)
        }

        let activityFrameEnergy = activityReferenceData.frameAverageMagnitudes ?? []
        let quietThreshold = SpectralDSP.percentile(activityFrameEnergy, 20)
        let activeThreshold = SpectralDSP.percentile(activityFrameEnergy, 35)
        let hasDynamicActivity = activeThreshold > quietThreshold * minimumActiveFrameRatio
        let hasSustainedActivity = rootMeanSquareDB(activityChannel) > sustainedMusicFloorDB
        guard hasDynamicActivity || hasSustainedActivity else {
            return (channel, false)
        }

        var didChange = false
        for frameIndex in 0..<frameCount {
            guard activityFrameEnergy[frameIndex] >= activeThreshold,
                  hasSustainedActivity || activityFrameEnergy[frameIndex] > quietThreshold * minimumActiveFrameRatio
            else { continue }

            if applyActiveLowMidBodyLift(
                to: &currentSpectrogram,
                referenceLevelDB: correctedReferenceData.frameBandLevelsDB[0][frameIndex],
                frameIndex: frameIndex,
                frequencyStep: frequencyStep
            ) {
                didChange = true
            }

            for (ruleIndex, rule) in rules.enumerated() {
                guard rule.band.endBin >= rule.band.startBin else { continue }

                let currentLevelDB = frameBandLevelDB(
                    currentSpectrogram,
                    frameIndex: frameIndex,
                    startBin: rule.band.startBin,
                    endBin: rule.band.endBin
                )
                let referenceLevelDB = lowBodyReferenceData.frameBandLevelsDB[lowBodyRuleLevelOffset + ruleIndex][frameIndex]
                let dropDB = referenceLevelDB - currentLevelDB
                guard dropDB > rule.maxDropDB else { continue }

                let boostDB = min(dropDB - rule.maxDropDB, rule.maxBoostDB)
                let gain = powf(10, Float(boostDB) / 20)
                for binIndex in rule.band.startBin...rule.band.endBin {
                    currentSpectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
                }
                didChange = true
            }
        }

        guard didChange else {
            return (channel, false)
        }
        return (SpectralDSP.istft(currentSpectrogram), true)
    }

    private static func applyActiveLowMidBodyLift(
        to spectrogram: inout Spectrogram,
        referenceLevelDB: Double,
        frameIndex: Int,
        frequencyStep: Double
    ) -> Bool {
        let startBin = max(1, Int(activeLowMidBodyLowerFrequency / frequencyStep))
        let endBin = min(spectrogram.binCount - 1, Int(activeLowMidBodyUpperFrequency / frequencyStep))
        guard endBin >= startBin else { return false }

        let currentLevelDB = frameBandLevelDB(
            spectrogram,
            frameIndex: frameIndex,
            startBin: startBin,
            endBin: endBin
        )
        let dropDB = referenceLevelDB - currentLevelDB
        guard dropDB > activeLowMidBodyMaxDropDB else { return false }

        let boostDB = min(dropDB - activeLowMidBodyMaxDropDB, Double(activeLowMidBodyLiftDB))
        let gain = powf(10, Float(boostDB) / 20)
        for binIndex in startBin...endBin {
            spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
        }
        return true
    }

    private static func protectActiveLowMidMinimum(
        channel: [Float],
        activityReference: [Float],
        sampleRate: Double
    ) -> (channel: [Float], didChange: Bool) {
        guard !channel.isEmpty, channel.count == activityReference.count else {
            return (channel, false)
        }

        var spectrogram = SpectralDSP.stft(channel)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let activeLowMidBand = ReferenceBand(
            startBin: max(1, Int(activeLowMidBodyLowerFrequency / frequencyStep)),
            endBin: min(spectrogram.binCount - 1, Int(activeLowMidBodyUpperFrequency / frequencyStep))
        )
        let activityReferenceData = referenceFrameData(
            for: activityReference,
            bands: [activeLowMidBand],
            includesFrameAverageMagnitudes: true
        )
        let frameCount = min(spectrogram.frameCount, activityReferenceData.frameCount)
        guard frameCount > 0 else {
            return (channel, false)
        }

        let frameEnergy = activityReferenceData.frameAverageMagnitudes ?? []
        let quietThreshold = SpectralDSP.percentile(frameEnergy, 20)
        let activeThreshold = SpectralDSP.percentile(frameEnergy, 35)
        let hasDynamicActivity = activeThreshold > quietThreshold * minimumActiveFrameRatio
        let hasSustainedActivity = rootMeanSquareDB(activityReference) > sustainedMusicFloorDB
        guard hasDynamicActivity || hasSustainedActivity else {
            return (channel, false)
        }

        guard activeLowMidBand.endBin >= activeLowMidBand.startBin else {
            return (channel, false)
        }
        let currentLevelDB = bandLevelDB(
            spectrogram,
            startBin: activeLowMidBand.startBin,
            endBin: activeLowMidBand.endBin
        )
        let referenceLevelDB = activityReferenceData.bandLevelsDB[0]
        guard referenceLevelDB - currentLevelDB > activeLowMidBodyMaxDropDB else {
            return (channel, false)
        }

        let gain = powf(10, activeLowMidBodyLiftDB / 20)
        var didChange = false
        for frameIndex in 0..<frameCount {
            guard frameEnergy[frameIndex] >= activeThreshold,
                  hasSustainedActivity || frameEnergy[frameIndex] > quietThreshold * minimumActiveFrameRatio
            else { continue }
            for binIndex in activeLowMidBand.startBin...activeLowMidBand.endBin {
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
            }
            didChange = true
        }

        guard didChange else {
            return (channel, false)
        }
        return (SpectralDSP.istft(spectrogram), true)
    }

    private static func bandLevelDB(
        _ spectrogram: Spectrogram,
        startBin: Int,
        endBin: Int
    ) -> Double {
        guard spectrogram.frameCount > 0, endBin >= startBin else { return -120 }

        var sumSquares = 0.0
        for frameIndex in 0..<spectrogram.frameCount {
            for binIndex in startBin...endBin {
                let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
                sumSquares += Double(magnitude * magnitude)
            }
        }

        return 10 * log10(
            max(sumSquares / Double(spectrogram.frameCount * (endBin - startBin + 1)), 1e-12)
        )
    }

    private static func frameBandLevelDB(
        _ spectrogram: Spectrogram,
        frameIndex: Int,
        startBin: Int,
        endBin: Int
    ) -> Double {
        guard endBin >= startBin else { return -120 }

        var sumSquares = 0.0
        for binIndex in startBin...endBin {
            let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            sumSquares += Double(magnitude * magnitude)
        }

        return 10 * log10(max(sumSquares / Double(endBin - startBin + 1), 1e-12))
    }

    private static func referenceFrameData(
        for signal: [Float],
        bands: [ReferenceBand],
        includesFrameAverageMagnitudes: Bool
    ) -> ReferenceFrameData {
        var frameCount = 0
        var frameAverageMagnitudes = includesFrameAverageMagnitudes ? [Float]() : nil
        var frameBandLevels = bands.map { _ in [Double]() }
        var bandSumSquares = Array(repeating: 0.0, count: bands.count)

        SpectralDSP.forEachSTFTFrame(signal) { _, binCount, real, imag in
            if includesFrameAverageMagnitudes {
                var sum: Float = 0
                for binIndex in 0..<binCount {
                    sum += hypotf(real[binIndex], imag[binIndex])
                }
                frameAverageMagnitudes?.append(sum / Float(binCount))
            }

            for (bandIndex, band) in bands.enumerated() {
                guard band.endBin >= band.startBin else {
                    frameBandLevels[bandIndex].append(-120)
                    continue
                }

                var sumSquares = 0.0
                for binIndex in band.startBin...band.endBin {
                    let magnitude = hypotf(real[binIndex], imag[binIndex])
                    sumSquares += Double(magnitude * magnitude)
                }
                bandSumSquares[bandIndex] += sumSquares
                frameBandLevels[bandIndex].append(
                    10 * log10(max(sumSquares / Double(band.endBin - band.startBin + 1), 1e-12))
                )
            }

            frameCount += 1
        }

        let bandLevels = bands.enumerated().map { bandIndex, band in
            guard frameCount > 0, band.endBin >= band.startBin else {
                return -120.0
            }
            return 10 * log10(
                max(bandSumSquares[bandIndex] / Double(frameCount * (band.endBin - band.startBin + 1)), 1e-12)
            )
        }

        return ReferenceFrameData(
            frameCount: frameCount,
            frameAverageMagnitudes: frameAverageMagnitudes,
            frameBandLevelsDB: frameBandLevels,
            bandLevelsDB: bandLevels
        )
    }

    private static func sharesStorage(_ lhs: [Float], _ rhs: [Float]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return lhs.withUnsafeBufferPointer { lhsBuffer in
            rhs.withUnsafeBufferPointer { rhsBuffer in
                lhsBuffer.baseAddress == rhsBuffer.baseAddress
            }
        }
    }

    private static func rootMeanSquareDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        return 10 * log10(max(meanSquare, 1e-12))
    }
}
