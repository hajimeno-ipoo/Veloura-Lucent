import Accelerate
import Foundation

struct SeparationEngine {
    let model: StemSeparationModel
    let parameters: DemucsSeparationParameters
    let monitor: SeparationMonitor?

    private var sourceCount: Int { model.descriptor.sourceNames.count }

    func separate(
        mix: [Float],
        channels: Int,
        frames: Int,
        sampleRate: Int
    ) throws -> [Float] {
        try self.monitor?.checkCancellation()

        if parameters.shifts == 0 {
            self.monitor?.reportProgress(0.0, stage: "Separating")
            return try separateNoShift(
                mix: mix,
                channels: channels,
                frames: frames,
                sampleRate: sampleRate,
                monitor: self.monitor
            )
        }

        let maxShift = max(1, sampleRate / 2)
        var rng = SeededGenerator(seed: UInt64(bitPattern: Int64(parameters.seed ?? Int(Date().timeIntervalSince1970))))
        var accumulator = [Float](repeating: 0, count: sourceCount * channels * frames)

        for shiftIndex in 0..<parameters.shifts {
            try self.monitor?.checkCancellation()

            let shiftStart = Float(shiftIndex) / Float(parameters.shifts)
            let shiftEnd = Float(shiftIndex + 1) / Float(parameters.shifts)
            let shiftMonitor = self.monitor?.scoped(start: shiftStart, end: shiftEnd)
            shiftMonitor?.reportProgress(0.0, stage: "Shift \(shiftIndex + 1)/\(parameters.shifts)")

            // Match Meta Demucs' shift trick: prepend 0...0.5 seconds of silence,
            // run the model on that longer signal, then crop the same leading amount
            // from every separated source. Circular rolling changes the audio boundary
            // conditions and is not equivalent to the reference implementation.
            let shift = rng.nextInt(upperBound: maxShift + 1)
            let leadingPaddingFrames = maxShift - shift
            let shiftedFrames = frames + leadingPaddingFrames
            let shifted = zeroPaddedShift(
                mix,
                channels: channels,
                frames: frames,
                leadingPaddingFrames: leadingPaddingFrames
            )
            let estimate = try separateNoShift(
                mix: shifted,
                channels: channels,
                frames: shiftedFrames,
                sampleRate: sampleRate,
                monitor: shiftMonitor
            )
            for sourceIndex in 0..<sourceCount {
                for channelIndex in 0..<channels {
                    let estimateBase = (
                        (sourceIndex * channels + channelIndex) * shiftedFrames
                    ) + leadingPaddingFrames
                    let accumulatorBase = (sourceIndex * channels + channelIndex) * frames
                    for frameIndex in 0..<frames {
                        accumulator[accumulatorBase + frameIndex]
                            += estimate[estimateBase + frameIndex]
                    }
                }
            }
            shiftMonitor?.reportProgress(1.0, stage: "Shift \(shiftIndex + 1)/\(parameters.shifts) complete")
        }

        let inv = 1.0 / Float(parameters.shifts)
        for i in 0..<accumulator.count {
            accumulator[i] *= inv
        }
        return accumulator
    }

