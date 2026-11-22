import Foundation
import Testing
@testable import VelouraLucent

struct MetalDenoiseMaskProcessorTests {
    @Test
    func executesNewKernelAndMatchesCPUShimmerMaskBits() throws {
        // An isolated temporal high-frequency event exercises the CPU sinf table,
        // first/last-frame exceptions, granular masking and complex multiplication.
        let magnitudes: [Float] = [0.3, 0.9, 0.2]
        let binWeight: Float = 0.75 + sinf(Float(0.37) * .pi) * 0.25
        let threshold: Float = 0.04
        let granularThreshold: Float = 0.03
        let floor: Float = 0.18
        let lift: Float = 0.02
        let granularReduction: Float = 0.32
        let stabilization: Float = 0.85
        let exception: Float = 0.04
        let real: [Float] = [0.23, -0.41, 0.06]
        let imag: [Float] = [-0.1, 0.29, -0.03]
        var actualReal = real
        var actualImag = imag
        let executed = MetalDenoiseMaskProcessor().apply(
            real: &actualReal, imag: &actualImag, magnitudes: magnitudes,
            bins: [threshold, floor, granularThreshold, 1, 0.2, 0.01, 0.02, 0, 0, 0, binWeight, 0],
            frames: [0, 0, lift, 0, 0, lift, 0, 0, lift],
            highFloorLifts: [0.04, 0.04, 0.04], highFloorIndices: [0], activeHighBinCount: 1,
            frameCount: 3, binCount: 1, shimmerStart: 0, shimmerEnd: 0,
            scalars: [0, granularReduction, stabilization, exception, 0.8, 0.7, 0.75]
        )
        try #require(executed, "New Metal denoise kernel must complete; CPU fallback cannot satisfy this test")
        for frame in 0..<3 {
            let magnitude = magnitudes[frame]
            let activity = frame > 0 ? abs(magnitude - magnitudes[frame - 1]) : 0
            let excess = max(0, activity - granularThreshold)
            let raw = max(floor, min(1, (magnitude - threshold) / max(magnitude, 1e-6)))
            let granular = max(floor, 1 - min(0.72, excess / max(magnitude + granularThreshold, 1e-6)) * granularReduction)
            let highProtection = min(1, Float(0.04) / 0.30)
            let reduction = (1 - highProtection) * 0.03
            let protectedRaw = max(min(0.995, floor + 0.04), max(floor, raw - reduction))
            let combined = protectedRaw * (1 - Float(1)) + min(protectedRaw, granular) * 1
            var shimmer: Float = 1
            if frame == 1 {
                let average = (magnitudes[0] + magnitudes[2]) * 0.5
                let ratio = max(0, (magnitude - average) / max(magnitude + average, 1e-6))
                shimmer = DenoiseShimmerStabilizer.mask(
                    temporalExcessRatio: ratio, bandPosition: 0.37, transientLift: lift * 0.2,
                    stabilization: stabilization, exceptionRelaxation: exception
                )
            }
            let mask = min(1, max(floor, min(combined, shimmer)) + lift * 0.2)
            #expect(actualReal[frame].bitPattern == (real[frame] * mask).bitPattern)
            #expect(actualImag[frame].bitPattern == (imag[frame] * mask).bitPattern)
        }
    }

    @Test
    func completeDenoisePreservesCPUOutputForProfilesAndSignalEdges() {
        for sampleRate in [44_100.0, 48_000.0, 96_000.0] {
            var noiseState: UInt64 = 0x53A1
            let samples = (0..<Int(sampleRate * 0.35)).map { index -> Float in
                let time = Double(index) / sampleRate
                let envelope = time < 0.12 ? 1.0 : exp(-(time - 0.12) * 12)
                let body = (sin(2 * .pi * 110 * time) * 0.09 + sin(2 * .pi * 220 * time) * 0.04) * envelope
                let burst = time > 0.16 && time < 0.18 ? 0.09 : 0.008
                let shimmer = sin(2 * .pi * 12_500 * time) * burst
                noiseState = noiseState &* 6_364_136_223_846_793_005 &+ 1
                let noise = (Double(noiseState >> 11) / 9_007_199_254_740_992 - 0.5) * 0.008
                return Float(body + shimmer + noise)
            }
            var impulse = Array(repeating: Float.zero, count: 4_097)
            impulse[0] = 0.5
            impulse[4_096] = -0.4
            for profile in DenoiseStrength.allCases {
                for (inputIndex, input) in [samples, impulse, Array(repeating: Float.zero, count: 1_025)].enumerated() {
                    let signal = AudioSignal(channels: [input], sampleRate: sampleRate)
                    let cpu = SpectralGateDenoiser(settings: profile.settings, useMetal: false, maskBreakdownCollector: nil).process(signal: signal)
                    let gpu = SpectralGateDenoiser(settings: profile.settings, maskBreakdownCollector: nil).process(signal: signal)
                    #expect(gpu.channels.count == cpu.channels.count)
                    let bitsEqual = gpu.channels[0].map(\.bitPattern) == cpu.channels[0].map(\.bitPattern)
                    let maxDifference = zip(gpu.channels[0], cpu.channels[0]).map { abs($0 - $1) }.max() ?? 0
                    #expect(bitsEqual, "rate=\(sampleRate), profile=\(profile.rawValue), input=\(inputIndex), maxDifference=\(maxDifference)")
                }
            }
        }
    }
}
