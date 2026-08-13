import SwiftUI

@MainActor
struct StemModeCorrectionSettingsView: View {
    @Bindable var model: StemModeWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stem別の独立設定")
                .font(.callout.bold())

            Text("実行モデルの各Stemごとに補正プリセットと12項目を保持します。")
                .font(.callout)
                .foregroundStyle(.secondary)

            LiquidGlassSegmentedPicker(
                title: "設定するStem",
                options: model.availableStemRoles,
                selection: correctionRoleBinding,
                label: \.stemModeDisplayTitle,
                maxWidth: 448,
                isDisabled: false
            )
            .accessibilityHint("補正設定を表示・変更するStemを選びます")

            HStack(spacing: 6) {
                Text("補正プリセット")
                    .font(.headline)
                TermHelpButton(
                    title: "補正プリセット",
                    reading: "ほせいぷりせっと",
                    description: "ノイズをどれくらい減らすかの大まかな出発点です。弱い、標準、強いから選び、その後で細かい設定を手動調整できます。"
                )
            }

            LiquidGlassSegmentedPicker(
                title: "補正プリセット",
                options: DenoiseStrength.allCases,
                selection: correctionProfileBinding,
                label: \.title,
                isDisabled: model.isCorrectionSettingsDisabled
            )
            .accessibilityHint("選択中Stemの補正上限を決める出発点です")

            Text(model.selectedDenoiseStrength.summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            Label(
                "この設定は選択中Stemの処理量上限です。役割解析とguardにより不要な処理は行わず、設定値より強くしません。",
                systemImage: "waveform.badge.magnifyingglass"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)

            resetRow

            SettingsDisclosureCard(
                title: "基本",
                summary: "補正の強さ、原音の残し方、音の芯を守る量です。",
                help: SettingHelp(
                    title: "補正の基本",
                    reading: "ほせいのきほん",
                    description: "ノイズを減らす量と、元の音の自然さをどれだけ残すかを決める中心設定です。強くしすぎると音楽の細かい成分まで弱くなる場合があります。"
                ),
                initiallyExpanded: true
            ) {
                StemModeCorrectionControlList(
                    model: model,
                    layout: .basic
                )
            }

            SettingsDisclosureCard(
                title: "掃除と修復",
                summary: "低域の濁り、こもり、高域の戻し方を調整します。",
                help: SettingHelp(
                    title: "掃除と修復",
                    reading: "そうじとしゅうふく",
                    description: "低いノイズ、こもり、高域の不足を個別に調整します。ノイズを減らす設定と、失われた明るさを戻す設定を分けて扱います。"
                ),
                initiallyExpanded: false
            ) {
                StemModeCorrectionControlList(
                    model: model,
                    layout: .repair
                )
            }

            SettingsDisclosureCard(
                title: "上級",
                summary: "ノイズ検出、高域補完、ステレオ保護を細かく調整します。",
                help: SettingHelp(
                    title: "補正の上級設定",
                    reading: "ほせいのじょうきゅうせってい",
                    description: "検出の敏感さ、高域補完、ステレオの守り方を細かく調整します。通常はプリセット値を基準にしてください。"
                ),
                initiallyExpanded: false
            ) {
                StemModeCorrectionControlList(
                    model: model,
                    layout: .advanced
                )
            }
        }
    }

    private var correctionProfileBinding: Binding<DenoiseStrength> {
        Binding(
            get: { model.selectedDenoiseStrength },
            set: { profile in
                applyCorrectionProfile(profile)
            }
        )
    }

    private var correctionRoleBinding: Binding<StemRole> {
        Binding(
            get: { model.selectedCorrectionRole },
            set: { model.selectCorrectionRole($0) }
        )
    }

    private var resetRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                customStatus
                Spacer()
                resetButton
            }

            VStack(alignment: .leading, spacing: 8) {
                customStatus
                resetButton
            }
        }
    }

    private var customStatus: some View {
        Text(model.isUsingCustomCorrectionSettings ? "手動調整中です" : "既定値を使用しています")
            .font(.body)
            .foregroundStyle(
                model.isUsingCustomCorrectionSettings
                    ? VelouraTextColors.orange
                    : Color.secondary
            )
    }

    private var resetButton: some View {
        LiquidGlassActionButton(
            title: "プリセットへ戻す",
            isDisabled: !model.isUsingCustomCorrectionSettings
                || model.isCorrectionSettingsDisabled,
            action: resetCorrectionSettings
        )
        .accessibilityHint("選択中の補正プリセットの12設定へ戻します")
    }

    private func applyCorrectionProfile(_ profile: DenoiseStrength) {
        do {
            try model.applyCorrectionProfile(profile)
        } catch {
            presentSettingsError(error)
        }
    }

    private func resetCorrectionSettings() {
        do {
            try model.resetCorrectionSettingsToProfile()
        } catch {
            presentSettingsError(error)
        }
    }

    private func presentSettingsError(_ error: any Error) {
        model.presentControllerFailure(
            title: "Stem補正設定を変更できません",
            message: error.localizedDescription
        )
    }
}
