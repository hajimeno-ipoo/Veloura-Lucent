import Foundation
#if canImport(Metal)
import Metal
#endif

/// Accelerates only the two FIR sums. Coefficients, reflected input and the
/// nonlinear transform are prepared by the existing CPU oversampling path.
struct MetalNonlinearFIRProcessor: Sendable {
    func process(
        samples: [Float], padded: [Float], phases: [Float], kernel: [Float],
        factor: Int, radius: Int, transform: (Float) -> Float
    ) -> [Float]? {
        #if canImport(Metal)
        guard samples.count > 1, factor == 4, radius == 32,
              phases.count == factor * (radius * 2 + 1),
              kernel.count == radius * factor * 2 + 1,
              padded.count == samples.count + radius * 4,
              samples.count < (Int(Int32.max) - radius * factor * 2) / factor,
              let context = Self.cache.context() else { return nil }
        let deltaCount = (samples.count - 1) * factor + 1 + radius * factor * 2
        guard deltaCount * MemoryLayout<Float>.stride <= context.device.maxBufferLength else { return nil }
        func buffer(_ values: [Float]) -> (any MTLBuffer)? {
            values.withUnsafeBytes { bytes in
                guard bytes.count <= context.device.maxBufferLength else { return nil }
                return context.device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            }
        }
        guard let paddedBuffer = buffer(padded), let phaseBuffer = buffer(phases),
              let deltaBuffer = context.device.makeBuffer(length: deltaCount * MemoryLayout<Float>.stride, options: .storageModeShared),
              let interpolation = context.queue.makeCommandBuffer(),
              let interpolationEncoder = interpolation.makeComputeCommandEncoder() else { return nil }
        interpolationEncoder.setComputePipelineState(context.interpolate)
        interpolationEncoder.setBuffer(paddedBuffer, offset: 0, index: 0)
        interpolationEncoder.setBuffer(phaseBuffer, offset: 0, index: 1)
        interpolationEncoder.setBuffer(deltaBuffer, offset: 0, index: 2)
        var count = UInt32(deltaCount)
        interpolationEncoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 3)
        interpolationEncoder.dispatchThreads(
            MTLSize(width: deltaCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(256, context.interpolate.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        )
        interpolationEncoder.endEncoding()
        interpolation.commit()
        interpolation.waitUntilCompleted()
        guard interpolation.status == .completed else { return nil }

        // Keep tanhf and its subtraction on the CPU, with the original rounding.
        let delta = deltaBuffer.contents().assumingMemoryBound(to: Float.self)
        for index in 0..<deltaCount {
            let interpolated = delta[index]
            delta[index] = transform(interpolated) - interpolated
        }
        guard let sampleBuffer = buffer(samples), let kernelBuffer = buffer(kernel),
              let outputBuffer = context.device.makeBuffer(length: samples.count * MemoryLayout<Float>.stride, options: .storageModeShared),
              let reconstruction = context.queue.makeCommandBuffer(),
              let reconstructionEncoder = reconstruction.makeComputeCommandEncoder() else { return nil }
        reconstructionEncoder.setComputePipelineState(context.reconstruct)
        for (index, buffer) in [sampleBuffer, deltaBuffer, kernelBuffer, outputBuffer].enumerated() {
            reconstructionEncoder.setBuffer(buffer, offset: 0, index: index)
        }
        count = UInt32(samples.count)
        reconstructionEncoder.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 4)
        reconstructionEncoder.dispatchThreads(
            MTLSize(width: samples.count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(256, context.reconstruct.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        )
        reconstructionEncoder.endEncoding()
        reconstruction.commit()
        reconstruction.waitUntilCompleted()
        guard reconstruction.status == .completed else { return nil }
        return Array(UnsafeBufferPointer(
            start: outputBuffer.contents().assumingMemoryBound(to: Float.self), count: samples.count
        ))
        #else
        return nil
        #endif
    }
}

#if canImport(Metal)
private extension MetalNonlinearFIRProcessor {
    static let cache = MetalNonlinearFIRCache()
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;
    #pragma clang fp contract(off)

    kernel void interpolateFIR(device const float *padded [[buffer(0)]],
        device const float *phases [[buffer(1)]], device float *interpolated [[buffer(2)]],
        constant uint &count [[buffer(3)]], uint index [[thread_position_in_grid]]) {
        if (index >= count) return;
        int position = int(index) - 128;
        int phase = ((position % 4) + 4) % 4;
        int base = (position - phase) / 4 + 64 - 32;
        float value = 0.0f;
        for (int tap = 0; tap < 65; ++tap) {
            value += padded[base + tap] * phases[phase * 65 + tap];
        }
        interpolated[index] = value;
    }

    kernel void reconstructFIR(device const float *samples [[buffer(0)]],
        device const float *delta [[buffer(1)]], device const float *coefficients [[buffer(2)]],
        device float *output [[buffer(3)]], constant uint &count [[buffer(4)]],
        uint index [[thread_position_in_grid]]) {
        if (index >= count) return;
        float filteredDelta = 0.0f;
        for (uint tap = 0; tap < 257; ++tap) {
            filteredDelta += delta[index * 4 + tap] * coefficients[tap];
        }
        output[index] = samples[index] + filteredDelta;
    }
    """#
}

private final class MetalNonlinearFIRCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: MetalNonlinearFIRContext?

    func context() -> MetalNonlinearFIRContext? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let options = MTLCompileOptions()
        options.mathMode = .safe
        options.mathFloatingPointFunctions = .precise
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: MetalNonlinearFIRProcessor.source, options: options),
              let interpolateFunction = library.makeFunction(name: "interpolateFIR"),
              let reconstructFunction = library.makeFunction(name: "reconstructFIR"),
              let interpolate = try? device.makeComputePipelineState(function: interpolateFunction),
              let reconstruct = try? device.makeComputePipelineState(function: reconstructFunction) else { return nil }
        let context = MetalNonlinearFIRContext(device: device, queue: queue, interpolate: interpolate, reconstruct: reconstruct)
        cached = context
        return context
    }
}

private struct MetalNonlinearFIRContext {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let interpolate: any MTLComputePipelineState
    let reconstruct: any MTLComputePipelineState
}
#endif
