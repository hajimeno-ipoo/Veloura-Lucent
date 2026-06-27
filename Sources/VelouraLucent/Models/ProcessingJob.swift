import Foundation
import Observation

@MainActor
@Observable
final class ProcessingJob {
    @ObservationIgnored private let notificationReporter: CompletionNotificationReporting
    @ObservationIgnored private var didSendCorrectionCompletion = false
    @ObservationIgnored private var didSendMasteringCompletion = false

    var inputFile: URL?
    var outputFile: URL?
    var masteredOutputFile: URL?
    var exportedCorrectedFile: URL?
    var exportedMasteredFile: URL?
    var inputFileInfo: AudioFileInfo?
    var outputFileInfo: AudioFileInfo?
    var masteredFileInfo: AudioFileInfo?
    var inputMetrics: AudioMetricSnapshot?
    var outputMetrics: AudioMetricSnapshot?
    var masteredMetrics: AudioMetricSnapshot?
    var inputCorrectionAnalysis: AnalysisData?
    var inputCorrectionAnalysisMode: AudioAnalysisMode?
    var outputMasteringAnalysis: MasteringAnalysis?
    var inputNoiseMeasurements: NoiseMeasurementSnapshot?
    var outputNoiseMeasurements: NoiseMeasurementSnapshot?
    var masteredNoiseMeasurements: NoiseMeasurementSnapshot?
    var inputSpectrogram: SpectrogramSnapshot?
    var outputSpectrogram: SpectrogramSnapshot?
    var masteredSpectrogram: SpectrogramSnapshot?
    static let visibleLogLineLimit = ProcessingLogStateStore.visibleLineLimit
    private var correctionLog = ProcessingLogStateStore()
    private var masteringLog = ProcessingLogStateStore()
    var logLines: [String] {
        correctionLog.lines
    }
    var masteringLogLines: [String] {
        masteringLog.lines
    }
    var logText: String {
        correctionLog.text
    }
    var masteringLogText: String {
        masteringLog.text
    }
    var visibleLogLines: [String] {
        correctionLog.visibleLines
    }
    var visibleMasteringLogLines: [String] {
        masteringLog.visibleLines
    }
    private(set) var activityEvents: [RecentActivityEvent] = []
    var recentActivityEvents: [RecentActivityEvent] {
        Array(activityEvents.suffix(4))
    }
    var statusMessage = "待機中"
    var masteringStatusMessage = "待機中"
    var isProcessing = false
    var isMastering = false
    var processingStartedAt: Date?
    var processingFinishedAt: Date?
    var masteringStartedAt: Date?
    var masteringFinishedAt: Date?
    var lastError: String?
    var masteringLastError: String?
    var hasExistingOutput = false
    var hasExistingMasteredOutput = false
    private var correctionProgress = ProcessingProgressStateStore<ProcessingStep>()
    private var masteringProgress = ProcessingProgressStateStore<MasteringStep>()
    private var displayAnalysisStates = DisplayAnalysisStateStore()
    @ObservationIgnored private let settingsState = ProcessingSettingsState()
    var selectedMasteringProfile: MasteringProfile {
        get { settingsState.selectedMasteringProfile }
        set { settingsState.selectedMasteringProfile = newValue }
    }
    var editableMasteringSettings: MasteringSettings {
        get { settingsState.editableMasteringSettings }
        set { settingsState.editableMasteringSettings = newValue }
    }
    var isUsingCustomMasteringSettings: Bool {
        get { settingsState.isUsingCustomMasteringSettings }
        set { settingsState.isUsingCustomMasteringSettings = newValue }
    }
    var showAdvancedMasteringSettings: Bool {
        get { settingsState.showAdvancedMasteringSettings }
        set { settingsState.showAdvancedMasteringSettings = newValue }
    }
    var selectedDenoiseStrength: DenoiseStrength {
        get { settingsState.selectedDenoiseStrength }
        set { settingsState.selectedDenoiseStrength = newValue }
    }
    var editableCorrectionSettings: CorrectionSettings {
        get { settingsState.editableCorrectionSettings }
        set { settingsState.editableCorrectionSettings = newValue }
    }
    var isUsingCustomCorrectionSettings: Bool {
        get { settingsState.isUsingCustomCorrectionSettings }
        set { settingsState.isUsingCustomCorrectionSettings = newValue }
    }
    var showAdvancedCorrectionSettings: Bool {
        get { settingsState.showAdvancedCorrectionSettings }
        set { settingsState.showAdvancedCorrectionSettings = newValue }
    }
    var appliedCorrectionSettings: CorrectionSettings? {
        get { settingsState.appliedCorrectionSettings }
        set { settingsState.appliedCorrectionSettings = newValue }
    }
    var appliedMasteringSettings: MasteringSettings? {
        get { settingsState.appliedMasteringSettings }
        set { settingsState.appliedMasteringSettings = newValue }
    }
    var selectedAnalysisMode: AudioAnalysisMode {
        get { settingsState.selectedAnalysisMode }
        set { settingsState.selectedAnalysisMode = newValue }
    }

