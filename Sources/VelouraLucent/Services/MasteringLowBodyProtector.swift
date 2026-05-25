import Foundation

enum MasteringLowBodyProtector {
    private static let minimumActiveFrameRatio: Float = 1.25
    private static let sustainedMusicFloorDB = -36.0

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
                reference: lowBodyReference.channels[channelIndex],
                activityReference: activitySignal.channels[channelIndex],
                usesSeparateActivityReference: activityReference != nil,
                sampleRate: signal.sampleRate
            )
            didChange = didChange || result.didChange
            return result.channel
        }
        guard didChange else { return signal }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private static func process(
        channel: [Float],
        reference: [Float],
        activityReference: [Float],
        usesSeparateActivityReference: Bool,
        sampleRate: Double
    ) -> (channel: [Float], didChange: Bool) {
        guard !channel.isEmpty, channel.count == reference.count else {
            return (channel, false)
        }
        let activityChannel = activityReference
        guard activityChannel.count == channel.count else {
            return (channel, false)
        }

        var currentSpectrogram = SpectralDSP.stft(channel)
        let referenceSpectrogram = SpectralDSP.stft(reference)
        let activitySpectrogram = usesSeparateActivityReference ? SpectralDSP.stft(activityChannel) : referenceSpectrogram
        let frameCount = min(currentSpectrogram.frameCount, referenceSpectrogram.frameCount)
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
                    referenceSpectrogram,
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
