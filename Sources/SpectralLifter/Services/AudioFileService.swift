import AVFoundation
import Foundation

enum AudioFileService {
    static let targetSampleRate = 48_000.0

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

        let file = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
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
            return AudioPreviewSnapshot(waveform: Array(repeating: 0, count: bucketCount), duration: 0)
        }

        let chunkSize = max(1, mono.count / bucketCount)
        let waveform = stride(from: 0, to: mono.count, by: chunkSize).prefix(bucketCount).map { index in
            let end = min(index + chunkSize, mono.count)
            let slice = mono[index..<end]
            let peak = slice.map { abs($0) }.max() ?? 0
            return min(1, peak)
        }

        return AudioPreviewSnapshot(
            waveform: Array(waveform),
            duration: Double(mono.count) / signal.sampleRate
        )
    }
}
