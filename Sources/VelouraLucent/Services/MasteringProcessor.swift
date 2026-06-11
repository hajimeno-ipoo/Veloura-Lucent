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

    private func logMasteringRoutePlan(_ routePlan: MasteringRoutePlan, logger: AudioProcessingLogger?) {
        guard let logger else { return }
        for step in MasteringRouteStep.allCases {
            let decision = routePlan.decision(for: step)
            logger.log("ルート/マスタリング: \(step.logName) = \(decision.action.logTitle) - \(decision.reason)")
        }
    }
}
