import Foundation

enum MasteringLowBodyProtector {
    private static let minimumActiveFrameRatio: Float = 1.25
    private static let sustainedMusicFloorDB = -36.0
    private static let activeLowMidBodyLiftDB: Float = 0.5
    private static let activeLowMidBodyMaxDropDB = 0.05
    private static let activeLowMidBodyLowerFrequency = 150.0
    private static let activeLowMidBodyUpperFrequency = 500.0

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
        let correctedReferenceSpectrogram = SpectralDSP.stft(correctedReference)
        let lowBodyReferenceSpectrogram = usesSeparateLowBodyReference
            ? SpectralDSP.stft(lowBodyReference)
            : correctedReferenceSpectrogram
        let activitySpectrogram = usesSeparateActivityReference ? SpectralDSP.stft(activityChannel) : correctedReferenceSpectrogram
        let frameCount = min(
            min(currentSpectrogram.frameCount, activitySpectrogram.frameCount),
            min(correctedReferenceSpectrogram.frameCount, lowBodyReferenceSpectrogram.frameCount)
        )
        guard frameCount > 0 else {
            return (channel, false)
        }

        let activityFrameEnergy = activitySpectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(activityFrameEnergy, 20)
        let activeThreshold = SpectralDSP.percentile(activityFrameEnergy, 35)
        let hasDynamicActivity = activeThreshold > quietThreshold * minimumActiveFrameRatio
        let hasSustainedActivity = rootMeanSquareDB(activityChannel) > sustainedMusicFloorDB
        guard hasDynamicActivity || hasSustainedActivity else {
            return (channel, false)
        }
        let frequencyStep = sampleRate / Double(currentSpectrogram.fftSize)
        let rules: [(lower: Double, upper: Double, maxDropDB: Double, maxBoostDB: Double)] = [
            (20, 60, 0.15, 0.80),
            (60, 150, -0.35, 1.20),
            (150, 300, 0.05, 0.90),
            (300, 1_000, 0.10, 0.65)
        ]

        var didChange = false
        for frameIndex in 0..<frameCount {
            guard activityFrameEnergy[frameIndex] >= activeThreshold,
                  hasSustainedActivity || activityFrameEnergy[frameIndex] > quietThreshold * minimumActiveFrameRatio
            else { continue }

            if applyActiveLowMidBodyLift(
                to: &currentSpectrogram,
                reference: correctedReferenceSpectrogram,
                frameIndex: frameIndex,
                frequencyStep: frequencyStep
            ) {
                didChange = true
            }

            for rule in rules {
                let startBin = max(1, Int(rule.lower / frequencyStep))
                let endBin = min(currentSpectrogram.binCount - 1, Int(rule.upper / frequencyStep))
                guard endBin >= startBin else { continue }

                let currentLevelDB = frameBandLevelDB(
                    currentSpectrogram,
                    frameIndex: frameIndex,
                    startBin: startBin,
                    endBin: endBin
                )
                let referenceLevelDB = frameBandLevelDB(
                    lowBodyReferenceSpectrogram,
                    frameIndex: frameIndex,
                    startBin: startBin,
                    endBin: endBin
                )
                let dropDB = referenceLevelDB - currentLevelDB
                guard dropDB > rule.maxDropDB else { continue }

                let boostDB = min(dropDB - rule.maxDropDB, rule.maxBoostDB)
                let gain = powf(10, Float(boostDB) / 20)
                for binIndex in startBin...endBin {
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
        reference: Spectrogram,
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
        let referenceLevelDB = frameBandLevelDB(
            reference,
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
        let activitySpectrogram = SpectralDSP.stft(activityReference)
        let frameCount = min(spectrogram.frameCount, activitySpectrogram.frameCount)
        guard frameCount > 0 else {
            return (channel, false)
        }

        let frameEnergy = activitySpectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(frameEnergy, 20)
        let activeThreshold = SpectralDSP.percentile(frameEnergy, 35)
        let hasDynamicActivity = activeThreshold > quietThreshold * minimumActiveFrameRatio
        let hasSustainedActivity = rootMeanSquareDB(activityReference) > sustainedMusicFloorDB
        guard hasDynamicActivity || hasSustainedActivity else {
            return (channel, false)
        }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let startBin = max(1, Int(activeLowMidBodyLowerFrequency / frequencyStep))
        let endBin = min(spectrogram.binCount - 1, Int(activeLowMidBodyUpperFrequency / frequencyStep))
        guard endBin >= startBin else {
            return (channel, false)
        }
        let currentLevelDB = bandLevelDB(spectrogram, startBin: startBin, endBin: endBin)
        let referenceLevelDB = bandLevelDB(activitySpectrogram, startBin: startBin, endBin: endBin)
        guard referenceLevelDB - currentLevelDB > activeLowMidBodyMaxDropDB else {
            return (channel, false)
        }

        let gain = powf(10, activeLowMidBodyLiftDB / 20)
        var didChange = false
        for frameIndex in 0..<frameCount {
            guard frameEnergy[frameIndex] >= activeThreshold,
                  hasSustainedActivity || frameEnergy[frameIndex] > quietThreshold * minimumActiveFrameRatio
            else { continue }
            for binIndex in startBin...endBin {
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

    private static func rootMeanSquareDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        let meanSquare = samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
        return 10 * log10(max(meanSquare, 1e-12))
    }
}
