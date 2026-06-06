import Foundation

protocol AudioProcessingLogger {
    func log(_ message: String)
}

extension AudioProcessingLogger {
    func start(_ step: ProcessingStep, detail: String? = nil) {
        log(ProcessingProgressEvent.correction(step: step, state: .started, detail: detail).encodedMessage)
    }

    func complete(_ step: ProcessingStep) {
        log(ProcessingProgressEvent.correction(step: step, state: .completed, detail: nil).encodedMessage)
    }

    func skip(_ step: ProcessingStep, reason: String? = nil) {
        log(ProcessingProgressEvent.correction(step: step, state: .skipped, detail: reason).encodedMessage)
    }

    func detail(_ detail: String, for step: ProcessingStep) {
        log(ProcessingProgressEvent.correction(step: step, state: .detail, detail: detail).encodedMessage)
    }

    func start(_ step: MasteringStep, detail: String? = nil) {
        log(ProcessingProgressEvent.mastering(step: step, state: .started, detail: detail).encodedMessage)
    }

    func complete(_ step: MasteringStep) {
        log(ProcessingProgressEvent.mastering(step: step, state: .completed, detail: nil).encodedMessage)
    }

    func skip(_ step: MasteringStep, reason: String? = nil) {
        log(ProcessingProgressEvent.mastering(step: step, state: .skipped, detail: reason).encodedMessage)
    }

    func detail(_ detail: String, for step: MasteringStep) {
        log(ProcessingProgressEvent.mastering(step: step, state: .detail, detail: detail).encodedMessage)
    }
}

struct AudioProcessingStageBenchmark: Equatable, Sendable {
    let name: String
    let durationSeconds: Double
}

struct NativeAudioProcessingBenchmark: Equatable, Sendable {
    let stages: [AudioProcessingStageBenchmark]

    var totalDurationSeconds: Double {
        stages.reduce(0) { $0 + $1.durationSeconds }
    }

    func duration(for stageName: String) -> Double? {
        stages.first { $0.name == stageName }?.durationSeconds
    }
}

struct NativeAudioProcessor {
    func process(
        inputFile: URL,
        outputFile: URL,
        denoiseStrength: DenoiseStrength = .balanced,
        correctionSettings: CorrectionSettings? = nil,
        analysisMode: AudioAnalysisMode = .auto,
        initialAnalysis: AnalysisData? = nil,
        initialNoiseMeasurements: NoiseMeasurementSnapshot? = nil,
        diagnosticOutputDirectory: URL? = nil,
        logger: AudioProcessingLogger? = nil
    ) throws {
        _ = try run(
            inputFile: inputFile,
            outputFile: outputFile,
            denoiseStrength: denoiseStrength,
            correctionSettings: correctionSettings ?? denoiseStrength.settings,
            analysisMode: analysisMode,
            initialAnalysis: initialAnalysis,
            initialNoiseMeasurements: initialNoiseMeasurements,
            diagnosticOutputDirectory: diagnosticOutputDirectory,
            logger: logger,
            collectsBenchmark: false
        )
    }

    func benchmark(
        inputFile: URL,
        outputFile: URL,
        denoiseStrength: DenoiseStrength = .balanced,
        correctionSettings: CorrectionSettings? = nil,
        analysisMode: AudioAnalysisMode = .auto,
        initialAnalysis: AnalysisData? = nil,
        initialNoiseMeasurements: NoiseMeasurementSnapshot? = nil,
        diagnosticOutputDirectory: URL? = nil,
        logger: AudioProcessingLogger? = nil
    ) throws -> NativeAudioProcessingBenchmark {
        try run(
            inputFile: inputFile,
            outputFile: outputFile,
            denoiseStrength: denoiseStrength,
            correctionSettings: correctionSettings ?? denoiseStrength.settings,
            analysisMode: analysisMode,
            initialAnalysis: initialAnalysis,
            initialNoiseMeasurements: initialNoiseMeasurements,
            diagnosticOutputDirectory: diagnosticOutputDirectory,
            logger: logger,
            collectsBenchmark: true
        )
    }

