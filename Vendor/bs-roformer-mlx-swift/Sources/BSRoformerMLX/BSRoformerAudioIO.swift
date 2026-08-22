@preconcurrency import AVFoundation
import Foundation

private final class BSRoformerConverterInput: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didSupplyInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}

public enum BSRoformerAudioIO {
    public static func load(
        from url: URL,
        targetSampleRate: Int? = nil,
        targetChannels: Int? = nil
    ) throws -> BSRoformerAudio {
        do {
            let file = try AVAudioFile(forReading: url)
            let sourceFormat = file.processingFormat
            let outputSampleRate = Double(targetSampleRate ?? Int(sourceFormat.sampleRate.rounded()))
            let outputChannels = AVAudioChannelCount(targetChannels ?? Int(sourceFormat.channelCount))
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: outputSampleRate,
                channels: outputChannels,
                interleaved: false
            ) else {
                throw BSRoformerError.audioIO("Float32形式を作成できません")
            }
            guard let sourceBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(file.length)
            ) else {
                throw BSRoformerError.audioIO("音声バッファを確保できません")
            }
            try file.read(into: sourceBuffer)

            let buffer: AVAudioPCMBuffer
            if sourceFormat.sampleRate == outputFormat.sampleRate,
               sourceFormat.channelCount == outputFormat.channelCount,
               sourceFormat.commonFormat == .pcmFormatFloat32,
               !sourceFormat.isInterleaved {
                buffer = sourceBuffer
            } else {
                guard let converter = AVAudioConverter(
                    from: sourceFormat,
                    to: outputFormat
                ) else {
                    throw BSRoformerError.audioIO("サンプルレート変換器を作成できません")
                }
                let ratio = outputFormat.sampleRate / sourceFormat.sampleRate
                let capacity = AVAudioFrameCount(
                    ceil(Double(sourceBuffer.frameLength) * ratio) + 32
                )
                guard let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat,
                    frameCapacity: capacity
                ) else {
                    throw BSRoformerError.audioIO("変換後の音声バッファを確保できません")
                }
                let converterInput = BSRoformerConverterInput(buffer: sourceBuffer)
                var conversionError: NSError?
                let status = converter.convert(
                    to: convertedBuffer,
                    error: &conversionError
                ) { _, inputStatus in
                    if converterInput.didSupplyInput {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    converterInput.didSupplyInput = true
                    inputStatus.pointee = .haveData
                    return converterInput.buffer
                }
                guard status != .error else {
                    throw BSRoformerError.audioIO(
                        conversionError?.localizedDescription ?? "サンプルレート変換に失敗しました"
                    )
                }
                buffer = convertedBuffer
            }

            guard let channelData = buffer.floatChannelData else {
                throw BSRoformerError.audioIO("音声サンプルを読み込めません")
            }
            let channels = Int(buffer.format.channelCount)
            let frames = Int(buffer.frameLength)
            var samples = [Float](repeating: 0, count: channels * frames)
            for channel in 0..<channels {
                for frame in 0..<frames {
                    samples[channel * frames + frame] = channelData[channel][frame]
                }
            }
            return try BSRoformerAudio(
                channelMajorSamples: samples,
                channels: channels,
                sampleRate: Int(buffer.format.sampleRate.rounded())
            )
        } catch let error as BSRoformerError {
            throw error
        } catch {
            throw BSRoformerError.audioIO(error.localizedDescription)
        }
    }

    public static func writeFloatWAV(_ audio: BSRoformerAudio, to url: URL) throws {
        do {
            guard let fileFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(audio.sampleRate),
                channels: AVAudioChannelCount(audio.channels),
                interleaved: true
            ), let processingFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(audio.sampleRate),
                channels: AVAudioChannelCount(audio.channels),
                interleaved: false
            ) else {
                throw BSRoformerError.audioIO("出力形式を作成できません")
            }
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: AVAudioFrameCount(audio.frameCount)
            ), let channelData = buffer.floatChannelData else {
                throw BSRoformerError.audioIO("出力バッファを確保できません")
            }
            buffer.frameLength = AVAudioFrameCount(audio.frameCount)
            for channel in 0..<audio.channels {
                for frame in 0..<audio.frameCount {
                    channelData[channel][frame] =
                        audio.channelMajorSamples[channel * audio.frameCount + frame]
                }
            }
            let file = try AVAudioFile(
                forWriting: url,
                settings: fileFormat.settings
            )
            try file.write(from: buffer)
        } catch let error as BSRoformerError {
            throw error
        } catch {
            throw BSRoformerError.audioIO(error.localizedDescription)
        }
    }
}
