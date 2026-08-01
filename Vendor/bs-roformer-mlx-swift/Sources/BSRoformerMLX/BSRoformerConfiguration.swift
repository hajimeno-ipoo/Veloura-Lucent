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
        let decoder = JSONDecoder()
        let configuration: Self
        if let native = try? decoder.decode(Self.self, from: data) {
            configuration = native
        } else {
            let published = try decoder.decode(PublishedConfiguration.self, from: data)
            try published.validateRuntimeAssumptions()
            configuration = Self(
                sampleRate: published.sampleRate,
                channels: published.stereo ? 2 : 1,
                stemNames: published.instruments,
                dimension: published.dimension,
                depth: published.depth,
                timeTransformerDepth: published.timeTransformerDepth,
                frequencyTransformerDepth: published.frequencyTransformerDepth,
                linearTransformerDepth: published.linearTransformerDepth,
                frequenciesPerBand: published.frequenciesPerBand,
                headDimension: published.headDimension,
                headCount: published.headCount,
                mlpExpansionFactor: published.mlpExpansionFactor,
                maskEstimatorDepth: published.maskEstimatorDepth,
                stftFFTSize: published.stftFFTSize,
                stftHopLength: published.stftHopLength,
                stftWindowLength: published.stftWindowLength,
                stftNormalized: published.stftNormalized,
                inferenceFrameCount: 801,
                shortAudioThresholdSeconds: 10,
                shortAudioInferenceFrameCount: 256,
                overlapSeconds: 8
            )
        }
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

private struct PublishedConfiguration: Decodable {
    let modelClass: String
    let sampleRate: Int
    let instruments: [String]
    let dimension: Int
    let depth: Int
    let stereo: Bool
    let timeTransformerDepth: Int
    let frequencyTransformerDepth: Int
    let linearTransformerDepth: Int
    let frequenciesPerBand: [Int]
    let headDimension: Int
    let headCount: Int
    let stftFFTSize: Int
    let stftHopLength: Int
    let stftWindowLength: Int
    let stftNormalized: Bool
    let maskEstimatorDepth: Int
    let mlpExpansionFactor: Int
    let skipConnection: Bool
    let zeroDC: Bool
    let ropeTheta: Double

    enum CodingKeys: String, CodingKey {
        case modelClass = "model_class"
        case sampleRate = "sample_rate"
        case instruments
        case dimension = "dim"
        case depth
        case stereo
        case timeTransformerDepth = "time_transformer_depth"
        case frequencyTransformerDepth = "freq_transformer_depth"
        case linearTransformerDepth = "linear_transformer_depth"
        case frequenciesPerBand = "freqs_per_bands"
        case headDimension = "dim_head"
        case headCount = "heads"
        case stftFFTSize = "stft_n_fft"
        case stftHopLength = "stft_hop_length"
        case stftWindowLength = "stft_win_length"
        case stftNormalized = "stft_normalized"
        case maskEstimatorDepth = "mask_estimator_depth"
        case mlpExpansionFactor = "mlp_expansion_factor"
        case skipConnection = "skip_connection"
        case zeroDC = "zero_dc"
        case ropeTheta = "rope_theta"
    }

    func validateRuntimeAssumptions() throws {
        guard modelClass == "BSRoformer",
              !skipConnection,
              zeroDC,
              ropeTheta == 10_000 else {
            throw BSRoformerError.invalidConfiguration(
                "公開設定のmodel_class、skip_connection、zero_dc、rope_thetaが未対応です"
            )
        }
    }
}
