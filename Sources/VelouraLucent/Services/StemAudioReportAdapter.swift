import Foundation

/// Builds Stem Mode presentation reports from the existing Standard Mode report services.
///
/// Standard Mode remains the owner of measurement boundaries and report severity decisions.
/// This adapter only supplies the exact settings fixed for the Stem run and translates the
/// intermediate-stage wording from "corrected" to "remixed" for the Stem Mode UI.
enum StemAudioReportAdapter {
    static func makeAudioQualityReport(
        input: AudioMetricSnapshot?,
        remixed: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?,
        peakCeilingDB: Double
    ) -> AudioQualityReport? {
        guard let report = AudioQualityReportService.makeReport(
            input: input,
            corrected: remixed,
            mastered: mastered,
            peakCeilingDB: peakCeilingDB
        ) else {
            return nil
        }

        return AudioQualityReport(
            items: report.items.map { item in
                AudioQualityReportItem(
                    severity: item.severity,
                    title: stemStageWording(item.title),
                    detail: stemStageWording(item.detail)
                )
            }
        )
    }

    static func makeCompletionReport(
        input: AudioMetricSnapshot?,
        remixed: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?,
        noiseReport: NoiseCheckReport,
        reportContext: StemMasteringReportContext,
        masteringSettings: MasteringSettings,
        sourceDisplayName: String,
        separationModelDisplayName: String,
        inputFileInfo: AudioFileInfo,
        remixedFileInfo: AudioFileInfo,
        masteredFileInfo: AudioFileInfo
    ) -> CompletionReport? {
        guard let base = CompletionReportService.makeStemReport(
            input: input,
            remixed: remixed,
            mastered: mastered,
            noiseReport: noiseReport,
            masteringSettings: masteringSettings,
            trackTitle: sourceDisplayName,
            processingSourceName: separationModelDisplayName,
            inputFileInfo: inputFileInfo,
            remixedFileInfo: remixedFileInfo,
            masteredFileInfo: masteredFileInfo
        ) else {
            return nil
        }

        return CompletionReport(
            loudnessRows: base.loudnessRows.map(stemCompletionRow),
            noiseRows: base.noiseRows.map(stemNoiseCompletionRow),
            highFrequencyRows: base.highFrequencyRows.map(stemCompletionRow),
            lowFrequencyRows: base.lowFrequencyRows.map(stemLowCompletionRow),
            qualityRows: [],
            reminder: base.reminder,
            mode: .stem,
            summary: base.summary,
            comparisonRows: base.comparisonRows,
            comparisonNotes: base.comparisonNotes,
            sections: base.sections + stemRunSections(
                reportContext: reportContext,
                separationModelDisplayName: separationModelDisplayName
            ),
            charts: base.charts,
            safetyRows: base.safetyRows
        )
    }

    static func makeNoiseCheckReport(
        input: NoiseMeasurementSnapshot?,
        remixed: NoiseMeasurementSnapshot?,
        mastered: NoiseMeasurementSnapshot?,
        masteringSettings: MasteringSettings
    ) -> NoiseCheckReport? {
        guard let report = NoiseCheckReportService.makeMasteringOnlyReport(
            input: input,
            remixed: remixed,
            mastered: mastered,
            settings: masteringSettings
        ) else {
            return nil
        }

        return NoiseCheckReport(
            rows: report.rows.map { row in
                NoiseCheckRow(
                    id: row.id,
                    label: row.label,
                    measurementDescription: row.measurementDescription,
                    displayDescription: row.displayDescription,
                    unitLabel: row.unitLabel,
                    displayScale: row.displayScale,
                    input: row.input,
                    corrected: row.corrected,
                    mastered: row.mastered,
                    correctionDeltaDB: row.correctionDeltaDB,
                    masteringDeltaDB: row.masteringDeltaDB,
                    severity: row.severity,
                    summaryText: stemStageWording(row.summaryText),
                    correctionEffectText: stemRemixEffectText(row.correctionEffectText),
                    masteringEffectText: row.masteringEffectText,
                    recommendedActions: masteringActions(from: row.recommendedActions)
                )
            },
            recommendedActions: masteringActions(from: report.recommendedActions)
        )
    }

