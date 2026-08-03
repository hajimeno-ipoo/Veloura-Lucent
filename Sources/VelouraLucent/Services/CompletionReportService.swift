import Foundation

enum CompletionReportService {
    static func makeReport(
        input: AudioMetricSnapshot?,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?,
        inputNoise: NoiseMeasurementSnapshot?,
        correctedNoise: NoiseMeasurementSnapshot?,
        masteredNoise: NoiseMeasurementSnapshot?,
        correctionSettings: CorrectionSettings,
        masteringSettings: MasteringSettings
    ) -> CompletionReport? {
        guard
            let input,
            let corrected,
            let mastered,
            let inputNoise,
            let correctedNoise,
            let masteredNoise,
            let qualityReport = AudioQualityReportService.makeReport(
                input: input,
                corrected: corrected,
                mastered: mastered,
                peakCeilingDB: Double(masteringSettings.peakCeilingDB)
            ),
            let noiseReport = NoiseCheckReportService.makeReport(
                input: inputNoise,
                corrected: correctedNoise,
                mastered: masteredNoise,
                correctionSettings: correctionSettings,
                settings: masteringSettings
            )
        else {
            return nil
        }

        return CompletionReport(
            loudnessRows: loudnessRows(input: input, corrected: corrected, mastered: mastered, settings: masteringSettings),
            noiseRows: noiseRows(from: noiseReport),
            highFrequencyRows: highFrequencyRows(input: input, corrected: corrected, mastered: mastered),
            lowFrequencyRows: lowFrequencyRows(input: input, corrected: corrected, mastered: mastered),
            qualityRows: qualityRows(from: qualityReport),
            reminder: "数値は確認材料です。最終判断は試聴で行ってください。"
        )
    }

    private static func qualityRows(from report: AudioQualityReport) -> [CompletionReportRow] {
        report.items.enumerated().map { index, item in
            CompletionReportRow(
                id: "quality-\(index)",
                title: item.title,
                value: qualitySeverityText(item.severity),
                detail: item.detail,
                severity: completionSeverity(from: item.severity)
            )
        }
    }

    private static func loudnessRows(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot,
        settings: MasteringSettings
    ) -> [CompletionReportRow] {
        let targetDelta = mastered.integratedLoudnessLUFS - Double(settings.targetLoudness)
        let inputDelta = mastered.integratedLoudnessLUFS - input.integratedLoudnessLUFS
        let masteringDelta = mastered.integratedLoudnessLUFS - corrected.integratedLoudnessLUFS
        let correctionDelta = corrected.integratedLoudnessLUFS - input.integratedLoudnessLUFS
        let peakHeadroom = Double(settings.peakCeilingDB) - mastered.truePeakDBFS

        return [
            CompletionReportRow(
                id: "loudness",
                title: "最終LUFS",
                value: format(mastered.integratedLoudnessLUFS, decimals: 1, unit: "LUFS"),
                detail: "目安 \(format(Double(settings.targetLoudness), decimals: 1, unit: "LUFS")) / 目安との差 \(formatSigned(targetDelta, decimals: 1, unit: "LU"))",
                severity: abs(targetDelta) >= 2.0 ? .caution : .normal
            ),
            CompletionReportRow(
                id: "truePeak",
                title: "True Peak",
                value: format(mastered.truePeakDBFS, decimals: 2, unit: "dBTP"),
                detail: "上限 \(format(Double(settings.peakCeilingDB), decimals: 1, unit: "dBTP")) / 余裕 \(formatSigned(peakHeadroom, decimals: 2, unit: "dB"))",
                severity: peakHeadroom < 0 ? .warning : peakHeadroom < 0.3 ? .caution : .normal
            ),
            CompletionReportRow(
                id: "loudnessChange",
                title: "音量変化",
                value: "入力差 \(formatSigned(inputDelta, decimals: 1, unit: "LU"))",
                detail: "入力→補正後 \(formatSigned(correctionDelta, decimals: 1, unit: "LU")) / 補正後→最終版 \(formatSigned(masteringDelta, decimals: 1, unit: "LU"))",
                severity: abs(inputDelta) >= 4.0 ? .caution : .normal
            )
        ]
    }

    private static func noiseRows(from report: NoiseCheckReport) -> [CompletionReportRow] {
        let rows = report.rows.map { row in
            CompletionReportRow(
                id: "noise-\(row.id)",
                title: row.label,
                value: row.summaryText,
                detail: "\(row.correctionEffectText) / \(row.masteringEffectText)",
                severity: completionSeverity(from: row.severity)
            )
        }

        guard !rows.isEmpty else {
            return [
                CompletionReportRow(
                    id: "noise-empty",
                    title: "ノイズ",
                    value: "未測定",
                    detail: "ノイズ測定結果がありません。",
                    severity: .caution
                )
            ]
        }
        return rows
    }

    private static func highFrequencyRows(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot
    ) -> [CompletionReportRow] {
        AudioQualityAssessmentService.reportBandRules.map { rule in
            highFrequencyRow(
                rule: rule,
                input: input,
                corrected: corrected,
                mastered: mastered
            )
        }
    }

