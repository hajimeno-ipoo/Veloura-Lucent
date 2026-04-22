import Foundation

#if canImport(Metal)
import Metal
#endif

struct MetalAudioAnalysisProcessor: Sendable {
    var isAvailable: Bool {
        #if canImport(Metal)
        Self.cache.context() != nil
        #else
        false
        #endif
    }

    func separatedMeanSpectra(spectrogram: Spectrogram) -> AudioSeparatedMeanSpectra? {
        guard let magnitudes = makeMagnitudes(spectrogram: spectrogram) else {
            return nil
        }
        return separatedMeanSpectra(
            magnitudes: magnitudes,
            frameCount: spectrogram.frameCount,
            binCount: spectrogram.binCount
        )
    }
}

extension MetalAudioAnalysisProcessor {
    private func separatedMeanSpectra(magnitudes: [Float], frameCount: Int, binCount: Int) -> AudioSeparatedMeanSpectra {
        guard frameCount > 0, binCount > 0 else {
            return AudioSeparatedMeanSpectra(harmonic: [], percussive: [])
        }

        let temporalMedian = makeTemporalMedian17(magnitudes: magnitudes, frameCount: frameCount, binCount: binCount)

        var harmonicSpectrum = Array(repeating: Float.zero, count: binCount)
        var percussiveSpectrum = Array(repeating: Float.zero, count: binCount)
        var frameMagnitudes = Array(repeating: Float.zero, count: binCount)

        for frameIndex in 0..<frameCount {
            let frameStart = frameIndex * binCount
            frameMagnitudes[0..<binCount] = magnitudes[frameStart..<(frameStart + binCount)]
            let spectralMedian = SpectralDSP.medianFilter(frameMagnitudes, windowSize: 9)
            for binIndex in 0..<binCount {
                let harmonicWeight = temporalMedian[frameStart + binIndex]
                let percussiveWeight = spectralMedian[binIndex]
                let total = max(harmonicWeight + percussiveWeight, 1e-6)
                let magnitude = frameMagnitudes[binIndex]
                harmonicSpectrum[binIndex] += magnitude * harmonicWeight / total
                percussiveSpectrum[binIndex] += magnitude * percussiveWeight / total
            }
        }

        let scale = 1 / Float(max(frameCount, 1))
        for binIndex in 0..<binCount {
            harmonicSpectrum[binIndex] *= scale
            percussiveSpectrum[binIndex] *= scale
        }
        return AudioSeparatedMeanSpectra(harmonic: harmonicSpectrum, percussive: percussiveSpectrum)
    }

    func makeTemporalMedian17(magnitudes: [Float], frameCount: Int, binCount: Int) -> [Float] {
        guard frameCount > 0, binCount > 0 else { return [] }

        var temporalMedian = Array(repeating: Float.zero, count: frameCount * binCount)
        var history = Array(repeating: Float.zero, count: frameCount)

        for binIndex in 0..<binCount {
            for frameIndex in 0..<frameCount {
                history[frameIndex] = magnitudes[frameIndex * binCount + binIndex]
            }
            let filtered = SpectralDSP.medianFilter(history, windowSize: 17)
            for frameIndex in 0..<frameCount {
                temporalMedian[frameIndex * binCount + binIndex] = filtered[frameIndex]
            }
        }

        return temporalMedian
    }

    private func makeMagnitudes(spectrogram: Spectrogram) -> [Float]? {
        #if canImport(Metal)
        let valueCount = spectrogram.frameCount * spectrogram.binCount
        guard valueCount > 0,
              let context = Self.cache.context(),
              let realBuffer = context.device.makeBuffer(bytes: spectrogram.real, length: valueCount * MemoryLayout<Float>.stride),
              let imagBuffer = context.device.makeBuffer(bytes: spectrogram.imag, length: valueCount * MemoryLayout<Float>.stride),
              let outputBuffer = context.device.makeBuffer(length: valueCount * MemoryLayout<Float>.stride),
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        encoder.setComputePipelineState(context.pipeline)
        encoder.setBuffer(realBuffer, offset: 0, index: 0)
        encoder.setBuffer(imagBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBytes([UInt32(valueCount)], length: MemoryLayout<UInt32>.stride, index: 3)

        let threadCount = min(context.pipeline.maxTotalThreadsPerThreadgroup, max(context.pipeline.threadExecutionWidth, 1))
        let threadsPerGroup = MTLSize(width: threadCount, height: 1, depth: 1)
        let grid = MTLSize(width: valueCount, height: 1, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed else {
            return nil
        }

        let outputPointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: valueCount)
        return Array(UnsafeBufferPointer(start: outputPointer, count: valueCount))
        #else
        return nil
        #endif
    }

    static var metalSource: String {
        """
        #include <metal_stdlib>
        using namespace metal;

        kernel void computeMagnitudes(
            device const float *realValues [[buffer(0)]],
            device const float *imagValues [[buffer(1)]],
            device float *magnitudes [[buffer(2)]],
            constant uint &valueCount [[buffer(3)]],
            uint index [[thread_position_in_grid]]
        ) {
            if (index >= valueCount) {
                return;
            }
            float realValue = realValues[index];
            float imagValue = imagValues[index];
            magnitudes[index] = sqrt(realValue * realValue + imagValue * imagValue);
        }
        """
    }
}

#if canImport(Metal)
private extension MetalAudioAnalysisProcessor {
    static let cache = MetalAudioAnalysisCache()
}

private final class MetalAudioAnalysisCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedContext: MetalAudioAnalysisContext?

    func context() -> MetalAudioAnalysisContext? {
        lock.lock()
        defer { lock.unlock() }

        if let cachedContext {
            return cachedContext
        }

        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: MetalAudioAnalysisProcessor.metalSource, options: nil),
              let function = library.makeFunction(name: "computeMagnitudes"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return nil
        }

        let context = MetalAudioAnalysisContext(
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline
        )
        cachedContext = context
        return context
    }
}

private final class MetalAudioAnalysisContext {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    let pipeline: any MTLComputePipelineState

    init(
        device: any MTLDevice,
        commandQueue: any MTLCommandQueue,
        pipeline: any MTLComputePipelineState
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.pipeline = pipeline
    }
}
#endif
