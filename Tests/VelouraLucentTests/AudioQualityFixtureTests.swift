import Foundation
import Testing
@testable import VelouraLucent

struct AudioQualityFixtureTests {
    @Test
    func fixedAudioQualityFixturesArePresentAndUsable() throws {
        let fixtureNames = [
            "bright_air_reference.wav",
            "hiss_under_music.wav",
            "short_shimmer_bursts.wav",
            "mixed_mastering_reference.wav"
        ]

        for fixtureName in fixtureNames {
            let signal = try audioQualityFixtureSignal(fixtureName)
            let metrics = try AudioComparisonService.analyze(signal: signal)

            #expect(signal.frameCount > 0)
            #expect(metrics.integratedLoudnessLUFS.isFinite)
            #expect(metrics.truePeakDBFS.isFinite)
            #expect(metrics.bandEnergies.count == 8)
        }
    }

    @Test
    func fixedBrightAirFixtureKeepsMusicalHighBandsAfterCorrection() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = try audioQualityFixtureURL("bright_air_reference.wav")
        let input = try AudioFileService.loadAudio(from: inputURL)

        let outputURL = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .strong,
            correctionSettings: DenoiseStrength.strong.settings,
            analysisMode: .cpu,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }
        let output = try AudioFileService.loadAudio(from: outputURL)

        expectAudioQualityHighBandsNotDulled(reference: input, processed: output)
        #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
    }

    @Test
    func fixedHissFixtureReducesQuietHissWithoutDullingMusicalAir() async throws {
        let inputURL = try audioQualityFixtureURL("hiss_under_music.wav")
        let outputURL = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            correctionSettings: DenoiseStrength.balanced.settings,
            analysisMode: .cpu
        ) { _ in }

        let input = try AudioFileService.loadAudio(from: inputURL)
        let output = try AudioFileService.loadAudio(from: outputURL)
        let quietBefore = try audioQualityExcerpt(from: input, startSeconds: 0.15, durationSeconds: 0.70)
        let quietAfter = try audioQualityExcerpt(from: output, startSeconds: 0.15, durationSeconds: 0.70)
        let musicBefore = try audioQualityExcerpt(from: input, startSeconds: 1.10, durationSeconds: 0.70)
        let musicAfter = try audioQualityExcerpt(from: output, startSeconds: 1.10, durationSeconds: 0.70)
        let inputNoise = NoiseMeasurementService.analyze(signal: input, ids: [NoiseMeasurementID.hiss])
        let outputNoise = NoiseMeasurementService.analyze(signal: output, ids: [NoiseMeasurementID.hiss])

        #expect(audioQualityBandRMSDB(signal: quietAfter, lower: 12_000, upper: 16_000)
            <= audioQualityBandRMSDB(signal: quietBefore, lower: 12_000, upper: 16_000) - 0.6)
        #expect(audioQualityBandRMSDB(signal: musicAfter, lower: 12_000, upper: 16_000)
            >= audioQualityBandRMSDB(signal: musicBefore, lower: 12_000, upper: 16_000) - 2.0)
        #expect((outputNoise.comparableLevel(for: NoiseMeasurementID.hiss) ?? -120)
            <= (inputNoise.comparableLevel(for: NoiseMeasurementID.hiss) ?? -120) + 0.5)
    }

    @Test
    func fixedShortShimmerFixtureReducesShortPeaksWithoutDullingSustainedHighs() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "correction-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = try audioQualityFixtureURL("short_shimmer_bursts.wav")

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

        let beforeGuard = try AudioFileService.loadAudio(from: audioQualityDiagnosticFile(in: diagnostics, containing: "02_correction_denoise"))
        let afterGuard = try AudioFileService.loadAudio(from: audioQualityDiagnosticFile(in: diagnostics, containing: "03_correction_sibilanceShimmerGuard"))

        #expect(audioQualityMaxWindowBandRMSDB(signal: afterGuard, lower: 10_000, upper: 14_000)
            <= audioQualityMaxWindowBandRMSDB(signal: beforeGuard, lower: 10_000, upper: 14_000) - 0.15)
        expectAudioQualityHighBandsNotDulled(reference: beforeGuard, processed: afterGuard, maxSparkleDropDB: 1.0, maxAirDropDB: 1.0, maxUltraAirDropDB: 1.5)
    }

    @Test
    func fixedMixedFixtureMeetsMasteringQualityBounds() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "mastering-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = try audioQualityFixtureURL("mixed_mastering_reference.wav")
        let input = try AudioFileService.loadAudio(from: inputURL)
        let inputNoise = NoiseMeasurementService.analyze(signal: input)
        let correctedURL = try await AudioProcessingService().process(
            inputFile: inputURL,
            denoiseStrength: .balanced,
            correctionSettings: DenoiseStrength.balanced.settings,
            analysisMode: .cpu
        ) { _ in }
        let corrected = try AudioFileService.loadAudio(from: correctedURL)
        let correctedNoise = NoiseMeasurementService.analyze(signal: corrected)
        let masteredURL = try await MasteringService().process(
            inputFile: correctedURL,
            settings: MasteringProfile.streaming.settings,
            referenceNoiseMeasurements: correctedNoise,
            originalReferenceFile: inputURL,
            originalReferenceNoiseMeasurements: inputNoise,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }
        let mastered = try AudioFileService.loadAudio(from: masteredURL)
        let masteredMetrics = try AudioComparisonService.analyze(signal: mastered)
        let baselineMetrics = try audioQualityMasteringLoudnessBaselineMetrics(in: diagnostics)
        let masteredNoise = NoiseMeasurementService.analyze(signal: mastered)
        let policy = MasteringProfile.streaming.settings.loudnessAdjustmentPolicy

        #expect(masteredMetrics.integratedLoudnessLUFS <= baselineMetrics.integratedLoudnessLUFS + policy.maxBoostDB + 0.2)
        #expect(masteredMetrics.integratedLoudnessLUFS >= baselineMetrics.integratedLoudnessLUFS - policy.maxCutDB - 0.2)
        #expect(masteredMetrics.truePeakDBFS <= Double(MasteringProfile.streaming.settings.peakCeilingDB) + 0.05)
        expectAudioQualityHighBandsNotDulled(reference: input, processed: corrected)
        expectAudioQualityHighBandsNotDulled(reference: input, processed: mastered)
        #expect((correctedNoise.comparableLevel(for: NoiseMeasurementID.hiss) ?? -120)
            <= (inputNoise.comparableLevel(for: NoiseMeasurementID.hiss) ?? -120) + 0.5)
        #expect((correctedNoise.comparableLevel(for: NoiseMeasurementID.shimmer) ?? -120)
            <= (inputNoise.comparableLevel(for: NoiseMeasurementID.shimmer) ?? -120) + 0.5)
        #expect((masteredNoise.comparableLevel(for: NoiseMeasurementID.hiss) ?? -120)
            <= (correctedNoise.comparableLevel(for: NoiseMeasurementID.hiss) ?? -120)
            + audioQualityMaxMasteringNoiseReturnDB(for: NoiseMeasurementID.hiss))
        #expect((masteredNoise.comparableLevel(for: NoiseMeasurementID.shimmer) ?? -120)
            <= (correctedNoise.comparableLevel(for: NoiseMeasurementID.shimmer) ?? -120)
            + audioQualityMaxMasteringNoiseReturnDB(for: NoiseMeasurementID.shimmer))
    }
}
