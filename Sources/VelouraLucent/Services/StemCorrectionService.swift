import Foundation

protocol StemCorrectionAudioEvaluating: Sendable {
    func evaluate(
        signal: AudioSignal,
        request: StemAudioEvaluationRequest
    ) async throws -> StemAudioEvaluationSnapshot
}

private struct ProductionStemCorrectionAudioEvaluator: StemCorrectionAudioEvaluating {
    func evaluate(
        signal: AudioSignal,
        request: StemAudioEvaluationRequest
    ) async throws -> StemAudioEvaluationSnapshot {
        try await StemAudioEvaluationService.evaluate(signal: signal, request: request)
    }
}

protocol StemRoleAnalyzing: Sendable {
    func analyzeWithProtection(
        role: StemRole,
        processingSignal48000: AudioSignal
    ) throws -> StemRoleAnalysisResult
}

extension StemRoleAnalysisService: StemRoleAnalyzing {}

private struct StemCorrectionLogger: AudioProcessingLogger {
    let logHandler: @Sendable (String) -> Void

    func log(_ message: String) {
        logHandler(message)
    }
}

/// Executes Standard Mode's proven lower correction stages for one separated stem.
///
/// A deterministic stage plan is fixed before the first DSP stage. Each reused lower DSP owns its
/// existing Standard Mode guard and returns the only signal passed to the next stage. Stem Mode
/// adds a role-specific protection guard to the same single path without generating or ranking
/// alternative completed outputs. Individual-stem peak limiting is deliberately absent; the existing
/// mastering path owns final peak control after pure sum.
struct StemCorrectionService: StemCorrecting, Sendable {
    private let processor: NativeAudioProcessor
    private let evaluator: any StemCorrectionAudioEvaluating
    private let roleAnalyzer: any StemRoleAnalyzing
    private let roleProtector: any StemRoleProtectionGuarding

    private static let routedStages: [(StemCorrectionStage, CorrectionRouteStep)] = [
        (.lowNoiseCleanup, .lowNoiseCleanup),
        (.denoise, .denoise),
        (.sibilanceShimmerProtection, .sibilanceShimmerGuard),
        (.harmonicRepair, .harmonicRepair),
        (.repairShimmerProtection, .repairShimmerGuard),
        (.lowMidResidueControl, .lowMidResidueGuard),
        (.shimmerPeakControl, .shimmerPeakLimit),
    ]

    init(
        processor: NativeAudioProcessor = NativeAudioProcessor(),
        evaluator: any StemCorrectionAudioEvaluating = ProductionStemCorrectionAudioEvaluator(),
        roleAnalyzer: any StemRoleAnalyzing = StemRoleAnalysisService(),
        roleProtector: any StemRoleProtectionGuarding = StemRoleProtectionGuardService()
    ) {
        self.processor = processor
        self.evaluator = evaluator
        self.roleAnalyzer = roleAnalyzer
        self.roleProtector = roleProtector
    }

