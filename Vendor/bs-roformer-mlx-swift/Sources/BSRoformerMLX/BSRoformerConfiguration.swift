import Foundation

public struct BSRoformerConfiguration: Codable, Equatable, Sendable {
    public let sampleRate: Int
    public let channels: Int
    public let stemNames: [String]
    public let dimension: Int
    public let depth: Int
    public let timeTransformerDepth: Int
    public let frequencyTransformerDepth: Int
    public let linearTransformerDepth: Int
    public let frequenciesPerBand: [Int]
    public let headDimension: Int
    public let headCount: Int
    public let mlpExpansionFactor: Int
    public let maskEstimatorDepth: Int
    public let stftFFTSize: Int
    public let stftHopLength: Int
    public let stftWindowLength: Int
    public let stftNormalized: Bool
    public let inferenceFrameCount: Int
    public let shortAudioThresholdSeconds: Int
    public let shortAudioInferenceFrameCount: Int
    public let overlapSeconds: Int

    public var stemCount: Int { stemNames.count }
    public var frequencyBinCount: Int { stftFFTSize / 2 + 1 }
    public var chunkSampleCount: Int { stftHopLength * (inferenceFrameCount - 1) }

    public func chunkSampleCount(for totalFrames: Int) -> Int {
        let threshold = shortAudioThresholdSeconds * sampleRate
        let frameCount = totalFrames < threshold
            ? shortAudioInferenceFrameCount
            : inferenceFrameCount
        return stftHopLength * (frameCount - 1)
    }

    public func stepSampleCount(for chunkSampleCount: Int) -> Int {
        min(chunkSampleCount, overlapSeconds * sampleRate)
    }

    public static func load(from url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        let configuration = try JSONDecoder().decode(Self.self, from: data)
        try configuration.validate()
        return configuration
    }

    public func validate() throws {
        guard sampleRate == 44_100 else {
            throw BSRoformerError.invalidConfiguration("sampleRateは44100である必要があります")
        }
        guard channels == 2 else {
            throw BSRoformerError.invalidConfiguration("channelsは2である必要があります")
        }
        guard stemNames == ["bass", "drums", "other", "vocals", "guitar", "piano"] else {
            throw BSRoformerError.invalidConfiguration("6ステムの順序がBS-RoFormer-SWと一致しません")
        }
        guard dimension == 256,
              depth == 12,
              timeTransformerDepth == 1,
              frequencyTransformerDepth == 1,
              linearTransformerDepth == 0,
              headDimension == 64,
              headCount == 8,
              mlpExpansionFactor == 4 else {
            throw BSRoformerError.invalidConfiguration("未対応のTransformer構成です")
        }
        guard maskEstimatorDepth == 2, frequenciesPerBand.count == 62 else {
            throw BSRoformerError.invalidConfiguration("maskEstimatorDepthは2である必要があります")
        }
        guard frequenciesPerBand.reduce(0, +) == frequencyBinCount else {
            throw BSRoformerError.invalidConfiguration(
                "周波数帯域の合計が\(frequencyBinCount)ではありません"
            )
        }
        guard stftFFTSize == 2_048,
              stftHopLength == 512,
              stftWindowLength == stftFFTSize,
              !stftNormalized else {
            throw BSRoformerError.invalidConfiguration("未対応のSTFT構成です")
        }
        guard inferenceFrameCount == 801,
              shortAudioThresholdSeconds == 10,
              shortAudioInferenceFrameCount == 256,
              overlapSeconds == 8,
              stepSampleCount(for: chunkSampleCount) > 0 else {
            throw BSRoformerError.invalidConfiguration("チャンク設定が不正です")
        }
    }
}
