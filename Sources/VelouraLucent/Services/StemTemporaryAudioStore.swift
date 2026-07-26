import AVFoundation
import Foundation

struct StemAudioArtifactValidationReport: Equatable, Sendable {
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
}

enum StemTemporaryAudioStoreError: LocalizedError, Equatable, Sendable {
    case invalidFileURL(String)
    case invalidSignal
    case outputAlreadyExists(String)
    case artifactURLMismatch(expected: String, actual: String)
    case artifactKindMismatch
    case formatMismatch(String)
    case nonFiniteSample(channel: Int, frame: Int)
    case fileOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFileURL(let value): "Stem一時音声のURLが不正です（\(value)）。"
        case .invalidSignal: "Stem一時音声として保存できない信号です。"
        case .outputAlreadyExists(let path): "Stem一時音声がすでに存在します（\(path)）。"
        case let .artifactURLMismatch(expected, actual):
            "Stem一時音声のURLが一致しません（期待: \(expected)、実際: \(actual)）。"
        case .artifactKindMismatch: "Stem一時音声の種類が一致しません。"
        case .formatMismatch(let detail): "Stem一時音声の形式が一致しません（\(detail)）。"
        case let .nonFiniteSample(channel, frame):
            "Stem一時音声にNaNまたはInfinityがあります（channel \(channel)、frame \(frame)）。"
        case .fileOperationFailed(let detail): "Stem一時音声のファイル操作に失敗しました（\(detail)）。"
        }
    }
}

/// 現在のStemセッションで使うWAVだけを扱う小さな一時音声store。
/// 保存した状態や履歴は扱わず、現在の音声ファイルだけを所有する。
struct StemTemporaryAudioStore: Sendable {
    func save(
        signal: AudioSignal,
        id: String,
        kind: StemArtifactKind,
        to destinationURL: URL
    ) async throws -> StemAudioArtifact {
        try validate(signal)
        let destination = try normalizedFileURL(destinationURL)
        let parent = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw StemTemporaryAudioStoreError.outputAlreadyExists(destination.path)
        }

