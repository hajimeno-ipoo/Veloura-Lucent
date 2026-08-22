import Foundation
import MLX

struct BSRoformerComplexSpectrogram {
    let real: MLXArray
    let imaginary: MLXArray
}

final class BSRoformerSpectralTransform {
    let fftSize: Int
    let hopLength: Int
    let center: Bool
    let window: [Float]
    let windowArray: MLXArray

    init(fftSize: Int, hopLength: Int, center: Bool = true) {
        self.fftSize = fftSize
        self.hopLength = hopLength
        self.center = center
        self.window = (0..<fftSize).map { index in
            0.5 * (1 - cos(2 * Float.pi * Float(index) / Float(fftSize)))
        }
        self.windowArray = MLXArray(window)
    }

    func stft(_ audio: MLXArray) -> BSRoformerComplexSpectrogram {
        precondition(audio.ndim == 3)
        let batch = audio.dim(0)
        let channels = audio.dim(1)
        let padded = center ? reflectPad(audio, amount: fftSize / 2) : audio
        let paddedSamples = padded.dim(2)
        let frameCount = 1 + (paddedSamples - fftSize) / hopLength
        let flattened = padded.reshaped([batch * channels, paddedSamples])
        let frames = asStrided(
            flattened,
            [batch * channels, frameCount, fftSize],
            strides: [paddedSamples, hopLength, 1]
        )
        let spectrum = MLXFFT.rfft(frames * windowArray)
        let frequencyBins = fftSize / 2 + 1
        let real = spectrum.realPart()
            .reshaped([batch, channels, frameCount, frequencyBins])
            .transposed(0, 1, 3, 2)
        let imaginary = spectrum.imaginaryPart()
            .reshaped([batch, channels, frameCount, frequencyBins])
            .transposed(0, 1, 3, 2)
        return BSRoformerComplexSpectrogram(real: real, imaginary: imaginary)
    }

    func istft(_ spectrum: BSRoformerComplexSpectrogram, length: Int) -> MLXArray {
        precondition(spectrum.real.shape == spectrum.imaginary.shape)
        precondition(spectrum.real.ndim == 5)

        let batch = spectrum.real.dim(0)
        let stems = spectrum.real.dim(1)
        let channels = spectrum.real.dim(2)
        let frequencyBins = spectrum.real.dim(3)
        let frameCount = spectrum.real.dim(4)
        let outer = batch * stems * channels

        let real = spectrum.real
            .reshaped([outer, frequencyBins, frameCount])
            .transposed(0, 2, 1)
        let imaginary = spectrum.imaginary
            .reshaped([outer, frequencyBins, frameCount])
            .transposed(0, 2, 1)
        let timeFrames = MLXFFT.irfft(real + imaginary.asImaginary(), n: fftSize) * windowArray
        eval(timeFrames)

        let materialized = timeFrames.asArray(Float.self)
        let paddedLength = (frameCount - 1) * hopLength + fftSize
        var overlapAdded = [Float](repeating: 0, count: outer * paddedLength)
        var denominator = [Float](repeating: 0, count: paddedLength)

        for frame in 0..<frameCount {
            let outputOffset = frame * hopLength
            let frameOffset = frame * fftSize
            for sample in 0..<fftSize {
                let windowValue = window[sample]
                denominator[outputOffset + sample] += windowValue * windowValue
                for item in 0..<outer {
                    let sourceIndex = item * frameCount * fftSize + frameOffset + sample
                    let destinationIndex = item * paddedLength + outputOffset + sample
                    overlapAdded[destinationIndex] += materialized[sourceIndex]
                }
            }
        }

        let trimStart = center ? fftSize / 2 : 0
        var output = [Float](repeating: 0, count: outer * length)
        for item in 0..<outer {
            let sourceBase = item * paddedLength
            let destinationBase = item * length
            for sample in 0..<length {
                let sourceIndex = trimStart + sample
                let weight = denominator[sourceIndex]
                if weight > 1e-11 {
                    output[destinationBase + sample] = overlapAdded[sourceBase + sourceIndex] / weight
                }
            }
        }
        return MLXArray(output, [batch, stems, channels, length])
    }

    private func reflectPad(_ audio: MLXArray, amount: Int) -> MLXArray {
        guard amount > 0 else { return audio }
        let length = audio.dim(2)
        precondition(length > amount)
        var indices = [Int32]()
        indices.reserveCapacity(length + 2 * amount)
        for index in stride(from: amount, through: 1, by: -1) {
            indices.append(Int32(index))
        }
        for index in 0..<length {
            indices.append(Int32(index))
        }
        for index in 0..<amount {
            indices.append(Int32(length - 2 - index))
        }
        return audio.take(MLXArray(indices), axis: 2)
    }
}
