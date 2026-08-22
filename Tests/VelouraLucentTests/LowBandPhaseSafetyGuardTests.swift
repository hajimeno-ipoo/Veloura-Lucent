import Foundation
import Testing
@testable import VelouraLucent

struct LowBandPhaseSafetyGuardTests {
    private let sampleRate = 48_000.0

    @Test
    func monoInputIsReturnedUnchanged() throws {
        let mono = sine(frequency: 80, amplitude: 0.2, duration: 0.5)
        let signal = AudioSignal(channels: [mono], sampleRate: sampleRate)

        let result = try LowBandPhaseSafetyGuard().process(
            signal: signal,
            reference: signal
        )

        #expect(result.outcome == .skippedMono)
        #expect(result.signal.channels == signal.channels)
    }

    @Test
    func inPhaseLowBandIsReturnedUnchanged() throws {
        let low = sine(frequency: 80, amplitude: 0.2, duration: 0.75)
        let signal = AudioSignal(channels: [low, low], sampleRate: sampleRate)

        let result = try LowBandPhaseSafetyGuard().process(
            signal: signal,
            reference: signal
        )

        #expect(
            result.outcome == .skippedNoDestructivePhase,
            "affected=\(result.affectedTimeFrequencyCells) risk=\(result.riskBefore)"
        )
        #expect(
            result.affectedTimeFrequencyCells == 0,
            "risk=\(result.riskBefore)"
        )
        #expect(result.signal.channels == signal.channels)
    }

    @Test
    func oneSidedLowBandIsNotMistakenForReversePhase() throws {
        let low = sine(frequency: 80, amplitude: 0.2, duration: 0.75)
        let silence = Array(repeating: Float.zero, count: low.count)
        let signal = AudioSignal(channels: [low, silence], sampleRate: sampleRate)

        let result = try LowBandPhaseSafetyGuard().process(
            signal: signal,
            reference: signal
        )

        #expect(
            result.outcome == .skippedNoDestructivePhase,
            "affected=\(result.affectedTimeFrequencyCells) risk=\(result.riskBefore)"
        )
        #expect(
            result.affectedTimeFrequencyCells == 0,
            "risk=\(result.riskBefore)"
        )
        #expect(result.signal.channels == signal.channels)
    }

    @Test
    func inputOriginReversePhaseLowBandIsRepairedWithoutChangingHighBandMaterially() throws {
        let low = sine(frequency: 80, amplitude: 0.2, duration: 1)
        let high = sine(frequency: 1_200, amplitude: 0.06, duration: 1)
        let left = zip(low, high).map(+)
        let right = zip(low, high).map { pair in -pair.0 + pair.1 }
        let signal = AudioSignal(channels: [left, right], sampleRate: sampleRate)

        let result = try LowBandPhaseSafetyGuard().process(
            signal: signal,
            reference: signal
        )

        #expect(result.outcome == .repaired(.input))
        #expect(result.affectedTimeFrequencyCells > 0)
        #expect(result.riskAfter < result.riskBefore)
        let inputMetrics = try #require(result.inputMetrics)
        #expect(abs(inputMetrics.riskScore - result.beforeMetrics.riskScore) < 0.000_1)
        #expect(result.beforeMetrics.affectedDurationSeconds > 0)
        let beforeLoss = try #require(result.beforeMetrics.monoCompatibilityLossDB)
        let afterLoss = try #require(result.afterMetrics.monoCompatibilityLossDB)
        #expect(afterLoss > beforeLoss)
        #expect(bandRMS(result.signal.monoMixdown(), lower: 20, upper: 180)
            > bandRMS(signal.monoMixdown(), lower: 20, upper: 180) * 10)
        expectBandChangeWithin(
            before: signal,
            after: result.signal,
            lower: 500,
            upper: 5_000,
            toleranceDB: 0.05
        )
    }

    @Test
    func processingOriginReversePhaseIsDistinguishedFromSafeInput() throws {
        let low = sine(frequency: 95, amplitude: 0.18, duration: 1)
        let reference = AudioSignal(channels: [low, low], sampleRate: sampleRate)
        let current = AudioSignal(channels: [low, low.map(-)], sampleRate: sampleRate)

        let result = try LowBandPhaseSafetyGuard().process(
            signal: current,
            reference: reference
        )

        #expect(result.outcome == .repaired(.processing))
        #expect(result.riskAfter < result.riskBefore)
        let inputMetrics = try #require(result.inputMetrics)
        #expect(inputMetrics.riskScore < result.beforeMetrics.riskScore)
    }

    @Test
    func worsenedInputReversePhaseIsClassifiedAsInputAndProcessing() throws {
        let low = sine(frequency: 95, amplitude: 0.18, duration: 1)
        let referenceRight = low.map { $0 * -0.4 }
        let reference = AudioSignal(
            channels: [low, referenceRight],
            sampleRate: sampleRate
        )
        let current = AudioSignal(channels: [low, low.map(-)], sampleRate: sampleRate)

        let result = try LowBandPhaseSafetyGuard().process(
            signal: current,
            reference: reference
        )

        #expect(result.outcome == .repaired(.inputAndProcessing))
        #expect(result.riskAfter < result.riskBefore)
        let inputMetrics = try #require(result.inputMetrics)
        #expect(inputMetrics.riskScore < result.beforeMetrics.riskScore)
    }

    @Test
    func repairedResultWritesBeforeAfterMetricsToDetailedLog() throws {
        let low = sine(frequency: 95, amplitude: 0.18, duration: 1)
        let referenceRight = low.map { $0 * -0.4 }
        let reference = AudioSignal(
            channels: [low, referenceRight],
            sampleRate: sampleRate
        )
        let current = AudioSignal(channels: [low, low.map(-)], sampleRate: sampleRate)
        let logger = LowBandPhaseLogCollector()
        let context = CorrectionRunContext(
            correctionSettings: DenoiseStrength.balanced.settings,
            resolvedAnalysisMode: .cpu,
            diagnosticOutputDirectory: nil,
            logger: logger,
            benchmarkRecorder: nil,
            noiseMeasurementCache: NoiseMeasurementRunCache()
        )

        _ = try NativeAudioProcessor().applyLowBandPhaseSafety(
            to: current,
            reference: reference,
            context: context
        )

        #expect(logger.values.compactMap(ProcessingProgressEvent.decode).contains { event in
            guard case let .correction(step, state, detail) = event else { return false }
            return step == .lowBandPhaseSafety
                && state == .detail
                && detail?.hasPrefix("位相補正 ") == true
                && detail?.hasSuffix("セル") == true
        })
        #expect(logger.values.contains(
            "低域位相/原因: 入力にも存在し、補正後に一部増加"
        ))
        #expect(logger.values.contains {
            $0.hasPrefix("低域位相/対象: 20〜180Hz・")
                && $0.contains("セル・対象時間 約")
        })
        #expect(logger.values.contains {
            $0.hasPrefix("低域位相/内部相殺指標: 入力 ")
                && $0.contains(" → 補正後 ")
                && $0.contains(" → 修復後 ")
                && !$0.contains("測定不可")
        })
        #expect(logger.values.contains {
            $0.hasPrefix("低域位相/モノラル低域損失: 入力 ")
                && $0.contains(" → 補正後 ")
                && $0.contains(" → 修復後 ")
                && !$0.contains("測定不可")
        })
        #expect(logger.values.contains {
            $0.hasPrefix("低域位相/結果: 内部相殺指標 ")
                && $0.contains("モノラル低域損失 ")
                && $0.hasSuffix("安全検証通過")
        })
        #expect(logger.values.allSatisfy {
            !$0.contains("入力由来かつ補正後に悪化")
        })
    }

    @Test
    func safeRegionBeforeReversePhaseSectionRemainsUnchanged() throws {
        let duration = 1.5
        let count = Int(sampleRate * duration)
        var left = Array(repeating: Float.zero, count: count)
        var right = Array(repeating: Float.zero, count: count)
        for index in 0..<count {
            let time = Double(index) / sampleRate
            let sample = Float(sin(2 * Double.pi * 72 * time) * 0.2)
            left[index] = sample
            right[index] = time < 0.75 ? sample : -sample
        }
        let signal = AudioSignal(channels: [left, right], sampleRate: sampleRate)

        let result = try LowBandPhaseSafetyGuard().process(
            signal: signal,
            reference: signal
        )

        #expect(result.outcome == .repaired(.input))
        let safeEnd = Int(sampleRate * 0.5)
        let maximumSafeDifference = (0..<safeEnd).reduce(Float.zero) { current, index in
            max(
                current,
                max(
                    abs(result.signal.channels[0][index] - signal.channels[0][index]),
                    abs(result.signal.channels[1][index] - signal.channels[1][index])
                )
            )
        }
        #expect(maximumSafeDifference < 0.000_1)

        let problemStart = Int(sampleRate * 1.0)
        let beforeProblemMono = monoRMS(signal, range: problemStart..<count)
        let afterProblemMono = monoRMS(result.signal, range: problemStart..<count)
        #expect(afterProblemMono > beforeProblemMono * 10)
    }

    @Test
    func reversePhaseOutsideLowBandIsReturnedUnchanged() throws {
        let high = faded(
            sine(frequency: 1_200, amplitude: 0.2, duration: 0.75),
            duration: 0.05
        )
        let signal = AudioSignal(channels: [high, high.map(-)], sampleRate: sampleRate)

        let result = try LowBandPhaseSafetyGuard().process(
            signal: signal,
            reference: signal
        )

        #expect(
            result.outcome == .skippedNoDestructivePhase,
            "affected=\(result.affectedTimeFrequencyCells) risk=\(result.riskBefore)"
        )
        #expect(
            result.affectedTimeFrequencyCells == 0,
            "risk=\(result.riskBefore)"
        )
        #expect(result.signal.channels == signal.channels)
    }

    private func sine(
        frequency: Double,
        amplitude: Double,
        duration: Double
    ) -> [Float] {
        let count = Int(sampleRate * duration)
        return (0..<count).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * amplitude)
        }
    }

    private func faded(_ samples: [Float], duration: Double) -> [Float] {
        let fadeCount = min(Int(sampleRate * duration), samples.count / 2)
        guard fadeCount > 1 else { return samples }
        return samples.enumerated().map { index, sample in
            let distanceFromEdge = min(index, samples.count - 1 - index)
            guard distanceFromEdge < fadeCount else { return sample }
            let phase = Double(distanceFromEdge) / Double(fadeCount - 1)
            let gain = 0.5 - 0.5 * cos(Double.pi * phase)
            return sample * Float(gain)
        }
    }

    private func bandRMS(
        _ samples: [Float],
        lower: Double,
        upper: Double
    ) -> Double {
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(samples, cutoff: lower, sampleRate: sampleRate),
            cutoff: upper,
            sampleRate: sampleRate
        )
        let meanSquare = band.reduce(0.0) {
            $0 + Double($1 * $1)
        } / Double(max(band.count, 1))
        return sqrt(max(meanSquare, 1e-20))
    }

    private func expectBandChangeWithin(
        before: AudioSignal,
        after: AudioSignal,
        lower: Double,
        upper: Double,
        toleranceDB: Double
    ) {
        for channelIndex in 0..<2 {
            let beforeRMS = bandRMS(
                before.channels[channelIndex],
                lower: lower,
                upper: upper
            )
            let afterRMS = bandRMS(
                after.channels[channelIndex],
                lower: lower,
                upper: upper
            )
            let changeDB = 20 * log10(max(afterRMS, 1e-20) / max(beforeRMS, 1e-20))
            #expect(abs(changeDB) <= toleranceDB)
        }
    }

    private func monoRMS(
        _ signal: AudioSignal,
        range: Range<Int>
    ) -> Double {
        let mono = signal.monoMixdown()
        let boundedRange = max(0, range.lowerBound)..<min(mono.count, range.upperBound)
        let meanSquare = mono[boundedRange].reduce(0.0) {
            $0 + Double($1 * $1)
        } / Double(max(boundedRange.count, 1))
        return sqrt(max(meanSquare, 1e-20))
    }
}

private final class LowBandPhaseLogCollector: AudioProcessingLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func log(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }
}
