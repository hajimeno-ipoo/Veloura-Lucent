import Foundation

extension MasteringProcessor {
    func applyTone(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float,
        noiseMeasurements: NoiseMeasurementSnapshot?,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let lowAdjustmentDB = settings.lowShelfGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 18), min: -0.25, max: 1.2)
        let lowMidAdjustmentDB = settings.lowMidGain - MasteringSignalMath.clamped(Float((analysis.lowBandLevelDB - analysis.midBandLevelDB) / 16), min: -0.2, max: 0.7)
        let roomPlan = roomLowMidAdjustment(
            settings: settings,
            mudLevelDB: noiseMeasurements?.comparableLevel(for: NoiseMeasurementID.mud)
        )
        let roomAdjustmentDB = roomPlan.adjustmentDB
        let presenceAdjustmentDB = settings.presenceGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 16), min: -0.2, max: 0.8) - analysis.harshnessScore * 0.32
        let highAdjustmentDB = settings.highShelfGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 18), min: -0.25, max: 0.9) - analysis.harshnessScore * 0.55
        let toneScale = 0.72 + finishingIntensity * 0.46
        let lowMidBefore = MasteringSignalMath.bandRMSDB(signal: signal, lower: 120, upper: 420)
        let roomBefore = MasteringSignalMath.bandRMSDB(signal: signal, lower: 420, upper: 1_200)
        let highBefore = MasteringSignalMath.bandRMSDB(signal: signal, lower: 10_000, upper: 20_000)

        let lowDelta = MasteringSignalMath.gainDelta(forDB: lowAdjustmentDB) * toneScale
        let lowMidDelta = MasteringSignalMath.gainDelta(forDB: lowMidAdjustmentDB) * toneScale
        let roomDelta = MasteringSignalMath.gainDelta(forDB: roomAdjustmentDB) * toneScale
        let presenceDelta = MasteringSignalMath.gainDelta(forDB: presenceAdjustmentDB) * toneScale
        let highDelta = MasteringSignalMath.gainDelta(forDB: highAdjustmentDB) * toneScale

        let channels = signal.channels.map { channel in
            let low = SpectralDSP.lowPass(channel, cutoff: 120, sampleRate: signal.sampleRate)
            let lowMid = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 120, sampleRate: signal.sampleRate),
                cutoff: 420,
                sampleRate: signal.sampleRate
            )
            let roomLowMid = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 420, sampleRate: signal.sampleRate),
                cutoff: 1_200,
                sampleRate: signal.sampleRate
            )
            let presence = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 2_500, sampleRate: signal.sampleRate),
                cutoff: 5_500,
                sampleRate: signal.sampleRate
            )
            let high = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 10_000, sampleRate: signal.sampleRate),
                cutoff: 20_000,
                sampleRate: signal.sampleRate
            )
            return channel.indices.map { index in
                channel[index]
                    + low[index] * lowDelta
                    + lowMid[index] * lowMidDelta
                    + roomLowMid[index] * roomDelta
                    + presence[index] * presenceDelta
                    + high[index] * highDelta
            }
        }

        let toned = GeneratedHighFrequencyDeltaLimiter.preserveOriginalUltraHigh(
            original: signal,
            processed: AudioSignal(channels: channels, sampleRate: signal.sampleRate)
        )
        let lowMidAfter = MasteringSignalMath.bandRMSDB(signal: toned, lower: 120, upper: 420)
        let roomAfter = MasteringSignalMath.bandRMSDB(signal: toned, lower: 420, upper: 1_200)
        let highShelfAfter = MasteringSignalMath.bandRMSDB(signal: toned, lower: 10_000, upper: 20_000)
        logger?.log(
            "中低域調整/120〜420Hz: 処理前 \(formatToneLevel(lowMidBefore)) / "
                + "適用量 \(formatSignedDB(lowMidAfter - lowMidBefore)) / 処理後 \(formatToneLevel(lowMidAfter)) / "
                + "理由 設定値と入力帯域差から算出"
        )
        logger?.log(
            "中低域調整/420〜1200Hz: 処理前 \(formatToneLevel(roomBefore)) / "
                + "適用量 \(formatSignedDB(roomAfter - roomBefore)) / 処理後 \(formatToneLevel(roomAfter)) / "
                + "理由 \(roomPlan.reason)"
        )
        logger?.log(
            "高域調整/10〜20kHz（Shelf）: 処理前 \(formatToneLevel(highBefore)) / "
                + "設定gain \(String(format: "%+.2f", settings.highShelfGain)) dB / "
                + "実測変化 \(formatSignedDB(highShelfAfter - highBefore)) / 処理後 \(formatToneLevel(highShelfAfter)) / "
                + "理由 high shelf設定と入力帯域差から算出"
        )
        return applySibilanceAwareBrillianceLift(
            signal: toned,
            analysis: analysis,
            finishingIntensity: finishingIntensity,
            logger: logger
        )
    }

    private func applySibilanceAwareBrillianceLift(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        finishingIntensity: Float,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let highDeficit = MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 24), min: 0, max: 0.45)
        let baseLiftDB = highDeficit - analysis.harshnessScore * 0.22
        let liftDB = MasteringSignalMath.clamped(baseLiftDB * (0.70 + finishingIntensity * 0.22), min: 0, max: 1.00)
        let before = MasteringSignalMath.bandRMSDB(signal: signal, lower: 9_000, upper: 12_000)
        guard liftDB > 0.08 else {
            logger?.log(
                "高域調整/9〜12kHz（Brilliance）: 処理前 \(formatToneLevel(before)) / "
                    + "設定gain +0.00 dB / 実測変化 \(formatSignedDB(0)) / "
                    + "処理後 \(formatToneLevel(before)) / 理由 高域不足なし"
            )
            return signal
        }

        let gain = powf(10, liftDB / 20)
        let sampleRate = signal.sampleRate
        let channels = mapChannelsConcurrently(signal.channels) {
            sibilanceAwareBrillianceLift(channel: $0, sampleRate: sampleRate, gain: gain)
        }
        let result = AudioSignal(channels: channels, sampleRate: signal.sampleRate)
        let after = MasteringSignalMath.bandRMSDB(signal: result, lower: 9_000, upper: 12_000)
        logger?.log(
            "高域調整/9〜12kHz（Brilliance）: 処理前 \(formatToneLevel(before)) / "
                + "設定gain \(String(format: "+%.2f", liftDB)) dB / "
                + "実測変化 \(formatSignedDB(after - before)) / 処理後 \(formatToneLevel(after)) / "
                + "理由 入力の高域不足から算出しサ行区間を除外"
        )
        return result
    }

    private func roomLowMidAdjustment(
        settings: MasteringSettings,
        mudLevelDB: Double?
    ) -> (adjustmentDB: Float, reason: String) {
        guard let mudLevelDB, mudLevelDB.isFinite else {
            return (0, "mud測定なしのため変更なし")
        }
        let cleanLevel = InternalAudioJudgementPolicy.routeLowMidCleanMudDB
        guard mudLevelDB > cleanLevel else {
            return (0, "mud \(String(format: "%.1f", mudLevelDB)) dB / 過剰なし")
        }

        let warningLevel = InternalAudioJudgementPolicy.severityLimit(for: NoiseMeasurementID.mud)?.warningDB ?? -4
        let pressureRange = max(warningLevel - cleanLevel, 0.1)
        let pressure = MasteringSignalMath.clamped(
            Float((mudLevelDB - cleanLevel) / pressureRange),
            min: 0,
            max: 1
        )
        let currentMaximumCut = max(0, -settings.lowMidGain * 0.45)
            + max(0, settings.lowShelfGain - 0.70) * 0.10
        let adjustmentDB = -currentMaximumCut * pressure
        return (
            adjustmentDB,
            "mud \(String(format: "%.1f", mudLevelDB)) dB / 実測過剰に応じて \(String(format: "%.2f", adjustmentDB)) dB"
        )
    }

    private func formatToneLevel(_ value: Double) -> String {
        String(format: "%.2f dB", value)
    }

    private func sibilanceAwareBrillianceLift(channel: [Float], sampleRate: Double, gain: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let sibilanceStartBin = clampedBin(5_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let sibilanceEndBin = clampedBin(8_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let brillianceStartBin = clampedBin(9_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let brillianceEndBin = clampedBin(12_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        guard sibilanceEndBin > sibilanceStartBin, brillianceEndBin > brillianceStartBin else { return channel }

        var sibilanceEnergy = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            sibilanceEnergy[frameIndex] = bandEnergy(
                spectrogram: spectrogram,
                frameIndex: frameIndex,
                startBin: sibilanceStartBin,
                endBin: sibilanceEndBin
            )
        }
        let transientThreshold = max(SpectralDSP.percentile(sibilanceEnergy, 50) * 1.05, 1e-7)

        for frameIndex in 0..<spectrogram.frameCount {
            let frameGain = sibilanceEnergy[frameIndex] > transientThreshold ? 1.0 : gain
            guard frameGain > 1.0001 else { continue }
            for binIndex in brillianceStartBin...brillianceEndBin {
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: frameGain)
            }
        }

        return SpectralDSP.istft(spectrogram)
    }

    private func bandEnergy(spectrogram: Spectrogram, frameIndex: Int, startBin: Int, endBin: Int) -> Float {
        var sum: Float = 0
        for binIndex in startBin...endBin {
            let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            sum += magnitude * magnitude
        }
        return sum / Float(max(1, endBin - startBin + 1))
    }

    private func clampedBin(_ frequency: Double, frequencyStep: Double, binCount: Int) -> Int {
        min(max(Int(frequency / frequencyStep), 0), binCount - 1)
    }
}
