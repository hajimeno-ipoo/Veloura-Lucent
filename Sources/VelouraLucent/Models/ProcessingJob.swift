import SwiftUI

enum ProcessingStep: String, CaseIterable, Hashable {
    case loadAudio = "入力音声を読み込みます"
    case analyze = "音声を解析します"
    case routeNoiseMeasurement = "ノイズの種類を測定します"
    case lowNoiseCleanup = "低域ノイズを先に整えます"
    case denoise = "ノイズを除去します"
    case sibilanceShimmerGuard = "サ行保護を行います"
    case analyzeDenoised = "ノイズ除去後の音を解析します"
    case analysisAssist = "高域補完の必要性を確認します"
    case harmonicRepair = "高域を補完します"
    case repairShimmerGuard = "修復後シマーを確認します"
    case lowMidResidueGuard = "低中域の残りを軽く整えます"
    case shimmerPeakLimit = "シマーを抑えます"
    case correctionHighPreserve = "高域を保持します"
    case correctionMudGuard = "低中域の残りを確認します"
    case peakSafety = "ピークを保護します"
    case save = "処理済みファイルを書き出します"

    var title: String {
        switch self {
        case .loadAudio: "読み込み"
        case .analyze: "解析"
        case .routeNoiseMeasurement: "ノイズ測定"
        case .lowNoiseCleanup: "低域整理"
        case .denoise: "ノイズ除去"
        case .sibilanceShimmerGuard: "サ行保護"
        case .analyzeDenoised: "再解析"
        case .analysisAssist: "解析補助"
        case .harmonicRepair: "高域修復"
        case .repairShimmerGuard: "修復後シマー"
        case .lowMidResidueGuard: "低中域整理"
        case .shimmerPeakLimit: "シマー制限"
        case .correctionHighPreserve: "高域保持"
        case .correctionMudGuard: "低中域確認"
        case .peakSafety: "ピーク保護"
        case .save: "書き出し"
        }
    }

    var eventID: String {
        switch self {
        case .loadAudio: "loadAudio"
        case .analyze: "analyze"
        case .routeNoiseMeasurement: "routeNoiseMeasurement"
        case .lowNoiseCleanup: "lowNoiseCleanup"
        case .denoise: "denoise"
        case .sibilanceShimmerGuard: "sibilanceShimmerGuard"
        case .analyzeDenoised: "analyzeDenoised"
        case .analysisAssist: "analysisAssist"
        case .harmonicRepair: "harmonicRepair"
        case .repairShimmerGuard: "repairShimmerGuard"
        case .lowMidResidueGuard: "lowMidResidueGuard"
        case .shimmerPeakLimit: "shimmerPeakLimit"
        case .correctionHighPreserve: "correctionHighPreserve"
        case .correctionMudGuard: "correctionMudGuard"
        case .peakSafety: "peakSafety"
        case .save: "save"
        }
    }

    static func step(eventID: String) -> ProcessingStep? {
        allCases.first { $0.eventID == eventID }
    }
}

enum ProcessingProgressEvent: Sendable, Equatable {
    enum Domain: String, Sendable, Equatable {
        case correction
        case mastering
    }

    enum State: String, Sendable, Equatable {
        case started
        case completed
        case skipped
        case failed
        case detail
    }

    private static let prefix = "__veloura_progress__"

    case correction(step: ProcessingStep, state: State, detail: String?)
    case mastering(step: MasteringStep, state: State, detail: String?)

    var encodedMessage: String {
        let parts: [String]
        switch self {
        case let .correction(step, state, detail):
            parts = [Self.prefix, Domain.correction.rawValue, state.rawValue, step.eventID, detail ?? ""]
        case let .mastering(step, state, detail):
            parts = [Self.prefix, Domain.mastering.rawValue, state.rawValue, step.eventID, detail ?? ""]
        }
        return parts.map(Self.encodePart).joined(separator: "|")
    }

