import Foundation

/// Translates only known log templates at the point of presentation.
/// The saved diagnostic entries keep their original wording and values.
enum ProcessingLogLineLocalization {
    // Some diagnostic lines combine fixed Japanese labels with measured values.
    // Match their fixed fragments once, then resolve each match through the catalog.
    private static let fragmentKeys: [String] = [
        "高域修復/Oversampling: 4倍処理を適用",
        "倍音/Oversampling: 4倍処理を適用",
        "空気感/Oversampling: 4倍処理を適用",
        "読み込み", "原音参照読み込み", "低域ノイズ", "ノイズ除去", "サ行保護", "通常高域戻し",
        "再解析", "解析補助", "高域修復", "シマー制限", "補正後高域保持", "低中域残り確認",
        "低中域残り", "候補選定", "低域位相確認", "低域位相", "ピーク保護", "書き出し",
        "音色", "ディエッサー", "ダイナミクス", "倍音", "空気感", "広がり", "ラウドネス",
        "高域戻りガード", "ノイズ戻りガード", "保存", "中低域調整", "高域調整", "密度調整",
        "マスタリング", "補正", "計測", "入力", "結果", "処理前", "処理後", "適用量",
        "実測変化", "理由", "設定値と入力帯域差から算出", "設定", "過剰なし",
        "high shelf設定と入力帯域差から算出", "入力の高域不足から算出しサ行区間を除外",
        "高域不足と既存の倍音設定から算出", "空気感の補正が必要", "直前再測定",
        "中域", "高域", "ラウドネス方針", "聴きやすく整える", "目安差", "適用",
        "早期終了", "高域戻りガードをスタンダードマスタリングでは使わない",
        "高域保持基準", "最終ノイズ上限", "高域保持（音声処理1回）", "最終音量復帰",
        "最終ノイズ確認", "最終低中域保護", "最終音量上限", "秒", "区間",
        "自動", "実験Metal", "入力にも存在し、補正後に一部増加",
        "対象時間 約", "セル", "対象", "内部相殺指標", "モノラル低域損失",
        "ポイント減少・モノラル低域損失", "改善・安全検証通過", "修復後", "補正後",
        "ドラム", "ベース", "その他", "ボーカル", "ギター", "ピアノ",
        "既存の補正後高域保持を使用", "既存の処理前後mud増加guardを使用",
        "Stem個別では使わず再ミックス後の既存マスタリングで制御",
        "Stem役割保護によりDSP差分を弱化", "工程省略・guard未評価",
        "DSP差分保持", "平均", "最小", "Protected components: ",
        "アタック、シンバルの余韻、トランジェント",
        "50/60 Hz付近の音程成分、低域位相、倍音、基音",
        "アンビエンス、ステレオ感、残響、空間",
        "サ行、フォルマント、倍音、声の芯、子音、息",
        "raw基準トランジェント回復", "補正で失われたドラムアタックだけをraw包絡線内で回復",
        "raw再ミックス", "再ミックス", "を入力2mixと検証します", "の検証が完了しました",
        "自動判定根拠", "rawとの差", "左右差", "中央", "raw空間成分の減少",
        "のgain", "のpan", "のreverb send", "自動値", "適用値", "衝突判定値",
        "ドラム／ベース", "ボーカル／その他", "ドラム→ベース衝突回避",
        "ボーカル→その他衝突回避", "ボーカル／伴奏（その他／ギター／ピアノ）",
        "ボーカル→伴奏（その他／ギター／ピアノ）衝突回避", "有効", "無効", "共通reverb",
        "raw／補正済みStemの安全確認を行います",
        "補正後の相対変化を基準にStem別gainを適用します",
        "Stem別gainを適用しました", "実測衝突区間だけdynamic EQ／duckingを適用します",
        "条件付き帯域制御を完了しました", "rawから変化した左右バランスだけを補正します",
        "Stem別panを適用しました", "pan後の各Stemから共通reverbへのsendを生成します",
        "Stem別reverb sendを生成しました", "一つの共通reverb returnを生成します",
        "共通reverb returnを生成しました", "dry Stem合計へ共通reverb returnを加算します",
        "dry／reverb加算を完了しました", "【", "】", "（", "）", "、", "〜", "・",
    ] + StemRoleProtectedComponent.allCases.map(\.stemModeDisplayTitle)
      + MasteringProfile.allCases.map(\.title)

