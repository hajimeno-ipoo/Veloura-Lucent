import SwiftUI

private enum InspectorSettingsSection: String, CaseIterable, Identifiable {
    case correction
    case mastering
    case app

    var id: String { rawValue }

    var title: String {
        switch self {
        case .correction: "補正"
        case .mastering: "マスタリング"
        case .app: "アプリ"
        }
    }
}

struct InspectorSettingsPanel: View {
    @Bindable var job: ProcessingJob
    @State private var selectedSection: InspectorSettingsSection = .correction
    @State private var showsCorrectionBasic = true
    @State private var showsCorrectionRepair = false
    @State private var showsCorrectionAdvanced = false
    @State private var showsMasteringBasic = true
    @State private var showsMasteringTone = false
    @State private var showsMasteringAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            Picker("詳細設定", selection: $selectedSection) {
                ForEach(InspectorSettingsSection.allCases) { section in
                    Text(section.title).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .disabled(job.isProcessing || job.isMastering)

            selectedContent
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("設定")
                .font(.title3.bold())
            Text("右側では、1項目ずつ縦に並べて調整します。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedSection {
        case .correction:
            correctionSettings
                .disabled(job.isProcessing || job.isMastering)
        case .mastering:
            masteringSettings
                .disabled(job.isProcessing || job.isMastering)
        case .app:
            appSettings
        }
    }

    private var appSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            AppSettingsPanel()

            VStack(alignment: .leading, spacing: 10) {
                Text("解析モード")
                    .font(.headline)
                Picker("解析モード", selection: $job.selectedAnalysisMode) {
                    ForEach(AudioAnalysisMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(job.isProcessing)

                Text(job.selectedAnalysisMode.summary)
                    .foregroundStyle(job.selectedAnalysisMode == .experimentalMetal ? .orange : .secondary)
                Text(job.selectedAnalysisMode.resolvedSummary)
                    .font(.callout)
                    .foregroundStyle(job.selectedAnalysisMode.resolvedMode == .experimentalMetal ? .orange : .secondary)
            }
        }
    }

    private var correctionSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("補正プリセット")
                    .font(.headline)
                Picker("補正プリセット", selection: correctionProfileBinding) {
                    ForEach(DenoiseStrength.allCases) { strength in
                        Text(strength.title).tag(strength)
                    }
                }
                .pickerStyle(.segmented)

                Text(job.selectedDenoiseStrength.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                resetRow(
                    isCustom: job.isUsingCustomCorrectionSettings,
                    resetTitle: "プリセットへ戻す",
                    action: job.resetCorrectionSettingsToProfile
                )
            }

            settingGroup(title: "基本", summary: "補正の強さ、原音の残し方、音の芯を守る量です。", isExpanded: $showsCorrectionBasic) {
                inspectorSlider(
                    title: "補正の強さ",
                    valueText: percentText(job.editableCorrectionSettings.correctionIntensity),
                    labels: ["弱い", "標準", "強い"],
                    value: correctionBinding(\.correctionIntensity, range: 0 ... 1),
                    range: 0 ... 1
                )
                inspectorSlider(
                    title: "原音保持",
                    valueText: percentText(job.editableCorrectionSettings.originalRetention),
                    labels: ["整える", "標準", "残す"],
                    value: correctionBinding(\.originalRetention, range: 0 ... 1),
                    range: 0 ... 1
                )
                inspectorSlider(
                    title: "芯保護",
                    valueText: percentText(job.editableCorrectionSettings.coreProtection),
                    labels: ["整理", "標準", "芯を守る"],
                    value: correctionBinding(\.coreProtection, range: 0 ... 1),
                    range: 0 ... 1
                )
            }

            settingGroup(title: "掃除と修復", summary: "低域の濁り、こもり、高域の戻し方を調整します。", isExpanded: $showsCorrectionRepair) {
                inspectorSlider(title: "低域整理", valueText: percentText(job.editableCorrectionSettings.lowCleanup), labels: ["弱い", "標準", "強い"], value: correctionBinding(\.lowCleanup, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "中低域整理", valueText: percentText(job.editableCorrectionSettings.lowMidCleanup), labels: ["弱い", "標準", "強い"], value: correctionBinding(\.lowMidCleanup, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "プレゼンス修復", valueText: percentText(job.editableCorrectionSettings.presenceRepair), labels: ["控えめ", "標準", "修復"], value: correctionBinding(\.presenceRepair, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "エアー修復", valueText: percentText(job.editableCorrectionSettings.airRepair), labels: ["控えめ", "標準", "修復"], value: correctionBinding(\.airRepair, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "高域の自然さ", valueText: percentText(job.editableCorrectionSettings.highNaturalness), labels: ["明るさ", "標準", "自然"], value: correctionBinding(\.highNaturalness, range: 0 ... 1), range: 0 ... 1)
            }

            settingGroup(title: "上級", summary: "ノイズ検出、高域補完、ステレオ保護を細かく調整します。", isExpanded: $showsCorrectionAdvanced) {
                inspectorSlider(title: "ノイズ検出しきい値", valueText: percentText(job.editableCorrectionSettings.noiseDetectionSensitivity), labels: ["鈍い", "標準", "敏感"], value: correctionBinding(\.noiseDetectionSensitivity, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "高域補完量", valueText: percentText(job.editableCorrectionSettings.harmonicRepairAmount), labels: ["少ない", "標準", "多い"], value: correctionBinding(\.harmonicRepairAmount, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "foldover補完量", valueText: percentText(job.editableCorrectionSettings.foldoverRepairAmount), labels: ["少ない", "標準", "多い"], value: correctionBinding(\.foldoverRepairAmount, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "ステレオ保護", valueText: percentText(job.editableCorrectionSettings.stereoProtection), labels: ["整理", "標準", "保護"], value: correctionBinding(\.stereoProtection, range: 0 ... 1), range: 0 ... 1)
            }
        }
    }

    private var masteringSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("仕上がりプロファイル")
                    .font(.headline)
                Picker("仕上がりプロファイル", selection: $job.selectedMasteringProfile) {
                    ForEach(MasteringProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(job.selectedMasteringProfile.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(job.selectedMasteringProfile.presetTargetText)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text("目標値に必ず合わせるものではなく、仕上げ意図を確認する目安です。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                resetRow(
                    isCustom: job.isUsingCustomMasteringSettings,
                    resetTitle: "プロファイルへ戻す",
                    action: job.resetMasteringSettingsToProfile
                )
            }

            masteringWarnings

            settingGroup(title: "基本", summary: "音量、安全上限、強弱、仕上げの量です。", isExpanded: $showsMasteringBasic) {
                inspectorSlider(title: "目標ラウドネス", valueText: String(format: "%.1f LUFS", job.editableMasteringSettings.targetLoudness), labels: ["余裕", "標準", "大きい"], value: masteringBinding(\.targetLoudness, range: -18 ... -9), range: -18 ... -9, step: 0.1)
                inspectorSlider(title: "True Peak", valueText: String(format: "%.1f dB", job.editableMasteringSettings.peakCeilingDB), labels: ["安全", "標準", "攻める"], value: masteringBinding(\.peakCeilingDB, range: -2 ... -0.2), range: -2 ... -0.2, step: 0.1)
                inspectorSlider(title: "ダイナミクス保持", valueText: percentText(job.editableMasteringSettings.dynamicsRetention), labels: ["密度", "標準", "開放感"], value: masteringBinding(\.dynamicsRetention, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "仕上げの強さ", valueText: percentText(job.editableMasteringSettings.finishingIntensity), labels: ["自然", "標準", "前に出す"], value: masteringBinding(\.finishingIntensity, range: 0 ... 1), range: 0 ... 1)
            }

            settingGroup(title: "音色", summary: "低域、こもり、前に出る感じ、空気感を調整します。", isExpanded: $showsMasteringTone) {
                inspectorSlider(title: "低域", valueText: decimalText(job.editableMasteringSettings.lowShelfGain), labels: ["軽い", "標準", "太い"], value: masteringBinding(\.lowShelfGain, range: 0 ... 2.5), range: 0 ... 2.5)
                inspectorSlider(title: "中低域", valueText: decimalText(job.editableMasteringSettings.lowMidGain), labels: ["すっきり", "標準", "厚い"], value: masteringBinding(\.lowMidGain, range: -1.2 ... 1.2), range: -1.2 ... 1.2)
                inspectorSlider(title: "プレゼンス", valueText: decimalText(job.editableMasteringSettings.presenceGain), labels: ["奥", "標準", "前"], value: masteringBinding(\.presenceGain, range: 0 ... 1.2), range: 0 ... 1.2)
                inspectorSlider(title: "空気感", valueText: decimalText(job.editableMasteringSettings.highShelfGain), labels: ["丸い", "標準", "明るい"], value: masteringBinding(\.highShelfGain, range: 0 ... 2.5), range: 0 ... 2.5)
                inspectorSlider(title: "ハーシュネス抑制", valueText: percentText(job.editableMasteringSettings.deEsserAmount), labels: ["弱い", "標準", "強い"], value: masteringBinding(\.deEsserAmount, range: 0 ... 1), range: 0 ... 1)
            }

            settingGroup(title: "上級", summary: "検出、帯域別コンプ、広がり、倍音密度です。", isExpanded: $showsMasteringAdvanced) {
                inspectorSlider(title: "ハーシュネス検出", valueText: String(format: "%.1f dB", job.editableMasteringSettings.deEsserThresholdDB), labels: ["敏感", "標準", "鈍い"], value: masteringBinding(\.deEsserThresholdDB, range: -36 ... -18), range: -36 ... -18, step: 0.1)
                compressorGroup(title: "低域コンプ", band: \.low)
                compressorGroup(title: "中域コンプ", band: \.mid)
                compressorGroup(title: "高域コンプ", band: \.high)
                inspectorSlider(title: "ステレオ幅", valueText: decimalText(job.editableMasteringSettings.stereoWidth), labels: ["狭い", "標準", "広い"], value: masteringBinding(\.stereoWidth, range: 0.8 ... 1.4), range: 0.8 ... 1.4)
                inspectorSlider(title: "倍音密度", valueText: decimalText(job.editableMasteringSettings.saturationAmount), labels: ["透明", "標準", "濃い"], value: masteringBinding(\.saturationAmount, range: 0 ... 0.45), range: 0 ... 0.45)
            }
        }
    }

    @ViewBuilder
    private var masteringWarnings: some View {
        let warnings = job.editableMasteringSettings.aggressiveSettingWarnings
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func compressorGroup(title: String, band: WritableKeyPath<MultibandCompressionSettings, BandCompressorSettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.callout.bold())
            inspectorSlider(title: "Threshold", valueText: String(format: "%.1f dB", job.editableMasteringSettings.multibandCompression[keyPath: band].thresholdDB), labels: ["深く効く", "標準", "浅く効く"], value: compressorBinding(band: band, field: \.thresholdDB, range: -36 ... -12), range: -36 ... -12, step: 0.1)
            inspectorSlider(title: "Ratio", valueText: String(format: "%.2f", job.editableMasteringSettings.multibandCompression[keyPath: band].ratio), labels: ["自然", "標準", "強く圧縮"], value: compressorBinding(band: band, field: \.ratio, range: 1.1 ... 4.0), range: 1.1 ... 4.0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func settingGroup<Content: View>(
        title: String,
        summary: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 14) {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                content()
            }
            .padding(.top, 8)
        } label: {
            Text(title)
                .font(.headline)
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func inspectorSlider(
        title: String,
        valueText: String,
        labels: [String],
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float = 0.01
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.callout.bold())
                Spacer()
                stepperButtons(title: title, value: value, range: range, step: step)
                Text(valueText)
                    .font(.callout.monospacedDigit().bold())
                    .foregroundStyle(.primary)
            }

            Slider(value: value, in: range, step: step)

            HStack {
                ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: scaleAlignment(index: index, count: labels.count))
                }
            }
        }
    }

    private func stepperButtons(title: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float) -> some View {
        HStack(spacing: 4) {
            Button("\(title)を下げる", systemImage: "minus") {
                value.wrappedValue = limited(value.wrappedValue - step, to: range)
            }
            .labelStyle(.iconOnly)
            Button("\(title)を上げる", systemImage: "plus") {
                value.wrappedValue = limited(value.wrappedValue + step, to: range)
            }
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }

    private func resetRow(isCustom: Bool, resetTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(isCustom ? "手動調整中です" : "既定値を使用しています")
                .font(.callout)
                .foregroundStyle(isCustom ? .orange : .secondary)
            Spacer()
            Button(resetTitle, action: action)
                .disabled(!isCustom)
        }
    }

    private var correctionProfileBinding: Binding<DenoiseStrength> {
        Binding(
            get: { job.selectedDenoiseStrength },
            set: { job.applyCorrectionProfile($0) }
        )
    }

    private func correctionBinding(_ keyPath: WritableKeyPath<CorrectionSettings, Float>, range: ClosedRange<Float>) -> Binding<Float> {
        Binding(
            get: { job.editableCorrectionSettings[keyPath: keyPath] },
            set: { newValue in
                job.updateCorrectionSettings { settings in
                    settings[keyPath: keyPath] = limited(newValue, to: range)
                }
            }
        )
    }

    private func masteringBinding(_ keyPath: WritableKeyPath<MasteringSettings, Float>, range: ClosedRange<Float>) -> Binding<Float> {
        Binding(
            get: { job.editableMasteringSettings[keyPath: keyPath] },
            set: { newValue in
                job.updateMasteringSettings { settings in
                    settings[keyPath: keyPath] = limited(newValue, to: range)
                }
            }
        )
    }

    private func compressorBinding(
        band: WritableKeyPath<MultibandCompressionSettings, BandCompressorSettings>,
        field: WritableKeyPath<BandCompressorSettings, Float>,
        range: ClosedRange<Float>
    ) -> Binding<Float> {
        Binding(
            get: { job.editableMasteringSettings.multibandCompression[keyPath: band][keyPath: field] },
            set: { newValue in
                job.updateMasteringSettings { settings in
                    settings.multibandCompression[keyPath: band][keyPath: field] = limited(newValue, to: range)
                }
            }
        )
    }

    private func percentText(_ value: Float) -> String {
        String(format: "%.0f%%", value * 100)
    }

    private func decimalText(_ value: Float) -> String {
        String(format: "%.2f", value)
    }

    private func scaleAlignment(index: Int, count: Int) -> Alignment {
        if index == 0 {
            return .leading
        }
        if index == count - 1 {
            return .trailing
        }
        return .center
    }

    private func limited(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
