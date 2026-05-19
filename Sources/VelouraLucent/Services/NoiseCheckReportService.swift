import Foundation

enum NoiseCheckReportService {
    static func makeReport(
        input: NoiseMeasurementSnapshot?,
        corrected: NoiseMeasurementSnapshot?,
        mastered: NoiseMeasurementSnapshot?,
        correctionSettings: CorrectionSettings,
        settings: MasteringSettings
    ) -> NoiseCheckReport? {
        guard input != nil || corrected != nil || mastered != nil else { return nil }

        let definitions = noiseDefinitions(correctionSettings: correctionSettings, masteringSettings: settings)
        let rows = definitions.map { definition in
            let inputValue = input.flatMap { value(for: definition, snapshot: $0) }
            let correctedValue = corrected.flatMap { value(for: definition, snapshot: $0) }
            let masteredValue = mastered.flatMap { value(for: definition, snapshot: $0) }
            let correctionDelta = delta(from: inputValue, to: correctedValue)
            let masteringDelta = delta(from: correctedValue, to: masteredValue)
            let masteringWorsened = (masteringDelta ?? 0) >= definition.masteringWorseningCautionDB
            let severity = maxSeverity([
                currentSeverity(input: inputValue, corrected: correctedValue, mastered: masteredValue),
                masteringWorsened ? .caution : nil
            ])

            return NoiseCheckRow(
                id: definition.id,
                label: definition.label,
                measurementDescription: definition.measurementDescription,
                displayDescription: definition.displayDescription,
                unitLabel: definition.unitLabel,
                displayScale: definition.displayScale,
                input: inputValue,
                corrected: correctedValue,
                mastered: masteredValue,
                correctionDeltaDB: correctionDelta,
                masteringDeltaDB: masteringDelta,
                severity: severity,
                summaryText: summaryText(
                    input: inputValue,
                    corrected: correctedValue,
                    mastered: masteredValue,
                    correctionDelta: correctionDelta,
                    masteringDelta: masteringDelta,
                    warningDelta: definition.masteringWorseningCautionDB
                ),
                correctionEffectText: correctionEffectText(correctionDelta),
                masteringEffectText: masteringEffectText(masteringDelta, warningDelta: definition.masteringWorseningCautionDB),
                recommendedActions: recommendedActions(
                    for: definition,
                    input: inputValue,
                    corrected: correctedValue,
                    mastered: masteredValue,
                    correctionDelta: correctionDelta,
                    masteringDelta: masteringDelta
                )
            )
        }

        return NoiseCheckReport(rows: rows, recommendedActions: mergedActions(from: rows))
    }

    private static func value(for definition: NoiseDefinition, snapshot: NoiseMeasurementSnapshot) -> NoiseCheckValue? {
        guard let measurement = snapshot.value(for: definition.id) else { return nil }
        return NoiseCheckValue(
            levelDB: measurement.measuredLevelDB,
            measuredLevelDB: measurement.measuredLevelDB,
            unitLabel: measurement.unitLabel,
            lowerIsBetter: measurement.lowerIsBetter,
            severity: severity(levelDB: measurement.measuredLevelDB, caution: definition.cautionDB, warning: definition.warningDB)
        )
    }

    private static func delta(from reference: NoiseCheckValue?, to target: NoiseCheckValue?) -> Double? {
        guard let reference, let target else { return nil }
        return target.levelDB - reference.levelDB
    }

    private static func severity(levelDB: Double, caution: Double, warning: Double) -> NoiseCheckSeverity {
        if levelDB >= warning {
            return .warning
        }
        if levelDB >= caution {
            return .caution
        }
        return .low
    }

    private static func maxSeverity(_ values: [NoiseCheckSeverity?]) -> NoiseCheckSeverity {
        let compact = values.compactMap { $0 }
        if compact.contains(.warning) {
            return .warning
        }
        if compact.contains(.caution) {
            return .caution
        }
        return .low
    }

    private static func currentSeverity(
        input: NoiseCheckValue?,
        corrected: NoiseCheckValue?,
        mastered: NoiseCheckValue?
    ) -> NoiseCheckSeverity {
        mastered?.severity ?? corrected?.severity ?? input?.severity ?? .low
    }

