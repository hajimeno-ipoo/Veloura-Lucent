# Spectral-Lifter 対応表

## 結論

- `Veloura Lucent` は、元プロジェクト `relationsuno/Spectral-Lifter` の処理思想を概ね引き継いでいます。
- 特に、解析、ノイズ除去、高域補完、帯域抑制、LUFS / True Peak の流れはかなり近いです。
- 違いは、Python + Librosa / PyTorch 実装ではなく、Swift + 自前DSP 実装に置き換えている点です。
- さらに、現在のアプリには元プロジェクトにない追加マスタリング段があります。

---

## 元プロジェクト

- GitHub:
  - [relationsuno/Spectral-Lifter](https://github.com/relationsuno/Spectral-Lifter)

主な参照元:

- README
  - <https://github.com/relationsuno/Spectral-Lifter#spectral-lifter-v10>
- 処理パイプライン
  - <https://raw.githubusercontent.com/relationsuno/Spectral-Lifter/main/processor.py>
- 解析
  - <https://raw.githubusercontent.com/relationsuno/Spectral-Lifter/main/core/analysis.py>
- ノイズ除去
  - <https://raw.githubusercontent.com/relationsuno/Spectral-Lifter/main/core/denoising.py>
- 高域補完
  - <https://raw.githubusercontent.com/relationsuno/Spectral-Lifter/main/core/upscaling.py>
- ダイナミクス
  - <https://raw.githubusercontent.com/relationsuno/Spectral-Lifter/main/core/dynamics.py>
- LUFS / True Peak
  - <https://raw.githubusercontent.com/relationsuno/Spectral-Lifter/main/utils/audio_io.py>

---

## 全体の対応

```text
Spectral-Lifter
  Analyzer
  -> Denoiser
  -> Upscaler
  -> DynamicsProcessor
  -> finalize_audio

Veloura Lucent
  AudioAnalyzer
  -> SpectralGateDenoiser
  -> HarmonicUpscaler
  -> MultibandDynamicsProcessor
  -> LoudnessProcessor
  -> 追加の MasteringProcessor
```

---

## 機能ごとの対応表

| 元プロジェクトの機能 | 元の実装 | 現在の対応先 | 判定 |
|---|---|---|---|
| Target Analysis | `core/analysis.py` | `Sources/VelouraLucent/Services/NativeAudioProcessor.swift` | ほぼ対応 |
| 12k-16kHz ロールオフ検出 | `core/analysis.py` | `AudioAnalyzer.analyze()` | 対応 |
| シマー成分の確認 | `core/analysis.py` | `AudioAnalyzer.analyze()` | 対応 |
| 倍音分析 | `core/analysis.py` | `AudioAnalyzer.analyze()` | 対応 |
| Digital Denoising | `core/denoising.py` | `SpectralGateDenoiser` | 対応 |
| Spectral Gate | `core/denoising.py` | `SpectralGateDenoiser.processPass()` | 対応 |
| Spectral Upscaling | `core/upscaling.py` | `HarmonicUpscaler` | 近い形で対応 |
| 16kHz以上の再構築 | `core/upscaling.py` | `HarmonicUpscaler.process()` | 対応 |
| トランジェント補強 | `core/upscaling.py` | `AudioAnalyzer.estimateTransientAmount()` + `HarmonicUpscaler.process()` | 対応 |
| Neural foldover | `core/upscaling.py` | なし | 元も実質ダミー |
| Dynamics Control | `core/dynamics.py` | `MultibandDynamicsProcessor` | ほぼ対応 |
| 5k-8kHz シビランス抑制 | `core/dynamics.py` | `MultibandDynamicsProcessor.bands` | 対応 |
| 10k-14kHz シマー抑制 | `core/dynamics.py` | `MultibandDynamicsProcessor.bands` | 対応 |
| 18kHz+ アーティファクト抑制 | `core/dynamics.py` | `MultibandDynamicsProcessor.bands` | 対応 |
| Final Mastering | `utils/audio_io.py` | `LoudnessProcessor` | 対応 |
| -14 LUFS | `utils/audio_io.py` | `LoudnessProcessor.targetLKFS` | 対応 |
| -1.0 dBTP | `utils/audio_io.py` | `LoudnessProcessor.peakLimitDB` | 対応 |

---

## 元プロジェクトの実処理

元の `processor.py` の流れは、かなり単純です。

1. 音声を読む
2. 解析する
3. ノイズ除去する
4. 高域を補う
5. ダイナミクスを整える
6. LUFS とピークを整える
7. 保存する

これは現在の `NativeAudioProcessor` と、ほぼ同じ並びです。

対応箇所:

- [NativeAudioProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift)

---

## 現在のアプリで対応している主な場所

### 1. 解析

- ファイル:
  - [NativeAudioProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift:38)

役割:

- `12kHz-16kHz` のロールオフ位置を見る
- `300Hz-800Hz` の倍音ピークを見る
- `10kHz-14kHz` のシマー傾向を見る
- トランジェント量をざっくり見る

### 2. ノイズ除去

- ファイル:
  - [NativeAudioProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift:109)

役割:

- STFT ベースの Spectral Gate
- 静かなフレームからノイズ床を推定
- 高域寄りで少し強めに効くよう調整

### 3. 高域補完

- ファイル:
  - [NativeAudioProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift:239)

役割:

- 欠けた高域を埋める方向の補完
- トランジェントを少し持ち上げる
- 元の Python 版と同じく、実体はヒューリスティック寄り

### 4. 帯域抑制

- ファイル:
  - [NativeAudioProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift:195)

役割:

- `5k-8kHz`
- `10k-14kHz`
- `18kHz-24kHz`

の3帯域に対して、過剰な成分を抑える

### 5. 最終音量調整

- ファイル:
  - [NativeAudioProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift:265)

役割:

- `-14 LUFS`
- `-1 dBTP`

へ寄せる簡易ラウドネス / リミッター処理

---

## LUFS / True Peak の対応

元プロジェクト README には、次の説明があります。

- LUFS: `utils/audio_io.py` に `-14.0 LUFS`
- True Peak: `utils/audio_io.py` に `-1.0 dBTP`

現在のアプリでは、同等の値が Swift 側にあります。

### 補正段

- [NativeAudioProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift:266)
  - `targetLKFS: -14`
- [NativeAudioProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift:267)
  - `peakLimitDB: -1`

### 追加マスタリング段

- [MasteringModels.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Models/MasteringModels.swift:53)
  - `streaming` プロファイルは `targetLoudness: -14.0`
- [MasteringModels.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Models/MasteringModels.swift:55)
  - `peakCeilingDB: -1.0`

---

## 元プロジェクトとの差分

### 1. 実装言語が違う

- 元:
  - Python
  - Librosa
  - NumPy
  - PyTorch
- 現在:
  - Swift
  - AVFoundation
  - Accelerate
  - 自前DSP

### 2. Neural 部分は元からかなり軽い

- README では Neural と見えますが、
- `core/upscaling.py` の実体は、学習済み重みを使った本格推論ではありません。
- 実際はヒューリスティックな補完が主です。

そのため、現在の Swift 実装も「元仕様から大きく外れた」のではなく、
「元の軽量実装をローカルアプリに置き換えた」と考えるほうが近いです。

### 3. 今のアプリには追加機能がある

現在のアプリには、元プロジェクトにない別段のマスタリングがあります。

- de-esser
- 3帯域コンプレッション
- saturation
- stereo width
- プリセット切り替え

対応箇所:

- [MasteringProcessor.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/MasteringProcessor.swift:4)
- [MasteringModels.swift](/Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Models/MasteringModels.swift:3)

---

## 最終判定

- 元の `Spectral-Lifter` の中心機能は、現在の `Veloura Lucent` にかなり引き継がれています。
- 特に、帯域設計と処理順は近いです。
- いちばん大きな違いは、技術スタックと UI です。
- さらに、現在のアプリは元プロジェクトより後段のマスタリング機能が増えています。

要するに、

- 元の処理を完全に捨てた別物

ではなく、

- 元の処理を Swift の macOS アプリとして再構成し、さらに仕上げ機能を足した版

と整理するのがいちばん近いです。
