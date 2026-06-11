import Foundation

extension NativeAudioProcessor {
    func loadInputSignal(from inputFile: URL, context: CorrectionRunContext) throws -> AudioSignal {
        context.logger?.start(ProcessingStep.loadAudio)
        context.logger?.log("入力音声を読み込みます")
        let signal = try measure("loadAudio", label: "読み込み", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .loadAudio) {
            try AudioFileService.loadAudio(from: inputFile)
        }
        saveDiagnostic(signal, to: context.diagnosticOutputDirectory, order: 0, id: "input", label: "入力", logger: context.logger)
        return signal
    }

    func resolveOriginalAnalysis(
        for signal: AudioSignal,
        analysisMode: AudioAnalysisMode,
        initialAnalysis: AnalysisData?,
        context: CorrectionRunContext
    ) -> AnalysisData {
        context.logger?.start(ProcessingStep.analyze)
        context.logger?.log("音声を解析します")
        context.logger?.log(analysisMode.logDescription)
        if let initialAnalysis {
            context.benchmarkRecorder?.append("analyze", durationSeconds: 0)
            context.logger?.log("解析: 既存結果を使用")
            context.logger?.complete(ProcessingStep.analyze)
            return initialAnalysis
        }
        return measure("analyze", label: "解析", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .analyze) {
            AudioAnalyzer(mode: context.resolvedAnalysisMode).analyze(signal: signal)
        }
    }

    func resolveRouteNoiseMeasurements(
        for signal: AudioSignal,
        initialNoiseMeasurements: NoiseMeasurementSnapshot?,
        context: CorrectionRunContext
    ) -> NoiseMeasurementSnapshot {
        if let initialNoiseMeasurements {
            context.noiseMeasurementCache.store(
                initialNoiseMeasurements,
                signalID: "input",
                ids: NoiseMeasurementRunCache.allNoiseIDs
            )
            context.benchmarkRecorder?.append("routeNoiseMeasurement", durationSeconds: 0)
            context.logger?.skip(ProcessingStep.routeNoiseMeasurement, reason: "既存の測定結果を使用")
            context.logger?.log("ノイズ測定: 既存結果を使用")
            return initialNoiseMeasurements
        }
        context.logger?.start(ProcessingStep.routeNoiseMeasurement)
        context.logger?.log(ProcessingStep.routeNoiseMeasurement.rawValue)
        return measure("routeNoiseMeasurement", label: "ルート用ノイズ測定", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .routeNoiseMeasurement) {
            context.noiseMeasurementCache.snapshot(
                signalID: "input",
                signal: signal,
                ids: NoiseMeasurementRunCache.allNoiseIDs
            )
        }
    }

    func makeCorrectionRoutePlan(
        analysis: AnalysisData,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        logger: AudioProcessingLogger?
    ) -> CorrectionRoutePlan {
        let routePlan = CorrectionRoutePlan.make(
            analysis: analysis,
            noiseMeasurements: routeNoiseMeasurements
        )
        logCorrectionRoutePlan(routePlan, logger: logger)
        return routePlan
    }

    func applyLowNoiseCleanup(
        to signal: AudioSignal,
        routePlan: CorrectionRoutePlan,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        context: CorrectionRunContext
    ) -> AudioSignal {
        let decision = routePlan.decision(for: .lowNoiseCleanup)
        let lowCleaned: AudioSignal
        if decision.action == .skip {
            context.benchmarkRecorder?.append("lowNoiseCleanup", durationSeconds: 0)
            context.logger?.skip(.lowNoiseCleanup, reason: decision.reason)
            lowCleaned = signal
        } else {
            context.logger?.start(.lowNoiseCleanup)
            context.logger?.log("低域ノイズを先に整えます")
            lowCleaned = measure("lowNoiseCleanup", label: "低域ノイズ", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .lowNoiseCleanup) {
                let dehummed = HumRemover(settings: context.correctionSettings).process(signal: signal)
                return RumbleReducer(settings: context.correctionSettings).process(
                    signal: dehummed,
                    reference: signal,
                    referenceMeasurements: routeNoiseMeasurements,
                    logger: context.logger
                )
            }
        }
        saveDiagnostic(lowCleaned, to: context.diagnosticOutputDirectory, order: 1, id: "lowNoiseCleanup", label: "低域整理後", logger: context.logger)
        return lowCleaned
    }

