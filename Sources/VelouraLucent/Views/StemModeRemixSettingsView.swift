import SwiftUI

@MainActor
struct StemModeRemixSettingsView: View {
    @Bindable var model: StemModeWorkspaceModel

    var body: some View {
        let plan = model.automaticRemixPlan
        let effective = model.displayedRemixSettings

        VStack(alignment: .leading, spacing: 14) {
            remixAdjustmentModeHeader
            remixResetRow

            ForEach(model.availableStemRoles, id: \.self) { role in
                roleCard(
                    role: role,
                    plan: plan,
                    automatic: plan?.settings.settings(for: role)
                        ?? StemRemixRoleSettings(),
                    effective: effective.settings(for: role)
                )
            }

            maskingCard(plan: plan, effective: effective)
            reverbCard(effective: effective)
        }
    }

    private var remixAdjustmentModeHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("再ミックス調整")
                        .font(.title3.bold())
                    TermHelpButton(
                        title: "再ミックス調整",
                        reading: "さいみっくすちょうせい",
                        description: "全Stemの音量が0 dB、パンが0、Stem間の衝突回避が無効または0、全Stemの共通リバーブへの送信量と共通リバーブの戻り量が0の場合、再ミックス後は補正後とほぼ同じ音になります。同じ設定でマスタリングすれば、最終音もほぼ同じです。いずれかが中立値ではない場合、その調整分だけ音量バランス、左右位置、帯域の重なり、空間感が変化します。"
                    )
                }
                Text("自動値を使うか、全項目を手動調整するかを切り替えます。")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Toggle(
                "手動",
                isOn: mainActorBinding(
                    get: { model.isRemixManualEditingEnabled },
                    set: { isEnabled in
                        apply { try model.setRemixManualEditingEnabled(isEnabled) }
                    }
                )
            )
            .font(.title3)
            .toggleStyle(.switch)
            .tint(LiquidGlassSegmentedPickerStyle.switchTint)
            .disabled(model.isRemixSettingsDisabled)
        }
    }

    private var remixResetRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                remixResetStatus
                Spacer()
                remixResetButton
            }

            VStack(alignment: .leading, spacing: 8) {
                remixResetStatus
                remixResetButton
            }
        }
    }

    private var remixResetStatus: some View {
        Text(remixAdjustmentStatusText)
        .font(.title3)
        .foregroundStyle(
            model.isRemixManualEditingEnabled && !model.manualRemixOverrides.isEmpty
                ? VelouraTextColors.orange
                : Color.secondary
        )
    }

    private var remixAdjustmentStatusText: String {
        if model.automaticRemixPlan != nil {
            return model.isRemixManualEditingEnabled && !model.manualRemixOverrides.isEmpty
                ? "手動調整中です"
                : "自動値を使用しています"
        }
        if model.isRemixManualEditingEnabled {
            return model.manualRemixOverrides.isEmpty
                ? "中立値から手動調整できます。補正後は未変更項目に自動値を使用します。"
                : "補正前の手動値を保持しています。補正後は未変更項目に自動値を使用します。"
        }
        return "補正後に自動値を算出します。現在は中立値を表示しています。"
    }

    private var remixResetButton: some View {
        LiquidGlassActionButton(
            title: "自動値へ戻す",
            isDisabled: model.isRemixSettingsDisabled
                || !model.isRemixManualEditingEnabled
                || model.manualRemixOverrides.isEmpty
        ) {
            apply { try model.resetManualRemixOverrides() }
        }
    }

    private func roleCard(
        role: StemRole,
        plan: StemRemixAutomaticPlan?,
        automatic: StemRemixRoleSettings,
        effective: StemRemixRoleSettings
    ) -> some View {
        SettingsDisclosureCard(
            title: role.stemModeDisplayTitle,
            summary: "音量、左右位置、共通リバーブへの送信量を調整します。",
            help: SettingHelp(
                title: "\(role.stemModeDisplayTitle)の再ミックス",
                reading: "すてむのさいみっくす",
                description: "補正済みStemに対して音量、左右位置、共通リバーブへ送る量を調整します。補正処理そのものは変更しません。"
            ),
            initiallyExpanded: role == .vocals
        ) {
            if let plan {
                roleAutomaticEvidence(role: role, plan: plan, automatic: automatic)
            }

            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                remixKnob(
                    title: "音量",
                    help: SettingHelp(
                        title: "Stem音量",
                        reading: "すてむおんりょう",
                        description: "このStemを加算する前の音量です。ほかのStemとのバランスだけを調整し、ここではノーマライズやリミッターを行いません。"
                    ),
                    value: effective.gainDB,
                    valueText: { String(format: "%+.1f dB", $0) },
                    displayValueText: { String(format: "%.1f", $0) },
                    unitText: "dB",
                    labels: ["小さい", "基準", "大きい"],
                    range: -12...12,
                    step: 0.1,
                    setValue: { value in
                        apply { try model.setRemixGainDB(value, for: role) }
                    }
                )

                remixKnob(
                    title: "パン",
                    help: SettingHelp(
                        title: "Stemパン",
                        reading: "すてむぱん",
                        description: "このStemの左右位置です。中央から左または右へ動かし、ほかのStemとの定位を調整します。"
                    ),
                    value: effective.pan,
                    valueText: panText,
                    displayValueText: panNumberText,
                    unitText: "%",
                    labels: ["左", "中央", "右"],
                    range: -1...1,
                    step: 0.01,
                    setValue: { value in
                        apply { try model.setRemixPan(value, for: role) }
                    }
                )

                remixKnob(
                    title: "リバーブ送信",
                    help: SettingHelp(
                        title: "共通リバーブへ送る量",
                        reading: "きょうつうりばーぶへおくるりょう",
                        description: "このStemから共通リバーブへ送る量です。上げるほど共通空間の残響が増えますが、元の乾いた音はそのまま残ります。"
                    ),
                    value: effective.reverbSend,
                    valueText: percentText,
                    displayValueText: percentNumberText,
                    unitText: "%",
                    labels: ["なし", "標準", "多い"],
                    range: 0...0.6,
                    step: 0.01,
                    setValue: { value in
                        apply { try model.setRemixReverbSend(value, for: role) }
                    }
                )
            }
            .frame(width: DAWKnobMetrics.threeColumnWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func maskingCard(
        plan: StemRemixAutomaticPlan?,
        effective: StemRemixSettings
    ) -> some View {
        SettingsDisclosureCard(
            title: "Stem間の衝突回避",
            summary: "実際に同時発音して衝突した区間だけ、対象帯域を動的に避けます。",
            help: SettingHelp(
                title: "Stem間の衝突回避",
                reading: "すてむかんのしょうとつかいひ",
                description: "ドラムとベース、ボーカルと\(accompanimentTitle)が同じ帯域で同時に強く鳴る区間だけ、後者の対象帯域を一時的に下げます。曲全体へ固定EQはかけません。"
            ),
            initiallyExpanded: false
        ) {
            if let plan {
                evidenceText("ドラム／ベース衝突", value: plan.drumsBassCollision)
                automaticDecisionText(
                    plan.settings.masking.drumsToBassEnabled
                        ? "自動判断: 衝突区間だけベース側を回避"
                        : "自動判断: 回避を行う衝突量ではないため無効"
                )
            }
            collisionAvoidanceControl(
                title: "ドラムに対するベース回避",
                isEnabled: effective.masking.drumsToBassEnabled,
                setEnabled: { value in
                    apply { try model.setDrumsToBassMaskingEnabled(value) }
                }
            ) {
                remixKnob(
                    title: "ベース回避量",
                    help: SettingHelp(
                        title: "ベース回避量",
                        reading: "べーすかいひりょう",
                        description: "ドラムの低域と同時に衝突した区間だけ、ベース側の対象帯域を下げる量です。曲全体のベース音量は下げません。"
                    ),
                    value: effective.masking.drumsToBassAmount,
                    valueText: percentText,
                    displayValueText: percentNumberText,
                    unitText: "%",
                    labels: ["なし", "標準", "強い"],
                    range: 0...0.5,
                    step: 0.01,
                    setValue: { value in
                        apply { try model.setDrumsToBassMasking(value) }
                    }
                )
            }

            if let plan {
                evidenceText(
                    "ボーカル／\(accompanimentTitle)衝突",
                    value: plan.vocalsAccompanimentCollision
                )
                automaticDecisionText(
                    plan.settings.masking.vocalsToAccompanimentEnabled
                        ? "自動判断: 衝突区間だけ\(accompanimentTitle)側を回避"
                        : "自動判断: 回避を行う衝突量ではないため無効"
                )
            }
            collisionAvoidanceControl(
                title: "ボーカルに対する\(accompanimentTitle)回避",
                isEnabled: effective.masking.vocalsToAccompanimentEnabled,
                setEnabled: { value in
                    apply { try model.setVocalsToAccompanimentMaskingEnabled(value) }
                }
            ) {
                remixKnob(
                    title: "\(accompanimentTitle)回避量",
                    help: SettingHelp(
                        title: "\(accompanimentTitle)回避量",
                        reading: "ばんそうかいひりょう",
                        description: "ボーカルの存在帯域と同時に衝突した区間だけ、\(accompanimentTitle)側へ共通の時間制御を適用して対象帯域を下げます。曲全体の音量は下げません。"
                    ),
                    value: effective.masking.vocalsToAccompanimentAmount,
                    valueText: percentText,
                    displayValueText: percentNumberText,
                    unitText: "%",
                    labels: ["なし", "標準", "強い"],
                    range: 0...0.5,
                    step: 0.01,
                    setValue: { value in
                        apply { try model.setVocalsToAccompanimentMasking(value) }
                    }
                )
            }
        }
    }

    private func reverbCard(effective: StemRemixSettings) -> some View {
        SettingsDisclosureCard(
            title: "共通リバーブ",
            summary: "\(model.availableStemRoles.count)Stemで一つの空間を共有し、Stemごとに送る量だけを変えます。",
            help: SettingHelp(
                title: "共通リバーブ",
                reading: "きょうつうりばーぶ",
                description: "Stemごとに別々のリバーブを置かず、一つの残響へ各Stemを送ります。最終的な残響量と減衰時間をここで調整します。"
            ),
            initiallyExpanded: false
        ) {
            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                remixKnob(
                    title: "戻り量",
                    help: SettingHelp(
                        title: "共通リバーブの戻り量",
                        reading: "きょうつうりばーぶのもどりりょう",
                        description: "共通リバーブで作った残響を、乾いたStem合計へ戻す量です。上げるほど曲全体で共有する残響が増えます。"
                    ),
                    value: effective.reverbReturnLevel,
                    valueText: percentText,
                    displayValueText: percentNumberText,
                    unitText: "%",
                    labels: ["なし", "標準", "多い"],
                    range: 0...0.5,
                    step: 0.01,
                    setValue: { value in
                        apply { try model.setRemixReturnLevel(value) }
                    }
                )

                remixKnob(
                    title: "減衰時間",
                    help: SettingHelp(
                        title: "共通リバーブの減衰時間",
                        reading: "きょうつうりばーぶのげんすいじかん",
                        description: "共通リバーブの残響が消えるまでの長さです。短くすると空間が引き締まり、長くすると余韻が残ります。"
                    ),
                    value: effective.reverbDecaySeconds,
                    valueText: { String(format: "%.2f 秒", $0) },
                    displayValueText: { String(format: "%.2f", $0) },
                    unitText: "秒",
                    labels: ["短い", "標準", "長い"],
                    range: 0.25...4,
                    step: 0.01,
                    setValue: { value in
                        apply { try model.setRemixDecaySeconds(value) }
                    }
                )
            }
            .frame(width: DAWKnobMetrics.twoColumnWidth)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var accompanimentTitle: String {
        model.availableStemRoles.contains(.guitar)
            ? "伴奏（その他・ギター・ピアノ）"
            : "その他"
    }

    private func collisionAvoidanceControl<Content: View>(
        title: String,
        isEnabled: Bool,
        setEnabled: @escaping @MainActor (Bool) -> Void,
        @ViewBuilder amountControl: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.title3.bold())
                Spacer()
                Toggle(
                    "有効",
                    isOn: mainActorBinding(
                        get: { isEnabled },
                        set: setEnabled
                    )
                )
                .font(.title3)
                .toggleStyle(.switch)
                .tint(LiquidGlassSegmentedPickerStyle.switchTint)
                .controlSize(.small)
                .fixedSize()
                .disabled(
                    model.isRemixSettingsDisabled
                        || !model.isRemixManualEditingEnabled
                )
            }

            amountControl()
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func remixKnob(
        title: String,
        help: SettingHelp,
        value: Float,
        valueText: @escaping (Float) -> String,
        displayValueText: ((Float) -> String)? = nil,
        unitText: String? = nil,
        labels: [String],
        range: ClosedRange<Float>,
        step: Float,
        setValue: @escaping @MainActor (Float) -> Void
    ) -> some View {
        DAWKnobControl(
            title: title,
            help: help,
            valueText: valueText(value),
            displayValueText: displayValueText?(value),
            unitText: unitText,
            labels: labels,
            value: mainActorBinding(
                get: { value },
                set: setValue
            ),
            range: range,
            step: step,
            dragValueScale: range.upperBound - range.lowerBound,
            isInteractionEnabled: !model.isRemixSettingsDisabled
                && model.isRemixManualEditingEnabled
        )
    }

    private func evidenceText(_ title: String, value: Float) -> some View {
        Text("\(title): \(percentText(value))")
            .font(.body.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func roleAutomaticEvidence(
        role: StemRole,
        plan: StemRemixAutomaticPlan,
        automatic: StemRemixRoleSettings
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                String(
                    format: "gain根拠: rawとの差 %+.2f dB → 自動値 %+.1f dB",
                    plan.gainEvidenceDB[role, default: 0],
                    automatic.gainDB
                )
            )
            Text(
                "pan根拠: 左右差 \(panText(plan.panEvidence[role, default: 0])) → "
                    + (automatic.pan == 0
                        ? "自動配置変更の条件を満たさないため中央"
                        : "自動値 \(panText(automatic.pan))")
            )
            Text(
                "reverb根拠: raw空間成分の減少 \(percentText(plan.reverbLossEvidence[role, default: 0])) → Send \(percentText(automatic.reverbSend))"
            )
        }
        .font(.body.monospacedDigit())
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func automaticDecisionText(_ value: String) -> some View {
        Text(value)
            .font(.body)
            .foregroundStyle(.secondary)
    }

    private func panText(_ value: Float) -> String {
        if abs(value) < 0.005 { return "中央" }
        return value < 0
            ? String(format: "L %.0f%%", abs(value) * 100)
            : String(format: "R %.0f%%", value * 100)
    }

    private func panNumberText(_ value: Float) -> String {
        String(format: "%.0f", value * 100)
    }

    private func percentText(_ value: Float) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func percentNumberText(_ value: Float) -> String {
        String(format: "%.0f", value * 100)
    }

    private func apply(_ operation: () throws -> Void) {
        do {
            try operation()
        } catch {
            model.presentControllerFailure(
                title: "再ミックス設定を変更できません",
                message: error.localizedDescription
            )
        }
    }
}
