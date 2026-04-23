import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct NativeAudioProcessorBenchmarkTests {
    @Test
    func recordsStageTimings() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "benchmark-input.wav")
        let outputURL = tempDirectory.appending(path: "benchmark-output.wav")

        try makeTestTone(at: inputURL, duration: 2)
        let logs = LogCollector()

        let benchmark = try NativeAudioProcessor().benchmark(
            inputFile: inputURL,
            outputFile: outputURL,
            denoiseStrength: .balanced,
            logger: logs
        )

        let expectedStages = [
            "loadAudio",
            "analyze",
            "neuralPrediction",
            "denoise",
            "harmonicUpscale",
            "multibandDynamics",
            "loudnessFinalize",
            "saveAudio"
        ]

        #expect(benchmark.stages.map(\.name) == expectedStages)
        #expect(benchmark.stages.allSatisfy { $0.durationSeconds >= 0 })
        #expect(benchmark.totalDurationSeconds >= 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path()))
        #expect(logs.values.contains { $0.hasPrefix("解析: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("合計: ") && $0.hasSuffix("秒") })
        let total = try #require(parsedDuration(prefix: "合計: ", from: logs.values))
        let stagePrefixes = ["読み込み: ", "解析: ", "解析補助: ", "ノイズ除去: ", "高域補完: ", "ダイナミクス: ", "最終音量: ", "書き出し: "]
        var summedStages = 0.0
        for prefix in stagePrefixes {
            summedStages += try #require(parsedDuration(prefix: prefix, from: logs.values))
        }
        #expect(total + 0.10 >= summedStages)

        let report = benchmarkReport(for: benchmark)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentNativeAudioBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    @Test
    func recordsRealAudioCPUAndExperimentalMetalBenchmark() throws {
        guard ProcessInfo.processInfo.environment["VELOURA_RUN_REAL_AUDIO_BENCHMARK"] == "1" else {
            return
        }

        let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let inputURL = projectDirectory.appending(path: "violin #002 睡眠.wav")
        guard FileManager.default.fileExists(atPath: inputURL.path(percentEncoded: false)) else {
            Issue.record("Real audio fixture is missing: \(inputURL.path(percentEncoded: false))")
            return
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let cpuOutputURL = tempDirectory.appending(path: "real-audio-cpu.wav")
        let metalOutputURL = tempDirectory.appending(path: "real-audio-metal.wav")

        let processor = NativeAudioProcessor()
        let cpu = try processor.benchmark(
            inputFile: inputURL,
            outputFile: cpuOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu
        )
        let metal = try processor.benchmark(
            inputFile: inputURL,
            outputFile: metalOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .experimentalMetal
        )

        #expect(FileManager.default.fileExists(atPath: cpuOutputURL.path()))
        #expect(FileManager.default.fileExists(atPath: metalOutputURL.path()))

        let report = realAudioBenchmarkReport(
            inputURL: inputURL,
            cpu: cpu,
            metal: metal,
            outputsMatch: try Data(contentsOf: cpuOutputURL) == Data(contentsOf: metalOutputURL)
        )
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentRealAudioBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    private func benchmarkReport(for benchmark: NativeAudioProcessingBenchmark) -> String {
        var lines = ["NativeAudioProcessor benchmark"]
        for stage in benchmark.stages {
            lines.append("\(stage.name): \(String(format: "%.6f", stage.durationSeconds))s")
        }
        lines.append("total: \(String(format: "%.6f", benchmark.totalDurationSeconds))s")
        return lines.joined(separator: "\n")
    }

    private func realAudioBenchmarkReport(
        inputURL: URL,
        cpu: NativeAudioProcessingBenchmark,
        metal: NativeAudioProcessingBenchmark,
        outputsMatch: Bool
    ) -> String {
        var lines = [
            "Veloura Lucent real audio benchmark",
            "input: \(inputURL.path(percentEncoded: false))",
            "outputsMatch: \(outputsMatch)",
            "cpu.total: \(String(format: "%.6f", cpu.totalDurationSeconds))s",
            "experimentalMetal.total: \(String(format: "%.6f", metal.totalDurationSeconds))s",
            "speedup.total.cpu_over_experimentalMetal: \(String(format: "%.3f", speedRatio(cpu.totalDurationSeconds, metal.totalDurationSeconds)))x"
        ]

        let stageNames = cpu.stages.map(\.name)
        for stageName in stageNames {
            let cpuDuration = cpu.duration(for: stageName) ?? 0
            let metalDuration = metal.duration(for: stageName) ?? 0
            lines.append(
                "\(stageName): cpu=\(String(format: "%.6f", cpuDuration))s experimentalMetal=\(String(format: "%.6f", metalDuration))s speedup=\(String(format: "%.3f", speedRatio(cpuDuration, metalDuration)))x"
            )
        }
        return lines.joined(separator: "\n")
    }

    private func speedRatio(_ cpu: Double, _ metal: Double) -> Double {
        metal > 0 ? cpu / metal : 0
    }

    private func makeTestTone(at url: URL, duration: Double) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let base = Float(sin(2 * Double.pi * 440 * time) * 0.12)
            let upper = Float(sin(2 * Double.pi * 6_000 * time) * 0.03)
            left[index] = base + upper
            right[index] = base * 0.96 - upper * 0.4
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
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

private final class LogCollector: AudioProcessingLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func log(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }
}