    func applyDenoise(to signal: AudioSignal, context: CorrectionRunContext) -> AudioSignal {
        context.logger?.start(.denoise)
        context.logger?.log("ノイズを除去します")
        let denoiseMaskBreakdownCollector = context.diagnosticOutputDirectory == nil ? nil : DenoiseMaskBreakdownCollector()
        let denoised = measure("denoise", label: "ノイズ除去", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .denoise) {
            SpectralGateDenoiser(settings: context.correctionSettings, maskBreakdownCollector: denoiseMaskBreakdownCollector).process(signal: signal)
        }
        denoiseMaskBreakdownCollector?.summaries.forEach { breakdown in
            context.logger?.log(breakdown.logMessage)
        }
        saveDiagnostic(denoised, to: context.diagnosticOutputDirectory, order: 2, id: "denoise", label: "ノイズ除去後", logger: context.logger)
        return denoised
    }

    func applySibilanceShimmerGuard(
        to signal: AudioSignal,
        reference: AudioSignal,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        routePlan: CorrectionRoutePlan,
        context: CorrectionRunContext
    ) -> AudioSignal {
        context.logger?.start(.sibilanceShimmerGuard)
        context.logger?.log("サ行保護を行います")
        let sibilanceScale: Float = routePlan.decision(for: .sibilanceShimmerGuard).action == .light ? 0.55 : 1
        let guarded = measure("sibilanceShimmerGuard", label: "サ行保護", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .sibilanceShimmerGuard) {
            SibilanceShimmerGuard(settings: context.correctionSettings).process(signal: signal, intensityScale: sibilanceScale)
        }
        let balanced = constrainCorrectionSibilanceIncrease(
            signal: guarded,
            reference: reference,
            referenceMeasurements: routeNoiseMeasurements,
            measurementCache: context.noiseMeasurementCache,
            logger: context.logger
        )
        saveDiagnostic(balanced, to: context.diagnosticOutputDirectory, order: 3, id: "sibilanceShimmerGuard", label: "サ行シマー保護後", logger: context.logger)
        return balanced
    }

    func prepareHarmonicRepair(
        for signal: AudioSignal,
        originalAnalysis: AnalysisData,
        context: CorrectionRunContext
    ) -> HarmonicRepairPreparation {
        context.logger?.start(.analyzeDenoised)
        context.logger?.log(ProcessingStep.analyzeDenoised.rawValue)
        let postDenoiseAnalysis = measure("analyzeDenoised", label: "再解析", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .analyzeDenoised) {
            AudioAnalyzer(mode: context.resolvedAnalysisMode).analyze(signal: signal)
        }
        context.logger?.start(.analysisAssist)
        context.logger?.log(ProcessingStep.analysisAssist.rawValue)
        let repairPrediction = measure("foldoverRepairPrediction", label: "解析補助", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .analysisAssist) {
            FoldoverRepairEstimator().predict(
                features: FoldoverRepairFeatures(
                    harmonicConfidence: postDenoiseAnalysis.harmonicConfidence,
                    shimmerRatio: postDenoiseAnalysis.shimmerRatio,
                    brightnessRatio: postDenoiseAnalysis.brightnessRatio,
                    transientAmount: postDenoiseAnalysis.transientAmount,
                    cutoffFrequency: originalAnalysis.cutoffFrequency,
                    noiseAmount: postDenoiseAnalysis.noiseAmount,
                    rolloffDepth: originalAnalysis.rolloffDepth,
                    airBandEnergyRatio: postDenoiseAnalysis.airBandEnergyRatio,
                    artifactBandRatio: postDenoiseAnalysis.artifactBandRatio
                )
            )
        }
        logDenoiseReport(
            before: originalAnalysis.denoiseEffectMetrics,
            after: postDenoiseAnalysis.denoiseEffectMetrics,
            logger: context.logger
        )
        return HarmonicRepairPreparation(
            postDenoiseAnalysis: postDenoiseAnalysis,
            repairPrediction: repairPrediction
        )
    }

