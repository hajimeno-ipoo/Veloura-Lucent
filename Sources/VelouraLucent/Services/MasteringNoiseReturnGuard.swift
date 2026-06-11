import Foundation

extension MasteringProcessor {
    func applyNoiseReturnGuard(
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

    func adaptiveNoiseLimit(
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

    func fullRangeNoiseReturnCorrection(
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

}

