import Foundation
import Testing
@testable import VelouraLucent

struct SharedHighFrequencyRealAudioValidationTests {
    @Test
    func validatesSavedRawDrumTransientRecovery() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let rawDirectoryPath = environment["VELOURA_SHARED_VALIDATION_RAW_STEMS"],
              let outputRootPath = environment["VELOURA_SHARED_VALIDATION_OUTPUT"]
        else {
            return
        }

        let rawURL = URL(fileURLWithPath: rawDirectoryPath).appending(path: "raw-drums-48000.wav")
        let outputDirectory = URL(fileURLWithPath: outputRootPath).appending(path: "stem-drum")
        try resetDirectory(outputDirectory)
        let raw = try AudioFileService.loadAudio(from: rawURL)
        let request = StemAudioEvaluationRequest(
            purpose: .rawStem(role: .drums),
            includeAudioAnalyzerSnapshot: true,
            includeMasteringAnalysisSnapshot: false,
            analysisMode: .cpu
        )
        let rawEvaluation = try await StemAudioEvaluationService.evaluate(signal: raw, request: request)
        let result = try await StemCorrectionService().correct(
            runID: UUID(),
            role: .drums,
            rawSignal: raw,
            rawEvaluation: rawEvaluation,
            settings: DenoiseStrength.balanced.settings,
            progressHandler: { _ in },
            logHandler: { _ in }
        )
        let correctedURL = outputDirectory.appending(path: "corrected-drums-48000.wav")
        try AudioFileService.saveAudio(result.correctedSignal, to: correctedURL)

        let report = makeReport(
            title: "Stemドラム・トランジェント回復修正後実測",
            sections: [
                makeComparisonSection(label: "ドラム raw→補正後", before: raw, after: result.correctedSignal),
            ]
        )
        let reportURL = outputDirectory.appending(path: "Stemドラム修正後実測.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        print("[shared-validation] Stem drum completed: \(reportURL.path)")

        #expect(result.correctedSignal.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
    }