    func correct(
        runID: UUID,
        role: StemRole,
        rawSignal: AudioSignal,
        rawEvaluation: StemAudioEvaluationSnapshot,
        settings: CorrectionSettings,
        progressHandler: @escaping @Sendable (StemModeProcessProgressEvent) -> Void,
        logHandler: @escaping @Sendable (String) -> Void
    ) async throws -> StemCorrectionSignalResult {
        guard rawEvaluation.purpose == .rawStem(role: role) else {
            throw StemCorrectionError.invalidEvaluationPurpose(role: role)
        }
        guard let originalAnalysis = rawEvaluation.audioAnalysis else {
            throw StemCorrectionError.missingAudioAnalysis(role: role)
        }

        let logger = StemCorrectionLogger(logHandler: logHandler)
        logHandler("【\(role.stemModeDisplayTitle)】")
        progressHandler(.init(
            runID: runID,
            step: .roleAnalysis(role),
            status: .running,
            fraction: 0,
            detail: "\(role.stemModeDisplayTitle)の役割別解析中"
        ))
        let roleAnalysis = try roleAnalyzer.analyzeWithProtection(
            role: role,
            processingSignal48000: rawSignal
        )
        logHandler("役割別解析を完了しました")
        progressHandler(.init(
            runID: runID,
            step: .roleAnalysis(role),
            status: .completed,
            fraction: 1,
            detail: "\(role.stemModeDisplayTitle)の役割別解析完了"
        ))

        let standardRoutePlan = processor.makeCorrectionRoutePlan(
            analysis: originalAnalysis,
            routeNoiseMeasurements: rawEvaluation.noiseMeasurements,
            logger: nil
        )
        let executionPlan = try makeExecutionPlan(
            role: role,
            settings: settings,
            standardRoutePlan: standardRoutePlan
        )
        try validate(plan: executionPlan, userSettings: settings)
        logExecutionPlan(
            role: role,
            plan: executionPlan,
            standardRoutePlan: standardRoutePlan,
            logHandler: logHandler
        )
        let routePlan = makeNativeRoutePlan(from: executionPlan)
        let context = CorrectionRunContext(
            correctionSettings: executionPlan.effectiveSettings,
            resolvedAnalysisMode: rawEvaluation.request.analysisMode.resolvedAudioAnalysisMode,
            diagnosticOutputDirectory: nil,
            logger: logger,
            benchmarkRecorder: nil,
            noiseMeasurementCache: NoiseMeasurementRunCache()
        )

        var currentSignal = rawSignal
        let rawProtectionProfile = roleAnalysis.protectionProfile
        var currentProtectionProfile = rawProtectionProfile
        var guardRecords: [StemCorrectionStageGuardRecord] = []

        for stage in StemCorrectionStage.allCases {
            try Task.checkCancellation()
            let displayStep = StemModeProcessStep.roleCorrection(role, stage: stage)
            progressHandler(.init(
                runID: runID,
                step: displayStep,
                status: .running,
                fraction: 0,
                detail: "\(role.stemModeDisplayTitle)を処理中"
            ))
            guard let stagePlan = executionPlan.decision(for: stage) else {
                throw StemCorrectionError.invalidPlanCoverage(role: role)
            }
            guard stagePlan.action != .skip else {
                guardRecords.append(StemCorrectionStageGuardRecord(
                    stage: stage,
                    action: .skip,
                    outcome: .notEvaluatedForSkippedStage,
                    reason: stagePlan.reason
                ))
                logGuardOutcome(
                    stage: stage,
                    outcome: .notEvaluatedForSkippedStage,
                    logHandler: logHandler
                )
                progressHandler(.init(runID: runID, step: displayStep, status: .skipped, fraction: 1, detail: stagePlan.reason))
                continue
            }

            let stageInput = currentSignal
            let stageInputProfile = currentProtectionProfile
            if role == .bass, stage == .lowNoiseCleanup {
                let bassResult = executeBassLowNoiseCleanup(
                    input: stageInput,
                    inputProfile: stageInputProfile,
                    rawProfile: rawProtectionProfile,
                    routeNoiseMeasurements: rawEvaluation.noiseMeasurements,
                    settings: context.correctionSettings,
                    logger: context.logger
                )
                currentSignal = bassResult.signal
                currentProtectionProfile = bassResult.profile
                guardRecords.append(StemCorrectionStageGuardRecord(
                    stage: stage,
                    action: stagePlan.action,
                    outcome: bassResult.outcome,
                    reason: bassResult.reason,
                    protectedComponents: bassResult.components,
                    protectionEvidence: bassResult.summaries.map {
                        StemCorrectionProtectionEvidence(label: $0.name, summary: $0.summary)
                    }
                ))
                logGuardOutcome(
                    stage: stage,
                    outcome: bassResult.outcome,
                    components: bassResult.components,
                    logHandler: logHandler
                )
                for item in bassResult.summaries {
                    logHandler("Stem役割保護詳細: \(stage.stemModeDisplayTitle)/\(item.name)")
                    logProtectionSummary(item.summary, logHandler: logHandler)
                }
                progressHandler(.init(runID: runID, step: displayStep, status: .completed, fraction: 1, detail: bassResult.reason))
                continue
            }
            let stageOutput: AudioSignal
            do {
                stageOutput = try execute(
                    stage: stage,
                    input: stageInput,
                    originalReference: rawSignal,
                    originalAnalysis: originalAnalysis,
                    routeNoiseMeasurements: rawEvaluation.noiseMeasurements,
                    routePlan: routePlan,
                    context: context
                )
            } catch {
                if error is CancellationError { throw error }
                guardRecords.append(StemCorrectionStageGuardRecord(
                    stage: stage,
                    action: stagePlan.action,
                    outcome: .restoredStageInputAfterDSPFailure,
                    reason: "当該DSPだけをスキップし、処理直前Stemを維持: \(error.localizedDescription)"
                ))
                logGuardOutcome(
                    stage: stage,
                    outcome: .restoredStageInputAfterDSPFailure,
                    logHandler: logHandler
                )
                progressHandler(.init(runID: runID, step: displayStep, status: .completed, fraction: 1, detail: "DSP失敗のため処理直前Stemを維持"))
                continue
            }
            guard structurallyMatches(stageOutput, reference: currentSignal) else {
                guardRecords.append(StemCorrectionStageGuardRecord(
                    stage: stage,
                    action: stagePlan.action,
                    outcome: .restoredStageInputAfterDSPFailure,
                    reason: "当該DSPの出力構造が不正なため、そのDSPだけをスキップして処理直前Stemを維持"
                ))
                logGuardOutcome(
                    stage: stage,
                    outcome: .restoredStageInputAfterDSPFailure,
                    logHandler: logHandler
                )
                progressHandler(.init(runID: runID, step: displayStep, status: .completed, fraction: 1, detail: "出力構造不正のため処理直前Stemを維持"))
                continue
            }
            if signalsExactlyEqual(stageOutput, stageInput) {
                guardRecords.append(StemCorrectionStageGuardRecord(
                    stage: stage,
                    action: stagePlan.action,
                    outcome: .unchanged,
                    reason: "既存DSPと内部guardが処理前信号を維持"
                ))
                logGuardOutcome(
                    stage: stage,
                    outcome: .unchanged,
                    logHandler: logHandler
                )
                progressHandler(.init(runID: runID, step: displayStep, status: .completed, fraction: 1, detail: "工程内判断により音声を維持"))
                continue
            }

            do {
                let protected = try roleProtector.protect(
                    role: role,
                    stageInput: stageInput,
                    proposedOutput: stageOutput,
                    rawProfile: rawProtectionProfile,
                    inputProfile: stageInputProfile
                )
                currentSignal = protected.signal
                currentProtectionProfile = protected.profile
                let evidence = makeGuardEvidence(
                    stage: stage,
                    action: stagePlan.action,
                    decision: protected.decision,
                    summary: protected.summary
                )
                guardRecords.append(evidence)
                logGuardOutcome(
                    stage: stage,
                    outcome: evidence.outcome,
                    components: protectedComponents(in: protected.decision),
                    summary: protected.summary,
                    logHandler: logHandler
                )
                progressHandler(.init(runID: runID, step: displayStep, status: .completed, fraction: 1, detail: evidence.reason))
            } catch {
                if error is CancellationError { throw error }
                currentSignal = stageInput
                currentProtectionProfile = stageInputProfile
                guardRecords.append(StemCorrectionStageGuardRecord(
                    stage: stage,
                    action: stagePlan.action,
                    outcome: .restoredStageInputAfterGuardFailure,
                    reason: "役割別guardを安全に完了できないため、音を変更せず処理直前Stemを維持: \(error.localizedDescription)"
                ))
                logGuardOutcome(
                    stage: stage,
                    outcome: .restoredStageInputAfterGuardFailure,
                    logHandler: logHandler
                )
                progressHandler(.init(runID: runID, step: displayStep, status: .completed, fraction: 1, detail: "guard不確実のため処理直前Stemを維持"))
            }
        }

        let correctedEvaluation: StemAudioEvaluationSnapshot
        if signalsExactlyEqual(currentSignal, rawSignal) {
            correctedEvaluation = relabel(
                rawEvaluation,
                purpose: .correctedStem(role: role)
            )
        } else {
            correctedEvaluation = try await evaluator.evaluate(
                signal: currentSignal,
                request: StemAudioEvaluationRequest(
                    purpose: .correctedStem(role: role),
                    includeAudioAnalyzerSnapshot: true,
                    includeMasteringAnalysisSnapshot: false,
                    analysisMode: rawEvaluation.request.analysisMode
                )
            )
            guard correctedEvaluation.purpose == .correctedStem(role: role) else {
                throw StemCorrectionError.invalidEvaluationPurpose(role: role)
            }
        }
        return StemCorrectionSignalResult(
            role: role,
            roleAnalysisSnapshot: roleAnalysis.snapshot,
            executionPlan: executionPlan,
            stageGuards: guardRecords,
            correctedSignal: currentSignal,
            correctedEvaluation: correctedEvaluation
        )
    }

