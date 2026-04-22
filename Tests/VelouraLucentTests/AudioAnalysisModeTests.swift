import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct AudioAnalysisModeTests {
    @Test
    func experimentalMetalAnalysisMatchesCPUOutput() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "analysis-mode-input.wav")
        let cpuOutputURL = tempDirectory.appending(path: "analysis-mode-cpu.wav")
        let metalOutputURL = tempDirectory.appending(path: "analysis-mode-metal.wav")

        try makeTestTone(at: inputURL, duration: 2)

        let processor = NativeAudioProcessor()
        try processor.process(
            inputFile: inputURL,
            outputFile: cpuOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu
        )
        try processor.process(
            inputFile: inputURL,
            outputFile: metalOutputURL,
            denoiseStrength: .balanced,
            analysisMode: .experimentalMetal
        )

        let cpuData = try Data(contentsOf: cpuOutputURL)
        let metalData = try Data(contentsOf: metalOutputURL)
        #expect(cpuData == metalData)
    }

    @Test
    func metalAnalysisProcessorProducesSeparatedSpectraWhenAvailable() {
        let processor = MetalAudioAnalysisProcessor()
        guard processor.isAvailable else { return }

        let sampleRate = 48_000.0
        let samples = (0..<16_384).map { index in
            let time = Double(index) / sampleRate
            return Float(sin(2 * Double.pi * 440 * time) * 0.1)
        }
        let spectrogram = SpectralDSP.stft(samples)

        let separated = processor.separatedMeanSpectra(spectrogram: spectrogram)

        #expect(separated != nil)
        #expect(separated?.harmonic.count == spectrogram.binCount)
        #expect(separated?.percussive.count == spectrogram.binCount)
    }

    @Test
    func experimentalMetalAnalysisValuesStayNearCPU() {
        let signal = makeTestSignal(duration: 2)

        let cpu = AudioAnalyzer(mode: .cpu).analyze(signal: signal)
        let metal = AudioAnalyzer(mode: .experimentalMetal).analyze(signal: signal)

        #expect(abs(cpu.cutoffFrequency - metal.cutoffFrequency) <= 1)
        #expect(abs(cpu.harmonicConfidence - metal.harmonicConfidence) <= 0.0001)
        #expect(cpu.hasShimmer == metal.hasShimmer)
        #expect(abs(cpu.shimmerRatio - metal.shimmerRatio) <= 0.0001)
        #expect(abs(cpu.brightnessRatio - metal.brightnessRatio) <= 0.0001)
        #expect(abs(cpu.transientAmount - metal.transientAmount) <= 0.000001)
        #expect(abs(cpu.noiseAmount - metal.noiseAmount) <= 0.0001)
    }

    @Test
    func recordsCPUAndExperimentalMetalAnalysisBenchmarks() throws {
        let durations = [0.5, 1.25, 2.0]
        let warmupIterations = 1
        let measuredIterations = 2
        var results: [AnalysisBenchmarkComparison] = []

        for duration in durations {
            let signal = makeTestSignal(duration: duration)
            let cpuBenchmark = measureAnalysis(
                label: "cpu",
                mode: .cpu,
                signal: signal,
                warmupIterations: warmupIterations,
                measuredIterations: measuredIterations
            )
            let metalBenchmark = measureAnalysis(
                label: "experimentalMetal",
                mode: .experimentalMetal,
                signal: signal,
                warmupIterations: warmupIterations,
                measuredIterations: measuredIterations
            )

            #expect(cpuBenchmark.measuredDurations.count == measuredIterations)
            #expect(metalBenchmark.measuredDurations.count == measuredIterations)
            #expect(cpuBenchmark.averageDuration >= 0)
            #expect(metalBenchmark.averageDuration >= 0)
            results.append(
                AnalysisBenchmarkComparison(
                    duration: duration,
                    cpu: cpuBenchmark,
                    metal: metalBenchmark
                )
            )
        }

        let report = analysisBenchmarkReport(results: results)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentAnalysisModeBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    @Test
    func recordsLongCPUAndExperimentalMetalAnalysisBenchmarks() throws {
        guard ProcessInfo.processInfo.environment["VELOURA_RUN_LONG_ANALYSIS_BENCHMARK"] == "1" else {
            return
        }

        let durations = [10.0, 30.0, 60.0]
        var results: [AnalysisBenchmarkComparison] = []

        for duration in durations {
            let signal = makeTestSignal(duration: duration)
            let cpuBenchmark = measureAnalysis(
                label: "cpu",
                mode: .cpu,
                signal: signal,
                warmupIterations: 0,
                measuredIterations: 1
            )
            let metalBenchmark = measureAnalysis(
                label: "experimentalMetal",
                mode: .experimentalMetal,
                signal: signal,
                warmupIterations: 0,
                measuredIterations: 1
            )

            #expect(cpuBenchmark.measuredDurations.count == 1)
            #expect(metalBenchmark.measuredDurations.count == 1)
            results.append(
                AnalysisBenchmarkComparison(
                    duration: duration,
                    cpu: cpuBenchmark,
                    metal: metalBenchmark
                )
            )
        }

        let report = analysisBenchmarkReport(results: results)
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentLongAnalysisModeBenchmark.txt")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    private func measureAnalysis(
        label: String,
        mode: AudioAnalysisMode,
        signal: AudioSignal,
        warmupIterations: Int,
        measuredIterations: Int
    ) -> AnalysisBenchmarkSummary {
        var warmupDurations: [Double] = []
        for _ in 0..<warmupIterations {
            warmupDurations.append(measureSeconds {
                _ = AudioAnalyzer(mode: mode).analyze(signal: signal)
            })
        }

        var measuredDurations: [Double] = []
        for _ in 0..<measuredIterations {
            measuredDurations.append(measureSeconds {
                _ = AudioAnalyzer(mode: mode).analyze(signal: signal)
            })
        }

        return AnalysisBenchmarkSummary(
            label: label,
            warmupDurations: warmupDurations,
            measuredDurations: measuredDurations
        )
    }

    private func measureSeconds(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }

    private func analysisBenchmarkReport(results: [AnalysisBenchmarkComparison]) -> String {
        var lines = ["Audio analysis mode benchmark"]
        for result in results {
            lines.append("duration: \(String(format: "%.2f", result.duration))s")
            lines.append(result.cpu.reportLine)
            lines.append(result.metal.reportLine)
            lines.append("speedup.cpu_over_experimentalMetal: \(String(format: "%.3f", result.speedRatio))x")
        }
        return lines.joined(separator: "\n")
    }

    private struct AnalysisBenchmarkComparison {
        let duration: Double
        let cpu: AnalysisBenchmarkSummary
        let metal: AnalysisBenchmarkSummary

        var speedRatio: Double {
            metal.averageDuration > 0 ? cpu.averageDuration / metal.averageDuration : 0
        }
    }

    private struct AnalysisBenchmarkSummary {
        let label: String
        let warmupDurations: [Double]
        let measuredDurations: [Double]

        var averageDuration: Double {
            guard !measuredDurations.isEmpty else { return 0 }
            return measuredDurations.reduce(0, +) / Double(measuredDurations.count)
        }

        var minimumDuration: Double {
            measuredDurations.min() ?? 0
        }

        var maximumDuration: Double {
            measuredDurations.max() ?? 0
        }

        var reportLine: String {
            let warmup = warmupDurations.map { String(format: "%.6f", $0) }.joined(separator: ",")
            let measured = measuredDurations.map { String(format: "%.6f", $0) }.joined(separator: ",")
            return "\(label).analyze warmup=[\(warmup)] measured=[\(measured)] avg=\(String(format: "%.6f", averageDuration))s min=\(String(format: "%.6f", minimumDuration))s max=\(String(format: "%.6f", maximumDuration))s"
        }
    }

    private func makeTestSignal(duration: Double) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        var left = Array(repeating: Float.zero, count: frameCount)
        var right = Array(repeating: Float.zero, count: frameCount)

        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let base = Float(sin(2 * Double.pi * 330 * time) * 0.11)
            let high = Float(sin(2 * Double.pi * 7_200 * time) * 0.025)
            left[index] = base + high
            right[index] = base * 0.94 - high * 0.35
        }

        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
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
            let base = Float(sin(2 * Double.pi * 330 * time) * 0.11)
            let high = Float(sin(2 * Double.pi * 7_200 * time) * 0.025)
            left[index] = base + high
            right[index] = base * 0.94 - high * 0.35
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }
}
