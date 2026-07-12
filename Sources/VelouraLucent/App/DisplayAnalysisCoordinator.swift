import Foundation

@MainActor
final class DisplayAnalysisCoordinator {
    private let job: ProcessingJob
    private let preview: AudioPreviewController
    private var inputSelectionID = UUID()
    private var tasks: [DisplayAnalysisTarget: Task<Void, Never>] = [:]
    private var errorHandler: @MainActor (UserFacingErrorPresentation) -> Void = { _ in }

    init(job: ProcessingJob, preview: AudioPreviewController) {
        self.job = job
        self.preview = preview
    }

    var selectionID: UUID {
        inputSelectionID
    }

    func setErrorHandler(_ handler: @escaping @MainActor (UserFacingErrorPresentation) -> Void) {
        errorHandler = handler
    }

    func analyzeMetrics(for url: URL, target: DisplayAnalysisTarget, selectionID: UUID) {
        startTask(
            for: url,
            target: target,
            selectionID: selectionID,
            includePreview: target == .input,
            includeMasteringAnalysis: target == .corrected,
            correctionAnalysisMode: target == .input ? job.selectedAnalysisMode.resolvedMode : nil,
            logHandler: displayAnalysisLogHandler(for: target)
        )
    }

    func startTask(
        for url: URL,
        target: DisplayAnalysisTarget,
        selectionID: UUID,
        includePreview: Bool,
        includeMasteringAnalysis: Bool,
        correctionAnalysisMode: AudioAnalysisMode?,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) {
        tasks[target]?.cancel()
        tasks[target] = Task { [weak self] in
            await self?.runDisplayAnalysis(
                for: url,
                target: target,
                selectionID: selectionID,
                includePreview: includePreview,
                includeMasteringAnalysis: includeMasteringAnalysis,
                correctionAnalysisMode: correctionAnalysisMode,
                logHandler: logHandler
            )
        }
    }

    func cancelTasks(for targets: [DisplayAnalysisTarget] = DisplayAnalysisTarget.allDisplayTargets) {
        for target in targets {
            tasks[target]?.cancel()
            tasks[target] = nil
        }
    }

    @discardableResult
    func beginInputSelection(for url: URL) -> UUID {
        let selectionID = UUID()
        cancelTasks()
        inputSelectionID = selectionID
        PreviewFileStore.removeAllPreviewFiles()
        job.prepareForSelection(url)
        preview.stopPlayback()
        preview.setComparisonPair(.inputVsCorrected)
        preparePreviewCards(loadInputPreview: false)
        return selectionID
    }

    func isCurrentInputSelection(_ selectionID: UUID, inputFile: URL) -> Bool {
        inputSelectionID == selectionID && job.inputFile == inputFile
    }

    func isCurrentMasteringSelection(_ selectionID: UUID, correctedFile: URL) -> Bool {
        inputSelectionID == selectionID && job.outputFile == correctedFile
    }

    private func runDisplayAnalysis(
        for url: URL,
        target: DisplayAnalysisTarget,
        selectionID: UUID,
        includePreview: Bool,
        includeMasteringAnalysis: Bool,
        correctionAnalysisMode: AudioAnalysisMode?,
        logHandler: (@Sendable (String) -> Void)? = nil
    ) async {
        guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }

        let requiredKinds = requiredDisplayAnalysisKinds(
            includePreview: includePreview,
            includeMasteringAnalysis: includeMasteringAnalysis,
            correctionAnalysisMode: correctionAnalysisMode
        )
        let missingKinds = requiredKinds.filter {
            !hasCachedAnalysis($0, for: target, fileURL: url, correctionAnalysisMode: correctionAnalysisMode)
        }
        guard !missingKinds.isEmpty else { return }

        guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
        for kind in missingKinds {
            job.beginDisplayAnalysis(kind, for: target)
        }
        guard shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }

        let signal: AudioSignal
        do {
            signal = try await DisplayAnalysisSupport.measure("ファイル読み込み", logHandler: logHandler) {
                try await DisplayAnalysisSupport.runWorker {
                    try AudioFileService.loadAudio(from: url)
                }
            }
        } catch is CancellationError {
            return
        } catch {
            failDisplayAnalysisKinds(missingKinds, for: target, selectionID: selectionID, fileURL: url)
            if target == .input,
               isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) {
                let presentation = UserFacingErrorPresentation.make(for: error, operation: .inputAnalysis)
                job.appendLog(presentation.technicalDetails)
                errorHandler(presentation)
                AccessibilityAnnouncementService.post(
                    "音声ファイルを解析できませんでした。画面のエラー内容を確認してください"
                )
            }
            return
        }

        guard shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if includePreview && (missingKinds.contains(.preview) || missingKinds.contains(.spectrogram)) {
            do {
                let snapshots = try await DisplayAnalysisSupport.measure(
                    "プレビュー/スペクトログラム生成",
                    logHandler: logHandler
                ) {
                    try await DisplayAnalysisSupport.runWorker {
                        AudioFileService.makeDisplaySnapshots(from: signal)
                    }
                }
                guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                preview.setPreviewSnapshot(snapshots.previewSnapshot, for: previewTarget(for: target), sourceURL: url)
                job.finishDisplayAnalysis(.preview, for: target)
                finishSpectrogramAnalysis(snapshots.spectrogram, for: target)
            } catch {
                failDisplayAnalysisKinds(
                    [.preview, .spectrogram].filter { missingKinds.contains($0) },
                    for: target,
                    selectionID: selectionID,
                    fileURL: url
                )
            }
        } else if missingKinds.contains(.spectrogram) {
            do {
                let spectrogram = try await DisplayAnalysisSupport.measure("スペクトログラム生成", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        AudioFileService.makeSpectrogramSnapshot(from: signal)
                    }
                }
                guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                finishSpectrogramAnalysis(spectrogram, for: target)
            } catch {
                failDisplayAnalysisKinds([.spectrogram], for: target, selectionID: selectionID, fileURL: url)
            }
        }

        guard shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if missingKinds.contains(.metrics) {
            do {
                let metrics = try await DisplayAnalysisSupport.measure("比較指標", logHandler: logHandler) {
                    try await AudioComparisonService.analyzeConcurrently(signal: signal)
                }
                guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                finishMetricsAnalysis(metrics, for: target)
                preview.setIntegratedLoudnessLUFS(metrics.integratedLoudnessLUFS, for: previewTarget(for: target))
            } catch {
                failDisplayAnalysisKinds([.metrics], for: target, selectionID: selectionID, fileURL: url)
            }
        }

        guard shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if includeMasteringAnalysis, missingKinds.contains(.masteringAnalysis) {
            do {
                let masteringAnalysis = try await DisplayAnalysisSupport.measure("マスタリング解析", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        MasteringAnalysisService.analyze(signal: signal)
                    }
                }
                guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                job.finishOutputMasteringAnalysis(masteringAnalysis)
            } catch {
                failDisplayAnalysisKinds([.masteringAnalysis], for: target, selectionID: selectionID, fileURL: url)
            }
        }

        guard shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if let correctionAnalysisMode, missingKinds.contains(.correctionAnalysis) {
            do {
                let correctionAnalysis = try await DisplayAnalysisSupport.measure("補正解析", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        AudioAnalyzer(mode: correctionAnalysisMode).analyze(signal: signal)
                    }
                }
                guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                job.finishInputCorrectionAnalysis(correctionAnalysis, mode: correctionAnalysisMode)
            } catch {
                failDisplayAnalysisKinds([.correctionAnalysis], for: target, selectionID: selectionID, fileURL: url)
            }
        }

        guard shouldContinueDisplayAnalysis(target: target, selectionID: selectionID, fileURL: url) else { return }
        if missingKinds.contains(.noise) {
            do {
                let noiseMeasurements = try await DisplayAnalysisSupport.measure("ノイズ測定", logHandler: logHandler) {
                    try await DisplayAnalysisSupport.runWorker {
                        try NoiseMeasurementService.analyzeCancellable(signal: signal)
                    }
                }
                guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: url) else { return }
                finishNoiseAnalysis(noiseMeasurements, for: target)
            } catch {
                failDisplayAnalysisKinds([.noise], for: target, selectionID: selectionID, fileURL: url)
            }
        }
    }

    private func shouldContinueDisplayAnalysis(
        target: DisplayAnalysisTarget,
        selectionID: UUID,
        fileURL: URL
    ) -> Bool {
        !Task.isCancelled
            && isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: fileURL)
    }

    private func displayAnalysisLogHandler(for target: DisplayAnalysisTarget) -> (@Sendable (String) -> Void) {
        switch target {
        case .input, .corrected:
            { [weak job] message in
                Task { @MainActor in
                    job?.appendLog(message)
                }
            }
        case .mastered:
            { [weak job] message in
                Task { @MainActor in
                    job?.appendMasteringLog(message)
                }
            }
        }
    }

    private func preparePreviewCards(loadInputPreview: Bool = true) {
        if loadInputPreview {
            preview.preparePreview(for: job.inputFile, target: .input, measureLoudness: false)
        } else {
            preview.preparePreviewPlaceholder(for: job.inputFile, target: .input)
        }
        if let inputMetrics = job.inputMetrics {
            preview.setIntegratedLoudnessLUFS(inputMetrics.integratedLoudnessLUFS, for: .input)
        }

        preview.preparePreview(
            for: job.hasExistingOutput ? job.outputFile : nil,
            target: .corrected,
            measureLoudness: job.outputMetrics == nil
        )
        if let outputMetrics = job.outputMetrics {
            preview.setIntegratedLoudnessLUFS(outputMetrics.integratedLoudnessLUFS, for: .corrected)
        }

        preview.preparePreview(
            for: job.hasExistingMasteredOutput ? job.masteredOutputFile : nil,
            target: .mastered,
            measureLoudness: job.masteredMetrics == nil
        )
        if let masteredMetrics = job.masteredMetrics {
            preview.setIntegratedLoudnessLUFS(masteredMetrics.integratedLoudnessLUFS, for: .mastered)
        }
    }

    private func requiredDisplayAnalysisKinds(
        includePreview: Bool,
        includeMasteringAnalysis: Bool,
        correctionAnalysisMode: AudioAnalysisMode?
    ) -> [DisplayAnalysisKind] {
        var kinds: [DisplayAnalysisKind] = [.spectrogram, .metrics, .noise]
        if includePreview {
            kinds.insert(.preview, at: 0)
        }
        if includeMasteringAnalysis {
            kinds.append(.masteringAnalysis)
        }
        if correctionAnalysisMode != nil {
            kinds.append(.correctionAnalysis)
        }
        return kinds
    }

    private func hasCachedAnalysis(
        _ kind: DisplayAnalysisKind,
        for target: DisplayAnalysisTarget,
        fileURL: URL,
        correctionAnalysisMode: AudioAnalysisMode?
    ) -> Bool {
        guard isCurrentMetricSelection(target: target, selectionID: inputSelectionID, fileURL: fileURL) else {
            return false
        }
        switch (target, kind) {
        case (.input, .metrics):
            return job.inputMetrics != nil
        case (.corrected, .metrics):
            return job.outputMetrics != nil
        case (.mastered, .metrics):
            return job.masteredMetrics != nil
        case (.input, .spectrogram):
            return job.inputSpectrogram != nil
        case (.corrected, .spectrogram):
            return job.outputSpectrogram != nil
        case (.mastered, .spectrogram):
            return job.masteredSpectrogram != nil
        case (.input, .noise):
            return job.inputNoiseMeasurements != nil
        case (.corrected, .noise):
            return job.outputNoiseMeasurements != nil
        case (.mastered, .noise):
            return job.masteredNoiseMeasurements != nil
        case (.input, .correctionAnalysis):
            return job.inputCorrectionAnalysis != nil
                && job.inputCorrectionAnalysisMode == correctionAnalysisMode
        case (.corrected, .masteringAnalysis):
            return job.outputMasteringAnalysis != nil
        case (_, .preview):
            return false
        default:
            return true
        }
    }

    private func finishMetricsAnalysis(_ metrics: AudioMetricSnapshot, for target: DisplayAnalysisTarget) {
        switch target {
        case .input:
            job.finishInputMetricAnalysis(metrics)
        case .corrected:
            job.finishOutputMetricAnalysis(metrics)
        case .mastered:
            job.finishMasteredMetricAnalysis(metrics)
        }
    }

    private func finishSpectrogramAnalysis(_ spectrogram: SpectrogramSnapshot, for target: DisplayAnalysisTarget) {
        switch target {
        case .input:
            job.finishInputSpectrogram(spectrogram)
        case .corrected:
            job.finishOutputSpectrogram(spectrogram)
        case .mastered:
            job.finishMasteredSpectrogram(spectrogram)
        }
    }

    private func finishNoiseAnalysis(_ noiseMeasurements: NoiseMeasurementSnapshot, for target: DisplayAnalysisTarget) {
        switch target {
        case .input:
            job.finishInputNoiseMeasurement(noiseMeasurements)
        case .corrected:
            job.finishOutputNoiseMeasurement(noiseMeasurements)
        case .mastered:
            job.finishMasteredNoiseMeasurement(noiseMeasurements)
        }
    }

    private func failDisplayAnalysisKinds(
        _ kinds: [DisplayAnalysisKind],
        for target: DisplayAnalysisTarget,
        selectionID: UUID,
        fileURL: URL
    ) {
        guard isCurrentMetricSelection(target: target, selectionID: selectionID, fileURL: fileURL) else { return }
        for kind in kinds {
            job.failDisplayAnalysis(kind, for: target)
        }
    }

    private func previewTarget(for target: DisplayAnalysisTarget) -> AudioPreviewTarget {
        switch target {
        case .input:
            .input
        case .corrected:
            .corrected
        case .mastered:
            .mastered
        }
    }

    private func isCurrentMetricSelection(
        target: DisplayAnalysisTarget,
        selectionID: UUID,
        fileURL: URL
    ) -> Bool {
        guard inputSelectionID == selectionID else { return false }

        switch target {
        case .input:
            return job.inputFile == fileURL
        case .corrected:
            return job.outputFile == fileURL
        case .mastered:
            return job.masteredOutputFile == fileURL
        }
    }
}
