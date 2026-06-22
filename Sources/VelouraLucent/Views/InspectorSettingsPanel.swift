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
                titleWithHelp(
                    "解析モード",
                    font: .headline,
                    help: SettingHelp(
                        title: "解析モード",
                        reading: "かいせきもーど",
                        description: "補正前の音声解析に使う方式です。自動はこのMacで使える方式を選び、安定CPUは速度より安定性を優先し、実験Metalは対応MacでGPUを使います。"
                    )
                )
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
                titleWithHelp(
                    "補正プリセット",
                    font: .headline,
                    help: SettingHelp(
                        title: "補正プリセット",
                        reading: "ほせいぷりせっと",
                        description: "ノイズをどれくらい減らすかの大まかな出発点です。弱い、標準、強いから選び、その後で細かい設定を手動調整できます。"
                    )
                )
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

            settingGroup(
                title: "基本",
                summary: "補正の強さ、原音の残し方、音の芯を守る量です。",
                help: SettingHelp(
                    title: "補正の基本",
                    reading: "ほせいのきほん",
                    description: "ノイズを減らす量と、元の音の自然さをどれだけ残すかを決める中心設定です。強くしすぎると音楽の細かい成分まで弱くなる場合があります。"
                ),
                isExpanded: $showsCorrectionBasic,
                backgroundColor: Color(red: 234.0 / 255.0, green: 225.0 / 255.0, blue: 255.0 / 255.0)
            ) {
                correctionBasicKnobRow
            }

            settingGroup(
                title: "掃除と修復",
                summary: "低域の濁り、こもり、高域の戻し方を調整します。",
                help: SettingHelp(
                    title: "掃除と修復",
                    reading: "そうじとしゅうふく",
                    description: "低いノイズ、こもり、高域の不足を個別に調整します。ノイズを減らす設定と、失われた明るさを戻す設定を分けて扱います。"
                ),
                isExpanded: $showsCorrectionRepair,
                backgroundColor: Color(red: 234.0 / 255.0, green: 225.0 / 255.0, blue: 255.0 / 255.0)
            ) {
                correctionRepairKnobRow
            }

            settingGroup(
                title: "上級",
                summary: "ノイズ検出、高域補完、ステレオ保護を細かく調整します。",
                help: SettingHelp(
                    title: "補正の上級設定",
                    reading: "ほせいのじょうきゅうせってい",
                    description: "検出の敏感さ、高域補完、ステレオの守り方を細かく調整します。通常はプリセット値を基準にしてください。"
                ),
                isExpanded: $showsCorrectionAdvanced
            ) {
                inspectorSlider(title: "ノイズ検出しきい値", help: SettingHelp(title: "ノイズ検出しきい値", reading: "のいずけんしゅつしきいち", description: "どれくらい小さなノイズまで検出するかです。敏感にすると細かいノイズを拾いますが、音楽成分も対象になりやすくなります。"), valueText: percentText(job.editableCorrectionSettings.noiseDetectionSensitivity), labels: ["鈍い", "標準", "敏感"], value: correctionBinding(\.noiseDetectionSensitivity, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "高域補完量", help: SettingHelp(title: "高域補完量", reading: "こういきほかんりょう", description: "補正で弱くなった高域の倍音を補う量です。上げるほど明るさを戻します。"), valueText: percentText(job.editableCorrectionSettings.harmonicRepairAmount), labels: ["少ない", "標準", "多い"], value: correctionBinding(\.harmonicRepairAmount, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "foldover補完量", help: SettingHelp(title: "foldover補完量", reading: "ふぉーるどおーばーほかんりょう", description: "高域の不足を別の帯域情報から補う量です。上げるほど高域の伸びを戻しますが、不自然な明るさが出る場合があります。"), valueText: percentText(job.editableCorrectionSettings.foldoverRepairAmount), labels: ["少ない", "標準", "多い"], value: correctionBinding(\.foldoverRepairAmount, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "ステレオ保護", help: SettingHelp(title: "ステレオ保護", reading: "すてれおほご", description: "左右の広がりや位相の違いを守る量です。上げるほど補正で広がりが崩れにくくなります。"), valueText: percentText(job.editableCorrectionSettings.stereoProtection), labels: ["整理", "標準", "保護"], value: correctionBinding(\.stereoProtection, range: 0 ... 1), range: 0 ... 1)
            }
        }
    }

    private var masteringSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                titleWithHelp(
                    "仕上がりプロファイル",
                    font: .headline,
                    help: SettingHelp(
                        title: "仕上がりプロファイル",
                        reading: "しあがりぷろふぁいる",
                        description: "最終版の音量感、明るさ、押し出し方の出発点です。配信用、安全重視、音圧重視など、仕上げたい方向に合わせて選びます。"
                    )
                )
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

            settingGroup(
                title: "基本",
                summary: "音量、安全上限、強弱、仕上げの量です。",
                help: SettingHelp(
                    title: "マスタリングの基本",
                    reading: "ますたりんぐのきほん",
                    description: "最終版の音量、安全上限、強弱の残し方、仕上げの効き方を決めます。測定値は事故防止の目安で、最終判断は試聴で行います。"
                ),
                isExpanded: $showsMasteringBasic
            ) {
                inspectorSlider(title: "目標ラウドネス", help: SettingHelp(title: "目標ラウドネス", reading: "もくひょうらうどねす", description: "最終版で目指す平均音量の目安です。必ず一致させる数値ではなく、曲の自然さと安全上限を見ながら近づけます。"), valueText: String(format: "%.1f LUFS", job.editableMasteringSettings.targetLoudness), labels: ["余裕", "標準", "大きい"], value: masteringBinding(\.targetLoudness, range: -18 ... -9), range: -18 ... -9, step: 0.1)
                inspectorSlider(title: "True Peak", help: SettingHelp(title: "True Peak", reading: "とぅるーぴーく", description: "書き出し後に歪まないようにするピーク上限です。値を上げるほど音量の余地は増えますが、安全余裕は小さくなります。"), valueText: String(format: "%.1f dB", job.editableMasteringSettings.peakCeilingDB), labels: ["安全", "標準", "攻める"], value: masteringBinding(\.peakCeilingDB, range: -2 ... -0.2), range: -2 ... -0.2, step: 0.1)
                inspectorSlider(title: "ダイナミクス保持", help: SettingHelp(title: "ダイナミクス保持", reading: "だいなみくすほじ", description: "音の強弱や抑揚をどれだけ残すかです。上げるほどサビや演奏の動きが残りやすくなります。"), valueText: percentText(job.editableMasteringSettings.dynamicsRetention), labels: ["密度", "標準", "開放感"], value: masteringBinding(\.dynamicsRetention, range: 0 ... 1), range: 0 ... 1)
                inspectorSlider(title: "仕上げの強さ", help: SettingHelp(title: "仕上げの強さ", reading: "しあげのつよさ", description: "マスタリング処理を全体的にどれくらい効かせるかです。上げるほど前に出ますが、素材によっては自然さが減る場合があります。"), valueText: percentText(job.editableMasteringSettings.finishingIntensity), labels: ["自然", "標準", "前に出す"], value: masteringBinding(\.finishingIntensity, range: 0 ... 1), range: 0 ... 1)
            }

            settingGroup(
                title: "音色",
                summary: "低域、こもり、前に出る感じ、空気感を調整します。",
                help: SettingHelp(
                    title: "音色",
                    reading: "ねいろ",
                    description: "最終版の低域、中低域、前に出る感じ、空気感、耳に痛い高域を調整します。音量とは別に、聞こえ方の色合いを決める設定です。"
                ),
                isExpanded: $showsMasteringTone
            ) {
                inspectorSlider(title: "低域", help: SettingHelp(title: "低域", reading: "ていいき", description: "キックやベースの土台になる低い帯域です。上げるほど太くなりますが、上げすぎると重く聞こえる場合があります。"), valueText: decimalText(job.editableMasteringSettings.lowShelfGain), labels: ["軽い", "標準", "太い"], value: masteringBinding(\.lowShelfGain, range: 0 ... 2.5), range: 0 ... 2.5)
                inspectorSlider(title: "中低域", help: SettingHelp(title: "中低域", reading: "ちゅうていいき", description: "音の厚みやこもりに関わる帯域です。下げるとすっきりし、上げると厚みが増えます。"), valueText: decimalText(job.editableMasteringSettings.lowMidGain), labels: ["すっきり", "標準", "厚い"], value: masteringBinding(\.lowMidGain, range: -1.2 ... 1.2), range: -1.2 ... 1.2)
                inspectorSlider(title: "プレゼンス", help: SettingHelp(title: "プレゼンス", reading: "ぷれぜんす", description: "声や主旋律が前に出る感じに関わる帯域です。上げるほど明瞭になりますが、上げすぎると耳に近く感じる場合があります。"), valueText: decimalText(job.editableMasteringSettings.presenceGain), labels: ["奥", "標準", "前"], value: masteringBinding(\.presenceGain, range: 0 ... 1.2), range: 0 ... 1.2)
                inspectorSlider(title: "空気感", help: SettingHelp(title: "空気感", reading: "くうきかん", description: "息感や高域の伸びに関わる帯域です。上げるほど明るく開いた印象になります。"), valueText: decimalText(job.editableMasteringSettings.highShelfGain), labels: ["丸い", "標準", "明るい"], value: masteringBinding(\.highShelfGain, range: 0 ... 2.5), range: 0 ... 2.5)
                inspectorSlider(title: "ハーシュネス抑制", help: SettingHelp(title: "ハーシュネス抑制", reading: "はーしゅねすよくせい", description: "サ行や耳に痛い高域を抑える量です。強くしすぎると抜けや明るさも弱くなる場合があります。"), valueText: percentText(job.editableMasteringSettings.deEsserAmount), labels: ["弱い", "標準", "強い"], value: masteringBinding(\.deEsserAmount, range: 0 ... 1), range: 0 ... 1)
            }

            settingGroup(
                title: "上級",
                summary: "検出、帯域別コンプ、広がり、倍音密度です。",
                help: SettingHelp(
                    title: "マスタリングの上級設定",
                    reading: "ますたりんぐのじょうきゅうせってい",
                    description: "高域の検出、帯域別の圧縮、ステレオ幅、倍音の濃さを調整します。音の印象が大きく変わるため、必要な時だけ触る設定です。"
                ),
                isExpanded: $showsMasteringAdvanced
            ) {
                inspectorSlider(title: "ハーシュネス検出", help: SettingHelp(title: "ハーシュネス検出", reading: "はーしゅねすけんしゅつ", description: "耳に痛い高域を検出する基準です。敏感にすると小さな刺さりも拾いますが、明るい音楽成分も対象になりやすくなります。"), valueText: String(format: "%.1f dB", job.editableMasteringSettings.deEsserThresholdDB), labels: ["敏感", "標準", "鈍い"], value: masteringBinding(\.deEsserThresholdDB, range: -36 ... -18), range: -36 ... -18, step: 0.1)
                compressorGroup(title: "低域コンプ", help: SettingHelp(title: "低域コンプ", reading: "ていいきこんぷ", description: "低域の音量差を整える処理です。キックやベースの暴れを抑え、低域の量感を安定させます。"), band: \.low)
                compressorGroup(title: "中域コンプ", help: SettingHelp(title: "中域コンプ", reading: "ちゅういきこんぷ", description: "声や主旋律の中心帯域を整える処理です。前に出る感じと聞きやすさに関わります。"), band: \.mid)
                compressorGroup(title: "高域コンプ", help: SettingHelp(title: "高域コンプ", reading: "こういきこんぷ", description: "明るさや刺激感の出過ぎを整える処理です。高域の動きを落ち着かせます。"), band: \.high)
                inspectorSlider(title: "ステレオ幅", help: SettingHelp(title: "ステレオ幅", reading: "すてれおはば", description: "左右への広がり具合です。今の実装では低域を広げず、中高域を中心に広がりを調整します。"), valueText: decimalText(job.editableMasteringSettings.stereoWidth), labels: ["狭い", "標準", "広い"], value: masteringBinding(\.stereoWidth, range: 0.8 ... 1.4), range: 0.8 ... 1.4)
                inspectorSlider(title: "倍音密度", help: SettingHelp(title: "倍音密度", reading: "ばいおんみつど", description: "音に厚みや存在感を加える量です。上げるほど濃くなりますが、上げすぎると透明感が減る場合があります。"), valueText: decimalText(job.editableMasteringSettings.saturationAmount), labels: ["透明", "標準", "濃い"], value: masteringBinding(\.saturationAmount, range: 0 ... 0.45), range: 0 ... 0.45)
            }
        }
    }

    private var correctionBasicKnobRow: some View {
        ViewThatFits(in: .horizontal) {
            correctionBasicThreeColumnRow
            correctionBasicTwoColumnRow
            correctionBasicOneColumnRow
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var correctionBasicThreeColumnRow: some View {
        HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
            correctionIntensityKnob
            originalRetentionKnob
            coreProtectionKnob
        }
        .frame(width: DAWKnobMetrics.threeColumnWidth)
    }

    private var correctionBasicTwoColumnRow: some View {
        VStack(spacing: DAWKnobMetrics.rowSpacing) {
            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                correctionIntensityKnob
                originalRetentionKnob
            }
            .frame(width: DAWKnobMetrics.twoColumnWidth)

            coreProtectionKnob
        }
        .frame(width: DAWKnobMetrics.twoColumnWidth)
    }

    private var correctionBasicOneColumnRow: some View {
        VStack(spacing: DAWKnobMetrics.rowSpacing) {
            correctionIntensityKnob
            originalRetentionKnob
            coreProtectionKnob
        }
        .frame(width: DAWKnobMetrics.controlWidth)
    }

    private var correctionIntensityKnob: some View {
        DAWKnobControl(
            title: "補正の強さ",
            help: SettingHelp(
                title: "補正の強さ",
                reading: "ほせいのつよさ",
                description: "ノイズ低減を全体的にどれくらい効かせるかです。上げるほどノイズは減りやすくなりますが、音の細かい余韻も変わりやすくなります。"
            ),
            valueText: percentText(job.editableCorrectionSettings.correctionIntensity),
            displayValueText: percentNumberText(job.editableCorrectionSettings.correctionIntensity),
            unitText: "%",
            labels: ["弱い", "標準", "強い"],
            value: correctionBinding(\.correctionIntensity, range: 0 ... 1),
            range: 0 ... 1,
            step: 0.01
        )
    }

    private var originalRetentionKnob: some View {
        DAWKnobControl(
            title: "原音保持",
            help: SettingHelp(
                title: "原音保持",
                reading: "げんおんほじ",
                description: "入力音声の雰囲気や質感をどれだけ残すかです。上げるほど元の音の印象を守りやすくなります。"
            ),
            valueText: percentText(job.editableCorrectionSettings.originalRetention),
            displayValueText: percentNumberText(job.editableCorrectionSettings.originalRetention),
            unitText: "%",
            labels: ["整える", "標準", "残す"],
            value: correctionBinding(\.originalRetention, range: 0 ... 1),
            range: 0 ... 1,
            step: 0.01
        )
    }

    private var coreProtectionKnob: some View {
        DAWKnobControl(
            title: "芯保護",
            help: SettingHelp(
                title: "芯保護",
                reading: "しんほご",
                description: "声や主旋律の中心になる帯域を守る量です。上げるほど音の中心が細くなりにくくなります。"
            ),
            valueText: percentText(job.editableCorrectionSettings.coreProtection),
            displayValueText: percentNumberText(job.editableCorrectionSettings.coreProtection),
            unitText: "%",
            labels: ["整理", "標準", "芯を守る"],
            value: correctionBinding(\.coreProtection, range: 0 ... 1),
            range: 0 ... 1,
            step: 0.01
        )
    }

    private var correctionRepairKnobRow: some View {
        VStack(spacing: DAWKnobMetrics.rowSpacing) {
            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                lowCleanupKnob
                lowMidCleanupKnob
                presenceRepairKnob
            }
            .frame(width: DAWKnobMetrics.threeColumnWidth)

            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                airRepairKnob
                highNaturalnessKnob
            }
            .frame(width: DAWKnobMetrics.twoColumnWidth)
        }
        .frame(width: DAWKnobMetrics.threeColumnWidth, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var lowCleanupKnob: some View {
        DAWKnobControl(
            title: "低域整理",
            help: SettingHelp(
                title: "低域整理",
                reading: "ていいきせいり",
                description: "低いゴロゴロしたノイズや不要な低音を整理する量です。上げるほど低域の濁りを抑えます。"
            ),
            valueText: percentText(job.editableCorrectionSettings.lowCleanup),
            displayValueText: percentNumberText(job.editableCorrectionSettings.lowCleanup),
            unitText: "%",
            labels: ["弱い", "標準", "強い"],
            value: correctionBinding(\.lowCleanup, range: 0 ... 1),
            range: 0 ... 1,
            step: 0.01
        )
    }

    private var lowMidCleanupKnob: some View {
        DAWKnobControl(
            title: "中低域整理",
            help: SettingHelp(
                title: "中低域整理",
                reading: "ちゅうていいきせいり",
                description: "300Hzから1kHz付近のこもりを整理する量です。上げるほど暗さや詰まりを抑えます。"
            ),
            valueText: percentText(job.editableCorrectionSettings.lowMidCleanup),
            displayValueText: percentNumberText(job.editableCorrectionSettings.lowMidCleanup),
            unitText: "%",
            labels: ["弱い", "標準", "強い"],
            value: correctionBinding(\.lowMidCleanup, range: 0 ... 1),
            range: 0 ... 1,
            step: 0.01
        )
    }

    private var presenceRepairKnob: some View {
        DAWKnobControl(
            title: "プレゼンス修復",
            help: SettingHelp(
                title: "プレゼンス修復",
                reading: "ぷれぜんすしゅうふく",
                description: "声や主旋律が前に出る帯域を補う量です。補正で引っ込みすぎた時に戻します。"
            ),
            valueText: percentText(job.editableCorrectionSettings.presenceRepair),
            displayValueText: percentNumberText(job.editableCorrectionSettings.presenceRepair),
            unitText: "%",
            labels: ["控えめ", "標準", "修復"],
            value: correctionBinding(\.presenceRepair, range: 0 ... 1),
            range: 0 ... 1,
            step: 0.01
        )
    }

    private var airRepairKnob: some View {
        DAWKnobControl(
            title: "エアー修復",
            help: SettingHelp(
                title: "エアー修復",
                reading: "えあーしゅうふく",
                description: "息感や空気感に関わる高域を補う量です。高域ノイズではなく、音楽成分として残したい明るさを戻します。"
            ),
            valueText: percentText(job.editableCorrectionSettings.airRepair),
            displayValueText: percentNumberText(job.editableCorrectionSettings.airRepair),
            unitText: "%",
            labels: ["控えめ", "標準", "修復"],
            value: correctionBinding(\.airRepair, range: 0 ... 1),
            range: 0 ... 1,
            step: 0.01
        )
    }

    private var highNaturalnessKnob: some View {
        DAWKnobControl(
            title: "高域の自然さ",
            help: SettingHelp(
                title: "高域の自然さ",
                reading: "こういきのしぜんさ",
                description: "高域が不自然に硬くならないように整える量です。上げるほど明るさより自然さを優先します。"
            ),
            valueText: percentText(job.editableCorrectionSettings.highNaturalness),
            displayValueText: percentNumberText(job.editableCorrectionSettings.highNaturalness),
            unitText: "%",
            labels: ["明るさ", "標準", "自然"],
            value: correctionBinding(\.highNaturalness, range: 0 ... 1),
            range: 0 ... 1,
            step: 0.01
        )
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

    private func compressorGroup(title: String, help: SettingHelp?, band: WritableKeyPath<MultibandCompressionSettings, BandCompressorSettings>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            titleWithHelp(title, font: .callout.bold(), help: help)
            inspectorSlider(title: "Threshold", help: SettingHelp(title: "\(title) Threshold", reading: "すれっしょるど", description: "コンプレッサーが反応し始める音量です。値を低くするほど、より小さな音から圧縮が始まります。"), valueText: String(format: "%.1f dB", job.editableMasteringSettings.multibandCompression[keyPath: band].thresholdDB), labels: ["深く効く", "標準", "浅く効く"], value: compressorBinding(band: band, field: \.thresholdDB, range: -36 ... -12), range: -36 ... -12, step: 0.1)
            inspectorSlider(title: "Ratio", help: SettingHelp(title: "\(title) Ratio", reading: "れしお", description: "しきい値を超えた音をどれくらい圧縮するかです。値を上げるほど強く抑えます。"), valueText: String(format: "%.2f", job.editableMasteringSettings.multibandCompression[keyPath: band].ratio), labels: ["自然", "標準", "強く圧縮"], value: compressorBinding(band: band, field: \.ratio, range: 1.1 ... 4.0), range: 1.1 ... 4.0)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func settingGroup<Content: View>(
        title: String,
        summary: String,
        help: SettingHelp?,
        isExpanded: Binding<Bool>,
        backgroundColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            if isExpanded.wrappedValue {
                VStack(alignment: .leading, spacing: 14) {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    content()
                }
                .padding(.top, 8)
            }
        } label: {
            titleWithHelp(title, font: .headline, help: help)
        }
        .padding(12)
        .background {
            if let backgroundColor {
                RoundedRectangle(cornerRadius: 14)
                    .fill(backgroundColor)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.thinMaterial)
            }
        }
    }

    private func inspectorSlider(
        title: String,
        help: SettingHelp?,
        valueText: String,
        labels: [String],
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float = 0.01
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    titleWithHelp(title, font: .callout.bold(), help: help)
                    Spacer()
                    stepperButtons(title: title, value: value, range: range, step: step)
                    sliderValueText(valueText)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        titleWithHelp(title, font: .callout.bold(), help: help)
                        Spacer()
                        sliderValueText(valueText)
                    }
                    stepperButtons(title: title, value: value, range: range, step: step)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
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

    private func sliderValueText(_ value: String) -> some View {
        Text(value)
            .font(.callout.monospacedDigit().bold())
            .foregroundStyle(.primary)
            .lineLimit(1)
    }

    private func titleWithHelp(_ title: String, font: Font, help: SettingHelp?) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(font)
            if let help {
                TermHelpButton(title: help.title, reading: help.reading, description: help.description)
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 10) {
                resetStatusText(isCustom: isCustom)
                Spacer()
                resetButton(title: resetTitle, isCustom: isCustom, action: action)
            }

            VStack(alignment: .leading, spacing: 8) {
                resetStatusText(isCustom: isCustom)
                resetButton(title: resetTitle, isCustom: isCustom, action: action)
            }
        }
    }

    private func resetStatusText(isCustom: Bool) -> some View {
        Text(isCustom ? "手動調整中です" : "既定値を使用しています")
            .font(.callout)
            .foregroundStyle(isCustom ? .orange : .secondary)
    }

    private func resetButton(title: String, isCustom: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .disabled(!isCustom)
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

    private func percentNumberText(_ value: Float) -> String {
        String(format: "%.0f", value * 100)
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