    private func run(
        inputFile: URL,
        outputFile: URL,
        denoiseStrength: DenoiseStrength,
        correctionSettings: CorrectionSettings,
        analysisMode: AudioAnalysisMode,
        initialAnalysis: AnalysisData?,
        initialNoiseMeasurements: NoiseMeasurementSnapshot?,
        diagnosticOutputDirectory: URL?,
        logger: AudioProcessingLogger?,
        collectsBenchmark: Bool
    ) throws -> NativeAudioProcessingBenchmark {
        let benchmarkRecorder = collectsBenchmark ? AudioProcessingBenchmarkRecorder() : nil
        let totalStart = DispatchTime.now().uptimeNanoseconds

        logger?.start(ProcessingStep.loadAudio)
        logger?.log("入力音声を読み込みます")
        let signal = try measure("loadAudio", label: "読み込み", recorder: benchmarkRecorder, logger: logger, progressStep: .loadAudio) {
            try AudioFileService.loadAudio(from: inputFile)
        }
        let noiseMeasurementCache = NoiseMeasurementRunCache()
        saveDiagnostic(signal, to: diagnosticOutputDirectory, order: 0, id: "input", label: "入力", logger: logger)

        let resolvedAnalysisMode = analysisMode.resolvedMode
        logger?.start(ProcessingStep.analyze)
        logger?.log("音声を解析します")
        logger?.log(analysisMode.logDescription)
        let originalAnalysis: AnalysisData
        if let initialAnalysis {
            originalAnalysis = initialAnalysis
            benchmarkRecorder?.append("analyze", durationSeconds: 0)
            logger?.log("解析: 既存結果を使用")
            logger?.complete(ProcessingStep.analyze)
        } else {
            originalAnalysis = measure("analyze", label: "解析", recorder: benchmarkRecorder, logger: logger, progressStep: .analyze) {
                AudioAnalyzer(mode: resolvedAnalysisMode).analyze(signal: signal)
            }
        }
        let routeNoiseMeasurements: NoiseMeasurementSnapshot
        if let initialNoiseMeasurements {
            routeNoiseMeasurements = initialNoiseMeasurements
            noiseMeasurementCache.store(
                initialNoiseMeasurements,
                signalID: "input",
                ids: NoiseMeasurementRunCache.allNoiseIDs
            )
            benchmarkRecorder?.append("routeNoiseMeasurement", durationSeconds: 0)
            logger?.skip(ProcessingStep.routeNoiseMeasurement, reason: "既存の測定結果を使用")
            logger?.log("ノイズ測定: 既存結果を使用")
        } else {
            logger?.start(ProcessingStep.routeNoiseMeasurement)
            logger?.log(ProcessingStep.routeNoiseMeasurement.rawValue)
            routeNoiseMeasurements = measure("routeNoiseMeasurement", label: "ルート用ノイズ測定", recorder: benchmarkRecorder, logger: logger, progressStep: .routeNoiseMeasurement) {
                noiseMeasurementCache.snapshot(
                    signalID: "input",
                    signal: signal,
                    ids: NoiseMeasurementRunCache.allNoiseIDs
                )
            }
        }
        let routePlan = CorrectionRoutePlan.make(
            analysis: originalAnalysis,
            noiseMeasurements: routeNoiseMeasurements
        )
        logCorrectionRoutePlan(routePlan, logger: logger)

        let lowNoiseDecision = routePlan.decision(for: .lowNoiseCleanup)
        let lowCleaned: AudioSignal
        if lowNoiseDecision.action == .skip {
            benchmarkRecorder?.append("lowNoiseCleanup", durationSeconds: 0)
            logger?.skip(.lowNoiseCleanup, reason: lowNoiseDecision.reason)
            lowCleaned = signal
        } else {
            logger?.start(.lowNoiseCleanup)
            logger?.log("低域ノイズを先に整えます")
            lowCleaned = measure("lowNoiseCleanup", label: "低域ノイズ", recorder: benchmarkRecorder, logger: logger, progressStep: .lowNoiseCleanup) {
                let dehummed = HumRemover(settings: correctionSettings).process(signal: signal)
                return RumbleReducer(settings: correctionSettings).process(
                    signal: dehummed,
                    reference: signal,
                    referenceMeasurements: routeNoiseMeasurements,
                    logger: logger
                )
            }
        }
        saveDiagnostic(lowCleaned, to: diagnosticOutputDirectory, order: 1, id: "lowNoiseCleanup", label: "低域整理後", logger: logger)

        logger?.start(.denoise)
        logger?.log("ノイズを除去します")
        let denoiseMaskBreakdownCollector = diagnosticOutputDirectory == nil ? nil : DenoiseMaskBreakdownCollector()
        let denoised = measure("denoise", label: "ノイズ除去", recorder: benchmarkRecorder, logger: logger, progressStep: .denoise) {
            SpectralGateDenoiser(settings: correctionSettings, maskBreakdownCollector: denoiseMaskBreakdownCollector).process(signal: lowCleaned)
        }
        denoiseMaskBreakdownCollector?.summaries.forEach { breakdown in
            logger?.log(breakdown.logMessage)
        }
        saveDiagnostic(denoised, to: diagnosticOutputDirectory, order: 2, id: "denoise", label: "ノイズ除去後", logger: logger)
        logger?.start(.sibilanceShimmerGuard)
        logger?.log("サ行保護を行います")
        let sibilanceScale: Float = routePlan.decision(for: .sibilanceShimmerGuard).action == .light ? 0.55 : 1
        let sibilanceGuarded = measure("sibilanceShimmerGuard", label: "サ行保護", recorder: benchmarkRecorder, logger: logger, progressStep: .sibilanceShimmerGuard) {
            SibilanceShimmerGuard(settings: correctionSettings).process(signal: denoised, intensityScale: sibilanceScale)
        }
        saveDiagnostic(sibilanceGuarded, to: diagnosticOutputDirectory, order: 3, id: "sibilanceShimmerGuard", label: "サ行シマー保護後", logger: logger)

        logger?.start(.analyzeDenoised)
        logger?.log(ProcessingStep.analyzeDenoised.rawValue)
        let postDenoiseAnalysis = measure("analyzeDenoised", label: "再解析", recorder: benchmarkRecorder, logger: logger, progressStep: .analyzeDenoised) {
            AudioAnalyzer(mode: resolvedAnalysisMode).analyze(signal: sibilanceGuarded)
        }
        logger?.start(.analysisAssist)
        logger?.log(ProcessingStep.analysisAssist.rawValue)
        let repairPrediction = measure("neuralPrediction", label: "解析補助", recorder: benchmarkRecorder, logger: logger, progressStep: .analysisAssist) {
            NeuralFoldoverEstimator().predict(
                features: NeuralFoldoverFeatures(
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
            logger: logger
        )

        logger?.start(.harmonicRepair)
        logger?.log("高域を補完します")
        let repaired = measure("harmonicRepair", label: "高域修復", recorder: benchmarkRecorder, logger: logger, progressStep: .harmonicRepair) {
            CorrectionHarmonicRepair(settings: correctionSettings).process(
                signal: sibilanceGuarded,
                analysis: postDenoiseAnalysis,
                prediction: repairPrediction
            )
        }
        saveDiagnostic(repaired, to: diagnosticOutputDirectory, order: 4, id: "harmonicRepair", label: "高域補完後", logger: logger)
        let repairDecision = routePlan.decision(for: .repairShimmerGuard)
        let repairGuarded: AudioSignal
        if repairDecision.action == .skip {
            benchmarkRecorder?.append("repairShimmerGuard", durationSeconds: 0)
            logger?.skip(.repairShimmerGuard, reason: repairDecision.reason)
            repairGuarded = repaired
        } else if !repairIncreasedHighNoise(repaired, referenceMeasurements: routeNoiseMeasurements, measurementCache: noiseMeasurementCache) {
            benchmarkRecorder?.append("repairShimmerGuard", durationSeconds: 0)
            logger?.skip(.repairShimmerGuard, reason: "高域修復でノイズ指標が悪化していません")
            logger?.log("修復後シマー保護: 早期終了 - 高域修復でノイズ指標が悪化していません")
            repairGuarded = repaired
        } else {
            logger?.start(.repairShimmerGuard)
            logger?.log("修復後シマーを確認します")
            repairGuarded = measure("repairShimmerGuard", label: "修復後シマー保護", recorder: benchmarkRecorder, logger: logger, progressStep: .repairShimmerGuard) {
                SibilanceShimmerGuard(settings: correctionSettings).process(signal: repaired)
            }
        }
        saveDiagnostic(repairGuarded, to: diagnosticOutputDirectory, order: 5, id: "repairShimmerGuard", label: "修復後シマー確認後", logger: logger)

        let residueDecision = routePlan.decision(for: .lowMidResidueGuard)
        let residueGuarded: AudioSignal
        if residueDecision.action == .skip {
            benchmarkRecorder?.append("lowMidResidueGuard", durationSeconds: 0)
            logger?.skip(.lowMidResidueGuard, reason: residueDecision.reason)
            residueGuarded = repairGuarded
        } else {
            logger?.start(.lowMidResidueGuard)
            logger?.log("低中域の残りを軽く整えます")
            residueGuarded = measure("lowMidResidueGuard", label: "低中域残り", recorder: benchmarkRecorder, logger: logger, progressStep: .lowMidResidueGuard) {
                LowMidResidueGuard(settings: correctionSettings).process(signal: repairGuarded)
            }
        }
        saveDiagnostic(residueGuarded, to: diagnosticOutputDirectory, order: 6, id: "lowMidResidueGuard", label: "低中域整理後", logger: logger)
        let shimmerDecision = routePlan.decision(for: .shimmerPeakLimit)
        let shimmerLimited: AudioSignal
        if shimmerDecision.action == .skip {
            benchmarkRecorder?.append("shimmerPeakLimit", durationSeconds: 0)
            logger?.skip(.shimmerPeakLimit, reason: shimmerDecision.reason)
            shimmerLimited = residueGuarded
        } else {
            logger?.start(.shimmerPeakLimit)
            logger?.log("シマーを抑えます")
            shimmerLimited = measure("shimmerPeakLimit", label: "シマー制限", recorder: benchmarkRecorder, logger: logger, progressStep: .shimmerPeakLimit) {
                ShimmerPeakLimiter(settings: correctionSettings).process(
                    signal: residueGuarded,
                    reference: signal,
                    referenceMeasurements: routeNoiseMeasurements,
                    logger: logger,
                    maxPasses: shimmerDecision.action == .light ? 2 : 5
                )
            }
        }
        saveDiagnostic(shimmerLimited, to: diagnosticOutputDirectory, order: 7, id: "shimmerPeakLimit", label: "シマー制限後", logger: logger)

        logger?.start(.correctionHighPreserve)
        let highPreserved = measure("correctionHighPreserve", label: "補正後高域保持", recorder: benchmarkRecorder, logger: logger, progressStep: .correctionHighPreserve) {
            preserveCorrectionHighFloor(
                signal: shimmerLimited,
                reference: signal,
                referenceMeasurements: routeNoiseMeasurements,
                measurementCache: noiseMeasurementCache,
                logger: logger
            )
        }
        saveDiagnostic(highPreserved, to: diagnosticOutputDirectory, order: 8, id: "correctionHighPreserve", label: "高域保持後", logger: logger)
        logger?.start(.correctionMudGuard)
        logger?.log(ProcessingStep.correctionMudGuard.rawValue)
        let mudControlled = measure("correctionMudGuard", label: "補正/計測: 低中域残り確認", recorder: benchmarkRecorder, logger: logger, progressStep: .correctionMudGuard) {
            constrainCorrectionMudIncrease(
                signal: highPreserved,
                referenceMeasurements: routeNoiseMeasurements,
                measurementCache: noiseMeasurementCache,
                logger: logger
            )
        }
        saveDiagnostic(mudControlled, to: diagnosticOutputDirectory, order: 9, id: "correctionMudGuard", label: "低中域確認後", logger: logger)

        logger?.start(.peakSafety)
        logger?.log("ピークを保護します")
        let finalized = measure("peakSafety", label: "ピーク保護", recorder: benchmarkRecorder, logger: logger, progressStep: .peakSafety) {
            PeakSafetyLimiter().process(signal: mudControlled)
        }
        saveDiagnostic(finalized, to: diagnosticOutputDirectory, order: 10, id: "peakSafety", label: "補正最終", logger: logger)

        logger?.start(ProcessingStep.save)
        logger?.log("処理済みファイルを書き出します")
        try measure("saveAudio", label: "書き出し", recorder: benchmarkRecorder, logger: logger, progressStep: .save) {
            try AudioFileService.saveAudio(finalized, to: outputFile)
        }
        logger?.log("合計: \(formatProcessingDuration(durationSeconds(since: totalStart)))")
        logger?.log("ルート/補正/実行工程数: \(routePlan.runLikeCount)/\(CorrectionRouteStep.allCases.count)")
        logger?.log("ルート/補正/スキップ工程数: \(CorrectionRouteStep.allCases.count - routePlan.runLikeCount)/\(CorrectionRouteStep.allCases.count)")
        logger?.log("処理が完了しました")

        return NativeAudioProcessingBenchmark(stages: benchmarkRecorder?.stages ?? [])
    }

    private func saveDiagnostic(_ signal: AudioSignal, to directory: URL?, order: Int, id: String, label: String, logger: AudioProcessingLogger?) {
        AudioStageDiagnostics.save(
            signal,
            to: directory,
            domain: "correction",
            order: order,
            id: id,
            label: label,
            logger: logger
        )
    }

    private func measure<T>(
        _ stageName: String,
        label: String,
        recorder: AudioProcessingBenchmarkRecorder?,
        logger: AudioProcessingLogger?,
        progressStep: ProcessingStep? = nil,
        work: () throws -> T
    ) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        do {
            let result = try work()
            let duration = durationSeconds(since: start)
            recorder?.append(stageName, durationSeconds: duration)
            logger?.log("\(label): \(formatProcessingDuration(duration))")
            if let progressStep {
                logger?.complete(progressStep)
            }
            return result
        } catch {
            let duration = durationSeconds(since: start)
            recorder?.append(stageName, durationSeconds: duration)
            logger?.log("\(label): \(formatProcessingDuration(duration))")
            throw error
        }
    }

    private func durationSeconds(since start: UInt64) -> Double {
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }

    private func logDenoiseReport(before: DenoiseEffectMetrics?, after: DenoiseEffectMetrics?, logger: AudioProcessingLogger?) {
        guard let logger, let before, let after else { return }
        logger.log("ノイズ除去/STFT再利用: 2回")
        logger.log("ノイズ除去/10-16kHzチラつき: \(formatSignedDecibelChange(from: before.shimmerFlicker, to: after.shimmerFlicker))")
        logger.log("ノイズ除去/12kHz以上: \(formatSignedDecibelChange(from: before.hf12Magnitude, to: after.hf12Magnitude))")
        logger.log("ノイズ除去/16kHz以上: \(formatSignedDecibelChange(from: before.hf16Magnitude, to: after.hf16Magnitude))")
        logger.log("ノイズ除去/18kHz以上: \(formatSignedDecibelChange(from: before.hf18Magnitude, to: after.hf18Magnitude))")
    }

    private func repairIncreasedHighNoise(
        _ signal: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        measurementCache: NoiseMeasurementRunCache
    ) -> Bool {
        let repairedMeasurements = measurementCache.snapshot(
            signalID: "harmonicRepair",
            signal: signal,
            ids: [NoiseMeasurementID.hiss, NoiseMeasurementID.shimmer, NoiseMeasurementID.sibilance]
        )
        let hissDelta = noiseDelta(id: NoiseMeasurementID.hiss, reference: referenceMeasurements, current: repairedMeasurements)
        let shimmerDelta = noiseDelta(id: NoiseMeasurementID.shimmer, reference: referenceMeasurements, current: repairedMeasurements)
        let sibilanceDelta = noiseDelta(id: NoiseMeasurementID.sibilance, reference: referenceMeasurements, current: repairedMeasurements)
        return hissDelta > 2.0 || shimmerDelta > 1.5 || sibilanceDelta > 1.2
    }

    private func noiseDelta(id: String, reference: NoiseMeasurementSnapshot, current: NoiseMeasurementSnapshot) -> Double {
        guard let referenceValue = reference.comparableLevel(for: id),
              let currentValue = current.comparableLevel(for: id)
        else { return 0 }
        return currentValue - referenceValue
    }

    private func preserveCorrectionHighFloor(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        measurementCache: NoiseMeasurementRunCache,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        struct Rule {
            let label: String
            let lower: Double
            let upper: Double
            let maxAbsoluteDropDB: Double
            let maxBoostDB: Double
            let minimumUsefulBoostDB: Double
        }

        let rules = [
            Rule(label: "5-8kHz", lower: 5_000, upper: 8_000, maxAbsoluteDropDB: 3.0, maxBoostDB: 0.4, minimumUsefulBoostDB: 0.25),
            Rule(label: "8-12kHz", lower: 8_000, upper: 12_000, maxAbsoluteDropDB: 0.20, maxBoostDB: 1.0, minimumUsefulBoostDB: 0.20),
            Rule(label: "12-16kHz", lower: 12_000, upper: 16_000, maxAbsoluteDropDB: 0.20, maxBoostDB: 0.85, minimumUsefulBoostDB: 0.15),
            Rule(label: "16kHz以上", lower: 16_000, upper: 20_000, maxAbsoluteDropDB: 2.20, maxBoostDB: 0.30, minimumUsefulBoostDB: 0.25)
        ]
        let referenceMono = reference.monoMixdown()
        let referenceBandRMSDB = rules.map { rule in
            bandRMSDB(mono: referenceMono, sampleRate: reference.sampleRate, lower: rule.lower, upper: rule.upper)
        }

        var current = signal
        var currentMono = current.monoMixdown()
        var didApply = false
        for (ruleIndex, rule) in rules.enumerated() {
            let currentDB = bandRMSDB(mono: currentMono, sampleRate: current.sampleRate, lower: rule.lower, upper: rule.upper)
            let referenceDB = referenceBandRMSDB[ruleIndex]
            guard currentDB.isFinite, referenceDB.isFinite else { continue }

            let targetDB = referenceDB - rule.maxAbsoluteDropDB
            let neededBoostDB = targetDB - currentDB
            guard neededBoostDB > rule.minimumUsefulBoostDB else { continue }

            let boostDB = min(neededBoostDB, rule.maxBoostDB)
            let gain = powf(10, Float(boostDB) / 20)
            let sampleRate = current.sampleRate
            let channels = mapChannelsConcurrently(current.channels) {
                scaleCorrectionBand($0, sampleRate: sampleRate, lower: rule.lower, upper: rule.upper, gain: gain)
            }
            current = AudioSignal(channels: channels, sampleRate: sampleRate)
            if ruleIndex + 1 < rules.count {
                currentMono = current.monoMixdown()
            }
            didApply = true
            logger?.log("補正後高域保持/\(rule.label): +\(String(format: "%.1f", boostDB)) dB")
        }

        guard didApply else { return signal }
        return constrainCorrectionHighFloorNoiseReturn(
            signal: current,
            fallback: signal,
            referenceMeasurements: referenceMeasurements,
            measurementCache: measurementCache,
            logger: logger
        )
    }

    private func constrainCorrectionHighFloorNoiseReturn(
        signal: AudioSignal,
        fallback: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        measurementCache: NoiseMeasurementRunCache,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let highNoiseIDs = [NoiseMeasurementID.hiss, NoiseMeasurementID.shimmer, NoiseMeasurementID.sibilance]
        var measurementCount = 0
        let fallbackMeasurements = measurementCache.snapshot(
            signalID: "correctionHighPreserve.fallback",
            signal: fallback,
            ids: highNoiseIDs
        )
        measurementCount += 1
        let fallbackHissReturn = noiseDelta(id: NoiseMeasurementID.hiss, reference: referenceMeasurements, current: fallbackMeasurements)
        let fallbackShimmerReturn = noiseDelta(id: NoiseMeasurementID.shimmer, reference: referenceMeasurements, current: fallbackMeasurements)
        let fallbackSibilanceReturn = noiseDelta(id: NoiseMeasurementID.sibilance, reference: referenceMeasurements, current: fallbackMeasurements)
        let hissCeiling = max(2.0, fallbackHissReturn + 0.35)
        let shimmerCeiling = max(2.0, fallbackShimmerReturn + 0.35)
        let sibilanceCeiling = min(2.2, max(1.5, fallbackSibilanceReturn + 0.25))
        let fallbackUltraHighDB = bandRMSDB(signal: fallback, lower: 16_000, upper: 20_000)
        let ultraHighLiftCeilingDB = 0.25

        func allowedCandidate(index: Int, signal candidateSignal: AudioSignal) -> Bool {
            let measurements = measurementCache.snapshot(
                signalID: "correctionHighPreserve.candidate.\(index)",
                signal: candidateSignal,
                ids: highNoiseIDs
            )
            measurementCount += 1
            let hissReturn = noiseDelta(id: NoiseMeasurementID.hiss, reference: referenceMeasurements, current: measurements)
            let shimmerReturn = noiseDelta(id: NoiseMeasurementID.shimmer, reference: referenceMeasurements, current: measurements)
            let sibilanceReturn = noiseDelta(id: NoiseMeasurementID.sibilance, reference: referenceMeasurements, current: measurements)
            let ultraHighLift = bandRMSDB(signal: candidateSignal, lower: 16_000, upper: 20_000) - fallbackUltraHighDB
            return hissReturn <= hissCeiling
                && shimmerReturn <= shimmerCeiling
                && sibilanceReturn <= sibilanceCeiling
                && ultraHighLift <= ultraHighLiftCeilingDB
        }

        if allowedCandidate(index: 0, signal: signal) {
            logger?.log("補正後高域保持/測定回数: \(measurementCount)")
            return signal
        }

        let blendedCandidates: [(index: Int, mix: Float, signal: AudioSignal)] = [
            (1, 0.75, blendSignals(base: fallback, boosted: signal, mix: 0.75)),
            (2, 0.60, blendSignals(base: fallback, boosted: signal, mix: 0.60)),
            (3, 0.50, blendSignals(base: fallback, boosted: signal, mix: 0.50)),
            (4, 0.25, blendSignals(base: fallback, boosted: signal, mix: 0.25)),
            (5, 0.10, blendSignals(base: fallback, boosted: signal, mix: 0.10))
        ]

        for candidate in blendedCandidates where allowedCandidate(index: candidate.index, signal: candidate.signal) {
            if candidate.mix < 1 {
                logger?.log("補正後高域保持: ノイズ/超高域戻り抑制 mix \(String(format: "%.2f", candidate.mix))")
            }
            logger?.log("補正後高域保持/測定回数: \(measurementCount)")
            return candidate.signal
        }

        logger?.log("補正後高域保持/測定回数: \(measurementCount)")
        logger?.log("補正後高域保持: ノイズ/超高域戻り抑制で見送り")
        return fallback
    }

    private func constrainCorrectionMudIncrease(
        signal: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        measurementCache: NoiseMeasurementRunCache,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        var measurementCount = 0
        let currentMeasurements = measurementCache.snapshot(
            signalID: "correctionMudGuard.current",
            signal: signal,
            ids: [NoiseMeasurementID.mud]
        )
        measurementCount += 1
        guard let referenceMud = referenceMeasurements.comparableLevel(for: NoiseMeasurementID.mud),
              let currentMud = currentMeasurements.comparableLevel(for: NoiseMeasurementID.mud)
        else {
            logger?.log("低中域残り/測定回数: \(measurementCount)")
            return signal
        }

        let allowedIncreaseDB = 0.5
        let excessDB = currentMud - referenceMud - allowedIncreaseDB
        guard excessDB > 0.25 else {
            logger?.log("低中域残り/測定回数: \(measurementCount)")
            return signal
        }

        let targetGainDB = -min(excessDB * 0.85, 3.0)
        let candidates = [targetGainDB, targetGainDB * 0.75, targetGainDB * 0.50, targetGainDB * 0.25]
            .enumerated()
            .map { index, gainDB in
                let candidate = scaleCorrectionSignalBand(signal: signal, lower: 300, upper: 1_000, gainDB: gainDB)
                return (
                    score: MudCorrectionCandidateScore(
                        index: index,
                        gainDB: gainDB,
                        bandRMSDB: bandRMSDB(signal: candidate, lower: 300, upper: 1_000)
                    ),
                    signal: candidate
                )
            }
        guard let selectedScore = MudCorrectionCandidateSelector.select(candidates.map(\.score)),
              let selectedCandidate = candidates.first(where: { $0.score.index == selectedScore.index })
        else {
            logger?.log("低中域残り/測定回数: \(measurementCount)")
            return signal
        }
        logger?.log(
            "低中域残り/候補選定: \(selectedCandidate.score.index) gain \(String(format: "%.1f", selectedCandidate.score.gainDB)) dB"
        )
        let candidateMeasurements = measurementCache.snapshot(
            signalID: "correctionMudGuard.candidate.\(selectedCandidate.score.index)",
            signal: selectedCandidate.signal,
            ids: [NoiseMeasurementID.mud]
        )
        measurementCount += 1
        let candidateMud = candidateMeasurements.comparableLevel(for: NoiseMeasurementID.mud) ?? currentMud
        logger?.log("低中域残り/測定回数: \(measurementCount)")
        if candidateMud > referenceMud + allowedIncreaseDB {
            logger?.log("低中域残り: 最終候補でもこもり基準を超過したため見送り")
            return signal
        }
        logger?.log("低中域残り: こもり悪化を抑制 \(String(format: "%.1f", selectedCandidate.score.gainDB)) dB")
        return selectedCandidate.signal
    }

    private func blendSignals(base: AudioSignal, boosted: AudioSignal, mix: Float) -> AudioSignal {
        let channelCount = min(base.channels.count, boosted.channels.count)
        guard channelCount > 0 else { return base }
        var channels = Array(base.channels.prefix(channelCount))
        for channelIndex in 0..<channelCount {
            let count = min(base.channels[channelIndex].count, boosted.channels[channelIndex].count)
            guard count > 0 else { continue }
            channels[channelIndex] = (0..<count).map { index in
                base.channels[channelIndex][index] * (1 - mix) + boosted.channels[channelIndex][index] * mix
            }
        }
        return AudioSignal(channels: channels, sampleRate: base.sampleRate)
    }

    private func scaleCorrectionBand(_ channel: [Float], sampleRate: Double, lower: Double, upper: Double, gain: Float) -> [Float] {
        let upperBound = min(upper, sampleRate * 0.5 - 100)
        guard lower < upperBound else { return channel }
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(channel, cutoff: lower, sampleRate: sampleRate),
            cutoff: upperBound,
            sampleRate: sampleRate
        )
        return channel.indices.map { index in
            channel[index] + band[index] * (gain - 1)
        }
    }

