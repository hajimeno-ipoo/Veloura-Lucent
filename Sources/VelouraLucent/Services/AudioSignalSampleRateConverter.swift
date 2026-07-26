import AVFoundation
import Foundation

enum AudioSignalSampleRateConversionError: LocalizedError, Equatable, Sendable {
    case invalidSourceSampleRate
    case invalidTargetSampleRate
    case missingChannels
    case emptyFrames
    case inconsistentFrameCount(channelIndex: Int, expected: Int, actual: Int)
    case nonFiniteSample(channelIndex: Int, frameIndex: Int)
    case channelCountExceedsConverterCapacity
    case frameCountExceedsConverterCapacity
    case unableToCreateAudioFormat
    case unableToCreateConverter
    case unableToCreateAudioBuffer
    case conversionFailed(String)
    case outputSampleRateMismatch(expected: Double, actual: Double)
    case outputChannelCountMismatch(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidSourceSampleRate:
            "変換元のサンプルレートが不正です。"
        case .invalidTargetSampleRate:
            "変換先のサンプルレートが不正です。"
        case .missingChannels:
            "サンプルレート変換する音声にチャンネルがありません。"
        case .emptyFrames:
            "サンプルレート変換する音声にフレームがありません。"
        case let .inconsistentFrameCount(channelIndex, expected, actual):
            "チャンネル\(channelIndex + 1)のフレーム数が一致しません（期待: \(expected)、実際: \(actual)）。"
        case let .nonFiniteSample(channelIndex, frameIndex):
            "チャンネル\(channelIndex + 1)のframe \(frameIndex)にNaNまたはInfinityがあります。"
        case .channelCountExceedsConverterCapacity:
            "音声のチャンネル数がサンプルレート変換器の上限を超えています。"
        case .frameCountExceedsConverterCapacity:
            "音声のフレーム数がサンプルレート変換器の上限を超えています。"
        case .unableToCreateAudioFormat:
            "サンプルレート変換用の音声形式を作成できません。"
        case .unableToCreateConverter:
            "サンプルレート変換器を作成できません。"
        case .unableToCreateAudioBuffer:
            "サンプルレート変換用の音声バッファを作成できません。"
        case let .conversionFailed(message):
            "サンプルレート変換に失敗しました（\(message)）。"
        case let .outputSampleRateMismatch(expected, actual):
            "変換後のサンプルレートが一致しません（期待: \(expected) Hz、実際: \(actual) Hz）。"
        case let .outputChannelCountMismatch(expected, actual):
            "変換後のチャンネル数が一致しません（期待: \(expected)、実際: \(actual)）。"
        }
    }
}

/// Converts an in-memory signal without changing channel layout, gain, or sample values
/// beyond the sample-rate conversion performed by AVAudioConverter.
enum AudioSignalSampleRateConverter {
    private static let equivalentSampleRateTolerance = 0.5

    static func convert(_ sourceSignal: AudioSignal, to targetSampleRate: Double) throws -> AudioSignal {
        let sourceFrameCount = try validate(signal: sourceSignal)
        guard targetSampleRate.isFinite, targetSampleRate > 0 else {
            throw AudioSignalSampleRateConversionError.invalidTargetSampleRate
        }
        guard abs(sourceSignal.sampleRate - targetSampleRate) >= equivalentSampleRateTolerance else {
            return sourceSignal
        }

        guard sourceSignal.channels.count <= Int(AVAudioChannelCount.max) else {
            throw AudioSignalSampleRateConversionError.channelCountExceedsConverterCapacity
        }
        guard sourceFrameCount <= Int(AVAudioFrameCount.max) else {
            throw AudioSignalSampleRateConversionError.frameCountExceedsConverterCapacity
        }

        let channelCount = AVAudioChannelCount(sourceSignal.channels.count)
        guard
            let inputFormat = AVAudioFormat(
                standardFormatWithSampleRate: sourceSignal.sampleRate,
                channels: channelCount
            ),
            let outputFormat = AVAudioFormat(
                standardFormatWithSampleRate: targetSampleRate,
                channels: channelCount
            )
        else {
            throw AudioSignalSampleRateConversionError.unableToCreateAudioFormat
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioSignalSampleRateConversionError.unableToCreateConverter
        }
        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        converter.sampleRateConverterAlgorithm = AVSampleRateConverterAlgorithm_Mastering

        let inputBuffer = try pcmBuffer(
            from: sourceSignal,
            frameCount: sourceFrameCount,
            format: inputFormat
        )
        let estimatedOutputCapacity = ceil(
            Double(sourceFrameCount) * targetSampleRate / sourceSignal.sampleRate
        ) + 64
        guard estimatedOutputCapacity.isFinite,
              estimatedOutputCapacity > 0,
              estimatedOutputCapacity <= Double(AVAudioFrameCount.max)
        else {
            throw AudioSignalSampleRateConversionError.frameCountExceedsConverterCapacity
        }
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(estimatedOutputCapacity)
        ) else {
            throw AudioSignalSampleRateConversionError.unableToCreateAudioBuffer
        }

