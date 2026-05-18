# 内部判定監査表

目的: 表示ではなく、補正とマスタリングの内部処理で音を変える判定を確認する。

| 項目 | 使う場所 | 計算元 | しきい値 | 失敗時の扱い | 音への影響 | 危険度 | 対応 |
|---|---|---|---|---|---|---|---|
| 低域整理の実行判定 | `CorrectionRoutePlan.make` | `rumble`, `hum` | rumble < -12 dB かつ hum < 5 dB ならスキップ | 測定値なしはスキップしない | 低域処理の有無が変わる | 高 | 測定不能時に実行へ倒す |
| サ行保護の軽量判定 | `CorrectionRoutePlan.make` | `sibilance`, `shimmerRatio` | sibilance < 7 dB かつ shimmerRatio < 0.18 なら軽量 | 測定値なしは通常実行 | 高域保護の強さが変わる | 高 | 測定不能時に軽量化しない |
| シマー制限の実行判定 | `CorrectionRoutePlan.make` | `hiss`, `shimmer`, `hasShimmer` | hiss < -58 dB かつ shimmer < -46 dB かつ短時間シマーなしならスキップ | 測定値なしは実行 | 短時間シマー抑制の有無が変わる | 高 | 測定不能時や短時間シマーありではスキップしない |
| 低中域整理の実行判定 | `CorrectionRoutePlan.make` | `mud` | mud < -9 dB ならスキップ | 測定値なしは実行 | 低中域の削り方が変わる | 中 | 測定不能時にスキップしない |
| ノイズ除去本体 | `SpectralGateDenoiser` | STFT、静かなフレーム、帯域別マスク | profile と詳細設定から算出 | 空音声は処理なし | 音全体のノイズと質感が変わる | 高 | 現状維持、しきい値をポリシー化対象外に分類 |
| シマー制限の最大削り量 | `ShimmerPeakLimiter` | `shimmer` | 2 / 3 / 4 dB | 参照値欠損時は再測定 | 短時間のチラつきだけを抑え、持続する高域を守る | 高 | 8〜14kHzの短時間イベントだけを対象にする |
| マスタリングのディエッサー判定 | `MasteringRoutePlan.make` | `harshnessScore`, `sibilance` | harshness < 0.24 かつ sibilance < 7 dB ならスキップ | 測定値なしは実行 | 刺さり抑制の有無が変わる | 高 | 測定不能時にスキップしない |
| 高域戻りガード判定 | `MasteringRoutePlan.make` | `harshnessScore`, `highShelfGain`, `shimmer` | harshness < 0.30 かつ highShelfGain < 0.34 かつ shimmer < -44 dB ならスキップ | 測定値なしは実行 | 高域抑制の有無が変わる | 高 | 測定不能時にスキップしない |
| ノイズ戻りガード判定 | `MasteringRoutePlan.make` | `hiss`, `sibilance`, `shimmer` | hiss < -58 dB、sibilance < 7 dB、shimmer < -46 dB なら軽量 | 測定値なしは通常実行 | マスタリング後のノイズ抑制が変わる | 高 | 測定不能時に軽量化しない |
| ノイズ戻りガードのヒス削り | `MasteringProcessor.applyNoiseReturnGuard` | 補正前と現在の `hiss` | allowedReturn -2.0 dB、倍率 2.2、最大 18 dB | 参照値欠損時は再測定 | 明るさとヒス量が変わる | 高 | 4.0倍 / 36 dB から抑制 |
| ラウドネス | `MasteringProcessor.applyLoudness` | `MasteringAnalysisService.integratedLoudness` | profile の targetLoudness | 空音声は -70 扱い | 最終音量が変わる | 高 | 現状維持、テストあり |
| ピーク保護 | `PeakSafetyLimiter`, `applyLookaheadLimiter` | oversampled peak | 補正 -1 dB、マスタリング profile ceiling | 空音声は処理なし | クリップ防止 | 高 | 現状維持、テストあり |
| ノイズチェックの警告 | `NoiseCheckReportService` | `NoiseMeasurementService` | `InternalAudioJudgementPolicy.noiseSeverityLimits` | 行がなければ表示しない | 音は変えない | 低 | しきい値定義を1箇所に集約 |

今回の修正判断:

- 測定値なしを `-120 dB` として扱う経路は修正対象。
- `hiss 4.0倍` と最大 `36 dB` はマスタリングで音を削りすぎるため修正対象。
- シマー制限は、最大 `2 / 3 / 4 dB` の短時間イベント処理にして、広い高域を一括で下げない。
- 表示専用のグラフ計算は今回の修正対象外。
