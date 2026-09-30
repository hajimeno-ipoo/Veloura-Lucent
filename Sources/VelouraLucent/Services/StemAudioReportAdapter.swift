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
            detail: row.detail
                .replacingOccurrences(of: AppLanguageSettings.string("補正後"), with: AppLanguageSettings.string("Stem再ミックス"))
                .replacingOccurrences(of: "補正後", with: AppLanguageSettings.string("Stem再ミックス")),
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
        let roleNames = contract.activeRoles.map { AppLanguageSettings.string($0.stemModeDisplayTitle) }.joined(separator: " / ")
        let pureSumNames = contract.pureSumOrder.map { AppLanguageSettings.string($0.stemModeDisplayTitle) }.joined(separator: " → ")
        let masking = remix.masking
        let commonSection = CompletionReportSection(
            id: "stem-run-contract",
            title: AppLanguageSettings.string("Stem実行契約と共通再ミックス"),
            subsections: [
                CompletionReportSubsection(
                    id: "stem-run-contract-model",
                    title: AppLanguageSettings.string("実行したモデル契約"),
                    paragraphs: [
                        AppLanguageSettings.format("モデル: %@（%ld Stem）", contract.separationModel.displayName, contract.stemCount),
                        AppLanguageSettings.format("有効Stem: %@", roleNames),
                        AppLanguageSettings.format("Float32純粋加算順: %@", pureSumNames)
                    ]
                ),
                CompletionReportSubsection(
                    id: "stem-run-contract-remix",
                    title: AppLanguageSettings.string("全Stem共通の再ミックス設定"),
                    paragraphs: [
                        AppLanguageSettings.format("ドラム→ベース帯域制御: %@ / 量 %@", onOff(masking.drumsToBassEnabled), percent(masking.drumsToBassAmount)),
                        AppLanguageSettings.format("ボーカル→伴奏帯域制御: %@ / 量 %@", onOff(masking.vocalsToAccompanimentEnabled), percent(masking.vocalsToAccompanimentAmount)),
                        AppLanguageSettings.format("共通reverb return: %@ / decay %@秒", percent(remix.reverbReturnLevel), decimal(remix.reverbDecaySeconds, digits: 2))
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
                    AppLanguageSettings.format("選択設定: %@", correctionSettingsText(evidence.selectedCorrectionSettings)),
                    AppLanguageSettings.string("実際の採用音声: raw Stem（補正済み候補は不採用）"),
                    AppLanguageSettings.format(
                        "fallback理由: %@",
                        StemDiagnosticLocalization.reason(evidence.fallbackReason ?? "記録なし")
                    )
                ]
            } else if let effective = evidence.effectiveCorrectionSettings {
                correctionParagraphs = [
                    AppLanguageSettings.format("選択設定: %@", correctionSettingsText(evidence.selectedCorrectionSettings)),
                    AppLanguageSettings.format("実効設定: %@", correctionSettingsText(effective)),
                    AppLanguageSettings.string("実際の採用音声: 補正済みStem")
                ]
            } else {
                return nil
            }

            let guardSubsections = evidence.stageGuards.map { record in
                let protected = record.protectedComponents.isEmpty
                    ? AppLanguageSettings.string("なし")
                    : record.protectedComponents.map { AppLanguageSettings.string($0.stemModeDisplayTitle) }.sorted().joined(separator: " / ")
                let protectionEvidence = record.protectionEvidence.map { evidence in
                    let summary = evidence.summary
                    let restoration = summary.restorationReason.map {
                        AppLanguageSettings.format(" / 復帰理由 %@", AppLanguageSettings.string($0.logDescription))
                    } ?? ""
                    return AppLanguageSettings.format(
                        "役割保護実測（%@）: 対象区間 %@ / DSP差分保持 平均 %@ / 最小 %@%@",
                        AppLanguageSettings.string(evidence.label),
                        percentage(summary.affectedTimeRatio),
                        percentage(summary.averageRetainedDSPDeltaRatio),
                        percentage(summary.minimumRetainedDSPDeltaRatio),
                        restoration
                    )
                }
                return CompletionReportSubsection(
                    id: "stem-role-\(role.rawValue)-guard-\(record.stage.rawValue)",
                    title: AppLanguageSettings.string(record.stage.stemModeDisplayTitle),
                    paragraphs: [
                        AppLanguageSettings.format("実行指示: %@", AppLanguageSettings.string(record.action.stemModeDisplayTitle)),
                        AppLanguageSettings.format("実行結果: %@", AppLanguageSettings.string(record.outcome.stemModeDisplayTitle)),
                        AppLanguageSettings.format("根拠: %@", StemDiagnosticLocalization.reason(record.reason)),
                        AppLanguageSettings.format("保護対象: %@", protected)
                    ] + protectionEvidence
                )
            }

            return CompletionReportSection(
                id: "stem-role-\(role.rawValue)",
                title: AppLanguageSettings.format("%@の補正・guard・再ミックス", AppLanguageSettings.string(role.stemModeDisplayTitle)),
                subsections: [
                    CompletionReportSubsection(
                        id: "stem-role-\(role.rawValue)-correction",
                        title: AppLanguageSettings.string("採用した補正結果"),
                        paragraphs: correctionParagraphs
                    ),
                    CompletionReportSubsection(
                        id: "stem-role-\(role.rawValue)-remix",
                        title: AppLanguageSettings.string("役割別再ミックス設定"),
                        paragraphs: [
                            AppLanguageSettings.format("gain: %@", signedDB(remixSettings.gainDB)),
                            AppLanguageSettings.format("pan: %@", panText(remixSettings.pan)),
                            AppLanguageSettings.format("reverb send: %@", percent(remixSettings.reverbSend))
                        ]
                    )
                ] + guardSubsections
            )
        }
        return [commonSection] + roleSections
    }

    private static func correctionSettingsText(_ settings: CorrectionSettings) -> String {
        [
            AppLanguageSettings.format("profile %@", AppLanguageSettings.string(settings.profile.title)),
            AppLanguageSettings.format("補正強度 %@", percent(settings.correctionIntensity)),
            AppLanguageSettings.format("原音保持 %@", percent(settings.originalRetention)),
            AppLanguageSettings.format("低域整理 %@", percent(settings.lowCleanup)),
            AppLanguageSettings.format("低中域整理 %@", percent(settings.lowMidCleanup)),
            AppLanguageSettings.format("presence修復 %@", percent(settings.presenceRepair)),
            AppLanguageSettings.format("air修復 %@", percent(settings.airRepair)),
            AppLanguageSettings.format("高域自然さ %@", percent(settings.highNaturalness)),
            AppLanguageSettings.format("ノイズ検出感度 %@", percent(settings.noiseDetectionSensitivity)),
            AppLanguageSettings.format("倍音修復 %@", percent(settings.harmonicRepairAmount)),
            AppLanguageSettings.format("foldover修復 %@", percent(settings.foldoverRepairAmount)),
            AppLanguageSettings.format("音の芯保護 %@", percent(settings.coreProtection)),
            AppLanguageSettings.format("stereo保護 %@", percent(settings.stereoProtection))
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
        AppLanguageSettings.string(enabled ? "有効" : "無効")
    }

    private static func stemRemixEffectText(_ text: String) -> String {
        let translated = stemStageWording(text)
        let prefix = AppLanguageSettings.string("再ミックス後:")
        if translated.hasPrefix(prefix) {
            return translated
        }
        return "\(prefix) \(translated)"
    }

    private static func stemStageWording(_ text: String) -> String {
        let corrected = AppLanguageSettings.string("補正後")
        let remixed = AppLanguageSettings.string("再ミックス後")
        return text
            .replacingOccurrences(of: corrected, with: remixed)
            .replacingOccurrences(of: "補正後", with: remixed)
            .replacingOccurrences(of: AppLanguageSettings.string("補正:"), with: AppLanguageSettings.string("再ミックス後:"))
            .replacingOccurrences(of: "補正:", with: AppLanguageSettings.string("再ミックス後:"))
    }
}