    private static func highFrequencyRow(
        rule: AudioQualityBandRule,
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot
    ) -> CompletionReportRow {
        guard
            let masteredValue = bandLevel(rule.id, in: mastered),
            let inputDelta = AudioQualityAssessmentService.normalizedBandDelta(
                id: rule.id,
                reference: input,
                target: mastered
            ),
            let correctionDelta = AudioQualityAssessmentService.normalizedBandDelta(
                id: rule.id,
                reference: input,
                target: corrected
            ),
            let masteringDelta = AudioQualityAssessmentService.normalizedBandDelta(
                id: rule.id,
                reference: corrected,
                target: mastered
            )
        else {
            return CompletionReportRow(
                id: "high-\(rule.id)",
                title: rule.label,
                value: "未測定",
                detail: "\(rule.range)の測定結果がありません。",
                severity: .caution
            )
        }
        let severity = max(
            completionSeverity(from: AudioQualityAssessmentService.severity(for: inputDelta, rule: rule)),
            completionSeverity(from: AudioQualityAssessmentService.severity(for: correctionDelta, rule: rule)),
            completionSeverity(from: AudioQualityAssessmentService.severity(for: masteringDelta, rule: rule))
        )

        return CompletionReportRow(
            id: "high-\(rule.id)",
            title: rule.label,
            value: format(masteredValue, decimals: 2, unit: "dB"),
            detail: "\(rule.range) / 全体音量差を除いた入力差 \(formatSigned(inputDelta, decimals: 2, unit: "dB")) / 処理差 \(formatSigned(correctionDelta, decimals: 2, unit: "dB")) / 仕上げ差 \(formatSigned(masteringDelta, decimals: 2, unit: "dB"))",
            severity: severity
        )
    }

    private static func bandLevel(_ id: String, in metrics: AudioMetricSnapshot) -> Double? {
        metrics.bandEnergies.first { $0.id == id }?.levelDB
    }

    private static func lowFrequencyRows(
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot
    ) -> [CompletionReportRow] {
        AudioQualityAssessmentService.lowBalanceRules.compactMap { rule in
            guard
                let inputLevel = normalizedMasteringBandLevel(rule.id, in: input),
                let correctedLevel = normalizedMasteringBandLevel(rule.id, in: corrected),
                let masteredLevel = normalizedMasteringBandLevel(rule.id, in: mastered)
            else {
                return nil
            }

            let correctionDelta = correctedLevel - inputLevel
            let masteringDelta = masteredLevel - correctedLevel
            let inputDelta = masteredLevel - inputLevel
            let severity = [correctionDelta, masteringDelta, inputDelta]
                .map { AudioQualityAssessmentService.severity(for: $0, rule: rule) }
                .max() ?? .normal

            return CompletionReportRow(
                id: "low-\(rule.id)",
                title: "\(rule.label)（\(rule.range)）",
                value: "入力比 \(formatSigned(inputDelta, decimals: 2, unit: "dB"))",
                detail: "入力→補正後 \(formatSigned(correctionDelta, decimals: 2, unit: "dB")) / 補正後→最終版 \(formatSigned(masteringDelta, decimals: 2, unit: "dB"))",
                severity: completionSeverity(from: severity)
            )
        }
    }

    private static func normalizedMasteringBandLevel(
        _ id: String,
        in metrics: AudioMetricSnapshot
    ) -> Double? {
        metrics.masteringBandEnergies.first { $0.id == id }.map {
            $0.levelDB - metrics.rmsDBFS
        }
    }

    private static func completionSeverity(from severity: NoiseCheckSeverity) -> CompletionReportSeverity {
        switch severity {
        case .low:
            return .normal
        case .caution:
            return .caution
        case .warning:
            return .warning
        }
    }

    private static func completionSeverity(
        from severity: AudioQualityAssessmentSeverity
    ) -> CompletionReportSeverity {
        switch severity {
        case .normal:
            return .normal
        case .caution:
            return .caution
        case .warning:
            return .warning
        }
    }

    private static func completionSeverity(
        from severity: AudioQualityReportSeverity
    ) -> CompletionReportSeverity {
        switch severity {
        case .info:
            return .normal
        case .caution:
            return .caution
        case .warning:
            return .warning
        }
    }

    private static func qualitySeverityText(_ severity: AudioQualityReportSeverity) -> String {
        switch severity {
        case .info:
            return "確認"
        case .caution:
            return "注意"
        case .warning:
            return "警告"
        }
    }

    private static func format(_ value: Double, decimals: Int, unit: String) -> String {
        "\(String(format: "%.\(decimals)f", value)) \(unit)"
    }

    private static func formatSigned(_ value: Double, decimals: Int, unit: String) -> String {
        "\(String(format: value >= 0 ? "+%.\(decimals)f" : "%.\(decimals)f", value)) \(unit)"
    }
}
