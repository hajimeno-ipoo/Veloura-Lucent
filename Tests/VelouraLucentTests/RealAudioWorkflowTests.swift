import Foundation
import Testing
@testable import VelouraLucent

struct RealAudioWorkflowTests {
    @Test
    func providedRealAudioExcerptProducesUpdatedCorrectionAndMasteringReport() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["VELOURA_PROVIDED_REAL_INPUT"] else {
            return
        }

        let sourceURL = URL(fileURLWithPath: inputPath)
        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            Issue.record("Provided real audio file is missing: \(sourceURL.path(percentEncoded: false))")
            return
        }

        let startSeconds = Double(environment["VELOURA_PROVIDED_REAL_START_SECONDS"] ?? "") ?? 60
        let durationSeconds = Double(environment["VELOURA_PROVIDED_REAL_DURATION_SECONDS"] ?? "") ?? 16
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let excerptURL = tempDirectory.appending(path: "provided-real-excerpt.wav")

        let inputSignal = try AudioFileService.loadAudio(from: sourceURL)
        let excerptSignal = excerpt(from: inputSignal, startSeconds: startSeconds, seconds: durationSeconds)
        try AudioFileService.saveAudio(excerptSignal, to: excerptURL)

        let correctionLogs = RealAudioLogCollector()
        let masteringLogs = RealAudioLogCollector()
        let masteringDiagnostics = tempDirectory.appending(path: "mastering-stages")
        let correctedURL = try await AudioProcessingService().process(
            inputFile: excerptURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu
        ) { message in
            correctionLogs.append(message)
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
        ) { message in
            masteringLogs.append(message)
        }

        let masteredSignal = try AudioFileService.loadAudio(from: masteredURL)
        let masteredNoise = NoiseMeasurementService.analyze(signal: masteredSignal)
        let inputMetrics = try AudioComparisonService.analyze(signal: excerptSignal)
        let correctedMetrics = try AudioComparisonService.analyze(signal: correctedSignal)
        let masteredMetrics = try AudioComparisonService.analyze(signal: masteredSignal)
        let loudnessBaselineMetrics = try AudioComparisonService.analyze(
            fileURL: realAudioDiagnosticFile(in: masteringDiagnostics, containing: "06_mastering_stereo")
        )
        let report = providedRealAudioReport(
            sourceURL: sourceURL,
            excerptURL: excerptURL,
            correctedURL: correctedURL,
            masteredURL: masteredURL,
            input: excerptSignal,
            corrected: correctedSignal,
            mastered: masteredSignal,
            inputMetrics: inputMetrics,
            correctedMetrics: correctedMetrics,
            masteredMetrics: masteredMetrics,
            inputNoise: inputNoise,
            correctedNoise: correctedNoise,
            masteredNoise: masteredNoise,
            correctionLogs: correctionLogs.values,
            masteringLogs: masteringLogs.values
        )
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentProvidedRealAudioWorkflow.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: correctedURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: masteredURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))
        let policy = MasteringProfile.streaming.settings.loudnessAdjustmentPolicy
        #expect(masteredMetrics.integratedLoudnessLUFS <= loudnessBaselineMetrics.integratedLoudnessLUFS + policy.maxBoostDB + 0.2)
        #expect(masteredMetrics.integratedLoudnessLUFS >= loudnessBaselineMetrics.integratedLoudnessLUFS - policy.maxCutDB - 0.2)
        #expect(masteredMetrics.truePeakDBFS <= Double(MasteringProfile.streaming.settings.peakCeilingDB) + 0.05)
        expectMetricHighBandsNotDulled(reference: inputMetrics, processed: correctedMetrics)
        expectMetricHighBandsNotDulled(reference: correctedMetrics, processed: masteredMetrics, maxBrillianceDropDB: 1.0, maxAirDropDB: 1.0, maxUltraAirDropDB: 1.0)
        expectMetricHighBandsNotDulled(reference: inputMetrics, processed: masteredMetrics)
        #expect(noiseValue(NoiseMeasurementID.hiss, in: masteredNoise) <= noiseValue(NoiseMeasurementID.hiss, in: inputNoise) + 0.5)
        #expect(noiseValue(NoiseMeasurementID.hiss, in: masteredNoise) <= noiseValue(NoiseMeasurementID.hiss, in: correctedNoise) + 2.5)
        #expect(noiseValue(NoiseMeasurementID.shimmer, in: masteredNoise) <= noiseValue(NoiseMeasurementID.shimmer, in: inputNoise) + 0.5)
        #expect(noiseValue(NoiseMeasurementID.shimmer, in: masteredNoise) <= noiseValue(NoiseMeasurementID.shimmer, in: correctedNoise) + 2.5)
        #expect(noiseValue(NoiseMeasurementID.sibilance, in: masteredNoise) <= noiseValue(NoiseMeasurementID.sibilance, in: correctedNoise) + 0.2)
        #expect(noiseValue(NoiseMeasurementID.mud, in: masteredNoise) <= noiseValue(NoiseMeasurementID.mud, in: inputNoise) + 2.0)
        #expect(noiseValue(NoiseMeasurementID.room, in: masteredNoise) <= noiseValue(NoiseMeasurementID.room, in: inputNoise) - 4.0)
    }

    @Test
    func realMasteringGoalFileMeetsHighBandTargets() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let inputPath = environment["VELOURA_REAL_GOAL_INPUT"],
              let correctedPath = environment["VELOURA_REAL_GOAL_CORRECTED"]
        else {
            return
        }

        let inputURL = URL(fileURLWithPath: inputPath)
        let correctedURL = URL(fileURLWithPath: correctedPath)
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let masteringDiagnostics = tempDirectory.appending(path: "mastering-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        guard FileManager.default.fileExists(atPath: inputURL.path(percentEncoded: false)),
              FileManager.default.fileExists(atPath: correctedURL.path(percentEncoded: false))
        else {
            Issue.record("Real goal audio files are missing")
            return
        }

        let input = try AudioFileService.loadAudio(from: inputURL)
        let corrected = try AudioFileService.loadAudio(from: correctedURL)
        let masteredURL = try await MasteringService().process(
            inputFile: correctedURL,
            settings: MasteringProfile.streaming.settings,
            diagnosticOutputDirectory: masteringDiagnostics
        ) { _ in }
        let mastered = try AudioFileService.loadAudio(from: masteredURL)
        let inputMetrics = try AudioComparisonService.analyze(signal: input)
        let correctedMetrics = try AudioComparisonService.analyze(signal: corrected)
        let masteredMetrics = try AudioComparisonService.analyze(fileURL: masteredURL)
        let loudnessBaselineMetrics = try AudioComparisonService.analyze(
            fileURL: realAudioDiagnosticFile(in: masteringDiagnostics, containing: "06_mastering_stereo")
        )

        let report = masteringGoalReport(
            input: input,
            corrected: corrected,
            mastered: mastered,
            inputMetrics: inputMetrics,
            correctedMetrics: correctedMetrics,
            masteredMetrics: masteredMetrics,
            masteredURL: masteredURL
        )
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentRealMasteringGoal.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: masteredURL.path(percentEncoded: false)))
        #expect(masteringBandDrop(input: input, mastered: mastered, lower: 5_000, upper: 8_000) >= -2.5)
        expectMetricHighBandsNotDulled(reference: inputMetrics, processed: masteredMetrics)
        let policy = MasteringProfile.streaming.settings.loudnessAdjustmentPolicy
        #expect(masteredMetrics.integratedLoudnessLUFS <= loudnessBaselineMetrics.integratedLoudnessLUFS + policy.maxBoostDB + 0.2)
        #expect(masteredMetrics.integratedLoudnessLUFS >= loudnessBaselineMetrics.integratedLoudnessLUFS - policy.maxCutDB - 0.2)
        #expect(masteredMetrics.truePeakDBFS <= -1.5)
        #expect(FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))
    }

    @Test
    func realAudioExcerptProducesCorrectedAndMasteredComparisonReport() async throws {
        let projectDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let sourceURL = projectDirectory.appending(path: "violin #002 睡眠.wav")
        guard FileManager.default.fileExists(atPath: sourceURL.path(percentEncoded: false)) else {
            Issue.record("Real audio fixture is missing: \(sourceURL.path(percentEncoded: false))")
            return
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let excerptURL = tempDirectory.appending(path: "real-audio-excerpt.wav")

        let inputSignal = try AudioFileService.loadAudio(from: sourceURL)
        let excerptSignal = excerpt(from: inputSignal, seconds: 8)
        try AudioFileService.saveAudio(excerptSignal, to: excerptURL)

        let correctedURL = try await AudioProcessingService().process(
            inputFile: excerptURL,
            denoiseStrength: .strong,
            analysisMode: .cpu
        ) { _ in }
        let masteredURL = try await MasteringService().process(
            inputFile: correctedURL,
            profile: .streaming
        ) { _ in }

        let correctedSignal = try AudioFileService.loadAudio(from: correctedURL)
        let masteredSignal = try AudioFileService.loadAudio(from: masteredURL)
        let inputNoise = NoiseMeasurementService.analyze(signal: excerptSignal)
        let correctedNoise = NoiseMeasurementService.analyze(signal: correctedSignal)
        let masteredNoise = NoiseMeasurementService.analyze(signal: masteredSignal)
        let report = report(
            input: excerptSignal,
            corrected: correctedSignal,
            mastered: masteredSignal,
            inputNoise: inputNoise,
            correctedNoise: correctedNoise,
            masteredNoise: masteredNoise
        )
        let reportURL = FileManager.default.temporaryDirectory.appending(path: "VelouraLucentRealAudioWorkflow.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)

        #expect(FileManager.default.fileExists(atPath: correctedURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: masteredURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: reportURL.path(percentEncoded: false)))
        #expect([inputNoise, correctedNoise, masteredNoise].flatMap(\.values).allSatisfy {
            $0.comparableLevelDB.isFinite && $0.measuredLevelDB.isFinite
        })
        #expect(MasteringAnalysisService.approximateTruePeak(masteredSignal.channels) <= powf(10, MasteringProfile.streaming.settings.peakCeilingDB / 20) + 0.02)
    }

    private func excerpt(from signal: AudioSignal, seconds: Double) -> AudioSignal {
        let frameCount = min(signal.frameCount, max(1, Int(signal.sampleRate * seconds)))
        return AudioSignal(
            channels: signal.channels.map { Array($0.prefix(frameCount)) },
            sampleRate: signal.sampleRate
        )
    }

    private func excerpt(from signal: AudioSignal, startSeconds: Double, seconds: Double) -> AudioSignal {
        let startFrame = max(0, min(signal.frameCount - 1, Int(signal.sampleRate * startSeconds)))
        let frameCount = min(signal.frameCount - startFrame, max(1, Int(signal.sampleRate * seconds)))
        let endFrame = min(signal.frameCount, startFrame + frameCount)
        return AudioSignal(
            channels: signal.channels.map { Array($0[startFrame..<endFrame]) },
            sampleRate: signal.sampleRate
        )
    }

    private func report(
        input: AudioSignal,
        corrected: AudioSignal,
        mastered: AudioSignal,
        inputNoise: NoiseMeasurementSnapshot,
        correctedNoise: NoiseMeasurementSnapshot,
        masteredNoise: NoiseMeasurementSnapshot
    ) -> String {
        var lines = [
            "# Real Audio Workflow",
            "",
            "- source: violin #002 睡眠.wav",
            "- excerpt: 8 seconds",
            "- correction: strong",
            "- mastering: streaming",
            "",
            "## Loudness",
            "",
            "| stage | integrated LUFS | true peak dBTP |",
            "| --- | ---: | ---: |",
            loudnessLine("input", input),
            loudnessLine("corrected", corrected),
            loudnessLine("mastered", mastered),
            "",
            "## Noise",
            "",
            "| metric | input | corrected | mastered | corrected-input | mastered-corrected |",
            "| --- | ---: | ---: | ---: | ---: | ---: |"
        ]

        for value in inputNoise.values {
            let correctedValue = correctedNoise.value(for: value.id)?.comparableLevelDB ?? -120
            let masteredValue = masteredNoise.value(for: value.id)?.comparableLevelDB ?? -120
            lines.append(
                "| \(value.label) | \(format(value.comparableLevelDB)) | \(format(correctedValue)) | \(format(masteredValue)) | \(format(correctedValue - value.comparableLevelDB, signed: true)) | \(format(masteredValue - correctedValue, signed: true)) |"
            )
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func loudnessLine(_ label: String, _ signal: AudioSignal) -> String {
        let loudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        let peak = 20 * log10(Double(max(MasteringAnalysisService.approximateTruePeak(signal.channels), 1e-9)))
        return "| \(label) | \(format(Double(loudness))) | \(format(peak)) |"
    }

    private func masteringGoalReport(
        input: AudioSignal,
        corrected: AudioSignal,
        mastered: AudioSignal,
        inputMetrics: AudioMetricSnapshot,
        correctedMetrics: AudioMetricSnapshot,
        masteredMetrics: AudioMetricSnapshot,
        masteredURL: URL
    ) -> String {
        let metricBands: [(label: String, id: String, target: Double)] = [
            ("Sparkle 8-12kHz", "sparkle", -2.0),
            ("Air 12-16kHz", "air", -2.0),
            ("Ultra Air 16-20kHz", "ultraAir", -2.5)
        ]
        var lines = [
            "# Real Mastering Goal",
            "",
            "- mastered: \(masteredURL.path(percentEncoded: false))",
            "",
            "| band | measurement | input | corrected | mastered | mastered-input | target |",
            "| --- | --- | ---: | ---: | ---: | ---: | ---: |"
        ]
        let presenceInput = bandRMSDB(signal: input, lower: 5_000, upper: 8_000)
        let presenceCorrected = bandRMSDB(signal: corrected, lower: 5_000, upper: 8_000)
        let presenceMastered = bandRMSDB(signal: mastered, lower: 5_000, upper: 8_000)
        lines.append("| Presence 5-8kHz | bandRMSDB | \(format(presenceInput)) | \(format(presenceCorrected)) | \(format(presenceMastered)) | \(format(presenceMastered - presenceInput, signed: true)) | >= \(format(-2.5, signed: true)) |")

        for band in metricBands {
            let inputLevel = self.band(band.id, in: inputMetrics)
            let correctedLevel = self.band(band.id, in: correctedMetrics)
            let masteredLevel = self.band(band.id, in: masteredMetrics)
            lines.append("| \(band.label) | AudioComparisonService | \(format(inputLevel)) | \(format(correctedLevel)) | \(format(masteredLevel)) | \(format(masteredLevel - inputLevel, signed: true)) | >= \(format(band.target, signed: true)) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func masteringBandDrop(input: AudioSignal, mastered: AudioSignal, lower: Double, upper: Double) -> Double {
        bandRMSDB(signal: mastered, lower: lower, upper: upper) - bandRMSDB(signal: input, lower: lower, upper: upper)
    }

    private func format(_ value: Double, signed: Bool = false) -> String {
        String(format: signed ? "%+.1f dB" : "%.1f dB", value)
    }

    private func providedRealAudioReport(
        sourceURL: URL,
        excerptURL: URL,
        correctedURL: URL,
        masteredURL: URL,
        input: AudioSignal,
        corrected: AudioSignal,
        mastered: AudioSignal,
        inputMetrics: AudioMetricSnapshot,
        correctedMetrics: AudioMetricSnapshot,
        masteredMetrics: AudioMetricSnapshot,
        inputNoise: NoiseMeasurementSnapshot,
        correctedNoise: NoiseMeasurementSnapshot,
        masteredNoise: NoiseMeasurementSnapshot,
        correctionLogs: [String],
        masteringLogs: [String]
    ) -> String {
        var lines = [
            "# Provided Real Audio Workflow",
            "",
            "- source: \(sourceURL.path(percentEncoded: false))",
            "- excerpt: \(excerptURL.path(percentEncoded: false))",
            "- corrected: \(correctedURL.path(percentEncoded: false))",
            "- mastered: \(masteredURL.path(percentEncoded: false))",
            "- correction: balanced",
            "- mastering: streaming",
            "",
            "## Main metrics",
            "",
            "| metric | input | corrected | mastered | corrected-input | mastered-corrected | mastered-input |",
            "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
            metricLine("Integrated Loudness", inputMetrics.integratedLoudnessLUFS, correctedMetrics.integratedLoudnessLUFS, masteredMetrics.integratedLoudnessLUFS, valueUnit: "LUFS", deltaUnit: "LU"),
            metricLine("True Peak", inputMetrics.truePeakDBFS, correctedMetrics.truePeakDBFS, masteredMetrics.truePeakDBFS, valueUnit: "dBTP", deltaUnit: "dB"),
            metricLine("Sparkle 8-12kHz", band("sparkle", in: inputMetrics), band("sparkle", in: correctedMetrics), band("sparkle", in: masteredMetrics), valueUnit: "dB", deltaUnit: "dB"),
            metricLine("Air 12-16kHz", band("air", in: inputMetrics), band("air", in: correctedMetrics), band("air", in: masteredMetrics), valueUnit: "dB", deltaUnit: "dB"),
            metricLine("Ultra Air 16-20kHz", band("ultraAir", in: inputMetrics), band("ultraAir", in: correctedMetrics), band("ultraAir", in: masteredMetrics), valueUnit: "dB", deltaUnit: "dB"),
            metricLine("Mud 300Hz-1kHz", band("mud", in: inputMetrics), band("mud", in: correctedMetrics), band("mud", in: masteredMetrics), valueUnit: "dB", deltaUnit: "dB"),
            "",
            "## Noise",
            "",
            "| metric | input | corrected | mastered | corrected-input | mastered-corrected |",
            "| --- | ---: | ---: | ---: | ---: | ---: |"
        ]

        for value in inputNoise.values {
            let correctedValue = correctedNoise.value(for: value.id)?.comparableLevelDB ?? -120
            let masteredValue = masteredNoise.value(for: value.id)?.comparableLevelDB ?? -120
            lines.append("| \(value.label) | \(format(value.comparableLevelDB)) | \(format(correctedValue)) | \(format(masteredValue)) | \(format(correctedValue - value.comparableLevelDB, signed: true)) | \(format(masteredValue - correctedValue, signed: true)) |")
        }

        lines.append(contentsOf: [
            "",
            "## Logs",
            "",
            "- correction final high preserve: \(correctionLogs.filter { $0.hasPrefix("補正後高域保持") }.joined(separator: " / "))",
            "- correction mud guard: \(correctionLogs.filter { $0.hasPrefix("低中域残り: こもり悪化を抑制") }.joined(separator: " / "))",
            "- mastering final loudness restore: \(masteringLogs.filter { $0.hasPrefix("最終音量復帰") }.joined(separator: " / "))"
        ])
        return lines.joined(separator: "\n") + "\n"
    }

    private func metricLine(_ label: String, _ input: Double, _ corrected: Double, _ mastered: Double, valueUnit: String, deltaUnit: String) -> String {
        "| \(label) | \(formatMetric(input, unit: valueUnit)) | \(formatMetric(corrected, unit: valueUnit)) | \(formatMetric(mastered, unit: valueUnit)) | \(formatMetric(corrected - input, unit: deltaUnit, signed: true)) | \(formatMetric(mastered - corrected, unit: deltaUnit, signed: true)) | \(formatMetric(mastered - input, unit: deltaUnit, signed: true)) |"
    }

    private func formatMetric(_ value: Double, unit: String, signed: Bool = false) -> String {
        "\(String(format: signed ? "%+.1f" : "%.1f", value)) \(unit)"
    }

    private func band(_ id: String, in metrics: AudioMetricSnapshot) -> Double {
        metrics.bandEnergies.first { $0.id == id }?.levelDB ?? .nan
    }

    private func noiseValue(_ id: String, in snapshot: NoiseMeasurementSnapshot) -> Double {
        snapshot.comparableLevel(for: id) ?? -120
    }
}

private func expectMetricHighBandsNotDulled(
    reference: AudioMetricSnapshot,
    processed: AudioMetricSnapshot,
    maxBrillianceDropDB: Double = 2.0,
    maxAirDropDB: Double = 2.0,
    maxUltraAirDropDB: Double = 2.5
) {
    #expect(band("sparkle", in: processed) >= band("sparkle", in: reference) - maxBrillianceDropDB)
    #expect(band("air", in: processed) >= band("air", in: reference) - maxAirDropDB)
    #expect(band("ultraAir", in: processed) >= band("ultraAir", in: reference) - maxUltraAirDropDB)
}

private func band(_ id: String, in metrics: AudioMetricSnapshot) -> Double {
    metrics.bandEnergies.first { $0.id == id }?.levelDB ?? .nan
}

private func realAudioDiagnosticFile(in directory: URL, containing fragment: String) throws -> URL {
    let contents = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    return try #require(contents.first { $0.lastPathComponent.contains(fragment) })
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

private final class RealAudioLogCollector: @unchecked Sendable {
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