    static func decode(_ message: String) -> ProcessingProgressEvent? {
        let parts = message.split(separator: "|", omittingEmptySubsequences: false).map { decodePart(String($0)) }
        guard parts.count == 5, parts[0] == prefix else { return nil }
        guard let domain = Domain(rawValue: parts[1]), let state = State(rawValue: parts[2]) else { return nil }
        let detail = parts[4].isEmpty ? nil : parts[4]
        switch domain {
        case .correction:
            guard let step = ProcessingStep.step(eventID: parts[3]) else { return nil }
            return .correction(step: step, state: state, detail: detail)
        case .mastering:
            guard let step = MasteringStep.step(eventID: parts[3]) else { return nil }
            return .mastering(step: step, state: state, detail: detail)
        }
    }

    private static func encodePart(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%", with: "%25")
            .replacingOccurrences(of: "|", with: "%7C")
            .replacingOccurrences(of: "\n", with: "%0A")
    }

    private static func decodePart(_ value: String) -> String {
        value
            .replacingOccurrences(of: "%0A", with: "\n")
            .replacingOccurrences(of: "%7C", with: "|")
            .replacingOccurrences(of: "%25", with: "%")
    }
}

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
    var inputMetrics: AudioMetricSnapshot?
    var outputMetrics: AudioMetricSnapshot?
    var masteredMetrics: AudioMetricSnapshot?
    var inputCorrectionAnalysis: AnalysisData?
    var inputCorrectionAnalysisMode: AudioAnalysisMode?
    var outputMasteringAnalysis: MasteringAnalysis?
    var inputNoiseMeasurements: NoiseMeasurementSnapshot?
    var outputNoiseMeasurements: NoiseMeasurementSnapshot?
    var masteredNoiseMeasurements: NoiseMeasurementSnapshot?
    var denoiseEffectReport: DenoiseEffectReport?
    var inputSpectrogram: SpectrogramSnapshot?
    var outputSpectrogram: SpectrogramSnapshot?
    var masteredSpectrogram: SpectrogramSnapshot?
    static let visibleLogLineLimit = 80
    private(set) var logLines: [String] = []
    private(set) var masteringLogLines: [String] = []
    var logText: String {
        logLines.joined(separator: "\n")
    }
    var masteringLogText: String {
        masteringLogLines.joined(separator: "\n")
    }
    var visibleLogLines: [String] {
        Array(logLines.suffix(Self.visibleLogLineLimit))
    }
    var visibleMasteringLogLines: [String] {
        Array(masteringLogLines.suffix(Self.visibleLogLineLimit))
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
    var selectedMasteringProfile: MasteringProfile = .streaming
    var editableMasteringSettings: MasteringSettings = MasteringProfile.streaming.settings
    var isUsingCustomMasteringSettings = false
    var showAdvancedMasteringSettings = false
    var selectedDenoiseStrength: DenoiseStrength = .balanced
    var editableCorrectionSettings: CorrectionSettings = DenoiseStrength.balanced.settings
    var isUsingCustomCorrectionSettings = false
    var showAdvancedCorrectionSettings = false
    var appliedCorrectionSettings: CorrectionSettings?
    var appliedMasteringSettings: MasteringSettings?
    var selectedAnalysisMode: AudioAnalysisMode = .auto

    init(notificationReporter: CompletionNotificationReporting = NoOpCompletionNotificationReporter.shared) {
        self.notificationReporter = notificationReporter
    }

    var statusColor: Color {
        if isProcessing {
            return .orange
        }
        if lastError != nil {
            return .red
        }
        return .secondary
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
        outputFile = AudioProcessingService.defaultOutputURL(for: inputURL)
        masteredOutputFile = outputFile.map { MasteringService.defaultOutputURL(for: $0) }
        exportedCorrectedFile = nil
        exportedMasteredFile = nil
        inputMetrics = nil
        outputMetrics = nil
        masteredMetrics = nil
        inputCorrectionAnalysis = nil
        inputCorrectionAnalysisMode = nil
        outputMasteringAnalysis = nil
        inputNoiseMeasurements = nil
        outputNoiseMeasurements = nil
        masteredNoiseMeasurements = nil
        denoiseEffectReport = nil
        inputSpectrogram = nil
        outputSpectrogram = nil
        masteredSpectrogram = nil
        logLines.removeAll()
        masteringLogLines.removeAll()
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
        appliedCorrectionSettings = nil
        appliedMasteringSettings = nil
        applyCorrectionProfile(selectedDenoiseStrength)
        applyMasteringProfile(selectedMasteringProfile)
    }

    func beginProcessing(appliedSettings: CorrectionSettings? = nil) {
        didSendCorrectionCompletion = false
        didSendMasteringCompletion = false
        isProcessing = true
        lastError = nil
        logLines.removeAll()
        statusMessage = "処理中"
        processingStartedAt = Date()
        processingFinishedAt = nil
        correctionProgress.reset()
        masteredOutputFile = outputFile.map { MasteringService.defaultOutputURL(for: $0) }
        outputMetrics = nil
        masteredMetrics = nil
        outputMasteringAnalysis = nil
        outputNoiseMeasurements = nil
        masteredNoiseMeasurements = nil
        denoiseEffectReport = nil
        outputSpectrogram = nil
        masteredSpectrogram = nil
        resetDisplayAnalysisStates(for: .corrected)
        resetDisplayAnalysisStates(for: .mastered)
        masteringLogLines.removeAll()
        masteringStatusMessage = "補正後に実行できます"
        masteringStartedAt = nil
        masteringFinishedAt = nil
        masteringLastError = nil
        hasExistingMasteredOutput = false
        masteringProgress.reset()
        appliedCorrectionSettings = nil
        appliedMasteringSettings = nil
    }

    func beginMastering(appliedSettings: MasteringSettings? = nil) {
        guard outputFile != nil else { return }
        didSendMasteringCompletion = false
        isMastering = true
        masteringLastError = nil
        masteringLogLines.removeAll()
        masteringStatusMessage = "マスタリング中"
        masteringStartedAt = Date()
        masteringFinishedAt = nil
        masteringProgress.reset()
        masteredOutputFile = nil
        masteredMetrics = nil
        masteredNoiseMeasurements = nil
        masteredSpectrogram = nil
        resetDisplayAnalysisStates(for: .mastered)
        hasExistingMasteredOutput = false
        appliedMasteringSettings = nil
    }

    func applyMasteringProfile(_ profile: MasteringProfile) {
        selectedMasteringProfile = profile
        editableMasteringSettings = profile.settings
        isUsingCustomMasteringSettings = false
    }

    func resetMasteringSettingsToProfile() {
        applyMasteringProfile(selectedMasteringProfile)
    }

    func updateMasteringSettings(_ update: (inout MasteringSettings) -> Void) {
        update(&editableMasteringSettings)
        isUsingCustomMasteringSettings = true
    }

    func applyCorrectionProfile(_ profile: DenoiseStrength) {
        selectedDenoiseStrength = profile
        editableCorrectionSettings = profile.settings
        isUsingCustomCorrectionSettings = false
    }

    func resetCorrectionSettingsToProfile() {
        applyCorrectionProfile(selectedDenoiseStrength)
    }

    func updateCorrectionSettings(_ update: (inout CorrectionSettings) -> Void) {
        update(&editableCorrectionSettings)
        editableCorrectionSettings.profile = selectedDenoiseStrength
        isUsingCustomCorrectionSettings = true
    }

    func finishInputMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        inputMetrics = metrics
        finishDisplayAnalysis(.metrics, for: .input)
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

    func resetDisplayAnalysisStates(for target: DisplayAnalysisTarget) {
        displayAnalysisStates.reset(for: target)
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
        updateDenoiseEffectReport(for: trimmed)

        logLines.append(trimmed)
    }

    func appendMasteringLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let event = ProcessingProgressEvent.decode(trimmed) {
            applyProgressEvent(event)
            return
        }

        masteringLogLines.append(trimmed)
    }

    func finishSuccess(_ outputURL: URL, appliedSettings: CorrectionSettings? = nil) {
        isProcessing = false
        outputFile = outputURL
        masteredOutputFile = nil
        statusMessage = "完了"
        processingFinishedAt = Date()
        hasExistingOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        correctionProgress.completeAll(ProcessingStep.allCases)
        masteringStatusMessage = hasExistingOutput ? "補正後の解析中" : "補正後に実行できます"
        appliedCorrectionSettings = appliedSettings ?? appliedCorrectionSettings ?? editableCorrectionSettings
        if !didSendCorrectionCompletion {
            didSendCorrectionCompletion = true
            notificationReporter.notifyCompletion(for: .correction)
        }
    }

    func finishMasteringSuccess(_ outputURL: URL, appliedSettings: MasteringSettings? = nil) {
        isMastering = false
        masteredOutputFile = outputURL
        masteringStatusMessage = "完了"
        masteringFinishedAt = Date()
        hasExistingMasteredOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        masteringProgress.completeAll(MasteringStep.allCases)
        appliedMasteringSettings = appliedSettings ?? appliedMasteringSettings ?? editableMasteringSettings
        if !didSendMasteringCompletion {
            didSendMasteringCompletion = true
            notificationReporter.notifyCompletion(for: .mastering)
        }
    }

    func finishCorrectedExport(_ url: URL) {
        exportedCorrectedFile = url
    }

    func finishMasteredExport(_ url: URL) {
        exportedMasteredFile = url
    }

    func finishFailure(_ message: String) {
        isProcessing = false
        lastError = message
        statusMessage = "失敗"
        processingFinishedAt = Date()
        hasExistingOutput = outputFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        correctionProgress.failActiveStep()
        appendLog(message)
    }

    func finishMasteringFailure(_ message: String) {
        isMastering = false
        masteringLastError = message
        masteringStatusMessage = "失敗"
        masteringFinishedAt = Date()
        hasExistingMasteredOutput = false
        masteringProgress.failActiveStep()
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
        case let .mastering(step, state, detail):
            masteringProgress.apply(step: step, state: state, detail: detail)
        }
    }

    private func updateDenoiseEffectReport(for message: String) {
        guard message.hasPrefix("ノイズ除去/") else { return }
        let current = denoiseEffectReport ?? .empty

        if let value = decibelValue(in: message, prefix: "ノイズ除去/10-16kHzチラつき: ") {
            denoiseEffectReport = DenoiseEffectReport(
                shimmerFlickerChangeDB: value,
                hf12ChangeDB: current.hf12ChangeDB,
                hf16ChangeDB: current.hf16ChangeDB,
                hf18ChangeDB: current.hf18ChangeDB
            )
        } else if let value = decibelValue(in: message, prefix: "ノイズ除去/12kHz以上: ") {
            denoiseEffectReport = DenoiseEffectReport(
                shimmerFlickerChangeDB: current.shimmerFlickerChangeDB,
                hf12ChangeDB: value,
                hf16ChangeDB: current.hf16ChangeDB,
                hf18ChangeDB: current.hf18ChangeDB
            )
        } else if let value = decibelValue(in: message, prefix: "ノイズ除去/16kHz以上: ") {
            denoiseEffectReport = DenoiseEffectReport(
                shimmerFlickerChangeDB: current.shimmerFlickerChangeDB,
                hf12ChangeDB: current.hf12ChangeDB,
                hf16ChangeDB: value,
                hf18ChangeDB: current.hf18ChangeDB
            )
        } else if let value = decibelValue(in: message, prefix: "ノイズ除去/18kHz以上: ") {
            denoiseEffectReport = DenoiseEffectReport(
                shimmerFlickerChangeDB: current.shimmerFlickerChangeDB,
                hf12ChangeDB: current.hf12ChangeDB,
                hf16ChangeDB: current.hf16ChangeDB,
                hf18ChangeDB: value
            )
        }
    }

    private func decibelValue(in message: String, prefix: String) -> Double? {
        guard message.hasPrefix(prefix) else { return nil }
        let rawValue = message
            .dropFirst(prefix.count)
            .replacingOccurrences(of: "dB", with: "")
            .replacingOccurrences(of: "±", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(rawValue)
    }

}
