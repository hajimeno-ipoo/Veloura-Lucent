import AVFoundation
import Accelerate
import Foundation

enum AudioFileService {
    static let targetSampleRate = 48_000.0
    private static let previewFFTSize = 1024
    private static let previewHopSize = 1024

    static func loadAudio(from url: URL) throws -> AudioSignal {
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: file.processingFormat.sampleRate, channels: file.processingFormat.channelCount, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)

        let signal = signal(from: buffer)
        if abs(signal.sampleRate - targetSampleRate) < 0.5 {
            return signal
        }
        return resample(signal: signal, to: targetSampleRate)
    }

    static func saveAudio(_ signal: AudioSignal, to url: URL) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: signal.sampleRate, channels: AVAudioChannelCount(signal.channels.count))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(signal.frameCount))!
        buffer.frameLength = AVAudioFrameCount(signal.frameCount)
        for (channelIndex, channel) in signal.channels.enumerated() {
            guard let destination = buffer.floatChannelData?[channelIndex] else { continue }
            destination.update(from: channel, count: channel.count)
        }

        let file = try AVAudioFile(forWriting: url, settings: interleavedFileSettings(sampleRate: signal.sampleRate, channels: signal.channels.count))
        try file.write(from: buffer)
    }

    private static func signal(from buffer: AVAudioPCMBuffer) -> AudioSignal {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let channels = (0..<channelCount).map { channelIndex in
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![channelIndex], count: frameLength))
        }
        return AudioSignal(channels: channels, sampleRate: buffer.format.sampleRate)
    }

    private static func resample(signal: AudioSignal, to targetRate: Double) -> AudioSignal {
        let ratio = targetRate / signal.sampleRate
        let newLength = max(1, Int((Double(signal.frameCount) * ratio).rounded()))
        let channels = signal.channels.map { channel in
            (0..<newLength).map { index in
                let sourcePosition = Double(index) / ratio
                let lower = Int(sourcePosition.rounded(.down))
                let upper = min(lower + 1, channel.count - 1)
                let fraction = Float(sourcePosition - Double(lower))
                return channel[lower] * (1 - fraction) + channel[upper] * fraction
            }
        }
        return AudioSignal(channels: channels, sampleRate: targetRate)
    }

    static func makePreviewSnapshot(for url: URL, bucketCount: Int = 96) throws -> AudioPreviewSnapshot {
        let signal = try loadAudio(from: url)
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return AudioPreviewSnapshot(
                waveform: Array(repeating: 0, count: bucketCount),
                duration: 0,
                bandLevels: emptyBandLevels(bucketCount: bucketCount),
                bandLevelDBs: emptyBandLevels(bucketCount: bucketCount, fill: -120)
            )
        }

        let chunkSize = max(1, mono.count / bucketCount)
        let waveform = stride(from: 0, to: mono.count, by: chunkSize).prefix(bucketCount).map { index in
            let end = min(index + chunkSize, mono.count)
            let slice = mono[index..<end]
            let peak = slice.map { abs($0) }.max() ?? 0
            return min(1, peak)
        }

        let (bandLevels, bandLevelDBs) = makeBandLevels(from: mono, sampleRate: signal.sampleRate, bucketCount: bucketCount)

        return AudioPreviewSnapshot(
            waveform: Array(waveform),
            duration: Double(mono.count) / signal.sampleRate,
            bandLevels: bandLevels,
            bandLevelDBs: bandLevelDBs
        )
    }

    private static func makeBandLevels(from mono: [Float], sampleRate: Double, bucketCount: Int) -> ([String: [Float]], [String: [Float]]) {
        let spectrogram = SpectralDSP.stft(mono, fftSize: previewFFTSize, hopSize: previewHopSize)
        guard spectrogram.frameCount > 0 else {
            return (
                emptyBandLevels(bucketCount: bucketCount),
                emptyBandLevels(bucketCount: bucketCount, fill: -120)
            )
        }

        let magnitudes = spectrogram.magnitudes()
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let bandBinRanges = AudioBandCatalog.previewBands.map { band -> (String, ClosedRange<Int>) in
            let lower = max(0, min(Int(floor(band.lowerBound / frequencyStep)), spectrogram.binCount - 1))
            let upper = max(lower, min(Int(floor(band.upperBound / frequencyStep)), spectrogram.binCount - 1))
            return (band.id, lower...upper)
        }

        var frameBandLevels: [String: [Float]] = Dictionary(uniqueKeysWithValues: bandBinRanges.map {
            ($0.0, Array(repeating: 0, count: spectrogram.frameCount))
        })

        for frameIndex in 0..<spectrogram.frameCount {
            let frameMagnitudes = magnitudes[frameIndex]
            for (bandID, range) in bandBinRanges {
                let values = frameMagnitudes[range]
                let meanSquare = values.reduce(0.0) { partial, value in
                    partial + value * value
                } / Float(max(values.count, 1))
                let rms = sqrtf(max(meanSquare, 1e-12))
                frameBandLevels[bandID]?[frameIndex] = 20 * log10f(rms)
            }
        }

        var bucketLevels: [String: [Float]] = Dictionary(uniqueKeysWithValues: bandBinRanges.map {
            ($0.0, Array(repeating: 0, count: bucketCount))
        })
        var bucketLevelDBs: [String: [Float]] = Dictionary(uniqueKeysWithValues: bandBinRanges.map {
            ($0.0, Array(repeating: Float(-120), count: bucketCount))
        })
        let framesPerBucket = max(Double(spectrogram.frameCount) / Double(bucketCount), 1)

        for (bandID, levels) in frameBandLevels {
            let peakLevel = levels.max() ?? -120
            let floorLevel = max(-84, peakLevel - 42)
            for bucketIndex in 0..<bucketCount {
                let start = Int(floor(Double(bucketIndex) * framesPerBucket))
                let end = min(levels.count, Int(ceil(Double(bucketIndex + 1) * framesPerBucket)))
                guard start < end else { continue }
                let bucketSlice = levels[start..<end]
                let bucketPeak = bucketSlice.max() ?? floorLevel
                let normalized = max(0, min(1, (bucketPeak - floorLevel) / max(peakLevel - floorLevel, 1)))
                bucketLevels[bandID]?[bucketIndex] = powf(normalized, 0.72)
                bucketLevelDBs[bandID]?[bucketIndex] = bucketPeak
            }
        }

        return (bucketLevels, bucketLevelDBs)
    }

    private static func emptyBandLevels(bucketCount: Int, fill: Float = 0) -> [String: [Float]] {
        Dictionary(uniqueKeysWithValues: AudioBandCatalog.previewBands.map { band in
            (band.id, Array(repeating: fill, count: bucketCount))
        })
    }

    static func interleavedFileSettings(sampleRate: Double, channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
}
