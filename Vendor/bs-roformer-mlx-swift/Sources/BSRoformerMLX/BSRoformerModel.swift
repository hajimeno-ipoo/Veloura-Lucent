import Foundation
import MLX

public final class BSRoformerModel {
    public let configuration: BSRoformerConfiguration
    private let weights: [String: MLXArray]
    private let spectral: BSRoformerSpectralTransform
    private let bandDimensions: [Int]

    public init(weightsURL: URL, configuration: BSRoformerConfiguration) throws {
        try configuration.validate()
        let required = Self.requiredWeightKeys(configuration: configuration)
        let weights = try Self.normalizedWeights(
            try MLX.loadArrays(url: weightsURL),
            required: required
        )
        let missing = required.subtracting(weights.keys)
        guard missing.isEmpty else {
            throw BSRoformerError.invalidWeights(
                "必要な重みが不足しています: \(missing.sorted().prefix(5).joined(separator: ", "))"
            )
        }
        guard weights.count == required.count else {
            throw BSRoformerError.invalidWeights(
                "重み数が一致しません（期待\(required.count)、実際\(weights.count)）"
            )
        }
        self.configuration = configuration
        self.weights = weights
        self.spectral = BSRoformerSpectralTransform(
            fftSize: configuration.stftFFTSize,
            hopLength: configuration.stftHopLength
        )
        self.bandDimensions = configuration.frequenciesPerBand.map {
            2 * $0 * configuration.channels
        }
    }

    public func callAsFunction(_ rawAudio: MLXArray) throws -> MLXArray {
        guard rawAudio.ndim == 3,
              rawAudio.dim(1) == configuration.channels else {
            throw BSRoformerError.invalidAudio("入力は[batch, 2, samples]である必要があります")
        }
        guard rawAudio.dim(2) > configuration.stftFFTSize / 2 else {
            throw BSRoformerError.invalidAudio("入力音声がSTFTの反射パディングより短すぎます")
        }

        let batch = rawAudio.dim(0)
        let samples = rawAudio.dim(2)
        let stft = spectral.stft(rawAudio)
        let frequencyBins = configuration.frequencyBinCount
        let frameCount = stft.real.dim(3)
        let realFrequencyChannel = stft.real.transposed(0, 2, 1, 3)
            .reshaped([batch, frequencyBins * configuration.channels, frameCount])
        let imaginaryFrequencyChannel = stft.imaginary.transposed(0, 2, 1, 3)
            .reshaped([batch, frequencyBins * configuration.channels, frameCount])
        let representation = stacked(
            [realFrequencyChannel, imaginaryFrequencyChannel],
            axis: -1
        )

        let masks = forwardMasks(representation)
        let sourceReal = realFrequencyChannel.expandedDimensions(axis: 1)
        let sourceImaginary = imaginaryFrequencyChannel.expandedDimensions(axis: 1)
        let maskReal = masks[0..., 0..., 0..., 0..., 0]
        let maskImaginary = masks[0..., 0..., 0..., 0..., 1]
        let maskedReal = sourceReal * maskReal - sourceImaginary * maskImaginary
        let maskedImaginary = sourceReal * maskImaginary + sourceImaginary * maskReal

        let stems = configuration.stemCount
        let channels = configuration.channels
        let separatedReal = maskedReal
            .reshaped([batch, stems, frequencyBins, channels, frameCount])
            .transposed(0, 1, 3, 2, 4)
        let separatedImaginary = maskedImaginary
            .reshaped([batch, stems, frequencyBins, channels, frameCount])
            .transposed(0, 1, 3, 2, 4)
        return spectral.istft(
            BSRoformerComplexSpectrogram(
                real: separatedReal,
                imaginary: separatedImaginary
            ),
            length: samples
        )
    }

    private func forwardMasks(_ representation: MLXArray) -> MLXArray {
        let batch = representation.dim(0)
        let frameCount = representation.dim(2)
        var features = representation.transposed(0, 2, 1, 3)
            .reshaped([batch, frameCount, -1])
        features = bandSplit(features)

        for block in 0..<configuration.depth {
            features = applyTransformer(
                features.transposed(0, 2, 1, 3)
                    .reshaped([batch * bandDimensions.count, frameCount, configuration.dimension]),
                prefix: "layers_\(block).time_transformer.layers_0"
            )
            features = features
                .reshaped([batch, bandDimensions.count, frameCount, configuration.dimension])
                .transposed(0, 2, 1, 3)
            features = applyTransformer(
                features.reshaped([
                    batch * frameCount,
                    bandDimensions.count,
                    configuration.dimension,
                ]),
                prefix: "layers_\(block).freq_transformer.layers_0"
            )
            features = features.reshaped([
                batch,
                frameCount,
                bandDimensions.count,
                configuration.dimension,
            ])
            eval(features)
        }

        features = l2Normalize(features, weight: weight("final_norm.weight"))
        var stemMasks = [MLXArray]()
        stemMasks.reserveCapacity(configuration.stemCount)
        for stem in 0..<configuration.stemCount {
            var bandMasks = [MLXArray]()
            bandMasks.reserveCapacity(bandDimensions.count)
            for band in 0..<bandDimensions.count {
                let prefix = "mask_estimators_\(stem).to_freqs_\(band).layers"
                let bandFeatures = features[0..., 0..., band, 0...]
                var output = linear(
                    bandFeatures,
                    weight: weight("\(prefix).0.weight"),
                    bias: weight("\(prefix).0.bias")
                )
                output = tanh(output)
                output = linear(
                    output,
                    weight: weight("\(prefix).2.weight"),
                    bias: weight("\(prefix).2.bias")
                )
                let halves = split(output, parts: 2, axis: -1)
                bandMasks.append(halves[0] * sigmoid(halves[1]))
            }
            stemMasks.append(concatenated(bandMasks, axis: -1))
        }

        let frequencyChannels = configuration.frequencyBinCount * configuration.channels
        return stacked(stemMasks, axis: 1)
            .reshaped([batch, configuration.stemCount, frameCount, frequencyChannels, 2])
            .transposed(0, 1, 3, 2, 4)
    }

