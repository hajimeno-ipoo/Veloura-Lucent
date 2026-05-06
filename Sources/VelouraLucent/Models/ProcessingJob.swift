import SwiftUI

enum ProcessingStep: String, CaseIterable, Hashable {
    case loadAudio = "入力音声を読み込みます"
    case analyze = "音声を解析します"
    case lowNoiseCleanup = "低域ノイズを先に整えます"
    case denoise = "ノイズを除去します"
    case sibilanceShimmerGuard = "サ行保護を行います"
    case harmonicRepair = "高域を補完します"
    case lowMidResidueGuard = "低中域の残りを軽く整えます"
    case shimmerPeakLimit = "シマーを抑えます"
    case peakSafety = "ピークを保護します"
    case save = "処理済みファイルを書き出します"

    var title: String {
        switch self {
        case .loadAudio: "読み込み"
        case .analyze: "解析"
        case .lowNoiseCleanup: "低域整理"
        case .denoise: "ノイズ除去"
        case .sibilanceShimmerGuard: "サ行保護"
        case .harmonicRepair: "高域修復"
        case .lowMidResidueGuard: "低中域整理"
        case .shimmerPeakLimit: "シマー制限"
        case .peakSafety: "ピーク保護"
        case .save: "書き出し"
        }
    }
}

