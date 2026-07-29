import Foundation

/// 補正開始時に現在のStemセッションへ固定する解析モードです。
enum StemAudioAnalysisMode: String, CaseIterable, Equatable, Sendable {
    case auto
    case cpu
    case experimentalMetal

    init(_ mode: AudioAnalysisMode) {
        switch mode {
        case .auto: self = .auto
        case .cpu: self = .cpu
        case .experimentalMetal: self = .experimentalMetal
        }
    }

    var audioAnalysisMode: AudioAnalysisMode {
        switch self {
        case .auto: .auto
        case .cpu: .cpu
        case .experimentalMetal: .experimentalMetal
        }
    }

    var resolvedAudioAnalysisMode: AudioAnalysisMode {
        audioAnalysisMode.resolvedMode
    }
}

enum StemAudioEvaluationPurpose: Equatable, Sendable {
    case canonicalInput
    case rawStem(role: StemRole)
    case correctedStem(role: StemRole)
    case rawRemix
    case correctedPureSum
    case remix
    case finalMaster
}

enum StemAudioEvaluationMeasurement: String, Equatable, Sendable {
    case audioComparisonSnapshot
    case noiseMeasurementSnapshot
    case audioAnalyzerSnapshot
    case masteringAnalysisSnapshot
}

enum StemAudioEvaluationError: LocalizedError, Equatable, Sendable {
    case noChannels
    case invalidSampleRate
    case emptySignal
    case inconsistentFrameCount(channelIndex: Int, expected: Int, actual: Int)
    case nonFiniteSample(channelIndex: Int, frameIndex: Int)

    var errorDescription: String? {
        switch self {
        case .noChannels: "Stem解析対象に音声チャンネルがありません。"
        case .invalidSampleRate: "Stem解析対象のサンプルレートが不正です。"
        case .emptySignal: "Stem解析対象に音声フレームがありません。"
        case let .inconsistentFrameCount(channelIndex, expected, actual):
            "Stem解析対象のフレーム数が一致しません（channel \(channelIndex)、期待: \(expected)、実際: \(actual)）。"
        case let .nonFiniteSample(channelIndex, frameIndex):
            "Stem解析対象にNaNまたはInfinityがあります（channel \(channelIndex)、frame \(frameIndex)）。"
        }
    }
}

struct StemAudioEvaluationRequest: Equatable, Sendable {
    let purpose: StemAudioEvaluationPurpose
    let includeAudioAnalyzerSnapshot: Bool
    let includeMasteringAnalysisSnapshot: Bool
    let analysisMode: StemAudioAnalysisMode

    init(
        purpose: StemAudioEvaluationPurpose,
        includeAudioAnalyzerSnapshot: Bool,
        includeMasteringAnalysisSnapshot: Bool,
        analysisMode: StemAudioAnalysisMode = .auto
    ) {
        self.purpose = purpose
        self.includeAudioAnalyzerSnapshot = includeAudioAnalyzerSnapshot
        self.includeMasteringAnalysisSnapshot = includeMasteringAnalysisSnapshot
        self.analysisMode = analysisMode
    }

    var requestedMeasurements: [StemAudioEvaluationMeasurement] {
        var measurements: [StemAudioEvaluationMeasurement] = [
            .audioComparisonSnapshot,
            .noiseMeasurementSnapshot,
        ]
        if includeAudioAnalyzerSnapshot {
            measurements.append(.audioAnalyzerSnapshot)
        }
        if includeMasteringAnalysisSnapshot {
            measurements.append(.masteringAnalysisSnapshot)
        }
        return measurements
    }
}

/// 現在のStemセッション内だけで使用する解析結果です。
/// JSON、schema、再開用snapshotは所有しません。
struct StemAudioEvaluationSnapshot: Sendable {
    let request: StemAudioEvaluationRequest
    let completedMeasurements: [StemAudioEvaluationMeasurement]
    let audioMetrics: AudioMetricSnapshot
    let noiseMeasurements: NoiseMeasurementSnapshot
    let audioAnalysis: AnalysisData?
    let masteringAnalysis: MasteringAnalysis?

    var purpose: StemAudioEvaluationPurpose { request.purpose }
}
