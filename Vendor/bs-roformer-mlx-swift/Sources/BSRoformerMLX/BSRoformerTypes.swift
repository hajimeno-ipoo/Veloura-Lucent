import Foundation

public enum BSRoformerStem: String, CaseIterable, Sendable {
    case bass
    case drums
    case other
    case vocals
    case guitar
    case piano
}

public struct BSRoformerAudio: Sendable {
    public let channelMajorSamples: [Float]
    public let channels: Int
    public let sampleRate: Int

    public var frameCount: Int {
        channelMajorSamples.count / channels
    }

    public init(channelMajorSamples: [Float], channels: Int, sampleRate: Int) throws {
        guard channels > 0, channelMajorSamples.count.isMultiple(of: channels) else {
            throw BSRoformerError.invalidAudio("チャンネル数とサンプル数が一致しません")
        }
        self.channelMajorSamples = channelMajorSamples
        self.channels = channels
        self.sampleRate = sampleRate
    }
}

public struct BSRoformerSeparation: Sendable {
    public let stems: [BSRoformerStem: BSRoformerAudio]

    public init(stems: [BSRoformerStem: BSRoformerAudio]) {
        self.stems = stems
    }
}

public enum BSRoformerError: LocalizedError {
    case invalidConfiguration(String)
    case invalidWeights(String)
    case invalidAudio(String)
    case audioIO(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            "BS-RoFormer設定エラー: \(message)"
        case .invalidWeights(let message):
            "BS-RoFormer重みエラー: \(message)"
        case .invalidAudio(let message):
            "BS-RoFormer音声エラー: \(message)"
        case .audioIO(let message):
            "BS-RoFormer入出力エラー: \(message)"
        case .cancelled:
            "BS-RoFormerの処理はキャンセルされました"
        }
    }
}
