import Foundation
import MLX
import Testing
@testable import BSRoformerMLX
@testable import VelouraLucent

@Suite(.serialized)
struct BSRoformerSpectralTests {
    @Test
    func metalOverlapAddPreservesCPUFrameOrderAndBoundaryNormalization() throws {
        let temporaryBundle = try installMetalBundle()
        defer { if let temporaryBundle { try? FileManager.default.removeItem(at: temporaryBundle) } }
        // Requiring a GPU result prevents CPU fallback from making this test pass.
        let metal = try #require(BSRoformerMetalOverlapAdd.shared)
        for length in [1_025, 1_535, 2_048, 4_095, 130_560, 409_600] {
            let transform = BSRoformerSpectralTransform(fftSize: 2_048, hopLength: 512)
            let frameCount = 1 + length / 512
            let outer = 12 // Six stereo stems.
            let frames = (0..<(outer * frameCount * 2_048)).map { index in
                Float(sin(Double(index) * 0.017) * 0.13 + cos(Double(index) * 0.003) * 0.07)
            }
            let gpu = try #require(metal.reconstruct(
                frames: frames, windowSquared: transform.windowSquared,
                fftSize: 2_048, hopLength: 512, frameCount: frameCount,
                outer: outer, length: length, trimStart: 1_024
            ))
            let cpu = transform.overlapAddCPU(frames, frameCount: frameCount, outer: outer, length: length)
            expectExact(gpu, cpu)
            #expect(gpu.allSatisfy { $0.isFinite })
        }

        // No center trim exposes the zero and near-zero Hann weights at the ends.
        let transform = BSRoformerSpectralTransform(fftSize: 2_048, hopLength: 512, center: false)
        let frameCount = 5
        let length = 4_096
        for impulse in [false, true] {
            var frames = [Float](repeating: 0, count: 2 * frameCount * 2_048)
            if impulse {
                for frame in 0..<(2 * frameCount) {
                    frames[frame * 2_048] = 1
                    frames[frame * 2_048 + 1] = -0.5
                    frames[frame * 2_048 + 2_047] = 0.75
                }
            }
            let gpu = try #require(metal.reconstruct(
                frames: frames, windowSquared: transform.windowSquared,
                fftSize: 2_048, hopLength: 512, frameCount: frameCount,
                outer: 2, length: length, trimStart: 0
            ))
            let cpu = transform.overlapAddCPU(frames, frameCount: frameCount, outer: 2, length: length)
            expectExact(gpu, cpu)
            #expect(gpu.allSatisfy { $0.isFinite })
        }
    }

    @Test
    func integratedISTFTMatchesCPUWithComplexMaskedSixStemSpectrum() throws {
        let temporaryBundle = try installMetalBundle()
        defer { if let temporaryBundle { try? FileManager.default.removeItem(at: temporaryBundle) } }
        let metal = try #require(BSRoformerMetalOverlapAdd.shared)
        let transform = BSRoformerSpectralTransform(fftSize: 2_048, hopLength: 512)
        let length = 8_193
        let samples = (0..<(2 * length)).map { index in
            Float(sin(Double(index) * 0.031) * 0.15 + cos(Double(index) * 0.007) * 0.08)
        }
        let source = transform.stft(MLXArray(samples, [1, 2, length]))
        let real = stacked((1...6).map { stem in
            source.real * Float(stem) * 0.1 - source.imaginary * 0.13
        }, axis: 1)
        let imaginary = stacked((1...6).map { stem in
            source.imaginary * Float(stem) * 0.1 + source.real * 0.13
        }, axis: 1)
        let spectrum = BSRoformerComplexSpectrogram(real: real, imaginary: imaginary)
        let frameCount = real.dim(4)
        let frequencyBins = real.dim(3)
        let fftReal = real.reshaped([12, frequencyBins, frameCount]).transposed(0, 2, 1)
        let fftImaginary = imaginary.reshaped([12, frequencyBins, frameCount]).transposed(0, 2, 1)
        let timeFrames = MLXFFT.irfft(fftReal + fftImaginary.asImaginary(), n: 2_048) * transform.windowArray
        eval(timeFrames)
        let frames = timeFrames.asArray(Float.self)
        let cpu = transform.overlapAddCPU(frames, frameCount: frameCount, outer: 12, length: length)
        let directGPU = try #require(metal.reconstruct(
            frames: frames, windowSquared: transform.windowSquared,
            fftSize: 2_048, hopLength: 512, frameCount: frameCount,
            outer: 12, length: length, trimStart: 1_024
        ))
        expectExact(directGPU, cpu)
        let actual = transform.istft(spectrum, length: length)
        eval(actual)
        #expect(actual.shape == [1, 6, 2, length])
        expectExact(actual.asArray(Float.self), cpu)
    }
    private func expectExact(_ actual: [Float], _ expected: [Float]) {
        #expect(actual.count == expected.count)
        let bitDifferences = zip(actual, expected).reduce(0) { count, pair in
            count + (pair.0.bitPattern == pair.1.bitPattern ? 0 : 1)
        }
        #expect(bitDifferences == 0, "Compared \(expected.count) output samples")
    }

    // Match the existing production-inference test's SwiftPM resource layout.
    private func installMetalBundle() throws -> URL? {
        let resources = try #require(AppResourceBundle.resourceURL)
        let source = resources.appending(path: "StemModels/MLX/mlx.metallib")
        let bundle = resources.appending(path: "mlx-swift_Cmlx.bundle", directoryHint: .isDirectory)
        let directory = bundle.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let destination = directory.appending(path: "default.metallib")
        if FileManager.default.fileExists(atPath: destination.path) { return nil }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: source, to: destination)
        return bundle
    }

}