    private func bandSplit(_ input: MLXArray) -> MLXArray {
        var outputs = [MLXArray]()
        outputs.reserveCapacity(bandDimensions.count)
        var start = 0
        for (band, dimension) in bandDimensions.enumerated() {
            let slice = input[0..., 0..., start..<(start + dimension)]
            let normalized = l2Normalize(
                slice,
                weight: weight("band_split.to_features_\(band).norm.weight")
            )
            outputs.append(linear(
                normalized,
                weight: weight("band_split.to_features_\(band).linear.weight"),
                bias: weight("band_split.to_features_\(band).linear.bias")
            ))
            start += dimension
        }
        return stacked(outputs, axis: -2)
    }

    private func applyTransformer(_ input: MLXArray, prefix: String) -> MLXArray {
        let attentionPrefix = "\(prefix).attn"
        let normalized = l2Normalize(input, weight: weight("\(attentionPrefix).norm.weight"))
        let qkv = linear(
            normalized,
            weight: weight("\(attentionPrefix).to_qkv.weight"),
            bias: nil
        )
        let batch = qkv.dim(0)
        let sequence = qkv.dim(1)
        let heads = configuration.headCount
        let headDimension = configuration.headDimension
        let arranged = qkv
            .reshaped([batch, sequence, 3, heads, headDimension])
            .transposed(2, 0, 3, 1, 4)
        var query = arranged[0]
        var key = arranged[1]
        let value = arranged[2]
        query = MLXFast.RoPE(
            query,
            dimensions: headDimension,
            traditional: true,
            base: 10_000,
            scale: 1,
            offset: 0
        )
        key = MLXFast.RoPE(
            key,
            dimensions: headDimension,
            traditional: true,
            base: 10_000,
            scale: 1,
            offset: 0
        )
        var scores = matmul(query, key.transposed(0, 1, 3, 2))
            * Float(1 / sqrt(Double(headDimension)))
        scores = scores - scores.max(axis: -1, keepDims: true)
        var attention = matmul(softmax(scores, axis: -1), value)
        let gates = sigmoid(linear(
            normalized,
            weight: weight("\(attentionPrefix).to_gates.weight"),
            bias: weight("\(attentionPrefix).to_gates.bias")
        )).transposed(0, 2, 1).expandedDimensions(axis: -1)
        attention = attention * gates
        let merged = attention.transposed(0, 2, 1, 3)
            .reshaped([batch, sequence, heads * headDimension])
        let projected = linear(
            merged,
            weight: weight("\(attentionPrefix).to_out.layers.0.weight"),
            bias: nil
        )
        var output = input + projected

        let feedForwardPrefix = "\(prefix).ff.net.layers"
        var feedForward = l2Normalize(
            output,
            weight: weight("\(feedForwardPrefix).0.weight")
        )
        feedForward = linear(
            feedForward,
            weight: weight("\(feedForwardPrefix).1.weight"),
            bias: weight("\(feedForwardPrefix).1.bias")
        )
        feedForward = 0.5 * feedForward
            * (1 + erf(feedForward / Float(sqrt(2.0))))
        feedForward = linear(
            feedForward,
            weight: weight("\(feedForwardPrefix).4.weight"),
            bias: weight("\(feedForwardPrefix).4.bias")
        )
        output = output + feedForward
        return output
    }

    private func l2Normalize(_ input: MLXArray, weight: MLXArray) -> MLXArray {
        let norm = sqrt((input * input).sum(axis: -1, keepDims: true))
        let denominator = maximum(norm, MLXArray(Float(1e-12)))
        return input / denominator * Float(sqrt(Double(input.dim(-1)))) * weight
    }

    private func linear(_ input: MLXArray, weight: MLXArray, bias: MLXArray?) -> MLXArray {
        let output = matmul(input, weight.transposed())
        return bias.map { output + $0 } ?? output
    }

