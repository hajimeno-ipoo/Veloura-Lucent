import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct DiagnosticStageExportTests {
    private enum DiagnosticStageExportError: Error {
        case emptyExcerpt
        case startOutOfRange
    }

    @Test
    func providedRealAudioCanExportDiagnosticStagesAndReport() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["VELOURA_DIAGNOSTIC_INPUT"] else {
            return
        }

        let inputURL = URL(fileURLWithPath: inputPath)
        guard FileManager.default.fileExists(atPath: inputURL.path(percentEncoded: false)) else {
            Issue.record("Diagnostic input is missing: \(inputURL.path(percentEncoded: false))")
            return
        }

        let outputDirectory = URL(
            fileURLWithPath: environment["VELOURA_DIAGNOSTIC_OUTPUT_DIR"]
                ?? FileManager.default.temporaryDirectory.appending(path: "VelouraLucentStageDiagnostics").path(percentEncoded: false)
        )
        let correctionDiagnostics = outputDirectory.appending(path: "correction")
        let masteringDiagnostics = outputDirectory.appending(path: "mastering")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try resetDiagnosticDirectory(correctionDiagnostics)
        try resetDiagnosticDirectory(masteringDiagnostics)

        let startSeconds = Double(environment["VELOURA_DIAGNOSTIC_START_SECONDS"] ?? "") ?? 75
        let durationSeconds = Double(environment["VELOURA_DIAGNOSTIC_DURATION_SECONDS"] ?? "") ?? 30
        let sourceSignal = try AudioFileService.loadAudio(from: inputURL)
        let excerptSignal = try excerpt(from: sourceSignal, startSeconds: startSeconds, durationSeconds: durationSeconds)
        let excerptURL = outputDirectory.appending(path: "00_input_excerpt.wav")
        try AudioFileService.saveAudio(excerptSignal, to: excerptURL)
        let logs = DiagnosticLogCollector()

        let correctedURL = try await AudioProcessingService().process(
            inputFile: excerptURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: correctionDiagnostics
        ) { message in
            logs.append(message)
        }
        let correctedSignal = try AudioFileService.loadAudio(from: correctedURL)
        let correctedNoise = NoiseMeasurementService.analyze(signal: correctedSignal)
        let inputNoise = NoiseMeasurementService.analyze(signal: excerptSignal)

        let masteredURL = try await MasteringService().process(
            inputFile: correctedURL,
            settings: MasteringProfile.streaming.settings,
            referenceNoiseMeasurements: correctedNoise,
            originalReferenceFile: excerptURL,
            originalReferenceNoiseMeasurements: inputNoise,
            diagnosticOutputDirectory: masteringDiagnostics
        ) { _ in }

        let report = try diagnosticReport(
            inputURL: inputURL,
            excerptURL: excerptURL,
            correctedURL: correctedURL,
            masteredURL: masteredURL,
            correctionFiles: diagnosticWAVs(in: correctionDiagnostics),
            masteringFiles: diagnosticWAVs(in: masteringDiagnostics),
            startSeconds: startSeconds,
            durationSeconds: durationSeconds,
            denoiseMaskBreakdownLines: logs.values.filter { $0.hasPrefix("ノイズ除去/マスク内訳/") }
        )
        let reportURL = outputDirectory.appending(path: "VelouraLucent_Stage_Diagnostic_Report.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))
        #expect(report.contains("## 補正工程 前stage差分"))
        #expect(report.contains("## マスタリング工程 前stage差分"))
        #expect(report.contains("Δ16-20kHz"))
        #expect(try diagnosticWAVs(in: correctionDiagnostics).count == 11)
        #expect(try diagnosticWAVs(in: masteringDiagnostics).count == 15)
    }

    @Test
    func correctionAndMasteringCanExportDiagnosticStages() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "diagnostic-input.wav")
        let correctionDiagnostics = tempDirectory.appending(path: "correction-stages")
        let masteringDiagnostics = tempDirectory.appending(path: "mastering-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeDiagnosticTone(at: inputURL)

        let correctedURL = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: correctionDiagnostics
        ) { _ in }
        let correctedSignal = try AudioFileService.loadAudio(from: correctedURL)
        let correctedNoise = NoiseMeasurementService.analyze(signal: correctedSignal)
        let inputSignal = try AudioFileService.loadAudio(from: inputURL)
        let inputNoise = NoiseMeasurementService.analyze(signal: inputSignal)

        let masteredURL = try await MasteringService().process(
            inputFile: correctedURL,
            settings: MasteringProfile.streaming.settings,
            referenceNoiseMeasurements: correctedNoise,
            originalReferenceFile: inputURL,
            originalReferenceNoiseMeasurements: inputNoise,
            diagnosticOutputDirectory: masteringDiagnostics
        ) { _ in }

        let correctionFiles = try diagnosticWAVs(in: correctionDiagnostics)
        let masteringFiles = try diagnosticWAVs(in: masteringDiagnostics)
        let report = try diagnosticReport(
            inputURL: inputURL,
            excerptURL: inputURL,
            correctedURL: correctedURL,
            masteredURL: masteredURL,
            correctionFiles: correctionFiles,
            masteringFiles: masteringFiles,
            startSeconds: 0,
            durationSeconds: 1.2
        )

        #expect(correctionFiles.count == 11)
        #expect(masteringFiles.count == 15)
        #expect(correctionFiles.contains { $0.lastPathComponent.contains("02_correction_denoise") })
        #expect(correctionFiles.contains { $0.lastPathComponent.contains("08_correction_correctionHighPreserve") })
        #expect(masteringFiles.contains { $0.lastPathComponent.contains("08_mastering_highReturnGuard") })
        #expect(masteringFiles.contains { $0.lastPathComponent.contains("09_mastering_noiseReturnGuard") })
        #expect(report.contains("## 補正工程 前stage差分"))
        #expect(report.contains("## マスタリング工程 前stage差分"))
        #expect(report.contains("Δ8-12kHz"))
        #expect(report.contains("->"))
    }

    @Test
    func denoiseDiagnosticLogsMaskBreakdownByHighBand() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "diagnostic-mask-input.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        let logs = DiagnosticLogCollector()
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeDiagnosticTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { message in
            logs.append(message)
        }

        let breakdownLines = logs.values.filter { $0.hasPrefix("ノイズ除去/マスク内訳/") }

        #expect(breakdownLines.contains { $0.contains("pass 1/8-12kHz") && $0.contains("raw") && $0.contains("final") })
        #expect(breakdownLines.contains { $0.contains("pass 1/12-16kHz") && $0.contains("granular") && $0.contains("shimmer") })
        #expect(breakdownLines.contains { $0.contains("pass 1/16-20kHz") && $0.contains("combined") && $0.contains("final") })
    }

    @Test
    func denoisePreservesSustainedMusicalHighBandsBeforeSibilanceGuard() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "denoise-sustained-highs.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeDenoiseSustainedHighBandTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let lowCleaned = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "01_correction_lowNoiseCleanup"))
        let denoised = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let sparkleDrop = bandLevelDB(signal: denoised, lower: 8_000, upper: 12_000)
            - bandLevelDB(signal: lowCleaned, lower: 8_000, upper: 12_000)
        let airDrop = bandLevelDB(signal: denoised, lower: 12_000, upper: 16_000)
            - bandLevelDB(signal: lowCleaned, lower: 12_000, upper: 16_000)
        let ultraAirDrop = bandLevelDB(signal: denoised, lower: 16_000, upper: 20_000)
            - bandLevelDB(signal: lowCleaned, lower: 16_000, upper: 20_000)

        #expect(sparkleDrop >= -2.0)
        #expect(airDrop >= -2.0)
        #expect(ultraAirDrop >= -2.5)
    }

    @Test
    func denoiseReducesQuietHissWithoutDullingMusicalAir() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "denoise-hiss-and-air.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeDenoiseHissWithMusicalAirTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let lowCleaned = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "01_correction_lowNoiseCleanup"))
        let denoised = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let quietBefore = try bandLevelDB(signal: excerpt(from: lowCleaned, startSeconds: 0.10, durationSeconds: 0.45), lower: 12_000, upper: 16_000)
        let quietAfter = try bandLevelDB(signal: excerpt(from: denoised, startSeconds: 0.10, durationSeconds: 0.45), lower: 12_000, upper: 16_000)
        let musicBefore = try bandLevelDB(signal: excerpt(from: lowCleaned, startSeconds: 1.10, durationSeconds: 0.70), lower: 12_000, upper: 16_000)
        let musicAfter = try bandLevelDB(signal: excerpt(from: denoised, startSeconds: 1.10, durationSeconds: 0.70), lower: 12_000, upper: 16_000)

        #expect(quietAfter <= quietBefore - 1.0)
        #expect(musicAfter >= musicBefore - 2.0)
    }

    @Test
    func denoiseReducesBackgroundHissUnderMusicWithoutRemovingTonalAir() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "denoise-background-hiss-under-music.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeDenoiseBackgroundHissUnderMusicTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let lowCleaned = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "01_correction_lowNoiseCleanup"))
        let denoised = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let musicBefore = try excerpt(from: lowCleaned, startSeconds: 1.10, durationSeconds: 0.70)
        let musicAfter = try excerpt(from: denoised, startSeconds: 1.10, durationSeconds: 0.70)
        let hissBefore = bandLevelDB(signal: musicBefore, lower: 16_000, upper: 20_000)
        let hissAfter = bandLevelDB(signal: musicAfter, lower: 16_000, upper: 20_000)
        let airBefore = bandLevelDB(signal: musicBefore, lower: 12_000, upper: 16_000)
        let airAfter = bandLevelDB(signal: musicAfter, lower: 12_000, upper: 16_000)

        #expect(hissAfter <= hissBefore - 0.6)
        #expect(airAfter >= airBefore - 2.0)
    }

    @Test
    func correctionHighPreserveRestoresMusicalHighBandsWithoutReturningUltraHiss() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "correction-high-preserve-musical-air.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        let logs = DiagnosticLogCollector()
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeCorrectionHighPreserveTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { message in
            logs.append(message)
        }

        let shimmerLimited = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "07_correction_shimmerPeakLimit"))
        let highPreserved = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "08_correction_correctionHighPreserve"))
        let brillianceLift = bandLevelDB(signal: highPreserved, lower: 8_000, upper: 12_000)
            - bandLevelDB(signal: shimmerLimited, lower: 8_000, upper: 12_000)
        let airLift = bandLevelDB(signal: highPreserved, lower: 12_000, upper: 16_000)
            - bandLevelDB(signal: shimmerLimited, lower: 12_000, upper: 16_000)
        let ultraLift = bandLevelDB(signal: highPreserved, lower: 16_000, upper: 20_000)
            - bandLevelDB(signal: shimmerLimited, lower: 16_000, upper: 20_000)

        #expect(logs.values.contains { $0.hasPrefix("補正後高域保持/") })
        #expect(brillianceLift >= 0.10)
        #expect(airLift >= 0.10)
        #expect(ultraLift <= 0.35)
    }

    @Test
    func diagnosticDirectoryResetRemovesStaleWAVs() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "correction")
        try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        let staleFile = diagnostics.appending(path: "99_old_stage.wav")
        try Data("old".utf8).write(to: staleFile)

        try resetDiagnosticDirectory(diagnostics)

        #expect(try diagnosticWAVs(in: diagnostics).isEmpty)
    }

    @Test
    func diagnosticExcerptRejectsOutOfRangeStart() throws {
        let signal = AudioSignal(channels: [[0, 0]], sampleRate: 1)
        var didRejectStart = false

        do {
            _ = try excerpt(from: signal, startSeconds: 2, durationSeconds: 1)
            Issue.record("Out-of-range diagnostic excerpt start should be rejected")
        } catch DiagnosticStageExportError.startOutOfRange {
            didRejectStart = true
        } catch {
            Issue.record("Unexpected diagnostic excerpt error: \(error)")
        }

        #expect(didRejectStart)
    }

    @Test
    func sibilanceGuardPreservesSustainedBrillianceAndAir() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "sustained-brilliance.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeSustainedBrillianceTone(at: inputURL)

        var settings = DenoiseStrength.strong.settings
        settings.correctionIntensity = 0.82
        settings.noiseDetectionSensitivity = 0.82
        settings.highNaturalness = 0.86

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong,
            correctionSettings: settings,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let denoisedMetrics = try AudioComparisonService.analyze(fileURL: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let guardedMetrics = try AudioComparisonService.analyze(fileURL: diagnosticFile(in: diagnostics, containing: "03_correction_sibilanceShimmerGuard"))

        #expect(band("sparkle", in: guardedMetrics) >= band("sparkle", in: denoisedMetrics) - 1.5)
        #expect(band("air", in: guardedMetrics) >= band("air", in: denoisedMetrics) - 1.0)
    }

    @Test
    func sibilanceGuardReducesOnlyShortSibilancePeaks() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "short-sibilance-bursts.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeSibilanceBurstTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let denoised = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let guarded = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "03_correction_sibilanceShimmerGuard"))
        let denoisedPeak = maxWindowBandRMSDB(signal: denoised, lower: 5_000, upper: 9_000)
        let guardedPeak = maxWindowBandRMSDB(signal: guarded, lower: 5_000, upper: 9_000)
        let denoisedMetrics = try AudioComparisonService.analyze(signal: denoised)
        let guardedMetrics = try AudioComparisonService.analyze(signal: guarded)
        let denoisedBrilliance = band("sparkle", in: denoisedMetrics)
        let guardedBrilliance = band("sparkle", in: guardedMetrics)

        #expect(guardedPeak <= denoisedPeak - 0.3)
        #expect(guardedBrilliance >= denoisedBrilliance - 1.5)
    }

    @Test
    func sibilanceGuardPreservesSustainedPresenceBand() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "sustained-presence.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeSustainedPresenceTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let denoised = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let guarded = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "03_correction_sibilanceShimmerGuard"))
        let denoisedPresence = try bandLevelDB(signal: excerpt(from: denoised, startSeconds: 0.45, durationSeconds: 0.9), lower: 6_000, upper: 8_000)
        let guardedPresence = try bandLevelDB(signal: excerpt(from: guarded, startSeconds: 0.45, durationSeconds: 0.9), lower: 6_000, upper: 8_000)

        #expect(guardedPresence >= denoisedPresence - 0.5)
    }

    @Test
    func sibilanceGuardReducesShortUpperBitePeaksWithoutDullingSustainedBrilliance() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "short-upper-bite-bursts.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeUpperBiteBurstTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let denoised = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let guarded = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "03_correction_sibilanceShimmerGuard"))
        let denoisedPeak = maxWindowBandRMSDB(signal: denoised, lower: 9_000, upper: 10_000)
        let guardedPeak = maxWindowBandRMSDB(signal: guarded, lower: 9_000, upper: 10_000)
        let denoisedSteady = try bandLevelDB(signal: excerpt(from: denoised, startSeconds: 0.22, durationSeconds: 0.12), lower: 9_000, upper: 10_000)
        let guardedSteady = try bandLevelDB(signal: excerpt(from: guarded, startSeconds: 0.22, durationSeconds: 0.12), lower: 9_000, upper: 10_000)

        #expect(guardedPeak <= denoisedPeak - 0.2)
        #expect(guardedSteady >= denoisedSteady - 0.5)
    }

    @Test
    func sibilanceGuardPreservesSustainedShimmerBand() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "sustained-shimmer.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeSustainedShimmerTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let denoised = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let guarded = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "03_correction_sibilanceShimmerGuard"))
        let denoisedShimmer = try bandLevelDB(signal: excerpt(from: denoised, startSeconds: 0.35, durationSeconds: 1.3), lower: 10_000, upper: 14_000)
        let guardedShimmer = try bandLevelDB(signal: excerpt(from: guarded, startSeconds: 0.35, durationSeconds: 1.3), lower: 10_000, upper: 14_000)

        #expect(guardedShimmer >= denoisedShimmer - 0.4)
    }

    @Test
    func sibilanceGuardReducesOnlyShortShimmerPeaks() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inputURL = tempDirectory.appending(path: "short-shimmer-bursts.wav")
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try makeShortShimmerBurstTone(at: inputURL)

        _ = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let denoised = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let guarded = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "03_correction_sibilanceShimmerGuard"))
        let denoisedPeak = maxWindowBandRMSDB(signal: denoised, lower: 10_000, upper: 14_000)
        let guardedPeak = maxWindowBandRMSDB(signal: guarded, lower: 10_000, upper: 14_000)

        #expect(guardedPeak <= denoisedPeak - 0.15)
    }

    private func diagnosticWAVs(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "wav" }
    }

    private func resetDiagnosticDirectory(_ directory: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path(percentEncoded: false)) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func makeDiagnosticTone(at url: URL, duration: Double = 1.2, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)

        for channelIndex in 0..<2 {
            guard let destination = buffer.floatChannelData?[channelIndex] else { continue }
            for index in 0..<frameCount {
                let t = Double(index) / sampleRate
                let base = sin(2 * Double.pi * 440 * t) * 0.18
                let air = sin(2 * Double.pi * 11_000 * t) * 0.018
                let hiss = sin(2 * Double.pi * 15_000 * t) * 0.006
                destination[index] = Float(base + air + hiss)
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func makeDenoiseSustainedHighBandTone(at url: URL, duration: Double = 2.2, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 220 * time) * 0.06
                + sin(2 * Double.pi * 440 * time) * 0.05
            let sparkle = sin(2 * Double.pi * 9_600 * time) * 0.030
            let air = sin(2 * Double.pi * 13_200 * time) * 0.023
            let ultraAir = sin(2 * Double.pi * 18_200 * time) * 0.014
            channel[index] = Float(body + sparkle + air + ultraAir)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeDenoiseHissWithMusicalAirTone(at url: URL, duration: Double = 2.4, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let musicEnvelope = time > 0.85 ? 1.0 : 0.0
            let body = (sin(2 * Double.pi * 220 * time) * 0.05
                + sin(2 * Double.pi * 440 * time) * 0.04) * musicEnvelope
            let musicalAir = (sin(2 * Double.pi * 13_200 * time) * 0.022
                + sin(2 * Double.pi * 18_200 * time) * 0.010) * musicEnvelope
            let hiss = sin(2 * Double.pi * 12_600 * time) * 0.010
                + sin(2 * Double.pi * 15_300 * time) * 0.008
                + sin(2 * Double.pi * 17_400 * time) * 0.006
            channel[index] = Float(body + musicalAir + hiss * (musicEnvelope > 0 ? 0.45 : 1.0))
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeDenoiseBackgroundHissUnderMusicTone(at url: URL, duration: Double = 2.4, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        var random = DiagnosticDeterministicRandom(seed: 0xB45E_A17)
        var noise = Array(repeating: Float.zero, count: frameCount)
        for index in 0..<frameCount {
            noise[index] = Float((random.nextDouble() * 2 - 1) * 0.04)
        }
        let highNoise = SpectralDSP.highPass(noise, cutoff: 16_000, sampleRate: sampleRate)
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let musicEnvelope = time > 0.85 ? 1.0 : 0.0
            let body = (sin(2 * Double.pi * 220 * time) * 0.05
                + sin(2 * Double.pi * 440 * time) * 0.04) * musicEnvelope
            let musicalAir = sin(2 * Double.pi * 13_200 * time) * 0.026 * musicEnvelope
            let backgroundHiss = Double(highNoise[index])
            channel[index] = Float(body + musicalAir + backgroundHiss)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeCorrectionHighPreserveTone(at url: URL, duration: Double = 2.4, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 220 * time) * 0.065
                + sin(2 * Double.pi * 440 * time) * 0.055
                + sin(2 * Double.pi * 880 * time) * 0.020
            let brilliance = sin(2 * Double.pi * 9_600 * time) * 0.030
            let air = sin(2 * Double.pi * 13_200 * time) * 0.024
            let ultraHiss = sin(2 * Double.pi * 17_600 * time) * 0.004
            channel[index] = Float(body + brilliance + air + ultraHiss)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeSustainedBrillianceTone(at url: URL, duration: Double = 2.0, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.08
            let brilliance = sin(2 * Double.pi * 9_600 * time) * 0.034
            let air = sin(2 * Double.pi * 13_200 * time) * 0.026
            channel[index] = Float(body + brilliance + air)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeSibilanceBurstTone(at url: URL, duration: Double = 2.4, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.08
            let sustainedBrilliance = sin(2 * Double.pi * 9_600 * time) * 0.014
            let phase = time.truncatingRemainder(dividingBy: 0.48)
            let burstEnvelope = phase > 0.10 && phase < 0.145 ? 1.0 : 0.0
            let sibilance = sin(2 * Double.pi * 7_200 * time) * 0.075 * burstEnvelope
            channel[index] = Float(body + sustainedBrilliance + sibilance)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeSustainedPresenceTone(at url: URL, duration: Double = 2.0, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.08
            let presence = sin(2 * Double.pi * 7_200 * time) * 0.030
            let brilliance = sin(2 * Double.pi * 9_600 * time) * 0.012
            channel[index] = Float(body + presence + brilliance)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeUpperBiteBurstTone(at url: URL, duration: Double = 2.4, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.08
            let sustainedBrilliance = sin(2 * Double.pi * 9_600 * time) * 0.014
            let phase = time.truncatingRemainder(dividingBy: 0.48)
            let burstEnvelope = phase > 0.10 && phase < 0.145 ? 1.0 : 0.0
            let upperBite = sin(2 * Double.pi * 9_500 * time) * 0.085 * burstEnvelope
            channel[index] = Float(body + sustainedBrilliance + upperBite)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeSustainedShimmerTone(at url: URL, duration: Double = 2.0, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.08
            let shimmer = sin(2 * Double.pi * 12_600 * time) * 0.030
            channel[index] = Float(body + shimmer)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func makeShortShimmerBurstTone(at url: URL, duration: Double = 2.4, sampleRate: Double = 48_000) throws {
        let frameCount = Int(duration * sampleRate)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let channel = buffer.floatChannelData![0]
        for index in 0..<frameCount {
            let time = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 440 * time) * 0.08
            let sustainedAir = sin(2 * Double.pi * 13_200 * time) * 0.012
            let phase = time.truncatingRemainder(dividingBy: 0.48)
            let burstEnvelope = phase > 0.10 && phase < 0.145 ? 1.0 : 0.0
            let shimmer = sin(2 * Double.pi * 12_600 * time) * 0.085 * burstEnvelope
            channel[index] = Float(body + sustainedAir + shimmer)
        }

        let file = try AVAudioFile(forWriting: url, settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 1))
        try file.write(from: buffer)
    }

    private func excerpt(from signal: AudioSignal, startSeconds: Double, durationSeconds: Double) throws -> AudioSignal {
        guard signal.frameCount > 0, durationSeconds > 0 else {
            throw DiagnosticStageExportError.emptyExcerpt
        }

        let requestedStart = max(0, Int(startSeconds * signal.sampleRate))
        guard requestedStart < signal.frameCount else {
            throw DiagnosticStageExportError.startOutOfRange
        }

        let length = min(max(1, Int(durationSeconds * signal.sampleRate)), signal.frameCount - requestedStart)
        guard length > 0 else {
            throw DiagnosticStageExportError.emptyExcerpt
        }

        let channels = signal.channels.map { channel in
            Array(channel[requestedStart..<(requestedStart + length)])
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func diagnosticReport(
        inputURL: URL,
        excerptURL: URL,
        correctedURL: URL,
        masteredURL: URL,
        correctionFiles: [URL],
        masteringFiles: [URL],
        startSeconds: Double,
        durationSeconds: Double,
        denoiseMaskBreakdownLines: [String] = []
    ) throws -> String {
        let correctionMetrics = try diagnosticStageMetrics(for: correctionFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }))
        let masteringMetrics = try diagnosticStageMetrics(for: masteringFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }))

        var lines: [String] = [
            "# Veloura Lucent Stage Diagnostic Report",
            "",
            "- 入力: \(inputURL.path(percentEncoded: false))",
            "- 抜き出し: \(String(format: "%.2f", startSeconds))秒から\(String(format: "%.2f", durationSeconds))秒",
            "- 抜き出しWAV: \(excerptURL.path(percentEncoded: false))",
            "- 補正後WAV: \(correctedURL.path(percentEncoded: false))",
            "- 最終版WAV: \(masteredURL.path(percentEncoded: false))",
            "",
            "## 補正工程",
            "",
            diagnosticTableHeader()
        ]
        for metric in correctionMetrics {
            lines.append(diagnosticTableRow(for: metric))
        }
        lines.append(contentsOf: diagnosticDeltaSection(title: "補正工程 前stage差分", metrics: correctionMetrics))
        lines.append(contentsOf: [
            "",
            "## マスタリング工程",
            "",
            diagnosticTableHeader()
        ])
        for metric in masteringMetrics {
            lines.append(diagnosticTableRow(for: metric))
        }
        lines.append(contentsOf: diagnosticDeltaSection(title: "マスタリング工程 前stage差分", metrics: masteringMetrics))
        if !denoiseMaskBreakdownLines.isEmpty {
            lines.append(contentsOf: [
                "",
                "## denoise マスク内訳",
                "",
                "```text"
            ])
            lines.append(contentsOf: denoiseMaskBreakdownLines)
            lines.append("```")
        }
        return lines.joined(separator: "\n")
    }

    private func diagnosticTableHeader() -> String {
        "| ファイル | LUFS | TP dBFS | 8-12kHz | 12-16kHz | 16-20kHz |\n|---|---:|---:|---:|---:|---:|"
    }

    private func diagnosticStageMetrics(for files: [URL]) throws -> [DiagnosticStageMetric] {
        try files.map { file in
            let metrics = try AudioComparisonService.analyze(fileURL: file)
            return DiagnosticStageMetric(
                fileName: file.lastPathComponent,
                integratedLoudnessLUFS: metrics.integratedLoudnessLUFS,
                truePeakDBFS: metrics.truePeakDBFS,
                sparkleDB: band("sparkle", in: metrics),
                airDB: band("air", in: metrics),
                ultraAirDB: band("ultraAir", in: metrics)
            )
        }
    }

    private func diagnosticTableRow(for metric: DiagnosticStageMetric) -> String {
        "| \(metric.fileName) | \(format(metric.integratedLoudnessLUFS)) | \(format(metric.truePeakDBFS)) | \(format(metric.sparkleDB)) | \(format(metric.airDB)) | \(format(metric.ultraAirDB)) |"
    }

    private func diagnosticDeltaSection(title: String, metrics: [DiagnosticStageMetric]) -> [String] {
        guard metrics.count > 1 else { return [] }
        var lines = [
            "",
            "## \(title)",
            "",
            "| 変化 | Δ8-12kHz | Δ12-16kHz | Δ16-20kHz |",
            "|---|---:|---:|---:|"
        ]
        for index in metrics.indices.dropFirst() {
            let previous = metrics[metrics.index(before: index)]
            let current = metrics[index]
            lines.append(
                "| \(previous.fileName) -> \(current.fileName) | \(formatDelta(current.sparkleDB - previous.sparkleDB)) | \(formatDelta(current.airDB - previous.airDB)) | \(formatDelta(current.ultraAirDB - previous.ultraAirDB)) |"
            )
        }
        return lines
    }

    private func band(_ id: String, in metrics: AudioMetricSnapshot) -> Double {
        metrics.bandEnergies.first { $0.id == id }?.levelDB ?? -120
    }

    private func diagnosticFile(in directory: URL, containing fragment: String) throws -> URL {
        try #require(diagnosticWAVs(in: directory).first { $0.lastPathComponent.contains(fragment) })
    }

    private func bandLevelDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let mono = signal.monoMixdown()
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(mono, cutoff: lower, sampleRate: signal.sampleRate),
            cutoff: upper,
            sampleRate: signal.sampleRate
        )
        let meanSquare = band.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(band.count, 1))
        return 10 * log10(max(meanSquare, 1e-12))
    }

    private func maxWindowBandRMSDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let mono = signal.monoMixdown()
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(mono, cutoff: lower, sampleRate: signal.sampleRate),
            cutoff: upper,
            sampleRate: signal.sampleRate
        )
        let windowSize = max(1, Int(signal.sampleRate * 0.035))
        let hopSize = max(1, windowSize / 2)
        var best = 0.0
        var start = 0
        while start < band.count {
            let end = min(start + windowSize, band.count)
            let meanSquare = band[start..<end].reduce(0.0) { $0 + Double($1 * $1) } / Double(max(end - start, 1))
            best = max(best, meanSquare)
            start += hopSize
        }
        return 10 * log10(max(best, 1e-12))
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatDelta(_ value: Double) -> String {
        String(format: "%+.2f dB", value)
    }
}

private struct DiagnosticStageMetric {
    let fileName: String
    let integratedLoudnessLUFS: Double
    let truePeakDBFS: Double
    let sparkleDB: Double
    let airDB: Double
    let ultraAirDB: Double
}

private final class DiagnosticLogCollector: @unchecked Sendable {
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

private struct DiagnosticDeterministicRandom {
    var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func nextDouble() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let value = Double((state >> 11) & ((1 << 53) - 1))
        return value / Double(1 << 53)
    }
}