    private static let fragmentExpression: NSRegularExpression = {
        let alternatives = Set(fragmentKeys).sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return try! NSRegularExpression(pattern: alternatives)
    }()
    private static let templates: [String] = [
        "表示解析/計測: %@: %@秒",
        "実行契約: %@ / %@Stem / %@",
        "%@で%@Stem分離を開始します",
        "%@で%@Stem分離が完了しました",
        "%@を解析・ノイズ測定します",
        "%@の解析・ノイズ測定が完了しました",
        "%@の補正後音声を解析・ノイズ測定しました",
        "%@の補正結果を保存・検証します",
        "%@の補正結果を保存・検証しました",
        "補正済み%@Stemの保存を確認しました",
        "分離後%@Stemを純粋加算します",
        "補正済み%@Stemをgain・pan・reverbなしで純粋加算します",
        "純粋加算安全確認: %@をraw Stemへ戻しました",
        "再ミックス安全確認: %@をraw Stemへ戻しました",
        "補正済み%@Stemと補正後を一時保存しました。再ミックスは別操作で開始します。",
        "補正済み%@Stemから再ミックス段を開始します。",
        "再ミックスを停止しました。補正済みStem一式と補正後は保持しています: %@",
        "マスタリング段を停止しました。Stem再ミックスは保持しています: %@",
        "最終音量復帰: +%@ dB",
        "最終音量上限: %@ / %@ の上限内へ調整",
        "最終音量下限: %@ / %@ の下限内へ調整",
        "最終音量上限: %@ の範囲内",
        "ノイズ戻り/判定: %@ +%@ dB",
        "ノイズ戻り: 緊急%@上限 %@",
        "ノイズ戻り: 緊急%@上限を優先 %@",
        "ノイズ戻り: 高域保護 mix %@",
        "補正後高域保持: ノイズ/超高域戻り抑制 mix %@",
        "低中域残り: こもり悪化を抑制 %@ dB",
        "密度調整/制限: 強弱を守るため圧縮mix %@",
        "解析/%@: %@",
        "診断書き出し失敗: %@/%@ - %@",
        "Stem役割保護: %@ = %@",
        "Stem役割保護詳細: %@/%@",
        "ルート/補正: %@ = %@ - %@",
        "ルート/マスタリング: %@ = %@ - %@",
        "補正後高域保持/%@: +%@ dB",
        "ルート/補正/実行工程数: %@/%@",
        "ルート/補正/スキップ工程数: %@/%@",
        "ルート/マスタリング/実行工程数: %@/%@",
        "ルート/マスタリング/スキップ工程数: %@/%@",
        "低域ノイズ/測定回数: %@",
        "低中域残り/測定回数: %@",
        "サ行保護/通常高域戻し/測定回数: %@",
        "シマー制限/測定回数: %@",
        "シマー制限/最終確認: %@",
        "ノイズ戻り/軽量判定回数: %@",
        "ノイズ戻り/最終確認回数: %@",
        "補正後高域保持/測定回数: %@",
        "ノイズ戻り/軽量判定: %@",
        "ノイズ戻り/軽量測定: %@",
        "シマー制限/測定: %@",
        "シマー制限/軽量測定: %@",
        "ノイズ戻り: 緊急上限確認 %@",
        "ノイズ戻り: 緊急サ行上限 %@",
        "低域位相/原因: %@",
        "低域位相/結果: %@",
        "Stem役割保護: %@",
        "役割別保護: %@",
        "保護対象: %@",
        "対象区間: %@",
        "理由: %@",
        "解析モード: %@",
        "合計: %@",
        "診断書き出し: %@",
        "ラウドネス目標: 設定値 %@",
        "ノイズ除去/10-16kHzチラつき: %@",
        "ノイズ除去/12kHz以上: %@",
        "ノイズ除去/16kHz以上: %@",
        "ノイズ除去/18kHz以上: %@",
    ]

    private static let rules: [(template: String, expression: NSRegularExpression)] =
        templates.compactMap { template in
            let pattern = "^" + template.components(separatedBy: "%@")
                .map(NSRegularExpression.escapedPattern(for:))
                .joined(separator: "(.+?)") + "$"
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (template, expression)
        }

    static func string(_ source: String) -> String {
        guard AppLanguageSettings.locale.language.languageCode?.identifier == "en" else {
            return source
        }
        guard containsJapanese(source) else {
            return source
        }
        let exact = AppLanguageSettings.string(source)
        if exact != source { return translateFragments(exact) }

        let fragmentResult = translateFragments(source)
        if !containsJapanese(fragmentResult) { return fragmentResult }

        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        for rule in rules {
            guard let match = rule.expression.firstMatch(in: source, options: [], range: fullRange) else { continue }
            let values = (1..<match.numberOfRanges).compactMap { index -> String? in
                guard let range = Range(match.range(at: index), in: source) else { return nil }
                return AppLanguageSettings.string(String(source[range]))
            }
            guard values.count == match.numberOfRanges - 1 else { continue }
            return translateFragments(String(
                format: AppLanguageSettings.string(rule.template),
                locale: AppLanguageSettings.locale,
                arguments: values.map { $0 as CVarArg }
            ))
        }

        return fragmentResult
    }

    private static func containsJapanese(_ source: String) -> Bool {
        source.unicodeScalars.contains {
            (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value)
        }
    }

    private static func translateFragments(_ source: String) -> String {
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = fragmentExpression.matches(in: source, range: range)
        guard !matches.isEmpty else { return source }
        var result = source
        for match in matches.reversed() {
            guard let sourceRange = Range(match.range, in: source),
                  let resultRange = Range(match.range, in: result) else { continue }
            let fragment = String(source[sourceRange])
            let translation = AppLanguageSettings.string(fragment)
            let rendered: String
            switch fragment {
            case "秒": rendered = " " + translation
            case "区間": rendered = " " + AppLanguageSettings.string("区間（複数）")
            case "平均", "最小": rendered = translation + " "
            default: rendered = translation
            }
            result.replaceSubrange(resultRange, with: rendered)
        }
        return result
    }
}
