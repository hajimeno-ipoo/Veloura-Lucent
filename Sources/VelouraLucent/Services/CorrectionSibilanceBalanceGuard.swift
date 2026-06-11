import Foundation

extension NativeAudioProcessor {
    func constrainCorrectionSibilanceIncrease(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        measurementCache: NoiseMeasurementRunCache,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let ids = [NoiseMeasurementID.sibilance, NoiseMeasurementID.hiss, NoiseMeasurementID.shimmer]
        var measurementCount = 0
        let currentMeasurements = measurementCache.snapshot(
            signalID: "correctionSibilanceBalance.current",
            signal: signal,
            ids: ids
        )
        measurementCount += 1
        guard let referenceSibilance = referenceMeasurements.comparableLevel(for: NoiseMeasurementID.sibilance),
              let currentSibilance = currentMeasurements.comparableLevel(for: NoiseMeasurementID.sibilance)
        else {
            logger?.log("サ行保護/通常高域戻し/測定回数: \(measurementCount)")
            return signal
        }

        let allowedIncreaseDB = 0.5
        guard currentSibilance > referenceSibilance + allowedIncreaseDB else {
            logger?.log("サ行保護/通常高域戻し/測定回数: \(measurementCount)")
            return signal
        }

        let currentHiss = currentMeasurements.comparableLevel(for: NoiseMeasurementID.hiss) ?? -120
        let currentShimmer = currentMeasurements.comparableLevel(for: NoiseMeasurementID.shimmer) ?? -120
        let referenceHiss = referenceMeasurements.comparableLevel(for: NoiseMeasurementID.hiss) ?? currentHiss
        let referenceShimmer = referenceMeasurements.comparableLevel(for: NoiseMeasurementID.shimmer) ?? currentShimmer
        let hissCeiling = max(currentHiss + 0.5, referenceHiss + 0.5)
        let shimmerCeiling = max(currentShimmer + 0.5, referenceShimmer + 0.5)

        let candidateInputs: [(mix: Float, transientScale: Float, peakReductionDB: Float)] = [
            (0.55, 1.45, 0), (0.75, 1.45, 0), (1.00, 1.45, 0), (1.25, 1.45, 0), (1.50, 1.45, 0),
            (0.75, 1.80, 0), (1.00, 1.80, 0), (1.25, 1.80, 0),
            (0.75, 2.10, 0), (1.00, 2.10, 0),
            (1.00, 1.45, 0.75), (1.25, 1.45, 0.75), (1.50, 1.45, 0.75),
            (1.00, 1.45, 1.25), (1.25, 1.45, 1.25), (1.50, 1.45, 1.25),
            (1.00, 1.45, 1.75), (1.25, 1.45, 1.75)
        ]
        let candidates: [(index: Int, mix: Float, transientScale: Float, peakReductionDB: Float, signal: AudioSignal)] = candidateInputs.enumerated().map { index, input in
            (
                index: index,
                mix: input.mix,
                transientScale: input.transientScale,
                peakReductionDB: input.peakReductionDB,
                signal: restoreSustainedSibilanceFloor(
                    signal: signal,
                    reference: reference,
                    mix: input.mix,
                    transientScale: input.transientScale,
                    peakReductionDB: input.peakReductionDB
                )
            )
        }

        var measuredCandidates: [(index: Int, mix: Float, transientScale: Float, peakReductionDB: Float, signal: AudioSignal, sibilance: Double)] = []
        measuredCandidates.reserveCapacity(candidates.count)
        for candidate in candidates {
            let measurements = measurementCache.snapshot(
                signalID: "correctionSibilanceBalance.candidate.\(candidate.index)",
                signal: candidate.signal,
                ids: ids
            )
            measurementCount += 1
            let candidateSibilance = measurements.comparableLevel(for: NoiseMeasurementID.sibilance) ?? currentSibilance
            let candidateHiss = measurements.comparableLevel(for: NoiseMeasurementID.hiss) ?? currentHiss
            let candidateShimmer = measurements.comparableLevel(for: NoiseMeasurementID.shimmer) ?? currentShimmer
            guard candidateHiss <= hissCeiling, candidateShimmer <= shimmerCeiling else { continue }
            measuredCandidates.append((candidate.index, candidate.mix, candidate.transientScale, candidate.peakReductionDB, candidate.signal, candidateSibilance))
        }

        logger?.log("サ行保護/通常高域戻し/測定回数: \(measurementCount)")
        let selected = measuredCandidates.first { $0.sibilance <= referenceSibilance + allowedIncreaseDB }
            ?? measuredCandidates.min { lhs, rhs in
                if lhs.sibilance != rhs.sibilance { return lhs.sibilance < rhs.sibilance }
                return lhs.mix < rhs.mix
            }
        guard let selected, selected.sibilance < currentSibilance - 0.1 else {
            logger?.log("サ行保護/通常高域戻し: 有効な改善候補がないため維持")
            return signal
        }
        logger?.log(
            "サ行保護/通常高域戻し: mix \(String(format: "%.2f", selected.mix)) threshold \(String(format: "%.2f", selected.transientScale)) peak \(String(format: "%.2f", selected.peakReductionDB)) dB sibilance \(String(format: "%.1f", selected.sibilance)) dB"
        )
        return selected.signal
    }