    private static func stemCompletionRow(_ row: CompletionReportRow) -> CompletionReportRow {
        CompletionReportRow(
            id: row.id,
            title: stemStageWording(row.title),
            value: stemStageWording(row.value),
            detail: stemStageWording(row.detail),
            severity: row.severity
        )
    }

    private static func stemNoiseCompletionRow(_ row: CompletionReportRow) -> CompletionReportRow {
        let components = row.detail.components(separatedBy: " / ")
        let detail: String
        if let first = components.first {
            detail = ([stemRemixEffectText(first)] + components.dropFirst()).joined(separator: " / ")
        } else {
            detail = stemStageWording(row.detail)
        }

        return CompletionReportRow(
            id: row.id,
            title: stemStageWording(row.title),
            value: stemStageWording(row.value),
            detail: detail,
            severity: row.severity
        )
    }

    private static func stemLowCompletionRow(_ row: CompletionReportRow) -> CompletionReportRow {
        CompletionReportRow(
            id: "stem-\(row.id)",
            title: row.title,
            value: row.value,
            detail: row.detail.replacingOccurrences(of: "補正後", with: "Stem再ミックス"),
            severity: row.severity
        )
    }

    private static func masteringActions(from actions: [NoiseCheckAction]) -> [NoiseCheckAction] {
        actions.filter { $0.stage == .mastering }
    }

    private static func stemRunSections(
        reportContext: StemMasteringReportContext,
        separationModelDisplayName: String
    ) -> [CompletionReportSection] {
        let contract = reportContext.runContract
        let remix = reportContext.appliedRemixSettings
        let roleNames = contract.activeRoles.map(\.stemModeDisplayTitle).joined(separator: " / ")
        let pureSumNames = contract.pureSumOrder.map(\.stemModeDisplayTitle).joined(separator: " → ")
        let masking = remix.masking
        let commonSection = CompletionReportSection(
            id: "stem-run-contract",
            title: "Stem実行契約と共通再ミックス",
            subsections: [
                CompletionReportSubsection(
                    id: "stem-run-contract-model",
                    title: "実行したモデル契約",
                    paragraphs: [
                        "モデル: \(contract.separationModel.displayName)（\(contract.stemCount) Stem）",
                        "有効Stem: \(roleNames)",
                        "Float32純粋加算順: \(pureSumNames)"
                    ]
                ),
                CompletionReportSubsection(
                    id: "stem-run-contract-remix",
                    title: "全Stem共通の再ミックス設定",
                    paragraphs: [
                        "ドラム→ベース帯域制御: \(onOff(masking.drumsToBassEnabled)) / 量 \(percent(masking.drumsToBassAmount))",
                        "ボーカル→伴奏帯域制御: \(onOff(masking.vocalsToAccompanimentEnabled)) / 量 \(percent(masking.vocalsToAccompanimentAmount))",
                        "共通reverb return: \(percent(remix.reverbReturnLevel)) / decay \(decimal(remix.reverbDecaySeconds, digits: 2))秒"
                    ]
                )
            ]
        )

        let evidenceByRole = Dictionary(uniqueKeysWithValues: reportContext.roleEvidence.map {
            ($0.role, $0)
        })
        let roleSections = contract.pureSumOrder.compactMap { role -> CompletionReportSection? in
            guard let evidence = evidenceByRole[role] else { return nil }
            let remixSettings = remix.settings(for: role)
            let correctionParagraphs: [String]
            if evidence.usedRawFallback {
                correctionParagraphs = [
                    "選択設定: \(correctionSettingsText(evidence.selectedCorrectionSettings))",
                    "実際の採用音声: raw Stem（補正済み候補は不採用）",
                    "fallback理由: \(evidence.fallbackReason ?? "記録なし")"
                ]
            } else if let effective = evidence.effectiveCorrectionSettings {
                correctionParagraphs = [
                    "選択設定: \(correctionSettingsText(evidence.selectedCorrectionSettings))",
                    "実効設定: \(correctionSettingsText(effective))",
                    "実際の採用音声: 補正済みStem"
                ]
            } else {
                return nil
            }

            let guardSubsections = evidence.stageGuards.map { record in
                let protected = record.protectedComponents.isEmpty
                    ? "なし"
                    : record.protectedComponents.map(\.rawValue).sorted().joined(separator: " / ")
                let protectionEvidence = record.protectionEvidence.map { evidence in
                    let summary = evidence.summary
                    let restoration = summary.restorationReason.map {
                        " / 復帰理由 \($0.logDescription)"
                    } ?? ""
                    return "役割保護実測（\(evidence.label)）: 対象区間 \(percentage(summary.affectedTimeRatio)) / DSP差分保持 平均 \(percentage(summary.averageRetainedDSPDeltaRatio)) / 最小 \(percentage(summary.minimumRetainedDSPDeltaRatio))\(restoration)"
                }
                return CompletionReportSubsection(
                    id: "stem-role-\(role.rawValue)-guard-\(record.stage.rawValue)",
                    title: record.stage.stemModeDisplayTitle,
                    paragraphs: [
                        "実行指示: \(record.action.stemModeDisplayTitle)",
                        "実行結果: \(record.outcome.stemModeDisplayTitle)",
                        "根拠: \(record.reason)",
                        "保護対象: \(protected)"
                    ] + protectionEvidence
                )
            }

            return CompletionReportSection(
                id: "stem-role-\(role.rawValue)",
                title: "\(role.stemModeDisplayTitle)の補正・guard・再ミックス",
                subsections: [
                    CompletionReportSubsection(
                        id: "stem-role-\(role.rawValue)-correction",
                        title: "採用した補正結果",
                        paragraphs: correctionParagraphs
                    ),
                    CompletionReportSubsection(
                        id: "stem-role-\(role.rawValue)-remix",
                        title: "役割別再ミックス設定",
                        paragraphs: [
                            "gain: \(signedDB(remixSettings.gainDB))",
                            "pan: \(panText(remixSettings.pan))",
                            "reverb send: \(percent(remixSettings.reverbSend))"
                        ]
                    )
                ] + guardSubsections
            )
        }
        return [commonSection] + roleSections
    }

