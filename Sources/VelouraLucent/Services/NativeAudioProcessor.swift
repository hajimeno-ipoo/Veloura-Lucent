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

struct DenoiseMaskBreakdown: Equatable, Sendable {
    let pass: Int
    let bandOrder: Int
    let band: String
    let sampleCount: Int
    let rawMaskDB: Double
    let granularMaskDB: Double
    let shimmerMaskDB: Double
    let combinedNoiseMaskDB: Double
    let finalMaskDB: Double

    var logMessage: String {
        String(
            format: "ノイズ除去/マスク内訳/pass %d/%@: raw %.2f dB, granular %.2f dB, shimmer %.2f dB, combined %.2f dB, final %.2f dB",
            pass,
            band,
            rawMaskDB,
            granularMaskDB,
            shimmerMaskDB,
            combinedNoiseMaskDB,
            finalMaskDB
        )
    }
}

private final class DenoiseMaskBreakdownCollector: @unchecked Sendable {
    private struct Key: Hashable {
        let pass: Int
        let bandOrder: Int
        let band: String
    }

    private struct Aggregate {
        var sampleCount = 0
        var rawMaskDB = 0.0
        var granularMaskDB = 0.0
        var shimmerMaskDB = 0.0
        var combinedNoiseMaskDB = 0.0
        var finalMaskDB = 0.0

        mutating func add(_ breakdown: DenoiseMaskBreakdown) {
            sampleCount += breakdown.sampleCount
            rawMaskDB += breakdown.rawMaskDB * Double(breakdown.sampleCount)
            granularMaskDB += breakdown.granularMaskDB * Double(breakdown.sampleCount)
            shimmerMaskDB += breakdown.shimmerMaskDB * Double(breakdown.sampleCount)
            combinedNoiseMaskDB += breakdown.combinedNoiseMaskDB * Double(breakdown.sampleCount)
            finalMaskDB += breakdown.finalMaskDB * Double(breakdown.sampleCount)
        }

        func average(pass: Int, bandOrder: Int, band: String) -> DenoiseMaskBreakdown? {
            guard sampleCount > 0 else { return nil }
            let count = Double(sampleCount)
            return DenoiseMaskBreakdown(
                pass: pass,
                bandOrder: bandOrder,
                band: band,
                sampleCount: sampleCount,
                rawMaskDB: rawMaskDB / count,
                granularMaskDB: granularMaskDB / count,
                shimmerMaskDB: shimmerMaskDB / count,
                combinedNoiseMaskDB: combinedNoiseMaskDB / count,
                finalMaskDB: finalMaskDB / count
            )
        }
    }

    private let lock = NSLock()
    private var storage: [Key: Aggregate] = [:]

    func record(_ breakdown: DenoiseMaskBreakdown) {
        let key = Key(pass: breakdown.pass, bandOrder: breakdown.bandOrder, band: breakdown.band)
        lock.lock()
        var aggregate = storage[key] ?? Aggregate()
        aggregate.add(breakdown)
        storage[key] = aggregate
        lock.unlock()
    }

    var summaries: [DenoiseMaskBreakdown] {
        lock.lock()
        defer { lock.unlock() }
        return storage.compactMap { key, aggregate in
            aggregate.average(pass: key.pass, bandOrder: key.bandOrder, band: key.band)
        }
        .sorted { lhs, rhs in
            if lhs.pass != rhs.pass { return lhs.pass < rhs.pass }
            return lhs.bandOrder < rhs.bandOrder
        }
    }
}

enum AudioAnalysisMode: String, CaseIterable, Identifiable, Equatable, Sendable {
    case auto
    case cpu
    case experimentalMetal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto:
            return "自動"
        case .cpu:
            return "安定CPU"
        case .experimentalMetal:
            return "実験Metal"
        }
    }

    var summary: String {
        switch self {
        case .auto:
            return MetalAudioAnalysisProcessor().isAvailable
                ? "このMacでは高速なMetal解析を使います"
                : "Metal解析を使えないためCPU解析を使います"
        case .cpu:
            return "安定した解析を使います"
        case .experimentalMetal:
            return MetalAudioAnalysisProcessor().isAvailable
                ? "解析の一部をMetalで高速化します"
                : "このMacではMetal解析を使えないためCPUへ戻ります"
        }
    }

    var resolvedMode: AudioAnalysisMode {
        switch self {
        case .auto:
            return MetalAudioAnalysisProcessor().isAvailable ? .experimentalMetal : .cpu
        case .experimentalMetal:
            return MetalAudioAnalysisProcessor().isAvailable ? .experimentalMetal : .cpu
        case .cpu:
            return .cpu
        }
    }

    var resolvedSummary: String {
        let resolved = resolvedMode
        if self == resolved {
            return "使用中: \(resolved.title)"
        }
        return "使用中: \(resolved.title)（\(title)から自動切替）"
    }

    var logDescription: String {
        let resolved = resolvedMode
        if self == resolved {
            return "解析モード: \(resolved.title)"
        }
        return "解析モード: \(title) -> \(resolved.title)"
    }
}

struct AudioSeparatedMeanSpectra: Equatable, Sendable {
    let harmonic: [Float]
    let percussive: [Float]
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

