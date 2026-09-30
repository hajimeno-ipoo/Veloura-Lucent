import Foundation

enum AudioQualityReportSeverity: Int, Sendable, Comparable {
    case info
    case caution
    case warning

    static func < (lhs: AudioQualityReportSeverity, rhs: AudioQualityReportSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AudioQualityReportItem: Sendable, Equatable {
    let severity: AudioQualityReportSeverity
    let title: String
    let detail: String
}

struct AudioQualityReport: Sendable, Equatable {
    let items: [AudioQualityReportItem]

    var severity: AudioQualityReportSeverity {
        items.map(\.severity).max() ?? .info
    }
}

enum AudioQualityReportService {
    static func makeReport(
        input: AudioMetricSnapshot?,
        corrected: AudioMetricSnapshot?,
        mastered: AudioMetricSnapshot?,
        peakCeilingDB: Double
    ) -> AudioQualityReport? {
        guard mastered != nil else { return nil }

        var items: [AudioQualityReportItem] = []
        var hasComparison = false

        if let input, let corrected {
            hasComparison = true
            items.append(contentsOf: compare(
                reference: input,
                target: corrected,
                stageName: "補正後",
                peakCeilingDB: nil
            ))
        }

        if let corrected, let mastered {
            hasComparison = true
            items.append(contentsOf: compare(
                reference: corrected,
                target: mastered,
                stageName: "マスタリング後",
                peakCeilingDB: peakCeilingDB
            ))
        }

        if let input, let mastered {
            hasComparison = true
            items.append(contentsOf: compareFinal(input: input, mastered: mastered))
            items.append(contentsOf: tonalBalanceItems(
                reference: input,
                target: mastered,
                stageName: "最終版（入力比）"
            ))
        }

        guard hasComparison else { return nil }
        return AudioQualityReport(items: items)
    }

    private static func compare(
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot,
        stageName: String,
        peakCeilingDB: Double?
    ) -> [AudioQualityReportItem] {
        var items: [AudioQualityReportItem] = []

        let loudnessDrop = reference.integratedLoudnessLUFS - target.integratedLoudnessLUFS
        if loudnessDrop >= 1.0 {
            if stageName == "補正後" {
                items.append(.info(
                    AppLanguageSettings.string("補正後は音量を作らないため音量が下がっています"),
                    localizedFormat(
                        "平均音量が %@ LU 下がっています。最終版で戻る場合は問題として扱いません。補正後と最終版を聴き比べてください。",
                        format(loudnessDrop)
                    )
                ))
            } else {
                items.append(.caution(
                    localizedFormat("%@の音量感が下がっています", AppLanguageSettings.string(stageName)),
                    localizedFormat(
                        "平均音量が %@ LU 下がっています。音量感が意図に合うか聴き比べてください。",
                        format(loudnessDrop)
                    )
                ))
            }
        }

        if let peakCeilingDB {
            let headroom = peakCeilingDB - target.truePeakDBFS
            if headroom < 0 {
                items.append(.warning(
                    localizedFormat("%@のピークが設定上限を超えています", AppLanguageSettings.string(stageName)),
                    localizedFormat(
                        "True Peak が %@ dBTP、設定上限が %@ dBTP です。音割れがないか%@を試聴してください。",
                        format(target.truePeakDBFS), format(peakCeilingDB), AppLanguageSettings.string(stageName)
                    )
                ))
            } else if headroom < 0.3 {
                items.append(.caution(
                    localizedFormat("%@のピークが設定上限に近づいています", AppLanguageSettings.string(stageName)),
                    localizedFormat(
                        "True Peak が %@ dBTP、設定上限までの余裕が %@ dB です。%@を試聴してください。",
                        format(target.truePeakDBFS), format(headroom), AppLanguageSettings.string(stageName)
                    )
                ))
            }
        }

        items.append(contentsOf: tonalBalanceItems(reference: reference, target: target, stageName: stageName))

        let widthChange = target.stereoWidth - reference.stereoWidth
        if abs(widthChange) >= 0.20 {
            items.append(.caution(
                localizedFormat("%@のステレオ幅が大きく変わっています", AppLanguageSettings.string(stageName)),
                localizedFormat("Stereo Width が %@ 変化しています。", formatSigned(widthChange))
            ))
        }

        let crestChange = target.crestFactorDB - reference.crestFactorDB
        if crestChange <= -3.0 {
            items.append(.caution(
                localizedFormat("%@の音の起伏が小さくなっています", AppLanguageSettings.string(stageName)),
                localizedFormat("Crest Factor が %@ dB 下がっています。", format(abs(crestChange)))
            ))
        } else if crestChange >= 4.0 {
            items.append(.caution(
                localizedFormat("%@の音の起伏が大きく変わっています", AppLanguageSettings.string(stageName)),
                localizedFormat("Crest Factor が %@ dB 上がっています。", format(crestChange))
            ))
        }

        return items
    }

    private static func compareFinal(input: AudioMetricSnapshot, mastered: AudioMetricSnapshot) -> [AudioQualityReportItem] {
        var items: [AudioQualityReportItem] = []
        let loudnessIncrease = mastered.integratedLoudnessLUFS - input.integratedLoudnessLUFS
        let loudnessDrop = input.integratedLoudnessLUFS - mastered.integratedLoudnessLUFS

        if loudnessDrop >= 1.5 {
            items.append(.caution(
                AppLanguageSettings.string("最終版の音量感が低めです"),
                localizedFormat(
                    "入力より平均音量が %@ LU 下がっています。最終版の音量感が意図に合うか聴き比べてください。",
                    format(loudnessDrop)
                )
            ))
        }

        if loudnessIncrease >= 4.0 {
            items.append(.caution(
                AppLanguageSettings.string("最終版の音量感が大きく上がっています"),
                localizedFormat(
                    "入力より平均音量が %@ LU 上がっています。聴き疲れしないか、入力と最終版を聴き比べてください。",
                    format(loudnessIncrease)
                )
            ))
        }

        return items
    }

    private static func tonalBalanceItems(
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot,
        stageName: String
    ) -> [AudioQualityReportItem] {
        let highItems = AudioQualityAssessmentService.reportBandRules.compactMap { rule in
            bandChangeItem(
                rule: rule,
                reference: reference,
                target: target,
                stageName: stageName
            )
        }
        let mudItem = bandChangeItem(
            rule: AudioQualityAssessmentService.mudRule,
            reference: reference,
            target: target,
            stageName: stageName
        )
        return highItems + [mudItem].compactMap { $0 }
    }

    private static func bandChangeItem(
        rule: AudioQualityBandRule,
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot,
        stageName: String
    ) -> AudioQualityReportItem? {
        guard let delta = AudioQualityAssessmentService.normalizedBandDelta(
            id: rule.id,
            reference: reference,
            target: target
        ) else {
            return nil
        }
        let sharedSeverity = AudioQualityAssessmentService.severity(for: delta, rule: rule)
        guard sharedSeverity != .normal else { return nil }

        let severity: AudioQualityReportSeverity = sharedSeverity == .warning ? .warning : .caution
        let isIncrease = delta >= 0
        let amount = abs(delta)
        let direction = AppLanguageSettings.string(isIncrease ? "増えています" : "下がっています")
        let listeningPoint: String
        if rule.id == "mud" {
            listeningPoint = AppLanguageSettings.string("こもりや暗さにつながっていないか")
        } else if isIncrease {
            listeningPoint = rule.id == "generatedUltraHigh"
                ? AppLanguageSettings.string("不要な超高域成分が増えていないか")
                : AppLanguageSettings.string("刺さりやザラつきがないか")
        } else {
            listeningPoint = AppLanguageSettings.string("抜け感、息感、空気感が弱くなっていないか")
        }

        return AudioQualityReportItem(
            severity: severity,
            title: localizedFormat(
                "%@の%@が%@",
                AppLanguageSettings.string(stageName), AppLanguageSettings.string(rule.label), direction
            ),
            detail: localizedFormat(
                "全体音量差を除いた%@ が %@ dB %@。%@聴き比べてください。",
                AppLanguageSettings.string(rule.range), format(amount), direction, listeningPoint
            )
        )
    }

    private static func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: AppLanguageSettings.string(key), locale: AppLanguageSettings.locale, arguments: arguments)
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private static func formatSigned(_ value: Double) -> String {
        String(format: "%+.2f", value)
    }

}

private extension AudioQualityReportItem {
    static func info(_ title: String, _ detail: String) -> AudioQualityReportItem {
        AudioQualityReportItem(severity: .info, title: title, detail: detail)
    }

    static func warning(_ title: String, _ detail: String) -> AudioQualityReportItem {
        AudioQualityReportItem(severity: .warning, title: title, detail: detail)
    }

    static func caution(_ title: String, _ detail: String) -> AudioQualityReportItem {
        AudioQualityReportItem(severity: .caution, title: title, detail: detail)
    }
}