    private func separateNoShift(
        mix: [Float],
        channels: Int,
        frames: Int,
        sampleRate: Int,
        monitor: SeparationMonitor?
    ) throws -> [Float] {
        if !parameters.split {
            return try runModelOnce(
                mix: mix,
                channels: channels,
                frames: frames,
                monitor: monitor
            )
        }

        let defaultSegment = model.descriptor.defaultSegmentSeconds
        let segmentSeconds = parameters.segmentSeconds ?? defaultSegment
        let segmentFrames = max(1, Int(segmentSeconds * Double(sampleRate)))
        let stride = max(1, Int(Float(segmentFrames) * (1.0 - parameters.overlap)))

        // Fast-path short clips: avoid overlap-add chunk scheduling when it would create
        // at most two windows. This removes substantial overhead from repeated STFT/iSTFT.
        if frames <= segmentFrames + stride {
            return try runModelOnce(
                mix: mix,
                channels: channels,
                frames: frames,
                monitor: monitor
            )
        }

        var offsets: [Int] = []
        var offset = 0
        while offset < frames {
            offsets.append(offset)
            offset += stride
        }

        let weights = AudioDSP.triangularWeights(length: segmentFrames)
        var out = [Float](repeating: 0, count: sourceCount * channels * frames)
        var sumWeight = [Float](repeating: 0, count: frames)

        var batchData: [Float] = []
        var batchOffsets: [Int] = []
        var batchLengths: [Int] = []
        var batchStartChunkIndex = 0

        func flushBatch() throws {
            guard !batchOffsets.isEmpty else { return }
            let batchCount = batchOffsets.count

            // Create a scoped monitor so the model reports sub-step progress
            // mapped to this batch's slice of overall progress
            let batchMonitor: SeparationMonitor?
            if let monitor {
                let total = Float(offsets.count)
                batchMonitor = monitor.scoped(
                    start: Float(batchStartChunkIndex) / total,
                    end: Float(batchStartChunkIndex + batchCount) / total
                )
            } else {
                batchMonitor = nil
            }

            let output = try runModelBatch(
                batchData: batchData,
                batchCount: batchCount,
                channels: channels,
                frames: segmentFrames,
                monitor: batchMonitor
            )

            for b in 0..<batchCount {
                let chunkOffset = batchOffsets[b]
                let chunkLength = batchLengths[b]

                output.withUnsafeBufferPointer { outputBuf in
                    weights.withUnsafeBufferPointer { weightBuf in
                        out.withUnsafeMutableBufferPointer { outBuf in
                            for s in 0..<sourceCount {
                                for c in 0..<channels {
                                    let srcBase = (((b * sourceCount + s) * channels + c) * segmentFrames)
                                    let dstBase = ((s * channels + c) * frames) + chunkOffset
                                    // out[dst+t] = output[src+t] * weight[t] + out[dst+t]
                                    vDSP_vma(
                                        outputBuf.baseAddress! + srcBase, 1,
                                        weightBuf.baseAddress!, 1,
                                        outBuf.baseAddress! + dstBase, 1,
                                        outBuf.baseAddress! + dstBase, 1,
                                        vDSP_Length(chunkLength)
                                    )
                                }
                            }
                        }
                    }
                }

                sumWeight.withUnsafeMutableBufferPointer { swBuf in
                    weights.withUnsafeBufferPointer { wBuf in
                        vDSP_vadd(
                            swBuf.baseAddress! + chunkOffset, 1,
                            wBuf.baseAddress!, 1,
                            swBuf.baseAddress! + chunkOffset, 1,
                            vDSP_Length(chunkLength)
                        )
                    }
                }
            }

            batchData.removeAll(keepingCapacity: true)
            batchOffsets.removeAll(keepingCapacity: true)
            batchLengths.removeAll(keepingCapacity: true)
        }

        for (chunkIndex, chunkOffset) in offsets.enumerated() {
            try monitor?.checkCancellation()

            let chunkLength = min(segmentFrames, frames - chunkOffset)
            var chunk = [Float](repeating: 0, count: channels * segmentFrames)
            for c in 0..<channels {
                let srcBase = c * frames + chunkOffset
                let dstBase = c * segmentFrames
                for t in 0..<chunkLength {
                    chunk[dstBase + t] = mix[srcBase + t]
                }
            }

            if batchOffsets.isEmpty {
                batchStartChunkIndex = chunkIndex
            }
            batchData.append(contentsOf: chunk)
            batchOffsets.append(chunkOffset)
            batchLengths.append(chunkLength)

            if batchOffsets.count >= parameters.batchSize {
                try flushBatch()
            }
        }

        try monitor?.checkCancellation()
        try flushBatch()

        // Invert sumWeight for multiplication (faster than per-element division)
        var invWeight = [Float](repeating: 0, count: frames)
        invWeight.withUnsafeMutableBufferPointer { inv in
            sumWeight.withUnsafeBufferPointer { sw in
                // Floor at 1e-6 then invert
                for t in 0..<frames {
                    inv[t] = 1.0 / max(sw[t], 1e-6)
                }
            }
        }

        out.withUnsafeMutableBufferPointer { outBuf in
            invWeight.withUnsafeBufferPointer { invBuf in
                for s in 0..<sourceCount {
                    for c in 0..<channels {
                        let base = (s * channels + c) * frames
                        vDSP_vmul(
                            outBuf.baseAddress! + base, 1,
                            invBuf.baseAddress!, 1,
                            outBuf.baseAddress! + base, 1,
                            vDSP_Length(frames)
                        )
                    }
                }
            }
        }

        return out
    }

    private func runModelOnce(
        mix: [Float],
        channels: Int,
        frames: Int,
        monitor: SeparationMonitor?
    ) throws -> [Float] {
        try runModelBatch(
            batchData: mix,
            batchCount: 1,
            channels: channels,
            frames: frames,
            monitor: monitor
        )
    }

    private func runModelBatch(
        batchData: [Float],
        batchCount: Int,
        channels: Int,
        frames: Int,
        monitor: SeparationMonitor? = nil
    ) throws -> [Float] {
        try model.predict(
            batchData: batchData,
            batchSize: batchCount,
            channels: channels,
            frames: frames,
            monitor: monitor
        )
    }

    private func zeroPaddedShift(
        _ input: [Float],
        channels: Int,
        frames: Int,
        leadingPaddingFrames: Int
    ) -> [Float] {
        guard leadingPaddingFrames > 0 else { return input }
        let shiftedFrames = frames + leadingPaddingFrames
        var output = [Float](repeating: 0, count: channels * shiftedFrames)
        for channelIndex in 0..<channels {
            let inputBase = channelIndex * frames
            let outputBase = channelIndex * shiftedFrames + leadingPaddingFrames
            for frameIndex in 0..<frames {
                output[outputBase + frameIndex] = input[inputBase + frameIndex]
            }
        }
        return output
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Avoid zero state for xorshift.
        self.state = seed == 0 ? 0x9e37_79b9_7f4a_7c15 : seed
    }

    mutating func next() -> UInt64 {
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 0x2545_f491_4f6c_dd1d
    }

    mutating func nextInt(upperBound: Int) -> Int {
        if upperBound <= 1 {
            return 0
        }
        return Int(next() % UInt64(upperBound))
    }
}
