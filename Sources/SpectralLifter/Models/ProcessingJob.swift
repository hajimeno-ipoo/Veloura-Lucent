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
    var logText = ""
    var statusMessage = "待機中"
    var isProcessing = false
    var lastError: String?
    var hasExistingOutput = false
    var activeStep: ProcessingStep?
    var completedSteps: Set<ProcessingStep> = []

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
        logText = ""
        statusMessage = "処理待ち"
        lastError = nil
        hasExistingOutput = outputFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        activeStep = nil
        completedSteps = []
    }

    func beginProcessing() {
        isProcessing = true
        lastError = nil
        logText = ""
        statusMessage = "処理中"
        activeStep = nil
        completedSteps = []
    }

    func appendLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateProgress(for: trimmed)

        if logText.isEmpty {
            logText = trimmed
        } else {
            logText += "\n\(trimmed)"
        }
    }

    func finishSuccess(_ outputURL: URL) {
        isProcessing = false
        outputFile = outputURL
        statusMessage = "完了"
        hasExistingOutput = FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false))
        completedSteps = Set(ProcessingStep.allCases)
        activeStep = nil
    }

    func finishFailure(_ message: String) {
        isProcessing = false
        lastError = message
        statusMessage = "失敗"
        hasExistingOutput = outputFile.map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } ?? false
        activeStep = nil
        appendLog(message)
    }

    private func updateProgress(for message: String) {
        guard let nextStep = ProcessingStep(rawValue: message) else { return }
        if let activeStep {
            completedSteps.insert(activeStep)
        }
        activeStep = nextStep
    }
}