    private func scaleCorrectionSignalBand(signal: AudioSignal, lower: Double, upper: Double, gainDB: Double) -> AudioSignal {
        let gain = powf(10, Float(gainDB) / 20)
        let sampleRate = signal.sampleRate
        let channels = mapChannelsConcurrently(signal.channels) {
            scaleCorrectionBand($0, sampleRate: sampleRate, lower: lower, upper: upper, gain: gain)
        }
        return AudioSignal(channels: channels, sampleRate: sampleRate)
    }

    private func bandRMSDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let mono = signal.monoMixdown()
        return bandRMSDB(mono: mono, sampleRate: signal.sampleRate, lower: lower, upper: upper)
    }

    private func bandRMSDB(mono: [Float], sampleRate: Double, lower: Double, upper: Double) -> Double {
        let upperBound = min(upper, sampleRate * 0.5 - 100)
        guard lower < upperBound else { return -120 }
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(mono, cutoff: lower, sampleRate: sampleRate),
            cutoff: upperBound,
            sampleRate: sampleRate
        )
        let meanSquare = band.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(band.count, 1))
        return 10 * log10(max(meanSquare, 1e-12))
    }

    private func bandBalanceDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
        bandRMSDB(signal: signal, lower: lower, upper: upper) - fullRMSDB(signal: signal)
    }

    private func fullRMSDB(signal: AudioSignal) -> Double {
        let mono = signal.monoMixdown()
        let meanSquare = mono.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(max(mono.count, 1))
        return 10 * log10(max(meanSquare, 1e-12))
    }

    private func logCorrectionRoutePlan(_ routePlan: CorrectionRoutePlan, logger: AudioProcessingLogger?) {
        guard let logger else { return }
        for step in CorrectionRouteStep.allCases {
            let decision = routePlan.decision(for: step)
            logger.log("ルート/補正: \(step.logName) = \(decision.action.logTitle) - \(decision.reason)")
        }
    }

    private func formatSignedDecibelChange(from before: Float, to after: Float) -> String {
        guard before.isFinite, after.isFinite, before > 1e-9 else {
            return "±0.0 dB"
        }
        let decibels = 20 * log10(Double(max(after, 1e-9) / before))
        return String(format: "%+.1f dB", decibels)
    }
}

