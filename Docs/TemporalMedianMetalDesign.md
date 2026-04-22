# temporal median Metal化の設計メモ

## 結論

`temporal median` のMetal化は、実装候補としては有りです。

ただし、すぐ本番採用はしません。まずCPU版と完全一致する実験実装を作り、解析値と最終WAVのA/B確認を通す必要があります。

理由は、`temporal median` が `AudioAnalyzer.separatedMeanSpectra` の中で harmonic / percussive 分離の重みに使われているためです。ここが少しでも変わると、`harmonicConfidence`、`shimmerRatio`、`noiseAmount` が変わり、高域補完やノイズ判断に影響します。

## 現在の処理

対象は次です。

```text
Sources/VelouraLucent/Services/NativeAudioProcessor.swift
AudioAnalyzer.cpuSeparatedMeanSpectra
```

現在の流れは次です。

```text
for binIndex in 0..<binCount
  magnitudesのbin履歴を作る
  medianFilter(history, windowSize: 17)
  temporalMedian[frameIndex * binCount + binIndex] へ保存
```

実験Metal解析では、すでに `real/imag -> magnitude` だけMetalで計算しています。  
しかし、`temporal median` はまだCPU側です。

## 何をMetal化するか

最初の対象は、`windowSize: 17` の temporal median だけに限定します。

```text
input:
  magnitudes[frameCount * binCount]

output:
  temporalMedian[frameCount * binCount]
```

GPU側では、各 `frameIndex, binIndex` について、同じbinの前後17窓から中央値を求めます。

## CPU版との完全一致条件

CPU版の中央値は、端では窓が短くなります。

```text
lower = max(0, frameIndex - 8)
upper = min(frameCount - 1, frameIndex + 8)
median = sorted(window)[(upper - lower) / 2]
```

Metal版もこの条件に完全一致させます。

重要なのは次です。

- 端の `lower / upper` をCPU版と同じにする
- 中央位置を `(upper - lower) / 2` にする
- `Float` の比較順を変えない
- 17窓以外には適用しない
- 結果バッファの並びを `frameIndex * binCount + binIndex` にする

## 実装案

### 1. Metalカーネルを追加

`MetalAudioAnalysisProcessor.metalSource` に次のようなカーネルを追加します。

```text
computeTemporalMedian17
```

役割は、magnitudeバッファから temporal median バッファを作ることです。

### 2. CPU側の流れ

`MetalAudioAnalysisProcessor.separatedMeanSpectra` を次の流れにします。

```text
makeMagnitudes(spectrogram)
 -> makeTemporalMedian17(magnitudes)
 -> spectral median と harmonic/percussive 集計はCPU
```

初回では、spectral median と集計はまだMetal化しません。

### 3. フォールバック

次のどれかが失敗したらCPU版へ戻します。

- Metalデバイス取得失敗
- pipeline作成失敗
- buffer作成失敗
- commandBuffer失敗
- 出力サイズ不一致

## テスト条件

実装前に必要なテストは次です。

### 1. temporal median バッファ一致

CPU版の `medianFilter(history, windowSize: 17)` と、Metal版の `temporalMedian` が完全一致することを確認します。

### 2. 解析値一致

次がCPU版と一致、または十分小さい差に収まることを確認します。

- `cutoffFrequency`
- `harmonicConfidence`
- `hasShimmer`
- `shimmerRatio`
- `brightnessRatio`
- `transientAmount`
- `noiseAmount`

### 3. WAV A/B一致

最終的な補正WAVがCPU版と一致することを確認します。

完全一致しない場合は、差分の最大値、平均値、解析値差を見て採用判断します。

## ベンチ条件

既存の長尺ベンチと同じ長さで確認します。

```text
10秒
30秒
60秒
```

見る値は次です。

- CPU解析時間
- 実験Metal解析時間
- speedup
- 解析値差分
- WAV A/B

## 採用判断

採用候補にしてよい条件は次です。

- 解析値がCPU版とほぼ一致
- WAV A/Bが一致、または差分が許容範囲
- 30秒以上で明確に速い
- 10秒程度で大きく遅くならない
- Metal不可時にCPUへ戻る

目安として、30秒以上で `1.2x` 以上の安定した改善が出ない場合は、実装負荷に見合いにくいです。

## リスク

### 音質リスク

`temporal median` は harmonic / percussive 分離の重みです。値が変わると、高域補完量やノイズ判断が変わる可能性があります。

### 速度リスク

Metalへ渡すデータ量は `frameCount * binCount` です。GPU計算が速くても、転送や同期で相殺される可能性があります。

### 保守性リスク

Metal shader側に中央値ロジックを持つため、CPU版と同じ仕様を保つテストが必須です。

## 次の一手

次に実装するなら、次の順で進めます。

1. CPU版 `temporalMedian` を直接作るテストヘルパーを用意
2. Metal版 `computeTemporalMedian17` を追加
3. `temporalMedian` 完全一致テストを追加
4. 解析値差分テストを通す
5. WAV A/Bを取る
6. 長尺ベンチで採用判断する