    init(notificationReporter: CompletionNotificationReporting = NoOpCompletionNotificationReporter.shared) {
        self.notificationReporter = notificationReporter
    }

    var progressValue: Double {
        if !isProcessing && statusMessage == "完了" {
            return 1
        }
        let total = Double(ProcessingStep.allCases.count)
        let completed = Double(completedSteps.count)
        let skipped = Double(skippedSteps.count)
        let activeBoost = activeStep == nil ? 0 : 0.5
        return min(0.98, (completed + skipped + activeBoost) / total)
    }

    var progressLabel: String {
        if let activeStep {
            if let activeStepDetail {
                return "\(activeStep.title): \(activeStepDetail)"
            }
            return "\(activeStep.title) を実行中"
        }
        return statusMessage
    }

    var activeStep: ProcessingStep? {
        correctionProgress.activeStep
    }

    var completedSteps: Set<ProcessingStep> {
        correctionProgress.completedSteps
    }

    var skippedSteps: Set<ProcessingStep> {
        correctionProgress.skippedSteps
    }

    var failedSteps: Set<ProcessingStep> {
        correctionProgress.failedSteps
    }

    var activeStepDetail: String? {
        correctionProgress.activeStepDetail
    }

    var masteringActiveStep: MasteringStep? {
        masteringProgress.activeStep
    }

    var completedMasteringSteps: Set<MasteringStep> {
        masteringProgress.completedSteps
    }

    var skippedMasteringSteps: Set<MasteringStep> {
        masteringProgress.skippedSteps
    }

    var failedMasteringSteps: Set<MasteringStep> {
        masteringProgress.failedSteps
    }

    var masteringActiveStepDetail: String? {
        masteringProgress.activeStepDetail
    }

    var isAnalyzingMetrics: Bool {
        displayAnalysisStates.isRunning(.metrics)
    }

    var isAnalyzingSpectrogram: Bool {
        displayAnalysisStates.isRunning(.spectrogram)
    }

    var isAnalyzingNoise: Bool {
        displayAnalysisStates.isRunning(.noise)
    }

    var isAnalyzingDisplayAnalysis: Bool {
        displayAnalysisStates.isRunningAny
    }

    var canUseCorrectedAnalysisForMastering: Bool {
        outputMasteringAnalysis != nil && outputNoiseMeasurements != nil
    }

    var displayAnalysisStatusText: String? {
        displayAnalysisStates.runningStatusText
    }

    var failedDisplayAnalysisText: String? {
        displayAnalysisStates.failedStatusText
    }

    func prepareForSelection(_ inputURL: URL) {
        inputFile = inputURL
        inputFileInfo = try? AudioFileService.fileInfo(for: inputURL)
        outputFileInfo = nil
        masteredFileInfo = nil
        outputFile = AudioProcessingService.defaultOutputURL(for: inputURL)
        masteredOutputFile = outputFile.map { MasteringService.defaultOutputURL(for: $0) }
        exportedCorrectedFile = nil
        exportedMasteredFile = nil
        resetAllAnalysisResults()
        correctionLog.reset()
        masteringLog.reset()
        activityEvents.removeAll()
        appendActivity(
            domain: .input,
            title: "ファイルを読み込みました",
            fileURL: inputURL,
            fileInfo: inputFileInfo
        )
        statusMessage = "処理待ち"
        masteringStatusMessage = "補正後に実行できます"
        processingStartedAt = nil
        processingFinishedAt = nil
        masteringStartedAt = nil
        masteringFinishedAt = nil
        lastError = nil
        masteringLastError = nil
        // Selecting a source file should not surface old outputs from prior runs.
        hasExistingOutput = false
        hasExistingMasteredOutput = false
        correctionProgress.reset()
        masteringProgress.reset()
        resetAllDisplayAnalysisStates()
        settingsState.resetAppliedSettings()
        applyCorrectionProfile(selectedDenoiseStrength)
        applyMasteringProfile(selectedMasteringProfile)
    }

