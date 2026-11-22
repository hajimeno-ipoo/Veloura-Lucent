import Foundation
import Metal

/// Reconstructs each output sample in the same frame order as the CPU iSTFT.
final class BSRoformerMetalOverlapAdd: @unchecked Sendable {
    static let shared = BSRoformerMetalOverlapAdd()

    private let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState

    private init?() {
        let options = MTLCompileOptions()
        if #available(macOS 15.0, *) {
            options.mathMode = .safe
            options.mathFloatingPointFunctions = .precise
        } else {
            options.fastMathEnabled = false
        }
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.source, options: options),
              let function = library.makeFunction(name: "bsOverlapAdd"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            return nil
        }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
    }

    func reconstruct(
        frames: [Float],
        windowSquared: [Float],
        fftSize: Int,
        hopLength: Int,
        frameCount: Int,
        outer: Int,
        length: Int,
        trimStart: Int
    ) -> [Float]? {
        guard fftSize > 0, hopLength > 0, frameCount > 0, outer > 0,
              length > 0, trimStart >= 0,
              frames.count == outer * frameCount * fftSize,
              windowSquared.count == fftSize,
              trimStart + length <= (frameCount - 1) * hopLength + fftSize,
              [fftSize, hopLength, frameCount, outer * length, trimStart + length]
                .allSatisfy({ $0 <= Int(Int32.max) }),
              frames.count <= Int(UInt32.max) else { return nil }
        let outputCount = outer * length
        guard let input = frames.withUnsafeBytes({ bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }), let window = windowSquared.withUnsafeBytes({ bytes in
            device.makeBuffer(bytes: bytes.baseAddress!, length: bytes.count, options: .storageModeShared)
        }), let output = device.makeBuffer(
            length: outputCount * MemoryLayout<Float>.stride, options: .storageModeShared
        ), let command = queue.makeCommandBuffer(),
           let encoder = command.makeComputeCommandEncoder() else { return nil }

        let parameters: [UInt32] = [fftSize, hopLength, frameCount, length, trimStart, outputCount].map(UInt32.init)
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(input, offset: 0, index: 0)
        encoder.setBuffer(window, offset: 0, index: 1)
        encoder.setBuffer(output, offset: 0, index: 2)
        parameters.withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 3)
        }
        encoder.dispatchThreads(
            MTLSize(width: outputCount, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: min(256, pipeline.maxTotalThreadsPerThreadgroup), height: 1, depth: 1)
        )
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        guard command.status == .completed else { return nil }
        return Array(UnsafeBufferPointer(start: output.contents().assumingMemoryBound(to: Float.self), count: outputCount))
    }

    private static let source = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void bsOverlapAdd(
        device const float *frames [[buffer(0)]],
        device const float *windowSquared [[buffer(1)]],
        device float *output [[buffer(2)]],
        constant uint *p [[buffer(3)]],
        uint index [[thread_position_in_grid]]) {
        if (index >= p[5]) return;
        const int fftSize = int(p[0]);
        const int hop = int(p[1]);
        const int frameCount = int(p[2]);
        const uint item = index / p[3];
        const int sample = int(index % p[3] + p[4]);
        // ceil((sample - fftSize + 1) / hop), clamped before division.
        const int firstFrame = sample < fftSize ? 0 : (sample - fftSize) / hop + 1;
        const int lastFrame = min(frameCount - 1, sample / hop);
        float sum = 0.0f;
        float weight = 0.0f;
        for (int frame = firstFrame; frame <= lastFrame; ++frame) {
            const int offset = sample - frame * hop;
            weight += windowSquared[offset];
            sum += frames[(item * p[2] + uint(frame)) * p[0] + uint(offset)];
        }
        output[index] = weight > 1e-11f ? precise::divide(sum, weight) : 0.0f;
    }
    """
}