    private func makeExecutionPlan(
        role: StemRole,
        settings: CorrectionSettings,
        standardRoutePlan: CorrectionRoutePlan
    ) throws -> StemCorrectionExecutionPlan {
        let roleProtection = roleProtectionDescription(role)
        var stages = Self.routedStages.map { stage, routeStep in
            let decision = standardRoutePlan.decision(for: routeStep)
            return StemCorrectionStagePlan(
                stage: stage,
                action: StemCorrectionStageAction(decision.action),
                reason: "共通の補正判定: \(decision.reason)。\(roleProtection)"
            )
        }
        stages.append(StemCorrectionStagePlan(
            stage: .highFloorPreservation,
            action: .run,
            reason: "既存の補正後高域保持を使用し、\(roleProtection)"
        ))
        stages.append(StemCorrectionStagePlan(
            stage: .mudIncreaseControl,
            action: .run,
            reason: "既存の処理前後mud増加guardを使用し、\(roleProtection)"
        ))
        return StemCorrectionExecutionPlan(
            role: role,
            effectiveSettings: settings,
            stages: StemCorrectionStage.allCases.compactMap { stage in
                stages.first { $0.stage == stage }
            }
        )
    }

    private func logExecutionPlan(
        role: StemRole,
        plan: StemCorrectionExecutionPlan,
        standardRoutePlan: CorrectionRoutePlan,
        logHandler: @escaping @Sendable (String) -> Void
    ) {
        logHandler("役割別保護: \(roleProtectionDescription(role))")
        for (stage, routeStep) in Self.routedStages {
            guard let stagePlan = plan.decision(for: stage) else { continue }
            let routeDecision = standardRoutePlan.decision(for: routeStep)
            logHandler(
                "ルート/補正: \(stage.stemModeDisplayTitle) = "
                    + "\(ProcessingRouteAction(stagePlan.action).logTitle) - \(routeDecision.reason)"
            )
        }
        if let highFloor = plan.decision(for: .highFloorPreservation) {
            logHandler(
                "ルート/補正: \(StemCorrectionStage.highFloorPreservation.stemModeDisplayTitle) = "
                    + "\(ProcessingRouteAction(highFloor.action).logTitle) - 既存の補正後高域保持を使用"
            )
        }
        if let mudGuard = plan.decision(for: .mudIncreaseControl) {
            logHandler(
                "ルート/補正: \(StemCorrectionStage.mudIncreaseControl.stemModeDisplayTitle) = "
                    + "\(ProcessingRouteAction(mudGuard.action).logTitle) - 既存の処理前後mud増加guardを使用"
            )
        }
        logHandler(
            "ルート/補正: ピーク保護 = スキップ - "
                + "Stem個別では使わず再ミックス後の既存マスタリングで制御"
        )
    }