    func beginProcessing(appliedSettings: CorrectionSettings? = nil) {
        didSendCorrectionCompletion = false
        didSendMasteringCompletion = false
        isProcessing = true
        lastError = nil
        correctionLog.reset()
        statusMessage = "処理中"
        processingStartedAt = Date()
        processingFinishedAt = nil
        exportedCorrectedFile = nil
        exportedMasteredFile = nil
        outputFileInfo = nil
        masteredFileInfo = nil
        correctionProgress.reset()
        masteredOutputFile = outputFile.map { MasteringService.defaultOutputURL(for: $0) }
        resetCorrectedAnalysisResults()
        resetMasteredAnalysisResults()
        resetDisplayAnalysisStates(for: .corrected)
        resetDisplayAnalysisStates(for: .mastered)
        masteringLog.reset()
        masteringStatusMessage = "補正後に実行できます"
        masteringStartedAt = nil
        masteringFinishedAt = nil
        masteringLastError = nil
        hasExistingMasteredOutput = false
        masteringProgress.reset()
        settingsState.resetAppliedSettings()
        appendActivity(
            domain: .correction,
            title: "補正処理を開始しました",
            detail: "準備中",
            progress: 0,
            isRunning: true
        )
    }

    func beginMastering(appliedSettings: MasteringSettings? = nil) {
        guard outputFile != nil else { return }
        didSendMasteringCompletion = false
        isMastering = true
        masteringLastError = nil
        masteringLog.reset()
        masteringStatusMessage = "マスタリング中"
        masteringStartedAt = Date()
        masteringFinishedAt = nil
        exportedMasteredFile = nil
        masteredFileInfo = nil
        masteringProgress.reset()
        masteredOutputFile = nil
        resetMasteredAnalysisResults()
        resetDisplayAnalysisStates(for: .mastered)
        hasExistingMasteredOutput = false
        settingsState.resetAppliedMasteringSettings()
        appendActivity(
            domain: .mastering,
            title: "マスタリングを開始しました",
            detail: "準備中",
            progress: 0,
            isRunning: true
        )
    }

    func applyMasteringProfile(_ profile: MasteringProfile) {
        settingsState.applyMasteringProfile(profile)
    }

    func resetMasteringSettingsToProfile() {
        settingsState.resetMasteringSettingsToProfile()
    }

    func updateMasteringSettings(_ update: (inout MasteringSettings) -> Void) {
        settingsState.updateMasteringSettings(update)
    }

    func applyCorrectionProfile(_ profile: DenoiseStrength) {
        settingsState.applyCorrectionProfile(profile)
    }

    func resetCorrectionSettingsToProfile() {
        settingsState.resetCorrectionSettingsToProfile()
    }

    func updateCorrectionSettings(_ update: (inout CorrectionSettings) -> Void) {
        settingsState.updateCorrectionSettings(update)
    }

