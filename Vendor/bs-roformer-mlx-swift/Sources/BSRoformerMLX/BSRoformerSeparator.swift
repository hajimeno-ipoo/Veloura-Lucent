import Foundation
import MLX

public final class BSRoformerSeparator {
    public typealias ProgressHandler = @Sendable (_ completedChunks: Int, _ totalChunks: Int) -> Void
    public typealias CancellationCheck = @Sendable () -> Bool

    public let model: BSRoformerModel

    public init(weightsURL: URL, configurationURL: URL) throws {
        let configuration = try BSRoformerConfiguration.load(from: configurationURL)
        self.model = try BSRoformerModel(
            weightsURL: weightsURL,
            configuration: configuration
        )
    }

    public func separate(
        _ audio: BSRoformerAudio,
        progress: ProgressHandler? = nil,
        isCancelled: CancellationCheck? = nil
    ) throws -> BSRoformerSeparation {
        let configuration = model.configuration
        guard audio.channels == configuration.channels else {
            throw BSRoformerError.invalidAudio("入力はステレオである必要があります")
        }
        guard audio.sampleRate == configuration.sampleRate else {
            throw BSRoformerError.invalidAudio("入力は44.1kHzである必要があります")
        }
        guard audio.frameCount > configuration.stftFFTSize / 2 else {
            throw BSRoformerError.invalidAudio("入力音声が短すぎます")
        }

        let totalFrames = audio.frameCount
        let chunkFrames = configuration.chunkSampleCount(for: totalFrames)
        let starts = chunkStarts(
            totalFrames: totalFrames,
            chunkFrames: chunkFrames,
            stepFrames: configuration.stepSampleCount(for: chunkFrames)
        )
        let window = hammingWindow(length: min(chunkFrames, totalFrames))
        let stemCount = configuration.stemCount
        let channels = configuration.channels
        var accumulated = [Float](
            repeating: 0,
            count: stemCount * channels * totalFrames
        )
        var denominator = [Float](repeating: 0, count: totalFrames)

        for (chunkIndex, start) in starts.enumerated() {
            if isCancelled?() == true {
                throw BSRoformerError.cancelled
            }
            let validLength = min(chunkFrames, totalFrames - start)
            var chunk = [Float](repeating: 0, count: channels * validLength)
            for channel in 0..<channels {
                let sourceStart = channel * totalFrames + start
                let destinationStart = channel * validLength
                chunk[destinationStart..<(destinationStart + validLength)] =
                    audio.channelMajorSamples[sourceStart..<(sourceStart + validLength)]
            }

            let input = MLXArray(chunk, [1, channels, validLength])
            let output = try model(input)
            eval(output)
            let separated = output.asArray(Float.self)
            let appliedWindow = validLength == window.count
                ? window
                : hammingWindow(length: validLength)

            for sample in 0..<validLength {
                denominator[start + sample] += appliedWindow[sample]
            }
            for stem in 0..<stemCount {
                for channel in 0..<channels {
                    let sourceBase = (stem * channels + channel) * validLength
                    let destinationBase = (stem * channels + channel) * totalFrames + start
                    for sample in 0..<validLength {
                        accumulated[destinationBase + sample] +=
                            separated[sourceBase + sample] * appliedWindow[sample]
                    }
                }
            }
            progress?(chunkIndex + 1, starts.count)
        }

        for stem in 0..<stemCount {
            for channel in 0..<channels {
                let base = (stem * channels + channel) * totalFrames
                for sample in 0..<totalFrames {
                    accumulated[base + sample] /= max(denominator[sample], 1e-10)
                }
            }
        }

        var stems: [BSRoformerStem: BSRoformerAudio] = [:]
        for (stemIndex, name) in configuration.stemNames.enumerated() {
            guard let stem = BSRoformerStem(rawValue: name) else {
                throw BSRoformerError.invalidConfiguration("不明なステム名です: \(name)")
            }
            let start = stemIndex * channels * totalFrames
            let end = start + channels * totalFrames
            stems[stem] = try BSRoformerAudio(
                channelMajorSamples: Array(accumulated[start..<end]),
                channels: channels,
                sampleRate: configuration.sampleRate
            )
        }
        return BSRoformerSeparation(stems: stems)
    }

    private func chunkStarts(totalFrames: Int, chunkFrames: Int, stepFrames: Int) -> [Int] {
        guard totalFrames > chunkFrames else { return [0] }
        let maximumStart = totalFrames - chunkFrames
        var starts = Array(stride(from: 0, through: maximumStart, by: stepFrames))
        if starts.last != maximumStart {
            starts.append(maximumStart)
        }
        return starts
    }

    private func hammingWindow(length: Int) -> [Float] {
        guard length > 1 else { return [1] }
        return (0..<length).map { index in
            0.54 - 0.46 * cos(2 * Float.pi * Float(index) / Float(length - 1))
        }
    }
}
