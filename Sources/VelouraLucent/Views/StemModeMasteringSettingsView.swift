import SwiftUI

@MainActor
struct StemModeMasteringSettingsView: View {
    @Bindable var model: StemModeWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StemModeMasteringProfileSection(model: model)

            SettingsDisclosureCard(
                title: "基本",
                summary: "音量、安全上限、強弱、仕上げの量です。",
                help: SettingHelp(
                    title: "マスタリングの基本",
                    reading: "ますたりんぐのきほん",
                    description: "最終版の音量、安全上限、強弱の残し方、仕上げの効き方を決めます。測定値は事故防止の目安で、最終判断は試聴で行います。"
                ),
                initiallyExpanded: true
            ) {
                StemModeMasteringWarnings(
                    warnings: model.masteringSettings.aggressiveSettingWarnings
                )
                StemModeMasteringBasicControls(settings: $model.masteringSettings)
            }

            SettingsDisclosureCard(
                title: "音色",
                summary: "低域、こもり、前に出る感じ、空気感を調整します。",
                help: SettingHelp(
                    title: "音色",
                    reading: "ねいろ",
                    description: "最終版の低域、中低域、前に出る感じ、空気感、耳に痛い高域を調整します。音量とは別に、聞こえ方の色合いを決める設定です。"
                ),
                initiallyExpanded: false
            ) {
                StemModeMasteringToneControls(settings: $model.masteringSettings)
            }

            SettingsDisclosureCard(
                title: "上級",
                summary: "検出、帯域別コンプ、広がり、倍音密度です。",
                help: SettingHelp(
                    title: "マスタリングの上級設定",
                    reading: "ますたりんぐのじょうきゅうせってい",
                    description: "高域の検出、帯域別の圧縮、ステレオ幅、倍音の濃さを調整します。音の印象が大きく変わるため、必要な時だけ触る設定です。"
                ),
                initiallyExpanded: false
            ) {
                StemModeMasteringAdvancedControls(settings: $model.masteringSettings)
            }
        }
    }
}

@MainActor
private struct StemModeMasteringProfileSection: View {
    @Bindable var model: StemModeWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StemModeMasteringTitleWithHelp(
                title: "仕上がりプロファイル",
                font: .headline,
                help: SettingHelp(
                    title: "仕上がりプロファイル",
                    reading: "しあがりぷろふぁいる",
                    description: "最終版の音量感、明るさ、押し出し方の出発点です。配信用、安全重視、音圧重視など、仕上げたい方向に合わせて選びます。"
                )
            )