    private func weight(_ key: String) -> MLXArray {
        weights[key]!
    }

    static func requiredWeightKeys(configuration: BSRoformerConfiguration) -> Set<String> {
        var keys: Set<String> = ["final_norm.weight"]
        for band in configuration.frequenciesPerBand.indices {
            let prefix = "band_split.to_features_\(band)"
            keys.insert("\(prefix).norm.weight")
            keys.insert("\(prefix).linear.weight")
            keys.insert("\(prefix).linear.bias")
        }
        for block in 0..<configuration.depth {
            for direction in ["time_transformer", "freq_transformer"] {
                let prefix = "layers_\(block).\(direction).layers_0"
                keys.formUnion([
                    "\(prefix).attn.norm.weight",
                    "\(prefix).attn.to_qkv.weight",
                    "\(prefix).attn.to_gates.weight",
                    "\(prefix).attn.to_gates.bias",
                    "\(prefix).attn.to_out.layers.0.weight",
                    "\(prefix).ff.net.layers.0.weight",
                    "\(prefix).ff.net.layers.1.weight",
                    "\(prefix).ff.net.layers.1.bias",
                    "\(prefix).ff.net.layers.4.weight",
                    "\(prefix).ff.net.layers.4.bias",
                ])
            }
        }
        for stem in 0..<configuration.stemCount {
            for band in configuration.frequenciesPerBand.indices {
                let prefix = "mask_estimators_\(stem).to_freqs_\(band).layers"
                keys.formUnion([
                    "\(prefix).0.weight",
                    "\(prefix).0.bias",
                    "\(prefix).2.weight",
                    "\(prefix).2.bias",
                ])
            }
        }
        return keys
    }

    private static func normalizedWeights(
        _ loaded: [String: MLXArray],
        required: Set<String>
    ) throws -> [String: MLXArray] {
        if Set(loaded.keys) == required {
            return loaded
        }

        var normalized: [String: MLXArray] = [:]
        normalized.reserveCapacity(loaded.count)
        for (key, value) in loaded {
            guard let normalizedKey = normalizedPublishedWeightKey(key) else {
                throw BSRoformerError.invalidWeights("未対応の公開重み名です: \(key)")
            }
            guard normalized.updateValue(value, forKey: normalizedKey) == nil else {
                throw BSRoformerError.invalidWeights("公開重み名の変換先が重複しています: \(normalizedKey)")
            }
        }
        return normalized
    }

    static func normalizedPublishedWeightKey(_ key: String) -> String? {
        if key == "final_norm.gamma" {
            return "final_norm.weight"
        }

        let parts = key.split(separator: ".").map(String.init)
        if parts.count == 5,
           parts[0] == "band_split",
           parts[1] == "to_features",
           Int(parts[2]) != nil {
            let prefix = "band_split.to_features_\(parts[2])"
            if parts[3] == "0", parts[4] == "gamma" {
                return "\(prefix).norm.weight"
            }
            if parts[3] == "1", parts[4] == "weight" || parts[4] == "bias" {
                return "\(prefix).linear.\(parts[4])"
            }
        }

        if parts.count >= 8,
           parts[0] == "layers",
           Int(parts[1]) != nil,
           parts[2] == "0" || parts[2] == "1",
           parts[3] == "layers",
           parts[4] == "0" {
            let direction = parts[2] == "0" ? "time_transformer" : "freq_transformer"
            let prefix = "layers_\(parts[1]).\(direction).layers_0"
            if parts[5] == "0" {
                if parts.count == 8, parts[6] == "norm", parts[7] == "gamma" {
                    return "\(prefix).attn.norm.weight"
                }
                if parts.count == 8,
                   ["to_qkv", "to_gates"].contains(parts[6]),
                   parts[7] == "weight" || parts[7] == "bias" {
                    return "\(prefix).attn.\(parts[6]).\(parts[7])"
                }
                if parts.count == 9,
                   parts[6] == "to_out",
                   parts[7] == "0",
                   parts[8] == "weight" {
                    return "\(prefix).attn.to_out.layers.0.weight"
                }
            }
            if parts[5] == "1",
               parts.count == 9,
               parts[6] == "net",
               ["0", "1", "4"].contains(parts[7]) {
                let parameter = parts[8] == "gamma" ? "weight" : parts[8]
                if parameter == "weight" || parameter == "bias" {
                    return "\(prefix).ff.net.layers.\(parts[7]).\(parameter)"
                }
            }
        }

        if parts.count == 7,
           parts[0] == "mask_estimators",
           Int(parts[1]) != nil,
           parts[2] == "to_freqs",
           Int(parts[3]) != nil,
           parts[4] == "0",
           ["0", "2"].contains(parts[5]),
           parts[6] == "weight" || parts[6] == "bias" {
            return "mask_estimators_\(parts[1]).to_freqs_\(parts[3]).layers.\(parts[5]).\(parts[6])"
        }

        return nil
    }
}