private final class NoiseMeasurementRunCache {
    static let allNoiseIDs = [
        NoiseMeasurementID.hiss,
        NoiseMeasurementID.sibilance,
        NoiseMeasurementID.shimmer,
        NoiseMeasurementID.mud,
        NoiseMeasurementID.hum,
        NoiseMeasurementID.rumble,
        NoiseMeasurementID.room
    ]

    private struct Key: Hashable {
        let signalID: String
        let ids: [String]
    }

    private var storage: [Key: NoiseMeasurementSnapshot] = [:]

    func store(_ snapshot: NoiseMeasurementSnapshot, signalID: String, ids: [String]) {
        storage[Key(signalID: signalID, ids: normalized(ids))] = snapshot
    }

    func snapshot(signalID: String, signal: AudioSignal, ids: [String]) -> NoiseMeasurementSnapshot {
        let requestedIDs = normalized(ids)
        let requestedIDSet = Set(requestedIDs)
        if let cached = storage[Key(signalID: signalID, ids: requestedIDs)] {
            return cached
        }
        if let cached = storage.first(where: { key, _ in
            key.signalID == signalID && requestedIDSet.isSubset(of: Set(key.ids))
        })?.value {
            return cached
        }
        let measured = NoiseMeasurementService.analyze(signal: signal, ids: requestedIDs)
        storage[Key(signalID: signalID, ids: requestedIDs)] = measured
        return measured
    }

    private func normalized(_ ids: [String]) -> [String] {
        Array(Set(ids)).sorted()
    }
}

struct MudCorrectionCandidateScore: Sendable, Equatable {
    let index: Int
    let gainDB: Double
    let bandRMSDB: Double
}

enum MudCorrectionCandidateSelector {
    static func select(_ candidates: [MudCorrectionCandidateScore]) -> MudCorrectionCandidateScore? {
        candidates.min {
            if $0.bandRMSDB == $1.bandRMSDB {
                return $0.index < $1.index
            }
            return $0.bandRMSDB < $1.bandRMSDB
        }
    }
}

private final class AudioProcessingBenchmarkRecorder {
    private(set) var stages: [AudioProcessingStageBenchmark] = []

    func append(_ stageName: String, durationSeconds: Double) {
        stages.append(
            AudioProcessingStageBenchmark(
                name: stageName,
                durationSeconds: durationSeconds
            )
        )
    }
}

func mapChannelsConcurrently(_ channels: [[Float]], transform: @escaping @Sendable ([Float]) -> [Float]) -> [[Float]] {
    guard channels.count > 1 else {
        return channels.map(transform)
    }

    let results = ConcurrentChannelResults(count: channels.count)
    DispatchQueue.concurrentPerform(iterations: channels.count) { index in
        let processed = transform(channels[index])
        results.set(processed, at: index)
    }
    return results.values()
}

private final class ConcurrentChannelResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [[Float]?]

    init(count: Int) {
        storage = Array(repeating: nil, count: count)
    }

    func set(_ value: [Float], at index: Int) {
        lock.lock()
        storage[index] = value
        lock.unlock()
    }

    func values() -> [[Float]] {
        lock.lock()
        defer { lock.unlock() }
        return storage.map { $0 ?? [] }
    }
}

struct HumRemovalFrameAttenuation: Sendable {
    static func scale(
        spectrogram: Spectrogram,
        frameIndex: Int,
        centerBin: Int,
        frameEnergy: Float,
        quietThreshold: Float,
        activeThreshold: Float
    ) -> Float {
        let activeScale: Float = localProminenceDB(
            spectrogram: spectrogram,
            frameIndex: frameIndex,
            centerBin: centerBin
        ) >= 6 ? 0.85 : 0.35
        return scale(
            frameEnergy: frameEnergy,
            quietThreshold: quietThreshold,
            activeThreshold: activeThreshold,
            activeScale: activeScale
        )
    }

    static func scale(
        frameEnergy: Float,
        quietThreshold: Float,
        activeThreshold: Float,
        activeScale: Float
    ) -> Float {
        if frameEnergy <= quietThreshold { return 1 }
        if frameEnergy >= activeThreshold { return activeScale }
        let position = (frameEnergy - quietThreshold) / max(activeThreshold - quietThreshold, 1e-9)
        return 1 - (1 - activeScale) * position
    }

    static func localProminenceDB(spectrogram: Spectrogram, frameIndex: Int, centerBin: Int) -> Float {
        let center = spectrogram.magnitude(frameIndex: frameIndex, binIndex: centerBin)
        let lowerBin = max(0, centerBin - 2)
        let upperBin = min(spectrogram.binCount - 1, centerBin + 2)
        var surrounding: Float = 0
        var count: Float = 0
        for binIndex in lowerBin...upperBin where binIndex != centerBin {
            surrounding += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            count += 1
        }
        let surroundingMean = surrounding / max(count, 1)
        return 20 * log10f(max(center, 1e-9) / max(surroundingMean, 1e-9))
    }
}

private struct RumbleReducer: Sendable {
    let settings: CorrectionSettings

    func process(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot? = nil,
        logger: AudioProcessingLogger? = nil
    ) -> AudioSignal {
        let intensity = clamped(settings.lowCleanup * 0.68 + settings.noiseDetectionSensitivity * 0.22, min: 0, max: 1)
        guard intensity > 0.05 else {
            logger?.log("低域ノイズ/測定回数: 0")
            return signal
        }
        let activeLowBodyScale = RumbleFrameAttenuation.activeMusicScale(correctionIntensity: settings.correctionIntensity)
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate, intensity: intensity, activeLowBodyScale: activeLowBodyScale)
        }
        return adaptiveRumbleLimit(
            signal: AudioSignal(channels: channels, sampleRate: signal.sampleRate),
            reference: reference,
            referenceMeasurements: referenceMeasurements,
            logger: logger
        )
    }

    private func adaptiveRumbleLimit(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot?,
        logger: AudioProcessingLogger?
    ) -> AudioSignal {
        let improvementDB = settings.correctionIntensity >= 0.65 ? 3.2 : (settings.correctionIntensity >= 0.45 ? 1.2 : 0.0)
        guard improvementDB > 0 else {
            logger?.log("低域ノイズ/測定回数: 0")
            return signal
        }

        let measurements = referenceMeasurements?.comparableLevel(for: NoiseMeasurementID.rumble) == nil
            ? NoiseMeasurementService.analyze(signal: reference, ids: [NoiseMeasurementID.rumble])
            : referenceMeasurements!
        guard let referenceRumble = measurements.comparableLevel(for: NoiseMeasurementID.rumble) else {
            logger?.log("低域ノイズ/測定回数: 0")
            return signal
        }
        let target = referenceRumble - improvementDB
        var currentSignal = signal
        var measurementCount = 0
        for _ in 0..<4 {
            measurementCount += 1
            guard let current = NoiseMeasurementService.analyze(signal: currentSignal, ids: [NoiseMeasurementID.rumble]).comparableLevel(for: NoiseMeasurementID.rumble) else {
                logger?.log("低域ノイズ/測定回数: \(measurementCount)")
                return currentSignal
            }
            let excessDB = max(0, current - target)
            guard excessDB > 0.1 else {
                logger?.log("低域ノイズ/測定回数: \(measurementCount)")
                return currentSignal
            }

            let gain = powf(10, -Float(min(excessDB, 48)) / 20)
            let sampleRate = currentSignal.sampleRate
            let channels = mapChannelsConcurrently(currentSignal.channels) {
                scaleBand($0, sampleRate: sampleRate, lower: 20, upper: 150, gain: gain)
            }
            currentSignal = AudioSignal(channels: channels, sampleRate: sampleRate)
        }
        logger?.log("低域ノイズ/測定回数: \(measurementCount)")
        return currentSignal
    }

    private func scaleBand(_ channel: [Float], sampleRate: Double, lower: Double, upper: Double, gain: Float) -> [Float] {
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(channel, cutoff: lower, sampleRate: sampleRate),
            cutoff: min(upper, sampleRate * 0.5 - 100),
            sampleRate: sampleRate
        )
        let reduction = 1 - gain
        return channel.indices.map { index in
            channel[index] - band[index] * reduction
        }
    }

    private func processChannel(_ channel: [Float], sampleRate: Double, intensity: Float, activeLowBodyScale: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }
        let frameEnergy = spectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(frameEnergy, 20)
        let activeThreshold = max(SpectralDSP.percentile(frameEnergy, 50), quietThreshold + 1e-9)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let endBin = min(max(Int(150 / frequencyStep), 0), spectrogram.binCount - 1)

        for binIndex in 0...endBin {
            let frequency = Double(binIndex) * frequencyStep
            let bandWeight: Float
            if frequency < 20 {
                bandWeight = 0.95
            } else if frequency < 35 {
                bandWeight = 0.82
            } else if frequency < 80 {
                bandWeight = 1.25
            } else {
                bandWeight = 0.50
            }
            for frameIndex in 0..<spectrogram.frameCount {
                let frameScale = RumbleFrameAttenuation.scale(
                    frequency: frequency,
                    frameEnergy: frameEnergy[frameIndex],
                    quietThreshold: quietThreshold,
                    activeThreshold: activeThreshold,
                    activeScale: activeLowBodyScale
                )
                let gain = clamped(1 - bandWeight * intensity * frameScale, min: 0.05, max: 1)
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
            }
        }

        return SpectralDSP.istft(spectrogram)
    }
}

