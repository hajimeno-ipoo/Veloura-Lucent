import Foundation
import Observation

@MainActor
@Observable
final class ProcessingActions {
    let job: ProcessingJob
    let preview: AudioPreviewController
    var presentedError: UserFacingErrorPresentation?

    @ObservationIgnored private let displayAnalysis: DisplayAnalysisCoordinator
    @ObservationIgnored private var correctionTask: Task<Void, Never>?
    @ObservationIgnored private var correctionTaskID: UUID?
    @ObservationIgnored private var masteringTask: Task<Void, Never>?
    @ObservationIgnored private var masteringTaskID: UUID?

    init(notificationReporter: CompletionNotificationReporting) {
        let job = ProcessingJob(notificationReporter: notificationReporter)
        let preview = AudioPreviewController()
        self.job = job
        self.preview = preview
        displayAnalysis = DisplayAnalysisCoordinator(job: job, preview: preview)
        displayAnalysis.setErrorHandler { [weak self] error in
            self?.presentedError = error
        }
    }

    var canStartMastering: Bool {
        job.hasExistingOutput
            && job.canUseCorrectedAnalysisForMastering
            && !job.isMastering
            && !job.isProcessing
    }

    var canAcceptInputAudioDrop: Bool {
        !job.isProcessing && !job.isMastering
    }

    func performCorrectionAction() {
        if job.isProcessing {
            cancelCorrectionProcessing()
        } else {
            startCorrectionProcessing()
        }
    }

    func performMasteringAction() {
        if job.isMastering {
            cancelMasteringProcessing()
        } else {
            startMasteringProcessing()
        }
    }

    func chooseInputAudio() {
        FilePanelService.chooseAudioFile { [weak self] url in
            guard let self, let url else { return }
            let selectionID = displayAnalysis.beginInputSelection(for: url)
            displayAnalysis.analyzeMetrics(for: url, target: .input, selectionID: selectionID)
        }
    }

    func acceptDroppedInputAudio(_ urls: [URL]) -> Bool {
        guard canAcceptInputAudioDrop else { return false }
        guard case let .accepted(url) = InputAudioDropSupport.validate(urls) else {
            return false
        }

        let selectionID = displayAnalysis.beginInputSelection(for: url)
        displayAnalysis.analyzeMetrics(for: url, target: .input, selectionID: selectionID)
        return true
    }

    func cancelCorrectionProcessing() {
        guard job.isProcessing, !job.isCancellingProcessing else { return }
        job.requestProcessingCancellation()
        correctionTask?.cancel()
    }

    func cancelMasteringProcessing() {
        guard job.isMastering, !job.isCancellingMastering else { return }
        job.requestMasteringCancellation()
        masteringTask?.cancel()
    }