    private func validate(
        plan: StemCorrectionExecutionPlan,
        userSettings: CorrectionSettings
    ) throws {
        let stages = plan.stages.map(\.stage)
        guard stages.count == StemCorrectionStage.allCases.count,
              Set(stages) == Set(StemCorrectionStage.allCases) else {
            throw StemCorrectionError.invalidPlanCoverage(role: plan.role)
        }
        for stage in StemCorrectionStage.allCases {
            let matches = plan.stages.filter { $0.stage == stage }
            guard matches.count == 1 else {
                throw StemCorrectionError.duplicatePlanStage(role: plan.role, stage: stage)
            }
            guard !matches[0].reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw StemCorrectionError.emptyPlanReason(role: plan.role, stage: stage)
            }
        }
        guard plan.effectiveSettings == userSettings else {
            throw StemCorrectionError.effectiveSettingsExceedUserMaximum(
                role: plan.role,
                field: "run-level settings"
            )
        }
    }

    private func makeNativeRoutePlan(
        from plan: StemCorrectionExecutionPlan
    ) -> CorrectionRoutePlan {
        func decision(
            _ stage: StemCorrectionStage,
            _ fallback: String
        ) -> ProcessingRouteDecision {
            let plan = plan.decision(for: stage)
            return ProcessingRouteDecision(
                action: ProcessingRouteAction(plan?.action ?? .skip),
                reason: plan?.reason ?? fallback,
                riskLevel: .medium
            )
        }
        return CorrectionRoutePlan(decisions: [
            .lowNoiseCleanup: decision(.lowNoiseCleanup, "補正計画なし"),
            .denoise: decision(.denoise, "補正計画なし"),
            .sibilanceShimmerGuard: decision(.sibilanceShimmerProtection, "補正計画なし"),
            .harmonicRepair: decision(.harmonicRepair, "補正計画なし"),
            .repairShimmerGuard: decision(.repairShimmerProtection, "補正計画なし"),
            .lowMidResidueGuard: decision(.lowMidResidueControl, "補正計画なし"),
            .shimmerPeakLimit: decision(.shimmerPeakControl, "補正計画なし"),
            .peakSafety: ProcessingRouteDecision(
                action: .skip,
                reason: "Stem個別limiterは使わず純粋加算後の既存masteringで制御",
                riskLevel: .low
            ),
        ])
    }

    private func execute(
        stage: StemCorrectionStage,
        input: AudioSignal,
        originalReference: AudioSignal,
        originalAnalysis: AnalysisData,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        routePlan: CorrectionRoutePlan,
        context: CorrectionRunContext
    ) throws -> AudioSignal {
        switch stage {
        case .lowNoiseCleanup:
            processor.applyLowNoiseCleanup(
                to: input,
                routePlan: routePlan,
                routeNoiseMeasurements: routeNoiseMeasurements,
                context: context
            )
        case .denoise:
            processor.applyDenoise(to: input, context: context)
        case .sibilanceShimmerProtection:
            processor.applySibilanceShimmerGuard(
                to: input,
                reference: originalReference,
                routeNoiseMeasurements: routeNoiseMeasurements,
                routePlan: routePlan,
                context: context
            )
        case .harmonicRepair:
            {
                let preparation = processor.prepareHarmonicRepair(
                    for: input,
                    originalAnalysis: originalAnalysis,
                    context: context
                )
                return processor.applyHarmonicRepair(
                    to: input,
                    postDenoiseAnalysis: preparation.postDenoiseAnalysis,
                    repairPrediction: preparation.repairPrediction,
                    context: context
                )
            }()
        case .repairShimmerProtection:
            processor.applyRepairShimmerGuard(
                to: input,
                routePlan: routePlan,
                routeNoiseMeasurements: routeNoiseMeasurements,
                context: context
            )
        case .lowMidResidueControl:
            processor.applyLowMidResidueGuard(
                to: input,
                routePlan: routePlan,
                context: context
            )
        case .shimmerPeakControl:
            processor.applyShimmerPeakLimit(
                to: input,
                reference: originalReference,
                routePlan: routePlan,
                routeNoiseMeasurements: routeNoiseMeasurements,
                context: context
            )
        case .highFloorPreservation:
            processor.applyCorrectionHighPreserve(
                to: input,
                reference: originalReference,
                routeNoiseMeasurements: routeNoiseMeasurements,
                context: context
            )
        case .mudIncreaseControl:
            processor.applyCorrectionMudGuard(
                to: input,
                routeNoiseMeasurements: routeNoiseMeasurements,
                context: context
            )
        }
    }

    private func executeBassLowNoiseCleanup(
        input: AudioSignal,
        inputProfile: StemRoleProtectionProfile,
        rawProfile: StemRoleProtectionProfile,
        routeNoiseMeasurements: NoiseMeasurementSnapshot,
        settings: CorrectionSettings,
        logger: AudioProcessingLogger?
    ) -> (
        signal: AudioSignal,
        profile: StemRoleProtectionProfile,
        outcome: StemCorrectionStageGuardOutcome,
        components: Set<StemRoleProtectedComponent>,
        summaries: [(name: String, summary: StemRoleProtectionGuardSummary)],
        reason: String
    ) {
        var signal = input
        var profile = inputProfile
        var decisions: [(name: String, decision: StemRoleProtectionGuardDecision)] = []
        var summaries: [(name: String, summary: StemRoleProtectionGuardSummary)] = []
        logger?.log("低域ノイズを先に整えます")

        func protectedStep(
            name: String,
            proposed: AudioSignal
        ) -> (
            signal: AudioSignal,
            profile: StemRoleProtectionProfile,
            decision: StemRoleProtectionGuardDecision,
            summary: StemRoleProtectionGuardSummary?
        ) {
            guard !signalsExactlyEqual(signal, proposed) else {
                return (signal, profile, .acceptedDSPOutput, nil)
            }
            do {
                let result = try roleProtector.protect(
                    role: .bass,
                    stageInput: signal,
                    proposedOutput: proposed,
                    rawProfile: rawProfile,
                    inputProfile: profile
                )
                return (result.signal, result.profile, result.decision, result.summary)
            } catch {
                return (
                    signal,
                    profile,
                    .restoredStageInput(components: Set(
                        StemRoleProtectedComponent.allCases.filter { $0.role == .bass }
                    )),
                    nil
                )
            }
        }

        let humOutput = HumRemover(settings: settings).process(signal: signal)
        let hum = protectedStep(name: "ハム除去", proposed: humOutput)
        signal = hum.signal
        profile = hum.profile
        decisions.append(("ハム除去", hum.decision))
        if let summary = hum.summary {
            summaries.append(("ハム除去", summary))
        }

        let rumbleOutput = RumbleReducer(settings: settings).process(
            signal: signal,
            reference: input,
            referenceMeasurements: routeNoiseMeasurements,
            logger: logger
        )
        let rumble = protectedStep(name: "ランブル除去", proposed: rumbleOutput)
        signal = rumble.signal
        profile = rumble.profile
        decisions.append(("ランブル除去", rumble.decision))
        if let summary = rumble.summary {
            summaries.append(("ランブル除去", summary))
        }

        let descriptions = decisions.map { name, decision in
            switch decision {
            case .acceptedDSPOutput:
                "\(name)=通過"
            case let .weakenedDSPDelta(components):
                "\(name)=\(componentList(components))保護のため弱化"
            case let .restoredStageInput(components):
                "\(name)=\(componentList(components))保護のためスキップ"
            }
        }
        let outcome: StemCorrectionStageGuardOutcome
        if decisions.contains(where: {
            if case .restoredStageInput = $0.decision { true } else { false }
        }) {
            outcome = .restoredStageInputByStemProtection
        } else if decisions.contains(where: {
            if case .weakenedDSPDelta = $0.decision { true } else { false }
        }) {
            outcome = .weakenedByStemProtection
        } else if signalsExactlyEqual(signal, input) {
            outcome = .unchanged
        } else {
            outcome = .completed
        }
        let components = decisions.reduce(into: Set<StemRoleProtectedComponent>()) { result, item in
            result.formUnion(protectedComponents(in: item.decision))
        }
        return (
            signal,
            profile,
            outcome,
            components,
            summaries,
            "bass低域処理を個別guard: \(descriptions.joined(separator: "、"))"
        )
    }

    private func relabel(
        _ evaluation: StemAudioEvaluationSnapshot,
        purpose: StemAudioEvaluationPurpose
    ) -> StemAudioEvaluationSnapshot {
        StemAudioEvaluationSnapshot(
            request: StemAudioEvaluationRequest(
                purpose: purpose,
                includeAudioAnalyzerSnapshot: evaluation.request.includeAudioAnalyzerSnapshot,
                includeMasteringAnalysisSnapshot: evaluation.request.includeMasteringAnalysisSnapshot,
                analysisMode: evaluation.request.analysisMode
            ),
            completedMeasurements: evaluation.completedMeasurements,
            audioMetrics: evaluation.audioMetrics,
            noiseMeasurements: evaluation.noiseMeasurements,
            audioAnalysis: evaluation.audioAnalysis,
            masteringAnalysis: evaluation.masteringAnalysis
        )
    }

    private func structurallyMatches(
        _ candidate: AudioSignal,
        reference: AudioSignal
    ) -> Bool {
        guard candidate.sampleRate == reference.sampleRate,
              candidate.channels.count == reference.channels.count,
              candidate.frameCount == reference.frameCount,
              !candidate.channels.isEmpty else {
            return false
        }
        return candidate.channels.enumerated().allSatisfy { channelIndex, channel in
            channel.count == reference.channels[channelIndex].count
                && channel.allSatisfy(\.isFinite)
        }
    }

    private func signalsExactlyEqual(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Bool {
        lhs.sampleRate == rhs.sampleRate && lhs.channels == rhs.channels
    }

    private func roleProtectionDescription(_ role: StemRole) -> String {
        switch role {
        case .vocals:
            "息・子音・サ行・フォルマント・倍音・声の芯"
        case .drums:
            "アタック・トランジェント・シンバルの余韻"
        case .bass:
            "基音・倍音・50/60 Hz付近の音程成分・低域位相"
        case .other:
            "残響・アンビエンス・空間・ステレオ感"
        }
    }

    private func logGuardOutcome(
        stage: StemCorrectionStage,
        outcome: StemCorrectionStageGuardOutcome,
        components: Set<StemRoleProtectedComponent> = [],
        summary: StemRoleProtectionGuardSummary? = nil,
        logHandler: @escaping @Sendable (String) -> Void
    ) {
        logHandler("Stem役割保護: \(stage.stemModeDisplayTitle) = \(outcome.stemModeDisplayTitle)")
        if let summary {
            logProtectionSummary(summary, logHandler: logHandler)
        }
        if !components.isEmpty {
            logHandler("保護対象: \(componentList(components))")
        }
    }

    private func logProtectionSummary(
        _ summary: StemRoleProtectionGuardSummary,
        logHandler: @escaping @Sendable (String) -> Void
    ) {
        logHandler("対象区間: \(formatPercentage(summary.affectedTimeRatio))")
        logHandler(
            "DSP差分保持: 平均\(formatPercentage(summary.averageRetainedDSPDeltaRatio))"
                + " / 最小\(formatPercentage(summary.minimumRetainedDSPDeltaRatio))"
        )
        if let restorationReason = summary.restorationReason {
            logHandler("理由: \(restorationReason.logDescription)")
        }
    }

    private func formatPercentage(_ ratio: Double) -> String {
        String(format: "%.1f%%", min(max(ratio, 0), 1) * 100)
    }

    private func protectedComponents(
        in decision: StemRoleProtectionGuardDecision
    ) -> Set<StemRoleProtectedComponent> {
        return switch decision {
        case .acceptedDSPOutput:
            []
        case let .weakenedDSPDelta(components), let .restoredStageInput(components):
            components
        }
    }

    private func makeGuardEvidence(
        stage: StemCorrectionStage,
        action: StemCorrectionStageAction,
        decision: StemRoleProtectionGuardDecision,
        summary: StemRoleProtectionGuardSummary?
    ) -> StemCorrectionStageGuardRecord {
        let components = protectedComponents(in: decision)
        let protectionEvidence = summary.map {
            [StemCorrectionProtectionEvidence(label: "役割別guard", summary: $0)]
        } ?? []
        return switch decision {
        case .acceptedDSPOutput:
            StemCorrectionStageGuardRecord(
                stage: stage,
                action: action,
                outcome: .completed,
                reason: "既存DSP内部guardとStem役割別guardを通過した1本を次工程へ継続",
                protectedComponents: components,
                protectionEvidence: protectionEvidence
            )
        case .weakenedDSPDelta:
            StemCorrectionStageGuardRecord(
                stage: stage,
                action: action,
                outcome: .weakenedByStemProtection,
                reason: "今回のStem自身との相対比較で\(componentList(components))を保護するため、問題区間のDSP差分だけを弱化",
                protectedComponents: components,
                protectionEvidence: protectionEvidence
            )
        case .restoredStageInput:
            StemCorrectionStageGuardRecord(
                stage: stage,
                action: action,
                outcome: .restoredStageInputByStemProtection,
                reason: "今回のStem自身との相対比較で\(componentList(components))を保護するため、そのDSPだけをスキップして処理直前Stemを維持",
                protectedComponents: components,
                protectionEvidence: protectionEvidence
            )
        }
    }

    private func componentList(_ components: Set<StemRoleProtectedComponent>) -> String {
        components.map { component in
            switch component {
            case .vocalsBreath: "息"
            case .vocalsConsonants: "子音"
            case .vocalsSibilance: "サ行"
            case .vocalsFormant: "フォルマント"
            case .vocalsHarmonics: "倍音"
            case .vocalsCore: "声の芯"
            case .drumsAttack: "アタック"
            case .drumsTransient: "トランジェント"
            case .drumsCymbalDecay: "シンバルの余韻"
            case .bassFundamental: "基音"
            case .bassHarmonics: "倍音"
            case .bassMainsRegionPitchContent: "50/60 Hz付近の音程成分"
            case .bassLowPhase: "低域位相"
            case .otherReverb: "残響"
            case .otherAmbience: "アンビエンス"
            case .otherSpace: "空間"
            case .otherStereo: "ステレオ感"
            }
        }
        .sorted()
        .joined(separator: "、")
    }
}

private extension StemCorrectionStageAction {
    init(_ action: ProcessingRouteAction) {
        switch action {
        case .run: self = .run
        case .light: self = .light
        case .skip: self = .skip
        }
    }
}

private extension ProcessingRouteAction {
    init(_ action: StemCorrectionStageAction) {
        switch action {
        case .run: self = .run
        case .light: self = .light
        case .skip: self = .skip
        }
    }
}