            Menu {
                ForEach(MasteringProfile.allCases) { profile in
                    Button {
                        model.selectedMasteringProfile = profile
                    } label: {
                        if profile == model.selectedMasteringProfile {
                            Label(profile.title, systemImage: "checkmark")
                        } else {
                            Text(profile.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text("仕上がりプロファイル")
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(model.selectedMasteringProfile.title)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .accessibilityHidden(true)
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .velouraAdaptiveGlass(in: .rect(cornerRadius: 10), interactive: true)
                .contentShape(.rect(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .accessibilityLabel("仕上がりプロファイル")
            .accessibilityValue(model.selectedMasteringProfile.title)

            Text(model.selectedMasteringProfile.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(model.selectedMasteringProfile.presetTargetText)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
            Text("目標値に必ず合わせるものではなく、仕上げ意図を確認する目安です。")
                .font(.callout)
                .foregroundStyle(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 10) {
                    resetStatus
                    Spacer()
                    resetButton
                }

                VStack(alignment: .leading, spacing: 8) {
                    resetStatus
                    resetButton
                }
            }
        }
    }

    private var resetStatus: some View {
        Text(model.isUsingCustomMasteringSettings ? "手動調整中です" : "既定値を使用しています")
            .font(.body)
            .foregroundStyle(model.isUsingCustomMasteringSettings ? VelouraTextColors.orange : .secondary)
    }

    private var resetButton: some View {
        LiquidGlassActionButton(
            title: "プロファイルへ戻す",
            isDisabled: !model.isUsingCustomMasteringSettings,
            action: model.resetMasteringSettingsToProfile
        )
    }
}

private struct StemModeMasteringBasicControls: View {
    @Binding var settings: MasteringSettings

    var body: some View {
        VStack(spacing: DAWKnobMetrics.rowSpacing) {
            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                targetLoudness
                truePeak
            }
            .frame(width: DAWKnobMetrics.twoColumnWidth)

            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                dynamicsRetention
                finishingIntensity
            }
            .frame(width: DAWKnobMetrics.twoColumnWidth)
        }
        .frame(width: DAWKnobMetrics.twoColumnWidth, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var targetLoudness: some View {
        DAWKnobControl(
            title: "目標ラウドネス",
            help: SettingHelp(
                title: "目標ラウドネス",
                reading: "もくひょうらうどねす",
                description: "最終版で目指す平均音量の目安です。必ず一致させる数値ではなく、曲の自然さと安全上限を見ながら近づけます。"
            ),
            valueText: String(format: "%.1f LUFS", settings.targetLoudness),
            displayValueText: String(format: "%.1f", settings.targetLoudness),
            unitText: "LUFS",
            labels: ["余裕", "標準", "大きい"],
            value: $settings.targetLoudness,
            range: -18 ... -9,
            step: 0.1,
            dragValueScale: DAWKnobMetrics.targetLoudnessDragValueScale
        )
    }

    private var truePeak: some View {
        DAWKnobControl(
            title: "True Peak",
            help: SettingHelp(
                title: "True Peak",
                reading: "とぅるーぴーく",
                description: "書き出し後に歪まないようにするピーク上限です。値を上げるほど音量の余地は増えますが、安全余裕は小さくなります。"
            ),
            valueText: String(format: "%.1f dB", settings.peakCeilingDB),
            displayValueText: String(format: "%.1f", settings.peakCeilingDB),
            unitText: "dB",
            labels: ["安全", "標準", "攻める"],
            value: $settings.peakCeilingDB,
            range: -2 ... -0.2,
            step: 0.1
        )
    }

    private var dynamicsRetention: some View {
        DAWKnobControl(
            title: "ダイナミクス保持",
            help: SettingHelp(
                title: "ダイナミクス保持",
                reading: "だいなみくすほじ",
                description: "音の強弱や抑揚をどれだけ残すかです。上げるほどサビや演奏の動きが残りやすくなります。"
            ),
            valueText: percentText(settings.dynamicsRetention),
            displayValueText: percentNumberText(settings.dynamicsRetention),
            unitText: "%",
            labels: ["密度", "標準", "開放感"],
            value: $settings.dynamicsRetention,
            range: 0 ... 1,
            step: 0.01
        )
    }

    private var finishingIntensity: some View {
        DAWKnobControl(
            title: "仕上げの強さ",
            help: SettingHelp(
                title: "仕上げの強さ",
                reading: "しあげのつよさ",
                description: "マスタリング処理を全体的にどれくらい効かせるかです。上げるほど前に出ますが、素材によっては自然さが減る場合があります。"
            ),
            valueText: percentText(settings.finishingIntensity),
            displayValueText: percentNumberText(settings.finishingIntensity),
            unitText: "%",
            labels: ["自然", "標準", "前に出す"],
            value: $settings.finishingIntensity,
            range: 0 ... 1,
            step: 0.01
        )
    }
}

private struct StemModeMasteringToneControls: View {
    @Binding var settings: MasteringSettings

    var body: some View {
        VStack(spacing: DAWKnobMetrics.rowSpacing) {
            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                lowShelfGain
                lowMidGain
                presenceGain
            }
            .frame(width: DAWKnobMetrics.threeColumnWidth)

            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                highShelfGain
                deEsserAmount
            }
            .frame(width: DAWKnobMetrics.twoColumnWidth)
        }
        .frame(width: DAWKnobMetrics.threeColumnWidth, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var lowShelfGain: some View {
        DAWKnobControl(
            title: "低域",
            help: SettingHelp(
                title: "低域",
                reading: "ていいき",
                description: "キックやベースの土台になる低い帯域です。上げるほど太くなりますが、上げすぎると重く聞こえる場合があります。"
            ),
            valueText: dbText(settings.lowShelfGain),
            displayValueText: decimalText(settings.lowShelfGain),
            unitText: "dB",
            labels: ["軽い", "標準", "太い"],
            value: $settings.lowShelfGain,
            range: 0 ... 2.5,
            step: 0.01
        )
    }

    private var lowMidGain: some View {
        DAWKnobControl(
            title: "中低域",
            help: SettingHelp(
                title: "中低域",
                reading: "ちゅうていいき",
                description: "音の厚みやこもりに関わる帯域です。下げるとすっきりし、上げると厚みが増えます。"
            ),
            valueText: dbText(settings.lowMidGain),
            displayValueText: decimalText(settings.lowMidGain),
            unitText: "dB",
            labels: ["すっきり", "標準", "厚い"],
            value: $settings.lowMidGain,
            range: -1.2 ... 1.2,
            step: 0.01
        )
    }

    private var presenceGain: some View {
        DAWKnobControl(
            title: "プレゼンス",
            help: SettingHelp(
                title: "プレゼンス",
                reading: "ぷれぜんす",
                description: "声や主旋律が前に出る感じに関わる帯域です。上げるほど明瞭になりますが、上げすぎると耳に近く感じる場合があります。"
            ),
            valueText: dbText(settings.presenceGain),
            displayValueText: decimalText(settings.presenceGain),
            unitText: "dB",
            labels: ["奥", "標準", "前"],
            value: $settings.presenceGain,
            range: 0 ... 1.2,
            step: 0.01
        )
    }

    private var highShelfGain: some View {
        DAWKnobControl(
            title: "空気感",
            help: SettingHelp(
                title: "空気感",
                reading: "くうきかん",
                description: "息感や高域の伸びに関わる帯域です。上げるほど明るく開いた印象になります。"
            ),
            valueText: dbText(settings.highShelfGain),
            displayValueText: decimalText(settings.highShelfGain),
            unitText: "dB",
            labels: ["丸い", "標準", "明るい"],
            value: $settings.highShelfGain,
            range: 0 ... 2.5,
            step: 0.01
        )
    }

    private var deEsserAmount: some View {
        DAWKnobControl(
            title: "ハーシュネス抑制",
            help: SettingHelp(
                title: "ハーシュネス抑制",
                reading: "はーしゅねすよくせい",
                description: "サ行や耳に痛い高域を抑える量です。強くしすぎると抜けや明るさも弱くなる場合があります。"
            ),
            valueText: percentText(settings.deEsserAmount),
            displayValueText: percentNumberText(settings.deEsserAmount),
            unitText: "%",
            labels: ["弱い", "標準", "強い"],
            value: $settings.deEsserAmount,
            range: 0 ... 1,
            step: 0.01
        )
    }
}

private struct StemModeMasteringAdvancedControls: View {
    @Binding var settings: MasteringSettings

    var body: some View {
        VStack(spacing: DAWKnobMetrics.rowSpacing) {
            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                deEsserThreshold
                stereoWidth
                saturationAmount
            }
            .frame(width: DAWKnobMetrics.threeColumnWidth)

            StemModeMasteringCompressorControls(
                title: "低域コンプ",
                help: SettingHelp(
                    title: "低域コンプ",
                    reading: "ていいきこんぷ",
                    description: "低域の音量差を整える処理です。キックやベースの暴れを抑え、低域の量感を安定させます。"
                ),
                shortTitle: "低域",
                settings: $settings.multibandCompression.low
            )

            StemModeMasteringCompressorControls(
                title: "中域コンプ",
                help: SettingHelp(
                    title: "中域コンプ",
                    reading: "ちゅういきこんぷ",
                    description: "声や主旋律の中心帯域を整える処理です。前に出る感じと聞きやすさに関わります。"
                ),
                shortTitle: "中域",
                settings: $settings.multibandCompression.mid
            )

            StemModeMasteringCompressorControls(
                title: "高域コンプ",
                help: SettingHelp(
                    title: "高域コンプ",
                    reading: "こういきこんぷ",
                    description: "明るさや刺激感の出過ぎを整える処理です。高域の動きを落ち着かせます。"
                ),
                shortTitle: "高域",
                settings: $settings.multibandCompression.high
            )
        }
        .frame(width: DAWKnobMetrics.threeColumnWidth, alignment: .center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var deEsserThreshold: some View {
        DAWKnobControl(
            title: "ハーシュネス検出",
            help: SettingHelp(
                title: "ハーシュネス検出",
                reading: "はーしゅねすけんしゅつ",
                description: "耳に痛い高域を検出する基準です。敏感にすると小さな刺さりも拾いますが、明るい音楽成分も対象になりやすくなります。"
            ),
            valueText: String(format: "%.1f dB", settings.deEsserThresholdDB),
            displayValueText: String(format: "%.1f", settings.deEsserThresholdDB),
            unitText: "dB",
            labels: ["敏感", "標準", "鈍い"],
            value: $settings.deEsserThresholdDB,
            range: -36 ... -18,
            step: 0.1,
            dragValueScale: DAWKnobMetrics.deEsserThresholdDragValueScale
        )
    }

    private var stereoWidth: some View {
        DAWKnobControl(
            title: "ステレオ幅",
            help: SettingHelp(
                title: "ステレオ幅",
                reading: "すてれおはば",
                description: "左右への広がり具合です。今の実装では低域を広げず、中高域を中心に広がりを調整します。"
            ),
            valueText: decimalText(settings.stereoWidth),
            displayValueText: decimalText(settings.stereoWidth),
            unitText: nil,
            labels: ["狭い", "標準", "広い"],
            value: $settings.stereoWidth,
            range: 0.8 ... 1.4,
            step: 0.01
        )
    }

    private var saturationAmount: some View {
        DAWKnobControl(
            title: "倍音密度",
            help: SettingHelp(
                title: "倍音密度",
                reading: "ばいおんみつど",
                description: "音に厚みや存在感を加える量です。上げるほど濃くなりますが、上げすぎると透明感が減る場合があります。"
            ),
            valueText: decimalText(settings.saturationAmount),
            displayValueText: decimalText(settings.saturationAmount),
            unitText: nil,
            labels: ["透明", "標準", "濃い"],
            value: $settings.saturationAmount,
            range: 0 ... 0.45,
            step: 0.01
        )
    }
}

private struct StemModeMasteringCompressorControls: View {
    let title: String
    let help: SettingHelp
    let shortTitle: String
    @Binding var settings: BandCompressorSettings

    var body: some View {
        VStack(spacing: 6) {
            StemModeMasteringTitleWithHelp(
                title: title,
                font: .callout.bold(),
                help: help
            )
            .frame(width: DAWKnobMetrics.twoColumnWidth, alignment: .leading)

            HStack(alignment: .top, spacing: DAWKnobMetrics.columnSpacing) {
                threshold
                ratio
            }
            .frame(width: DAWKnobMetrics.twoColumnWidth)
        }
        .frame(width: DAWKnobMetrics.twoColumnWidth, alignment: .center)
    }

    private var threshold: some View {
        DAWKnobControl(
            title: "\(shortTitle) Threshold",
            help: SettingHelp(
                title: "\(title) Threshold",
                reading: "すれっしょるど",
                description: "コンプレッサーが反応し始める音量です。値を低くするほど、より小さな音から圧縮が始まります。"
            ),
            valueText: String(format: "%.1f dB", settings.thresholdDB),
            displayValueText: String(format: "%.1f", settings.thresholdDB),
            unitText: "dB",
            labels: ["深く効く", "標準", "浅く効く"],
            value: $settings.thresholdDB,
            range: -36 ... -12,
            step: 0.1,
            dragValueScale: DAWKnobMetrics.compressorThresholdDragValueScale
        )
    }

    private var ratio: some View {
        DAWKnobControl(
            title: "\(shortTitle) Ratio",
            help: SettingHelp(
                title: "\(title) Ratio",
                reading: "れしお",
                description: "しきい値を超えた音をどれくらい圧縮するかです。値を上げるほど強く抑えます。"
            ),
            valueText: decimalText(settings.ratio),
            displayValueText: decimalText(settings.ratio),
            unitText: nil,
            labels: ["自然", "標準", "強く圧縮"],
            value: $settings.ratio,
            range: 1.1 ... 4,
            step: 0.01
        )
    }
}

private struct StemModeMasteringWarnings: View {
    let warnings: [String]

    var body: some View {
        ZStack(alignment: .topLeading) {
            normalNotice
                .hidden()
            warningMessages(MasteringSettings.allAggressiveSettingWarnings)
                .hidden()

            if warnings.isEmpty {
                normalNotice
            } else {
                warningMessages(warnings)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .velouraAdaptiveGlass(in: .rect(cornerRadius: 10))
    }

    private var normalNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("現在の音量とピーク上限は安全な範囲です。", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("必要に応じて試聴しながら微調整してください。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func warningMessages(_ messages: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(messages, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(VelouraTextColors.orange)
            }
        }
    }
}

private struct StemModeMasteringTitleWithHelp: View {
    let title: String
    let font: Font
    let help: SettingHelp?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(font)
            if let help {
                TermHelpButton(
                    title: help.title,
                    reading: help.reading,
                    description: help.description
                )
            }
        }
    }
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

private func dbText(_ value: Float) -> String {
    String(format: "%.2f dB", value)
}