    private static func correctionEffectText(_ delta: Double?) -> String {
        guard let delta else { return "補正: 未実行" }
        if delta <= -3.0 {
            return "\(formatDelta(delta)) 大きく改善"
        }
        if delta <= -1.0 {
            return "\(formatDelta(delta)) 改善"
        }
        if delta < 1.0 {
            return "\(formatDelta(delta)) ほぼ維持"
        }
        return "\(formatDelta(delta)) 増加"
    }

    private static func masteringEffectText(_ delta: Double?, warningDelta: Double) -> String {
        guard let delta else { return "仕上げ: 未実行" }
        if delta <= -1.0 {
            return "\(formatDelta(delta)) さらに改善"
        }
        if delta < 0.5 {
            return "\(formatDelta(delta)) 維持"
        }
        if delta < warningDelta {
            return "\(formatDelta(delta)) 少し戻り"
        }
        return "\(formatDelta(delta)) 戻りあり"
    }

    private static func summaryText(
        input: NoiseCheckValue?,
        corrected: NoiseCheckValue?,
        mastered: NoiseCheckValue?,
        correctionDelta: Double?,
        masteringDelta: Double?,
        warningDelta: Double
    ) -> String {
        let current = mastered ?? corrected ?? input
        guard let current else { return "未測定" }

        if let input, current.levelDB >= input.levelDB + 1.0 {
            return "原音より悪化"
        }
        if let input, current.levelDB <= input.levelDB - 6.0 {
            if let masteringDelta, masteringDelta >= warningDelta {
                return "原音より大幅に低い / 戻りあり"
            }
            if let masteringDelta, masteringDelta >= 0.5 {
                return "原音より大幅に低い / 少し戻りあり"
            }
            return "原音より大幅に低い"
        }
        if let input, current.levelDB <= input.levelDB - 1.0 {
            if let masteringDelta, masteringDelta >= warningDelta {
                return "原音より低い / 戻りあり"
            }
            if let masteringDelta, masteringDelta >= 0.5 {
                return "原音より低い / 少し戻りあり"
            }
            return "原音より低い"
        }
        if let correctionDelta, abs(correctionDelta) < 1.0, masteringDelta.map({ abs($0) < 1.0 }) != false {
            return "悪化なし"
        }
        if current.severity == .low {
            return "目立つ問題なし"
        }
        return noiseCheckSeveritySummary(current.severity)
    }

    private static func noiseCheckSeveritySummary(_ severity: NoiseCheckSeverity) -> String {
        switch severity {
        case .low: return "目立つ問題なし"
        case .caution: return "少し目立つ"
        case .warning: return "目立つ"
        }
    }

    private static func recommendedActions(
        for definition: NoiseDefinition,
        input: NoiseCheckValue?,
        corrected: NoiseCheckValue?,
        mastered: NoiseCheckValue?,
        correctionDelta: Double?,
        masteringDelta: Double?
    ) -> [NoiseCheckAction] {
        let correctionWeak = corrected.map { $0.severity != .low } == true && (correctionDelta ?? 0) > -1.0
        let correctionWorse = (correctionDelta ?? 0) >= 1.0
        let masteringReturned = (masteringDelta ?? 0) >= definition.masteringWorseningCautionDB
        let masteringStillHigh = mastered.map { $0.severity != .low } == true && (masteringDelta ?? 0) >= 0.5
        let inputWasHigh = input.map { $0.severity != .low } == true

        var actions: [NoiseCheckAction] = []
        if masteringReturned || masteringStillHigh {
            appendIfUseful(definition.masteringAction(masteringDelta, mastered), to: &actions)
        }
        if actions.count < 2 && (correctionWorse || correctionWeak || (corrected == nil && inputWasHigh)) {
            appendIfUseful(definition.correctionAction(correctionDelta, corrected ?? input), to: &actions)
        }
        return Array(actions.prefix(2))
    }

    private static func appendIfUseful(_ action: NoiseCheckAction, to actions: inout [NoiseCheckAction]) {
        guard action.currentValue != action.recommendedValue else { return }
        actions.append(action)
    }