        logger?.start(.loadAudio)
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
            logger?.log("ノイズ測定: 既存結果を使用")
        } else {
            routeNoiseMeasurements = measure("routeNoiseMeasurement", label: "ルート用ノイズ測定", recorder: benchmarkRecorder, logger: logger) {
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

        let postDenoiseAnalysis = measure("analyzeDenoised", label: "再解析", recorder: benchmarkRecorder, logger: logger) {
            AudioAnalyzer(mode: resolvedAnalysisMode).analyze(signal: sibilanceGuarded)
        }
        let repairPrediction = measure("neuralPrediction", label: "解析補助", recorder: benchmarkRecorder, logger: logger) {
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
        let mudControlled = measure("correctionMudGuard", label: "補正/計測: 低中域残り確認", recorder: benchmarkRecorder, logger: logger) {
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

        var current = signal
        var didApply = false
        for rule in rules {
            let currentDB = bandRMSDB(signal: current, lower: rule.lower, upper: rule.upper)
            let referenceDB = bandRMSDB(signal: reference, lower: rule.lower, upper: rule.upper)
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
        let candidates: [(mix: Float, signal: AudioSignal)] = [
            (1.0, signal),
            (0.75, blendSignals(base: fallback, boosted: signal, mix: 0.75)),
            (0.60, blendSignals(base: fallback, boosted: signal, mix: 0.60)),
            (0.50, blendSignals(base: fallback, boosted: signal, mix: 0.50)),
            (0.25, blendSignals(base: fallback, boosted: signal, mix: 0.25)),
            (0.10, blendSignals(base: fallback, boosted: signal, mix: 0.10))
        ]

        for (index, candidate) in candidates.enumerated() {
            let measurements = measurementCache.snapshot(
                signalID: "correctionHighPreserve.candidate.\(index)",
                signal: candidate.signal,
                ids: highNoiseIDs
            )
            measurementCount += 1
            let hissReturn = noiseDelta(id: NoiseMeasurementID.hiss, reference: referenceMeasurements, current: measurements)
            let shimmerReturn = noiseDelta(id: NoiseMeasurementID.shimmer, reference: referenceMeasurements, current: measurements)
            let sibilanceReturn = noiseDelta(id: NoiseMeasurementID.sibilance, reference: referenceMeasurements, current: measurements)
            let ultraHighLift = bandRMSDB(signal: candidate.signal, lower: 16_000, upper: 20_000) - fallbackUltraHighDB
            guard hissReturn <= hissCeiling,
                  shimmerReturn <= shimmerCeiling,
                  sibilanceReturn <= sibilanceCeiling,
                  ultraHighLift <= ultraHighLiftCeilingDB
            else { continue }
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
        let upperBound = min(upper, signal.sampleRate * 0.5 - 100)
        guard lower < upperBound else { return -120 }
        let mono = signal.monoMixdown()
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(mono, cutoff: lower, sampleRate: signal.sampleRate),
            cutoff: upperBound,
            sampleRate: signal.sampleRate
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

private struct HumRemover: Sendable {
    let settings: CorrectionSettings

    func process(signal: AudioSignal) -> AudioSignal {
        let detectedBase = dominantHumBase(signal: signal)
        guard let detectedBase else { return signal }

        let intensity = clamped(settings.lowCleanup * 0.55 + settings.noiseDetectionSensitivity * 0.35, min: 0, max: 1)
        let channels = mapChannelsConcurrently(signal.channels) { channel in
            attenuateHarmonics(channel: channel, sampleRate: signal.sampleRate, baseFrequency: detectedBase, intensity: intensity)
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func dominantHumBase(signal: AudioSignal) -> Double? {
        let mono = signal.monoMixdown()
        guard mono.count > 512 else { return nil }

        let candidates = [50.0, 60.0].map { base in
            (base: base, score: humScore(mono: mono, sampleRate: signal.sampleRate, baseFrequency: base))
        }
        guard let best = candidates.max(by: { $0.score < $1.score }), best.score > 8 else {
            return nil
        }
        return best.base
    }

    private func humScore(mono: [Float], sampleRate: Double, baseFrequency: Double) -> Double {
        var harmonic = baseFrequency
        var score = 0.0
        var count = 0
        while harmonic <= min(300, sampleRate * 0.5 - 30) {
            let center = sineMagnitudeDB(mono, frequency: harmonic, sampleRate: sampleRate)
            let lower = sineMagnitudeDB(mono, frequency: max(20, harmonic - 17), sampleRate: sampleRate)
            let upper = sineMagnitudeDB(mono, frequency: min(sampleRate * 0.5 - 20, harmonic + 17), sampleRate: sampleRate)
            score += max(0, center - (lower + upper) * 0.5)
            count += 1
            harmonic += baseFrequency
        }
        return score / Double(max(count, 1))
    }

    private func sineMagnitudeDB(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double {
        var real = 0.0
        var imag = 0.0
        let angular = 2 * Double.pi * frequency / sampleRate
        for index in samples.indices {
            let phase = angular * Double(index)
            let sample = Double(samples[index])
            real += sample * cos(phase)
            imag -= sample * sin(phase)
        }
        let magnitude = sqrt(real * real + imag * imag) * 2 / Double(max(samples.count, 1))
        return 20 * log10(max(magnitude, 1e-12))
    }

    private func attenuateHarmonics(channel: [Float], sampleRate: Double, baseFrequency: Double, intensity: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        var harmonic = baseFrequency
        var harmonicIndex = 1
        while harmonic <= min(300, sampleRate * 0.5 - 30) {
            let centerBin = min(max(Int(round(harmonic / frequencyStep)), 0), spectrogram.binCount - 1)
            let reduction = clamped((0.46 - Float(harmonicIndex - 1) * 0.055) * intensity, min: 0.10, max: 0.46)
            for frameIndex in 0..<spectrogram.frameCount {
                for binIndex in max(0, centerBin - 1)...min(spectrogram.binCount - 1, centerBin + 1) {
                    let distance = abs(binIndex - centerBin)
                    let gain = 1 - reduction * (distance == 0 ? 1 : 0.45)
                    spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
                }
            }
            harmonicIndex += 1
            harmonic += baseFrequency
        }

        return SpectralDSP.istft(spectrogram)
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
        let channels = mapChannelsConcurrently(signal.channels) {
            processChannel($0, sampleRate: signal.sampleRate, intensity: intensity)
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

    private func processChannel(_ channel: [Float], sampleRate: Double, intensity: Float) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }
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
            let gain = clamped(1 - bandWeight * intensity, min: 0.05, max: 1)
            for frameIndex in 0..<spectrogram.frameCount {
                spectrogram.scaleBin(frameIndex: frameIndex, binIndex: binIndex, by: gain)
            }
        }

        return SpectralDSP.istft(spectrogram)
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

struct AudioAnalyzer {
    let mode: AudioAnalysisMode

    init(mode: AudioAnalysisMode = .cpu) {
        self.mode = mode
    }

    func analyze(signal: AudioSignal) -> AnalysisData {
        let mono = signal.monoMixdown()
        let spectrogram = SpectralDSP.stft(mono)
        guard spectrogram.frameCount > 0 else {
            return AnalysisData(
                cutoffFrequency: 16_000,
                dominantHarmonics: [],
                harmonicConfidence: 0,
                hasShimmer: false,
                shimmerRatio: 0,
                brightnessRatio: 0,
                transientAmount: 0,
                noiseAmount: 0,
                rolloffDepth: 0,
                airBandEnergyRatio: 0,
                artifactBandRatio: 0,
                denoiseEffectMetrics: DenoiseEffectMetrics(shimmerFlicker: 0, hf12Magnitude: 0, hf16Magnitude: 0, hf18Magnitude: 0)
            )
        }

        let separatedSpectrum = separatedMeanSpectra(spectrogram: spectrogram)
        let harmonicSpectrum = SpectralDSP.medianFilter(separatedSpectrum.harmonic, windowSize: 7)
        let percussiveSpectrum = SpectralDSP.medianFilter(separatedSpectrum.percussive, windowSize: 5)
        let meanSpectrum = zip(harmonicSpectrum, percussiveSpectrum).map { harmonic, percussive in
            harmonic * 0.78 + percussive * 0.22
        }

        let frequencyStep = signal.sampleRate / Double(spectrogram.fftSize)
        let decibels = SpectralDSP.amplitudeToDecibels(meanSpectrum)
        let cutoffStart = Int(12_000 / frequencyStep)
        let cutoffEnd = min(Int(16_000 / frequencyStep), decibels.count - 1)
        var cutoff = 16_000.0
        var steepestDrop = Float.greatestFiniteMagnitude
        if cutoffEnd > cutoffStart + 1 {
            for index in cutoffStart..<(cutoffEnd - 1) {
                let delta = decibels[index + 1] - decibels[index]
                if delta < steepestDrop {
                    steepestDrop = delta
                    cutoff = Double(index) * frequencyStep
                }
            }
        }

        let harmonicStart = Int(300 / frequencyStep)
        let harmonicEnd = min(Int(800 / frequencyStep), meanSpectrum.count - 1)
        var peaks: [HarmonicPeak] = []
        var harmonicSupport: Float = 0
        if harmonicEnd > harmonicStart + 1 {
            for index in (harmonicStart + 1)..<harmonicEnd {
                let value = harmonicSpectrum[index]
                let localFloor = max(0.015, (harmonicSpectrum[max(harmonicStart, index - 4)...min(harmonicEnd, index + 4)].reduce(0, +) / Float(min(harmonicEnd, index + 4) - max(harmonicStart, index - 4) + 1)) * 1.08)
                if value > harmonicSpectrum[index - 1], value >= harmonicSpectrum[index + 1], value > localFloor {
                    peaks.append(HarmonicPeak(frequency: Double(index) * frequencyStep, magnitude: value))
                    harmonicSupport += value
                }
            }
        }

        let shimmerStart = min(Int(10_000 / frequencyStep), meanSpectrum.count - 1)
        let shimmerEnd = min(Int(14_000 / frequencyStep), meanSpectrum.count - 1)
        let shimmerEnergy = meanSpectrum[shimmerStart...shimmerEnd].reduce(0, +)
        let bodyEnergy = meanSpectrum[0...min(200, meanSpectrum.count - 1)].reduce(0, +)
        let preRolloffEnergy = bandAverage(meanSpectrum, frequencyStep: frequencyStep, lower: 8_000, upper: 12_000)
        let postRolloffEnergy = bandAverage(meanSpectrum, frequencyStep: frequencyStep, lower: 16_000, upper: min(20_000, signal.sampleRate * 0.5))
        let upperBandStart = min(Int(16_000 / frequencyStep), meanSpectrum.count - 1)
        let upperBandEnergy = meanSpectrum[upperBandStart...(meanSpectrum.count - 1)].reduce(0, +)
        let artifactEnergy = bandEnergy(meanSpectrum, frequencyStep: frequencyStep, lower: 18_000, upper: signal.sampleRate * 0.5)
        let centroid = SpectralDSP.spectralCentroid(meanSpectrum, sampleRate: signal.sampleRate, fftSize: spectrogram.fftSize)
        let brightnessRatio = Float(centroid / max(signal.sampleRate * 0.5, 1))
        let transientAmount = estimateTransientAmount(mono)
        let shimmerRatio = shimmerEnergy / max(bodyEnergy + upperBandEnergy, 1e-6)
        let rolloffDepth = min(1.0, max(0, (20 * log10f(max(preRolloffEnergy, 1e-6) / max(postRolloffEnergy, 1e-6))) / 24))
        let airBandEnergyRatio = min(1.0, upperBandEnergy / max(bodyEnergy + upperBandEnergy, 1e-6))
        let artifactBandRatio = min(1.0, artifactEnergy / max(bodyEnergy + upperBandEnergy, 1e-6))
        let harmonicConfidence = min(1.2, harmonicSupport / max(harmonicSupport + percussiveSpectrum[harmonicStart...harmonicEnd].reduce(0, +), 1e-6))
        let noiseAmount = estimateNoiseAmount(
            percussiveSpectrum: percussiveSpectrum,
            meanSpectrum: meanSpectrum,
            frequencyStep: frequencyStep
        )

        return AnalysisData(
            cutoffFrequency: cutoff,
            dominantHarmonics: peaks.sorted { $0.magnitude > $1.magnitude }.prefix(8).map { $0 },
            harmonicConfidence: harmonicConfidence,
            hasShimmer: shimmerEnergy > bodyEnergy * 0.05 || steepestDrop < -4,
            shimmerRatio: shimmerRatio,
            brightnessRatio: brightnessRatio,
            transientAmount: transientAmount,
            noiseAmount: noiseAmount,
            rolloffDepth: rolloffDepth,
            airBandEnergyRatio: airBandEnergyRatio,
            artifactBandRatio: artifactBandRatio,
            denoiseEffectMetrics: denoiseEffectMetrics(from: spectrogram, sampleRate: signal.sampleRate)
        )
    }

    private func denoiseEffectMetrics(from spectrogram: Spectrogram, sampleRate: Double) -> DenoiseEffectMetrics {
        guard spectrogram.frameCount > 0, spectrogram.binCount > 0 else {
            return DenoiseEffectMetrics(shimmerFlicker: 0, hf12Magnitude: 0, hf16Magnitude: 0, hf18Magnitude: 0)
        }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let shimmerStart = binIndex(for: 10_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let shimmerEnd = binIndex(for: 16_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let hf12Start = binIndex(for: 12_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let hf16Start = binIndex(for: 16_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)
        let hf18Start = binIndex(for: 18_000, frequencyStep: frequencyStep, binCount: spectrogram.binCount)

        var hf12Sum: Float = 0
        var hf16Sum: Float = 0
        var hf18Sum: Float = 0
        var previousShimmerMean: Float?
        var shimmerDiffSum: Float = 0
        var shimmerFrameCount = 0

        for frameIndex in 0..<spectrogram.frameCount {
            var shimmerEnergy: Float = 0
            var shimmerCount = 0
            for binIndex in 0..<spectrogram.binCount {
                let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
                if binIndex >= hf12Start { hf12Sum += magnitude }
                if binIndex >= hf16Start { hf16Sum += magnitude }
                if binIndex >= hf18Start { hf18Sum += magnitude }
                if binIndex >= shimmerStart, binIndex <= shimmerEnd {
                    shimmerEnergy += magnitude
                    shimmerCount += 1
                }
            }

            let shimmerMean = shimmerEnergy / Float(max(shimmerCount, 1))
            if let previousShimmerMean {
                shimmerDiffSum += abs(shimmerMean - previousShimmerMean)
            }
            previousShimmerMean = shimmerMean
            shimmerFrameCount += 1
        }

        let frameCount = Float(max(spectrogram.frameCount, 1))
        return DenoiseEffectMetrics(
            shimmerFlicker: shimmerDiffSum / Float(max(shimmerFrameCount - 1, 1)),
            hf12Magnitude: hf12Sum / frameCount,
            hf16Magnitude: hf16Sum / frameCount,
            hf18Magnitude: hf18Sum / frameCount
        )
    }

    private func binIndex(for frequency: Double, frequencyStep: Double, binCount: Int) -> Int {
        min(max(Int(frequency / frequencyStep), 0), binCount - 1)
    }

    private func bandEnergy(_ spectrum: [Float], frequencyStep: Double, lower: Double, upper: Double) -> Float {
        guard !spectrum.isEmpty, frequencyStep > 0 else { return 0 }
        let start = min(max(Int(lower / frequencyStep), 0), spectrum.count - 1)
        let end = min(max(Int(upper / frequencyStep), start), spectrum.count - 1)
        guard end >= start else { return 0 }
        return spectrum[start...end].reduce(0, +)
    }

    private func bandAverage(_ spectrum: [Float], frequencyStep: Double, lower: Double, upper: Double) -> Float {
        guard !spectrum.isEmpty, frequencyStep > 0 else { return 0 }
        let start = min(max(Int(lower / frequencyStep), 0), spectrum.count - 1)
        let end = min(max(Int(upper / frequencyStep), start), spectrum.count - 1)
        guard end >= start else { return 0 }
        return spectrum[start...end].reduce(0, +) / Float(end - start + 1)
    }

    private func separatedMeanSpectra(spectrogram: Spectrogram) -> AudioSeparatedMeanSpectra {
        if mode == .experimentalMetal,
           let separatedSpectrum = MetalAudioAnalysisProcessor().separatedMeanSpectra(spectrogram: spectrogram) {
            return separatedSpectrum
        }
        return cpuSeparatedMeanSpectra(spectrogram: spectrogram)
    }

    private func cpuSeparatedMeanSpectra(spectrogram: Spectrogram) -> AudioSeparatedMeanSpectra {
        guard spectrogram.frameCount > 0, spectrogram.binCount > 0 else {
            return AudioSeparatedMeanSpectra(harmonic: [], percussive: [])
        }

        let frameCount = spectrogram.frameCount
        let binCount = spectrogram.binCount
        var temporalMedian = Array(repeating: Float.zero, count: frameCount * binCount)
        var history = Array(repeating: Float.zero, count: frameCount)

        for binIndex in 0..<binCount {
            spectrogram.fillMagnitudeHistory(binIndex: binIndex, into: &history)
            let filtered = SpectralDSP.medianFilter(history, windowSize: 17)
            for frameIndex in 0..<frameCount {
                temporalMedian[frameIndex * binCount + binIndex] = filtered[frameIndex]
            }
        }

        var harmonicSpectrum = Array(repeating: Float.zero, count: binCount)
        var percussiveSpectrum = Array(repeating: Float.zero, count: binCount)
        var frameMagnitudes = Array(repeating: Float.zero, count: binCount)

        for frameIndex in 0..<frameCount {
            spectrogram.fillMagnitudes(frameIndex: frameIndex, into: &frameMagnitudes)
            let spectralMedian = SpectralDSP.medianFilter(frameMagnitudes, windowSize: 9)
            for binIndex in 0..<binCount {
                let harmonicWeight = temporalMedian[frameIndex * binCount + binIndex]
                let percussiveWeight = spectralMedian[binIndex]
                let total = max(harmonicWeight + percussiveWeight, 1e-6)
                let magnitude = frameMagnitudes[binIndex]
                harmonicSpectrum[binIndex] += magnitude * harmonicWeight / total
                percussiveSpectrum[binIndex] += magnitude * percussiveWeight / total
            }
        }

        let scale = 1 / Float(max(frameCount, 1))
        for binIndex in 0..<binCount {
            harmonicSpectrum[binIndex] *= scale
            percussiveSpectrum[binIndex] *= scale
        }
        return AudioSeparatedMeanSpectra(harmonic: harmonicSpectrum, percussive: percussiveSpectrum)
    }

    private func estimateTransientAmount(_ signal: [Float]) -> Float {
        guard signal.count > 2 else { return 0 }
        var diffSum: Float = 0
        var levelSum: Float = abs(signal[0])
        for index in 1..<signal.count {
            diffSum += abs(signal[index] - signal[index - 1])
            levelSum += abs(signal[index])
        }
        let averageDiff = diffSum / Float(signal.count - 1)
        let averageLevel = max(levelSum / Float(signal.count), 1e-6)
        return min(1.5, averageDiff / averageLevel)
    }

    private func estimateNoiseAmount(percussiveSpectrum: [Float], meanSpectrum: [Float], frequencyStep: Double) -> Float {
        guard !percussiveSpectrum.isEmpty, !meanSpectrum.isEmpty else { return 0 }
        let granularStart = min(max(Int(12_000 / frequencyStep), 0), percussiveSpectrum.count - 1)
        let granularEnd = min(max(Int(20_000 / frequencyStep), granularStart), percussiveSpectrum.count - 1)
        let bodyEnd = min(max(Int(4_000 / frequencyStep), 0), meanSpectrum.count - 1)
        let granularEnergy = percussiveSpectrum[granularStart...granularEnd].reduce(0, +)
        let bodyEnergy = meanSpectrum[0...bodyEnd].reduce(0, +)
        return min(1.0, granularEnergy / max(granularEnergy + bodyEnergy * 0.65, 1e-6))
    }
}

private struct SpectralGateDenoiser: Sendable {
    let settings: CorrectionSettings
    let maskBreakdownCollector: DenoiseMaskBreakdownCollector?

    private var tuning: DenoiseTuning {
        let base = Self.baseTuning(for: settings.profile)
        let defaults = settings.profile.settings
        return DenoiseTuning(
            passes: settings.correctionIntensity < 0.42 ? 1 : (settings.correctionIntensity > 0.66 ? 3 : 2),
            thresholdMultiplier: clamped(
                base.thresholdMultiplier
                    + (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 1.35
                    + (settings.correctionIntensity - defaults.correctionIntensity) * 0.90,
                min: 1.0,
                max: 2.5
            ),
            lowBandFloor: clamped(
                base.lowBandFloor
                    + (settings.originalRetention - defaults.originalRetention) * 0.14
                    - (settings.lowCleanup - defaults.lowCleanup) * 0.26
                    - (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 0.06,
                min: 0.04,
                max: 0.34
            ),
            highBandFloor: clamped(
                base.highBandFloor
                    + (settings.originalRetention - defaults.originalRetention) * 0.12
                    - (settings.correctionIntensity - defaults.correctionIntensity) * 0.18
                    - (settings.highNaturalness - defaults.highNaturalness) * 0.16,
                min: 0.12,
                max: 0.42
            ),
            quietPercentile: clamped(
                base.quietPercentile + (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 28,
                min: 10,
                max: 40
            ),
            transientProtection: clamped(
                base.transientProtection + (settings.originalRetention - defaults.originalRetention) * 0.22,
                min: 0.08,
                max: 0.42
            ),
            granularReduction: clamped(
                base.granularReduction
                    + (settings.correctionIntensity - defaults.correctionIntensity) * 0.40
                    + (settings.highNaturalness - defaults.highNaturalness) * 0.34
                    + (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 0.18,
                min: 0.10,
                max: 0.72
            ),
            shimmerStabilization: clamped(
                base.shimmerStabilization
                    + (settings.highNaturalness - defaults.highNaturalness) * 0.42
                    + (settings.noiseDetectionSensitivity - defaults.noiseDetectionSensitivity) * 0.12,
                min: 0.04,
                max: 0.48
            ),
            coreProtection: clamped(
                base.coreProtection + (settings.coreProtection - defaults.coreProtection) * 0.35,
                min: 0.20,
                max: 0.78
            ),
            exceptionRelaxation: clamped(
                base.exceptionRelaxation
                    + (settings.originalRetention - defaults.originalRetention) * 0.20
                    + (settings.stereoProtection - defaults.stereoProtection) * 0.08,
                min: 0.25,
                max: 0.70
            )
        )
    }

    private static func baseTuning(for strength: DenoiseStrength) -> DenoiseTuning {
        switch strength {
        case .gentle:
            return DenoiseTuning(passes: 1, thresholdMultiplier: 1.28, lowBandFloor: 0.22, highBandFloor: 0.33, quietPercentile: 16, transientProtection: 0.28, granularReduction: 0.18, shimmerStabilization: 0.08, coreProtection: 0.30, exceptionRelaxation: 0.36)
        case .balanced:
            return DenoiseTuning(passes: 2, thresholdMultiplier: 1.46, lowBandFloor: 0.16, highBandFloor: 0.28, quietPercentile: 20, transientProtection: 0.22, granularReduction: 0.26, shimmerStabilization: 0.13, coreProtection: 0.42, exceptionRelaxation: 0.46)
        case .strong:
            return DenoiseTuning(passes: 3, thresholdMultiplier: 1.85, lowBandFloor: 0.10, highBandFloor: 0.14, quietPercentile: 30, transientProtection: 0.12, granularReduction: 0.48, shimmerStabilization: 0.24, coreProtection: 0.50, exceptionRelaxation: 0.40)
        }
    }

    func process(signal: AudioSignal) -> AudioSignal {
        let channels = mapChannelsConcurrently(signal.channels) { channel in
            var current = channel
            for passIndex in 0..<tuning.passes {
                current = processPass(current, sampleRate: signal.sampleRate, pass: passIndex + 1)
            }
            return current
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func processPass(_ channel: [Float], sampleRate: Double, pass: Int) -> [Float] {
        var spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return channel }
        let binCount = spectrogram.binCount
        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let shimmerStartBin = min(max(Int(10_000 / frequencyStep), 0), binCount - 1)
        let shimmerEndBin = min(max(Int(16_000 / frequencyStep), shimmerStartBin), binCount - 1)
        let airStartBin = min(max(Int(18_000 / frequencyStep), 0), binCount - 1)
        let hasAirBand = sampleRate * 0.5 >= 18_000
        let coefficients = DenoiseMaskCoefficients(
            binCount: binCount,
            lowBandFloor: tuning.lowBandFloor,
            highBandFloor: tuning.highBandFloor
        )
        var noiseProfile = Array(repeating: Float.zero, count: binCount)
        var granularProfile = Array(repeating: Float.zero, count: binCount)
        var maskBreakdowns = maskBreakdownCollector == nil ? [] : [
            DenoiseMaskBreakdownAccumulator(bandOrder: 0, band: "8-12kHz", lower: 8_000, upper: 12_000),
            DenoiseMaskBreakdownAccumulator(bandOrder: 1, band: "12-16kHz", lower: 12_000, upper: 16_000),
            DenoiseMaskBreakdownAccumulator(bandOrder: 2, band: "16-20kHz", lower: 16_000, upper: 20_000)
        ]
        let frameEnergy = spectrogram.frameAverageMagnitudes()
        let quietThreshold = SpectralDSP.percentile(frameEnergy, tuning.quietPercentile)
        let quietFrameIndices = frameEnergy.enumerated().compactMap { index, value in
            value <= quietThreshold ? index : nil
        }
        let sourceFrameIndices = quietFrameIndices.isEmpty ? Array(0..<spectrogram.frameCount) : quietFrameIndices
        var isSourceFrame = Array(repeating: false, count: spectrogram.frameCount)
        for frameIndex in sourceFrameIndices {
            isSourceFrame[frameIndex] = true
        }
        var noiseSums = Array(repeating: Float.zero, count: binCount)
        var noiseMinimums = Array(repeating: Float.greatestFiniteMagnitude, count: binCount)
        var magnitudesByBin = Array(repeating: [Float](), count: binCount)
        var granularSums = Array(repeating: Float.zero, count: binCount)
        let smoothedFrameEnergy = SpectralDSP.movingAverage(frameEnergy, windowSize: 7)
        let highBandMusicalProtection = HighBandMusicalProtection(
            spectrogram: spectrogram,
            frequencyStep: frequencyStep,
            frameEnergy: frameEnergy
        )

        for frameIndex in 0..<spectrogram.frameCount {
            let frameStart = frameIndex * binCount
            let previousFrameStart = frameStart - binCount
            for binIndex in 0..<binCount {
                let index = frameStart + binIndex
                let magnitude = hypotf(spectrogram.real[index], spectrogram.imag[index])
                magnitudesByBin[binIndex].append(magnitude)
                if isSourceFrame[frameIndex] {
                    noiseSums[binIndex] += magnitude
                    noiseMinimums[binIndex] = min(noiseMinimums[binIndex], magnitude)
                }
                if frameIndex > 0 {
                    let previousIndex = previousFrameStart + binIndex
                    let previous = hypotf(spectrogram.real[previousIndex], spectrogram.imag[previousIndex])
                    granularSums[binIndex] += abs(magnitude - previous)
                }
            }
        }

        let sourceCount = Float(max(sourceFrameIndices.count, 1))
        var shimmerEnergy: Float = 0
        var airEnergy: Float = 0
        for binIndex in 0..<binCount {
            let averageNoise = noiseSums[binIndex] / sourceCount
            let minimumNoise = noiseMinimums[binIndex].isFinite ? noiseMinimums[binIndex] : averageNoise
            let percentileNoise = SpectralDSP.percentile(magnitudesByBin[binIndex], 12)
            let baseNoise = averageNoise * 0.55 + minimumNoise * 0.20 + percentileNoise * 0.25
            noiseProfile[binIndex] = baseNoise * coefficients.highBandBias[binIndex]
            let granularAverage = granularSums[binIndex] / Float(max(spectrogram.frameCount, 1))
            granularProfile[binIndex] = granularAverage * coefficients.granularProfileScale[binIndex]
            if binIndex >= shimmerStartBin, binIndex <= shimmerEndBin {
                shimmerEnergy += averageNoise
            } else if hasAirBand, binIndex >= airStartBin {
                airEnergy += averageNoise
            }
        }
        let shimmerExceptionRelaxation = DenoiseShimmerStabilizer.exceptionRelaxation(
            airEnergy: airEnergy,
            shimmerEnergy: shimmerEnergy,
            maximum: tuning.exceptionRelaxation
        )
        var frequencyByBin = Array(repeating: 0.0, count: binCount)
        var thresholdByBin = Array(repeating: Float.zero, count: binCount)
        var baseFloorByBin = Array(repeating: Float.zero, count: binCount)
        var granularThresholdByBin = Array(repeating: Float.zero, count: binCount)
        var highBandWeightByBin = Array(repeating: Float.zero, count: binCount)
        var transientLiftScaleByBin = Array(repeating: Float.zero, count: binCount)
        for binIndex in 0..<binCount {
            let frequency = Double(binIndex) * frequencyStep
            frequencyByBin[binIndex] = frequency
            thresholdByBin[binIndex] = noiseProfile[binIndex] * tuning.thresholdMultiplier * coefficients.thresholdScale[binIndex]
            baseFloorByBin[binIndex] = coefficients.floor[binIndex]
            granularThresholdByBin[binIndex] = granularProfile[binIndex] * coefficients.granularThresholdScale[binIndex]
            highBandWeightByBin[binIndex] = min(1, max(0, Float((frequency - 8_000) / 8_000)))
            transientLiftScaleByBin[binIndex] = Self.transientProtectionLiftScale(frequency: frequency)
        }

        for frameIndex in 0..<spectrogram.frameCount {
            let transientRatio = frameEnergy[frameIndex] / max(smoothedFrameEnergy[frameIndex], 1e-6)
            let frameTransientLift = max(0, min(0.35, (transientRatio - 1) * tuning.transientProtection))
            let frameStart = frameIndex * binCount
            let previousFrameStart = frameStart - binCount
            for binIndex in 0..<binCount {
                let index = frameStart + binIndex
                let magnitude = hypotf(spectrogram.real[index], spectrogram.imag[index])
                let threshold = thresholdByBin[binIndex]
                let baseFloor = baseFloorByBin[binIndex]
                let granularActivity: Float
                if frameIndex > 0 {
                    let previousIndex = previousFrameStart + binIndex
                    let previous = hypotf(spectrogram.real[previousIndex], spectrogram.imag[previousIndex])
                    granularActivity = abs(magnitude - previous)
                } else {
                    granularActivity = 0
                }
                let granularThreshold = granularThresholdByBin[binIndex]
                let granularExcess = max(0, granularActivity - granularThreshold)
                let frequency = frequencyByBin[binIndex]
                let floor = DenoiseMaskCoefficients.protectedFloor(
                    baseFloor: baseFloor,
                    frequency: frequency,
                    magnitude: magnitude,
                    noiseLevel: noiseProfile[binIndex],
                    granularActivity: granularActivity,
                    granularBaseline: granularProfile[binIndex],
                    coreProtection: tuning.coreProtection
                )
                let highFloorLift = highBandMusicalProtection.floorLift(frameIndex: frameIndex, binIndex: binIndex, pass: pass)
                let protectedRawFloor = min(
                    0.995,
                    floor + highFloorLift
                )
                let rawMask = max(floor, min(1.0, (magnitude - threshold) / max(magnitude, 1e-6)))
                let granularMask = max(
                    floor,
                    1 - min(0.72, granularExcess / max(magnitude + granularThreshold, 1e-6)) * tuning.granularReduction
                )
                let shimmerMask = shimmerStabilizationMask(
                    spectrogram: spectrogram,
                    frameIndex: frameIndex,
                    binIndex: binIndex,
                    magnitude: magnitude,
                    shimmerStartBin: shimmerStartBin,
                    shimmerEndBin: shimmerEndBin,
                    transientLift: frameTransientLift * transientLiftScaleByBin[binIndex],
                    exceptionRelaxation: shimmerExceptionRelaxation
                )
                let highBandWeight = highBandWeightByBin[binIndex]
                let highProtectionWeight = min(1, highFloorLift / 0.30)
                let nonTonalHighReduction = highBandWeight * (1 - highProtectionWeight) * 0.03
                let nonTonalAwareRawMask = max(floor, rawMask - nonTonalHighReduction)
                let protectedRawMask = max(protectedRawFloor, nonTonalAwareRawMask)
                let combinedNoiseMask = protectedRawMask * (1 - highBandWeight) + min(protectedRawMask, granularMask) * highBandWeight
                let mask = min(
                    1.0,
                    max(floor, min(combinedNoiseMask, shimmerMask))
                        + frameTransientLift * transientLiftScaleByBin[binIndex]
                )
                if !maskBreakdowns.isEmpty {
                    for breakdownIndex in maskBreakdowns.indices where maskBreakdowns[breakdownIndex].contains(frequency) {
                        maskBreakdowns[breakdownIndex].record(
                            rawMask: protectedRawMask,
                            granularMask: granularMask,
                            shimmerMask: shimmerMask,
                            combinedNoiseMask: combinedNoiseMask,
                            finalMask: mask
                        )
                    }
                }
                spectrogram.real[index] *= mask
                spectrogram.imag[index] *= mask
            }
        }

        if let maskBreakdownCollector {
            for breakdown in maskBreakdowns.compactMap({ $0.summary(pass: pass) }) {
                maskBreakdownCollector.record(breakdown)
            }
        }

        return SpectralDSP.istft(spectrogram)
    }

    private func transientProtectionLift(frameLift: Float, frequency: Double) -> Float {
        frameLift * Self.transientProtectionLiftScale(frequency: frequency)
    }

    private static func transientProtectionLiftScale(frequency: Double) -> Float {
        if frequency < 5_000 {
            return 1
        }
        if frequency < 10_000 {
            return 0.5
        }
        if frequency < 16_000 {
            return 0.2
        }
        return 0
    }

    private func shimmerStabilizationMask(
        spectrogram: Spectrogram,
        frameIndex: Int,
        binIndex: Int,
        magnitude: Float,
        shimmerStartBin: Int,
        shimmerEndBin: Int,
        transientLift: Float,
        exceptionRelaxation: Float
    ) -> Float {
        guard tuning.shimmerStabilization > 0 else { return 1 }
        guard binIndex >= shimmerStartBin, binIndex <= shimmerEndBin else { return 1 }
        guard frameIndex > 0, frameIndex + 1 < spectrogram.frameCount else { return 1 }

        let previousIndex = spectrogram.storageIndex(frameIndex: frameIndex - 1, binIndex: binIndex)
        let nextIndex = spectrogram.storageIndex(frameIndex: frameIndex + 1, binIndex: binIndex)
        let previous = hypotf(spectrogram.real[previousIndex], spectrogram.imag[previousIndex])
        let next = hypotf(spectrogram.real[nextIndex], spectrogram.imag[nextIndex])
        let temporalAverage = (previous + next) * 0.5
        let temporalExcessRatio = max(0, (magnitude - temporalAverage) / max(magnitude + temporalAverage, 1e-6))
        guard temporalExcessRatio > 0 else { return 1 }

        let bandPosition = Float(binIndex - shimmerStartBin) / Float(max(shimmerEndBin - shimmerStartBin, 1))
        return DenoiseShimmerStabilizer.mask(
            temporalExcessRatio: temporalExcessRatio,
            bandPosition: bandPosition,
            transientLift: transientLift,
            stabilization: tuning.shimmerStabilization,
            exceptionRelaxation: exceptionRelaxation
        )
    }
}

private struct DenoiseMaskBreakdownAccumulator {
    let bandOrder: Int
    let band: String
    let lower: Double
    let upper: Double
    private var sampleCount = 0
    private var rawMaskDB = 0.0
    private var granularMaskDB = 0.0
    private var shimmerMaskDB = 0.0
    private var combinedNoiseMaskDB = 0.0
    private var finalMaskDB = 0.0

    init(bandOrder: Int, band: String, lower: Double, upper: Double) {
        self.bandOrder = bandOrder
        self.band = band
        self.lower = lower
        self.upper = upper
    }

    func contains(_ frequency: Double) -> Bool {
        frequency >= lower && frequency < upper
    }

    mutating func record(rawMask: Float, granularMask: Float, shimmerMask: Float, combinedNoiseMask: Float, finalMask: Float) {
        sampleCount += 1
        rawMaskDB += Self.decibels(rawMask)
        granularMaskDB += Self.decibels(granularMask)
        shimmerMaskDB += Self.decibels(shimmerMask)
        combinedNoiseMaskDB += Self.decibels(combinedNoiseMask)
        finalMaskDB += Self.decibels(finalMask)
    }

    func summary(pass: Int) -> DenoiseMaskBreakdown? {
        guard sampleCount > 0 else { return nil }
        let count = Double(sampleCount)
        return DenoiseMaskBreakdown(
            pass: pass,
            bandOrder: bandOrder,
            band: band,
            sampleCount: sampleCount,
            rawMaskDB: rawMaskDB / count,
            granularMaskDB: granularMaskDB / count,
            shimmerMaskDB: shimmerMaskDB / count,
            combinedNoiseMaskDB: combinedNoiseMaskDB / count,
            finalMaskDB: finalMaskDB / count
        )
    }

    private static func decibels(_ gain: Float) -> Double {
        20 * log10(max(Double(gain), 1e-6))
    }
}

private struct HighBandMusicalProtection {
    private struct Band {
        let lower: Double
        let upper: Double
        let baseLift: Float
        let secondPassLift: Float
        let frameLift: [Float]

        func contains(_ frequency: Double) -> Bool {
            frequency >= lower && frequency < upper
        }
    }

    private let bands: [Band]
    private let bandIndexByBin: [Int?]

    init(spectrogram: Spectrogram, frequencyStep: Double, frameEnergy: [Float]) {
        let bodyEnergy = Self.bandEnergy(in: spectrogram, lower: 160, upper: 5_000, frequencyStep: frequencyStep)
        let bodyReference = max(SpectralDSP.percentile(bodyEnergy, 50), 1e-7)
        let frameReference = max(SpectralDSP.percentile(frameEnergy, 50), 1e-7)
        let quietFrameThreshold = SpectralDSP.percentile(frameEnergy, 20)
        let bodyWeights = bodyEnergy.indices.map { index -> Float in
            let bodyRatio = bodyEnergy[index] / bodyReference
            let frameRatio = frameEnergy[index] / frameReference
            let bodyWeight = clamped((bodyRatio - 0.20) / 0.55, min: 0, max: 1)
            let frameWeight = clamped((frameRatio - 0.30) / 0.50, min: 0, max: 1)
            return bodyWeight * frameWeight
        }

        let builtBands = [
            Self.makeBand(
                spectrogram: spectrogram,
                frequencyStep: frequencyStep,
                lower: 8_000,
                upper: 12_000,
                baseLift: 0.98,
                secondPassLift: 0.05,
                frameEnergy: frameEnergy,
                quietFrameThreshold: quietFrameThreshold,
                bodyWeights: bodyWeights
            ),
            Self.makeBand(
                spectrogram: spectrogram,
                frequencyStep: frequencyStep,
                lower: 12_000,
                upper: 16_000,
                baseLift: 1.05,
                secondPassLift: 0.06,
                frameEnergy: frameEnergy,
                quietFrameThreshold: quietFrameThreshold,
                bodyWeights: bodyWeights
            ),
            Self.makeBand(
                spectrogram: spectrogram,
                frequencyStep: frequencyStep,
                lower: 16_000,
                upper: 20_000,
                baseLift: 0.94,
                secondPassLift: 0.04,
                frameEnergy: frameEnergy,
                quietFrameThreshold: quietFrameThreshold,
                bodyWeights: bodyWeights
            )
        ]
        bands = builtBands
        bandIndexByBin = (0..<spectrogram.binCount).map { binIndex in
            let frequency = Double(binIndex) * frequencyStep
            return builtBands.firstIndex(where: { $0.contains(frequency) })
        }
    }

    func floorLift(frameIndex: Int, binIndex: Int, pass: Int) -> Float {
        guard bandIndexByBin.indices.contains(binIndex),
              let bandIndex = bandIndexByBin[binIndex],
              bands.indices.contains(bandIndex),
              bands[bandIndex].frameLift.indices.contains(frameIndex)
        else {
            return 0
        }
        let band = bands[bandIndex]
        let passLift = pass > 1 ? band.secondPassLift : 0
        return band.frameLift[frameIndex] + passLift * min(1, band.frameLift[frameIndex] / max(band.baseLift, 1e-6))
    }

    private static func makeBand(
        spectrogram: Spectrogram,
        frequencyStep: Double,
        lower: Double,
        upper: Double,
        baseLift: Float,
        secondPassLift: Float,
        frameEnergy: [Float],
        quietFrameThreshold: Float,
        bodyWeights: [Float]
    ) -> Band {
        let energy = bandEnergy(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep)
        let peakShare = bandPeakShare(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep)
        let smoothed = SpectralDSP.movingAverage(energy, windowSize: 9)
        let reference = max(SpectralDSP.percentile(energy, 50), 1e-7)
        let quietEnergy = energy.indices.compactMap { index -> Float? in
            frameEnergy.indices.contains(index) && frameEnergy[index] <= quietFrameThreshold ? energy[index] : nil
        }
        let quietReference = max(SpectralDSP.percentile(quietEnergy.isEmpty ? energy : quietEnergy, 50), 1e-7)
        let lift = energy.indices.map { index -> Float in
            let presence = clamped((energy[index] / reference - 0.20) / 0.50, min: 0, max: 1)
            let stability = clamped(
                1 - abs(energy[index] - smoothed[index]) / max(smoothed[index], 1e-7) * 1.2,
                min: 0,
                max: 1
            )
            let tonalWeight = clamped((peakShare[index] - 0.06) / 0.10, min: 0, max: 1)
            let quietExcessWeight = clamped((energy[index] / quietReference - 1.05) / 0.90, min: 0, max: 1)
            let musicalHighWeight = max(tonalWeight, quietExcessWeight)
            let bodyWeight = bodyWeights.indices.contains(index) ? bodyWeights[index] : 0
            return baseLift * bodyWeight * presence * stability * musicalHighWeight
        }

        return Band(lower: lower, upper: upper, baseLift: baseLift, secondPassLift: secondPassLift, frameLift: lift)
    }

    private static func bandEnergy(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> [Float] {
        let (startBin, endBin) = binRange(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep)
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

    private static func bandPeakShare(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> [Float] {
        let (startBin, endBin) = binRange(in: spectrogram, lower: lower, upper: upper, frequencyStep: frequencyStep)
        guard endBin > startBin else {
            return Array(repeating: 0, count: spectrogram.frameCount)
        }

        var values = Array(repeating: Float.zero, count: spectrogram.frameCount)
        for frameIndex in 0..<spectrogram.frameCount {
            var sum: Float = 0
            var peak: Float = 0
            for binIndex in startBin...endBin {
                let magnitude = spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex)
                sum += magnitude
                peak = max(peak, magnitude)
            }
            values[frameIndex] = peak / max(sum, 1e-7)
        }
        return values
    }

    private static func binRange(in spectrogram: Spectrogram, lower: Double, upper: Double, frequencyStep: Double) -> (Int, Int) {
        let maxBin = spectrogram.binCount - 1
        let startBin = min(max(Int(lower / frequencyStep), 0), maxBin)
        let endBin = min(max(Int(upper / frequencyStep), startBin), maxBin)
        return (startBin, endBin)
    }
}

struct DenoiseMaskCoefficients: Sendable {
    let highBandBias: [Float]
    let granularProfileScale: [Float]
    let thresholdScale: [Float]
    let floor: [Float]
    let granularThresholdScale: [Float]

    init(binCount: Int, lowBandFloor: Float, highBandFloor: Float) {
        let denominator = Float(max(binCount - 1, 1))
        var highBandBias: [Float] = []
        var granularProfileScale: [Float] = []
        var thresholdScale: [Float] = []
        var floor: [Float] = []
        var granularThresholdScale: [Float] = []
        highBandBias.reserveCapacity(binCount)
        granularProfileScale.reserveCapacity(binCount)
        thresholdScale.reserveCapacity(binCount)
        floor.reserveCapacity(binCount)
        granularThresholdScale.reserveCapacity(binCount)

        for binIndex in 0..<binCount {
            let normalizedBand = Float(binIndex) / denominator
            highBandBias.append(0.90 + powf(normalizedBand, 1.25) * 0.08)
            granularProfileScale.append(max(0, (normalizedBand - 0.42) / 0.58))
            thresholdScale.append(0.90 + powf(normalizedBand, 1.1) * 0.12)
            floor.append(lowBandFloor + (highBandFloor - lowBandFloor) * powf(normalizedBand, 1.25))
            granularThresholdScale.append(1.1 + normalizedBand * 0.6)
        }

        self.highBandBias = highBandBias
        self.granularProfileScale = granularProfileScale
        self.thresholdScale = thresholdScale
        self.floor = floor
        self.granularThresholdScale = granularThresholdScale
    }

    static func protectedFloor(
        baseFloor: Float,
        frequency: Double,
        magnitude: Float,
        noiseLevel: Float,
        granularActivity: Float,
        granularBaseline: Float,
        coreProtection: Float
    ) -> Float {
        guard coreProtection > 0, frequency <= 5_000 else { return baseFloor }
        guard magnitude > noiseLevel * 1.2 else { return baseFloor }

        let bandWeight: Float
        if frequency <= 1_200 {
            bandWeight = 1
        } else {
            bandWeight = max(0, Float((5_000 - frequency) / 3_800))
        }

        let stabilityRatio = granularActivity / max(magnitude + granularBaseline, 1e-6)
        let stableWeight = max(0, 1 - min(1, stabilityRatio * 2.2))
        let lift = (1 - baseFloor) * coreProtection * bandWeight * stableWeight * 0.22
        return min(0.46, baseFloor + lift)
    }
}

struct DenoiseShimmerStabilizer: Sendable {
    static func exceptionRelaxation(airEnergy: Float, shimmerEnergy: Float, maximum: Float) -> Float {
        guard maximum > 0, shimmerEnergy > 1e-6 else { return 0 }

        let airRatio = airEnergy / max(shimmerEnergy, 1e-6)
        let normalized = max(0, min(1, (airRatio - 0.28) / 0.55))
        return normalized * maximum
    }

    static func mask(
        temporalExcessRatio: Float,
        bandPosition: Float,
        transientLift: Float,
        stabilization: Float,
        exceptionRelaxation: Float
    ) -> Float {
        guard temporalExcessRatio > 0, stabilization > 0 else { return 1 }

        let bandWeight = 0.75 + sinf(bandPosition * .pi) * 0.25
        let transientProtection = max(0.35, 1 - transientLift * 1.6)
        let effectiveStabilization = stabilization * max(0, 1 - exceptionRelaxation)
        let reduction = min(0.42, temporalExcessRatio * effectiveStabilization * bandWeight * transientProtection)
        return 1 - reduction
    }
}

private struct DenoiseTuning: Sendable {
    let passes: Int
    let thresholdMultiplier: Float
    let lowBandFloor: Float
    let highBandFloor: Float
    let quietPercentile: Float
    let transientProtection: Float
    let granularReduction: Float
    let shimmerStabilization: Float
    let coreProtection: Float
    let exceptionRelaxation: Float
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
        let spectrogram = SpectralDSP.stft(channel)
        guard spectrogram.frameCount > 0 else { return Array(repeating: 0, count: channel.count) }

        let frequencyStep = sampleRate / Double(spectrogram.fftSize)
        let sourceStart = max(1, min(Int(max(cutoff * 0.5, 5_500) / frequencyStep), spectrogram.binCount - 1))
        let sourceEnd = max(sourceStart, min(Int(min(cutoff * 0.95, 12_000) / frequencyStep), spectrogram.binCount - 1))
        let targetStart = max(sourceStart + 1, min(Int(16_000 / frequencyStep), spectrogram.binCount - 1))
        guard sourceEnd > sourceStart, targetStart < spectrogram.binCount else {
            return Array(repeating: 0, count: channel.count)
        }

        var activeBins: [Int] = []
        var seenBins = Set<Int>()
        for sourceBin in sourceStart...sourceEnd {
            let targetBin = min(spectrogram.binCount - 1, sourceBin * 2)
            guard targetBin >= targetStart, seenBins.insert(targetBin).inserted else { continue }
            activeBins.append(targetBin)
        }

        return SpectralDSP.istftSparseHalfSpectrum(
            frameCount: spectrogram.frameCount,
            fftSize: spectrogram.fftSize,
            hopSize: spectrogram.hopSize,
            originalLength: spectrogram.originalLength,
            leadingPadding: spectrogram.leadingPadding,
            trailingPadding: spectrogram.trailingPadding,
            activeBins: activeBins
        ) { frameIndex, realFrame, imagFrame in
            for sourceBin in sourceStart...sourceEnd {
                let targetBin = min(spectrogram.binCount - 1, sourceBin * 2)
                guard targetBin >= targetStart else { continue }
                let normalizedPosition = Float(targetBin - targetStart) / Float(max(spectrogram.binCount - targetStart - 1, 1))
                let lift = mix * (1 - normalizedPosition * 0.45)
                let sourceIndex = spectrogram.storageIndex(frameIndex: frameIndex, binIndex: sourceBin)
                realFrame[targetBin] += spectrogram.real[sourceIndex] * lift
                imagFrame[targetBin] += spectrogram.imag[sourceIndex] * lift
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
