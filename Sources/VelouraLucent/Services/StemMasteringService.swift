import Darwin
import Foundation

protocol StemMasteringProcessing: Sendable {
    func process(
        inputFile: URL,
        settings: MasteringSettings,
        initialAnalysis: MasteringAnalysis,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot,
        originalReferenceFile: URL,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> URL
}

struct ProductionStemMasteringProcessor: StemMasteringProcessing {
    func process(
        inputFile: URL,
        settings: MasteringSettings,
        initialAnalysis: MasteringAnalysis,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot,
        originalReferenceFile: URL,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        try await MasteringService().process(
            inputFile: inputFile,
            settings: settings,
            initialAnalysis: initialAnalysis,
            referenceNoiseMeasurements: referenceNoiseMeasurements,
            originalReferenceFile: originalReferenceFile,
            originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
            logHandler: logHandler
        )
    }
}

protocol StemFinalAudioEvaluating: Sendable {
    func evaluate(
        signal: AudioSignal,
        request: StemAudioEvaluationRequest
    ) async throws -> StemAudioEvaluationSnapshot
}

struct ProductionStemFinalAudioEvaluator: StemFinalAudioEvaluating {
    func evaluate(
        signal: AudioSignal,
        request: StemAudioEvaluationRequest
    ) async throws -> StemAudioEvaluationSnapshot {
        try await StemAudioEvaluationService.evaluate(signal: signal, request: request)
    }
}

struct StemMasteringService: Sendable {
    static let finalMasterFileName = "final-master.wav"

    private let masteringProcessor: any StemMasteringProcessing
    private let finalEvaluator: any StemFinalAudioEvaluating
    private let artifactStore: StemTemporaryAudioStore

    init(
        masteringProcessor: any StemMasteringProcessing = ProductionStemMasteringProcessor(),
        finalEvaluator: any StemFinalAudioEvaluating = ProductionStemFinalAudioEvaluator(),
        artifactStore: StemTemporaryAudioStore = StemTemporaryAudioStore()
    ) {
        self.masteringProcessor = masteringProcessor
        self.finalEvaluator = finalEvaluator
        self.artifactStore = artifactStore
    }

    /// Rebuilds only the presentation reports from the current in-memory evaluations.
    /// No audio is loaded, analyzed, corrected, or mastered by this function.
    static func reconstructReports(
        canonicalInputEvaluation: StemAudioEvaluationSnapshot,
        masteringInputEvaluation: StemAudioEvaluationSnapshot,
        finalEvaluation: StemAudioEvaluationSnapshot,
        correctionSettings: StemRoleCorrectionSettings,
        settings: MasteringSettings
    ) throws -> StemMasteringReports {
        guard canonicalInputEvaluation.purpose == .canonicalInput else {
            throw StemMasteringError.unexpectedEvaluationPurpose(
                label: "canonical input",
                expected: .canonicalInput,
                actual: canonicalInputEvaluation.purpose
            )
        }
        guard masteringInputEvaluation.purpose == .remix else {
            throw StemMasteringError.unexpectedEvaluationPurpose(
                label: "mastering input",
                expected: .remix,
                actual: masteringInputEvaluation.purpose
            )
        }
        guard finalEvaluation.purpose == .finalMaster else {
            throw StemMasteringError.unexpectedEvaluationPurpose(
                label: "final master",
                expected: .finalMaster,
                actual: finalEvaluation.purpose
            )
        }
        guard let audioQuality = StemAudioReportAdapter.makeAudioQualityReport(
            input: canonicalInputEvaluation.audioMetrics,
            remixed: masteringInputEvaluation.audioMetrics,
            mastered: finalEvaluation.audioMetrics,
            peakCeilingDB: Double(settings.peakCeilingDB)
        ) else {
            throw StemMasteringError.reportUnavailable(.audioQuality)
        }
        guard let completion = StemAudioReportAdapter.makeCompletionReport(
            input: canonicalInputEvaluation.audioMetrics,
            remixed: masteringInputEvaluation.audioMetrics,
            mastered: finalEvaluation.audioMetrics,
            inputNoise: canonicalInputEvaluation.noiseMeasurements,
            remixedNoise: masteringInputEvaluation.noiseMeasurements,
            masteredNoise: finalEvaluation.noiseMeasurements,
            correctionSettings: correctionSettings,
            masteringSettings: settings
        ) else {
            throw StemMasteringError.reportUnavailable(.completion)
        }
        guard let noiseCheck = StemAudioReportAdapter.makeNoiseCheckReport(
            input: canonicalInputEvaluation.noiseMeasurements,
            remixed: masteringInputEvaluation.noiseMeasurements,
            mastered: finalEvaluation.noiseMeasurements,
            correctionSettings: correctionSettings,
            masteringSettings: settings
        ) else {
            throw StemMasteringError.reportUnavailable(.noiseCheck)
        }
        return StemMasteringReports(
            audioQuality: audioQuality,
            completion: completion,
            noiseCheck: noiseCheck
        )
    }