    @Test
    func validatesNormalModeOnProvidedSharedSource() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sourcePath = environment["VELOURA_SHARED_VALIDATION_SOURCE"],
              let outputRootPath = environment["VELOURA_SHARED_VALIDATION_OUTPUT"]
        else {
            return
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let outputDirectory = URL(fileURLWithPath: outputRootPath).appending(path: "normal")
        try resetDirectory(outputDirectory)
        let correctionDiagnostics = outputDirectory.appending(path: "correction")
        let masteringDiagnostics = outputDirectory.appending(path: "mastering")

        print("[shared-validation] Normal correction started")
        let correctedTemporaryURL = try await AudioProcessingService().process(
            inputFile: sourceURL,
            denoiseStrength: .balanced,
            analysisMode: .cpu,
            diagnosticOutputDirectory: correctionDiagnostics
        ) { _ in }
        let source = try AudioFileService.loadAudio(from: sourceURL)
        let corrected = try AudioFileService.loadAudio(from: correctedTemporaryURL)
        let correctedURL = outputDirectory.appending(path: "normal-corrected.wav")
        try AudioFileService.saveAudio(corrected, to: correctedURL)

        print("[shared-validation] Normal mastering started")
        let sourceNoise = NoiseMeasurementService.analyze(signal: source)
        let correctedNoise = NoiseMeasurementService.analyze(signal: corrected)
        let masteredTemporaryURL = try await MasteringService().process(
            inputFile: correctedURL,
            settings: MasteringProfile.streaming.settings,
            referenceNoiseMeasurements: correctedNoise,
            originalReferenceFile: sourceURL,
            originalReferenceNoiseMeasurements: sourceNoise,
            diagnosticOutputDirectory: masteringDiagnostics
        ) { _ in }
        let mastered = try AudioFileService.loadAudio(from: masteredTemporaryURL)
        let masteredURL = outputDirectory.appending(path: "normal-mastered.wav")
        try AudioFileService.saveAudio(mastered, to: masteredURL)

        let report = makeReport(
            title: "通常モード 共通高域修正後実測",
            sections: [
                makeComparisonSection(label: "入力→補正後", before: source, after: corrected),
                makeComparisonSection(label: "補正後→最終版", before: corrected, after: mastered),
            ]
        )
        let reportURL = outputDirectory.appending(path: "通常モード修正後実測.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        print("[shared-validation] Normal completed: \(reportURL.path)")

        #expect(corrected.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        #expect(mastered.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
    }

    @Test
    func validatesStemModeUsingSavedRawStemsAndSameRemix() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let sourcePath = environment["VELOURA_SHARED_VALIDATION_SOURCE"],
              let rawDirectoryPath = environment["VELOURA_SHARED_VALIDATION_RAW_STEMS"],
              let remixPath = environment["VELOURA_SHARED_VALIDATION_STEM_REMIX"],
              let outputRootPath = environment["VELOURA_SHARED_VALIDATION_OUTPUT"]
        else {
            return
        }

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let rawDirectory = URL(fileURLWithPath: rawDirectoryPath)
        let remixURL = URL(fileURLWithPath: remixPath)
        let outputDirectory = URL(fileURLWithPath: outputRootPath).appending(path: "stem")
        try resetDirectory(outputDirectory)

        var correctionSections: [String] = []
        for role in StemRole.allCases {
            let rawURL = rawDirectory.appending(path: "raw-\(role.rawValue)-48000.wav")
            let raw = try AudioFileService.loadAudio(from: rawURL)
            print("[shared-validation] Stem correction started: \(role.rawValue)")
            let request = StemAudioEvaluationRequest(
                purpose: .rawStem(role: role),
                includeAudioAnalyzerSnapshot: true,
                includeMasteringAnalysisSnapshot: false,
                analysisMode: .cpu
            )
            let rawEvaluation = try await StemAudioEvaluationService.evaluate(
                signal: raw,
                request: request
            )
            let result = try await StemCorrectionService().correct(
                runID: UUID(),
                role: role,
                rawSignal: raw,
                rawEvaluation: rawEvaluation,
                settings: DenoiseStrength.balanced.settings,
                progressHandler: { _ in },
                logHandler: { _ in }
            )
            let correctedURL = outputDirectory.appending(path: "corrected-\(role.rawValue)-48000.wav")
            try AudioFileService.saveAudio(result.correctedSignal, to: correctedURL)
            correctionSections.append(
                makeComparisonSection(
                    label: "\(role.stemModeDisplayTitle) raw→補正後",
                    before: raw,
                    after: result.correctedSignal
                )
            )
            print("[shared-validation] Stem correction completed: \(role.rawValue)")
        }

        print("[shared-validation] Same Stem remix mastering started")
        let source = try AudioFileService.loadAudio(from: sourceURL)
        let remix = try AudioFileService.loadAudio(from: remixURL)
        let masteringDiagnostics = outputDirectory.appending(path: "mastering")
        let masteredTemporaryURL = try await MasteringService().process(
            inputFile: remixURL,
            settings: MasteringProfile.streaming.settings,
            referenceNoiseMeasurements: NoiseMeasurementService.analyze(signal: remix),
            originalReferenceFile: sourceURL,
            originalReferenceNoiseMeasurements: NoiseMeasurementService.analyze(signal: source),
            diagnosticOutputDirectory: masteringDiagnostics
        ) { _ in }
        let mastered = try AudioFileService.loadAudio(from: masteredTemporaryURL)
        let masteredURL = outputDirectory.appending(path: "same-remix-mastered.wav")
        try AudioFileService.saveAudio(mastered, to: masteredURL)

        let report = makeReport(
            title: "Stemモード 共通高域修正後実測",
            sections: correctionSections + [
                makeComparisonSection(label: "同じStem再ミックス→最終版", before: remix, after: mastered),
            ]
        )
        let reportURL = outputDirectory.appending(path: "Stemモード修正後実測.md")
        try report.write(to: reportURL, atomically: true, encoding: .utf8)
        print("[shared-validation] Stem completed: \(reportURL.path)")

        #expect(mastered.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
    }