    private static func mergedActions(from rows: [NoiseCheckRow]) -> [NoiseCheckAction] {
        var actionsByID: [String: NoiseCheckAction] = [:]
        var scoresByID: [String: Double] = [:]

        for row in rows {
            let rowScore = max(row.masteringDeltaDB ?? 0, row.correctionDeltaDB ?? 0, 0)
                + severityScore(row.severity)
            for action in row.recommendedActions {
                let existingScore = scoresByID[action.id] ?? -Double.infinity
                if rowScore > existingScore {
                    actionsByID[action.id] = action
                    scoresByID[action.id] = rowScore
                }
            }
        }

        return actionsByID.values.sorted {
            (scoresByID[$0.id] ?? 0) > (scoresByID[$1.id] ?? 0)
        }
        .prefix(3)
        .map { $0 }
    }

    private static func severityScore(_ severity: NoiseCheckSeverity) -> Double {
        switch severity {
        case .low: return 0
        case .caution: return 1
        case .warning: return 2
        }
    }

    private static func noiseDefinitions(correctionSettings: CorrectionSettings, masteringSettings: MasteringSettings) -> [NoiseDefinition] {
        [
            NoiseDefinition(
                id: "hiss",
                label: "ヒス・シュワシュワ",
                unitLabel: "dBFS",
                measurementDescription: "静かな区間の8kHz以上の床",
                displayDescription: "下がるほどノイズが少ない",
                displayScale: NoiseCheckDisplayScale(minimum: -120, maximum: -55),
                cautionDB: limit(for: NoiseMeasurementID.hiss).cautionDB,
                warningDB: limit(for: NoiseMeasurementID.hiss).warningDB,
                masteringWorseningCautionDB: limit(for: NoiseMeasurementID.hiss).masteringWorseningCautionDB,
                correctionAction: correctionAction(
                    id: "hiss-correction",
                    title: "補正: 高域の自然さ / ノイズ検出しきい値",
                    current: correctionSettings.noiseDetectionSensitivity,
                    maximum: 1.0,
                    sensitivity: 6.0,
                    fallbackDB: 1.0,
                    reasonPrefix: "補正後のヒスが残っています",
                    expectedEffect: "補正段階でヒスを抑えます",
                    caution: "上げすぎるとシンバルの伸びが丸くなります"
                ),
                masteringAction: masteringAction(
                    id: "hiss-mastering",
                    title: "マスタリング: エアー帯域",
                    current: masteringSettings.highShelfGain,
                    minimum: -0.20,
                    sensitivity: 10.0,
                    fallbackDB: 0.8,
                    reasonPrefix: "マスタリング後にヒスが戻っています",
                    expectedEffect: "ヒスの戻りを必要な分だけ抑えます",
                    caution: "下げすぎると空気感も弱くなります"
                )
            ),
            NoiseDefinition(
                id: "sibilance",
                label: "サ行・歯擦音",
                unitLabel: "dB",
                measurementDescription: "5〜9kHzの短時間突出",
                displayDescription: "増えると刺さりやすい。下げすぎると声が丸くなる",
                displayScale: NoiseCheckDisplayScale(minimum: 0, maximum: 14),
                cautionDB: limit(for: NoiseMeasurementID.sibilance).cautionDB,
                warningDB: limit(for: NoiseMeasurementID.sibilance).warningDB,
                masteringWorseningCautionDB: limit(for: NoiseMeasurementID.sibilance).masteringWorseningCautionDB,
                correctionAction: correctionAction(
                    id: "sibilance-correction",
                    title: "補正: 高域の自然さ / エアー補完",
                    current: correctionSettings.highNaturalness,
                    maximum: 1.0,
                    sensitivity: 7.0,
                    fallbackDB: 1.0,
                    reasonPrefix: "補正後のサ行が残っています",
                    expectedEffect: "サ行の刺さりを抑えます",
                    caution: "声の息感まで丸くなる場合があります"
                ),
                masteringAction: correctionAction(
                    id: "sibilance-mastering",
                    title: "マスタリング: ハーシュネス抑制",
                    current: masteringSettings.deEsserAmount,
                    maximum: 1.0,
                    sensitivity: 8.0,
                    fallbackDB: 0.8,
                    reasonPrefix: "マスタリング後にサ行が戻っています",
                    expectedEffect: "サ行と刺さりを抑えます",
                    caution: "上げすぎるとボーカルの明るさが下がります",
                    stage: .mastering
                )
            ),
            NoiseDefinition(
                id: "shimmer",
                label: "高域のチラつき",
                unitLabel: "dBFS",
                measurementDescription: "静かな区間の10〜16kHz床",
                displayDescription: "下がるほど高域ノイズが少ない",
                displayScale: NoiseCheckDisplayScale(minimum: -120, maximum: -55),
                cautionDB: limit(for: NoiseMeasurementID.shimmer).cautionDB,
                warningDB: limit(for: NoiseMeasurementID.shimmer).warningDB,
                masteringWorseningCautionDB: limit(for: NoiseMeasurementID.shimmer).masteringWorseningCautionDB,
                correctionAction: correctionAction(
                    id: "shimmer-correction",
                    title: "補正: 高域の自然さ / エアー補完",
                    current: correctionSettings.highNaturalness,
                    maximum: 1.0,
                    sensitivity: 7.0,
                    fallbackDB: 1.0,
                    reasonPrefix: "補正後の高域チラつきが残っています",
                    expectedEffect: "高域のザラつきを抑えます",
                    caution: "上げすぎると煌びやかさが丸くなります"
                ),
                masteringAction: masteringAction(
                    id: "shimmer-mastering",
                    title: "マスタリング: エアー帯域 / ハーシュネス抑制",
                    current: masteringSettings.highShelfGain,
                    minimum: -0.20,
                    sensitivity: 10.0,
                    fallbackDB: 0.7,
                    reasonPrefix: "マスタリング後に高域チラつきが戻っています",
                    expectedEffect: "高域ノイズの戻りを抑えます",
                    caution: "空気感と煌びやかさも少し下がります"
                )
            ),
            NoiseDefinition(
                id: "mud",
                label: "こもり・低いザラつき",
                unitLabel: "dB",
                measurementDescription: "300Hz〜1kHzの全体比",
                displayDescription: "上がるとこもりやすい",
                displayScale: NoiseCheckDisplayScale(minimum: -25, maximum: -5),
                cautionDB: limit(for: NoiseMeasurementID.mud).cautionDB,
                warningDB: limit(for: NoiseMeasurementID.mud).warningDB,
                masteringWorseningCautionDB: limit(for: NoiseMeasurementID.mud).masteringWorseningCautionDB,
                correctionAction: correctionAction(
                    id: "mud-correction",
                    title: "補正: 中低域整理",
                    current: correctionSettings.lowMidCleanup,
                    maximum: 1.0,
                    sensitivity: 6.0,
                    fallbackDB: 1.0,
                    reasonPrefix: "補正後のこもりが残っています",
                    expectedEffect: "こもりと低いザラつきを抑えます",
                    caution: "上げすぎると音の厚みが薄くなります"
                ),
                masteringAction: masteringAction(
                    id: "mud-mastering",
                    title: "マスタリング: 中低域",
                    current: masteringSettings.lowMidGain,
                    minimum: -0.80,
                    sensitivity: 8.0,
                    fallbackDB: 0.8,
                    reasonPrefix: "マスタリング後にこもりが戻っています",
                    expectedEffect: "中低域の戻りを抑えます",
                    caution: "下げすぎると音の温かさが減ります"
                )
            ),
            NoiseDefinition(
                id: "hum",
                label: "ハム・電源ノイズ",
                unitLabel: "dB",
                measurementDescription: "50/60Hzと倍音の周辺比",
                displayDescription: "下がるほど電源ノイズが少ない",
                displayScale: NoiseCheckDisplayScale(minimum: 0, maximum: 12),
                cautionDB: limit(for: NoiseMeasurementID.hum).cautionDB,
                warningDB: limit(for: NoiseMeasurementID.hum).warningDB,
                masteringWorseningCautionDB: limit(for: NoiseMeasurementID.hum).masteringWorseningCautionDB,
                correctionAction: correctionAction(
                    id: "hum-correction",
                    title: "補正: ノイズ検出しきい値 / 低域整理",
                    current: correctionSettings.noiseDetectionSensitivity,
                    maximum: 1.0,
                    sensitivity: 6.0,
                    fallbackDB: 1.0,
                    reasonPrefix: "補正後のハムが残っています",
                    expectedEffect: "電源ノイズの検出を強めます",
                    caution: "上げすぎると弱い余韻まで削る場合があります"
                ),
                masteringAction: masteringAction(
                    id: "hum-mastering",
                    title: "マスタリング: 低域",
                    current: masteringSettings.lowShelfGain,
                    minimum: 0,
                    sensitivity: 8.0,
                    fallbackDB: 0.8,
                    reasonPrefix: "マスタリング後にハムが戻っています",
                    expectedEffect: "低域ノイズの戻りを抑えます",
                    caution: "下げすぎると低音の支えが弱くなります"
                )
            ),
            NoiseDefinition(
                id: "rumble",
                label: "低域ゴロゴロ",
                unitLabel: "dBFS",
                measurementDescription: "静かな区間の20〜150Hz床",
                displayDescription: "下がるほど低域ノイズが少ない",
                displayScale: NoiseCheckDisplayScale(minimum: -90, maximum: -40),
                cautionDB: limit(for: NoiseMeasurementID.rumble).cautionDB,
                warningDB: limit(for: NoiseMeasurementID.rumble).warningDB,
                masteringWorseningCautionDB: limit(for: NoiseMeasurementID.rumble).masteringWorseningCautionDB,
                correctionAction: correctionAction(
                    id: "rumble-correction",
                    title: "補正: 低域整理",
                    current: correctionSettings.lowCleanup,
                    maximum: 1.0,
                    sensitivity: 6.0,
                    fallbackDB: 1.0,
                    reasonPrefix: "補正後の低域ゴロゴロが残っています",
                    expectedEffect: "不要な低域ノイズを抑えます",
                    caution: "上げすぎると低音の量感も減ります"
                ),
                masteringAction: masteringAction(
                    id: "rumble-mastering",
                    title: "マスタリング: 低域",
                    current: masteringSettings.lowShelfGain,
                    minimum: 0,
                    sensitivity: 8.0,
                    fallbackDB: 0.8,
                    reasonPrefix: "マスタリング後に低域ゴロゴロが戻っています",
                    expectedEffect: "低域ノイズの戻りを抑えます",
                    caution: "下げすぎると低音の支えが弱くなります"
                )
            ),
            NoiseDefinition(
                id: "room",
                label: "環境音・部屋鳴り",
                unitLabel: "dBFS",
                measurementDescription: "静かな区間の100Hz〜8kHz床",
                displayDescription: "下がるほど環境音が少ない",
                displayScale: NoiseCheckDisplayScale(minimum: -60, maximum: -25),
                cautionDB: limit(for: NoiseMeasurementID.room).cautionDB,
                warningDB: limit(for: NoiseMeasurementID.room).warningDB,
                masteringWorseningCautionDB: limit(for: NoiseMeasurementID.room).masteringWorseningCautionDB,
                correctionAction: correctionAction(
                    id: "room-correction",
                    title: "補正: 補正の強さ / 原音保持",
                    current: correctionSettings.correctionIntensity,
                    maximum: 1.0,
                    sensitivity: 5.0,
                    fallbackDB: 1.0,
                    reasonPrefix: "補正後の環境音が残っています",
                    expectedEffect: "環境音と部屋鳴りを抑えます",
                    caution: "上げすぎると原音の自然さが下がります"
                ),
                masteringAction: correctionAction(
                    id: "room-mastering",
                    title: "マスタリング: ダイナミクス保持",
                    current: masteringSettings.dynamicsRetention,
                    maximum: 1.0,
                    sensitivity: 5.0,
                    fallbackDB: 0.8,
                    reasonPrefix: "マスタリング後に環境音が戻っています",
                    expectedEffect: "環境音の持ち上がりを抑えます",
                    caution: "上げすぎると迫力の変化が小さくなります",
                    stage: .mastering
                )
            )
        ]
    }

