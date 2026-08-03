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
        inputNoise: NoiseMeasurementSnapshot?,
        remixedNoise: NoiseMeasurementSnapshot?,
        masteredNoise: NoiseMeasurementSnapshot?,
        correctionSettings: StemRoleCorrectionSettings,
        masteringSettings: MasteringSettings
    ) -> CompletionReport? {
        let reports = correctionSettings.allRoleSettings.compactMap { roleSettings in
            CompletionReportService.makeReport(
                input: input,
                corrected: remixed,
                mastered: mastered,
                inputNoise: inputNoise,
                correctedNoise: remixedNoise,
                masteredNoise: masteredNoise,
                correctionSettings: roleSettings,
                masteringSettings: masteringSettings
            )
        }
        guard reports.count == StemRole.allCases.count,
              let first = reports.first,
              reports.dropFirst().allSatisfy({ $0 == first }) else {
            return nil
        }

        return CompletionReport(
            loudnessRows: first.loudnessRows.map(stemCompletionRow),
            noiseRows: first.noiseRows.map(stemNoiseCompletionRow),
            highFrequencyRows: first.highFrequencyRows.map(stemCompletionRow),
            lowFrequencyRows: first.lowFrequencyRows.map(stemLowCompletionRow),
            reminder: first.reminder
        )
    }

    static func makeNoiseCheckReport(
        input: NoiseMeasurementSnapshot?,
        remixed: NoiseMeasurementSnapshot?,
        mastered: NoiseMeasurementSnapshot?,
        correctionSettings: StemRoleCorrectionSettings,
        masteringSettings: MasteringSettings
    ) -> NoiseCheckReport? {
        let reports = correctionSettings.allRoleSettings.compactMap { roleSettings in
            NoiseCheckReportService.makeReport(
                input: input,
                corrected: remixed,
                mastered: mastered,
                correctionSettings: roleSettings,
                settings: masteringSettings
            )
        }.map(sanitizedStemNoiseReport)
        guard reports.count == StemRole.allCases.count,
              let first = reports.first,
              reports.dropFirst().allSatisfy({
                  noiseReportsAreEquivalent($0, first)
              }) else {
            return nil
        }

        return NoiseCheckReport(
            rows: first.rows.map { row in
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
            recommendedActions: first.recommendedActions
        )
    }

    private static func sanitizedStemNoiseReport(_ report: NoiseCheckReport) -> NoiseCheckReport {
        let rows = report.rows.map { row in
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
                summaryText: row.summaryText,
                correctionEffectText: row.correctionEffectText,
                masteringEffectText: row.masteringEffectText,
                recommendedActions: masteringActions(from: row.recommendedActions)
            )
        }
        return NoiseCheckReport(
            rows: rows,
            recommendedActions: mergedMasteringActions(from: rows)
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

    /// Rebuilds Standard Mode's score ordering after correction-stage actions are removed.
    /// Otherwise correction actions can occupy the original top-three slots differently for each
    /// role even though the remixed/mastered measurements and mastering settings are identical.
    private static func mergedMasteringActions(
        from rows: [NoiseCheckRow]
    ) -> [NoiseCheckAction] {
        var actionsByID: [String: NoiseCheckAction] = [:]
        var scoresByID: [String: Double] = [:]

        for row in rows {
            let rowScore = max(row.masteringDeltaDB ?? 0, row.correctionDeltaDB ?? 0, 0)
                + noiseSeverityScore(row.severity)
            for action in row.recommendedActions where action.stage == .mastering {
                let existingScore = scoresByID[action.id] ?? -Double.infinity
                if rowScore > existingScore {
                    actionsByID[action.id] = action
                    scoresByID[action.id] = rowScore
                }
            }
        }

        return actionsByID.values.sorted { lhs, rhs in
            let lhsScore = scoresByID[lhs.id] ?? 0
            let rhsScore = scoresByID[rhs.id] ?? 0
            if lhsScore == rhsScore {
                return lhs.id < rhs.id
            }
            return lhsScore > rhsScore
        }
        .prefix(3)
        .map { $0 }
    }

    private static func noiseSeverityScore(_ severity: NoiseCheckSeverity) -> Double {
        switch severity {
        case .low: 0
        case .caution: 1
        case .warning: 2
        }
    }

    /// `NoiseCheckReportService` preserves score priority, but actions with the same score can be
    /// emitted in dictionary iteration order. Role reports therefore compare actions by stable ID
    /// while the first report's original priority order remains the presentation order.
    private static func noiseReportsAreEquivalent(
        _ lhs: NoiseCheckReport,
        _ rhs: NoiseCheckReport
    ) -> Bool {
        canonicalNoiseReport(lhs) == canonicalNoiseReport(rhs)
    }

    private static func canonicalNoiseReport(_ report: NoiseCheckReport) -> NoiseCheckReport {
        NoiseCheckReport(
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
                    summaryText: row.summaryText,
                    correctionEffectText: row.correctionEffectText,
                    masteringEffectText: row.masteringEffectText,
                    recommendedActions: row.recommendedActions.sorted { $0.id < $1.id }
                )
            },
            recommendedActions: report.recommendedActions.sorted { $0.id < $1.id }
        )
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
