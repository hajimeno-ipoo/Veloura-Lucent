# STFT / ISTFT 往復削減の設計メモ

## 結論

STFT / ISTFT の往復削減は、すぐ本番実装しないほうが安全です。

理由は、いまの補正処理では「周波数で直す工程」と「波形で直す工程」が交互にあります。ここを無理にまとめると、処理順や中間波形が変わり、ノイズ除去、高域補完、帯域抑制の効き方が変わる可能性があります。

まずは、往復箇所を分類し、試作してよい場所を限定します。

## 現在の往復箇所

### 1. 解析 `AudioAnalyzer`

- 場所: `Sources/VelouraLucent/Services/NativeAudioProcessor.swift`
- 処理: `SpectralDSP.stft`
- 逆変換: なし
- 用途: 補正前の特徴量を見る

ここは往復ではありません。削るなら `STFT` の軽量化や解析量の削減ですが、今回の「往復削減」とは別です。

### 2. ノイズ除去 `SpectralGateDenoiser`

- 場所: `SpectralGateDenoiser.processPass`
- 処理: `STFT -> mask -> ISTFT`
- 回数: `gentle` は1回、`balanced` は2回、`strong` は3回

ここは往復回数が多いです。ただし、複数passは「前passで変わった波形」を次passで再解析する意味があります。passをまとめると、ノイズ除去の効き方が変わります。

判断: すぐ統合しない。

### 3. 高域補完 `CorrectionHarmonicRepair.foldover`

- 場所: `CorrectionHarmonicRepair.foldover`
- 処理: `STFT -> 高域foldover成分生成 -> ISTFT`
- その後: 波形上で `presence`、`air`、`transient` を混ぜる

ここは一部だけ周波数処理です。すでに `foldover` 用の一時スペクトログラム生成とゼロクリアは軽量化済みです。

判断: 追加統合の優先度は低い。

### 4. サ行保護・低中域整理

- 場所: `SibilanceShimmerGuard.processChannel` / `LowMidResidueGuard.processChannel`
- 処理: `STFT -> 帯域ごとのgain -> ISTFT`
- 目的: サ行、シマー、低中域の残りを抑える

ここは周波数領域だけで完結する部分があります。ただし前後に波形処理があり、補正順を変えると音が変わる可能性があります。

判断: 試作候補。ただし本番化はA/B確認後。

### 5. マスタリング解析

- 場所: `MasteringAnalysisService.analyze`
- 処理: `STFT`
- 逆変換: なし

これは補正後の別工程です。往復削減ではなく、解析の軽量化対象です。

## 統合候補

| 候補 | 期待効果 | 音質リスク | 判断 |
| --- | --- | --- | --- |
| ノイズ除去pass統合 | 高 | 高 | 見送り |
| foldoverとサ行保護・低中域整理の統合 | 中 | 中〜高 | 設計だけ |
| サ行保護・低中域整理の内部軽量化 | 中 | 低〜中 | 次の試作候補 |
| 解析STFTの使い回し | 中 | 中 | 使い回せる範囲が狭い |
| ログ用STFTの使い回し | 低〜中 | 低 | 実装済み |
| 補正全体の周波数領域パイプライン化 | 高 | 高 | 現時点ではやらない |

## やってはいけないこと

### ノイズ除去passを単純に1回へまとめる

これは速くなりますが、ノイズ除去の結果が変わります。

`balanced` や `strong` は、前pass後の波形をもう一度見て次のmaskを作ります。ここを省くと、ノイズが残るか、逆に削りすぎる可能性があります。

### 補正全体を1つのSTFTで処理する

これは大きな変更です。

高域補完には、波形上の `tanhf`、`lowPass`、`highPass`、`transient` が含まれます。全部を周波数領域で同じ結果にするのは難しく、音質差が出やすいです。

### A/Bなしで採用する

この領域は、ビルドや単体テストだけでは足りません。

必ず旧版と同じ入力で処理し、WAV出力、解析値、必要なら聴感を確認します。

## 実装するなら最初の一手

最初に試すなら、`MultibandDynamicsProcessor` の内部軽量化です。

理由は次です。

- すでに1回の `STFT -> ISTFT` に閉じている
- 処理対象が限定されている
- ノイズ除去passのような再解析ループではない
- 出力A/Bを取りやすい

ただし、`STFT/ISTFT` の往復そのものを削るというより、まずはこの工程の中の余計な配列や走査を減らすのが現実的です。

## 本当に往復を削る場合の試作案

### 試作A: `HarmonicUpscaler` と `MultibandDynamicsProcessor` の連結

`HarmonicUpscaler` の出力直後に `MultibandDynamicsProcessor` が走ります。

ただし `HarmonicUpscaler` は波形で複数成分を足しているため、`MultibandDynamicsProcessor` と完全にまとめるには中間波形を作る必要があります。その時点で `ISTFT` は必要です。

結論: 往復削減効果は限定的です。

### 試作B: `MultibandDynamicsProcessor` をfoldover用ISTFTへ寄せる

foldover成分だけに帯域gainをかける案です。

ただし現状の `MultibandDynamicsProcessor` は、foldover成分だけでなく、補完後の全体音に対して動きます。対象が変わるため、音が変わります。

結論: 採用しないほうが安全です。

### 試作C: 周波数領域パイプラインを別実験フラグで作る

通常処理はそのまま残し、実験用に別経路を作ります。

これは一番安全に比較できますが、実装量が大きくなります。Metal/GPU試作と同じく、まだ後回しでよいです。

## 採用条件

往復削減を本番採用する条件は次です。

- `swift test` が通る
- 旧版A/BのWAVが完全一致する、または差分が明確に許容範囲内
- `MasteringAnalysisService` の主要値が大きくズレない
- ノイズ除去の効き方が弱くならない
- 高域補完が痛くならない
- 速度差が単回ではなく複数回測定で明確

完全一致しない場合は、速度改善だけで採用しません。

## 次の推奨

次は `STFT/ISTFT` 往復を削る実装ではなく、サ行保護・低中域整理の内部軽量化を先に行うのが安全です。

具体的には、帯域ごとの `bandEnergy` 計算とgain適用の走査を見直します。音の式は変えず、配列生成と走査回数だけを減らす方針です。