    private static func correctionAction(
        id: String,
        title: String,
        current: Float,
        maximum: Float,
        sensitivity: Double,
        fallbackDB: Double,
        reasonPrefix: String,
        expectedEffect: String,
        caution: String,
        stage: NoiseCheckAction.Stage = .correction
    ) -> (Double?, NoiseCheckValue?) -> NoiseCheckAction {
        { delta, value in
            let targetReduction = targetReductionDB(delta: delta, value: value, fallbackDB: fallbackDB)
            let change = min(maximum - current, Float(targetReduction / sensitivity))
            let recommended = min(maximum, current + max(0, change))
            return NoiseCheckAction(
                id: id,
                stage: stage,
                title: title,
                currentValue: formatPercent(current),
                recommendedValue: formatPercent(recommended),
                changeValue: formatPercentChange(recommended - current),
                reason: "\(reasonPrefix)（根拠: \(formatDelta(delta ?? targetReduction))）",
                expectedEffect: "\(expectedEffect)（目安: \(formatReduction(targetReduction * 0.65))）",
                caution: caution
            )
        }
    }

    private static func masteringAction(
        id: String,
        title: String,
        current: Float,
        minimum: Float,
        sensitivity: Double,
        fallbackDB: Double,
        reasonPrefix: String,
        expectedEffect: String,
        caution: String
    ) -> (Double?, NoiseCheckValue?) -> NoiseCheckAction {
        { delta, value in
            let targetReduction = targetReductionDB(delta: delta, value: value, fallbackDB: fallbackDB)
            let change = min(current - minimum, Float(targetReduction / sensitivity))
            let recommended = max(minimum, current - max(0, change))
            return NoiseCheckAction(
                id: id,
                stage: .mastering,
                title: title,
                currentValue: format(current),
                recommendedValue: format(recommended),
                changeValue: formatSigned(recommended - current),
                reason: "\(reasonPrefix)（根拠: \(formatDelta(delta ?? targetReduction))）",
                expectedEffect: "\(expectedEffect)（目安: \(formatReduction(targetReduction * 0.65))）",
                caution: caution
            )
        }
    }