    func startCorrectionProcessing() {
        guard let inputFile = job.inputFile else { return }
        let selectionID = displayAnalysis.selectionID
        let appliedSettings = job.editableCorrectionSettings
        let resolvedAnalysisMode = job.selectedAnalysisMode.resolvedMode
        let initialAnalysis = job.inputCorrectionAnalysisMode == resolvedAnalysisMode ? job.inputCorrectionAnalysis : nil
        displayAnalysis.cancelTasks(for: [.corrected, .mastered])
        job.beginProcessing(appliedSettings: appliedSettings)

        let taskID = UUID()
        correctionTaskID = taskID
        correctionTask = Task { [weak self] in
            guard let self else { return }
            defer { clearCorrectionTask(ifMatching: taskID) }
            let logSink = OrderedProcessingLogSink { [weak job] message in
                job?.appendLog(message)
            }
            do {
                let outputFile: URL
                do {
                    outputFile = try await AudioProcessingService().process(
                        inputFile: inputFile,
                        denoiseStrength: job.selectedDenoiseStrength,
                        correctionSettings: appliedSettings,
                        analysisMode: job.selectedAnalysisMode,
                        initialAnalysis: initialAnalysis,
                        initialNoiseMeasurements: job.inputNoiseMeasurements
                    ) { message in
                        logSink.send(message)
                    }
                    await logSink.finish()
                } catch {
                    await logSink.finish()
                    throw error
                }

                guard displayAnalysis.isCurrentInputSelection(selectionID, inputFile: inputFile) else { return }
                job.finishSuccess(outputFile, appliedSettings: appliedSettings)
                AccessibilityAnnouncementService.post("補正処理が完了しました")
                preview.preparePreview(for: job.inputFile, target: .input, measureLoudness: false)
                if let inputMetrics = job.inputMetrics {
                    preview.setIntegratedLoudnessLUFS(inputMetrics.integratedLoudnessLUFS, for: .input)
                }
                preview.preparePreview(for: nil, target: .mastered)
                displayAnalysis.startTask(
                    for: outputFile,
                    target: .corrected,
                    selectionID: selectionID,
                    includePreview: true,
                    includeMasteringAnalysis: true,
                    correctionAnalysisMode: nil,
                    logHandler: { [weak job] message in
                        Task { @MainActor in
                            job?.appendLog(message)
                        }
                    }
                )
            } catch is CancellationError {
                guard displayAnalysis.isCurrentInputSelection(selectionID, inputFile: inputFile) else { return }
                guard job.isCancellingProcessing else { return }
                job.resetDisplayAnalysisStates(for: .corrected)
                clearCorrectionOutputPreviews()
                job.finishProcessingCancellation()
                AccessibilityAnnouncementService.post("補正処理をキャンセルしました")
            } catch {
                guard displayAnalysis.isCurrentInputSelection(selectionID, inputFile: inputFile) else { return }
                let presentation = UserFacingErrorPresentation.make(for: error, operation: .correction)
                job.resetDisplayAnalysisStates(for: .corrected)
                job.finishFailure(presentation.technicalDetails)
                presentedError = presentation
                AccessibilityAnnouncementService.post(
                    "補正処理に失敗しました。画面のエラー内容を確認してください"
                )
            }
        }
    }

    func startMasteringProcessing() {
        guard let correctedFile = job.outputFile else { return }
        guard canStartMastering else { return }
        let selectionID = displayAnalysis.selectionID
        let appliedSettings = job.editableMasteringSettings
        displayAnalysis.cancelTasks(for: [.mastered])
        job.beginMastering(appliedSettings: appliedSettings)

        let taskID = UUID()
        masteringTaskID = taskID
        masteringTask = Task { [weak self] in
            guard let self else { return }
            defer { clearMasteringTask(ifMatching: taskID) }
            let logSink = OrderedProcessingLogSink { [weak job] message in
                job?.appendMasteringLog(message)
            }
            do {
                let masteredFile: URL
                do {
                    masteredFile = try await MasteringService().process(
                        inputFile: correctedFile,
                        settings: appliedSettings,
                        initialAnalysis: job.outputMasteringAnalysis,
                        referenceNoiseMeasurements: job.outputNoiseMeasurements,
                        originalReferenceFile: job.inputFile,
                        originalReferenceNoiseMeasurements: job.inputNoiseMeasurements
                    ) { message in
                        logSink.send(message)
                    }
                    await logSink.finish()
                } catch {
                    await logSink.finish()
                    throw error
                }

                guard displayAnalysis.isCurrentMasteringSelection(selectionID, correctedFile: correctedFile) else { return }
                job.finishMasteringSuccess(masteredFile, appliedSettings: appliedSettings)
                AccessibilityAnnouncementService.post("マスタリングが完了しました")
                displayAnalysis.startTask(
                    for: masteredFile,
                    target: .mastered,
                    selectionID: selectionID,
                    includePreview: true,
                    includeMasteringAnalysis: false,
                    correctionAnalysisMode: nil,
                    logHandler: { [weak job] message in
                        Task { @MainActor in
                            job?.appendMasteringLog(message)
                        }
                    }
                )
            } catch is CancellationError {
                guard displayAnalysis.isCurrentMasteringSelection(selectionID, correctedFile: correctedFile) else { return }
                guard job.isCancellingMastering else { return }
                job.resetDisplayAnalysisStates(for: .mastered)
                clearMasteringOutputPreview()
                job.finishMasteringCancellation()
                AccessibilityAnnouncementService.post("マスタリングをキャンセルしました")
            } catch {
                guard displayAnalysis.isCurrentMasteringSelection(selectionID, correctedFile: correctedFile) else { return }
                let presentation = UserFacingErrorPresentation.make(for: error, operation: .mastering)
                job.resetDisplayAnalysisStates(for: .mastered)
                job.finishMasteringFailure(presentation.technicalDetails)
                presentedError = presentation
                AccessibilityAnnouncementService.post(
                    "マスタリングに失敗しました。画面のエラー内容を確認してください"
                )
            }
        }
    }