    private func makeReport(title: String, sections: [String]) -> String {
        (["# \(title)", ""] + sections).joined(separator: "\n")
    }

    private func makeComparisonSection(label: String, before: AudioSignal, after: AudioSignal) -> String {
        let beforeMetrics = measuredBands(before)
        let afterMetrics = measuredBands(after)
        let overallDelta = afterMetrics.rmsDB - beforeMetrics.rmsDB
        let rows = ValidationBand.allCases.map { band in
            let delta = afterMetrics.levels[band, default: -120] - beforeMetrics.levels[band, default: -120]
            return "| \(band.label) | \(format(delta)) dB | \(format(delta - overallDelta)) dB |"
        }
        return ([
            "## \(label)",
            "",
            "- 全体RMS変化: \(format(overallDelta)) dB",
            "",
            "| 帯域 | 絶対変化 | 全体RMSを除いた相対差 |",
            "|---|---:|---:|",
        ] + rows + [""]).joined(separator: "\n")
    }

    private func measuredBands(_ signal: AudioSignal) -> ValidationMeasurement {
        var energies = Dictionary(uniqueKeysWithValues: ValidationBand.allCases.map { ($0, 0.0) })
        var counts = Dictionary(uniqueKeysWithValues: ValidationBand.allCases.map { ($0, 0) })
        var rmsEnergy = 0.0
        var rmsCount = 0

        for channel in signal.channels {
            for sample in channel {
                rmsEnergy += Double(sample * sample)
                rmsCount += 1
            }
            SpectralDSP.forEachSTFTFrame(channel) { _, binCount, real, imag in
                let frequencyStep = signal.sampleRate / Double(SpectralDSP.fftSize)
                for binIndex in 0..<binCount {
                    let frequency = Double(binIndex) * frequencyStep
                    let power = Double(real[binIndex] * real[binIndex] + imag[binIndex] * imag[binIndex])
                    for band in ValidationBand.allCases where frequency >= band.lower && frequency <= band.upper {
                        energies[band, default: 0] += power
                        counts[band, default: 0] += 1
                    }
                }
            }
        }

        let levels = Dictionary(uniqueKeysWithValues: ValidationBand.allCases.map { band in
            let average = energies[band, default: 0] / Double(max(counts[band, default: 0], 1))
            return (band, 10 * log10(max(average, 1e-12)))
        })
        let rmsDB = 10 * log10(max(rmsEnergy / Double(max(rmsCount, 1)), 1e-12))
        return ValidationMeasurement(rmsDB: rmsDB, levels: levels)
    }

    private func resetDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func format(_ value: Double) -> String {
        String(format: "%+.3f", value)
    }
}

private enum ValidationBand: CaseIterable {
    case body
    case lowMid
    case sparkle
    case air
    case ultraAir
    case generatedUltraHigh

    var label: String {
        switch self {
        case .body: "20Hz–2kHz"
        case .lowMid: "150–500Hz"
        case .sparkle: "8–12kHz"
        case .air: "12–16kHz"
        case .ultraAir: "16–20kHz"
        case .generatedUltraHigh: "21–24kHz"
        }
    }

    var lower: Double {
        switch self {
        case .body: 20
        case .lowMid: 150
        case .sparkle: 8_000
        case .air: 12_000
        case .ultraAir: 16_000
        case .generatedUltraHigh: 21_000
        }
    }

    var upper: Double {
        switch self {
        case .body: 2_000
        case .lowMid: 500
        case .sparkle: 12_000
        case .air: 16_000
        case .ultraAir: 20_000
        case .generatedUltraHigh: 24_000
        }
    }
}

private struct ValidationMeasurement {
    let rmsDB: Double
    let levels: [ValidationBand: Double]
}
