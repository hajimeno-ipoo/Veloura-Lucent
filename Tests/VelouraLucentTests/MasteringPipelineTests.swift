import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct MasteringPipelineTests {
    @Test
    func masteringProducesOutputFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "song_lifter.wav")
        let logs = MasteringLogCollector()

        try makeTestTone(at: inputURL)

        let output = try await MasteringService().process(inputFile: inputURL, profile: .streaming) { message in
            logs.append(message)
        }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(output.lastPathComponent.contains("song_lifter_mastered"))
        #expect(logs.values.contains("解析モード: マスタリングCPU"))
        #expect(logs.values.contains { $0.hasPrefix("解析/STFT: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析/ラウドネス: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析/トゥルーピーク: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析/帯域集計: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析/ステレオ幅: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("合計: ") && $0.hasSuffix("秒") })
        let total = try #require(parsedDuration(prefix: "合計: ", from: logs.values))
        let stagePrefixes = ["解析: ", "音色: ", "ディエッサー: ", "ダイナミクス: ", "倍音: ", "広がり: ", "音量: ", "保存: "]
        var summedStages = 0.0
        for prefix in stagePrefixes {
            summedStages += try #require(parsedDuration(prefix: prefix, from: logs.values))
        }
        #expect(total + 0.10 >= summedStages)

        let written = try AVAudioFile(forReading: output)
        #expect(written.length > 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: written.processingFormat, frameCapacity: AVAudioFrameCount(written.length))!
        try written.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        #expect(samples.contains { $0.isFinite })
        #expect(samples.map { abs($0) }.max() ?? 0 <= 1.01)
    }

    @Test
    func masteringAcceptsEditableSettings() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "song_lifter.wav")

        try makeTestTone(at: inputURL)

        var settings = MasteringProfile.streaming.settings
        settings.targetLoudness = -13.2
        settings.stereoWidth = 1.15
        settings.lowMidGain = 0.45
        settings.presenceGain = 0.38
        settings.deEsserAmount = 0.52

        let output = try await MasteringService().process(inputFile: inputURL, settings: settings) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
    }

    @Test
    func masteringKeepsTruePeakNearCeiling() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "ceiling-check.wav")

        try makeHotTransientTone(at: inputURL)

        let output = try await MasteringService().process(inputFile: inputURL, profile: .forward) { _ in }
        let mastered = try MasteringAnalysisService.analyze(fileURL: output)

        #expect(mastered.truePeakDBFS <= -0.4)
    }

    @Test
    func forwardMasteringPreservesUsefulDynamics() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "dynamic-check.wav")

        try makeHotTransientTone(at: inputURL)

        let before = try AudioComparisonService.analyze(fileURL: inputURL)
        let output = try await MasteringService().process(inputFile: inputURL, profile: .forward) { _ in }
        let after = try AudioComparisonService.analyze(fileURL: output)

        #expect(after.loudnessRangeLU >= before.loudnessRangeLU * 0.60)
        #expect(after.crestFactorDB >= before.crestFactorDB * 0.60)
    }

    @Test
    func masteringLimitsHighReturnForHarshMaterial() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "harsh-air-check.wav")

        try makeHarshAirTone(at: inputURL)

        let before = try AudioComparisonService.analyze(fileURL: inputURL)
        let output = try await MasteringService().process(inputFile: inputURL, profile: .streaming) { _ in }
        let after = try AudioComparisonService.analyze(fileURL: output)

        let beforeHigh = try #require(before.bandEnergies.first { $0.id == "high" }?.levelDB)
        let afterHigh = try #require(after.bandEnergies.first { $0.id == "high" }?.levelDB)

        #expect(afterHigh - after.rmsDBFS <= beforeHigh - before.rmsDBFS + 3.6)
    }

    @Test
    func masteredOutputURLsStayWav() {
        let inputURL = URL(fileURLWithPath: "/tmp/song_lifter.mp3")

        let defaultOutput = MasteringService.defaultOutputURL(for: inputURL)
        let temporaryOutput = MasteringService.temporaryOutputURL(for: inputURL)

        #expect(defaultOutput.pathExtension == AudioFileService.outputFileExtension)
        #expect(temporaryOutput.pathExtension == AudioFileService.outputFileExtension)
    }

    private func makeTestTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            left[index] = Float(sin(2 * Double.pi * 220 * t) * 0.08 + sin(2 * Double.pi * 8_000 * t) * 0.02)
            right[index] = Float(sin(2 * Double.pi * 220 * t + 0.12) * 0.08 + sin(2 * Double.pi * 7_600 * t) * 0.018)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private func makeHotTransientTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2.5)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 180 * t) * 0.32
            let bright = sin(2 * Double.pi * 6_400 * t) * 0.10
            let transient = index % 7_200 < 120 ? 0.55 : 0
            left[index] = Float(body + bright + transient)
            right[index] = Float(body * 0.96 + sin(2 * Double.pi * 7_100 * t) * 0.09 + transient * 0.92)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private func makeHarshAirTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let body = Float(sin(2 * Double.pi * 260 * t) * 0.06)
            let presence = Float(sin(2 * Double.pi * 6_800 * t) * 0.026)
            let air = Float(sin(2 * Double.pi * 13_500 * t) * 0.018)
            let shimmer = Float(sin(2 * Double.pi * 15_500 * t + sin(2 * Double.pi * 11 * t)) * 0.012)
            left[index] = body + presence + air + shimmer
            right[index] = body * 0.97 + presence * 0.92 - air * 0.28 + shimmer * 0.7
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }
}

private final class MasteringLogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }
}

private func parsedDuration(prefix: String, from logs: [String]) -> Double? {
    guard let line = logs.first(where: { $0.hasPrefix(prefix) && $0.hasSuffix("秒") }) else {
        return nil
    }
    let trimmed = line
        .replacingOccurrences(of: prefix, with: "")
        .replacingOccurrences(of: "秒", with: "")
    return Double(trimmed)
}
