import Foundation

enum CorrectionSettingControlID: String, CaseIterable, Hashable {
    case correctionIntensity
    case originalRetention
    case coreProtection
    case lowCleanup
    case lowMidCleanup
    case presenceRepair
    case airRepair
    case highNaturalness
    case noiseDetectionSensitivity
    case harmonicRepairAmount
    case foldoverRepairAmount
    case stereoProtection
}

struct CorrectionSettingControlDefinition {
    let id: CorrectionSettingControlID
    let title: String
    let help: SettingHelp
    let labels: [String]
    let keyPath: WritableKeyPath<CorrectionSettings, Float>
    let range: ClosedRange<Float>
    let step: Float
}

/// Standard Modeで実際に使われている12設定の意味・範囲・刻みを、
/// 通常モード側を変更せずStem Modeへ写すためのStem専用表示契約です。
enum CorrectionSettingControlCatalog {
    static var basic: [CorrectionSettingControlDefinition] {
        [correctionIntensity, originalRetention, coreProtection]
    }

    static var repair: [CorrectionSettingControlDefinition] {
        [lowCleanup, lowMidCleanup, presenceRepair, airRepair, highNaturalness]
    }

    static var advanced: [CorrectionSettingControlDefinition] {
        [
            noiseDetectionSensitivity,
            harmonicRepairAmount,
            foldoverRepairAmount,
            stereoProtection
        ]
    }

    static var all: [CorrectionSettingControlDefinition] {
        basic + repair + advanced
    }

    static var correctionIntensity: CorrectionSettingControlDefinition {
        definition(
            id: .correctionIntensity,
            title: "補正の強さ",
            reading: "ほせいのつよさ",
            description: "ノイズ低減を全体的にどれくらい効かせるかです。上げるほどノイズは減りやすくなりますが、音の細かい余韻も変わりやすくなります。",
            labels: ["弱い", "標準", "強い"],
            keyPath: \.correctionIntensity
        )
    }

    static var originalRetention: CorrectionSettingControlDefinition {
        definition(
            id: .originalRetention,
            title: "原音保持",
            reading: "げんおんほじ",
            description: "入力音声の雰囲気や質感をどれだけ残すかです。上げるほど元の音の印象を守りやすくなります。",
            labels: ["整える", "標準", "残す"],
            keyPath: \.originalRetention
        )
    }

    static var coreProtection: CorrectionSettingControlDefinition {
        definition(
            id: .coreProtection,
            title: "芯保護",
            reading: "しんほご",
            description: "声や主旋律の中心になる帯域を守る量です。上げるほど音の中心が細くなりにくくなります。",
            labels: ["整理", "標準", "芯を守る"],
            keyPath: \.coreProtection
        )
    }

    static var lowCleanup: CorrectionSettingControlDefinition {
        definition(
            id: .lowCleanup,
            title: "低域整理",
            reading: "ていいきせいり",
            description: "低いゴロゴロしたノイズや不要な低音を整理する量です。上げるほど低域の濁りを抑えます。",
            labels: ["弱い", "標準", "強い"],
            keyPath: \.lowCleanup
        )
    }

    static var lowMidCleanup: CorrectionSettingControlDefinition {
        definition(
            id: .lowMidCleanup,
            title: "中低域整理",
            reading: "ちゅうていいきせいり",
            description: "300Hzから1kHz付近のこもりを整理する量です。上げるほど暗さや詰まりを抑えます。",
            labels: ["弱い", "標準", "強い"],
            keyPath: \.lowMidCleanup
        )
    }

    static var presenceRepair: CorrectionSettingControlDefinition {
        definition(
            id: .presenceRepair,
            title: "プレゼンス修復",
            reading: "ぷれぜんすしゅうふく",
            description: "声や主旋律が前に出る帯域を補う量です。補正で引っ込みすぎた時に戻します。",
            labels: ["控えめ", "標準", "修復"],
            keyPath: \.presenceRepair
        )
    }

    static var airRepair: CorrectionSettingControlDefinition {
        definition(
            id: .airRepair,
            title: "エアー修復",
            reading: "えあーしゅうふく",
            description: "息感や空気感に関わる高域を補う量です。高域ノイズではなく、音楽成分として残したい明るさを戻します。",
            labels: ["控えめ", "標準", "修復"],
            keyPath: \.airRepair
        )
    }

    static var highNaturalness: CorrectionSettingControlDefinition {
        definition(
            id: .highNaturalness,
            title: "高域の自然さ",
            reading: "こういきのしぜんさ",
            description: "高域が不自然に硬くならないように整える量です。上げるほど明るさより自然さを優先します。",
            labels: ["明るさ", "標準", "自然"],
            keyPath: \.highNaturalness
        )
    }

    static var noiseDetectionSensitivity: CorrectionSettingControlDefinition {
        definition(
            id: .noiseDetectionSensitivity,
            title: "ノイズ検出しきい値",
            reading: "のいずけんしゅつしきいち",
            description: "どれくらい小さなノイズまで検出するかです。敏感にすると細かいノイズを拾いますが、音楽成分も対象になりやすくなります。",
            labels: ["鈍い", "標準", "敏感"],
            keyPath: \.noiseDetectionSensitivity
        )
    }

    static var harmonicRepairAmount: CorrectionSettingControlDefinition {
        definition(
            id: .harmonicRepairAmount,
            title: "高域補完量",
            reading: "こういきほかんりょう",
            description: "補正で弱くなった高域の倍音を補う量です。上げるほど明るさを戻します。",
            labels: ["少ない", "標準", "多い"],
            keyPath: \.harmonicRepairAmount
        )
    }

    static var foldoverRepairAmount: CorrectionSettingControlDefinition {
        definition(
            id: .foldoverRepairAmount,
            title: "foldover補完量",
            reading: "ふぉーるどおーばーほかんりょう",
            description: "高域の不足を別の帯域情報から補う量です。上げるほど高域の伸びを戻しますが、不自然な明るさが出る場合があります。",
            labels: ["少ない", "標準", "多い"],
            keyPath: \.foldoverRepairAmount
        )
    }

    static var stereoProtection: CorrectionSettingControlDefinition {
        definition(
            id: .stereoProtection,
            title: "ステレオ保護",
            reading: "すてれおほご",
            description: "左右の広がりや位相の違いを守る量です。上げるほど補正で広がりが崩れにくくなります。",
            labels: ["整理", "標準", "保護"],
            keyPath: \.stereoProtection
        )
    }

    private static func definition(
        id: CorrectionSettingControlID,
        title: String,
        reading: String,
        description: String,
        labels: [String],
        keyPath: WritableKeyPath<CorrectionSettings, Float>
    ) -> CorrectionSettingControlDefinition {
        CorrectionSettingControlDefinition(
            id: id,
            title: title,
            help: SettingHelp(
                title: title,
                reading: reading,
                description: description
            ),
            labels: labels,
            keyPath: keyPath,
            range: 0 ... 1,
            step: 0.01
        )
    }
}