    func applyHarmonicRepair(
        to signal: AudioSignal,
        postDenoiseAnalysis: AnalysisData,
        repairPrediction: FoldoverRepairPrediction,
        context: CorrectionRunContext
    ) -> AudioSignal {
        context.logger?.start(.harmonicRepair)
        context.logger?.log("高域を補完します")
        let repaired = measure("harmonicRepair", label: "高域修復", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .harmonicRepair) {
            CorrectionHarmonicRepair(settings: context.correctionSettings).process(
                signal: signal,
                analysis: postDenoiseAnalysis,
                prediction: repairPrediction
            )
        }
        saveDiagnostic(repaired, to: context.diagnosticOutputDirectory, order: 4, id: "harmonicRepair", label: "高域補完後", logger: context.logger)
        return repaired
    }

    func applyRepairShimmerGuard(
        to signal: AudioSignal,
        routePlan: CorrectionRoutePlan,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        context: CorrectionRunContext
    ) -> AudioSignal {
        let decision = routePlan.decision(for: .repairShimmerGuard)
        let guarded: AudioSignal
        if decision.action == .skip {
            context.benchmarkRecorder?.append("repairShimmerGuard", durationSeconds: 0)
            context.logger?.skip(.repairShimmerGuard, reason: decision.reason)
            guarded = signal
        } else if !repairIncreasedHighNoise(signal, referenceMeasurements: routeNoiseMeasurements, measurementCache: context.noiseMeasurementCache) {
            context.benchmarkRecorder?.append("repairShimmerGuard", durationSeconds: 0)
            context.logger?.skip(.repairShimmerGuard, reason: "高域修復でノイズ指標が悪化していません")
            context.logger?.log("修復後シマー保護: 早期終了 - 高域修復でノイズ指標が悪化していません")
            guarded = signal
        } else {
            context.logger?.start(.repairShimmerGuard)
            context.logger?.log("修復後シマーを確認します")
            guarded = measure("repairShimmerGuard", label: "修復後シマー保護", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .repairShimmerGuard) {
                SibilanceShimmerGuard(settings: context.correctionSettings).process(signal: signal)
            }
        }
        saveDiagnostic(guarded, to: context.diagnosticOutputDirectory, order: 5, id: "repairShimmerGuard", label: "修復後シマー確認後", logger: context.logger)
        return guarded
    }

    func applyLowMidResidueGuard(
        to signal: AudioSignal,
        routePlan: CorrectionRoutePlan,
        context: CorrectionRunContext
    ) -> AudioSignal {
        let decision = routePlan.decision(for: .lowMidResidueGuard)
        let guarded: AudioSignal
        if decision.action == .skip {
            context.benchmarkRecorder?.append("lowMidResidueGuard", durationSeconds: 0)
            context.logger?.skip(.lowMidResidueGuard, reason: decision.reason)
            guarded = signal
        } else {
            context.logger?.start(.lowMidResidueGuard)
            context.logger?.log("低中域の残りを軽く整えます")
            guarded = measure("lowMidResidueGuard", label: "低中域残り", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .lowMidResidueGuard) {
                LowMidResidueGuard(settings: context.correctionSettings).process(signal: signal)
            }
        }
        saveDiagnostic(guarded, to: context.diagnosticOutputDirectory, order: 6, id: "lowMidResidueGuard", label: "低中域整理後", logger: context.logger)
        return guarded
    }