struct RumbleFrameAttenuation: Sendable {
    static let activeMusicScale: Float = 0.60
    private static let balancedCorrectionIntensity: Float = 0.50
    private static let strongCorrectionIntensity: Float = 0.72

    static func activeMusicScale(correctionIntensity: Float) -> Float {
        if correctionIntensity <= balancedCorrectionIntensity { return activeMusicScale }
        if correctionIntensity >= strongCorrectionIntensity { return 1.0 }
        let progress = (correctionIntensity - balancedCorrectionIntensity)
            / (strongCorrectionIntensity - balancedCorrectionIntensity)
        return activeMusicScale + (1.0 - activeMusicScale) * progress
    }

    static func scale(
        frequency: Double,
        frameEnergy: Float,
        quietThreshold: Float,
        activeThreshold: Float,
        activeScale: Float = activeMusicScale
    ) -> Float {
        guard frequency >= 60, frequency < 150 else {
            return 1
        }
        return scale(
            frameEnergy: frameEnergy,
            quietThreshold: quietThreshold,
            activeThreshold: activeThreshold,
            activeScale: activeScale
        )
    }

    static func scale(
        frameEnergy: Float,
        quietThreshold: Float,
        activeThreshold: Float,
        activeScale: Float
    ) -> Float {
        if frameEnergy <= quietThreshold { return 1 }
        if frameEnergy >= activeThreshold { return activeScale }
        let position = (frameEnergy - quietThreshold) / max(activeThreshold - quietThreshold, 1e-9)
        return 1 - (1 - activeScale) * position
    }
}

private struct SibilanceShimmerGuard: Sendable {
    let settings: CorrectionSettings

