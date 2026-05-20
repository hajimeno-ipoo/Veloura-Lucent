import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct AudioProcessingPipelineTests {
    @Test
    func pipelineProducesOutputFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "input.wav")

        try makeTestTone(at: inputURL)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong
        ) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(output.lastPathComponent.contains("input_lifter"))
        let written = try AVAudioFile(forReading: output)
        #expect(written.length > 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: written.processingFormat, frameCapacity: AVAudioFrameCount(written.length))!
        try written.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        #expect(samples.contains { $0.isFinite })
        #expect(samples.map { abs($0) }.max() ?? 0 <= 1.01)
    }

    @Test
    func pipelineHandlesLocalizedFilename() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "violin #002 睡眠.wav")

        try makeTestTone(at: inputURL, duration: 6)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .gentle
        ) { _ in }

        #expect(output.lastPathComponent.contains("_lifter_"))
        #expect(FileManager.default.fileExists(atPath: output.path(percentEncoded: false)))
    }

    @Test
    func pipelineAcceptsExperimentalMetalAnalysisMode() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "metal-analysis.wav")

        try makeTestTone(at: inputURL)

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .experimentalMetal
        ) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
    }

    @Test
    func pipelineAcceptsAutoAnalysisMode() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "auto-analysis.wav")

        try makeTestTone(at: inputURL)
        let logs = LogCollector()

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .auto
        ) { message in
            logs.append(message)
        }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(logs.values.contains("解析モード: 自動 -> \(AudioAnalysisMode.auto.resolvedMode.title)"))
        #expect(logs.values.contains { $0.hasPrefix("合計: ") && $0.hasSuffix("秒") })
    }

    @Test
    func pipelineAcceptsCustomCorrectionSettings() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "custom-correction.wav")

        try makeTestTone(at: inputURL)
        var settings = DenoiseStrength.balanced.settings
        settings.highNaturalness = 0.74
        settings.airRepair = 0.42

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            correctionSettings: settings,
            analysisMode: .cpu
        ) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
    }

    @Test
    func strongerCorrectionSettingsReduceMeasuredHighNoise() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "hissy-input.wav")

        try makeNoisyTone(at: inputURL)

        var strongerSettings = DenoiseStrength.balanced.settings
        strongerSettings.correctionIntensity = 0.78
        strongerSettings.highNaturalness = 0.88
        strongerSettings.noiseDetectionSensitivity = 0.78
        strongerSettings.airRepair = 0.32

        let defaultOutput = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            correctionSettings: DenoiseStrength.balanced.settings,
            analysisMode: .cpu
        ) { _ in }
        let strongerOutput = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            correctionSettings: strongerSettings,
            analysisMode: .cpu
        ) { _ in }

        let defaultSignal = try AudioFileService.loadAudio(from: defaultOutput)
        let strongerSignal = try AudioFileService.loadAudio(from: strongerOutput)
        let defaultQuietHiss = bandRMSDB(
            signal: excerpt(from: defaultSignal, startSeconds: 0.10, durationSeconds: 0.50),
            lower: 12_000,
            upper: 16_000
        )
        let strongerQuietHiss = bandRMSDB(
            signal: excerpt(from: strongerSignal, startSeconds: 0.10, durationSeconds: 0.50),
            lower: 12_000,
            upper: 16_000
        )
        let defaultMusicalAir = bandRMSDB(
            signal: excerpt(from: defaultSignal, startSeconds: 1.10, durationSeconds: 0.60),
            lower: 12_000,
            upper: 16_000
        )
        let strongerMusicalAir = bandRMSDB(
            signal: excerpt(from: strongerSignal, startSeconds: 1.10, durationSeconds: 0.60),
            lower: 12_000,
            upper: 16_000
        )

        #expect(strongerQuietHiss <= defaultQuietHiss - 1.0)
        #expect(strongerMusicalAir >= defaultMusicalAir - 1.5)
    }

    @Test
    func correctionPreservesMusicalAirWhileKeepingNoiseBelowOriginal() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "bright-air-correction.wav")
        let logs = LogCollector()

        try makeBrightAirTone(at: inputURL)

        var settings = DenoiseStrength.strong.settings
        settings.correctionIntensity = 0.82
        settings.noiseDetectionSensitivity = 0.82
        settings.highNaturalness = 0.86

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong,
            correctionSettings: settings,
            analysisMode: .cpu
        ) { message in
            logs.append(message)
        }

        let inputSignal = try AudioFileService.loadAudio(from: inputURL)
        let outputSignal = try AudioFileService.loadAudio(from: output)
        let inputNoise = NoiseMeasurementService.analyze(signal: inputSignal)
        let outputNoise = NoiseMeasurementService.analyze(signal: outputSignal)

        expectHighBandsNotDulled(reference: inputSignal, processed: outputSignal)
        #expect((outputNoise.comparableLevel(for: NoiseMeasurementID.hiss) ?? 0) <= (inputNoise.comparableLevel(for: NoiseMeasurementID.hiss) ?? 0) + 0.5)
        #expect((outputNoise.comparableLevel(for: NoiseMeasurementID.shimmer) ?? 0) <= (inputNoise.comparableLevel(for: NoiseMeasurementID.shimmer) ?? 0) + 0.5)
        #expect(
            logs.values.contains { $0.hasPrefix("補正後高域保持") }
                || bandRMSDB(signal: outputSignal, lower: 8_000, upper: 12_000)
                    >= bandRMSDB(signal: inputSignal, lower: 8_000, upper: 12_000) - 2.0
        )
    }

    @Test
    func correctionDoesNotLeaveMudWorseThanOriginal() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "muddy-correction.wav")
        let logs = LogCollector()

        try makeMuddyTone(at: inputURL)

        var settings = DenoiseStrength.strong.settings
        settings.lowMidCleanup = 0.82
        settings.correctionIntensity = 0.72

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong,
            correctionSettings: settings,
            analysisMode: .cpu
        ) { message in
            logs.append(message)
        }

        let inputSignal = try AudioFileService.loadAudio(from: inputURL)
        let outputSignal = try AudioFileService.loadAudio(from: output)
        let inputMud = try #require(NoiseMeasurementService.analyze(signal: inputSignal).comparableLevel(for: NoiseMeasurementID.mud))
        let outputMud = try #require(NoiseMeasurementService.analyze(signal: outputSignal).comparableLevel(for: NoiseMeasurementID.mud))

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(outputMud <= inputMud + 0.5)
        #expect(logs.values.contains { $0.hasPrefix("低中域残り: こもり悪化を抑制") } || outputMud <= inputMud)
        let mudMeasurementCount = try #require(parsedInteger(prefix: "低中域残り/測定回数: ", from: logs.values))
        #expect(mudMeasurementCount <= 2)
    }

    @Test
    func correctionMudGuardSelectsCandidateBeforeFinalMudMeasurement() async throws {
        let candidates = [
            MudCorrectionCandidateScore(index: 0, gainDB: -2.0, bandRMSDB: -24.9),
            MudCorrectionCandidateScore(index: 1, gainDB: -1.5, bandRMSDB: -25.4),
            MudCorrectionCandidateScore(index: 2, gainDB: -1.0, bandRMSDB: -25.1),
            MudCorrectionCandidateScore(index: 3, gainDB: -0.5, bandRMSDB: -24.7)
        ]

        let selected = try #require(MudCorrectionCandidateSelector.select(candidates))
        #expect(selected.index == 1)
        #expect(selected.gainDB == -1.5)
    }


    @Test
    func shimmerLimiterDoesNotUseFiveFullMeasurementPasses() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "shimmer-loop-input.wav")
        let logs = LogCollector()

        try makeNoisyTone(at: inputURL)

        var settings = DenoiseStrength.strong.settings
        settings.correctionIntensity = 0.82
        settings.noiseDetectionSensitivity = 0.82
        settings.highNaturalness = 0.86

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong,
            correctionSettings: settings,
            analysisMode: .cpu
        ) { message in
            logs.append(message)
        }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        if let measurementCount = parsedInteger(prefix: "シマー制限/測定回数: ", from: logs.values) {
            #expect(measurementCount <= 3)
        } else {
            #expect(logs.values.contains { $0.hasPrefix("ルート/補正: シマー制限 = スキップ") })
        }
        #expect(!logs.values.contains("シマー制限/測定: 4/5"))
        #expect(!logs.values.contains("シマー制限/測定: 5/5"))
    }

    @Test
    func maximumLowCleanupKeepsRumbleBandPolarity() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "rumbly-input.wav")

        try makeRumblyTone(at: inputURL)
        var settings = DenoiseStrength.strong.settings
        settings.lowCleanup = 1
        settings.noiseDetectionSensitivity = 1
        settings.correctionIntensity = 1

        let output = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong,
            correctionSettings: settings,
            analysisMode: .cpu
        ) { _ in }

        let inputBand = try bandSamples(from: inputURL, lower: 35, upper: 80)
        let outputBand = try bandSamples(from: output, lower: 35, upper: 80)
        let dotProduct = zip(inputBand, outputBand).reduce(Float.zero) { partial, pair in
            partial + pair.0 * pair.1
        }

        #expect(dotProduct > 0)
        #expect(outputBand.allSatisfy { $0.isFinite })
    }

    @Test
    func correctionLeavesFinalLoudnessToMastering() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "mastering-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "loudness-reference.wav")

        try makeTestTone(at: inputURL, duration: 3)

        let correctedOutput = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu
        ) { _ in }
        let masteredOutput = try await MasteringService().process(
            inputFile: correctedOutput,
            settings: MasteringProfile.streaming.settings,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let inputSignal = try AudioFileService.loadAudio(from: inputURL)
        let correctedSignal = try AudioFileService.loadAudio(from: correctedOutput)
        let masteredSignal = try AudioFileService.loadAudio(from: masteredOutput)
        let inputLoudness = MasteringAnalysisService.integratedLoudness(signal: inputSignal)
        let correctedLoudness = MasteringAnalysisService.integratedLoudness(signal: correctedSignal)
        let masteredLoudness = MasteringAnalysisService.integratedLoudness(signal: masteredSignal)
        let baselineLoudness = MasteringAnalysisService.integratedLoudness(
            signal: try AudioFileService.loadAudio(from: audioProcessingDiagnosticFile(in: diagnostics, containing: "06_mastering_stereo"))
        )
        let masteredPeak = MasteringAnalysisService.approximateTruePeak(masteredSignal.channels)
        let policy = MasteringProfile.streaming.settings.loudnessAdjustmentPolicy

        #expect(correctedLoudness < inputLoudness - 3)
        #expect(masteredLoudness > correctedLoudness)
        #expect(Double(masteredLoudness - baselineLoudness) <= policy.maxBoostDB + 0.2)
        #expect(masteredPeak <= powf(10, MasteringProfile.streaming.settings.peakCeilingDB / 20) + 0.02)
    }

    @Test
    func outputURLsUseWavEvenWhenInputExtensionIsCompressed() {
        let inputURL = URL(fileURLWithPath: "/tmp/demo-track.mp3")

        let defaultOutput = AudioProcessingService.defaultOutputURL(for: inputURL)
        let temporaryOutput = AudioProcessingService.temporaryOutputURL(for: inputURL)

        #expect(defaultOutput.pathExtension == AudioFileService.outputFileExtension)
        #expect(temporaryOutput.pathExtension == AudioFileService.outputFileExtension)
    }

    private func makeTestTone(at url: URL, duration: Double = 2) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            channel[index] = Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate) * 0.1)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func makeNoisyTone(at url: URL, duration: Double = 2) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let musicEnvelope = time > 0.85 ? 1.0 : 0.0
            let body = sin(2 * Double.pi * 440 * time) * 0.09 * musicEnvelope
            let musicalAir = sin(2 * Double.pi * 13_200 * time) * 0.022 * musicEnvelope
            let hiss = sin(2 * Double.pi * 11_700 * time) * 0.026
                + sin(2 * Double.pi * 13_900 * time) * 0.022
            let flicker = (index / 240) % 2 == 0 ? 1.0 : 0.55
            channel[index] = Float(body + musicalAir + hiss * flicker * (musicEnvelope > 0 ? 0.45 : 1.0))
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func makeBrightAirTone(at url: URL, duration: Double = 2) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.08
            let brilliance = sin(2 * Double.pi * 9_600 * time) * 0.035
            let air = sin(2 * Double.pi * 13_200 * time) * 0.028
            let ultra = sin(2 * Double.pi * 17_200 * time) * 0.012
            channel[index] = Float(body + brilliance + air + ultra)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func makeRumblyTone(at url: URL, duration: Double = 1) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.04
            let rumble = sin(2 * Double.pi * 50 * time) * 0.08
            channel[index] = Float(body + rumble)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func makeMuddyTone(at url: URL, duration: Double = 2) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 190 * time) * 0.06
            let lowMid = sin(2 * Double.pi * 520 * time) * 0.08
                + sin(2 * Double.pi * 820 * time) * 0.055
            let air = sin(2 * Double.pi * 9_600 * time) * 0.010
            channel[index] = Float(body + lowMid + air)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1)
        )
        try file.write(from: buffer)
    }

    private func bandRMS(from url: URL, lower: Double, upper: Double) throws -> Float {
        let band = try bandSamples(from: url, lower: lower, upper: upper)
        let meanSquare = band.reduce(Float.zero) { $0 + $1 * $1 } / Float(max(band.count, 1))
        return sqrtf(meanSquare)
    }

    private func bandRMSDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let upperBound = min(upper, signal.sampleRate * 0.5 - 100)
        guard lower < upperBound else { return -120 }
        let mono = signal.monoMixdown()
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(mono, cutoff: lower, sampleRate: signal.sampleRate),
            cutoff: upperBound,
            sampleRate: signal.sampleRate
        )
        let meanSquare = band.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(band.count, 1))
        return 10 * log10(max(meanSquare, 1e-12))
    }

    private func excerpt(from signal: AudioSignal, startSeconds: Double, durationSeconds: Double) -> AudioSignal {
        let start = min(max(0, Int(startSeconds * signal.sampleRate)), signal.frameCount)
        let length = min(max(1, Int(durationSeconds * signal.sampleRate)), max(signal.frameCount - start, 0))
        let end = min(signal.frameCount, start + length)
        let channels = signal.channels.map { channel in
            start < end ? Array(channel[start..<end]) : []
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func bandBalanceDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        bandRMSDB(signal: signal, lower: lower, upper: upper) - fullRMSDB(signal: signal)
    }

    private func expectHighBandsNotDulled(
        reference: AudioSignal,
        processed: AudioSignal,
        maxBrillianceDropDB: Double = 2.0,
        maxAirDropDB: Double = 2.0,
        maxUltraAirDropDB: Double = 2.5
    ) {
        #expect(
            bandRMSDB(signal: processed, lower: 8_000, upper: 12_000)
                >= bandRMSDB(signal: reference, lower: 8_000, upper: 12_000) - maxBrillianceDropDB
        )
        #expect(
            bandRMSDB(signal: processed, lower: 12_000, upper: 16_000)
                >= bandRMSDB(signal: reference, lower: 12_000, upper: 16_000) - maxAirDropDB
        )
        #expect(
            bandRMSDB(signal: processed, lower: 16_000, upper: 20_000)
                >= bandRMSDB(signal: reference, lower: 16_000, upper: 20_000) - maxUltraAirDropDB
        )
    }

    private func fullRMSDB(signal: AudioSignal) -> Double {
        let mono = signal.monoMixdown()
        let meanSquare = mono.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(mono.count, 1))
        return 10 * log10(max(meanSquare, 1e-12))
    }

    private func bandSamples(from url: URL, lower: Double, upper: Double) throws -> [Float] {
        let signal = try AudioFileService.loadAudio(from: url)
        guard let channel = signal.channels.first else { return [] }
        return SpectralDSP.lowPass(
            SpectralDSP.highPass(channel, cutoff: lower, sampleRate: signal.sampleRate),
            cutoff: upper,
            sampleRate: signal.sampleRate
        )
    }

    private func parsedInteger(prefix: String, from logs: [String]) -> Int? {
        logs.compactMap { line -> Int? in
            guard line.hasPrefix(prefix) else { return nil }
            return Int(line.dropFirst(prefix.count))
        }.last
    }

    private func audioProcessingDiagnosticFile(in directory: URL, containing fragment: String) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return try #require(contents.first { $0.lastPathComponent.contains(fragment) })
    }

}

private final class LogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }
}
