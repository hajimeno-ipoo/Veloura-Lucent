import SwiftUI

/// 通常モードの詳細解析を中核にし、Stem固有解析と純粋加算／再ミックス比較を追加します。
@MainActor
struct StemModeDetailedAnalysisWorkspaceView: View {
    @Bindable var model: StemModeWorkspaceModel
    @State private var showStemSpecificAnalysis = false
    @State private var showRemixSpecificAnalysis = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            DetailedAnalysisComparisonView(presentation: commonPresentation)

            if model.inputMetrics != nil {
                stemAnalysisDisclosureSection(
                    title: "Stem固有解析",
                    help: AppLanguageSettings.format("%d Stemそれぞれのrawと補正後の測定値、役割別解析、各DSPの最終適用結果、役割別guard、rawへ戻した理由を確認します。route決定の詳しい理由や処理経過は詳細ログで確認します。数値だけで品質を自動判定する画面ではありません。", model.availableStemRoles.count),
                    isExpanded: $showStemSpecificAnalysis
                ) {
                    stemSpecificAnalysisContent
                }

                stemAnalysisDisclosureSection(
                    title: "再ミックス固有解析",
                    help: AppLanguageSettings.format("raw %d Stem、補正後、実行済み再ミックスを比べ、再合成、残差、位相、相関、帯域、ノイズ、分離アーティファクトの測定結果を確認します。数値だけで完成音を自動選択しません。", model.availableStemRoles.count),
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

        let noiseReport = model.qualityReports?.noiseCheck
            ?? StemAudioReportAdapter.makeNoiseCheckReport(
                input: model.inputNoiseMeasurements,
                remixed: model.correctedRemixNoiseMeasurements,
                mastered: model.finalNoiseMeasurements,
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
            availableTargets: Set(
                DisplayAnalysisTarget.allDisplayTargets.filter { target in
                    switch target {
                    case .input: model.selectedInputURL != nil
                    case .corrected: model.correctedRemixPreviewArtifact != nil
                    case .mastered: model.finalPreviewArtifact != nil
                    }
                }
            ),
            emptyTitle: "入力2mixは未解析です",
            emptyDescription: "音声を選ぶと、入力、補正後または再ミックス、ステム最終版の詳細解析を表示します。",
            correctedTitle: processedTitle
        )
    }

    private var processedTitle: String {
        model.remixedPreviewArtifact == nil
            ? "補正後"
            : "Stem再ミックス"
    }

    private var analysisStatusText: String? {
        if model.isAnalyzingInput {
            return "入力2mixを解析しています。"
        }
        if model.isAnalyzingDisplayAudio {
            return "補正後、再ミックス、またはステム最終版を解析しています。"
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
                Text(AppLanguageSettings.format("%d Stemの解析完了後に表示します。", model.availableStemRoles.count))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(model.stemEvaluations.enumerated()), id: \.offset) { _, evaluation in
                    DisclosureGroup(AppLanguageSettings.string(evaluation.role.stemModeDisplayTitle)) {
                        VStack(alignment: .leading, spacing: 10) {
                            stemMetricGrid(evaluation)
                            if let roleAnalysis = evaluation.roleAnalysisSnapshot {
                                roleAnalysisGrid(roleAnalysis)
                            }
                            if evaluation.usedRawFallback {
                                Label(StemDiagnosticLocalization.reason(evaluation.fallbackReason ?? "このStemはrawを使用しました。"), systemImage: "arrow.uturn.backward.circle")
                                .foregroundStyle(.orange)
                            }
                            if !evaluation.stageGuards.isEmpty {
                                AppLocalizedText("DSP最終適用結果")
                                    .font(.title3.bold())
                                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
                                    GridRow {
                                        headerCell("処理段")
                                        headerCell("実行内容")
                                            .analysisTableTextColumn(minWidth: 160)
                                    }
                                    Divider().gridCellColumns(2)
                                    ForEach(Array(evaluation.stageGuards.enumerated()), id: \.offset) { index, record in
                                        GridRow {
                                            AppLocalizedText(record.stage.stemModeDisplayTitle)
                                                .analysisTableLabelCell()
                                            AppLocalizedText(record.action.stemModeDisplayTitle)
                                                .font(.body)
                                                .foregroundStyle(.secondary)
                                                .analysisTableTextColumn(minWidth: 160)
                                        }
                                        GridRow {
                                            VStack(alignment: .leading, spacing: 4) {
                                                AppLocalizedText(record.outcome.stemModeDisplayTitle)
                                                    .font(.title3.weight(.semibold))
                                                Text(StemDiagnosticLocalization.reason(record.reason))
                                                    .font(.body)
                                                    .foregroundStyle(.secondary)
                                                if !record.protectedComponents.isEmpty {
                                                    Text(AppLanguageSettings.format(
                                                        "保護対象: %@",
                                                        record.protectedComponents
                                                            .sorted { $0.rawValue < $1.rawValue }
                                                            .map { AppLanguageSettings.string($0.stemModeDisplayTitle) }
                                                            .joined(separator: AppLanguageSettings.string("、"))
                                                    ))
                                                    .font(.body)
                                                    .foregroundStyle(.secondary)
                                                }
                                                ForEach(Array(record.protectionEvidence.enumerated()), id: \.offset) { _, evidence in
                                                    protectionEvidenceRow(evidence)
                                                }
                                            }
                                            .padding(.leading, 8)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .gridCellColumns(2)
                                        }
                                        if index < evaluation.stageGuards.count - 1 {
                                            Divider().gridCellColumns(2)
                                        }
                                    }
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
                        AppLocalizedText("構造検証")
                            .analysisTableLabelCell()
                            .foregroundStyle(.secondary)
                        AppLocalizedText(presentation.validation.canContinue ? "継続可能" : "継続不能")
                            .font(.title3.weight(.semibold))
                            .analysisTableTextColumn()
                    }
                    Divider().gridCellColumns(2)
                    GridRow {
                        AppLocalizedText("解析確認事項")
                            .analysisTableLabelCell()
                            .foregroundStyle(.secondary)
                        Text(presentation.validation.analysisIssues.count, format: .number)
                            .font(.callout.monospacedDigit())
                            .analysisTableTextColumn()
                    }
                }
                remixEvaluationComparison(presentation)
            } else {
                AppLocalizedText("補正後と解析が完了すると表示します。")
                    .foregroundStyle(.secondary)
            }
            validationIssues(model.remixAnalysisPresentation?.validation.analysisIssues)
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
                    accessibilityHint: AppLanguageSettings.string("解析項目を開閉します")
                ) {
                    LiquidGlassMotion.perform(
                        reduceMotion: reduceMotion,
                        animation: LiquidGlassMotion.panel
                    ) {
                        isExpanded.wrappedValue.toggle()
                    }
                }
                HStack(spacing: 6) {
                    AppLocalizedText(title)
                        .font(.title3.bold())
                    TermHelpButton(
                        title: title,
                        reading: title,
                        description: help
                    )
                }
            }

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity)
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
                    .analysisTableNumericColumn()
                headerCell("補正後")
                    .analysisTableNumericColumn()
            }
            Divider().gridCellColumns(3)
            GridRow {
                AppLocalizedText("Integrated Loudness")
                    .analysisTableLabelCell()
                number(raw.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .blue)
                number(corrected?.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .green)
            }
            GridRow {
                AppLocalizedText("True Peak")
                    .analysisTableLabelCell()
                number(raw.audioMetrics.truePeakDBFS, unit: "dBTP", color: .blue)
                number(corrected?.audioMetrics.truePeakDBFS, unit: "dBTP", color: .green)
            }
            GridRow {
                AppLocalizedText("Transient")
                    .analysisTableLabelCell()
                number(Double(raw.audioAnalysis?.transientAmount ?? 0), unit: "", color: .blue)
                number(corrected?.audioAnalysis.map { Double($0.transientAmount) }, unit: "", color: .green)
            }
            GridRow {
                AppLocalizedText("Artifact band")
                    .analysisTableLabelCell()
                number(Double(raw.audioAnalysis?.artifactBandRatio ?? 0), unit: "", color: .blue)
                number(corrected?.audioAnalysis.map { Double($0.artifactBandRatio) }, unit: "", color: .green)
            }
        }
    }

    private func roleAnalysisGrid(_ snapshot: StemRoleAnalysisSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AppLocalizedText("役割別解析")
                .font(.title3.bold())
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    headerCell("保護対象")
                    headerCell("中央値")
                        .analysisTableNumericColumn()
                    headerCell("変動幅")
                        .analysisTableNumericColumn()
                    headerCell("扱い")
                }
                Divider().gridCellColumns(4)
                ForEach(snapshot.features, id: \.feature) { distribution in
                    GridRow {
                        AppLocalizedText(distribution.feature.stemModeDisplayTitle)
                            .analysisTableLabelCell()
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
                        AppLocalizedText(distribution.preservationRule.stemModeDisplayTitle)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            AppLocalizedText("今回のraw Stem自身から取得した解析量です。他曲の固定基準や品質スコアには使用しません。")
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private func protectionEvidenceRow(
        _ evidence: StemCorrectionProtectionEvidence
    ) -> some View {
        let summary = evidence.summary
        return VStack(alignment: .leading, spacing: 2) {
            AppLocalizedText(evidence.label)
                .font(.title3.weight(.semibold))
            Text(AppLanguageSettings.format(
                "対象区間 %@・DSP差分保持 平均%@／最小%@",
                percentage(summary.affectedTimeRatio),
                percentage(summary.averageRetainedDSPDeltaRatio),
                percentage(summary.minimumRetainedDSPDeltaRatio)
            ))
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
            if let reason = summary.restorationReason {
                Text(AppLanguageSettings.format("復帰理由: %@", AppLanguageSettings.string(reason.logDescription)))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func remixEvaluationComparison(
        _ presentation: StemModeRemixAnalysisPresentation
    ) -> some View {
        let raw = presentation.rawRemixEvaluation
        let pureSum = presentation.correctedRemixEvaluation
        let remix = presentation.processedRemixEvaluation
        return Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                headerCell("再ミックス解析")
                headerCell("raw")
                    .analysisTableNumericColumn()
                headerCell("補正後")
                    .analysisTableNumericColumn()
                if remix != nil {
                    headerCell("再ミックス")
                        .analysisTableNumericColumn()
                }
            }
            Divider().gridCellColumns(remix == nil ? 3 : 4)
            GridRow {
                AppLocalizedText("Integrated Loudness")
                    .analysisTableLabelCell()
                number(raw.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .blue)
                number(pureSum.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .cyan)
                if let remix {
                    number(remix.audioMetrics.integratedLoudnessLUFS, unit: "LUFS", color: .green)
                }
            }
            GridRow {
                AppLocalizedText("True Peak")
                    .analysisTableLabelCell()
                number(raw.audioMetrics.truePeakDBFS, unit: "dBTP", color: .blue)
                number(pureSum.audioMetrics.truePeakDBFS, unit: "dBTP", color: .cyan)
                if let remix {
                    number(remix.audioMetrics.truePeakDBFS, unit: "dBTP", color: .green)
                }
            }
            GridRow {
                AppLocalizedText("位相・相関")
                    .analysisTableLabelCell()
                number(raw.audioMetrics.stereoCorrelation, unit: "", color: .blue)
                number(pureSum.audioMetrics.stereoCorrelation, unit: "", color: .cyan)
                if let remix {
                    number(remix.audioMetrics.stereoCorrelation, unit: "", color: .green)
                }
            }
            GridRow {
                AppLocalizedText("ステレオ幅")
                    .analysisTableLabelCell()
                number(raw.audioMetrics.stereoWidth, unit: "", color: .blue)
                number(pureSum.audioMetrics.stereoWidth, unit: "", color: .cyan)
                if let remix {
                    number(remix.audioMetrics.stereoWidth, unit: "", color: .green)
                }
            }
            GridRow {
                AppLocalizedText("ダイナミクス")
                    .analysisTableLabelCell()
                number(raw.audioMetrics.crestFactorDB, unit: "dB", color: .blue)
                number(pureSum.audioMetrics.crestFactorDB, unit: "dB", color: .cyan)
                if let remix {
                    number(remix.audioMetrics.crestFactorDB, unit: "dB", color: .green)
                }
            }
            GridRow {
                AppLocalizedText("分離アーティファクト")
                    .analysisTableLabelCell()
                number(raw.audioAnalysis.map { Double($0.artifactBandRatio) }, unit: "", color: .blue)
                number(pureSum.audioAnalysis.map { Double($0.artifactBandRatio) }, unit: "", color: .cyan)
                if let remix {
                    number(remix.audioAnalysis.map { Double($0.artifactBandRatio) }, unit: "", color: .green)
                }
            }
        }
    }

    @ViewBuilder
    private func validationIssues(
        _ issues: [StemValidationFailure]?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AppLocalizedText("解析上の確認事項")
                .font(.title3.weight(.semibold))

            if let issues {
                if issues.isEmpty {
                    AppLocalizedText("確認事項はありません。")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(AppLanguageSettings.format("%@・%@", AppLanguageSettings.string(issue.check.stemModeDisplayTitle), AppLanguageSettings.string(issue.subject)))
                                    .font(.title3.weight(.semibold))
                                Text(StemDiagnosticLocalization.issueDetail(issue.detail))
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                AppLocalizedText("再ミックス解析が完了すると表示します。")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func headerCell(_ text: String) -> some View {
        AppLocalizedText(text)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func number(_ value: Double?, unit: String, color: Color) -> some View {
        Text(value.map { String(format: "%.2f%@", $0, unit.isEmpty ? "" : " \(unit)") } ?? "--")
            .font(.callout.monospacedDigit())
            .foregroundStyle(value == nil ? .secondary : color)
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .analysisTableNumericColumn()
    }

    private func percentage(_ ratio: Double) -> String {
        String(format: "%.1f%%", min(max(ratio, 0), 1) * 100)
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
        case .guitarPickingOnsetEnergy: "ピッキング・onset"
        case .guitarAttackCrest: "ギターのアタック"
        case .guitarHarmonicEnergyRatio: "ギターの調波・音色本体"
        case .guitarInharmonicity: "ギターの非調波性"
        case .guitarHighBandDetail: "ギターの高域ディテール"
        case .guitarSpectralCentroid: "ギターのスペクトル重心"
        case .guitarRolloff85: "ギターのロールオフ"
        case .guitarLowTailRetention: "ギター低域の余韻"
        case .guitarMidTailRetention: "ギター中域の余韻"
        case .guitarHighTailRetention: "ギター高域の余韻"
        case .guitarStereoSideRatio: "ギターのステレオ幅"
        case .guitarStereoCorrelation: "ギターの左右相関"
        case .pianoHammerOnsetEnergy: "ハンマー・onset"
        case .pianoAttackCrest: "ピアノのアタック"
        case .pianoPartialEnergyRatio: "ピアノの部分音"
        case .pianoInharmonicity: "ピアノの非調波性"
        case .pianoLowTailRetention: "ピアノ低域の余韻"
        case .pianoMidTailRetention: "ピアノ中域の余韻"
        case .pianoHighTailRetention: "ピアノ高域の余韻"
        case .pianoDoubleDecaySlopeDelta: "ピアノの二段減衰"
        case .pianoLowBandBalance: "ピアノの低域バランス"
        case .pianoMidBandBalance: "ピアノの中域バランス"
        case .pianoSpectralCentroid: "ピアノのスペクトル重心"
        case .pianoRolloff85: "ピアノのロールオフ"
        case .pianoStereoSideRatio: "ピアノのステレオ幅"
        case .pianoStereoCorrelation: "ピアノの左右相関"
        }
    }
}

private extension StemRoleAnalysisUnit {
    var stemModeDisplayUnit: String {
        switch self {
        case .ratio, .normalized: ""
        case .hertz: "Hz"
        case .decibels: "dB"
        case .decibelsPerSecond: "dB/s"
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