    func process(signal: AudioSignal, intensityScale: Float = 1) -> AudioSignal {
        let defaults = settings.profile.settings
        let intensity = clamped(
            0.28
                + settings.highNaturalness * 0.34
                + settings.noiseDetectionSensitivity * 0.24
                + max(0, settings.correctionIntensity - defaults.correctionIntensity) * 0.44,
            min: 0.22,
            max: 0.86
        ) * clamped(intensityScale, min: 0.25, max: 1)
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate, intensity: intensity)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processChannel(_ channel: [Float], sampleRate: Double, intensity: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 2 else { return channel }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let affectedStartBin = bin(for: 5_000, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        let affectedEndBin = bin(for: 14_000, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        guard affectedEndBin > affectedStartBin else { return channel }

        let sibilanceEnergy = bandEnergy(in: spectrogram, lower: 5_000, upper: 9_000, frequencyStep: frequencyStep)
        let biteEnergy = bandEnergy(in: spectrogram, lower: 6_000, upper: 10_000, frequencyStep: frequencyStep)
        let shimmerEnergy = bandEnergy(in: spectrogram, lower: 10_000, upper: 14_000, frequencyStep: frequencyStep)
        let sibilanceEventEnergy = smoothedEnergy(sibilanceEnergy, radius: 3)
        let biteEventEnergy = smoothedEnergy(biteEnergy, radius: 3)
        let shimmerEventEnergy = smoothedEnergy(shimmerEnergy, radius: 3)
        let sibilanceThreshold = transientThreshold(for: sibilanceEventEnergy)
        let biteThreshold = transientThreshold(for: biteEventEnergy)
        let shimmerThreshold = transientThreshold(for: shimmerEventEnergy)
        guard sibilanceThreshold > 1e-9 || biteThreshold > 1e-9 || shimmerThreshold > 1e-9 else { return channel }
        let shortEventFrameLimit = max(3, Int((sampleRate * 0.16 / Double(spectrogram.hopSize)).rounded(.up)))

        var didReduce = false
        for frameIndex in 0..<spectrogram.frameCount {
            let sibilancePeak = shortEventPeakAmount(
                in: sibilanceEventEnergy,
                frameIndex: frameIndex,
                threshold: sibilanceThreshold,
                maxEventFrames: shortEventFrameLimit
            )
            let bitePeak = shortEventPeakAmount(
                in: biteEventEnergy,
                frameIndex: frameIndex,
                threshold: biteThreshold,
                maxEventFrames: shortEventFrameLimit
            )
            let shimmerPeak = shortEventPeakAmount(
                in: shimmerEventEnergy,
                frameIndex: frameIndex,
                threshold: shimmerThreshold,
                maxEventFrames: shortEventFrameLimit
            )
            guard sibilancePeak > 0 || bitePeak > 0 || shimmerPeak > 0 else { continue }

            for binIndex in affectedStartBin...affectedEndBin {
                let frequency = Double(binIndex) * frequencyStep
                let reduction = transientReduction(
                    frequency: frequency,
                    sibilancePeak: sibilancePeak,
                    bitePeak: bitePeak,
                    shimmerPeak: shimmerPeak,
                    intensity: intensity
                )
                guard reduction > 0 else { continue }
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: 1 - reduction)
                didReduce = true
            }
        }

        guard didReduce else { return channel }
        return SpectralDSP.istft(spectrogram)
    }

    private func bandEnergy(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> [Float] {
        let startBin = bin(for: lower, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        let endBin = bin(for: upper, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        guard endBin > startBin else {
            return Array(repeating: 0, count: spectrogram.frameCount)
        }

        var values = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            for binIndex in startBin...endBin {
                sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            values[frameIndex] = sum / Float(endBin - startBin + 1)
        }
        return values
    }

    private func smoothedEnergy(_ energy: [Float], radius: Int) -> [Float] {
        guard !energy.isEmpty, radius > 0 else { return energy }
        return energy.indices.map { index in
            let start = max(0, index - radius)
            let end = min(energy.count - 1, index + radius)
            let sum = energy[start...end].reduce(Float.zero, +)
            return sum / Float(end - start + 1)
        }
    }

    private func transientThreshold(for energy: [Float]) -> Float {
        guard !energy.isEmpty else { return 0 }
        let median = SpectralDSP.percentile(energy, 50)
        let upper = SpectralDSP.percentile(energy, 78)
        return max(median * 1.35, upper)
    }

    private func shortEventPeakAmount(in energy: [Float], frameIndex: Int, threshold: Float, maxEventFrames: Int) -> Float {
        guard energy.indices.contains(frameIndex), threshold > 1e-9 else { return 0 }
        let current = energy[frameIndex]
        guard current > threshold else { return 0 }
        let eventRange = aboveThresholdRange(in: energy, containing: frameIndex, threshold: threshold)
        guard eventRange.count <= maxEventFrames else { return 0 }
        let surroundingMean = surroundingMeanEnergy(in: energy, excluding: eventRange, radius: max(3, maxEventFrames / 2))
        let localThreshold = max(threshold, surroundingMean * 1.18)
        guard current > localThreshold else { return 0 }
        return min(1, (current - localThreshold) / max(current, 1e-6))
    }

    private func aboveThresholdRange(in energy: [Float], containing frameIndex: Int, threshold: Float) -> ClosedRange<Int> {
        var start = frameIndex
        while start > 0, energy[start - 1] > threshold {
            start -= 1
        }

        var end = frameIndex
        while end + 1 < energy.count, energy[end + 1] > threshold {
            end += 1
        }

        return start...end
    }

    private func surroundingMeanEnergy(in energy: [Float], excluding eventRange: ClosedRange<Int>, radius: Int) -> Float {
        guard !energy.isEmpty else { return 0 }
        var sum: Float = 0
        var count = 0
        let beforeStart = max(0, eventRange.lowerBound - radius)
        if beforeStart < eventRange.lowerBound {
            for index in beforeStart..<eventRange.lowerBound {
                sum += energy[index]
                count += 1
            }
        }

        let afterEnd = min(energy.count - 1, eventRange.upperBound + radius)
        if eventRange.upperBound < afterEnd {
            for index in (eventRange.upperBound + 1)...afterEnd {
                sum += energy[index]
                count += 1
            }
        }

        return count > 0 ? sum / Float(count) : 0
    }

    private func transientReduction(
        frequency: Double,
        sibilancePeak: Float,
        bitePeak: Float,
        shimmerPeak: Float,
        intensity: Float
    ) -> Float {
        let weightedPeak: Float
        let maxReduction: Float
        if frequency < 6_000 {
            weightedPeak = sibilancePeak * 0.90
            maxReduction = 0.42
        } else if frequency < 8_000 {
            weightedPeak = max(sibilancePeak * 1.08, bitePeak * 0.20)
            maxReduction = 0.58
        } else if frequency < 9_000 {
            weightedPeak = max(sibilancePeak * 0.12, bitePeak * 0.12)
            maxReduction = 0.04
        } else if frequency < 10_000 {
            weightedPeak = bitePeak * 0.22
            maxReduction = 0.08
        } else if frequency < 12_000 {
            weightedPeak = shimmerPeak * 0.24
            maxReduction = 0.08
        } else {
            weightedPeak = shimmerPeak * 0.46
            maxReduction = 0.14
        }
        return min(maxReduction, weightedPeak * intensity)
    }

    private func bin(for frequency: Double, frequencyStep: Double, maxBin: Int) -> Int {
        min(max(Int(frequency / frequencyStep), 0), maxBin)
    }
}

private struct MultibandDynamicsProcessor: Sendable {
    let settings: CorrectionSettings

    private var bands: [(range: ClosedRange<Double>, reductionDB: Float, percentile: Float, steadyReductionDB: Float)] {
        let defaults = settings.profile.settings
        let lowCleanupDelta = max(0, settings.lowCleanup - defaults.lowCleanup)
        let lowMidCleanupDelta = max(0, settings.lowMidCleanup - defaults.lowMidCleanup)
        let naturalnessDelta = max(0, settings.highNaturalness - defaults.highNaturalness)
        let sensitivityDelta = max(0, settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity)
        let presenceReduction = clamped(3.0 + (settings.presenceRepair - defaults.presenceRepair) * 1.5 + naturalnessDelta * 1.6, min: 2.2, max: 5.8)
        let shimmerReduction = clamped(3.2 + naturalnessDelta * 4.2 + sensitivityDelta * 2.2, min: 2.4, max: 7.4)
        let airReduction = clamped(2.8 + naturalnessDelta * 2.8 + sensitivityDelta * 1.4 - (settings.airRepair - defaults.airRepair) * 0.6, min: 1.8, max: 6.4)
        return [
            (20...150, clamped(2.2 + lowCleanupDelta * 3.0, min: 1.8, max: 5.2), 62, lowCleanupDelta * 3.0),
            (45...70, clamped(2.8 + lowCleanupDelta * 3.4 + sensitivityDelta * 1.4, min: 2.0, max: 6.0), 58, lowCleanupDelta * 2.4 + sensitivityDelta * 1.2),
            (90...130, clamped(2.4 + lowCleanupDelta * 3.0 + sensitivityDelta * 1.2, min: 1.8, max: 5.6), 58, lowCleanupDelta * 2.0 + sensitivityDelta * 1.0),
            (200...1_000, clamped(2.4 + lowMidCleanupDelta * 3.0, min: 1.8, max: 5.8), 66, lowMidCleanupDelta * 2.2),
            (5_000...8_000, presenceReduction, 78, naturalnessDelta * 2.0 + sensitivityDelta * 0.8),
            (10_000...14_000, shimmerReduction, 58, naturalnessDelta * 6.0 + sensitivityDelta * 3.0),
            (18_000...24_000, airReduction, 76, naturalnessDelta * 3.8 + sensitivityDelta * 1.8)
        ]
    }

    func process(signal: AudioSignal) -> AudioSignal {
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processChannel(_ channel: [Float], sampleRate: Double) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        var bandEnergy = Array(repeating: Float.zero, count: spectrogram.frameCount)
        var rawMask = Array(repeating: Float.zero, count: spectrogram.frameCount)
        var smoothedMask = Array(repeating: Float.zero, count: spectrogram.frameCount)

        for band in bands {
            let start = min(Int(band.range.lowerBound / frequencyStep), spectrogram.binCount - 1)
            let end = min(Int(band.range.upperBound / frequencyStep), spectrogram.binCount - 1)
            guard end > start else { continue }

            fillBandEnergy(spectrogram: spectrogram, startBin: start, endBin: end, into: &bandEnergy)
            let threshold = SpectralDSP.percentile(bandEnergy, band.percentile)
            let reductionLinear = powf(10, -band.reductionDB / 20)
            let steadyReductionLinear = powf(10, -band.steadyReductionDB / 20)
            fillBandMask(
                bandEnergy: bandEnergy,
                threshold: threshold,
                reductionLinear: reductionLinear,
                into: &rawMask
            )
            fillMovingAverage(rawMask, windowSize: 5, into: &smoothedMask)

            for frameIndex in 0..<spectrogram.frameCount {
                let dynamicGain = max(reductionLinear, min(1.0, smoothedMask[frameIndex]))
                let gain = min(dynamicGain, steadyReductionLinear)
                for binIndex in start...end {
                    spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
                }
            }
        }

        return SpectralDSP.istft(spectrogram)
    }

    private func fillBandEnergy(
        spectrogram: Spectrogram,
        startBin: Int,
        endBin: Int,
        into bandEnergy: inout [Float]
    ) {
        if bandEnergy.count != spectrogram.frameCount {
            bandEnergy = Array(repeating: Float.zero, count: spectrogram.frameCount)
        }

        let binCount = Float(endBin - startBin + 1)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            for binIndex in startBin...endBin {
                sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            bandEnergy[frameIndex] = sum / binCount
        }
    }

    private func fillBandMask(
        bandEnergy: [Float],
        threshold: Float,
        reductionLinear: Float,
        into mask: inout [Float]
    ) {
        if mask.count != bandEnergy.count {
            mask = Array(repeating: Float.zero, count: bandEnergy.count)
        }

        for index in bandEnergy.indices {
            let energy = bandEnergy[index]
            mask[index] = energy > threshold ? reductionLinear + (1 - reductionLinear) * (threshold / max(energy, 1e-6)) : 1
        }
    }

    private func fillMovingAverage(_ values: [Float], windowSize: Int, into smoothed: inout [Float]) {
        guard windowSize > 1, !values.isEmpty else {
            smoothed = values
            return
        }

        if smoothed.count != values.count {
            smoothed = Array(repeating: Float.zero, count: values.count)
        }

        let radius = windowSize / 2
        for index in values.indices {
            let lower = max(0, index - radius)
            let upper = min(values.count - 1, index + radius)
            var sum: Float = 0
            for valueIndex in lower...upper {
                sum += values[valueIndex]
            }
            smoothed[index] = sum / Float(upper - lower + 1)
        }
    }
}

private struct LowMidResidueGuard: Sendable {
    let settings: CorrectionSettings

    func process(signal: AudioSignal) -> AudioSignal {
        let defaults = settings.profile.settings
        let intensity = clamped(
            0.10 + settings.lowMidCleanup * 0.20 + max(0, settings.lowMidCleanup - defaults.lowMidCleanup) * 0.35,
            min: 0.08,
            max: 0.32
        )
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate, intensity: intensity)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processChannel(_ channel: [Float], sampleRate: Double, intensity: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let startBin = min(max(Int(200 / frequencyStep), 0), spectrogram.binCount - 1)
        let endBin = min(max(Int(1_000 / frequencyStep), startBin), spectrogram.binCount - 1)
        guard endBin > startBin else { return channel }

        var bandEnergy = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            for binIndex in startBin...endBin {
                sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            bandEnergy[frameIndex] = sum / Float(endBin - startBin + 1)
        }

        let sustainedThreshold = SpectralDSP.percentile(bandEnergy, 62)
        for frameIndex in 0..<spectrogram.frameCount where bandEnergy[frameIndex] <= sustainedThreshold {
            let reduction = intensity * (1 - bandEnergy[frameIndex] / max(sustainedThreshold, 1e-6))
            let gain = 1 - reduction
            for binIndex in startBin...endBin {
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
            }
        }

        return SpectralDSP.istft(spectrogram)
    }
}

private struct ShimmerPeakLimiter: Sendable {
    let settings: CorrectionSettings

    func process(
        signal: AudioSignal,
        reference: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot? = nil,
        logger: AudioProcessingLogger? = nil,
        maxPasses: Int = 5
    ) -> AudioSignal {
        let rules = InternalAudioJudgementPolicy.shimmerLimitRules(improvementDB: targetImprovementDB)
        let requiredIDs = rules.map(\.id)
        let referenceMeasurements = requiredIDs.allSatisfy { referenceMeasurements?.comparableLevel(for: $0) != nil }
            ? referenceMeasurements!
            : NoiseMeasurementService.analyze(signal: reference, ids: requiredIDs)
        return adaptiveLimit(
            signal: signal,
            referenceMeasurements: referenceMeasurements,
            rules: rules,
            logger: logger,
            maxPasses: maxPasses
        )
    }

    private var targetImprovementDB: Double {
        if settings.correctionIntensity >= 0.65 { return 1.0 }
        if settings.correctionIntensity >= 0.45 { return 0.35 }
        return -0.2
    }

    private func adaptiveLimit(
        signal: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        rules: [ShimmerLimitRule],
        logger: AudioProcessingLogger?,
        maxPasses: Int = 5
    ) -> AudioSignal {
        var currentSignal = signal
        var measurementCount = 0
        var previousExcessDB: Double?
        let adaptivePasses = min(maxPasses, settings.correctionIntensity >= 0.70 ? 3 : 2)
        let analysisPlan = shimmerProbePlan(for: signal)

        logger?.log("シマー制限: 短時間判定を開始")
        if analysisPlan.usesRepresentativeWindows {
            logger?.detail("\(analysisPlan.selectedWindowCount)/\(analysisPlan.totalWindowCount) 区間を確認中", for: .shimmerPeakLimit)
            logger?.log("シマー制限/軽量測定: \(analysisPlan.selectedWindowCount)/\(analysisPlan.totalWindowCount)区間")
        }
        for _ in 0..<adaptivePasses {
            let currentMeasurements = shimmerProbe(signal: currentSignal, plan: analysisPlan)
            measurementCount += 1
            logger?.detail("\(measurementCount)/\(adaptivePasses) 回目を確認中", for: .shimmerPeakLimit)
            logger?.log("シマー制限/測定: \(measurementCount)/\(adaptivePasses)")

            let strongestExcess = rules
                .compactMap { rule -> (rule: ShimmerLimitRule, excessDB: Double)? in
                    guard let reference = referenceMeasurements.comparableLevel(for: rule.id),
                          let current = currentMeasurements.comparableLevel(for: rule.id)
                    else { return nil }
                    let target = reference - rule.improvementDB
                    return (rule, max(0, current - target))
                }
                .max { $0.excessDB < $1.excessDB }

            guard let strongestExcess, strongestExcess.excessDB > 0.1 else {
                let residualSmoothed = residualShortEventLimit(signal: currentSignal, rules: rules)
                logger?.log("シマー制限/測定回数: \(measurementCount)")
                logger?.log("シマー制限: 目標到達 - 短時間シマーのみ確認")
                logger?.log("シマー制限: 完了")
                return residualSmoothed
            }
            if let previousExcessDB, previousExcessDB - strongestExcess.excessDB < 0.35 {
                logger?.log("シマー制限/測定回数: \(measurementCount)")
                logger?.log("シマー制限: 改善量が小さいため終了")
                return currentSignal
            }
            previousExcessDB = strongestExcess.excessDB

            let gain = powf(10, -Float(min(strongestExcess.excessDB * reductionScale, maxReductionPerPassDB)) / 20)
            let sampleRate = currentSignal.sampleRate
            let channels = mapChannelsConcurrently(currentSignal.channels) {
                processChannel(
                    $0,
                    sampleRate: sampleRate,
                    lower: strongestExcess.rule.lowerFrequency,
                    upper: strongestExcess.rule.upperFrequency,
                    gain: gain
                )
            }
            currentSignal = AudioSignal(channels: channels, sampleRate: sampleRate)
        }

        if settings.correctionIntensity >= 0.65,
           let finalCorrection = fullRangeCorrection(
            signal: currentSignal,
            referenceMeasurements: referenceMeasurements,
            rules: rules
           ) {
            logger?.log("シマー制限/最終確認: 全体測定")
            logger?.log("シマー制限: 最終確認で短時間シマーを追加補正")
            let sampleRate = currentSignal.sampleRate
            let channels = mapChannelsConcurrently(currentSignal.channels) {
                processChannel(
                    $0,
                    sampleRate: sampleRate,
                    lower: finalCorrection.rule.lowerFrequency,
                    upper: finalCorrection.rule.upperFrequency,
                    gain: finalCorrection.gain
                )
            }
            currentSignal = AudioSignal(channels: channels, sampleRate: sampleRate)
        }

        logger?.log("シマー制限/測定回数: \(measurementCount)")
        logger?.log("シマー制限: 安全上限に到達")
        return currentSignal
    }

    private func fullRangeCorrection(
        signal: AudioSignal,
        referenceMeasurements: NoiseMeasurementSnapshot,
        rules: [ShimmerLimitRule]
    ) -> (rule: ShimmerLimitRule, gain: Float)? {
        let currentMeasurements = NoiseMeasurementService.analyze(signal: signal, ids: rules.map(\.id))
        guard let strongestExcess = rules
            .compactMap({ rule -> (rule: ShimmerLimitRule, excessDB: Double)? in
                guard let reference = referenceMeasurements.comparableLevel(for: rule.id),
                      let current = currentMeasurements.comparableLevel(for: rule.id)
                else { return nil }
                let target = reference - rule.improvementDB
                return (rule, max(0, current - target))
            })
            .max(by: { $0.excessDB < $1.excessDB }),
            strongestExcess.excessDB > 0.1
        else {
            return nil
        }
        let gain = powf(10, -Float(min(strongestExcess.excessDB * reductionScale, maxReductionPerPassDB)) / 20)
        return (strongestExcess.rule, gain)
    }

    private func residualShortEventLimit(signal: AudioSignal, rules: [ShimmerLimitRule]) -> AudioSignal {
        let residualReductionDB = min(max(1.2, targetImprovementDB), maxReductionPerPassDB)
        let gain = powf(10, -Float(residualReductionDB) / 20)
        let sampleRate = signal.sampleRate
        var currentSignal = signal
        for rule in rules {
            let channels = mapChannelsConcurrently(currentSignal.channels) {
                processChannel(
                    $0,
                    sampleRate: sampleRate,
                    lower: rule.lowerFrequency,
                    upper: rule.upperFrequency,
                    gain: gain
                )
            }
            currentSignal = AudioSignal(channels: channels, sampleRate: sampleRate)
        }
        return currentSignal
    }

    private var maxReductionPerPassDB: Double {
        InternalAudioJudgementPolicy.shimmerMaxReductionPerPassDB(correctionIntensity: settings.correctionIntensity)
    }

    private var reductionScale: Double {
        InternalAudioJudgementPolicy.shimmerReductionScale(correctionIntensity: settings.correctionIntensity)
    }

    private struct ShimmerProbePlan {
        let ranges: [Range<Int>]
        let totalWindowCount: Int

        var selectedWindowCount: Int { ranges.count }
        var usesRepresentativeWindows: Bool {
            totalWindowCount > ranges.count
        }
    }

    private struct ShimmerProbe {
        let hiss: Double
        let shimmer: Double

        func comparableLevel(for id: String) -> Double? {
            switch id {
            case "hiss": hiss
            case "shimmer": shimmer
            default: nil
            }
        }
    }

    private func shimmerProbePlan(for signal: AudioSignal) -> ShimmerProbePlan {
        let mono = signal.monoMixdown()
        guard !mono.isEmpty else {
            return ShimmerProbePlan(ranges: [], totalWindowCount: 0)
        }
        let windowSize = max(Int(signal.sampleRate), 1)
        let totalWindowCount = max(1, Int(ceil(Double(mono.count) / Double(windowSize))))
        guard totalWindowCount > 45 else {
            return ShimmerProbePlan(ranges: [mono.indices], totalWindowCount: 1)
        }

        let probeCount = min(24, totalWindowCount)
        let selectedCount = min(8, probeCount)
        let windowStride = max(1, totalWindowCount / probeCount)
        let candidates = stride(from: 0, to: totalWindowCount, by: windowStride).prefix(probeCount).map { windowIndex in
            let start = min(windowIndex * windowSize, mono.count)
            let end = min(start + windowSize, mono.count)
            return (range: start..<end, score: rmsEnergy(mono[start..<end]))
        }
        let selected = candidates
            .sorted { $0.score > $1.score }
            .prefix(selectedCount)
            .map { $0.range }
            .sorted { $0.lowerBound < $1.lowerBound }
        return ShimmerProbePlan(ranges: selected, totalWindowCount: totalWindowCount)
    }

    private func shimmerProbe(signal: AudioSignal, plan: ShimmerProbePlan) -> ShimmerProbe {
        let mono = signal.monoMixdown()
        let analysisMono = representativeSamples(from: mono, ranges: plan.ranges)
        guard !analysisMono.isEmpty else {
            return ShimmerProbe(hiss: -120, shimmer: -120)
        }

        let loudness = MasteringAnalysisService.integratedLoudness(
            signal: AudioSignal(channels: [analysisMono], sampleRate: signal.sampleRate)
        )
        let gain = loudness.isFinite && loudness > -69
            ? powf(10, (-23 - loudness) / 20)
            : 1
        let comparable = analysisMono.map { $0 * gain }
        let hissBand = bandPass(comparable, lower: 8_000, upper: min(20_000, signal.sampleRate * 0.5 - 100), sampleRate: signal.sampleRate)
        let shimmerBand = bandPass(comparable, lower: 8_000, upper: min(14_000, signal.sampleRate * 0.5 - 100), sampleRate: signal.sampleRate)
        return ShimmerProbe(
            hiss: rmsDB(hissBand),
            shimmer: transientPeakDB(shimmerBand, sampleRate: signal.sampleRate)
        )
    }

    private func representativeSamples(from mono: [Float], ranges: [Range<Int>]) -> [Float] {
        guard !mono.isEmpty else { return [] }
        guard !(ranges.count == 1 && ranges[0] == mono.indices) else { return mono }

        var samples: [Float] = []
        samples.reserveCapacity(ranges.reduce(0) { $0 + $1.count })
        for range in ranges {
            samples.append(contentsOf: mono[range])
        }
        return samples
    }

    private func bandPass(_ samples: [Float], lower: Double, upper: Double, sampleRate: Double) -> [Float] {
        guard lower < upper, upper < sampleRate * 0.5 else {
            return Array(repeating: 0, count: samples.count)
        }
        return SpectralDSP.lowPass(
            SpectralDSP.highPass(samples, cutoff: lower, sampleRate: sampleRate),
            cutoff: upper,
            sampleRate: sampleRate
        )
    }

    private func transientPeakDB(_ samples: [Float], sampleRate: Double) -> Double {
        let frameSize = max(128, Int(sampleRate * 0.020))
        let hopSize = max(64, Int(sampleRate * 0.010))
        let frames = frameRMS(samples, frameSize: frameSize, hopSize: hopSize)
        guard frames.count >= 4 else { return rmsDB(samples) }
        return percentile(frames, 0.95)
    }

    private func frameRMS(_ samples: [Float], frameSize: Int, hopSize: Int) -> [Double] {
        guard !samples.isEmpty else { return [] }
        if samples.count <= frameSize {
            return [rmsDB(samples)]
        }

        var values: [Double] = []
        var start = 0
        while start + frameSize <= samples.count {
            values.append(10 * log10(max(rmsEnergy(samples[start..<(start + frameSize)]), 1e-12)))
            start += hopSize
        }
        return values
    }

    private func rmsDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -120 }
        return 10 * log10(max(rmsEnergy(samples[...]), 1e-12))
    }

    private func rmsEnergy(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return samples.reduce(0.0) { partial, sample in
            partial + Double(sample * sample)
        } / Double(samples.count)
    }

    private func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return -120 }
        let sorted = values.sorted()
        let index = max(0, min(sorted.count - 1, Int(round(Double(sorted.count - 1) * percentile))))
        return sorted[index]
    }

