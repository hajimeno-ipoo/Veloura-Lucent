# Metal / GPU 化の調査メモ

## 結論

現時点では、Metal / GPU 化は本番実装へ進めず、調査止まりにするのが妥当です。

理由は、今の重い処理が `SpectralDSP.stft` / `SpectralDSP.istft` を中心にしており、すでに `Accelerate` の `vDSP` を使っているためです。Apple Silicon では `Accelerate` 自体がCPU側でかなり最適化されています。

GPUへ移す場合、音声データをCPU配列からGPUバッファへ移し、計算後に戻す必要があります。この転送と実装の複雑さに対して、今の規模では速度改善が読みにくいです。さらに、FFT、窓掛け、逆FFT、重ね合わせの小さな差が、ノイズ除去や高域補完の結果を変える可能性があります。

## いまの重い場所

### 1. `SpectralDSP.stft`

- 場所: `Sources/VelouraLucent/Support/SpectralDSP.swift`
- 内容: 波形を短いフレームに分け、周波数成分へ変換します。
- 現状: `vDSP.DiscreteFourierTransform<Float>` を使っています。
- 影響範囲: 補正、ノイズ除去、高域補完、マスタリング解析、スペクトログラム表示に効きます。

Metal化の難易度は高いです。FFTそのものをGPUへ移すだけでなく、窓掛け、半分の周波数ビン管理、逆変換との整合まで合わせる必要があります。

### 2. `SpectralDSP.istft`

- 場所: `Sources/VelouraLucent/Support/SpectralDSP.swift`
- 内容: 周波数成分を波形へ戻します。
- 現状: `vDSP.DiscreteFourierTransform<Float>` の逆変換を使っています。
- 影響範囲: 補正後の音そのものです。

ここは音質リスクが特に高いです。小さな丸め誤差や重ね合わせの差でも、出力波形が変わります。

### 3. `SpectralGateDenoiser`

- 場所: `Sources/VelouraLucent/Services/NativeAudioProcessor.swift`
- 内容: 周波数ごとにノイズ量を見て、maskを掛けます。
- 現状: CPUループで、チャンネル単位は並列化済みです。
- 影響範囲: ノイズ除去の効き方です。

GPU向きではあります。各フレーム、各ビンを独立して処理しやすいからです。ただし、今の `Spectrogram` は `[[Float]]` なので、GPUへ渡すには連続した1本のバッファへ直す必要があります。

### 4. `HarmonicUpscaler.foldover`

- 場所: `Sources/VelouraLucent/Services/NativeAudioProcessor.swift`
- 内容: 低めの高域成分を、16kHz以上へ折り返して少し足します。
- 現状: CPUループで、チャンネル単位は並列化済みです。
- 影響範囲: 高域補完の明るさ、粒立ちです。

GPU化の候補ではありますが、まずCPU側で `foldReal` / `foldImag` の作り方を軽くするほうが安全です。

### 5. `MasteringAnalysisService`

- 場所: `Sources/VelouraLucent/Services/MasteringAnalysisService.swift`
- 内容: ラウドネス、ピーク、帯域量、刺さり感、ステレオ幅を見ます。
- 現状: CPUで直接集計します。
- 影響範囲: 解析表示とマスタリング判断です。

GPU化の優先度は低いです。集計処理が中心なので、GPU転送コストに負けやすいです。

## Metal化するなら必要な前提

Metal化を本当に進めるなら、先に次の準備が必要です。

1. `Spectrogram` を連続メモリへ寄せる
   - 現在は `[[Float]]` です。
   - GPUへ渡すには `frames * bins` の1本配列のほうが扱いやすいです。
   - これはCPUのままでも速度改善につながる可能性があります。

2. 工程別ベンチを固定する
   - `stft`
   - `denoise mask`
   - `istft`
   - `foldover`
   - `mastering analysis`
   - `saveAudio`

3. A/B一致確認を自動化する
   - 既存CPU版とMetal試作版で同じ入力を処理します。
   - 完全一致が難しい場合は、最大差、平均差、ピーク差、ラウドネス差を見ます。
   - ノイズ除去と高域補完は聴感差も出やすいので、数値だけで採用しないほうが安全です。

4. Metal版は実験フラグで隔離する
   - 通常の音声処理経路を置き換えないようにします。
   - 例: `UseExperimentalMetalAudioPipeline`
   - 検証が終わるまでUIから触れない形が安全です。

## 候補ごとの判断

| 候補 | 期待速度 | 音質リスク | 実装負荷 | 判断 |
| --- | --- | --- | --- | --- |
| `SpectralGateDenoiser` mask適用 | 中 | 中 | 中 | 試作候補。ただし連続バッファ化が先 |
| `HarmonicUpscaler.foldover` | 低〜中 | 中 | 中 | まずCPU軽量化が先 |
| `SpectralDSP.stft` | 中〜高 | 高 | 高 | すぐ本番化しない |
| `SpectralDSP.istft` | 中〜高 | 高 | 高 | すぐ本番化しない |
| `MasteringAnalysisService` | 低 | 低〜中 | 中 | 優先しない |

## 現実的な進め方

### 短期

Metal化は入れず、CPU版のまま保つのが安全です。

`Spectrogram` の内部表現は連続メモリ化済みです。これにより、GPU化の準備が進み、CPU処理のままでも配列アクセスとメモリ使用量を減らせる可能性があります。

### 中期

`SpectralGateDenoiser` のmask適用だけを、実験用Metalカーネルで試す価値はあります。

ただし、その場合も `stft` と `istft` はCPUのままにして、mask処理だけGPUへ渡す形になります。音声が短い場合は転送コストで遅くなる可能性があります。

### 長期

FFTからmask、逆FFTまでをまとめてGPU上で完結できるなら効果が出る可能性があります。

ただし、この段階は実装量が大きく、音質確認も重くなります。今のアプリでは、優先度は低いです。

## 採用しない理由

Metal化を今すぐ入れない理由は、速度よりも音の安全性を優先するためです。

このアプリでは、ノイズ除去が正しく効かなくなること、高域補完の質感が変わること、マスタリング解析値がずれることが大きな問題になります。Metal化は処理の土台を変えるため、効果が見える前に確認コストが大きくなります。

## 推奨判断

現時点の推奨は次です。

- Metal / GPU 化は本番実装しない
- CPU最適化済みの現経路を維持する
- `Spectrogram` の連続メモリ化は実施済み
- Metal試作をする場合は、`SpectralGateDenoiser` のmask適用だけに限定する
- 採用条件は、速度改善が実測で明確で、A/B差分が許容範囲内であること
