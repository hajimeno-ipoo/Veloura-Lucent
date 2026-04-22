import SwiftUI

struct MasteringSettingsPanel: View {
    @Bindable var job: ProcessingJob

    private let advancedSettingColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("マスタリング")
                .font(.headline)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("仕上がり")
                        .font(.subheadline.weight(.semibold))
                    Picker("仕上がり", selection: $job.selectedMasteringProfile) {
                        ForEach(MasteringProfile.allCases) { profile in
                            Text(profile.title).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("説明")
                        .font(.subheadline.weight(.semibold))
                    Text(job.selectedMasteringProfile.summary)
                        .foregroundStyle(.secondary)
                    Text(job.isUsingCustomMasteringSettings ? "詳細設定を調整中です" : "プリセットの既定値を使用しています")
                        .font(.caption)
                        .foregroundStyle(job.isUsingCustomMasteringSettings ? .orange : .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclosureGroup(isExpanded: $job.showAdvancedMasteringSettings) {
                advancedMasteringSettings
                    .padding(.top, 8)
            } label: {
                Text("詳細設定")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var advancedMasteringSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("まず基本だけ触れば十分です。音色と上級は必要な時だけ調整します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("プリセットへ戻す") {
                    job.resetMasteringSettingsToProfile()
                }
                .disabled(!job.isUsingCustomMasteringSettings)
            }

            settingsSection(title: "基本", summary: "音量、安全性、開放感、押し出し感をまとめて調整します。") {
                LazyVGrid(columns: advancedSettingColumns, spacing: 12) {
                    loudnessControl
                    truePeakControl
                    dynamicsRetentionControl
                    finishingIntensityControl
                }
            }

            settingsSection(title: "音色", summary: "低域の土台、こもり、前に出る感じ、空気感を整えます。") {
                LazyVGrid(columns: advancedSettingColumns, spacing: 12) {
                    lowToneControl
                    lowMidToneControl
                    presenceToneControl
                    airToneControl
                    harshnessAmountControl
                }
            }

            settingsSection(title: "上級", summary: "コンプ、検出しきい値、広がり、倍音密度を細かく調整します。") {
                LazyVGrid(columns: advancedSettingColumns, spacing: 12) {
                    deEssThresholdControl
                    compressorControlCard(item: compressionBandDefinitions[0], band: \.low)
                    compressorControlCard(item: compressionBandDefinitions[1], band: \.mid)
                    compressorControlCard(item: compressionBandDefinitions[2], band: \.high)
                    stereoWidthControl
                    saturationControl
                }
            }
        }
    }

    private var loudnessControl: some View {
        sliderCard(
            item: radarTermDefinitions[0],
            valueText: String(format: "%.1f LUFS", job.editableMasteringSettings.targetLoudness),
            hintText: "小さいほど余裕、大きいほど前に出ます。",
            scaleLabels: ["余裕", "標準", "大きい"],
            quickActions: [
                SliderQuickAction(title: "余裕", action: { set(\.targetLoudness, -16.0, range: -18 ... -9) }),
                SliderQuickAction(title: "標準", action: { set(\.targetLoudness, -14.5, range: -18 ... -9) }),
                SliderQuickAction(title: "強め", action: { set(\.targetLoudness, -13.8, range: -18 ... -9) })
            ],
            stepperActions: stepper(for: \.targetLoudness, delta: 0.1, range: -18 ... -9)
        ) {
            Slider(value: settingBinding(\.targetLoudness, range: -18 ... -9), in: -18 ... -9, step: 0.1)
        }
    }

    private var truePeakControl: some View {
        sliderCard(
            item: radarTermDefinitions[1],
            valueText: String(format: "%.1f dB", job.editableMasteringSettings.peakCeilingDB),
            hintText: "0 dBに近いほど危険です。通常は -1.0 dB 前後が安全です。",
            scaleLabels: ["安全", "標準", "攻める"],
            quickActions: [
                SliderQuickAction(title: "安全", action: { set(\.peakCeilingDB, -1.5, range: -2 ... -0.2) }),
                SliderQuickAction(title: "標準", action: { set(\.peakCeilingDB, -1.0, range: -2 ... -0.2) }),
                SliderQuickAction(title: "攻める", action: { set(\.peakCeilingDB, -0.7, range: -2 ... -0.2) })
            ],
            stepperActions: stepper(for: \.peakCeilingDB, delta: 0.1, range: -2 ... -0.2)
        ) {
            Slider(value: settingBinding(\.peakCeilingDB, range: -2 ... -0.2), in: -2 ... -0.2, step: 0.1)
        }
    }

    private var dynamicsRetentionControl: some View {
        sliderCard(
            item: MasteringSettingTerm(
                id: "dynamicsRetention",
                label: "ダイナミクス保持",
                reading: "だいなみくすほじ",
                description: "音の強弱差をどれだけ残すかです。高くすると圧縮感や息苦しさを抑えます。"
            ),
            valueText: String(format: "%.0f%%", job.editableMasteringSettings.dynamicsRetention * 100),
            hintText: "サビの開放感を残したい時は高めにします。",
            scaleLabels: ["密度優先", "バランス", "開放感"],
            quickActions: [
                SliderQuickAction(title: "密度", action: { set(\.dynamicsRetention, 0.45, range: 0 ... 1) }),
                SliderQuickAction(title: "標準", action: { set(\.dynamicsRetention, 0.68, range: 0 ... 1) }),
                SliderQuickAction(title: "開放感", action: { set(\.dynamicsRetention, 0.85, range: 0 ... 1) })
            ],
            stepperActions: stepper(for: \.dynamicsRetention, delta: 0.01, range: 0 ... 1)
        ) {
            Slider(value: settingBinding(\.dynamicsRetention, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var finishingIntensityControl: some View {
        sliderCard(
            item: MasteringSettingTerm(
                id: "finishingIntensity",
                label: "仕上げの強さ",
                reading: "しあげのつよさ",
                description: "音量、密度、押し出し感をまとめて調整します。上げるほど前に出ます。"
            ),
            valueText: String(format: "%.0f%%", job.editableMasteringSettings.finishingIntensity * 100),
            hintText: "上げすぎると平坦に聞こえやすくなります。",
            scaleLabels: ["自然", "標準", "前に出す"],
            quickActions: [
                SliderQuickAction(title: "自然", action: { set(\.finishingIntensity, 0.35, range: 0 ... 1) }),
                SliderQuickAction(title: "標準", action: { set(\.finishingIntensity, 0.55, range: 0 ... 1) }),
                SliderQuickAction(title: "強め", action: { set(\.finishingIntensity, 0.75, range: 0 ... 1) })
            ],
            stepperActions: stepper(for: \.finishingIntensity, delta: 0.01, range: 0 ... 1)
        ) {
            Slider(value: settingBinding(\.finishingIntensity, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var lowToneControl: some View {
        sliderCard(
            item: masteringSettingDefinitions[0],
            valueText: String(format: "%.2f", job.editableMasteringSettings.lowShelfGain),
            scaleLabels: ["軽い", "標準", "太い"],
            stepperActions: stepper(for: \.lowShelfGain, delta: 0.05, range: 0 ... 2.5)
        ) {
            Slider(value: settingBinding(\.lowShelfGain, range: 0 ... 2.5), in: 0 ... 2.5, step: 0.05)
        }
    }

    private var lowMidToneControl: some View {
        sliderCard(
            item: masteringSettingDefinitions[1],
            valueText: String(format: "%.2f", job.editableMasteringSettings.lowMidGain),
            scaleLabels: ["すっきり", "標準", "厚い"],
            stepperActions: stepper(for: \.lowMidGain, delta: 0.05, range: -1.2 ... 1.2)
        ) {
            Slider(value: settingBinding(\.lowMidGain, range: -1.2 ... 1.2), in: -1.2 ... 1.2, step: 0.05)
        }
    }

    private var presenceToneControl: some View {
        sliderCard(
            item: masteringSettingDefinitions[2],
            valueText: String(format: "%.2f", job.editableMasteringSettings.presenceGain),
            scaleLabels: ["奥", "標準", "前"],
            stepperActions: stepper(for: \.presenceGain, delta: 0.05, range: 0 ... 1.2)
        ) {
            Slider(value: settingBinding(\.presenceGain, range: 0 ... 1.2), in: 0 ... 1.2, step: 0.05)
        }
    }

    private var airToneControl: some View {
        sliderCard(
            item: masteringSettingDefinitions[3],
            valueText: String(format: "%.2f", job.editableMasteringSettings.highShelfGain),
            scaleLabels: ["丸い", "標準", "明るい"],
            stepperActions: stepper(for: \.highShelfGain, delta: 0.05, range: 0 ... 2.5)
        ) {
            Slider(value: settingBinding(\.highShelfGain, range: 0 ... 2.5), in: 0 ... 2.5, step: 0.05)
        }
    }

    private var harshnessAmountControl: some View {
        sliderCard(
            item: masteringSettingDefinitions[4],
            valueText: String(format: "%.0f%%", job.editableMasteringSettings.deEsserAmount * 100),
            scaleLabels: ["弱い", "標準", "強い"],
            stepperActions: stepper(for: \.deEsserAmount, delta: 0.01, range: 0 ... 1)
        ) {
            Slider(value: settingBinding(\.deEsserAmount, range: 0 ... 1), in: 0 ... 1, step: 0.01)
        }
    }

    private var deEssThresholdControl: some View {
        sliderCard(
            item: MasteringSettingTerm(
                id: "deEssThreshold",
                label: "ハーシュネス検出しきい値",
                reading: "はーしゅねすけんしゅつしきいち",
                description: "ハーシュネス抑制が動き始める強さです。下げるほど早めに反応します。"
            ),
            valueText: String(format: "%.1f dB", job.editableMasteringSettings.deEsserThresholdDB),
            scaleLabels: ["敏感", "標準", "鈍い"],
            stepperActions: stepper(for: \.deEsserThresholdDB, delta: 0.5, range: -36 ... -18)
        ) {
            Slider(value: settingBinding(\.deEsserThresholdDB, range: -36 ... -18), in: -36 ... -18, step: 0.5)
        }
    }

    private var stereoWidthControl: some View {
        sliderCard(
            item: masteringSettingDefinitions[5],
            valueText: String(format: "%.2f", job.editableMasteringSettings.stereoWidth),
            scaleLabels: ["狭い", "標準", "広い"],
            stepperActions: stepper(for: \.stereoWidth, delta: 0.01, range: 0.8 ... 1.4)
        ) {
            Slider(value: settingBinding(\.stereoWidth, range: 0.8 ... 1.4), in: 0.8 ... 1.4, step: 0.01)
        }
    }

    private var saturationControl: some View {
        sliderCard(
            item: MasteringSettingTerm(
                id: "saturation",
                label: "サチュレーション",
                reading: "さちゅれーしょん",
                description: "倍音を足して音の密度感を増やす処理です。強くしすぎると飽和して聞こえます。"
            ),
            valueText: String(format: "%.2f", job.editableMasteringSettings.saturationAmount),
            scaleLabels: ["透明", "標準", "濃い"],
            stepperActions: stepper(for: \.saturationAmount, delta: 0.01, range: 0 ... 0.45)
        ) {
            Slider(value: settingBinding(\.saturationAmount, range: 0 ... 0.45), in: 0 ... 0.45, step: 0.01)
        }
    }

    private func compressorControlCard(item: MasteringSettingTerm, band: WritableKeyPath<MultibandCompressionSettings, BandCompressorSettings>) -> some View {
        let settings = job.editableMasteringSettings.multibandCompression[keyPath: band]

        return VStack(alignment: .leading, spacing: 12) {
            termLabel(item: item)

            compressorSliderBlock(
                title: "Threshold",
                valueText: String(format: "%.1f dB", settings.thresholdDB),
                hintText: "左ほど深く効き、右ほど自然に残ります。",
                scaleLabels: ["深く効く", "標準", "浅く効く"],
                stepperActions: compressorStepper(band: band, field: \.thresholdDB, delta: 0.5, range: -36 ... -12)
            ) {
                Slider(
                    value: compressorBinding(band: band, field: \.thresholdDB, range: -36 ... -12),
                    in: -36 ... -12,
                    step: 0.5
                )
            }

            compressorSliderBlock(
                title: "Ratio",
                valueText: String(format: "%.2f", settings.ratio),
                hintText: "右ほど圧縮が強くなります。",
                scaleLabels: ["自然", "標準", "強く圧縮"],
                stepperActions: compressorStepper(band: band, field: \.ratio, delta: 0.05, range: 1.1 ... 4.0)
            ) {
                Slider(
                    value: compressorBinding(band: band, field: \.ratio, range: 1.1 ... 4.0),
                    in: 1.1 ... 4.0,
                    step: 0.05
                )
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func compressorSliderBlock<Content: View>(
        title: String,
        valueText: String,
        hintText: String,
        scaleLabels: [String],
        stepperActions: (decrement: () -> Void, increment: () -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                stepperButtons(title: title, actions: stepperActions)
                Text(valueText)
                    .font(.title3.monospacedDigit().weight(.bold))
            }

            content()

            scaleLabelsView(scaleLabels)

            Text(hintText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func sliderCard<Content: View>(
        item: MasteringSettingTerm,
        valueText: String,
        hintText: String? = nil,
        scaleLabels: [String] = [],
        quickActions: [SliderQuickAction] = [],
        stepperActions: (decrement: () -> Void, increment: () -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                termLabel(item: item)
                Spacer()
                stepperButtons(title: item.label, actions: stepperActions)
                Text(valueText)
                    .font(.title3.monospacedDigit().weight(.bold))
                    .foregroundStyle(.primary)
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

            if !scaleLabels.isEmpty {
                scaleLabelsView(scaleLabels)
            }

            if let hintText {
                Text(hintText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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

    private func termLabel(item: MasteringSettingTerm) -> some View {
        HStack(spacing: 6) {
            Text(item.label)
                .font(.title3.weight(.semibold))
            MasteringTermHelpButton(title: item.label, reading: item.reading, description: item.description)
        }
    }

    private func settingBinding(_ keyPath: WritableKeyPath<MasteringSettings, Float>, range: ClosedRange<Float>) -> Binding<Float> {
        Binding(
            get: { job.editableMasteringSettings[keyPath: keyPath] },
            set: { set(keyPath, $0, range: range) }
        )
    }

    private func compressorBinding(
        band: WritableKeyPath<MultibandCompressionSettings, BandCompressorSettings>,
        field: WritableKeyPath<BandCompressorSettings, Float>,
        range: ClosedRange<Float>
    ) -> Binding<Float> {
        Binding(
            get: { job.editableMasteringSettings.multibandCompression[keyPath: band][keyPath: field] },
            set: { value in setCompressor(band: band, field: field, value: value, range: range) }
        )
    }

    private func stepper(for keyPath: WritableKeyPath<MasteringSettings, Float>, delta: Float, range: ClosedRange<Float>) -> (decrement: () -> Void, increment: () -> Void) {
        (
            decrement: { set(keyPath, job.editableMasteringSettings[keyPath: keyPath] - delta, range: range) },
            increment: { set(keyPath, job.editableMasteringSettings[keyPath: keyPath] + delta, range: range) }
        )
    }

    private func compressorStepper(
        band: WritableKeyPath<MultibandCompressionSettings, BandCompressorSettings>,
        field: WritableKeyPath<BandCompressorSettings, Float>,
        delta: Float,
        range: ClosedRange<Float>
    ) -> (decrement: () -> Void, increment: () -> Void) {
        let value = job.editableMasteringSettings.multibandCompression[keyPath: band][keyPath: field]
        return (
            decrement: { setCompressor(band: band, field: field, value: value - delta, range: range) },
            increment: { setCompressor(band: band, field: field, value: value + delta, range: range) }
        )
    }

    private func set(_ keyPath: WritableKeyPath<MasteringSettings, Float>, _ value: Float, range: ClosedRange<Float>) {
        job.updateMasteringSettings { settings in
            settings[keyPath: keyPath] = value.clamped(to: range)
        }
    }

    private func setCompressor(
        band: WritableKeyPath<MultibandCompressionSettings, BandCompressorSettings>,
        field: WritableKeyPath<BandCompressorSettings, Float>,
        value: Float,
        range: ClosedRange<Float>
    ) {
        job.updateMasteringSettings { settings in
            settings.multibandCompression[keyPath: band][keyPath: field] = value.clamped(to: range)
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

    private var radarTermDefinitions: [MasteringSettingTerm] {
        [
            MasteringSettingTerm(id: "loudness", label: "ラウドネス", reading: "らうどねす", description: "曲全体の平均的な音量感です。配信先で聞こえる大きさの目安になります。"),
            MasteringSettingTerm(id: "truePeak", label: "トゥルーピーク", reading: "とぅるーぴーく", description: "波形の本当の最大ピークです。上がりすぎると歪みやすくなります。")
        ]
    }

    private var masteringSettingDefinitions: [MasteringSettingTerm] {
        [
            MasteringSettingTerm(id: "low", label: "低域", reading: "ていいき", description: "20Hz〜180Hz 付近です。キックやベースの土台になる帯域です。"),
            MasteringSettingTerm(id: "lowMid", label: "中低域", reading: "ちゅうていいき", description: "180Hz〜500Hz 付近です。増えすぎるとこもりや重さとして感じやすい帯域です。"),
            MasteringSettingTerm(id: "presence", label: "プレゼンス帯域", reading: "ぷれぜんすたいいき", description: "2.5kHz〜5.5kHz 付近です。声や主旋律の前に出る感じに関わる帯域です。"),
            MasteringSettingTerm(id: "air", label: "エアー帯域", reading: "えあーたいいき", description: "10kHz〜20kHz 付近です。空気感や高域の伸びに関わる帯域です。"),
            MasteringSettingTerm(id: "deEss", label: "ハーシュネス抑制", reading: "はーしゅねすよくせい", description: "歯擦音や耳に痛い高域だけを抑える処理です。強くしすぎると抜けも弱くなります。"),
            MasteringSettingTerm(id: "stereoWidth", label: "ステレオ幅", reading: "すてれおはば", description: "左右への広がり具合です。今の実装では低域は広げず、中高域だけを広げます。")
        ]
    }

    private var compressionBandDefinitions: [MasteringSettingTerm] {
        [
            MasteringSettingTerm(id: "lowComp", label: "低域コンプ", reading: "ていいきこんぷ", description: "低域のコンプレッサーです。キックやベースの暴れを抑えて、量感を整えます。"),
            MasteringSettingTerm(id: "midComp", label: "中域コンプ", reading: "ちゅういきこんぷ", description: "中域のコンプレッサーです。声や主旋律の押し出しを整えます。"),
            MasteringSettingTerm(id: "highComp", label: "高域コンプ", reading: "こういきこんぷ", description: "高域のコンプレッサーです。明るさや刺激感の出過ぎを整えます。")
        ]
    }
}

private struct MasteringSettingTerm: Identifiable {
    let id: String
    let label: String
    let reading: String
    let description: String
}

private struct SliderQuickAction {
    let title: String
    let action: () -> Void
}

private struct MasteringTermHelpButton: View {
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
