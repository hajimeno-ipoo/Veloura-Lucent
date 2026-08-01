# Stem分離モデル比較検証結果

## 結論

MUSDB公式7秒サンプルのtest subset 50曲を正解Stemと直接比較した結果、BS-RoFormer-SWはHTDemucsより高いStem分離精度を示した。

- 4Stem総合SDRは、BS-RoFormer-SWが`9.9718 dB`、HTDemucsが`8.2463 dB`
- 同じ曲同士で比較した総合SDR差の中央値は、BS-RoFormer-SWが`+1.5990 dB`
- BS-RoFormer-SWが総合SDRで上回った曲は50曲中45曲
- ユーザー指定曲では、BS-RoFormer-SWはHTDemucsより約1.82倍遅く、最大メモリ使用量は約1.57倍だった
- M3 Pro・18GBで両モデルとも処理を完了し、測定中のスワップは0だった

したがって、Stem精度を理由にBS-RoFormer-SWの採用検討を中止する根拠はない。速度とメモリの増加は、精度とは別の採用判断材料として扱う。

## 検証日と対象

- 検証日：2026-07-30
- 実行機：Apple M3 Pro、メモリ18GB
- 比較モデル：
  - BS-RoFormer-SW
  - HTDemucs
- 実音源：
  - `Tests/Fixtures/Sample_audio/星屑のシンパシー.wav`
  - 長さ：約246.2秒

## Stem精度の評価条件

### 正解Stem

- データ：MUSDB公式7秒サンプル
- 対象：test subset 50曲
- 1曲の長さ：約6.8秒
- 形式：44.1kHz、ステレオ
- 正解Stem：
  - `vocals`
  - `drums`
  - `bass`
  - `other`

公式資料：

