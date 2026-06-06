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

    private func effectiveTargetLoudness(_ target: Float, dynamicsRetention: Float, finishingIntensity: Float) -> Float {
        target + (finishingIntensity - 0.5) * 0.9 - dynamicsRetention * 0.45
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
