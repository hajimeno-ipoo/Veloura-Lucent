import SwiftUI

struct CorrectionSettingsPanel: View {
    @Bindable var job: ProcessingJob

    private let advancedSettingColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("補正")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ノイズ除去の強さ")
                        .font(.subheadline.weight(.semibold))
                    Picker("ノイズ除去の強さ", selection: correctionProfileBinding) {
                        ForEach(DenoiseStrength.allCases) { strength in
                            Text(strength.title).tag(strength)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(job.isProcessing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("説明")
                        .font(.subheadline.weight(.semibold))
                    Text(job.selectedDenoiseStrength.summary)
                        .foregroundStyle(.secondary)
                    Text(job.isUsingCustomCorrectionSettings ? "詳細設定を調整中です" : "プリセットの既定値を使用しています")
                        .font(.caption)
                        .foregroundStyle(job.isUsingCustomCorrectionSettings ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            advancedCorrectionSettings
        }
    }

    private var advancedCorrectionSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("プリセットを基準に、補正の効き方を細かく調整します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("プリセットへ戻す") {
                    job.resetCorrectionSettingsToProfile()
                }
                .disabled(!job.isUsingCustomCorrectionSettings)
            }

            settingsSection(title: "基本", summary: "補正の強さ、原音の残し方、音の芯の守り方を調整します。") {
                LazyVGrid(columns: advancedSettingColumns, spacing: 12) {
                    correctionIntensityControl
                    originalRetentionControl
                    coreProtectionControl
                }
            }

            settingsSection(title: "掃除と修復", summary: "低域の濁り、低中域の残り、最低限の高域修復と自然さを整えます。") {
                LazyVGrid(columns: advancedSettingColumns, spacing: 12) {
                    lowCleanupControl
                    lowMidCleanupControl
                    presenceRepairControl
                    airRepairControl
                    highNaturalnessControl
                }
            }

            settingsSection(title: "上級", summary: "ノイズ検出、高域補完、foldover補完、ステレオ保護を細かく調整します。") {
                LazyVGrid(columns: advancedSettingColumns, spacing: 12) {
                    noiseDetectionControl
                    harmonicRepairControl
                    foldoverRepairControl
                    stereoProtectionControl
                }
            }
        }
    }

    private var correctionIntensityControl: some View {
        sliderCard(
            item: correctionTermDefinitions[0],
            valueText: String(format: "%.0f%%", job.editableCorrectionSettings.correctionIntensity * 100),
            scaleLabels: ["弱い", "標準", "強い"],
            quickActions: [
                CorrectionSliderQuickAction(title: "弱い", action: { set(\.correctionIntensity, 0.32, range: 0 ... 1) }),
                CorrectionSliderQuickAction(title: "標準", action: { set(\.correctionIntensity, 0.50, range: 0 ... 1) }),
                CorrectionSliderQuickAction(title: "強い", action: { set(\.correctionIntensity, 0.72, range: 0 ... 1) })
            ],
            stepperActions: stepper(for: \.correctionIntensity, delta: 0.01, range: 0 ... 1)
        ) {
            Slider(value: settingBinding(\.correctionIntensity, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var originalRetentionControl: some View {
        sliderCard(
            item: correctionTermDefinitions[1],
            valueText: String(format: "%.0f%%", job.editableCorrectionSettings.originalRetention * 100),
            scaleLabels: ["整える", "標準", "残す"],
            stepperActions: stepper(for: \.originalRetention, delta: 0.01, range: 0 ... 1)
        ) {
            Slider(value: settingBinding(\.originalRetention, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var coreProtectionControl: some View {
        sliderCard(
            item: correctionTermDefinitions[10],
            valueText: String(format: "%.0f%%", job.editableCorrectionSettings.coreProtection * 100),
            scaleLabels: ["整理", "標準", "芯を守る"],
            stepperActions: stepper(for: \.coreProtection, delta: 0.01, range: 0 ... 1)
        ) {
            Slider(value: settingBinding(\.coreProtection, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var lowCleanupControl: some View {
        sliderCard(item: correctionTermDefinitions[2], valueText: valueText(\.lowCleanup), scaleLabels: ["弱い", "標準", "強い"], stepperActions: stepper(for: \.lowCleanup, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.lowCleanup, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var lowMidCleanupControl: some View {
        sliderCard(item: correctionTermDefinitions[3], valueText: valueText(\.lowMidCleanup), scaleLabels: ["弱い", "標準", "強い"], stepperActions: stepper(for: \.lowMidCleanup, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.lowMidCleanup, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var presenceRepairControl: some View {
        sliderCard(item: correctionTermDefinitions[4], valueText: valueText(\.presenceRepair), scaleLabels: ["控えめ", "標準", "修復"], stepperActions: stepper(for: \.presenceRepair, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.presenceRepair, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var airRepairControl: some View {
        sliderCard(item: correctionTermDefinitions[5], valueText: valueText(\.airRepair), scaleLabels: ["控えめ", "標準", "修復"], stepperActions: stepper(for: \.airRepair, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.airRepair, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var highNaturalnessControl: some View {
        sliderCard(item: correctionTermDefinitions[6], valueText: valueText(\.highNaturalness), scaleLabels: ["明るさ", "標準", "自然"], stepperActions: stepper(for: \.highNaturalness, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.highNaturalness, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var noiseDetectionControl: some View {
        sliderCard(item: correctionTermDefinitions[7], valueText: valueText(\.noiseDetectionSensitivity), scaleLabels: ["鈍い", "標準", "敏感"], stepperActions: stepper(for: \.noiseDetectionSensitivity, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.noiseDetectionSensitivity, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var harmonicRepairControl: some View {
        sliderCard(item: correctionTermDefinitions[8], valueText: valueText(\.harmonicRepairAmount), scaleLabels: ["少ない", "標準", "多い"], stepperActions: stepper(for: \.harmonicRepairAmount, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.harmonicRepairAmount, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var foldoverRepairControl: some View {
        sliderCard(item: correctionTermDefinitions[9], valueText: valueText(\.foldoverRepairAmount), scaleLabels: ["少ない", "標準", "多い"], stepperActions: stepper(for: \.foldoverRepairAmount, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.foldoverRepairAmount, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var stereoProtectionControl: some View {
        sliderCard(item: correctionTermDefinitions[11], valueText: valueText(\.stereoProtection), scaleLabels: ["整理", "標準", "保護"], stepperActions: stepper(for: \.stereoProtection, delta: 0.01, range: 0 ... 1)) {
            Slider(value: settingBinding(\.stereoProtection, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var correctionProfileBinding: Binding<DenoiseStrength> {
        Binding(
            get: { job.selectedDenoiseStrength },
            set: { job.applyCorrectionProfile($0) }
        )
    }

    private func valueText(_ keyPath: KeyPath<CorrectionSettings, Float>) -> String {
        String(format: "%.0f%%", job.editableCorrectionSettings[keyPath: keyPath] * 100)
    }

    private func settingsSection<Content: View>(title: String, summary: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            content()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sliderCard<Content: View>(
        item: CorrectionSettingTerm,
        valueText: String,
        scaleLabels: [String],
        quickActions: [CorrectionSliderQuickAction] = [],
        stepperActions: (decrement: () -> Void, increment: () -> Void)?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                termLabel(item: item)
                Spacer()
                stepperButtons(title: item.label, actions: stepperActions)
                Text(valueText)
                    .font(.title3.monospacedDigit().weight(.bold))
            }

            if !quickActions.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(quickActions.enumerated()), id: \.offset) { _, action in
                        Button(action.title) {
                            action.action()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                }
            }

            content()
            scaleLabelsView(scaleLabels)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func termLabel(item: CorrectionSettingTerm) -> some View {
        HStack(spacing: 6) {
            Text(item.label)
                .font(.title3.weight(.semibold))
            CorrectionTermHelpButton(title: item.label, reading: item.reading, description: item.description)
        }
    }

    @ViewBuilder
    private func stepperButtons(title: String, actions: (decrement: () -> Void, increment: () -> Void)?) -> some View {
        if let actions {
            HStack(spacing: 4) {
                Button("\(title)を下げる", systemImage: "minus") {
                    actions.decrement()
                }
                .labelStyle(.iconOnly)
                Button("\(title)を上げる", systemImage: "plus") {
                    actions.increment()
                }
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    private func scaleLabelsView(_ labels: [String]) -> some View {
        HStack {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: alignment(forScaleLabel: label, in: labels))
            }
        }
    }

    private func settingBinding(_ keyPath: WritableKeyPath<CorrectionSettings, Float>, range: ClosedRange<Float>) -> Binding<Float> {
        Binding(
            get: { job.editableCorrectionSettings[keyPath: keyPath] },
            set: { set(keyPath, $0, range: range) }
        )
    }

    private func stepper(for keyPath: WritableKeyPath<CorrectionSettings, Float>, delta: Float, range: ClosedRange<Float>) -> (decrement: () -> Void, increment: () -> Void) {
        (
            decrement: { set(keyPath, job.editableCorrectionSettings[keyPath: keyPath] - delta, range: range) },
            increment: { set(keyPath, job.editableCorrectionSettings[keyPath: keyPath] + delta, range: range) }
        )
    }

    private func set(_ keyPath: WritableKeyPath<CorrectionSettings, Float>, _ value: Float, range: ClosedRange<Float>) {
        job.updateCorrectionSettings { settings in
            settings[keyPath: keyPath] = value.clamped(to: range)
        }
    }

    private func alignment(forScaleLabel label: String, in labels: [String]) -> Alignment {
        guard let index = labels.firstIndex(of: label), labels.count > 1 else {
            return .center
        }
        if index == 0 {
            return .leading
        }
        if index == labels.count - 1 {
            return .trailing
        }
        return .center
    }

    private var correctionTermDefinitions: [CorrectionSettingTerm] {
        [
            CorrectionSettingTerm(id: "intensity", label: "補正の強さ", reading: "ほせいのつよさ", description: "補正処理全体の効き方です。上げるほどノイズ低減や整理が強くなります。"),
            CorrectionSettingTerm(id: "retention", label: "原音保持", reading: "げんおんほじ", description: "元の音の芯や自然さをどれだけ残すかです。高くすると細くなりにくくなります。"),
            CorrectionSettingTerm(id: "low", label: "低域整理", reading: "ていいきせいり", description: "20Hz〜150Hz付近のゴロゴロ感を整えます。"),
            CorrectionSettingTerm(id: "lowMid", label: "中低域整理", reading: "ちゅうていいきせいり", description: "200Hz〜1kHz付近のこもりや濁りを整えます。"),
            CorrectionSettingTerm(id: "presence", label: "プレゼンス修復", reading: "ぷれぜんすしゅうふく", description: "欠けた中高域を最低限だけ戻します。前に出す演出はマスタリング側で行います。"),
            CorrectionSettingTerm(id: "air", label: "エアー修復", reading: "えあーしゅうふく", description: "欠けた高域を最低限だけ戻します。空気感を足す演出はマスタリング側で行います。"),
            CorrectionSettingTerm(id: "naturalness", label: "高域の自然さ", reading: "こういきのしぜんさ", description: "シュワシュワ感や人工的な高域を抑え、声やシンバルの自然さを残します。"),
            CorrectionSettingTerm(id: "noiseDetection", label: "ノイズ検出しきい値", reading: "のいずけんしゅつしきいち", description: "ノイズとして拾う範囲です。高くすると細かいノイズにも反応しやすくなります。"),
            CorrectionSettingTerm(id: "harmonic", label: "高域補完量", reading: "こういきほかんりょう", description: "失われた高域を補う量です。"),
            CorrectionSettingTerm(id: "foldover", label: "foldover補完量", reading: "ふぉーるどおーばーほかんりょう", description: "既存の倍音から高域側へ補う量です。多すぎると人工感が出やすくなります。"),
            CorrectionSettingTerm(id: "core", label: "芯保護", reading: "しんほご", description: "ノイズ除去で音の中心が細くならないように守る量です。"),
            CorrectionSettingTerm(id: "stereo", label: "ステレオ保護", reading: "すてれおほご", description: "左右の広がりを急に崩さないための保護量です。")
        ]
    }
}

private struct CorrectionSettingTerm: Identifiable {
    let id: String
    let label: String
    let reading: String
    let description: String
}

private struct CorrectionSliderQuickAction {
    let title: String
    let action: () -> Void
}

private struct CorrectionTermHelpButton: View {
    let title: String
    let reading: String
    let description: String
    @State private var isPresented = false

    var body: some View {
        Button("用語の説明を表示", systemImage: "questionmark.circle") {
            isPresented.toggle()
        }
        .labelStyle(.iconOnly)
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                Text(reading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(description)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(width: 260, alignment: .leading)
        }
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(range.upperBound, max(range.lowerBound, self))
    }
}