    func restoreSustainedSibilanceFloor(signal: AudioSignal, reference: AudioSignal, mix: Float, transientScale: Float, peakReductionDB: Float) -> AudioSignal {
        let channelCount = min(signal.channels.count, reference.channels.count)
        guard channelCount > 0 else { return signal }
        let sampleRate = signal.sampleRate
        var channels = Array(signal.channels.prefix(channelCount))
        for channelIndex in 0..<channelCount {
            channels[channelIndex] = restoreSustainedBand(
                channel: signal.channels[channelIndex],
                reference: reference.channels[channelIndex],
                sampleRate: sampleRate,
                mix: mix,
                transientScale: transientScale,
                peakReductionDB: peakReductionDB
            )
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func restoreSustainedBand(channel: [Float], reference: [Float], sampleRate: Double, mix: Float, transientScale: Float, peakReductionDB: Float) -> [Float] {
        let count = min(channel.count, reference.count)
        guard count > 0 else { return channel }
        let upper = min(9_000.0, sampleRate * 0.5 - 100)
        guard 5_000 < upper else { return channel }

        let processedBand = Array(SpectralDSP.lowPass(
            SpectralDSP.highPass(Array(channel.prefix(count)), cutoff: 5_000, sampleRate: sampleRate),
            cutoff: upper,
            sampleRate: sampleRate
        ).prefix(count))
        let referenceBand = Array(SpectralDSP.lowPass(
            SpectralDSP.highPass(Array(reference.prefix(count)), cutoff: 5_000, sampleRate: sampleRate),
            cutoff: upper,
            sampleRate: sampleRate
        ).prefix(count))
        let frameSize = max(1, Int(sampleRate * 0.020))
        var frameRMS: [Float] = []
        frameRMS.reserveCapacity(max(1, count / frameSize))
        var start = 0
        while start < count {
            let end = min(count, start + frameSize)
            let meanSquare = processedBand[start..<end].reduce(Float.zero) { $0 + $1 * $1 } / Float(max(end - start, 1))
            frameRMS.append(sqrtf(meanSquare))
            start = end
        }
        let median = max(SpectralDSP.percentile(frameRMS, 50), 1e-7)
        let transientThreshold = median * transientScale
        let peakReduction = 1 - powf(10, -peakReductionDB / 20)

        var output = Array(channel.prefix(count))
        for frameIndex in frameRMS.indices {
            let start = frameIndex * frameSize
            let end = min(count, start + frameSize)
            if frameRMS[frameIndex] <= transientThreshold {
                for index in start..<end {
                    output[index] += (referenceBand[index] - processedBand[index]) * mix
                }
            } else if peakReductionDB > 0 {
                for index in start..<end {
                    output[index] -= processedBand[index] * peakReduction
                }
            }
        }
        if channel.count > count {
            output.append(contentsOf: channel[count...])
        }
        return output
    }
}
