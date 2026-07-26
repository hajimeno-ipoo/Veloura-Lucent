import Foundation
import Testing
@testable import VelouraLucent

struct StemInputDisplayAnalysisServiceTests {
    @Test("選択した入力ファイルから波形・スペクトログラム・通常解析値を生成する")
    func analyzesSelectedInputForDisplayAndPreview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "stem-input-display-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inputURL = directory.appending(path: "input.wav")
        let sampleRate = 48_000.0
        let frameCount = 48_000
        let channel = (0..<frameCount).map { frame -> Float in
            let phase = 2 * Double.pi * 440 * Double(frame) / sampleRate
            return Float(sin(phase) * 0.2)
        }
        try AudioFileService.saveAudio(
            AudioSignal(channels: [channel, channel], sampleRate: sampleRate),
            to: inputURL
        )

        let logs = StemInputDisplayLogCollector()
        let result = try await ProductionStemInputDisplayAnalyzer().analyze(
            inputURL: inputURL,
            analysisMode: .cpu,
            logHandler: { logs.append($0) }
        )

        let evaluation = try #require(result.evaluation)
        #expect(evaluation.purpose == .canonicalInput)
        #expect(evaluation.completedMeasurements.contains(.audioComparisonSnapshot))
        #expect(evaluation.completedMeasurements.contains(.noiseMeasurementSnapshot))
        #expect(evaluation.audioMetrics.duration > 0.9)
        #expect(result.previewSnapshot.duration > 0.9)
        #expect(!result.previewSnapshot.waveform.isEmpty)
        #expect(result.spectrogram.duration > 0.9)
        #expect(result.spectrogram.timeBucketCount > 0)
        #expect(result.spectrogram.frequencyBucketCount > 0)
        #expect(logs.labels == [
            "ファイル読み込み",
            "プレビュー/スペクトログラム生成",
            "比較指標",
            "補正解析",
            "ノイズ測定",
        ])
    }
}

private final class StemInputDisplayLogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    var labels: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages.compactMap { message in
            let prefix = "表示解析/計測: "
            guard message.hasPrefix(prefix),
                  let durationSeparator = message.lastIndex(of: ":") else {
                return nil
            }
            return String(message[message.index(message.startIndex, offsetBy: prefix.count)..<durationSeparator])
        }
    }

    func append(_ message: String) {
        lock.lock()
        messages.append(message)
        lock.unlock()
    }
}
