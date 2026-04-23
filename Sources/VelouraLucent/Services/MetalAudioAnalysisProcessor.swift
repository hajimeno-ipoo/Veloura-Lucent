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
        guard let magnitudes = makeMagnitudes(spectrogram: spectrogram),
              let separatedSpectrum = separatedMeanSpectra(
                magnitudes: magnitudes,
                frameCount: spectrogram.frameCount,
                binCount: spectrogram.binCount
              ) else {
            return nil
        }
        return separatedSpectrum
    }

    func masteringSpectralSummary(spectrogram: Spectrogram, sampleRate: Double) -> MasteringSpectralSummary? {
        #if canImport(Metal)
        guard spectrogram.frameCount > 0 else {
            return MasteringSpectralSummary(lowBandLevelDB: -120, midBandLevelDB: -120, highBandLevelDB: -120, harshnessScore: 0)
        }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let lowRange = metalBinRange(20...180, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let midRange = metalBinRange(180...5_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let highRange = metalBinRange(5_000...20_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let harshUpperMidRange = metalBinRange(3_000...8_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let harshAirRange = metalBinRange(12_000...(sampleRate * 0.5), frequencyStep: frequencyStep, binCount: spectrogram.binCount)

        guard let magnitudes = makeMagnitudes(spectrogram: spectrogram) else {
            return nil
        }

        var lowEnergy: Float = 0
        var midEnergy: Float = 0
        var highEnergy: Float = 0
        var lowCount = 0
        var midCount = 0
        var highCount = 0
        for frameIndex in 0..<spectrogram.frameCount {
            let frameStart = frameIndex * spectrogram.binCount
            for binIndex in 0..<spectrogram.binCount {
                let magnitude = magnitudes[frameStart + binIndex]
                let energy = magnitude * magnitude

                if lowRange.contains(UInt32(binIndex)) {
                    lowEnergy += energy
                    lowCount += 1
                }
                if midRange.contains(UInt32(binIndex)) {
                    midEnergy += energy
                    midCount += 1
                }
                if highRange.contains(UInt32(binIndex)) {
                    highEnergy += energy
                    highCount += 1
                }
            }
        }
        let harshness = cpuHarshnessScore(
            spectrogram: spectrogram,
            harshUpperMidRange: harshUpperMidRange,
            harshAirRange: harshAirRange
        )

        return MasteringSpectralSummary(
            lowBandLevelDB: masteringBandLevelDB(energy: lowEnergy, count: lowCount),
            midBandLevelDB: masteringBandLevelDB(energy: midEnergy, count: midCount),
            highBandLevelDB: masteringBandLevelDB(energy: highEnergy, count: highCount),
            harshnessScore: harshness
        )
        #else
        return nil
        #endif
    }
}

extension MetalAudioAnalysisProcessor {
    private func separatedMeanSpectra(magnitudes: [Float], frameCount: Int, binCount: Int) -> AudioSeparatedMeanSpectra? {
        guard frameCount > 0, binCount > 0 else {
            return AudioSeparatedMeanSpectra(harmonic: [], percussive: [])
        }

        guard let temporalMedian = makeTemporalMedian17(magnitudes: magnitudes, frameCount: frameCount, binCount: binCount) else {
            return nil
        }

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

    func makeTemporalMedian17(magnitudes: [Float], frameCount: Int, binCount: Int) -> [Float]? {
        #if canImport(Metal)
        guard frameCount > 0, binCount > 0 else { return [] }
        let valueCount = frameCount * binCount
        guard magnitudes.count == valueCount,
              let context = Self.cache.context(),
              let magnitudeBuffer = context.device.makeBuffer(bytes: magnitudes, length: valueCount * MemoryLayout<Float>.stride),
              let outputBuffer = context.device.makeBuffer(length: valueCount * MemoryLayout<Float>.stride),
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        var frameCountValue = UInt32(frameCount)
        var binCountValue = UInt32(binCount)
        encoder.setComputePipelineState(context.temporalMedianPipeline)
        encoder.setBuffer(magnitudeBuffer, offset: 0, index: 0)
        encoder.setBuffer(outputBuffer, offset: 0, index: 1)
        encoder.setBytes(&frameCountValue, length: MemoryLayout<UInt32>.stride, index: 2)
        encoder.setBytes(&binCountValue, length: MemoryLayout<UInt32>.stride, index: 3)

        let threadCount = min(context.temporalMedianPipeline.maxTotalThreadsPerThreadgroup, max(context.temporalMedianPipeline.threadExecutionWidth, 1))
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

        encoder.setComputePipelineState(context.magnitudePipeline)
        encoder.setBuffer(realBuffer, offset: 0, index: 0)
        encoder.setBuffer(imagBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBytes([UInt32(valueCount)], length: MemoryLayout<UInt32>.stride, index: 3)

        let threadCount = min(context.magnitudePipeline.maxTotalThreadsPerThreadgroup, max(context.magnitudePipeline.threadExecutionWidth, 1))
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

    private func makeMasteringSpectralFrameSums(
        spectrogram: Spectrogram,
        lowRange: MetalBinRange,
        midRange: MetalBinRange,
        highRange: MetalBinRange,
        harshUpperMidRange: MetalBinRange,
        harshAirRange: MetalBinRange
    ) -> [Float]? {
        #if canImport(Metal)
        let valueCount = spectrogram.frameCount * spectrogram.binCount
        let outputCount = spectrogram.frameCount * 5
        guard valueCount > 0,
              outputCount > 0,
              let context = Self.cache.context(),
              let realBuffer = context.device.makeBuffer(bytes: spectrogram.real, length: valueCount * MemoryLayout<Float>.stride),
              let imagBuffer = context.device.makeBuffer(bytes: spectrogram.imag, length: valueCount * MemoryLayout<Float>.stride),
              let outputBuffer = context.device.makeBuffer(length: outputCount * MemoryLayout<Float>.stride),
              let commandBuffer = context.commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            return nil
        }

        var parameters = MetalSpectralSummaryParameters(
            frameCount: UInt32(spectrogram.frameCount),
            binCount: UInt32(spectrogram.binCount),
            lowLower: lowRange.lower,
            lowUpper: lowRange.upper,
            midLower: midRange.lower,
            midUpper: midRange.upper,
            highLower: highRange.lower,
            highUpper: highRange.upper,
            harshUpperMidLower: harshUpperMidRange.lower,
            harshUpperMidUpper: harshUpperMidRange.upper,
            harshAirLower: harshAirRange.lower,
            harshAirUpper: harshAirRange.upper
        )

        encoder.setComputePipelineState(context.masteringSpectralSummaryPipeline)
        encoder.setBuffer(realBuffer, offset: 0, index: 0)
        encoder.setBuffer(imagBuffer, offset: 0, index: 1)
        encoder.setBuffer(outputBuffer, offset: 0, index: 2)
        encoder.setBytes(&parameters, length: MemoryLayout<MetalSpectralSummaryParameters>.stride, index: 3)

        let threadCount = min(context.masteringSpectralSummaryPipeline.maxTotalThreadsPerThreadgroup, max(context.masteringSpectralSummaryPipeline.threadExecutionWidth, 1))
        let threadsPerGroup = MTLSize(width: threadCount, height: 1, depth: 1)
        let grid = MTLSize(width: spectrogram.frameCount, height: 1, depth: 1)
        encoder.dispatchThreads(grid, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard commandBuffer.status == .completed else {
            return nil
        }

        let outputPointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: outputCount)
        return Array(UnsafeBufferPointer(start: outputPointer, count: outputCount))
        #else
        return nil
        #endif
    }

    private func metalBinRange(_ range: ClosedRange<Double>, frequencyStep: Double, binCount: Int) -> MetalBinRange {
        let lower = max(0, min(Int(range.lowerBound / frequencyStep), binCount - 1))
        let upper = max(lower, min(Int(range.upperBound / frequencyStep), binCount - 1))
        return MetalBinRange(lower: UInt32(lower), upper: UInt32(upper))
    }

    private func masteringBandLevelDB(energy: Float, count: Int) -> Double {
        let rms = sqrt(max(energy / Float(max(count, 1)), 1e-12))
        return 20 * log10(max(Double(rms), 1e-12))
    }

    private func cpuHarshnessScore(
        spectrogram: Spectrogram,
        harshUpperMidRange: MetalBinRange,
        harshAirRange: MetalBinRange
    ) -> Float {
        var harshUpperMid: Float = 0
        var harshAir: Float = 0
        for frameIndex in 0..<spectrogram.frameCount {
            let frameStart = frameIndex * spectrogram.binCount
            var frameHarshUpperMid: Float = 0
            var frameHarshAir: Float = 0
            for binIndex in Int(harshUpperMidRange.lower)...Int(harshUpperMidRange.upper) {
                let storageIndex = frameStart + binIndex
                frameHarshUpperMid += hypotf(spectrogram.real[storageIndex], spectrogram.imag[storageIndex])
            }
            for binIndex in Int(harshAirRange.lower)...Int(harshAirRange.upper) {
                let storageIndex = frameStart + binIndex
                frameHarshAir += hypotf(spectrogram.real[storageIndex], spectrogram.imag[storageIndex])
            }
            harshUpperMid += frameHarshUpperMid
            harshAir += frameHarshAir
        }
        return min(1.0, harshUpperMid / max(harshUpperMid + harshAir, 1e-6))
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
            float realValue = abs(realValues[index]);
            float imagValue = abs(imagValues[index]);
            float larger = max(realValue, imagValue);
            float smaller = min(realValue, imagValue);
            if (larger == 0.0) {
                magnitudes[index] = 0.0;
                return;
            }
            float ratio = smaller / larger;
            magnitudes[index] = larger * precise::sqrt(1.0 + ratio * ratio);
        }

        kernel void computeTemporalMedian17(
            device const float *magnitudes [[buffer(0)]],
            device float *temporalMedian [[buffer(1)]],
            constant uint &frameCount [[buffer(2)]],
            constant uint &binCount [[buffer(3)]],
            uint index [[thread_position_in_grid]]
        ) {
            uint valueCount = frameCount * binCount;
            if (index >= valueCount) {
                return;
            }

            uint frameIndex = index / binCount;
            uint binIndex = index - frameIndex * binCount;
            uint lower = frameIndex > 8 ? frameIndex - 8 : 0;
            uint upper = min(frameCount - 1, frameIndex + 8);
            uint count = upper - lower + 1;

            float window[17];
            for (uint offset = 0; offset < count; offset++) {
                uint sourceFrame = lower + offset;
                window[offset] = magnitudes[sourceFrame * binCount + binIndex];
            }

            for (uint outer = 1; outer < count; outer++) {
                float value = window[outer];
                int inner = int(outer) - 1;
                while (inner >= 0 && window[inner] > value) {
                    window[inner + 1] = window[inner];
                    inner -= 1;
                }
                window[inner + 1] = value;
            }

            temporalMedian[index] = window[(count - 1) / 2];
        }

        struct MasteringSpectralSummaryParameters {
            uint frameCount;
            uint binCount;
            uint lowLower;
            uint lowUpper;
            uint midLower;
            uint midUpper;
            uint highLower;
            uint highUpper;
            uint harshUpperMidLower;
            uint harshUpperMidUpper;
            uint harshAirLower;
            uint harshAirUpper;
        };

        float magnitudeAt(device const float *realValues, device const float *imagValues, uint index) {
            float realValue = abs(realValues[index]);
            float imagValue = abs(imagValues[index]);
            float larger = max(realValue, imagValue);
            float smaller = min(realValue, imagValue);
            if (larger == 0.0) {
                return 0.0;
            }
            float ratio = smaller / larger;
            return larger * precise::sqrt(1.0 + ratio * ratio);
        }

        float bandEnergy(
            device const float *realValues,
            device const float *imagValues,
            uint frameStart,
            uint lower,
            uint upper
        ) {
            float energy = 0.0;
            for (uint binIndex = lower; binIndex <= upper; binIndex++) {
                volatile float magnitude = magnitudeAt(realValues, imagValues, frameStart + binIndex);
                energy += float(magnitude * magnitude);
            }
            return energy;
        }

        float bandMagnitude(
            device const float *realValues,
            device const float *imagValues,
            uint frameStart,
            uint lower,
            uint upper
        ) {
            float sum = 0.0;
            for (uint binIndex = lower; binIndex <= upper; binIndex++) {
                sum += magnitudeAt(realValues, imagValues, frameStart + binIndex);
            }
            return sum;
        }

        kernel void computeMasteringSpectralSummary(
            device const float *realValues [[buffer(0)]],
            device const float *imagValues [[buffer(1)]],
            device float *frameSums [[buffer(2)]],
            constant MasteringSpectralSummaryParameters &params [[buffer(3)]],
            uint frameIndex [[thread_position_in_grid]]
        ) {
            if (frameIndex >= params.frameCount) {
                return;
            }

            uint frameStart = frameIndex * params.binCount;
            uint outputStart = frameIndex * 5;
            frameSums[outputStart] = bandEnergy(realValues, imagValues, frameStart, params.lowLower, params.lowUpper);
            frameSums[outputStart + 1] = bandEnergy(realValues, imagValues, frameStart, params.midLower, params.midUpper);
            frameSums[outputStart + 2] = bandEnergy(realValues, imagValues, frameStart, params.highLower, params.highUpper);
            frameSums[outputStart + 3] = bandMagnitude(realValues, imagValues, frameStart, params.harshUpperMidLower, params.harshUpperMidUpper);
            frameSums[outputStart + 4] = bandMagnitude(realValues, imagValues, frameStart, params.harshAirLower, params.harshAirUpper);
        }
        """
    }
}

private struct MetalBinRange {
    let lower: UInt32
    let upper: UInt32

    var count: UInt32 {
        upper - lower + 1
    }

    func contains(_ binIndex: UInt32) -> Bool {
        binIndex >= lower && binIndex <= upper
    }
}

private struct MetalSpectralSummaryParameters {
    let frameCount: UInt32
    let binCount: UInt32
    let lowLower: UInt32
    let lowUpper: UInt32
    let midLower: UInt32
    let midUpper: UInt32
    let highLower: UInt32
    let highUpper: UInt32
    let harshUpperMidLower: UInt32
    let harshUpperMidUpper: UInt32
    let harshAirLower: UInt32
    let harshAirUpper: UInt32
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
              let magnitudeFunction = library.makeFunction(name: "computeMagnitudes"),
              let temporalMedianFunction = library.makeFunction(name: "computeTemporalMedian17"),
              let masteringSpectralSummaryFunction = library.makeFunction(name: "computeMasteringSpectralSummary"),
              let magnitudePipeline = try? device.makeComputePipelineState(function: magnitudeFunction),
              let temporalMedianPipeline = try? device.makeComputePipelineState(function: temporalMedianFunction),
              let masteringSpectralSummaryPipeline = try? device.makeComputePipelineState(function: masteringSpectralSummaryFunction) else {
            return nil
        }

        let context = MetalAudioAnalysisContext(
            device: device,
            commandQueue: commandQueue,
            magnitudePipeline: magnitudePipeline,
            temporalMedianPipeline: temporalMedianPipeline,
            masteringSpectralSummaryPipeline: masteringSpectralSummaryPipeline
        )
        cachedContext = context
        return context
    }
}

private final class MetalAudioAnalysisContext {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    let magnitudePipeline: any MTLComputePipelineState
    let temporalMedianPipeline: any MTLComputePipelineState
    let masteringSpectralSummaryPipeline: any MTLComputePipelineState

    init(
        device: any MTLDevice,
        commandQueue: any MTLCommandQueue,
        magnitudePipeline: any MTLComputePipelineState,
        temporalMedianPipeline: any MTLComputePipelineState,
        masteringSpectralSummaryPipeline: any MTLComputePipelineState
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.magnitudePipeline = magnitudePipeline
        self.temporalMedianPipeline = temporalMedianPipeline
        self.masteringSpectralSummaryPipeline = masteringSpectralSummaryPipeline
    }
}
#endif
