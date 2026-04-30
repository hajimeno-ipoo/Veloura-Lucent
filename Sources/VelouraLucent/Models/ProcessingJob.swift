import SwiftUI

enum ProcessingStep: String, CaseIterable, Hashable {
    case loadAudio = "入力音声を読み込みます"
    case analyze = "音声を解析します"
    case denoise = "ノイズを除去します"
    case upscale = "高域を補完します"
    case dynamics = "ダイナミクスを整えます"
    case loudness = "最終音量を整えます"
    case save = "処理済みファイルを書き出します"

    var title: String {
        switch self {
        case .loadAudio: "読み込み"
        case .analyze: "解析"
        case .denoise: "ノイズ除去"
        case .upscale: "高域補完"
        case .dynamics: "ダイナミクス"
        case .loudness: "音量調整"
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
        applyMasteringProfile(selectedMasteringProfile)
    }

    func beginProcessing() {
        isProcessing = true
        lastError = nil
        logText = ""
        statusMessage = "処理中"
        activeStep = nil
        completedSteps = []
        masteredOutputFile = outputFile.map { MasteringService.defaultOutputURL(for: $0) }
        masteredMetrics = nil
        denoiseEffectReport = nil
        outputSpectrogram = nil
        masteredSpectrogram = nil
        masteringLogText = ""
        masteringStatusMessage = "補正後に実行できます"
        masteringLastError = nil
        hasExistingMasteredOutput = false
        masteringActiveStep = nil
        completedMasteringSteps = []
    }

    func beginMastering() {
        guard outputFile != nil else { return }
        isMastering = true
        masteringLastError = nil
        masteringLogText = ""
        masteringStatusMessage = "マスタリング中"
        masteringActiveStep = nil
        completedMasteringSteps = []
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

    func beginMetricAnalysis() {
        isAnalyzingMetrics = true
    }

    func finishInputMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        inputMetrics = metrics
        isAnalyzingMetrics = false
    }

    func finishOutputMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        outputMetrics = metrics
        isAnalyzingMetrics = false
    }

    func finishMasteredMetricAnalysis(_ metrics: AudioMetricSnapshot) {
        masteredMetrics = metrics
        isAnalyzingMetrics = false
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

    func finishSuccess(_ outputURL: URL) {
        isProcessing = false
        outputFile = outputURL
        masteredOutputFile = nil
        statusMessage = "完了"
        hasExistingOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        completedSteps = Set(ProcessingStep.allCases)
        activeStep = nil
        masteringStatusMessage = hasExistingOutput ? "実行できます" : "補正後に実行できます"
    }

    func finishMasteringSuccess(_ outputURL: URL) {
        isMastering = false
        masteredOutputFile = outputURL
        masteringStatusMessage = "完了"
        hasExistingMasteredOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        completedMasteringSteps = Set(MasteringStep.allCases)
        masteringActiveStep = nil
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