    func process(
        _ request: StemMasteringRequest,
        finalizationProgressHandler: @escaping @Sendable (StemModeProcessStepStatus) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StemMasteringResult {
        try Task.checkCancellation()

        let finalURL = try finalArtifactURL(in: request.sessionDirectory)
        guard !pathEntryExists(at: finalURL) else {
            throw StemMasteringError.finalArtifactAlreadyExists(finalURL.path)
        }

        _ = try await artifactStore.validate(
            artifact: request.masteringInput.artifact,
            expectedURL: request.masteringInput.artifact.fileURL,
            expectedKind: .remixed48000
        )
        _ = try await artifactStore.validate(
            artifact: request.canonicalReference.artifact,
            expectedURL: request.canonicalReference.artifact.fileURL,
            expectedKind: .input44100
        )
        try Task.checkCancellation()

        guard let initialAnalysis = request.masteringInput.evaluation.masteringAnalysis else {
            throw StemMasteringError.missingMasteringAnalysis
        }

        let temporaryMasterURL = try await masteringProcessor.process(
            inputFile: request.masteringInput.artifact.fileURL,
            settings: request.settings,
            initialAnalysis: initialAnalysis,
            referenceNoiseMeasurements: request.masteringInput.evaluation.noiseMeasurements,
            originalReferenceFile: request.canonicalReference.artifact.fileURL,
            originalReferenceNoiseMeasurements: request.canonicalReference.evaluation.noiseMeasurements,
            logHandler: logHandler
        )
        let normalizedTemporaryURL = try validateTemporaryOutputURL(
            temporaryMasterURL,
            masteringInputURL: request.masteringInput.artifact.fileURL,
            canonicalInputURL: request.canonicalReference.artifact.fileURL,
            finalURL: finalURL
        )
        defer {
            removeOutputFileIfPresent(at: normalizedTemporaryURL)
        }

        var publishedFinalURL: URL?
        do {
            finalizationProgressHandler(.running)
            logHandler("マスタリング済み音声を読み込みます")
            try Task.checkCancellation()
            let masteredSignal = try await runCancellableDetachedWorker(priority: .utility) {
                try AudioFileService.loadAudio(from: normalizedTemporaryURL)
            }
            try Task.checkCancellation()

            logHandler("Stem Mode最終版を保存します")
            let finalArtifact = try await artifactStore.save(
                signal: masteredSignal,
                id: "stem-final-\(request.runID.uuidString.lowercased())",
                kind: .finalMaster,
                to: finalURL
            )
            publishedFinalURL = finalURL
            logHandler("Stem Mode最終版を検証します")
            _ = try await artifactStore.validate(
                artifact: finalArtifact,
                expectedURL: finalURL,
                expectedKind: .finalMaster
            )
            let verifiedFinalSignal = try await artifactStore.load(
                artifact: finalArtifact,
                expectedURL: finalURL,
                expectedKind: .finalMaster
            )
            try Task.checkCancellation()

            logHandler("Stem Mode最終版を解析・ノイズ測定します")
            let evaluationRequest = StemAudioEvaluationRequest(
                purpose: .finalMaster,
                includeAudioAnalyzerSnapshot: true,
                includeMasteringAnalysisSnapshot: true,
                analysisMode: request.canonicalReference.evaluation.request.analysisMode
            )
            let finalEvaluation = try await finalEvaluator.evaluate(
                signal: verifiedFinalSignal,
                request: evaluationRequest
            )
            guard finalEvaluation.purpose == .finalMaster else {
                throw StemMasteringError.unexpectedEvaluationPurpose(
                    label: "final master",
                    expected: .finalMaster,
                    actual: finalEvaluation.purpose
                )
            }
            try Task.checkCancellation()

            logHandler("最終品質レポートを作成します")
            let reports = try Self.reconstructReports(
                canonicalInputEvaluation: request.canonicalReference.evaluation,
                masteringInputEvaluation: request.masteringInput.evaluation,
                finalEvaluation: finalEvaluation,
                correctionSettings: request.correctionSettings,
                settings: request.settings
            )
            try Task.checkCancellation()

            let result = StemMasteringResult(
                finalArtifact: finalArtifact,
                finalEvaluation: finalEvaluation,
                masteringSettings: request.settings,
                audioQualityReport: reports.audioQuality,
                completionReport: reports.completion,
                noiseCheckReport: reports.noiseCheck
            )
            logHandler("マスタリングが完了しました")
            finalizationProgressHandler(.completed)
            return result
        } catch {
            if let publishedFinalURL {
                removeOutputFileIfPresent(at: publishedFinalURL)
            }
            if error is CancellationError {
                throw CancellationError()
            }
            throw error
        }
    }

    private func finalArtifactURL(in sessionDirectory: URL) throws -> URL {
        guard sessionDirectory.isFileURL,
              sessionDirectory.query == nil,
              sessionDirectory.fragment == nil else {
            throw StemMasteringError.invalidSessionDirectory(sessionDirectory.absoluteString)
        }
        try FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        return sessionDirectory.appending(path: Self.finalMasterFileName).standardizedFileURL
    }

    private func validateTemporaryOutputURL(
        _ temporaryURL: URL,
        masteringInputURL: URL,
        canonicalInputURL: URL,
        finalURL: URL
    ) throws -> URL {
        guard temporaryURL.isFileURL else {
            throw StemMasteringError.unsafeTemporaryOutputURL(temporaryURL.absoluteString)
        }
        let normalized = temporaryURL.standardizedFileURL
        let protectedURLs = [masteringInputURL, canonicalInputURL, finalURL].map(\.standardizedFileURL)
        guard !protectedURLs.contains(normalized) else {
            throw StemMasteringError.unsafeTemporaryOutputURL(normalized.path)
        }

        return try validateSystemPreviewOutput(normalized)
    }

    /// `FileManager.default.temporaryDirectory` is normally reported below `/var/folders`
    /// on macOS, while `/var` is a system symbolic link to `/private/var`. Stem run artifacts
    /// continue to reject every symbolic-link ancestor. This exception is limited to the
    /// existing Standard-mode preview directory and verifies both lexical and `realpath`
    /// containment before accepting the regular temporary WAV.
    private func validateSystemPreviewOutput(_ normalized: URL) throws -> URL {
        let previewDirectory = PreviewFileStore.directory.standardizedFileURL
        let lexicalPreviewPrefix = directoryPrefix(previewDirectory.path)
        guard normalized.path.hasPrefix(lexicalPreviewPrefix) else {
            throw StemMasteringError.unsafeTemporaryOutputURL(normalized.path)
        }

        let canonicalTemporaryRoot = try canonicalExistingURL(
            FileManager.default.temporaryDirectory
        )
        let canonicalPreviewDirectory = try canonicalExistingURL(previewDirectory)
        let canonicalOutput = try canonicalExistingURL(normalized)

        guard canonicalPreviewDirectory.path.hasPrefix(
            directoryPrefix(canonicalTemporaryRoot.path)
        ), canonicalOutput.path.hasPrefix(
            directoryPrefix(canonicalPreviewDirectory.path)
        ) else {
            throw StemMasteringError.unsafeTemporaryOutputURL(normalized.path)
        }

        try requireRegularTemporaryFile(at: normalized)
        try requireRegularTemporaryFile(at: canonicalOutput)
        return canonicalOutput
    }

    private func canonicalExistingURL(_ url: URL) throws -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard Darwin.realpath(url.path, &buffer) != nil else {
            throw StemMasteringError.temporaryOutputMissing(url.path)
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return URL(
            fileURLWithPath: String(decoding: bytes, as: UTF8.self),
            isDirectory: url.hasDirectoryPath
        )
    }

    private func directoryPrefix(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private func requireRegularTemporaryFile(at url: URL) throws {
        var metadata = stat()
        let inspectionResult = url.path.withCString { Darwin.lstat($0, &metadata) }
        guard inspectionResult == 0 else {
            throw StemMasteringError.temporaryOutputMissing(url.path)
        }
        guard (metadata.st_mode & S_IFMT) == S_IFREG else {
            throw StemMasteringError.unsafeTemporaryOutputURL(url.path)
        }
    }

    private func pathEntryExists(at url: URL) -> Bool {
        var metadata = stat()
        return url.path.withCString { Darwin.lstat($0, &metadata) } == 0
    }

    /// `unlink` never recursively removes a directory and removes only a symbolic-link
    /// leaf, so a replaced path cannot turn cleanup into directory deletion.
    private func removeOutputFileIfPresent(at url: URL) {
        _ = url.path.withCString { Darwin.unlink($0) }
    }
}