        let temporaryURL = parent.appending(
            path: ".\(destination.lastPathComponent).\(UUID().uuidString).partial.wav"
        )
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            try write(signal, to: temporaryURL)
            let report = try inspect(temporaryURL, verifyFiniteSamples: true)
            guard report.sampleRate == signal.sampleRate,
                  report.channelCount == signal.channels.count,
                  report.frameCount == signal.frameCount else {
                throw StemTemporaryAudioStoreError.formatMismatch("保存前後で音声構造が変化しました")
            }
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
        } catch {
            if error is StemTemporaryAudioStoreError { throw error }
            throw StemTemporaryAudioStoreError.fileOperationFailed(error.localizedDescription)
        }

        return StemAudioArtifact(
            id: id,
            kind: kind,
            fileURL: destination,
            sampleRate: signal.sampleRate,
            channelCount: signal.channels.count,
            frameCount: signal.frameCount
        )
    }

    func validate(
        artifact: StemAudioArtifact,
        expectedURL: URL,
        expectedKind: StemArtifactKind
    ) async throws -> StemAudioArtifactValidationReport {
        let expected = try normalizedFileURL(expectedURL)
        let actual = try normalizedFileURL(artifact.fileURL)
        guard actual == expected else {
            throw StemTemporaryAudioStoreError.artifactURLMismatch(
                expected: expected.path,
                actual: actual.path
            )
        }
        guard artifact.kind == expectedKind else {
            throw StemTemporaryAudioStoreError.artifactKindMismatch
        }
        let report = try inspect(actual, verifyFiniteSamples: true)
        guard report.sampleRate == artifact.sampleRate,
              report.channelCount == artifact.channelCount,
              report.frameCount == artifact.frameCount else {
            throw StemTemporaryAudioStoreError.formatMismatch("成果物メタデータとWAVが一致しません")
        }
        return report
    }

    func load(
        artifact: StemAudioArtifact,
        expectedURL: URL,
        expectedKind: StemArtifactKind
    ) async throws -> AudioSignal {
        _ = try await validate(
            artifact: artifact,
            expectedURL: expectedURL,
            expectedKind: expectedKind
        )
        return try read(artifact.fileURL)
    }

    func removeIfPresent(_ url: URL) throws {
        let normalized = try normalizedFileURL(url)
        guard FileManager.default.fileExists(atPath: normalized.path) else { return }
        try FileManager.default.removeItem(at: normalized)
    }

    func removeDirectoryIfPresent(_ url: URL) throws {
        let normalized = url.standardizedFileURL
        guard normalized.isFileURL, FileManager.default.fileExists(atPath: normalized.path) else { return }
        try FileManager.default.removeItem(at: normalized)
    }

    private func validate(_ signal: AudioSignal) throws {
        guard signal.sampleRate.isFinite, signal.sampleRate > 0,
              !signal.channels.isEmpty, signal.frameCount > 0,
              signal.channels.allSatisfy({ $0.count == signal.frameCount }) else {
            throw StemTemporaryAudioStoreError.invalidSignal
        }
        for (channelIndex, channel) in signal.channels.enumerated() {
            if let frame = channel.firstIndex(where: { !$0.isFinite }) {
                throw StemTemporaryAudioStoreError.nonFiniteSample(
                    channel: channelIndex,
                    frame: frame
                )
            }
        }
    }

    private func write(_ signal: AudioSignal, to url: URL) throws {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: signal.sampleRate,
            channels: AVAudioChannelCount(signal.channels.count),
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(signal.frameCount)
        ), let channelData = buffer.floatChannelData else {
            throw StemTemporaryAudioStoreError.invalidSignal
        }
        buffer.frameLength = AVAudioFrameCount(signal.frameCount)
        for channelIndex in signal.channels.indices {
            signal.channels[channelIndex].withUnsafeBufferPointer { source in
                channelData[channelIndex].update(from: source.baseAddress!, count: signal.frameCount)
            }
        }
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: signal.sampleRate,
            AVNumberOfChannelsKey: signal.channels.count,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: fileSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    private func inspect(_ url: URL, verifyFiniteSamples: Bool) throws -> StemAudioArtifactValidationReport {
        let signal = try read(url, verifyFiniteSamples: verifyFiniteSamples)
        return StemAudioArtifactValidationReport(
            sampleRate: signal.sampleRate,
            channelCount: signal.channels.count,
            frameCount: signal.frameCount
        )
    }

    private func read(_ url: URL, verifyFiniteSamples: Bool = true) throws -> AudioSignal {
        let normalized = try normalizedFileURL(url)
        let values = try normalized.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw StemTemporaryAudioStoreError.fileOperationFailed("通常のWAVファイルではありません")
        }
        let file = try AVAudioFile(forReading: normalized)
        guard file.length > 0, file.length <= Int64(Int.max),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat,
                frameCapacity: AVAudioFrameCount(file.length)
              ) else {
            throw StemTemporaryAudioStoreError.invalidSignal
        }
        try file.read(into: buffer)
        guard let channelData = buffer.floatChannelData else {
            throw StemTemporaryAudioStoreError.formatMismatch("Float32非インターリーブとして読み込めません")
        }
        let frameCount = Int(buffer.frameLength)
        var channels: [[Float]] = []
        channels.reserveCapacity(Int(buffer.format.channelCount))
        for channelIndex in 0..<Int(buffer.format.channelCount) {
            let channel = Array(UnsafeBufferPointer(start: channelData[channelIndex], count: frameCount))
            if verifyFiniteSamples, let frame = channel.firstIndex(where: { !$0.isFinite }) {
                throw StemTemporaryAudioStoreError.nonFiniteSample(channel: channelIndex, frame: frame)
            }
            channels.append(channel)
        }
        return AudioSignal(channels: channels, sampleRate: buffer.format.sampleRate)
    }

    private func normalizedFileURL(_ url: URL) throws -> URL {
        guard url.isFileURL, url.query == nil, url.fragment == nil else {
            throw StemTemporaryAudioStoreError.invalidFileURL(url.absoluteString)
        }
        return url.standardizedFileURL
    }
}