@MainActor
@Observable
final class ProcessingJob {
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
    var logText = ""
    var masteringLogText = ""
    var statusMessage = "待機中"
    var masteringStatusMessage = "待機中"
    var isProcessing = false
    var isMastering = false
    var lastError: String?
    var masteringLastError: String?
    var hasExistingOutput = false
    var hasExistingMasteredOutput = false
    var activeStep: ProcessingStep?
    var completedSteps: Set<ProcessingStep> = []
    var masteringActiveStep: MasteringStep?
    var completedMasteringSteps: Set<MasteringStep> = []
    var isAnalyzingMetrics = false
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
        let activeBoost = activeStep == nil ? 0 : 0.5
        return min(0.98, (completed + activeBoost) / total)
    }

    var progressLabel: String {
        if let activeStep {
            return "\(activeStep.title) を実行中"
        }
        return statusMessage
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
        logText = ""
        masteringLogText = ""
        statusMessage = "処理待ち"
        masteringStatusMessage = "補正後に実行できます"
        lastError = nil
        masteringLastError = nil
        // Selecting a source file should not surface old outputs from prior runs.
        hasExistingOutput = false
        hasExistingMasteredOutput = false
        activeStep = nil
        completedSteps = []
        masteringActiveStep = nil
        completedMasteringSteps = []
        appliedCorrectionSettings = nil
        appliedMasteringSettings = nil
        applyCorrectionProfile(selectedDenoiseStrength)
        applyMasteringProfile(selectedMasteringProfile)
    }

    func beginProcessing(appliedSettings: CorrectionSettings? = nil) {
        isProcessing = true
        lastError = nil
        logText = ""
        statusMessage = "処理中"
        activeStep = nil
        completedSteps = []
        masteredOutputFile = outputFile.map { MasteringService.defaultOutputURL(for: $0) }
        outputMetrics = nil
        masteredMetrics = nil
        outputMasteringAnalysis = nil
        outputNoiseMeasurements = nil
        masteredNoiseMeasurements = nil
        denoiseEffectReport = nil
        outputSpectrogram = nil
        masteredSpectrogram = nil
        masteringLogText = ""
        masteringStatusMessage = "補正後に実行できます"
        masteringLastError = nil
        hasExistingMasteredOutput = false
        masteringActiveStep = nil
        completedMasteringSteps = []
        appliedCorrectionSettings = nil
        appliedMasteringSettings = nil
    }

    func beginMastering(appliedSettings: MasteringSettings? = nil) {
        guard outputFile != nil else { return }
        isMastering = true
        masteringLastError = nil
        masteringLogText = ""
        masteringStatusMessage = "マスタリング中"
        masteringActiveStep = nil
        completedMasteringSteps = []
        masteredMetrics = nil
        masteredNoiseMeasurements = nil
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

    func beginMetricAnalysis() {
        isAnalyzingMetrics = true
    }

    func finishInputMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        inputMetrics = metrics
        isAnalyzingMetrics = false
    }

    func finishInputCorrectionAnalysis(_ analysis: AnalysisData, mode: AudioAnalysisMode) {
        inputCorrectionAnalysis = analysis
        inputCorrectionAnalysisMode = mode
    }

    func finishInputNoiseMeasurement(_ measurements: NoiseMeasurementSnapshot) {
        inputNoiseMeasurements = measurements
    }

    func finishOutputMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        outputMetrics = metrics
        isAnalyzingMetrics = false
    }

    func finishOutputMasteringAnalysis(_ analysis: MasteringAnalysis) {
        outputMasteringAnalysis = analysis
    }

    func finishOutputNoiseMeasurement(_ measurements: NoiseMeasurementSnapshot) {
        outputNoiseMeasurements = measurements
    }

    func finishMasteredMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        masteredMetrics = metrics
        isAnalyzingMetrics = false
    }

    func finishMasteredNoiseMeasurement(_ measurements: NoiseMeasurementSnapshot) {
        masteredNoiseMeasurements = measurements
    }

    func finishInputSpectrogram(_ snapshot: SpectrogramSnapshot) {
        inputSpectrogram = snapshot
    }

    func finishOutputSpectrogram(_ snapshot: SpectrogramSnapshot) {
        outputSpectrogram = snapshot
    }

    func finishMasteredSpectrogram(_ snapshot: SpectrogramSnapshot) {
        masteredSpectrogram = snapshot
    }

    func failMetricAnalysis() {
        isAnalyzingMetrics = false
    }

    func appendLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateProgress(for: trimmed)
        updateDenoiseEffectReport(for: trimmed)

        if logText.isEmpty {
            logText = trimmed
        } else {
            logText += "\n\(trimmed)"
        }
    }

    func appendMasteringLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateMasteringProgress(for: trimmed)

        if masteringLogText.isEmpty {
            masteringLogText = trimmed
        } else {
            masteringLogText += "\n\(trimmed)"
        }
    }

    func finishSuccess(_ outputURL: URL, appliedSettings: CorrectionSettings? = nil) {
        isProcessing = false
        outputFile = outputURL
        masteredOutputFile = nil
        statusMessage = "完了"
        hasExistingOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        completedSteps = Set(ProcessingStep.allCases)
        activeStep = nil
        masteringStatusMessage = hasExistingOutput ? "実行できます" : "補正後に実行できます"
        appliedCorrectionSettings = appliedSettings ?? appliedCorrectionSettings ?? editableCorrectionSettings
    }

    func finishMasteringSuccess(_ outputURL: URL, appliedSettings: MasteringSettings? = nil) {
        isMastering = false
        masteredOutputFile = outputURL
        masteringStatusMessage = "完了"
        hasExistingMasteredOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        completedMasteringSteps = Set(MasteringStep.allCases)
        masteringActiveStep = nil
        appliedMasteringSettings = appliedSettings ?? appliedMasteringSettings ?? editableMasteringSettings
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
        hasExistingOutput = outputFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        activeStep = nil
        appendLog(message)
    }

    func finishMasteringFailure(_ message: String) {
        isMastering = false
        masteringLastError = message
        masteringStatusMessage = "失敗"
        hasExistingMasteredOutput = masteredOutputFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        masteringActiveStep = nil
        appendMasteringLog(message)
    }

    private func updateProgress(for message: String) {
        guard let nextStep = ProcessingStep(rawValue: message) else { return }
        if let activeStep {
            completedSteps.insert(activeStep)
        }
        activeStep = nextStep
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

    private func updateMasteringProgress(for message: String) {
        guard let nextStep = MasteringStep(rawValue: message) else { return }
        if let masteringActiveStep {
            completedMasteringSteps.insert(masteringActiveStep)
        }
        masteringActiveStep = nextStep
    }
}