    private static func correctionSettingsText(_ settings: CorrectionSettings) -> String {
        [
            "profile \(settings.profile.title)",
            "補正強度 \(percent(settings.correctionIntensity))",
            "原音保持 \(percent(settings.originalRetention))",
            "低域整理 \(percent(settings.lowCleanup))",
            "低中域整理 \(percent(settings.lowMidCleanup))",
            "presence修復 \(percent(settings.presenceRepair))",
            "air修復 \(percent(settings.airRepair))",
            "高域自然さ \(percent(settings.highNaturalness))",
            "ノイズ検出感度 \(percent(settings.noiseDetectionSensitivity))",
            "倍音修復 \(percent(settings.harmonicRepairAmount))",
            "foldover修復 \(percent(settings.foldoverRepairAmount))",
            "音の芯保護 \(percent(settings.coreProtection))",
            "stereo保護 \(percent(settings.stereoProtection))"
        ].joined(separator: " / ")
    }

    private static func percent(_ value: Float) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func percentage(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private static func decimal(_ value: Float, digits: Int) -> String {
        String(format: "%.*f", digits, Double(value))
    }

    private static func signedDB(_ value: Float) -> String {
        String(format: "%+.2f dB", Double(value))
    }

    private static func panText(_ value: Float) -> String {
        if abs(value) < 0.000_1 { return "center" }
        return String(format: "%@ %.0f%%", value < 0 ? "left" : "right", Double(abs(value) * 100))
    }

    private static func onOff(_ enabled: Bool) -> String {
        enabled ? "有効" : "無効"
    }

    private static func stemRemixEffectText(_ text: String) -> String {
        let translated = stemStageWording(text)
        if translated.hasPrefix("再ミックス後:") {
            return translated
        }
        return "再ミックス後: \(translated)"
    }

    private static func stemStageWording(_ text: String) -> String {
        text
            .replacingOccurrences(of: "補正後", with: "再ミックス後")
            .replacingOccurrences(of: "補正:", with: "再ミックス後:")
    }
}
