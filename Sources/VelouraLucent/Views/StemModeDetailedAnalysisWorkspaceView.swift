import SwiftUI

/// 通常モードの詳細解析と同じ3段階比較を中核にし、Stem固有解析だけを追加します。
@MainActor
struct StemModeDetailedAnalysisWorkspaceView: View {
    @Bindable var model: StemModeWorkspaceModel
    @State private var showStemSpecificAnalysis = false
    @State private var showRemixSpecificAnalysis = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailedAnalysisComparisonView(presentation: commonPresentation)

            if model.inputMetrics != nil {
                stemAnalysisDisclosureSection(
                    title: "Stem固有解析",
                    help: "4Stemそれぞれのrawと補正後の測定値、役割別解析、各DSPの最終適用結果、役割別guard、rawへ戻した理由を確認します。route決定の詳しい理由や処理経過は詳細ログで確認します。数値だけで品質を自動判定する画面ではありません。",
                    isExpanded: $showStemSpecificAnalysis
                ) {
                    stemSpecificAnalysisContent
                }

                stemAnalysisDisclosureSection(
                    title: "再ミックス固有解析",
                    help: "raw 4Stemと補正後4Stemの純粋加算を比べ、再合成、残差、位相、相関、帯域、ノイズ、分離アーティファクトの測定結果を確認します。数値だけで完成音を自動選択しません。",
                    isExpanded: $showRemixSpecificAnalysis
                ) {
                    remixSpecificAnalysisContent
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var commonPresentation: DetailedAnalysisPresentation {
        var analyzingTargets: Set<DisplayAnalysisTarget> = []
        var failedTargets: Set<DisplayAnalysisTarget> = []

        if model.isAnalyzingInput {
            analyzingTargets.insert(.input)
        }
        if model.isAnalyzingDisplayAudio {
            if model.correctedRemixPreviewArtifact != nil {
                analyzingTargets.insert(.corrected)
            }
            if model.finalPreviewArtifact != nil {
                analyzingTargets.insert(.mastered)
            }
        }
        if model.inputAnalysisError != nil {
            failedTargets.insert(.input)
        }
        if model.displayAnalysisError != nil {
            if model.correctedRemixPreviewArtifact != nil {
                failedTargets.insert(.corrected)
            }
            if model.finalPreviewArtifact != nil {
                failedTargets.insert(.mastered)
            }
        }

        let correctionSettings = model.remixAnalysisPresentation?.correctionSettings
            ?? model.correctionSettings
        let noiseReport = model.qualityReports?.noiseCheck
            ?? StemAudioReportAdapter.makeNoiseCheckReport(
                input: model.inputNoiseMeasurements,
                remixed: model.correctedRemixNoiseMeasurements,
                mastered: model.finalNoiseMeasurements,
                correctionSettings: correctionSettings,
                masteringSettings: model.masteringSettings
            )

        return DetailedAnalysisPresentation(
            inputMetrics: model.inputMetrics,
            correctedMetrics: model.correctedRemixMetrics,
            masteredMetrics: model.finalMetrics,
            noiseReport: noiseReport,
            isAnalyzing: model.isAnalyzingInput || model.isAnalyzingDisplayAudio,
            statusText: analysisStatusText,
            failedText: analysisFailureText,
            analyzingTargets: analyzingTargets,
            failedTargets: failedTargets,
            emptyTitle: "入力2mixは未解析です",
            emptyDescription: "音声を選ぶと、入力、補正後再ミックス、Stem Mode最終版の詳細解析を表示します。"
        )
    }

    private var analysisStatusText: String? {
        if model.isAnalyzingInput {
            return "入力2mixを解析しています。"
        }
        if model.isAnalyzingDisplayAudio {
            return "補正後再ミックスまたはStem Mode最終版を解析しています。"
        }
        return nil
    }

    private var analysisFailureText: String? {
        let failures = [model.inputAnalysisError, model.displayAnalysisError]
            .compactMap { $0 }
        return failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    @ViewBuilder
    private var stemSpecificAnalysisContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.stemEvaluations.isEmpty {
                Text("4Stemの解析完了後に表示します。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.stemEvaluations.enumerated()), id: \.offset) { _, evaluation in
                    DisclosureGroup(evaluation.role.stemModeDisplayTitle) {
                        VStack(alignment: .leading, spacing: 10) {
                            stemMetricGrid(evaluation)
                            if let roleAnalysis = evaluation.roleAnalysisSnapshot {
                                roleAnalysisGrid(roleAnalysis)
                            }
                            if evaluation.usedRawFallback {
                                Label(
                                    evaluation.fallbackReason ?? "このStemはrawを使用しました。",
                                    systemImage: "arrow.uturn.backward.circle"
                                )
                                .foregroundStyle(.orange)
                            }
                            if !evaluation.stageGuards.isEmpty {
                                Text("DSP最終適用結果")
                                    .font(.callout.bold())
                                ForEach(Array(evaluation.stageGuards.enumerated()), id: \.offset) { _, record in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(record.stage.stemModeDisplayTitle)
                                            Spacer()
                                            Text(record.action.stemModeDisplayTitle)
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(record.outcome.stemModeDisplayTitle)
                                            .font(.callout.weight(.semibold))
                                        Text(record.reason)
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                        if !record.protectedComponents.isEmpty {
                                            Text(
                                                "保護対象: "
                                                    + record.protectedComponents
                                                        .sorted { $0.rawValue < $1.rawValue }
                                                        .map(\.stemModeDisplayTitle)
                                                        .joined(separator: "、")
                                            )
                                            .font(.callout)
                                            .foregroundStyle(.secondary)
                                        }
                                        ForEach(Array(record.protectionEvidence.enumerated()), id: \.offset) { _, evidence in
                                            protectionEvidenceRow(evidence)
                                        }
                                    }
                                    .font(.callout)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var remixSpecificAnalysisContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let presentation = model.remixAnalysisPresentation {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Text("構造検証")
                            .foregroundStyle(.secondary)
                        Text(presentation.validation.canContinue ? "継続可能" : "継続不能")
                    }
                    GridRow {
                        Text("解析確認事項")
                            .foregroundStyle(.secondary)
                        Text(presentation.validation.analysisIssues.count, format: .number)
                    }
                }
                remixEvaluationComparison(presentation)
                validationMeasurements(presentation.validation.measurements)
                validationIssues(presentation.validation.analysisIssues)
                Text("位相、相関、残差、帯域差、分離アーティファクトは解析・表示・レポートの材料であり、自動候補選択には使用しません。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("補正後4Stemの純粋加算と解析が完了すると表示します。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stemAnalysisDisclosureSection<Content: View>(
        title: String,
        help: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                DisclosureToggleButton(
                    title: title,
                    isExpanded: isExpanded.wrappedValue,
                    accessibilityHint: "解析項目を開閉します"
                ) {
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isExpanded.wrappedValue.toggle()
                    }
                }
                HStack(spacing: 6) {
                    Text(title)
                        .font(.headline)
                    TermHelpButton(
                        title: title,
                        reading: title,
                        description: help
                    )
                }
            }

            if isExpanded.wrappedValue {
                content()
            }
        }
        .analysisCard()
    }

    private func stemMetricGrid(_ evaluation: StemModeStemEvaluationPresentation) -> some View {
        let raw = evaluation.rawEvaluation
        let corrected = evaluation.correctedEvaluation
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                headerCell("項目")
                headerCell("raw")
                headerCell("補正後")
            }
            GridRow {
                Text("Integrated Loudness")
                number(raw.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .blue)
                number(corrected?.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .green)
            }
            GridRow {
                Text("True Peak")
                number(raw.audioMetrics.truePeakDBFS, unit: "dBTP", color: .blue)
                number(corrected?.audioMetrics.truePeakDBFS, unit: "dBTP", color: .green)
            }
            GridRow {
                Text("Transient")
                number(Double(raw.audioAnalysis?.transientAmount ?? 0), unit: "", color: .blue)
                number(corrected?.audioAnalysis.map { Double($0.transientAmount) }, unit: "", color: .green)
            }
            GridRow {
                Text("Artifact band")
                number(Double(raw.audioAnalysis?.artifactBandRatio ?? 0), unit: "", color: .blue)
                number(corrected?.audioAnalysis.map { Double($0.artifactBandRatio) }, unit: "", color: .green)
            }
        }
    }

    private func roleAnalysisGrid(_ snapshot: StemRoleAnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("役割別解析")
                .font(.callout.bold())
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    headerCell("保護対象")
                    headerCell("中央値")
                    headerCell("変動幅")
                    headerCell("扱い")
                }
                ForEach(snapshot.features, id: \.feature) { distribution in
                    GridRow {
                        Text(distribution.feature.stemModeDisplayTitle)
                        number(
                            distribution.median,
                            unit: distribution.unit.stemModeDisplayUnit,
                            color: .primary
                        )
                        number(
                            distribution.interquartileRange,
                            unit: distribution.unit.stemModeDisplayUnit,
                            color: .secondary
                        )
                        Text(distribution.preservationRule.stemModeDisplayTitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("今回のraw Stem自身から取得した解析量です。他曲の固定基準や品質スコアには使用しません。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func protectionEvidenceRow(
        _ evidence: StemCorrectionProtectionEvidence
    ) -> some View {
        let summary = evidence.summary
        return VStack(alignment: .leading, spacing: 2) {
            Text(evidence.label)
                .font(.callout.weight(.semibold))
            Text(
                "対象区間 \(percentage(summary.affectedTimeRatio))"
                    + "・DSP差分保持 平均\(percentage(summary.averageRetainedDSPDeltaRatio))"
                    + "／最小\(percentage(summary.minimumRetainedDSPDeltaRatio))"
            )
            .font(.callout.monospacedDigit())
            .foregroundStyle(.secondary)
            if let reason = summary.restorationReason {
                Text("復帰理由: \(reason.logDescription)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func remixEvaluationComparison(
        _ presentation: StemModeRemixAnalysisPresentation
    ) -> some View {
        let raw = presentation.rawRemixEvaluation
        let corrected = presentation.correctedRemixEvaluation
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                headerCell("再ミックス解析")
                headerCell("raw")
                headerCell("補正後")
            }
            GridRow {
                Text("Integrated Loudness")
                number(raw.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .blue)
                number(corrected.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .green)
            }
            GridRow {
                Text("True Peak")
                number(raw.audioMetrics.truePeakDBFS, unit: "dBTP", color: .blue)
                number(corrected.audioMetrics.truePeakDBFS, unit: "dBTP", color: .green)
            }
            GridRow {
                Text("位相・相関")
                number(raw.audioMetrics.stereoCorrelation, unit: "", color: .blue)
                number(corrected.audioMetrics.stereoCorrelation, unit: "", color: .green)
            }
            GridRow {
                Text("ステレオ幅")
                number(raw.audioMetrics.stereoWidth, unit: "", color: .blue)
                number(corrected.audioMetrics.stereoWidth, unit: "", color: .green)
            }
            GridRow {
                Text("ダイナミクス")
                number(raw.audioMetrics.crestFactorDB, unit: "dB", color: .blue)
                number(corrected.audioMetrics.crestFactorDB, unit: "dB", color: .green)
            }
            GridRow {
                Text("分離アーティファクト")
                number(raw.audioAnalysis.map { Double($0.artifactBandRatio) }, unit: "", color: .blue)
                number(corrected.audioAnalysis.map { Double($0.artifactBandRatio) }, unit: "", color: .green)
            }
        }
    }

    @ViewBuilder
    private func validationMeasurements(
        _ measurements: [StemValidationMeasurement]
    ) -> some View {
        if !measurements.isEmpty {
            DisclosureGroup("再合成・残差・帯域・ノイズ測定") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
                    ForEach(measurements) { measurement in
                        GridRow {
                            Text(validationMeasurementTitle(measurement.id))
                            Text(formatValidationMeasurement(measurement))
                                .font(.callout.monospacedDigit())
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func validationIssues(
        _ issues: [StemValidationFailure]
    ) -> some View {
        if !issues.isEmpty {
            DisclosureGroup("解析上の確認事項") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(issue.check.stemModeDisplayTitle)・\(issue.subject)")
                                .font(.callout.weight(.semibold))
                            Text(issue.detail)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func headerCell(_ text: String) -> some View {
        Text(text)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func number(_ value: Double?, unit: String, color: Color) -> some View {
        Text(value.map { String(format: "%.2f%@", $0, unit.isEmpty ? "" : " \(unit)") } ?? "--")
            .font(.callout.monospacedDigit())
            .foregroundStyle(value == nil ? .secondary : color)
            .lineLimit(1)
    }

    private func percentage(_ ratio: Double) -> String {
        String(format: "%.1f%%", min(max(ratio, 0), 1) * 100)
    }

    private func formatValidationMeasurement(
        _ measurement: StemValidationMeasurement
    ) -> String {
        switch measurement.unit {
        case "samples":
            "\(Int(measurement.value.rounded())) samples"
        case "ratio", "linear":
            String(format: "%.4f", measurement.value)
        default:
            String(format: "%.2f %@", measurement.value, measurement.unit)
        }
    }

    private func validationMeasurementTitle(_ id: String) -> String {
        let prefixes: [(String, String)] = [
            ("corrected-remix-difference.canonical-to-raw.", "入力2mix → raw再ミックス 残差"),
            ("corrected-remix-difference.canonical-to-corrected.", "入力2mix → 補正後再ミックス 残差"),
            ("corrected-remix-difference.raw-to-corrected.", "raw → 補正後再ミックス 残差"),
            ("corrected-remix-correlation.canonical-to-raw.", "入力2mix → raw再ミックス 相関"),
            ("corrected-remix-correlation.canonical-to-corrected.", "入力2mix → 補正後再ミックス 相関"),
            ("corrected-remix-correlation.raw-to-corrected.", "raw → 補正後再ミックス 相関"),
            ("corrected-remix-band-difference.canonical-to-raw.", "入力2mix → raw再ミックス 帯域差"),
            ("corrected-remix-band-difference.canonical-to-corrected.", "入力2mix → 補正後再ミックス 帯域差"),
            ("corrected-remix-band-difference.raw-to-corrected.", "raw → 補正後再ミックス 帯域差"),
            ("corrected-remix-noise.", "再ミックス ノイズ"),
            ("corrected-remix.", "補正後再ミックス")
        ]
        for (prefix, title) in prefixes where id.hasPrefix(prefix) {
            let detail = id.dropFirst(prefix.count)
                .replacingOccurrences(of: ".", with: " / ")
                .replacingOccurrences(of: "sample-peak", with: "sample peak")
                .replacingOccurrences(of: "true-peak", with: "true peak")
                .replacingOccurrences(of: "over-range-samples", with: "上限超過sample数")
                .replacingOccurrences(of: "raw-minus-canonical", with: "raw − 入力")
                .replacingOccurrences(of: "corrected-minus-canonical", with: "補正後 − 入力")
                .replacingOccurrences(of: "corrected-minus-raw", with: "補正後 − raw")
                .replacingOccurrences(of: "canonical", with: "入力")
                .replacingOccurrences(of: "corrected", with: "補正後")
            return "\(title) / \(detail)"
        }
        return id
    }
}

private extension StemRoleAnalysisFeature {
    var stemModeDisplayTitle: String {
        switch self {
        case .vocalsVoicedHarmonicStrength: "ボーカル有声音・倍音"
        case .vocalsBreathConsonantBalance: "息・子音バランス"
        case .vocalsFormantCenter: "フォルマント中心"
        case .vocalsHarmonicContinuity: "ボーカル倍音の連続性"
        case .drumsOnsetStrength: "ドラムonset"
        case .drumsAttackCrest: "アタック"
        case .drumsCymbalDecayContinuity: "シンバルの余韻"
        case .drumsQuietGapContrast: "打音間の静音差"
        case .bassFundamentalHarmonicStrength: "ベース基音・倍音"
        case .bassFiftyHertzPitchAlignment: "50 Hz付近の音程成分"
        case .bassSixtyHertzPitchAlignment: "60 Hz付近の音程成分"
        case .bassLowBandPhaseCoherence: "低域位相"
        case .otherPolyphonicSpectralSpread: "複合音の帯域広がり"
        case .otherTransientStrength: "その他のtransient"
        case .otherAmbienceContinuity: "残響・ambience"
        case .otherStereoSpatialBalance: "空間・ステレオ感"
        }
    }
}

private extension StemRoleAnalysisUnit {
    var stemModeDisplayUnit: String {
        switch self {
        case .ratio, .normalized: ""
        case .hertz: "Hz"
        case .decibels: "dB"
        }
    }
}

private extension StemRoleFeaturePreservationRule {
    var stemModeDisplayTitle: String {
        switch self {
        case .preserveMinimum: "低下を抑える"
        case .preserveStability: "変動を保つ"
        }
    }
}

private extension StemRoleProtectedComponent {
    var stemModeDisplayTitle: String {
        switch self {
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
        case .bassMainsRegionPitchContent: "50／60 Hz付近の音程成分"
        case .bassLowPhase: "低域位相"
        case .otherReverb: "残響"
        case .otherAmbience: "アンビエンス"
        case .otherSpace: "空間"
        case .otherStereo: "ステレオ感"
        }
    }
}

private extension StemValidationCheck {
    var stemModeDisplayTitle: String {
        switch self {
        case .stemCount: "Stem数"
        case .roleCoverage: "役割"
        case .channelFrameCounts: "長さ"
        case .sampleRate: "sample rate"
        case .channelCount: "channel数"
        case .finiteSamples: "音声sample"
        case .finiteMeasurements: "測定値"
        case .audioComparison: "音声比較"
        case .bandEnergies: "帯域"
        case .noiseMeasurements: "ノイズ"
        case .residual: "残差"
        case .peak: "ピーク"
        case .correlation: "相関"
        }
    }
}