    private static func targetReductionDB(delta: Double?, value: NoiseCheckValue?, fallbackDB: Double) -> Double {
        let returned = max(delta ?? 0, 0)
        let severityExcess: Double
        switch value?.severity ?? .low {
        case .low:
            severityExcess = 0
        case .caution:
            severityExcess = 0.8
        case .warning:
            severityExcess = 1.4
        }
        return max(fallbackDB, returned + severityExcess)
    }

    private static func limit(for id: String) -> NoiseSeverityLimit {
        InternalAudioJudgementPolicy.severityLimit(for: id) ?? NoiseSeverityLimit(
            id: id,
            cautionDB: 0,
            warningDB: 0,
            masteringWorseningCautionDB: 2.0
        )
    }

    private static func format(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private static func formatSigned(_ value: Float) -> String {
        String(format: value >= 0 ? "+%.2f" : "%.2f", value)
    }

    private static func formatPercent(_ value: Float) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private static func formatPercentChange(_ value: Float) -> String {
        String(format: value >= 0 ? "+%.0f%%" : "%.0f%%", value * 100)
    }

    private static func formatDelta(_ value: Double) -> String {
        String(format: value >= 0 ? "+%.1f dB" : "%.1f dB", value)
    }

    private static func formatReduction(_ value: Double) -> String {
        String(format: "%.1f dB低下", max(0, value))
    }
}

private struct NoiseDefinition {
    let id: String
    let label: String
    let unitLabel: String
    let measurementDescription: String
    let displayDescription: String
    let displayScale: NoiseCheckDisplayScale
    let cautionDB: Double
    let warningDB: Double
    let masteringWorseningCautionDB: Double
    let correctionAction: (Double?, NoiseCheckValue?) -> NoiseCheckAction
    let masteringAction: (Double?, NoiseCheckValue?) -> NoiseCheckAction
}