    private func processChannel(_ channel: [Float], sampleRate: Double, lower: Double, upper: Double, gain: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 2 else { return channel }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let startBin = bin(for: lower, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        let endBin = bin(for: min(upper, sampleRate * 0.5 - 100), frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        guard endBin > startBin else { return channel }

        let eventEnergy = smoothedEnergy(
            bandEnergy(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep),
            radius: 2
        )
        let threshold = transientThreshold(for: eventEnergy)
        guard threshold > 1e-9 else { return channel }

        let shortEventFrameLimit = max(3, Int((sampleRate * 0.16 / Double(spectrogram.hopSize)).rounded(.up)))
        let requestedReduction = clamped(1 - gain, min: 0, max: 0.60)
        var didReduce = false

        for frameIndex in 0..<spectrogram.frameCount {
            let eventAmount = shortEventPeakAmount(
                in: eventEnergy,
                frameIndex: frameIndex,
                threshold: threshold,
                maxEventFrames: shortEventFrameLimit
            )
            guard eventAmount > 0 else { continue }

            for binIndex in startBin...endBin {
                let frequency = Double(binIndex) * frequencyStep
                let reduction = requestedReduction
                    * (0.35 + eventAmount * 0.65)
                    * frequencyWeight(for: frequency)
                guard reduction > 0 else { continue }
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: max(0.25, 1 - reduction))
                didReduce = true
            }
        }

        guard didReduce else { return channel }
        return preserveUltraAir(original: channel, processed: SpectralDSP.istft(spectrogram), sampleRate: sampleRate)
    }

    private func bandEnergy(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> [Float] {
        let startBin = bin(for: lower, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        let endBin = bin(for: upper, frequencyStep: frequencyStep, maxBin: spectrogram.binCount - 1)
        guard endBin > startBin else {
            return Array(repeating: 0, count: spectrogram.frameCount)
        }

        var values = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            for binIndex in startBin...endBin {
                sum += spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
            }
            values[frameIndex] = sum / Float(endBin - startBin + 1)
        }
        return values
    }

    private func smoothedEnergy(_ energy: [Float], radius: Int) -> [Float] {
        guard !energy.isEmpty, radius > 0 else { return energy }
        return energy.indices.map { index in
            let start = max(0, index - radius)
            let end = min(energy.count - 1, index + radius)
            let sum = energy[start...end].reduce(Float.zero, +)
            return sum / Float(end - start + 1)
        }
    }

    private func transientThreshold(for energy: [Float]) -> Float {
        guard !energy.isEmpty else { return 0 }
        let median = SpectralDSP.percentile(energy, 50)
        let upper = SpectralDSP.percentile(energy, 82)
        return max(median * 1.45, upper)
    }

    private func shortEventPeakAmount(in energy: [Float], frameIndex: Int, threshold: Float, maxEventFrames: Int) -> Float {
        guard energy.indices.contains(frameIndex), threshold > 1e-9 else { return 0 }
        let current = energy[frameIndex]
        guard current > threshold else { return 0 }
        let eventRange = aboveThresholdRange(in: energy, containing: frameIndex, threshold: threshold)
        guard eventRange.count <= maxEventFrames else { return 0 }
        let surroundingMean = surroundingMeanEnergy(in: energy, excluding: eventRange, radius: max(3, maxEventFrames))
        let localThreshold = max(threshold, surroundingMean * 1.22)
        guard current > localThreshold else { return 0 }
        return min(1, (current - localThreshold) / max(current, 1e-6))
    }

    private func aboveThresholdRange(in energy: [Float], containing frameIndex: Int, threshold: Float) -> ClosedRange<Int> {
        var start = frameIndex
        while start > 0, energy[start - 1] > threshold {
            start -= 1
        }

        var end = frameIndex
        while end + 1 < energy.count, energy[end + 1] > threshold {
            end += 1
        }

        return start...end
    }

    private func surroundingMeanEnergy(in energy: [Float], excluding eventRange: ClosedRange<Int>, radius: Int) -> Float {
        guard !energy.isEmpty else { return 0 }
        var sum: Float = 0
        var count = 0
        let beforeStart = max(0, eventRange.lowerBound - radius)
        if beforeStart < eventRange.lowerBound {
            for index in beforeStart..<eventRange.lowerBound {
                sum += energy[index]
                count += 1
            }
        }

        let afterEnd = min(energy.count - 1, eventRange.upperBound + radius)
        if eventRange.upperBound < afterEnd {
            for index in (eventRange.upperBound + 1)...afterEnd {
                sum += energy[index]
                count += 1
            }
        }

        return count > 0 ? sum / Float(count) : 0
    }

    private func frequencyWeight(for frequency: Double) -> Float {
        if frequency < 10_000 { return 0.45 }
        if frequency < 12_000 { return 0.80 }
        if frequency < 16_000 { return 1.00 }
        return 0.70
    }

    private func preserveUltraAir(original: [Float], processed: [Float], sampleRate: Double) -> [Float] {
        guard original.count == processed.count, sampleRate * 0.5 > 16_200 else { return processed }
        let originalUltra = SpectralDSP.highPass(original, cutoff: 16_000, sampleRate: sampleRate)
        let processedUltra = SpectralDSP.highPass(processed, cutoff: 16_000, sampleRate: sampleRate)
        return processed.indices.map { index in
            processed[index] - processedUltra[index] + originalUltra[index]
        }
    }

    private func bin(for frequency: Double, frequencyStep: Double, maxBin: Int) -> Int {
        min(max(Int(frequency / frequencyStep), 0), maxBin)
    }
}

private struct CorrectionHarmonicRepair: Sendable {
    let settings: CorrectionSettings

    func process(signal: AudioSignal, analysis: AnalysisData, prediction: NeuralFoldoverPrediction) -> AudioSignal {
        let defaults = settings.profile.settings
        let cutoff = max(analysis.cutoffFrequency - 1_000, 12_000)
        let harmonicWeight = min(1.25, 0.55 + Float(analysis.dominantHarmonics.count) * 0.08 + analysis.harmonicConfidence * 0.26)
        let shimmerControl = analysis.hasShimmer ? max(0.65, 1 - analysis.shimmerRatio * 1.4) : 1.0
        let deficiency = Float(max(0, 16_000 - analysis.cutoffFrequency) / 4_000)
        let brightnessBoost = max(0.9, min(1.2, 1.02 + (0.55 - analysis.brightnessRatio) * 0.35))
        let harmonicScale = clamped(1 + (settings.harmonicRepairAmount - defaults.harmonicRepairAmount) * 0.70 + (settings.presenceRepair - defaults.presenceRepair) * 0.25, min: 0.60, max: 1.45)
        let noiseGuard = clamped(1.0 - analysis.noiseAmount * 0.60 - analysis.artifactBandRatio * 0.50, min: 0.25, max: 1.0)
        let airScale = clamped(0.35 + (settings.airRepair - defaults.airRepair) * 0.28 - (settings.highNaturalness - defaults.highNaturalness) * 0.30, min: 0.18, max: 0.58) * noiseGuard
        let transientScale = clamped(0.42 + (settings.presenceRepair - defaults.presenceRepair) * 0.20, min: 0.24, max: 0.62) * noiseGuard
        let foldoverScale = clamped(1 + (settings.foldoverRepairAmount - defaults.foldoverRepairAmount) * 0.85 - (settings.highNaturalness - defaults.highNaturalness) * 0.25, min: 0.45, max: 1.45)
        let cleanupGuard = clamped(1 - settings.correctionIntensity * 0.58 - settings.noiseDetectionSensitivity * 0.18, min: 0.28, max: 1.0)
        let baseGain = max(0.03, min(0.16, (0.06 + deficiency * 0.05) * harmonicWeight * shimmerControl)) * harmonicScale * noiseGuard * cleanupGuard
        let airGain = max(
            0,
            min(0.16, (0.05 + deficiency * 0.08) * brightnessBoost - analysis.shimmerRatio * 0.04 + prediction.airGainBias * 0.45)
        ) * (1 - prediction.harshnessGuard * 0.55) * airScale * cleanupGuard
        let transientBoost = max(
            0,
            min(0.12, 0.04 + analysis.transientAmount * 0.03 + prediction.transientBoostBias * 0.45)
        ) * (1 - prediction.harshnessGuard * 0.35) * transientScale * cleanupGuard
        let foldoverMix = max(
            0.02,
            min(0.22, 0.05 + deficiency * 0.11 + analysis.harmonicConfidence * 0.06 - analysis.shimmerRatio * 0.06 + prediction.foldoverMix * 0.70 - 0.12)
        ) * (1 - prediction.harshnessGuard * 0.62) * foldoverScale * noiseGuard * cleanupGuard

        let channels = mapChannelsConcurrently(signal.channels) { channel in
            let folded = foldover(channel: channel, sampleRate: signal.sampleRate, cutoff: cutoff, mix: foldoverMix)
            let excited = channel.map { tanhf($0 * 2.8) - tanhf($0 * 1.1) }
            let presence = SpectralDSP.lowPass(SpectralDSP.highPass(excited, cutoff: cutoff, sampleRate: signal.sampleRate), cutoff: 13_500, sampleRate: signal.sampleRate)
            let air = SpectralDSP.highPass(excited, cutoff: 13_500, sampleRate: signal.sampleRate)
            let body = SpectralDSP.lowPass(channel, cutoff: 4_000, sampleRate: signal.sampleRate)
            let transient = SpectralDSP.highPass(zip(channel, body).map(-), cutoff: 2_500, sampleRate: signal.sampleRate)
            return channel.indices.map {
                let mixed = channel[$0]
                    + folded[$0]
                    + presence[$0] * baseGain
                    + air[$0] * airGain
                    + transient[$0] * transientBoost
                return tanhf(mixed * 0.98)
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func foldover(channel: [Float], sampleRate: Double, cutoff: Double, mix: Float) -> [Float] {
        let fftSize = SpectralDSP.fftSize
        let binCount = fftSize / 2 + 1
        let frequencyStep = sampleRate / Double(fftSize)
        let sourceStart = max(1, min(Int(max(cutoff * 0.5, 5_500) / frequencyStep), binCount - 1))
        let sourceEnd = max(sourceStart, min(Int(min(cutoff * 0.95, 12_000) / frequencyStep), binCount - 1))
        let targetStart = max(sourceStart + 1, min(Int(16_000 / frequencyStep), binCount - 1))
        guard sourceEnd > sourceStart, targetStart < binCount else {
            return Array(repeating: 0, count: channel.count)
        }

        var activeBins: [Int] = []
        var seenBins = Set<Int>()
        for sourceBin in sourceStart...sourceEnd {
            let targetBin = min(binCount - 1, sourceBin * 2)
            guard targetBin >= targetStart, seenBins.insert(targetBin).inserted else { continue }
            activeBins.append(targetBin)
        }

        return SpectralDSP.istftSparseHalfSpectrumFromSTFTFrames(
            channel,
            activeBins: activeBins
        ) { _, sourceBinCount, sourceReal, sourceImag, realFrame, imagFrame in
            for sourceBin in sourceStart...sourceEnd {
                let targetBin = min(sourceBinCount - 1, sourceBin * 2)
                guard targetBin >= targetStart else { continue }
                let normalizedPosition = Float(targetBin - targetStart) / Float(max(sourceBinCount - targetStart - 1, 1))
                let lift = mix * (1 - normalizedPosition * 0.45)
                realFrame[targetBin] += sourceReal[sourceBin] * lift
                imagFrame[targetBin] += sourceImag[sourceBin] * lift
            }
        }
    }
}

private struct PeakSafetyLimiter {
    let peakLimitDB: Float = -1
    let limiterReleaseMs: Float = 120

    func process(signal: AudioSignal) -> AudioSignal {
        let peakLimit = powf(10, peakLimitDB / 20)
        var channels = applyLinkedLimiter(signal.channels, peakLimit: peakLimit, sampleRate: signal.sampleRate)

        let peak = approximateTruePeak(channels: channels)
        if peak > peakLimit {
            let trim = peakLimit / peak
            channels = channels.map { $0.map { $0 * trim } }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func applyLinkedLimiter(_ channels: [[Float]], peakLimit: Float, sampleRate: Double) -> [[Float]] {
        guard let first = channels.first else { return channels }
        guard first.count > 0 else { return channels }

        let releaseCoeff = expf(-1 / max(Float(sampleRate) * limiterReleaseMs * 0.001, 1))
        var gain: Float = 1
        var limited = channels

        for index in 0..<first.count {
            let framePeak = channels.reduce(Float.zero) { partial, channel in
                guard index < channel.count else { return partial }
                return max(partial, abs(channel[index]))
            }

            let desiredGain = framePeak > peakLimit ? peakLimit / max(framePeak, 1e-6) : 1
            if desiredGain < gain {
                gain = desiredGain
            } else {
                gain = gain * releaseCoeff + (1 - releaseCoeff)
            }

            for channelIndex in limited.indices where index < limited[channelIndex].count {
                limited[channelIndex][index] = limited[channelIndex][index] * gain
            }
        }

        return limited
    }

    private func approximateTruePeak(channels: [[Float]]) -> Float {
        channels.map(oversampledPeak).max() ?? 0
    }

    private func oversampledPeak(_ channel: [Float]) -> Float {
        guard channel.count > 1 else { return channel.map { abs($0) }.max() ?? 0 }
        var peak: Float = 0
        for index in 0..<(channel.count - 1) {
            let a = channel[index]
            let b = channel[index + 1]
            for step in 0...3 {
                let t = Float(step) / 4
                peak = max(peak, abs(a * (1 - t) + b * t))
            }
        }
        return peak
    }
}

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.min(maxValue, Swift.max(minValue, value))
}