- [sigsep/sigsep-mus-db](https://github.com/sigsep/sigsep-mus-db)
- [sigsep/sigsep-mus-eval](https://github.com/sigsep/sigsep-mus-eval)

### 両モデルへの入力

両モデルへ、各曲の同一2mixを入力した。

BS-RoFormer-SWの6Stem出力は、次のように4Stemへ対応させた。

| 4Stem評価対象 | BS-RoFormer-SW出力 |
|---|---|
| `vocals` | `vocals` |
| `drums` | `drums` |
| `bass` | `bass` |
| `other` | `other + guitar + piano` |

`other`は、`other`、`guitar`、`piano`を無係数のFloat32加算で合成した。音量正規化や係数調整は加えていない。

### 評価方法

- 評価ツール：`museval 0.4.1`
- 評価方式：BSS Eval v4
- window：1.0秒
- hop：1.0秒
- 各曲の値：有限値フレームの中央値
- モデル間比較：同一曲の対応差、勝敗数、全50曲の中央値
- 統計確認：
  - Wilcoxon符号付順位検定、両側
  - 対応差中央値のブートストラップ95%信頼区間
  - 20,000回、乱数seed `20260730`

## Stem精度の結果

SDRは、正解Stemに対する分離結果全体の近さを示す。値が高いほど正解Stemに近い。

| Stem | BS-RoFormer-SW SDR中央値 | HTDemucs SDR中央値 | 同一曲SDR差の中央値 | BS勝利数 | HT勝利数 | 差の95%信頼区間 | p値 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `vocals` | 11.5432 dB | 9.0494 dB | +2.5065 dB | 49 | 1 | +2.0301〜+2.9693 dB | 3.55e-15 |
| `drums` | 10.7801 dB | 9.6435 dB | +1.3491 dB | 48 | 2 | +1.1791〜+1.6587 dB | 6.34e-11 |
| `bass` | 9.3041 dB | 9.4605 dB | +0.8093 dB | 37 | 13 | +0.4120〜+1.0437 dB | 0.00996 |
| `other` | 7.7494 dB | 5.7285 dB | +1.9976 dB | 43 | 7 | +1.4998〜+2.2572 dB | 9.75e-08 |
| 4Stem総合 | 9.9718 dB | 8.2463 dB | +1.5990 dB | 45 | 5 | +1.2939〜+1.8512 dB | 3.88e-10 |

`bass`は各モデル単独の中央値ではHTDemucsが`0.1564 dB`高い。一方、同じ曲同士を対応させた比較では、BS-RoFormer-SWが50曲中37曲で勝ち、対応差の中央値はBS-RoFormer-SW側へ`+0.8093 dB`だった。モデル差の判断には、曲構成の影響を避けられる同一曲の対応差と勝敗数を使用する。

### SIR・SAR・ISR

- SIR：他Stemの混入の少なさ
- SAR：分離による人工的な破綻の少なさ
- ISR：ステレオ空間の再現性
- いずれも値が高いほど良い

| Stem | BS SIR | HT SIR | BS SAR | HT SAR | BS ISR | HT ISR |
|---|---:|---:|---:|---:|---:|---:|
| `vocals` | 17.2821 | 14.2855 | 11.3744 | 9.3678 | 18.5820 | 14.4149 |
| `drums` | 15.8246 | 15.4245 | 10.5492 | 10.4888 | 18.1645 | 14.9073 |
| `bass` | 16.1432 | 15.7988 | 11.1235 | 10.4512 | 14.5192 | 13.9910 |
| `other` | 12.3681 | 8.9450 | 8.1968 | 6.7335 | 12.4655 | 10.0653 |
| 4Stem総合 | 14.7586 | 13.4190 | 10.0802 | 9.2193 | 15.1650 | 12.9160 |

表内の単位はdB。

## 実音源での速度とメモリ

対象：

`Tests/Fixtures/Sample_audio/星屑のシンパシー.wav`

| 項目 | BS-RoFormer-SW | HTDemucs | BS / HT |
|---|---:|---:|---:|
| 処理時間 | 65.40秒 | 35.95秒 | 約1.82倍 |
| 最大メモリ使用量 | 10,422,405,616 bytes | 6,620,990,560 bytes | 約1.57倍 |
| 最大メモリ使用量・10進GB | 約10.42GB | 約6.62GB | 約1.57倍 |
| スワップ | 0 | 0 | 同じ |

この結果から直接確認できることは、今回の1曲では両モデルともM3 Pro・18GBで処理を完了し、BS-RoFormer-SWの方が遅く、使用メモリが多かったことまでである。複数回実行時や別の長時間音源での安定性は未確認。

## 実行条件

### BS-RoFormer-SW

- Python：3.13.6
- `mlx-audio-separator`：0.1.5
- MLX：0.31.2
- モデル：`BS-Roformer-SW.ckpt`
- speed mode：`latency_safe_v3`
- normalization：1.0
- 出力：WAV

### HTDemucs

- 実行系：`demucs-mlx-swift`のrelease build
- モデル：`htdemucs`
- segment：7.8
- overlap：0.25
- shifts：2
- seed：`20260730`
- batch size：1
- dtype：Float32

## 判断に使用しない値

次の値は、正解Stemとの一致を示さないため、Stem精度の代用には使用しない。

- 4Stemや6Stemを足し戻した再合成誤差
- 各Stemの帯域別エネルギー分布
- Stem間の相関
- 無音率
- 処理時間
- メモリ使用量

処理時間とメモリ使用量は、実行可能性と負荷を判断するために別枠で使用する。

## 制限事項

- 精度検証はMUSDB公式7秒サンプルのtest subset 50曲に対する結果であり、すべての楽曲で同じ差になることは確認していない
- ユーザー指定曲には正解Stemがないため、その曲自体のSDR、SIR、SARは測定していない
- BS-RoFormer-SWチェックポイントの学習データとMUSDB test subsetの重複有無は未確認
- BS-RoFormer-SWチェックポイントの再配布ライセンスは未確認
- 実音源の処理時間とメモリ使用量は各モデル1回の実測

## 今後の再検証

1. MUSDB公式7秒サンプルのtest subset 50曲を同一入力として使用する
2. 比較モデルの出力を`vocals`、`drums`、`bass`、`other`へ揃える
3. `museval 0.4.1`、BSS Eval v4、1.0秒window・hopで評価する
4. 同一曲のSDR対応差、勝敗数、95%信頼区間を今回の結果と比較する
5. 速度とメモリは、同じ実音源・同じ実行機で別に測定する
6. 精度結果と負荷結果を混ぜずに報告する

## Swift単独ランタイムの後続検証

BS-RoFormer-SW専用MLX SwiftランタイムのPython一致度、全編処理時間、メモリ実測は、
`Docs/BSRoformerSwiftRuntimeValidation_2026-07-30.md`に保存している。

公開Float16モデルrevision `13edef2e713151522e4049e92f011e0543c45d53`の互換性確認後、
Veloura Lucentの既存Stem ModeへHTDemucsと切り替えて使える形で接続した。既定は
HTDemucsのままで、自動フォールバックと新しい管理画面は追加していない。

ユーザー指定実音源は、Release構成のアプリ本体でBS-RoFormer-SW分離、6→4Stem変換、
既存Stem解析・補正、再ミックス、マスタリングまで`418.755秒`で完走した。この時間は
単独分離の速度比較値ではなく、後続工程を含む統合確認の所要時間として分けて扱う。