    func exportCorrectedAudio(as format: AudioExportFormat) {
        guard let sourceURL = job.outputFile, let inputFile = job.inputFile else { return }
        let suggestedName = exportFileName(
            baseURL: AudioProcessingService.defaultOutputURL(for: inputFile),
            format: format
        )
        FilePanelService.chooseSaveLocation(
            suggestedFileName: suggestedName,
            allowedContentTypes: [format.contentType]
        ) { [weak self] destinationURL in
            guard let self, let destinationURL else { return }
            do {
                try AudioFileService.exportAudio(from: sourceURL, to: destinationURL, format: format)
                job.finishCorrectedExport(destinationURL)
            } catch {
                let presentation = UserFacingErrorPresentation.make(for: error, operation: .correctedExport)
                job.recordCorrectedExportFailure(presentation.technicalDetails)
                presentedError = presentation
                AccessibilityAnnouncementService.post("補正後の音声を書き出せませんでした")
            }
        }
    }

    func exportMasteredAudio(as format: AudioExportFormat) {
        guard let sourceURL = job.masteredOutputFile else { return }
        let baseURL = job.inputFile.map { MasteringService.defaultOutputURL(for: $0) } ?? sourceURL
        let suggestedName = exportFileName(baseURL: baseURL, format: format)
        FilePanelService.chooseSaveLocation(
            suggestedFileName: suggestedName,
            allowedContentTypes: [format.contentType]
        ) { [weak self] destinationURL in
            guard let self, let destinationURL else { return }
            do {
                try AudioFileService.exportAudio(from: sourceURL, to: destinationURL, format: format)
                job.finishMasteredExport(destinationURL)
            } catch {
                let presentation = UserFacingErrorPresentation.make(for: error, operation: .masteredExport)
                job.recordMasteredExportFailure(presentation.technicalDetails)
                presentedError = presentation
                AccessibilityAnnouncementService.post("最終版を書き出せませんでした")
            }
        }
    }

    func shutdown() {
        correctionTask?.cancel()
        masteringTask?.cancel()
        displayAnalysis.cancelTasks()
        PreviewFileStore.removeAllPreviewFiles()
    }

    func clearCorrectionOutputPreviews() {
        preview.preparePreview(for: nil, target: .corrected)
        preview.preparePreview(for: nil, target: .mastered)
    }

    func clearMasteringOutputPreview() {
        preview.preparePreview(for: nil, target: .mastered)
    }

    private func clearCorrectionTask(ifMatching taskID: UUID) {
        guard correctionTaskID == taskID else { return }
        correctionTask = nil
        correctionTaskID = nil
    }

    private func clearMasteringTask(ifMatching taskID: UUID) {
        guard masteringTaskID == taskID else { return }
        masteringTask = nil
        masteringTaskID = nil
    }

    private func exportFileName(baseURL: URL, format: AudioExportFormat) -> String {
        baseURL.deletingPathExtension().appendingPathExtension(format.fileExtension).lastPathComponent
    }
}

struct OrderedProcessingLogSink: Sendable {
    private let continuation: AsyncStream<String>.Continuation
    private let consumer: Task<Void, Never>

    @MainActor
    init(append: @escaping @MainActor @Sendable (String) -> Void) {
        let (stream, continuation) = AsyncStream<String>.makeStream()
        self.continuation = continuation
        consumer = Task { @MainActor in
            for await message in stream {
                append(message)
            }
        }
    }

    func send(_ message: String) {
        continuation.yield(message)
    }

    func finish() async {
        continuation.finish()
        await consumer.value
    }
}
