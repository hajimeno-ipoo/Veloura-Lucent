import Foundation
#if canImport(Metal)
import Metal
#endif

/// Only the final mask and complex multiplication run here. Profiles and musical
/// protection tables continue to come from the unmodified CPU analysis.
struct MetalDenoiseMaskProcessor: Sendable {
    // Bin-major magnitudes; twelve CPU-prepared coefficients per bin and three
    // frame coefficients (active, decay, transient lift) per frame.
    func apply(
        real: inout [Float], imag: inout [Float], magnitudes: [Float],
        bins: [Float], frames: [Float], highFloorLifts: [Float],
        highFloorIndices: [Int32], activeHighBinCount: Int,
        frameCount: Int, binCount: Int, shimmerStart: Int, shimmerEnd: Int,
        scalars: [Float]
    ) -> Bool {
        #if canImport(Metal)
        guard frameCount > 0, binCount > 0,
              real.count == frameCount * binCount, imag.count == real.count,
              magnitudes.count == real.count, bins.count == binCount * 12,
              frames.count == frameCount * 3, highFloorIndices.count == binCount,
              highFloorLifts.count == frameCount * activeHighBinCount,
              scalars.count == 7, let context = Self.cache.context() else { return false }
        func buffer<T>(_ values: [T]) -> (any MTLBuffer)? {
            guard !values.isEmpty else {
                return context.device.makeBuffer(length: MemoryLayout<T>.stride, options: .storageModeShared)
            }
            return values.withUnsafeBytes { bytes in
                context.device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
            }
        }
        guard let realBuffer = buffer(real), let imagBuffer = buffer(imag),
              let magnitudeBuffer = buffer(magnitudes), let binBuffer = buffer(bins),
              let frameBuffer = buffer(frames), let highBuffer = buffer(highFloorLifts),
              let highIndexBuffer = buffer(highFloorIndices), let scalarBuffer = buffer(scalars),
              let command = context.queue.makeCommandBuffer(),
              let encoder = command.makeComputeCommandEncoder() else { return false }
        encoder.setComputePipelineState(context.pipeline)
        for (index, value) in [realBuffer, imagBuffer, magnitudeBuffer, binBuffer,
                               frameBuffer, highBuffer, highIndexBuffer, scalarBuffer].enumerated() {
            encoder.setBuffer(value, offset: 0, index: index)
        }
        let dimensions = [UInt32(frameCount), UInt32(binCount), UInt32(shimmerStart),
                          UInt32(shimmerEnd), UInt32(activeHighBinCount)]
        dimensions.withUnsafeBytes { encoder.setBytes($0.baseAddress!, length: $0.count, index: 8) }
        encoder.dispatchThreads(MTLSize(width: real.count, height: 1, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: min(256, context.pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return false }
        real = Array(UnsafeBufferPointer(start: realBuffer.contents().assumingMemoryBound(to: Float.self), count: real.count))
        imag = Array(UnsafeBufferPointer(start: imagBuffer.contents().assumingMemoryBound(to: Float.self), count: imag.count))
        return true
        #else
        return false
        #endif
    }
}

#if canImport(Metal)
private extension MetalDenoiseMaskProcessor {
    static let cache = MetalDenoiseMaskCache()
    static let source = #"""
    #include <metal_stdlib>
    using namespace metal;
    // Preserve CPU rounding at each multiply/add boundary.
    #pragma clang fp contract(off)
    kernel void denoiseMask(device float *real [[buffer(0)]], device float *imag [[buffer(1)]],
        device const float *magnitudes [[buffer(2)]], device const float *bins [[buffer(3)]],
        device const float *frames [[buffer(4)]], device const float *highFloors [[buffer(5)]],
        device const int *highIndices [[buffer(6)]], constant float *s [[buffer(7)]],
        constant uint *d [[buffer(8)]], uint index [[thread_position_in_grid]]) {
        uint frameCount = d[0], binCount = d[1];
        if (index >= frameCount * binCount) return;
        uint frame = index / binCount, bin = index % binCount;
        device const float *b = bins + bin * 12;
        device const float *f = frames + frame * 3;
        uint mi = bin * frameCount + frame;
        float magnitude = magnitudes[mi];
        float activity = frame > 0 ? abs(magnitude - magnitudes[mi - 1]) : 0.0f;
        float excess = max(0.0f, activity - b[2]);
        float floor = b[1];
        if (b[11] > 0.0f && s[0] > 0.0f && magnitude > b[5] * 1.2f) {
            float stability = precise::divide(activity, max(magnitude + b[6], 1e-6f));
            float stableWeight = max(0.0f, 1.0f - min(1.0f, stability * 2.2f));
            float lift = (1.0f - floor) * s[0] * b[7] * stableWeight * 0.22f;
            floor = min(0.46f, floor + lift);
        }
        if (f[0] > 0.0f && b[8] > 0.0f && magnitude > b[5] * 1.2f) floor = max(floor, s[4]);
        if (f[1] > 0.0f && magnitude > b[5] * 1.2f) {
            if (b[9] == 1.0f) floor = max(floor, s[5]);
            if (b[9] == 2.0f) floor = max(floor, s[6]);
        }
        int highIndex = highIndices[bin];
        float highLift = highIndex < 0 ? 0.0f : highFloors[frame * d[4] + uint(highIndex)];
        float protectedFloor = min(0.995f, floor + highLift);
        float raw = max(floor, min(1.0f, precise::divide(magnitude - b[0], max(magnitude, 1e-6f))));
        float granular = max(floor, 1.0f - min(0.72f, precise::divide(excess, max(magnitude + b[2], 1e-6f))) * s[1]);
        float transient = f[2] * b[4];
        float shimmer = 1.0f;
        if (bin >= d[2] && bin <= d[3] && frame > 0 && frame + 1 < frameCount && s[2] > 0.0f) {
            float average = (magnitudes[mi - 1] + magnitudes[mi + 1]) * 0.5f;
            float ratio = max(0.0f, precise::divide(magnitude - average, max(magnitude + average, 1e-6f)));
            if (ratio > 0.0f) {
                float protection = max(0.35f, 1.0f - transient * 1.6f);
                float stabilization = s[2] * max(0.0f, 1.0f - s[3]);
                shimmer = 1.0f - min(0.42f, ratio * stabilization * b[10] * protection);
            }
        }
        float highProtection = min(1.0f, precise::divide(highLift, 0.30f));
        float nonTonalReduction = b[3] * (1.0f - highProtection) * 0.03f;
        float nonTonalRaw = max(floor, raw - nonTonalReduction);
        float protectedRaw = max(protectedFloor, nonTonalRaw);
        float combined = protectedRaw * (1.0f - b[3]) + min(protectedRaw, granular) * b[3];
        float mask = min(1.0f, max(floor, min(combined, shimmer)) + transient);
        real[index] *= mask;
        imag[index] *= mask;
    }
    """#
}

private final class MetalDenoiseMaskCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: MetalDenoiseMaskContext?
    func context() -> MetalDenoiseMaskContext? {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        let options = MTLCompileOptions()
        options.mathMode = .safe
        options.mathFloatingPointFunctions = .precise
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: MetalDenoiseMaskProcessor.source, options: options),
              let function = library.makeFunction(name: "denoiseMask"),
              let pipeline = try? device.makeComputePipelineState(function: function) else { return nil }
        let context = MetalDenoiseMaskContext(device: device, queue: queue, pipeline: pipeline)
        cached = context
        return context
    }
}
private struct MetalDenoiseMaskContext {
    let device: any MTLDevice
    let queue: any MTLCommandQueue
    let pipeline: any MTLComputePipelineState
}
#endif