    func applyShimmerPeakLimit(
        to signal: AudioSignal,
        reference: AudioSignal,
        routePlan: CorrectionRoutePlan,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        context: CorrectionRunContext
    ) -> AudioSignal {
        let decision = routePlan.decision(for: .shimmerPeakLimit)
        let limited: AudioSignal
        if decision.action == .skip {
            context.benchmarkRecorder?.append("shimmerPeakLimit", durationSeconds: 0)
            context.logger?.skip(.shimmerPeakLimit, reason: decision.reason)
            limited = signal
        } else {
            context.logger?.start(.shimmerPeakLimit)
            context.logger?.log("シマーを抑えます")
            limited = measure("shimmerPeakLimit", label: "シマー制限", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .shimmerPeakLimit) {
                ShimmerPeakLimiter(settings: context.correctionSettings).process(
                    signal: signal,
                    reference: reference,
                    referenceMeasurements: routeNoiseMeasurements,
                    logger: context.logger,
                    maxPasses: decision.action == .light ? 2 : 5
                )
            }
        }
        saveDiagnostic(limited, to: context.diagnosticOutputDirectory, order: 7, id: "shimmerPeakLimit", label: "シマー制限後", logger: context.logger)
        return limited
    }

    func applyCorrectionHighPreserve(
        to signal: AudioSignal,
        reference: AudioSignal,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        context: CorrectionRunContext
    ) -> AudioSignal {
        context.logger?.start(.correctionHighPreserve)
        let preserved = measure("correctionHighPreserve", label: "補正後高域保持", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .correctionHighPreserve) {
            preserveCorrectionHighFloor(
                signal: signal,
                reference: reference,
                referenceMeasurements: routeNoiseMeasurements,
                measurementCache: context.noiseMeasurementCache,
                logger: context.logger
            )
        }
        saveDiagnostic(preserved, to: context.diagnosticOutputDirectory, order: 8, id: "correctionHighPreserve", label: "高域保持後", logger: context.logger)
        return preserved
    }

    func applyCorrectionMudGuard(
        to signal: AudioSignal,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        context: CorrectionRunContext
    ) -> AudioSignal {
        context.logger?.start(.correctionMudGuard)
        context.logger?.log(ProcessingStep.correctionMudGuard.rawValue)
        let controlled = measure("correctionMudGuard", label: "補正/計測: 低中域残り確認", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .correctionMudGuard) {
            constrainCorrectionMudIncrease(
                signal: signal,
                referenceMeasurements: routeNoiseMeasurements,
                measurementCache: context.noiseMeasurementCache,
                logger: context.logger
            )
        }
        saveDiagnostic(controlled, to: context.diagnosticOutputDirectory, order: 9, id: "correctionMudGuard", label: "低中域確認後", logger: context.logger)
        return controlled
    }

    func applyPeakSafety(to signal: AudioSignal, context: CorrectionRunContext) -> AudioSignal {
        context.logger?.start(.peakSafety)
        context.logger?.log("ピークを保護します")
        let finalized = measure("peakSafety", label: "ピーク保護", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .peakSafety) {
            PeakSafetyLimiter().process(signal: signal)
        }
        saveDiagnostic(finalized, to: context.diagnosticOutputDirectory, order: 10, id: "peakSafety", label: "補正最終", logger: context.logger)
        return finalized
    }

    func saveFinalizedAudio(
        _ signal: AudioSignal,
        to outputFile: URL,
        totalStart: UInt64,
        routePlan: CorrectionRoutePlan,
        context: CorrectionRunContext
    ) throws {
        context.logger?.start(ProcessingStep.save)
        context.logger?.log("処理済みファイルを書き出します")
        try measure("saveAudio", label: "書き出し", recorder: context.benchmarkRecorder, logger: context.logger, progressStep: .save) {
            try AudioFileService.saveAudio(signal, to: outputFile)
        }
        context.logger?.log("合計: \(formatProcessingDuration(durationSeconds(since: totalStart)))")
        context.logger?.log("ルート/補正/実行工程数: \(routePlan.runLikeCount)/\(CorrectionRouteStep.allCases.count)")
        context.logger?.log("ルート/補正/スキップ工程数: \(CorrectionRouteStep.allCases.count - routePlan.runLikeCount)/\(CorrectionRouteStep.allCases.count)")
        context.logger?.log("処理が完了しました")
    }
}