        let inputState = AudioSignalSampleRateConverterInputState(buffer: inputBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
            if inputState.didProvideInput {
                inputStatus.pointee = .endOfStream
                return nil
            }
            inputState.didProvideInput = true
            inputStatus.pointee = .haveData
            return inputState.buffer
        }
        guard status != .error, conversionError == nil else {
            throw AudioSignalSampleRateConversionError.conversionFailed(
                conversionError?.localizedDescription ?? "AVAudioConverter returned an error"
            )
        }

        let converted = try signal(from: outputBuffer)
        guard abs(converted.sampleRate - targetSampleRate) < equivalentSampleRateTolerance else {
            throw AudioSignalSampleRateConversionError.outputSampleRateMismatch(
                expected: targetSampleRate,
                actual: converted.sampleRate
            )
        }
        guard converted.channels.count == sourceSignal.channels.count else {
            throw AudioSignalSampleRateConversionError.outputChannelCountMismatch(
                expected: sourceSignal.channels.count,
                actual: converted.channels.count
            )
        }
        _ = try validate(signal: converted)
        return converted
    }

    private static func validate(signal: AudioSignal) throws -> Int {
        guard signal.sampleRate.isFinite, signal.sampleRate > 0 else {
            throw AudioSignalSampleRateConversionError.invalidSourceSampleRate
        }
        guard let firstChannel = signal.channels.first else {
            throw AudioSignalSampleRateConversionError.missingChannels
        }
        let expectedFrameCount = firstChannel.count
        guard expectedFrameCount > 0 else {
            throw AudioSignalSampleRateConversionError.emptyFrames
        }

        for (channelIndex, channel) in signal.channels.enumerated() {
            guard channel.count == expectedFrameCount else {
                throw AudioSignalSampleRateConversionError.inconsistentFrameCount(
                    channelIndex: channelIndex,
                    expected: expectedFrameCount,
                    actual: channel.count
                )
            }
            if let frameIndex = channel.firstIndex(where: { !$0.isFinite }) {
                throw AudioSignalSampleRateConversionError.nonFiniteSample(
                    channelIndex: channelIndex,
                    frameIndex: frameIndex
                )
            }
        }
        return expectedFrameCount
    }

    private static func pcmBuffer(
        from signal: AudioSignal,
        frameCount: Int,
        format: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(frameCount)
        ) else {
            throw AudioSignalSampleRateConversionError.unableToCreateAudioBuffer
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        for (channelIndex, channel) in signal.channels.enumerated() {
            guard let destination = buffer.floatChannelData?[channelIndex] else {
                throw AudioSignalSampleRateConversionError.unableToCreateAudioBuffer
            }
            destination.update(from: channel, count: frameCount)
        }
        return buffer
    }

    private static func signal(from buffer: AVAudioPCMBuffer) throws -> AudioSignal {
        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        guard channelCount > 0, frameLength > 0, let channelData = buffer.floatChannelData else {
            throw AudioSignalSampleRateConversionError.unableToCreateAudioBuffer
        }
        let channels = (0..<channelCount).map { channelIndex in
            Array(UnsafeBufferPointer(start: channelData[channelIndex], count: frameLength))
        }
        return AudioSignal(channels: channels, sampleRate: buffer.format.sampleRate)
    }
}

private final class AudioSignalSampleRateConverterInputState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
