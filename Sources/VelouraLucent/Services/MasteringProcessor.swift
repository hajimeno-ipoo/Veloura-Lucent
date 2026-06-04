import Foundation

struct MasteringProcessor {
    func process(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot? = nil,
        originalReferenceSignal: AudioSignal? = nil,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot? = nil,
        diagnosticOutputDirectory: URL? = nil,
        logger: AudioProcessingLogger? = nil
    ) -> AudioSignal {
        let dynamicsRetention = MasteringSignalMath.clamped(settings.dynamicsRetention, min: 0, max: 1)
        let finishingIntensity = MasteringSignalMath.clamped(settings.finishingIntensity, min: 0, max: 1)
        let loudnessPolicy = settings.loudnessAdjustmentPolicy
        let routePlan = MasteringRoutePlan.make(
            analysis: analysis,
            settings: settings,
            noiseMeasurements: referenceNoiseMeasurements
        )
        logMasteringRoutePlan(routePlan, logger: logger)
        saveDiagnostic(signal, to: diagnosticOutputDirectory, order: 0, id: "input", label: "補正済み入力", logger: logger)

        logger?.start(.tone)
        logger?.log(MasteringStep.tone.rawValue)
        var current = measure(label: "音色", logger: logger, progressStep: .tone) {
            applyTone(signal: signal, analysis: analysis, settings: settings, finishingIntensity: finishingIntensity)
        }
        saveDiagnostic(current, to: diagnosticOutputDirectory, order: 1, id: "tone", label: "音色調整後", logger: logger)

        let deEssDecision = routePlan.decision(for: .deEss)
        if deEssDecision.action == .skip {
            logger?.skip(.deEss, reason: deEssDecision.reason)
            logger?.log("ディエッサー: 早期終了 - \(deEssDecision.reason)")
        } else {
            logger?.start(.deEss)
            logger?.log(MasteringStep.deEss.rawValue)
            current = measure(label: "ディエッサー", logger: logger, progressStep: .deEss) {
                applyDeEsser(signal: current, analysis: analysis, settings: settings)
            }
        }
        saveDiagnostic(current, to: diagnosticOutputDirectory, order: 2, id: "deEss", label: "ディエッサー後", logger: logger)

        logger?.start(.dynamics)
        logger?.log(MasteringStep.dynamics.rawValue)
        current = measure(label: "ダイナミクス", logger: logger, progressStep: .dynamics) {
            applyMultibandCompression(
                signal: current,
                analysis: analysis,
                settings: settings.multibandCompression,
                dynamicsRetention: dynamicsRetention,
                finishingIntensity: finishingIntensity
            )
        }
        saveDiagnostic(current, to: diagnosticOutputDirectory, order: 3, id: "dynamics", label: "ダイナミクス後", logger: logger)

        let saturateDecision = routePlan.decision(for: .saturate)
        if saturateDecision.action == .skip {
            logger?.skip(.saturate, reason: saturateDecision.reason)
            logger?.log("倍音: 早期終了 - \(saturateDecision.reason)")
        } else {
            logger?.start(.saturate)
            logger?.log(MasteringStep.saturate.rawValue)
            current = measure(label: "倍音", logger: logger, progressStep: .saturate) {
                applySaturation(signal: current, amount: effectiveSaturation(settings.saturationAmount, dynamicsRetention: dynamicsRetention, finishingIntensity: finishingIntensity))
            }
        }
        saveDiagnostic(current, to: diagnosticOutputDirectory, order: 4, id: "saturate", label: "倍音調整後", logger: logger)

        let airDecision = routePlan.decision(for: .air)
        if airDecision.action == .skip {
            logger?.skip(.air, reason: airDecision.reason)
            logger?.log("空気感: 早期終了 - \(airDecision.reason)")
        } else {
            logger?.start(.air)
            logger?.log(MasteringStep.air.rawValue)
            current = measure(label: "空気感", logger: logger, progressStep: .air) {
                MasteringAirEnhancer().process(
                    signal: current,
                    analysis: analysis,
                    settings: settings,
                    finishingIntensity: finishingIntensity
                )
            }
        }
        saveDiagnostic(current, to: diagnosticOutputDirectory, order: 5, id: "air", label: "空気感調整後", logger: logger)

        let stereoDecision = routePlan.decision(for: .stereo)
        if stereoDecision.action == .skip {
            logger?.skip(.stereo, reason: stereoDecision.reason)
            logger?.log("広がり: 早期終了 - \(stereoDecision.reason)")
        } else {
            logger?.start(.stereo)
            logger?.log(MasteringStep.stereo.rawValue)
            current = measure(label: "広がり", logger: logger, progressStep: .stereo) {
                applyStereoWidth(signal: current, targetWidth: settings.stereoWidth)
            }
        }
        saveDiagnostic(current, to: diagnosticOutputDirectory, order: 6, id: "stereo", label: "ステレオ調整後", logger: logger)

        logger?.start(.loudness)
        logger?.log(MasteringStep.loudness.rawValue)
        let effectiveLoudnessTarget = effectiveTargetLoudness(
            settings.targetLoudness,
            dynamicsRetention: dynamicsRetention,
            finishingIntensity: finishingIntensity
        )
        let loudnessBaseline = MasteringAnalysisService.integratedLoudness(signal: current)
        let guidedLoudnessTarget = guidedLoudnessTarget(
            currentLoudness: loudnessBaseline,
            requestedTargetLKFS: effectiveLoudnessTarget,
            policy: loudnessPolicy,
            logger: logger
        )
        let lowBodyProtectedLoud = measure(label: "ラウドネス", logger: logger, progressStep: .loudness) {
            let loud = applyLoudness(
                signal: current,
                targetLKFS: guidedLoudnessTarget,
                peakCeilingDB: settings.peakCeilingDB
            )
            let loudnessReference = applyLoudness(
                signal: signal,
                targetLKFS: guidedLoudnessTarget,
                peakCeilingDB: settings.peakCeilingDB
            )
            let originalLoudnessReference = originalReferenceSignal.map {
                applyLoudness(
                    signal: $0,
                    targetLKFS: guidedLoudnessTarget,
                    peakCeilingDB: settings.peakCeilingDB
                )
            }
            return MasteringSignalMath.enforcePeakCeiling(
                signal: MasteringLowBodyProtector.process(
                    signal: loud,
                    reference: loudnessReference,
                    activityReference: signal,
                    musicalReference: originalLoudnessReference
                ),
                peakCeilingDB: settings.peakCeilingDB
            )
        }
        saveDiagnostic(lowBodyProtectedLoud, to: diagnosticOutputDirectory, order: 7, id: "loudness", label: "ラウドネス調整後", logger: logger)

        let highReturnDecision = routePlan.decision(for: .highReturnGuard)
        let guarded: AudioSignal
        if highReturnDecision.action == .skip {
            logger?.skip(.highReturnGuard, reason: highReturnDecision.reason)
            logger?.log("高域戻りガード: 早期終了 - \(highReturnDecision.reason)")
            guarded = lowBodyProtectedLoud
        } else {
            logger?.start(.highReturnGuard)
            logger?.log(MasteringStep.highReturnGuard.rawValue)
            guarded = measure(label: "高域戻りガード", logger: logger, progressStep: .highReturnGuard) {
                applyHighReturnGuard(
                    signal: lowBodyProtectedLoud,
                    analysis: analysis,
                    settings: settings,
                    finishingIntensity: finishingIntensity
                )
            }
        }
        saveDiagnostic(guarded, to: diagnosticOutputDirectory, order: 8, id: "highReturnGuard", label: "高域戻りガード後", logger: logger)

        let noiseReturnDecision = routePlan.decision(for: .noiseReturnGuard)
        logger?.start(.noiseReturnGuard)
        logger?.log(MasteringStep.noiseReturnGuard.rawValue)
        let noiseGuarded = measure(label: "ノイズ戻りガード", logger: logger, progressStep: .noiseReturnGuard) {
            applyNoiseReturnGuard(
                signal: guarded,
                reference: signal,
                logger: logger,
                maxPasses: noiseReturnDecision.action == .light ? 1 : 3
            )
        }
        saveDiagnostic(noiseGuarded, to: diagnosticOutputDirectory, order: 9, id: "noiseReturnGuard", label: "ノイズ戻りガード後", logger: logger)
        logger?.start(.highPreserve)
        logger?.log(MasteringStep.highPreserve.rawValue)
        let (mastered, highFloorReferenceLevels) = measure(label: "マスタリング/計測: 高域保持", logger: logger, progressStep: .highPreserve) {
            let referenceLevels = MasteringHighFloorPreserver.makeReferenceLevels(
                reference: signal,
                originalReference: originalReferenceSignal
            )
            logger?.log("高域保持/基準測定: 2工程で再利用")
            return (
                MasteringHighFloorPreserver.preserve(
                    signal: noiseGuarded,
                    reference: signal,
                    referenceLevels: referenceLevels,
                    referenceNoiseMeasurements: referenceNoiseMeasurements,
                    originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
                    peakCeilingDB: settings.peakCeilingDB,
                    logger: logger
                ),
                referenceLevels
            )
        }
        saveDiagnostic(mastered, to: diagnosticOutputDirectory, order: 10, id: "highPreserve", label: "高域保持後", logger: logger)
        var finalNoiseReturnReferenceLevels: [NoiseReturnHighBandReferenceLevel]?
        let allowsOriginalReferenceHighRecovery = MasteringHighFloorPreserver.originalReferenceNeedsHighRecovery(highFloorReferenceLevels)
        logger?.start(.finalNoiseCeiling)
        logger?.log(MasteringStep.finalNoiseCeiling.rawValue)
        let finalGuarded = measure(label: "マスタリング/計測: 最終ノイズ上限", logger: logger, progressStep: .finalNoiseCeiling) {
            applyFinalNoiseReturnCeiling(
                signal: mastered,
                reference: signal,
                referenceHighBandLevels: &finalNoiseReturnReferenceLevels,
                referenceNoiseMeasurements: referenceNoiseMeasurements,
                originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
                allowsOriginalReferenceHighRecovery: allowsOriginalReferenceHighRecovery,
                peakCeilingDB: settings.peakCeilingDB,
                logger: logger
            )
        }
        saveDiagnostic(finalGuarded, to: diagnosticOutputDirectory, order: 11, id: "finalNoiseCeiling", label: "最終ノイズ上限後", logger: logger)
        logger?.start(.finalHighPreserve)
        logger?.log(MasteringStep.finalHighPreserve.rawValue)
        let finalHighPreserved = measure(label: "マスタリング/計測: 最終高域保持", logger: logger, progressStep: .finalHighPreserve) {
            MasteringHighFloorPreserver.preserve(
                signal: finalGuarded,
                reference: signal,
                referenceLevels: highFloorReferenceLevels,
                referenceNoiseMeasurements: referenceNoiseMeasurements,
                originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
                peakCeilingDB: settings.peakCeilingDB,
                logger: logger
            )
        }
        saveDiagnostic(finalHighPreserved, to: diagnosticOutputDirectory, order: 12, id: "finalHighPreserve", label: "最終高域保持後", logger: logger)
        logger?.start(.finalLoudnessRestore)
        logger?.log(MasteringStep.finalLoudnessRestore.rawValue)
        let finalLoudnessRestored = measure(label: "マスタリング/計測: 最終音量復帰", logger: logger, progressStep: .finalLoudnessRestore) {
            restoreFinalLoudnessAfterGuards(
                signal: finalHighPreserved,
                reference: signal,
                referenceNoiseMeasurements: referenceNoiseMeasurements,
                originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
                targetLKFS: guidedLoudnessTarget,
                requestedTargetLKFS: effectiveLoudnessTarget,
                peakCeilingDB: settings.peakCeilingDB,
                policy: loudnessPolicy,
                logger: logger
            )
        }
        saveDiagnostic(finalLoudnessRestored, to: diagnosticOutputDirectory, order: 13, id: "finalLoudnessRestore", label: "最終音量復帰後", logger: logger)
        logger?.start(.finalNoiseConfirm)
        logger?.log(MasteringStep.finalNoiseConfirm.rawValue)
        let finalNoiseConfirmed = measure(label: "マスタリング/計測: 最終ノイズ確認", logger: logger, progressStep: .finalNoiseConfirm) {
            applyFinalNoiseReturnCeiling(
                signal: finalLoudnessRestored,
                reference: signal,
                referenceHighBandLevels: &finalNoiseReturnReferenceLevels,
                referenceNoiseMeasurements: referenceNoiseMeasurements,
                originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
                loudnessRestoreFallback: finalHighPreserved,
                allowsOriginalReferenceHighRecovery: allowsOriginalReferenceHighRecovery,
                peakCeilingDB: settings.peakCeilingDB,
                logger: logger
            )
        }
        saveDiagnostic(finalNoiseConfirmed, to: diagnosticOutputDirectory, order: 14, id: "finalNoiseConfirm", label: "最終ノイズ確認後", logger: logger)
        let finalLowMidProtected = measure(label: "マスタリング/計測: 最終低中域保護", logger: logger) {
            let activityReference = loudnessMatchedFinalLowMidReference(
                reference: signal,
                target: finalNoiseConfirmed
            )
            guard let protected = MasteringLowBodyProtector.protectActiveLowMidMinimum(
                signal: finalNoiseConfirmed,
                activityReference: activityReference
            ) else {
                logger?.log("最終低中域保護: 対象なし")
                return finalNoiseConfirmed
            }
            let candidate = MasteringSignalMath.enforcePeakCeiling(
                signal: protected,
                peakCeilingDB: settings.peakCeilingDB
            )
            let probePlan = MasteringNoiseReturnSupport.noiseReturnProbePlan(for: finalNoiseConfirmed)
            let baseProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: finalNoiseConfirmed, plan: probePlan)
            let candidateProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: candidate, plan: probePlan)
            guard isFinalLoudnessRestoreNoiseSafe(
                baseProbe: baseProbe,
                candidateProbe: candidateProbe,
                referenceMeasurements: referenceNoiseMeasurements,
                originalReferenceMeasurements: originalReferenceNoiseMeasurements
            ), isFinalLowMidBodyNoiseSafe(
                base: finalNoiseConfirmed,
                candidate: candidate,
                referenceMeasurements: referenceNoiseMeasurements,
                originalReferenceMeasurements: originalReferenceNoiseMeasurements
            ), isFinalLoudnessRestoreMudBalanceSafe(base: finalNoiseConfirmed, candidate: candidate) else {
                logger?.log("最終低中域保護: ノイズ保護で見送り")
                return finalNoiseConfirmed
            }
            logger?.log("最終低中域保護: 演奏中の150Hz〜500Hzを最大+0.5dB")
            return candidate
        }
        saveDiagnostic(finalLowMidProtected, to: diagnosticOutputDirectory, order: 15, id: "finalLowMidBody", label: "最終低中域保護後", logger: logger)
        logger?.start(.finalLoudnessBounds)
        logger?.log(MasteringStep.finalLoudnessBounds.rawValue)
        let finalLoudnessBounded = measure(label: "マスタリング/計測: 最終音量上限", logger: logger, progressStep: .finalLoudnessBounds) {
            enforceFinalLoudnessPolicyBounds(
                signal: finalLowMidProtected,
                baselineLoudness: loudnessBaseline,
                referenceNoiseMeasurements: referenceNoiseMeasurements,
                originalReferenceNoiseMeasurements: originalReferenceNoiseMeasurements,
                peakCeilingDB: settings.peakCeilingDB,
                policy: loudnessPolicy,
                logger: logger
            )
        }
        saveDiagnostic(finalLoudnessBounded, to: diagnosticOutputDirectory, order: 16, id: "finalLoudnessBounds", label: "マスタリング最終", logger: logger)
        logger?.log("ルート/マスタリング/実行工程数: \(routePlan.runLikeCount)/\(MasteringRouteStep.allCases.count)")
        logger?.log("ルート/マスタリング/スキップ工程数: \(MasteringRouteStep.allCases.count - routePlan.runLikeCount)/\(MasteringRouteStep.allCases.count)")
        return finalLoudnessBounded
    }

    private func saveDiagnostic(_ signal: AudioSignal, to directory: URL?, order: Int, id: String, label: String, logger: AudioProcessingLogger?) {
        AudioStageDiagnostics.save(
            signal,
            to: directory,
            domain: "mastering",
            order: order,
            id: id,
            label: label,
            logger: logger
        )
    }

    private func measure<T>(
        label: String,
        logger: AudioProcessingLogger?,
        progressStep: MasteringStep? = nil,
        work: () -> T
    ) -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = work()
        let end = DispatchTime.now().uptimeNanoseconds
        logger?.log("\(label): \(formatProcessingDuration(Double(end - start) / 1_000_000_000))")
        if let progressStep {
            logger?.complete(progressStep)
        }
        return result
    }

    private func applyTone(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings, finishingIntensity: Float) -> AudioSignal {
        let lowAdjustmentDB = settings.lowShelfGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 18), min: -0.25, max: 1.2)
        let lowMidAdjustmentDB = settings.lowMidGain - MasteringSignalMath.clamped(Float((analysis.lowBandLevelDB - analysis.midBandLevelDB) / 16), min: -0.2, max: 0.7)
        let roomAdjustmentDB = min(0, settings.lowMidGain * 0.45) - max(0, settings.lowShelfGain - 0.70) * 0.10
        let presenceAdjustmentDB = settings.presenceGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 16), min: -0.2, max: 0.8) - analysis.harshnessScore * 0.32
        let highAdjustmentDB = settings.highShelfGain + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 18), min: -0.25, max: 0.9) - analysis.harshnessScore * 0.55
        let toneScale = 0.72 + finishingIntensity * 0.46

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
            let high = SpectralDSP.highPass(channel, cutoff: 10_000, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                channel[index]
                    + low[index] * lowDelta
                    + lowMid[index] * lowMidDelta
                    + roomLowMid[index] * roomDelta
                    + presence[index] * presenceDelta
                    + high[index] * highDelta
            }
        }

        return applySibilanceAwareBrillianceLift(
            signal: AudioSignal(channels: channels, sampleRate: signal.sampleRate),
            analysis: analysis,
            settings: settings,
            finishingIntensity: finishingIntensity
        )
    }

    private func applySibilanceAwareBrillianceLift(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float
    ) -> AudioSignal {
        let highDeficit = MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 24), min: 0, max: 0.45)
        let baseLiftDB = settings.highShelfGain * 1.05 + highDeficit - analysis.harshnessScore * 0.22
        let liftDB = MasteringSignalMath.clamped(baseLiftDB * (0.70 + finishingIntensity * 0.22), min: 0, max: 1.00)
        guard liftDB > 0.08 else { return signal }

        let gain = powf(10, liftDB / 20)
        let sampleRate = signal.sampleRate
        let channels = mapChannelsConcurrently(signal.channels) {
            sibilanceAwareBrillianceLift(channel: $0, sampleRate: sampleRate, gain: gain)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
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

    private func applyDeEsser(signal: AudioSignal, analysis: MasteringAnalysis, settings: MasteringSettings) -> AudioSignal {
        guard settings.deEsserAmount > 0.001 else { return signal }

        let threshold = powf(10, settings.deEsserThresholdDB / 20)
        let attackCoeff = expf(-1 / max(Float(signal.sampleRate) * 0.002, 1))
        let releaseCoeff = expf(-1 / max(Float(signal.sampleRate) * 0.090, 1))
        let adaptiveAmount = settings.deEsserAmount * (0.55 + analysis.harshnessScore * 0.75)
        let maxReduction = min(0.68, 0.18 + analysis.harshnessScore * 0.28 + settings.deEsserAmount * 0.20)

        let channels = signal.channels.map { channel in
            let detectionBand = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 4_500, sampleRate: signal.sampleRate),
                cutoff: 9_000,
                sampleRate: signal.sampleRate
            )
            let reductionBand = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 5_500, sampleRate: signal.sampleRate),
                cutoff: 11_000,
                sampleRate: signal.sampleRate
            )
            let detectorRMS = sqrtf(detectionBand.reduce(Float.zero) { partial, sample in
                partial + sample * sample
            } / Float(max(detectionBand.count, 1)))
            let adaptiveThreshold = max(1e-5, min(threshold, detectorRMS))

            var envelope: Float = 0
            return channel.indices.map { index in
                let detectorSample = detectionBand[index]
                let level = abs(detectorSample)
                if level > envelope {
                    envelope = attackCoeff * envelope + (1 - attackCoeff) * level
                } else {
                    envelope = releaseCoeff * envelope + (1 - releaseCoeff) * level
                }

                guard envelope > adaptiveThreshold else { return channel[index] }
                let excess = min(3.0, max(0, (envelope - adaptiveThreshold) / max(adaptiveThreshold, 1e-6)))
                let reduction = min(maxReduction, excess * adaptiveAmount * 0.40)
                return channel[index] - reductionBand[index] * reduction
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyMultibandCompression(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MultibandCompressionSettings,
        dynamicsRetention: Float,
        finishingIntensity: Float
    ) -> AudioSignal {
        let adjustedSettings = tunedCompressionSettings(
            base: settings,
            analysis: analysis,
            dynamicsRetention: dynamicsRetention,
            finishingIntensity: finishingIntensity
        )
        let channels = signal.channels.map { channel in
            let low = SpectralDSP.lowPass(channel, cutoff: 160, sampleRate: signal.sampleRate)
            let mid = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 160, sampleRate: signal.sampleRate),
                cutoff: 3_200,
                sampleRate: signal.sampleRate
            )
            let high = SpectralDSP.lowPass(
                SpectralDSP.highPass(channel, cutoff: 3_200, sampleRate: signal.sampleRate),
                cutoff: 9_000,
                sampleRate: signal.sampleRate
            )
            let air = SpectralDSP.highPass(channel, cutoff: 9_000, sampleRate: signal.sampleRate)
            let compressedLow = compressBand(low, sampleRate: signal.sampleRate, settings: adjustedSettings.low)
            let compressedMid = compressBand(mid, sampleRate: signal.sampleRate, settings: adjustedSettings.mid)
            let compressedHigh = compressBand(high, sampleRate: signal.sampleRate, settings: adjustedSettings.high)

            return channel.indices.map { index in
                compressedLow[index] + compressedMid[index] + compressedHigh[index] + air[index]
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func tunedCompressionSettings(
        base: MultibandCompressionSettings,
        analysis: MasteringAnalysis,
        dynamicsRetention: Float,
        finishingIntensity: Float
    ) -> MultibandCompressionSettings {
        let compressionScale = MasteringSignalMath.clamped(0.56 + finishingIntensity * 0.58 - dynamicsRetention * 0.24, min: 0.35, max: 1.10)
        let makeupScale = MasteringSignalMath.clamped(0.62 + finishingIntensity * 0.46 - dynamicsRetention * 0.22, min: 0.35, max: 1.00)
        let thresholdOffset = dynamicsRetention * 1.4 - finishingIntensity * 0.45
        let lowMakeup = (base.low.makeupGainDB + MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.lowBandLevelDB) / 20), min: -0.15, max: 0.25)) * makeupScale
        let midMakeup = (base.mid.makeupGainDB + MasteringSignalMath.clamped(Float((analysis.highBandLevelDB - analysis.midBandLevelDB) / 24), min: -0.10, max: 0.12)) * makeupScale
        let highThreshold = base.high.thresholdDB - analysis.harshnessScore * 1.2
        let highRatio = scaledRatio(base.high.ratio + analysis.harshnessScore * 0.18, scale: compressionScale)
        let highMakeup = max(-0.2, (base.high.makeupGainDB - analysis.harshnessScore * 0.14) * makeupScale)

        return MultibandCompressionSettings(
            low: BandCompressorSettings(
                thresholdDB: base.low.thresholdDB + thresholdOffset,
                ratio: scaledRatio(base.low.ratio, scale: compressionScale),
                attackMs: base.low.attackMs,
                releaseMs: base.low.releaseMs,
                makeupGainDB: lowMakeup
            ),
            mid: BandCompressorSettings(
                thresholdDB: base.mid.thresholdDB + thresholdOffset,
                ratio: scaledRatio(base.mid.ratio, scale: compressionScale),
                attackMs: base.mid.attackMs,
                releaseMs: base.mid.releaseMs,
                makeupGainDB: midMakeup
            ),
            high: BandCompressorSettings(
                thresholdDB: highThreshold + thresholdOffset,
                ratio: highRatio,
                attackMs: base.high.attackMs,
                releaseMs: base.high.releaseMs,
                makeupGainDB: highMakeup
            )
        )
    }

    private func compressBand(_ samples: [Float], sampleRate: Double, settings: BandCompressorSettings) -> [Float] {
        guard !samples.isEmpty else { return samples }

        let threshold = powf(10, settings.thresholdDB / 20)
        let makeupGain = powf(10, settings.makeupGainDB / 20)
        let attackCoeff = expf(-1 / max(Float(sampleRate) * settings.attackMs * 0.001, 1))
        let releaseCoeff = expf(-1 / max(Float(sampleRate) * settings.releaseMs * 0.001, 1))

        var envelope: Float = 0
        var result = Array(repeating: Float.zero, count: samples.count)

        let kneeWidth: Float = 3

        for index in samples.indices {
            let input = samples[index]
            let level = abs(input)
            if level > envelope {
                envelope = attackCoeff * envelope + (1 - attackCoeff) * level
            } else {
                envelope = releaseCoeff * envelope + (1 - releaseCoeff) * level
            }

            var gain: Float = 1
            if envelope > threshold {
                let envelopeDB = 20 * log10f(max(envelope, 1e-6))
                let gainReductionDB = compressionGainReductionDB(
                    envelopeDB: envelopeDB,
                    thresholdDB: settings.thresholdDB,
                    ratio: settings.ratio,
                    kneeWidthDB: kneeWidth
                )
                gain = powf(10, gainReductionDB / 20)
            }

            result[index] = input * gain * makeupGain
        }

        return result
    }

    private func applySaturation(signal: AudioSignal, amount: Float) -> AudioSignal {
        let drive = 1 + amount * 2.8
        let mix = min(max(amount * 0.75, 0), 0.4)

        let channels = signal.channels.map { channel in
            channel.map { sample in
                let saturated = tanhf(sample * drive)
                return sample * (1 - mix) + saturated * mix
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyStereoWidth(signal: AudioSignal, targetWidth: Float) -> AudioSignal {
        guard signal.channels.count >= 2 else { return signal }
        let left = signal.channels[0]
        let right = signal.channels[1]
        let count = min(left.count, right.count)
        guard count > 0 else { return signal }

        let lowLeft = SpectralDSP.lowPass(left, cutoff: 180, sampleRate: signal.sampleRate)
        let lowRight = SpectralDSP.lowPass(right, cutoff: 180, sampleRate: signal.sampleRate)
        let highLeft = zip(left, lowLeft).map(-)
        let highRight = zip(right, lowRight).map(-)

        var widenedLeft = Array(repeating: Float.zero, count: count)
        var widenedRight = Array(repeating: Float.zero, count: count)
        for index in 0..<count {
            let highMid = (highLeft[index] + highRight[index]) * 0.5
            let highSide = (highLeft[index] - highRight[index]) * 0.5 * targetWidth
            widenedLeft[index] = lowLeft[index] + highMid + highSide
            widenedRight[index] = lowRight[index] + highMid - highSide
        }

        var channels = signal.channels
        channels[0] = widenedLeft
        channels[1] = widenedRight
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyHighReturnGuard(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float
    ) -> AudioSignal {
        let reduction = highReturnGuardReduction(
            analysis: analysis,
            settings: settings,
            finishingIntensity: finishingIntensity
        )
        guard reduction > 0.001 else { return signal }

        let channels = signal.channels.map { channel in
            let high = SpectralDSP.highPass(channel, cutoff: 10_000, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                channel[index] - high[index] * reduction
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func highReturnGuardReduction(
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float
    ) -> Float {
        let harshnessPressure = max(0, analysis.harshnessScore - 0.62) * 0.24
        let airBoostPressure = max(0, settings.highShelfGain - 0.56) * 0.08
        let finishPressure = max(0, finishingIntensity - 0.72) * 0.05
        return MasteringSignalMath.clamped(harshnessPressure + airBoostPressure + finishPressure, min: 0, max: 0.07)
    }

    private func applyNoiseReturnGuard(
        signal: AudioSignal,
        reference: AudioSignal,
        logger: AudioProcessingLogger?,
        maxPasses: Int = 8
    ) -> AudioSignal {
        logger?.log("ノイズ戻り: 専用測定を開始")
        let probePlan = MasteringNoiseReturnSupport.noiseReturnProbePlan(for: reference)
        let referenceProbe = MasteringNoiseReturnSupport.noiseReturnProbe(
            signal: reference,
            plan: probePlan
        )
        return adaptiveNoiseLimit(
            signal: signal,
            probePlan: probePlan,
            referenceProbe: referenceProbe,
            fullRangeReferenceProbe: maxPasses > 1
                ? MasteringNoiseReturnSupport.noiseReturnProbe(signal: reference, plan: MasteringNoiseReturnSupport.fullRangeNoiseReturnProbePlan(for: reference))
                : nil,
            rules: InternalAudioJudgementPolicy.masteringNoiseReturnLimits,
            logger: logger,
            maxPasses: maxPasses
        )
    }

    private func adaptiveNoiseLimit(
        signal: AudioSignal,
        probePlan: NoiseReturnProbePlan,
        referenceProbe: NoiseReturnProbe,
        fullRangeReferenceProbe: NoiseReturnProbe?,
        rules: [NoiseReturnLimit],
        logger: AudioProcessingLogger?,
        maxPasses: Int = 8
    ) -> AudioSignal {
        var currentSignal = signal
        var measurementCount = 0
        var completionLog = "ノイズ戻り: 安全上限に到達"
        let adaptivePasses = min(maxPasses, 3)
        var referenceHighBandLevels: [NoiseReturnHighBandReferenceLevel]?

        logger?.log("ノイズ戻り: 一括判定を開始")
        if probePlan.usesRepresentativeWindows {
            logger?.detail("\(probePlan.selectedWindowCount)/\(probePlan.totalWindowCount) 区間を確認中", for: .noiseReturnGuard)
            logger?.log("ノイズ戻り/軽量測定: \(probePlan.selectedWindowCount)/\(probePlan.totalWindowCount)区間")
        }
        for _ in 0..<adaptivePasses {
            let currentMeasurements = MasteringNoiseReturnSupport.noiseReturnProbe(signal: currentSignal, plan: probePlan)
            measurementCount += 1
            logger?.detail("\(measurementCount)/\(adaptivePasses) 回目を確認中", for: .noiseReturnGuard)
            logger?.log("ノイズ戻り/軽量判定: \(measurementCount)/\(adaptivePasses)")

            let strongestExcess = rules
                .compactMap { rule -> (rule: NoiseReturnLimit, excessDB: Double)? in
                    guard let reference = referenceProbe.comparableLevel(for: rule.id),
                          let current = currentMeasurements.comparableLevel(for: rule.id)
                    else { return nil }
                    let target = reference + rule.allowedReturnDB
                    return (rule, max(0, current - target))
                }
                .max { $0.excessDB < $1.excessDB }

            guard let strongestExcess, strongestExcess.excessDB > 0.1 else {
                if maxPasses == 1 {
                    logger?.log("ノイズ戻り/軽量判定回数: \(measurementCount)")
                    logger?.log("ノイズ戻りガード: 早期終了 - 初回測定で問題なし")
                    logger?.log("ノイズ戻り: 目標到達")
                    logger?.log("ノイズ戻り: 完了")
                    return currentSignal
                }
                logger?.log("ノイズ戻り: 目標到達")
                completionLog = "ノイズ戻り: 完了"
                break
            }
            logger?.log("ノイズ戻り/判定: \(MasteringNoiseReturnSupport.noiseReturnDisplayName(for: strongestExcess.rule.id)) +\(String(format: "%.1f", strongestExcess.excessDB)) dB")
            let gain = MasteringNoiseReturnSupport.noiseReturnGain(for: strongestExcess.rule, excessDB: strongestExcess.excessDB)
            guard let candidate = MasteringNoiseReturnSupport.constrainedNoiseReturnCandidate(
                signal: currentSignal,
                guardReferenceLevels: MasteringNoiseReturnSupport.resolvedNoiseReturnHighBandReferenceLevels(
                    &referenceHighBandLevels,
                    signal: signal
                ),
                rule: strongestExcess.rule,
                gain: gain,
                logger: logger
            ) else {
                completionLog = "ノイズ戻り: 高域保護で追加削減を停止"
                break
            }
            currentSignal = candidate
        }

        var finalConfirmationCount = 0
        if maxPasses > 1,
           let fullRangeReferenceProbe,
           let finalCorrection = fullRangeNoiseReturnCorrection(
            signal: currentSignal,
            referenceProbe: fullRangeReferenceProbe,
            rules: rules
            ) {
            finalConfirmationCount = 1
            logger?.detail("最終確認 1/1", for: .noiseReturnGuard)
            logger?.log("ノイズ戻り/最終確認: 全体測定 1/1")
            logger?.log("ノイズ戻り: 最終確認で追加補正")
            if let candidate = MasteringNoiseReturnSupport.constrainedNoiseReturnCandidate(
                signal: currentSignal,
                guardReferenceLevels: MasteringNoiseReturnSupport.resolvedNoiseReturnHighBandReferenceLevels(
                    &referenceHighBandLevels,
                    signal: signal
                ),
                rule: finalCorrection.rule,
                gain: finalCorrection.gain,
                logger: logger
            ) {
                currentSignal = candidate
            } else {
                logger?.log("ノイズ戻り: 最終確認を高域保護で見送り")
            }
        }
        if finalConfirmationCount > 0 {
            logger?.log("ノイズ戻り/最終確認回数: \(finalConfirmationCount)")
        }

        logger?.log("ノイズ戻り/軽量判定回数: \(measurementCount)")
        logger?.log(completionLog)
        return currentSignal
    }

    private func fullRangeNoiseReturnCorrection(
        signal: AudioSignal,
        referenceProbe: NoiseReturnProbe,
        rules: [NoiseReturnLimit]
    ) -> (rule: NoiseReturnLimit, gain: Float)? {
        let currentMeasurements = MasteringNoiseReturnSupport.noiseReturnProbe(signal: signal, plan: MasteringNoiseReturnSupport.fullRangeNoiseReturnProbePlan(for: signal))
        guard let strongestExcess = rules
            .compactMap({ rule -> (rule: NoiseReturnLimit, excessDB: Double)? in
                guard let reference = referenceProbe.comparableLevel(for: rule.id),
                      let current = currentMeasurements.comparableLevel(for: rule.id)
                else { return nil }
                let target = reference + rule.allowedReturnDB
                return (rule, max(0, current - target))
            })
            .max(by: { $0.excessDB < $1.excessDB }),
            strongestExcess.excessDB > 0.1
        else {
            return nil
        }
        let gain = MasteringNoiseReturnSupport.noiseReturnGain(for: strongestExcess.rule, excessDB: strongestExcess.excessDB)
        return (strongestExcess.rule, gain)
    }

    private func restoreFinalLoudnessAfterGuards(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        targetLKFS: Float,
        requestedTargetLKFS: Float,
        peakCeilingDB: Float,
        policy: LoudnessAdjustmentPolicy,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let currentLoudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        guard currentLoudness.isFinite, currentLoudness > -69 else {
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }

        let loudnessDeficitDB = Double(targetLKFS - currentLoudness)
        let peak = max(MasteringAnalysisService.approximateTruePeak(signal.channels), 1e-6)
        let currentPeakDB = 20 * log10(Double(peak))
        let peakHeadroomDB = max(0, Double(peakCeilingDB) - currentPeakDB)
        let safetyRestoreLimitDB = 2.0
        let requestedTargetHeadroomDB = max(
            0,
            Double(requestedTargetLKFS - currentLoudness) + policy.targetOvershootLimitDB
        )
        let requestedGainDB: Double
        if loudnessDeficitDB > 0.35 {
            requestedGainDB = min(loudnessDeficitDB, peakHeadroomDB, policy.finalRestoreLimitDB)
        } else {
            requestedGainDB = min(
                safetyRestoreLimitDB,
                peakHeadroomDB,
                policy.finalRestoreLimitDB,
                requestedTargetHeadroomDB
            )
        }
        guard requestedGainDB > 0.25 else {
            logger?.log("最終音量復帰: ピーク余裕不足")
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }

        let candidate = MasteringSignalMath.enforcePeakCeiling(
            signal: MasteringSignalMath.applyGain(signal: signal, gainDB: requestedGainDB),
            peakCeilingDB: peakCeilingDB
        )
        let probePlan = MasteringNoiseReturnSupport.noiseReturnProbePlan(for: signal)
        let baseProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: signal, plan: probePlan)
        let candidateProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: candidate, plan: probePlan)
        guard isFinalLoudnessRestoreNoiseSafe(
            baseProbe: baseProbe,
            candidateProbe: candidateProbe,
            referenceMeasurements: referenceNoiseMeasurements,
            originalReferenceMeasurements: originalReferenceNoiseMeasurements
        ), isFinalLoudnessRestoreMudBalanceSafe(base: signal, candidate: candidate) else {
            logger?.log("最終音量復帰: ノイズ保護で見送り")
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }
        logger?.log("最終音量復帰: +\(String(format: "%.1f", requestedGainDB)) dB")
        return candidate
    }

    private func guidedLoudnessTarget(
        currentLoudness: Float,
        requestedTargetLKFS: Float,
        policy: LoudnessAdjustmentPolicy,
        logger: AudioProcessingLogger?
    ) -> Float {
        guard currentLoudness.isFinite, currentLoudness > -69 else {
            logger?.log("ラウドネス方針: \(policy.label) / 無音に近いため音量変更なし")
            return currentLoudness
        }

        let requestedDeltaDB = Double(requestedTargetLKFS - currentLoudness)
        let appliedDeltaDB: Double
        if abs(requestedDeltaDB) < policy.deadbandDB {
            appliedDeltaDB = 0
        } else if requestedDeltaDB > 0 {
            appliedDeltaDB = min(requestedDeltaDB, policy.maxBoostDB)
        } else {
            appliedDeltaDB = max(requestedDeltaDB, -policy.maxCutDB)
        }

        logger?.log(
            "ラウドネス方針: \(policy.label) / 目安差 \(formatSignedDB(requestedDeltaDB)) -> 適用 \(formatSignedDB(appliedDeltaDB))"
        )
        return currentLoudness + Float(appliedDeltaDB)
    }

    private func enforceFinalLoudnessPolicyBounds(
        signal: AudioSignal,
        baselineLoudness: Float,
        referenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceNoiseMeasurements: NoiseMeasurementSnapshot?,
        peakCeilingDB: Float,
        policy: LoudnessAdjustmentPolicy,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let currentLoudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        guard baselineLoudness.isFinite,
              currentLoudness.isFinite,
              baselineLoudness > -69,
              currentLoudness > -69
        else {
            logger?.log("最終音量上限: 無音に近いためピーク確認のみ")
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }

        let toleranceDB = 0.05
        let allowedMaximum = Double(baselineLoudness) + policy.maxBoostDB
        let allowedMinimum = Double(baselineLoudness) - policy.maxCutDB
        let current = Double(currentLoudness)

        if current > allowedMaximum + toleranceDB {
            let gainDB = allowedMaximum - current
            logger?.log("最終音量上限: \(formatSignedDB(gainDB)) / \(policy.label) の上限内へ調整")
            return MasteringSignalMath.enforcePeakCeiling(
                signal: MasteringSignalMath.applyGain(signal: signal, gainDB: gainDB),
                peakCeilingDB: peakCeilingDB
            )
        }

        if current < allowedMinimum - toleranceDB {
            let loudnessDeficitDB = allowedMinimum - current
            let peak = max(MasteringAnalysisService.approximateTruePeak(signal.channels), 1e-6)
            let currentPeakDB = 20 * log10(Double(peak))
            let peakHeadroomDB = max(0, Double(peakCeilingDB) - currentPeakDB)
            let restoreDB = min(loudnessDeficitDB, peakHeadroomDB, policy.finalRestoreLimitDB)
            guard restoreDB > 0.25 else {
                logger?.log("最終音量下限: ピーク余裕不足")
                return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
            }

            let candidate = MasteringSignalMath.enforcePeakCeiling(
                signal: MasteringSignalMath.applyGain(signal: signal, gainDB: restoreDB),
                peakCeilingDB: peakCeilingDB
            )
            let probePlan = MasteringNoiseReturnSupport.noiseReturnProbePlan(for: signal)
            let baseProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: signal, plan: probePlan)
            let candidateProbe = MasteringNoiseReturnSupport.noiseReturnProbe(signal: candidate, plan: probePlan)
            guard isFinalLoudnessRestoreNoiseSafe(
                baseProbe: baseProbe,
                candidateProbe: candidateProbe,
                referenceMeasurements: referenceNoiseMeasurements,
                originalReferenceMeasurements: originalReferenceNoiseMeasurements
            ), isFinalLoudnessRestoreMudBalanceSafe(base: signal, candidate: candidate) else {
                logger?.log("最終音量下限: ノイズ保護で見送り")
                return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
            }

            let candidateLoudness = MasteringAnalysisService.integratedLoudness(signal: candidate)
            let appliedRestoreDB = candidateLoudness.isFinite
                ? Double(candidateLoudness - currentLoudness)
                : loudnessDeficitDB
            logger?.log("最終音量下限: \(formatSignedDB(appliedRestoreDB)) / \(policy.label) の下限内へ調整")
            return candidate
        }

        logger?.log("最終音量上限: \(policy.label) の範囲内")
        return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
    }

    private func formatSignedDB(_ value: Double) -> String {
        String(format: "%+.1f dB", value)
    }

    private func isFinalLoudnessRestoreNoiseSafe(
        baseProbe: NoiseReturnProbe,
        candidateProbe: NoiseReturnProbe,
        referenceMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceMeasurements: NoiseMeasurementSnapshot?
    ) -> Bool {
        for rule in InternalAudioJudgementPolicy.masteringNoiseReturnLimits {
            guard let baseLevel = baseProbe.comparableLevel(for: rule.id),
                  let candidateLevel = candidateProbe.comparableLevel(for: rule.id)
            else {
                continue
            }
            if candidateLevel > baseLevel + 0.35 {
                return false
            }
            if let referenceLevel = referenceMeasurements?.comparableLevel(for: rule.id) {
                let referenceLimit = referenceLevel + min(rule.allowedReturnDB + 0.35, Self.finalNoiseReturnLimit(for: rule.id))
                if baseLevel <= referenceLimit, candidateLevel > referenceLimit {
                    return false
                }
            }
            if let originalLevel = originalReferenceMeasurements?.comparableLevel(for: rule.id) {
                let originalLimit = originalLevel + max(0.75, rule.allowedReturnDB)
                if baseLevel <= originalLimit, candidateLevel > originalLimit {
                    return false
                }
            }
        }
        return true
    }

    func loudnessMatchedFinalLowMidReference(reference: AudioSignal, target: AudioSignal) -> AudioSignal {
        let referenceLoudness = MasteringAnalysisService.integratedLoudness(signal: reference)
        let targetLoudness = MasteringAnalysisService.integratedLoudness(signal: target)
        guard referenceLoudness.isFinite,
              targetLoudness.isFinite,
              referenceLoudness > -69,
              targetLoudness > -69
        else {
            return reference
        }
        return MasteringSignalMath.applyGain(signal: reference, gainDB: Double(targetLoudness - referenceLoudness))
    }

    func isFinalLowMidBodyNoiseSafe(
        base: AudioSignal,
        candidate: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot?,
        originalReferenceMeasurements: NoiseMeasurementSnapshot?
    ) -> Bool {
        let checkedIDs = [NoiseMeasurementID.hum, NoiseMeasurementID.rumble]
        let baseMeasurements = NoiseMeasurementService.analyze(signal: base, ids: checkedIDs)
        let candidateMeasurements = NoiseMeasurementService.analyze(signal: candidate, ids: checkedIDs)

        for id in checkedIDs {
            guard let baseLevel = baseMeasurements.comparableLevel(for: id),
                  let candidateLevel = candidateMeasurements.comparableLevel(for: id)
            else {
                continue
            }
            if candidateLevel > baseLevel + 0.35 {
                return false
            }
            if let referenceLevel = referenceMeasurements?.comparableLevel(for: id) {
                let referenceLimit = referenceLevel + 0.75
                if baseLevel <= referenceLimit, candidateLevel > referenceLimit {
                    return false
                }
            }
            if let originalLevel = originalReferenceMeasurements?.comparableLevel(for: id) {
                let originalLimit = originalLevel + 0.75
                if baseLevel <= originalLimit, candidateLevel > originalLimit {
                    return false
                }
            }
        }
        return true
    }

    private func isFinalLoudnessRestoreMudBalanceSafe(base: AudioSignal, candidate: AudioSignal) -> Bool {
        let baseMud = MasteringSignalMath.bandBalanceDB(signal: base, lower: 300, upper: 1_000)
        let candidateMud = MasteringSignalMath.bandBalanceDB(signal: candidate, lower: 300, upper: 1_000)
        guard baseMud.isFinite, candidateMud.isFinite else { return true }
        return candidateMud <= baseMud + 0.25
    }

    private func applyLoudness(signal: AudioSignal, targetLKFS: Float, peakCeilingDB: Float) -> AudioSignal {
        let currentLoudness = MasteringAnalysisService.integratedLoudness(signal: signal)
        guard currentLoudness.isFinite, targetLKFS.isFinite, currentLoudness > -69 else {
            return MasteringSignalMath.enforcePeakCeiling(signal: signal, peakCeilingDB: peakCeilingDB)
        }
        let gain = powf(10, (targetLKFS - currentLoudness) / 20)
        let peakCeiling = powf(10, peakCeilingDB / 20)
        let gainedChannels = signal.channels.map { channel in channel.map { $0 * gain } }
        var channels = MasteringSignalMath.applyLookaheadLimiter(gainedChannels, peakCeiling: peakCeiling, sampleRate: signal.sampleRate)

        let peak = MasteringAnalysisService.approximateTruePeak(channels)
        if peak > peakCeiling {
            let trim = peakCeiling / peak
            channels = channels.map { $0.map { $0 * trim } }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func effectiveSaturation(_ amount: Float, dynamicsRetention: Float, finishingIntensity: Float) -> Float {
        amount * MasteringSignalMath.clamped(0.64 + finishingIntensity * 0.52 - dynamicsRetention * 0.24, min: 0.35, max: 1.10)
    }

    private func effectiveTargetLoudness(_ target: Float, dynamicsRetention: Float, finishingIntensity: Float) -> Float {
        target + (finishingIntensity - 0.5) * 0.9 - dynamicsRetention * 0.45
    }

    private func scaledRatio(_ ratio: Float, scale: Float) -> Float {
        1 + (max(ratio, 1) - 1) * scale
    }

    private func compressionGainReductionDB(envelopeDB: Float, thresholdDB: Float, ratio: Float, kneeWidthDB: Float) -> Float {
        let safeRatio = max(ratio, 1)
        let lowerKnee = thresholdDB - kneeWidthDB * 0.5
        let upperKnee = thresholdDB + kneeWidthDB * 0.5

        if envelopeDB <= lowerKnee {
            return 0
        }

        if envelopeDB >= upperKnee {
            let compressedDB = thresholdDB + (envelopeDB - thresholdDB) / safeRatio
            return compressedDB - envelopeDB
        }

        let over = envelopeDB - lowerKnee
        let gainReductionDB = (1 / safeRatio - 1) * over * over / (2 * kneeWidthDB)
        return gainReductionDB
    }

    private func logMasteringRoutePlan(_ routePlan: MasteringRoutePlan, logger: AudioProcessingLogger?) {
        guard let logger else { return }
        for step in MasteringRouteStep.allCases {
            let decision = routePlan.decision(for: step)
            logger.log("ルート/マスタリング: \(step.logName) = \(decision.action.logTitle) - \(decision.reason)")
        }
    }
}

private struct MasteringAirEnhancer {
    func process(
        signal: AudioSignal,
        analysis: MasteringAnalysis,
        settings: MasteringSettings,
        finishingIntensity: Float
    ) -> AudioSignal {
        let harshnessGuard = MasteringSignalMath.clamped(1 - analysis.harshnessScore * 0.62, min: 0.28, max: 1)
        let requestedAir = max(0, settings.highShelfGain) * 0.035 + settings.saturationAmount * 0.030
        let adaptiveAir = MasteringSignalMath.clamped(Float((analysis.midBandLevelDB - analysis.highBandLevelDB) / 42), min: 0, max: 0.055)
        let amount = MasteringSignalMath.clamped((requestedAir + adaptiveAir) * (0.55 + finishingIntensity * 0.65) * harshnessGuard, min: 0, max: 0.11)
        guard amount > 0.001 else { return signal }

        let channels = mapChannelsConcurrently(signal.channels) { channel in
            let excited = channel.map { tanhf($0 * 2.4) - tanhf($0 * 1.08) }
            let presence = SpectralDSP.lowPass(
                SpectralDSP.highPass(excited, cutoff: 5_500, sampleRate: signal.sampleRate),
                cutoff: 10_000,
                sampleRate: signal.sampleRate
            )
            let air = SpectralDSP.highPass(excited, cutoff: 10_000, sampleRate: signal.sampleRate)
            return channel.indices.map { index in
                tanhf(channel[index] + presence[index] * amount * 0.45 + air[index] * amount)
            }
        }

        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }
}
