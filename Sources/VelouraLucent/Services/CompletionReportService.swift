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
            reminder: "数値は確認材料です。最終判断は試聴で行ってください。"
        )
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
        [
            highFrequencyRow(
                id: "sparkle",
                title: "煌びやかさ",
                range: "8〜12kHz",
                input: input,
                corrected: corrected,
                mastered: mastered,
                cautionDropDB: 2.0,
                warningDropDB: 4.0
            ),
            highFrequencyRow(
                id: "air",
                title: "空気感",
                range: "12〜16kHz",
                input: input,
                corrected: corrected,
                mastered: mastered,
                cautionDropDB: 2.0,
                warningDropDB: 4.0
            ),
            highFrequencyRow(
                id: "ultraAir",
                title: "超高域",
                range: "16〜20kHz",
                input: input,
                corrected: corrected,
                mastered: mastered,
                cautionDropDB: 2.5,
                warningDropDB: 5.0
            )
        ]
    }

    private static func highFrequencyRow(
        id: String,
        title: String,
        range: String,
        input: AudioMetricSnapshot,
        corrected: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot,
        cautionDropDB: Double,
        warningDropDB: Double
    ) -> CompletionReportRow {
        let inputValue = bandLevel(id, in: input) ?? -120
        let correctedValue = bandLevel(id, in: corrected) ?? inputValue
        let masteredValue = bandLevel(id, in: mastered) ?? correctedValue
        let inputDelta = masteredValue - inputValue
        let masteringDelta = masteredValue - correctedValue
        let drop = -inputDelta
        let severity: CompletionReportSeverity
        if drop >= warningDropDB {
            severity = .warning
        } else if drop >= cautionDropDB {
            severity = .caution
        } else {
            severity = .normal
        }

        return CompletionReportRow(
            id: "high-\(id)",
            title: title,
            value: format(masteredValue, decimals: 2, unit: "dB"),
            detail: "\(range) / 入力差 \(formatSigned(inputDelta, decimals: 2, unit: "dB")) / 仕上げ差 \(formatSigned(masteringDelta, decimals: 2, unit: "dB"))",
            severity: severity
        )
    }

    private static func bandLevel(_ id: String, in metrics: AudioMetricSnapshot) -> Double? {
        metrics.bandEnergies.first { $0.id == id }?.levelDB
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

    private static func format(_ value: Double, decimals: Int, unit: String) -> String {
        "\(String(format: "%.\(decimals)f", value)) \(unit)"
    }

    private static func formatSigned(_ value: Double, decimals: Int, unit: String) -> String {
        "\(String(format: value >= 0 ? "+%.\(decimals)f" : "%.\(decimals)f", value)) \(unit)"
    }
}