    func finishInputMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        inputMetrics = metrics
        finishDisplayAnalysis(.metrics, for: .input)
        appendMetricActivity(title: "解析が完了しました", metrics: metrics, domain: .input)
    }

    func finishInputCorrectionAnalysis(_ analysis: AnalysisData, mode: AudioAnalysisMode) {
        inputCorrectionAnalysis = analysis
        inputCorrectionAnalysisMode = mode
        finishDisplayAnalysis(.correctionAnalysis, for: .input)
    }

    func finishInputNoiseMeasurement(_ measurements: NoiseMeasurementSnapshot) {
        inputNoiseMeasurements = measurements
        finishDisplayAnalysis(.noise, for: .input)
    }

    func finishOutputMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        outputMetrics = metrics
        finishDisplayAnalysis(.metrics, for: .corrected)
        appendMetricActivity(title: "補正後の解析が完了しました", metrics: metrics, domain: .correction)
    }

    func finishOutputMasteringAnalysis(_ analysis: MasteringAnalysis) {
        outputMasteringAnalysis = analysis
        finishDisplayAnalysis(.masteringAnalysis, for: .corrected)
        updateMasteringAvailabilityStatus()
    }

    func finishOutputNoiseMeasurement(_ measurements: NoiseMeasurementSnapshot) {
        outputNoiseMeasurements = measurements
        finishDisplayAnalysis(.noise, for: .corrected)
        updateMasteringAvailabilityStatus()
    }

    func finishMasteredMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        masteredMetrics = metrics
        finishDisplayAnalysis(.metrics, for: .mastered)
        appendMetricActivity(title: "最終版の解析が完了しました", metrics: metrics, domain: .mastering)
    }

    func finishMasteredNoiseMeasurement(_ measurements: NoiseMeasurementSnapshot) {
        masteredNoiseMeasurements = measurements
        finishDisplayAnalysis(.noise, for: .mastered)
    }

    func finishInputSpectrogram(_ snapshot: SpectrogramSnapshot) {
        inputSpectrogram = snapshot
        finishDisplayAnalysis(.spectrogram, for: .input)
    }

    func finishOutputSpectrogram(_ snapshot: SpectrogramSnapshot) {
        outputSpectrogram = snapshot
        finishDisplayAnalysis(.spectrogram, for: .corrected)
    }

    func finishMasteredSpectrogram(_ snapshot: SpectrogramSnapshot) {
        masteredSpectrogram = snapshot
        finishDisplayAnalysis(.spectrogram, for: .mastered)
    }

    func beginDisplayAnalysis(_ kind: DisplayAnalysisKind, for target: DisplayAnalysisTarget) {
        displayAnalysisStates.begin(kind, for: target)
    }

    func finishDisplayAnalysis(_ kind: DisplayAnalysisKind, for target: DisplayAnalysisTarget) {
        displayAnalysisStates.finish(kind, for: target)
    }

    func failDisplayAnalysis(_ kind: DisplayAnalysisKind, for target: DisplayAnalysisTarget) {
        displayAnalysisStates.fail(kind, for: target)
    }

    func displayAnalysisState(_ kind: DisplayAnalysisKind, for target: DisplayAnalysisTarget) -> DisplayAnalysisState {
        displayAnalysisStates.state(kind, for: target)
    }

    func isAnalyzingDisplayAnalysis(for target: DisplayAnalysisTarget) -> Bool {
        displayAnalysisStates.isRunningAny(for: target)
    }

    func hasFailedDisplayAnalysis(for target: DisplayAnalysisTarget) -> Bool {
        displayAnalysisStates.isFailedAny(for: target)
    }

    func resetDisplayAnalysisStates(for target: DisplayAnalysisTarget) {
        displayAnalysisStates.reset(for: target)
    }

    private func resetAllAnalysisResults() {
        resetInputAnalysisResults()
        resetCorrectedAnalysisResults()
        resetMasteredAnalysisResults()
    }

    private func resetInputAnalysisResults() {
        inputMetrics = nil
        inputCorrectionAnalysis = nil
        inputCorrectionAnalysisMode = nil
        inputNoiseMeasurements = nil
        inputSpectrogram = nil
    }

    private func resetCorrectedAnalysisResults() {
        outputMetrics = nil
        outputMasteringAnalysis = nil
        outputNoiseMeasurements = nil
        outputSpectrogram = nil
    }

    private func resetMasteredAnalysisResults() {
        masteredMetrics = nil
        masteredNoiseMeasurements = nil
        masteredSpectrogram = nil
    }

    private func resetAllDisplayAnalysisStates() {
        displayAnalysisStates.resetAll()
    }

    func appendLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let event = ProcessingProgressEvent.decode(trimmed) {
            applyProgressEvent(event)
            return
        }
        correctionLog.append(trimmed)
    }

    func appendMasteringLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let event = ProcessingProgressEvent.decode(trimmed) {
            applyProgressEvent(event)
            return
        }

        masteringLog.append(trimmed)
    }

    func finishSuccess(_ outputURL: URL, appliedSettings: CorrectionSettings? = nil) {
        isProcessing = false
        outputFile = outputURL
        outputFileInfo = try? AudioFileService.fileInfo(for: outputURL)
        masteredOutputFile = nil
        masteredFileInfo = nil
        statusMessage = "完了"
        processingFinishedAt = Date()
        hasExistingOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        correctionProgress.completeAll(ProcessingStep.allCases)
        completeRunningActivity(
            domain: .correction,
            title: "補正処理が完了しました",
            detail: outputURL.lastPathComponent,
            progress: 1,
            fileURL: outputURL,
            fileInfo: outputFileInfo
        )
        masteringStatusMessage = hasExistingOutput ? "補正後の解析中" : "補正後に実行できます"
        settingsState.storeAppliedCorrectionSettings(appliedSettings)
        if !didSendCorrectionCompletion {
            didSendCorrectionCompletion = true
            notificationReporter.notifyCompletion(for: .correction)
        }
    }

    func finishMasteringSuccess(_ outputURL: URL, appliedSettings: MasteringSettings? = nil) {
        isMastering = false
        masteredOutputFile = outputURL
        masteredFileInfo = try? AudioFileService.fileInfo(for: outputURL)
        masteringStatusMessage = "完了"
        masteringFinishedAt = Date()
        hasExistingMasteredOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        masteringProgress.completeAll(MasteringStep.allCases)
        completeRunningActivity(
            domain: .mastering,
            title: "マスタリングが完了しました",
            detail: outputURL.lastPathComponent,
            progress: 1,
            fileURL: outputURL,
            fileInfo: masteredFileInfo
        )
        settingsState.storeAppliedMasteringSettings(appliedSettings)
        if !didSendMasteringCompletion {
            didSendMasteringCompletion = true
            notificationReporter.notifyCompletion(for: .mastering)
        }
    }

    func finishCorrectedExport(_ url: URL) {
        exportedCorrectedFile = url
        appendActivity(
            domain: .export,
            title: "補正後を書き出しました",
            fileURL: url,
            fileInfo: try? AudioFileService.fileInfo(for: url)
        )
    }

    func finishMasteredExport(_ url: URL) {
        exportedMasteredFile = url
        appendActivity(
            domain: .export,
            title: "最終版を書き出しました",
            fileURL: url,
            fileInfo: try? AudioFileService.fileInfo(for: url)
        )
    }

    func finishFailure(_ message: String) {
        let failureProgress = progressValue
        isProcessing = false
        lastError = message
        statusMessage = "失敗"
        processingFinishedAt = Date()
        hasExistingOutput = outputFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        correctionProgress.failActiveStep()
        completeRunningActivity(
            domain: .correction,
            title: "補正処理に失敗しました",
            detail: message,
            progress: failureProgress,
            hasFailed: true
        )
        appendLog(message)
    }

    func finishMasteringFailure(_ message: String) {
        let failureProgress = masteringProgressValue
        isMastering = false
        masteringLastError = message
        masteringStatusMessage = "失敗"
        masteringFinishedAt = Date()
        hasExistingMasteredOutput = false
        masteringProgress.failActiveStep()
        completeRunningActivity(
            domain: .mastering,
            title: "マスタリングに失敗しました",
            detail: message,
            progress: failureProgress,
            hasFailed: true
        )
        appendMasteringLog(message)
    }

    private func updateMasteringAvailabilityStatus() {
        guard !isMastering, hasExistingOutput else { return }
        masteringStatusMessage = canUseCorrectedAnalysisForMastering ? "実行できます" : "補正後の解析中"
    }

    private func applyProgressEvent(_ event: ProcessingProgressEvent) {
        switch event {
        case let .correction(step, state, detail):
            correctionProgress.apply(step: step, state: state, detail: detail)
            updateRunningActivity(
                domain: .correction,
                title: "補正処理を実行中",
                detail: progressDetail(stepTitle: step.title, state: state, detail: detail),
                progress: progressValue
            )
        case let .mastering(step, state, detail):
            masteringProgress.apply(step: step, state: state, detail: detail)
            updateRunningActivity(
                domain: .mastering,
                title: "マスタリングを実行中",
                detail: progressDetail(stepTitle: step.title, state: state, detail: detail),
                progress: masteringProgressValue
            )
        }
    }

    var masteringProgressValue: Double {
        if !isMastering && masteringStatusMessage == "完了" {
            return 1
        }
        let total = Double(MasteringStep.allCases.count)
        let completed = Double(completedMasteringSteps.count)
        let skipped = Double(skippedMasteringSteps.count)
        let activeBoost = masteringActiveStep == nil ? 0 : 0.5
        return min(0.98, (completed + skipped + activeBoost) / total)
    }

    private func appendMetricActivity(title: String, metrics: AudioMetricSnapshot, domain: RecentActivityDomain) {
        appendActivity(
            domain: domain,
            title: title,
            detail: String(
                format: "ラウドネス: %.1f LUFS / ピーク: %.1f dBTP",
                metrics.integratedLoudnessLUFS,
                metrics.truePeakDBFS
            )
        )
    }

    private func appendActivity(
        domain: RecentActivityDomain,
        title: String,
        detail: String? = nil,
        fileURL: URL? = nil,
        fileInfo: AudioFileInfo? = nil,
        progress: Double? = nil,
        isRunning: Bool = false,
        hasFailed: Bool = false
    ) {
        activityEvents.append(
            RecentActivityEvent(
                domain: domain,
                title: title,
                detail: detail,
                fileName: fileURL?.lastPathComponent,
                audioSummary: fileInfo?.technicalSummary,
                progress: progress.map { min(max($0, 0), 1) },
                isRunning: isRunning,
                hasFailed: hasFailed
            )
        )
        if activityEvents.count > 20 {
            activityEvents.removeFirst(activityEvents.count - 20)
        }
    }

    private func updateRunningActivity(
        domain: RecentActivityDomain,
        title: String,
        detail: String?,
        progress: Double
    ) {
        guard let index = activityEvents.lastIndex(where: { $0.domain == domain && $0.isRunning }) else {
            appendActivity(domain: domain, title: title, detail: detail, progress: progress, isRunning: true)
            return
        }
        activityEvents[index].title = title
        activityEvents[index].detail = detail
        activityEvents[index].progress = min(max(progress, 0), 1)
    }

    private func completeRunningActivity(
        domain: RecentActivityDomain,
        title: String,
        detail: String?,
        progress: Double,
        fileURL: URL? = nil,
        fileInfo: AudioFileInfo? = nil,
        hasFailed: Bool = false
    ) {
        if let index = activityEvents.lastIndex(where: { $0.domain == domain && $0.isRunning }) {
            activityEvents[index].timestamp = Date()
            activityEvents[index].title = title
            activityEvents[index].detail = detail
            activityEvents[index].fileName = fileURL?.lastPathComponent
            activityEvents[index].audioSummary = fileInfo?.technicalSummary
            activityEvents[index].progress = min(max(progress, 0), 1)
            activityEvents[index].isRunning = false
            activityEvents[index].hasFailed = hasFailed
            return
        }
        if let index = activityEvents.lastIndex(where: { $0.domain == domain && $0.title == title }) {
            activityEvents[index].detail = detail
            activityEvents[index].fileName = fileURL?.lastPathComponent
            activityEvents[index].audioSummary = fileInfo?.technicalSummary
            activityEvents[index].progress = min(max(progress, 0), 1)
            activityEvents[index].timestamp = Date()
            activityEvents[index].hasFailed = hasFailed
            return
        }
        appendActivity(
            domain: domain,
            title: title,
            detail: detail,
            fileURL: fileURL,
            fileInfo: fileInfo,
            progress: progress,
            hasFailed: hasFailed
        )
    }

    private func progressDetail(
        stepTitle: String,
        state: ProcessingProgressEvent.State,
        detail: String?
    ) -> String {
        if let detail, !detail.isEmpty {
            return "\(stepTitle): \(detail)"
        }
        switch state {
        case .started, .detail:
            return "\(stepTitle)を実行中"
        case .completed:
            return "\(stepTitle)が完了"
        case .skipped:
            return "\(stepTitle)を省略"
        case .failed:
            return "\(stepTitle)に失敗"
        }
    }

}
