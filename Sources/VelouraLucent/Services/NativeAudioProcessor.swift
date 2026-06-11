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
        let repairPrediction = measure("foldoverRepairPrediction", label: "解析補助", recorder: benchmarkRecorder, logger: logger, progressStep: .analysisAssist) {
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

private func clamped(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
    Swift.min(maxValue, Swift.max(minValue, value))
}
