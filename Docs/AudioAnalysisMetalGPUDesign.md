# 解析Metal / GPU化の設計メモ

## 結論

解析のMetal / GPU化は可能です。

ただし、最初から `AudioAnalyzer` 全体をGPU化するのは避けます。最初に試すなら、`separatedMeanSpectra` の中でも重い配列走査と集計だけを、実験モードとして切り出すのが安全です。

理由は、解析結果がその後の高域補完やノイズ量判断に使われるためです。解析値が少し変わるだけでも、最終的な補正音が変わる可能性があります。

## 現在の解析フロー

対象は `Sources/VelouraLucent/Services/NativeAudioProcessor.swift` の `AudioAnalyzer` です。

現在の大まかな流れは次です。

```text
monoMixdown
 -> SpectralDSP.stft
 -> separatedMeanSpectra
    -> binごとの magnitude 履歴
    -> temporal median
    -> frameごとの spectral median
    -> harmonic / percussive mean spectrum 集計
 -> harmonic / percussive の medianFilter
 -> cutoff / peaks / shimmer / brightness / transient / noise 推定
```

この中で、工程別ベンチでは `analyze` が最も重く出ています。特に `separatedMeanSpectra` は、`frameCount * binCount` を複数回なめるため、GPU化候補になります。

## GPU化候補の分類

| 対象 | GPU向き | 音質リスク | 初回対象 |
| --- | --- | --- | --- |
| magnitude計算 | 高 | 低 | 候補 |
| binごとの履歴抽出 | 高 | 低 | 候補 |
| temporal median | 中 | 中 | 条件付き候補 |
| spectral median | 中 | 中 | 条件付き候補 |
| harmonic / percussive 集計 | 高 | 中 | 候補 |
| cutoff検出 | 低 | 低 | CPU維持 |
| peak検出 | 中 | 中 | CPU維持 |
| shimmer / brightness / noise 推定 | 低〜中 | 中 | CPU維持 |
| transient推定 | 低 | 低 | CPU維持 |

## 最初に試す範囲

最初は `AudioAnalyzer.separatedMeanSpectra` だけを対象にします。

ただし、`SpectralDSP.stft` はCPUのままです。`vDSP` のFFTをGPUへ置き換えると、窓関数、半スペクトル、逆変換との整合まで影響が広がるため、初回試作には向きません。

初回の実験モードは次の形にします。

```text
CPU解析
SpectralDSP.stft
 -> CPU separatedMeanSpectra
 -> AnalysisData

実験GPU解析
SpectralDSP.stft
 -> GPU separatedMeanSpectra
 -> AnalysisData
```

## 実装方針

### 1. CPU基準を残す

既存の `AudioAnalyzer` を基準実装として残します。

GPU版は別経路にします。通常の補正処理をいきなり置き換えません。

例:

```text
AudioAnalysisMode.cpu
AudioAnalysisMode.experimentalMetal
```

### 2. `MetalAudioAnalysisProcessor` を別ファイルで追加する

候補ファイル:

```text
Sources/VelouraLucent/Services/MetalAudioAnalysisProcessor.swift
```

責務は `separatedMeanSpectra` 相当の結果を返すことだけに限定します。

```text
input:
  Spectrogram.real
  Spectrogram.imag
  frameCount
  binCount

output:
  harmonicSpectrum
  percussiveSpectrum
```

### 3. Metalが使えない場合はCPUへ戻す

Metalデバイスが取れない、カーネル作成に失敗する、バッファ確保に失敗する場合は、必ずCPU解析へ戻します。

これは失敗時の音質と安定性を守るためです。

### 4. UIでは最初から通常表示しない

最初は開発用または詳細設定内の実験モードにします。

ユーザー向けに出す場合も、次のような扱いにします。

```text
解析モード
- 安定CPU
- 実験Metal
```

## 解析値の一致条件

GPU解析を採用するには、次の値がCPU版とほぼ一致する必要があります。

| 値 | 役割 | 許容目安 |
| --- | --- | --- |
| `cutoffFrequency` | 高域補完の起点 | 小さい差 |
| `harmonicConfidence` | 倍音補完量 | 小さい差 |
| `shimmerRatio` | シマー抑制 | 小さい差 |
| `brightnessRatio` | 明るさ判断 | 小さい差 |
| `transientAmount` | 立ち上がり判断 | 原則同じ |
| `noiseAmount` | ノイズ判断 | 小さい差 |

最終的には、解析値だけでなく、CPU出力とMetal出力のWAV差分も確認します。

## 速度の採用条件

Metal版を採用する条件は次です。

- 同じ入力で複数回測って、`analyze` が明確に速い
- 短い音声でCPUより遅い場合は、自動的にCPUを使える
- GPU版の初期化コストを含めても実用上速い
- メモリ使用量が過剰に増えない

単回ベンチで速いだけでは採用しません。

## リスク

### 1. 解析値が変わる

中央値や丸め誤差の差で、`harmonicConfidence` や `noiseAmount` が変わる可能性があります。

これは高域補完やノイズ除去の効き方に影響します。

### 2. 短い音声では遅くなる

GPUへデータを渡す転送コストがあります。

短い音声や軽い入力では、CPUのままのほうが速い可能性があります。

### 3. 実装量が大きい

Metal shader、バッファ管理、フォールバック、テストが必要です。

このため、CPU版を消さずに実験モードとして進める必要があります。

## 実装順

1. `AudioAnalysisMode` を追加する
2. `AudioAnalyzer` に mode を渡せるようにする
3. `MetalAudioAnalysisProcessor` を空実装で追加する
4. Metal不可時はCPUへ戻す
5. CPU版と同じ `separatedMeanSpectra` 結果を返すテストを用意する
6. magnitude / 集計部分だけMetalで試作する
7. 解析値のCPU/GPU差分テストを追加する
8. 最終WAVのA/B比較を追加する
9. 複数回ベンチで採用判断する

## 次の推奨

`AudioAnalysisMode` と `MetalAudioAnalysisProcessor` の土台は追加済みです。

現在の実験Metal解析では、`separatedMeanSpectra` のうち magnitude 計算だけをMetalで試作しています。中央値フィルタとharmonic / percussive集計はCPU側に残しています。

次に進めるなら、GPU版magnitudeの複数回ベンチと、解析値差分の専用テストを追加します。その後に、集計部分をMetalへ寄せるか判断します。
