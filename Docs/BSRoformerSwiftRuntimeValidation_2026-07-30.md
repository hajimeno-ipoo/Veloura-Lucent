# BS-RoFormer-SW MLX Swift単独ランタイム検証結果

## 結論

`Vendor/bs-roformer-mlx-swift`へ、BS-RoFormer-SW専用の単独MLX Swiftランタイムを追加した。
Python参照出力との同一入力比較では、6ステムすべてで高い一致を確認した。

- MUSDB公式6.8秒音源：相関`0.9998601〜0.9999999`
- ユーザー指定曲の全編・同一44.1kHz入力：相関`0.9999804〜0.9999998`
- ユーザー指定の48kHz原音：31チャンク、`112.31秒`で完走
- 48kHz原音実行時のpeak memory footprint：`8,096,074,368 bytes`（約8.10GB）
- スワップ：`0`

この結果は、Swiftランタイム単体が対象モデルを読み込み、6ステムを最後まで出力でき、
Python参照実装に近い結果を返したことを示す。

その後、公開配布されているFloat16モデルと設定を同じランタイムで確認し、
Veloura Lucent本体の既存Stem Modeへ選択式で接続した。既定はHTDemucsのままであり、
自動フォールバックは追加していない。

- 公開モデルrevision：`13edef2e713151522e4049e92f011e0543c45d53`
- 公開safetensors：`349,521,144 bytes`
- 公開safetensors SHA-256：`6c8303a829575d03f21562ea185be7b6b23e922052883dec1b9518ca00a920fc`
- 公開config：`1,141 bytes`
- 公開config SHA-256：`ab4ae4369276c2ff12ee86d55ce45c37a88a82f6744c33c0bb6a40c1c2f620f9`
- 6.8秒入力：3チャンク、6Stemすべて出力
- ユーザー指定実音源のアプリ三段階workflow：`418.755秒`で完走
- Releaseアプリの既存取得画面：weightsの`us.aws.cdn.hf.co`転送を通過し、
  2資産の容量・SHA-256検証、receipt保存、BS専用active pointer作成まで完了

## 実装範囲

対象：

`Vendor/bs-roformer-mlx-swift`

含めたもの：

- BS-RoFormer-SW用JSON設定の読み込みと検証
- 1,915個のsafetensors重みの読み込みと不足確認
- Hann窓のSTFT / iSTFT
- 62帯域のBand Split
- 時間方向・周波数方向のRoFormer推論
- 6ステム別の複素マスク生成と適用
- Python参照と同じ長音源のチャンク分割、Hamming窓、Overlap Add
- 10秒未満で256フレームへ切り替える確認済みの短音源条件
- 48kHz入力をモデル条件の44.1kHz / stereo / Float32へ変換するCLI入力
- 進捗通知とキャンセル確認
- 6ステムFloat32 WAV出力

Veloura Lucent本体へ追加したもの：

- 既存右サイド「Stem分離」内のHTDemucs／BS-RoFormer-SW選択
- モデル別manifest、検証、独立active pointer
- 選択モデルに対応するbackend routing
- `vocals`、`drums`、`bass`の直接対応
- `other + guitar + piano`の無係数Float32加算
- 既存の進捗、キャンセル、ログ、4Stem保存への接続

追加していないもの：

- 新しい管理画面またはダウンロード画面
- 自動フォールバック
- HTDemucsからBS-RoFormer-SWへの既定変更
- 通常モードの変更
- Stem解析、Stem別補正、再ミックス、マスタリングの新方式

## 固定したモデル契約

| 項目 | 値 |
|---|---|
| sample rate | 44,100Hz |
| channels | 2 |
| stems | `bass, drums, other, vocals, guitar, piano` |
| model dimension | 256 |
| RoFormer blocks | 12 |
| attention heads | 8 |
| head dimension | 64 |
| bands | 62 |
| frequency bins | 1,025 |
| STFT | FFT 2,048 / hop 512 / window 2,048 |
| long-audio frames | 801 |
| short-audio frames | 256 |
| MLX Swift | 0.30.6 |

対象safetensors：

- file：`BS-Roformer-SW.safetensors`
- size：`698,849,326 bytes`
- SHA-256：`a5b52f2a2a605be1ee9e827696d6a80a4aaef55c0ceaa6308ef51b48d8ce906e`
- weight keys：`1,915`

モデルファイル自体はプロジェクトへ同梱していない。

### アプリで使う公開Float16資産

アプリのmanifestは、次の公開資産を固定している。

| 項目 | 値 |
|---|---|
| repository | `MrSimmo/BS_Roformer_SW-MLX` |
| revision | `13edef2e713151522e4049e92f011e0543c45d53` |
| weights | `bs_roformer_sw.safetensors` |
| weights size | `349,521,144 bytes` |
| weights SHA-256 | `6c8303a829575d03f21562ea185be7b6b23e922052883dec1b9518ca00a920fc` |
| config | `bs_roformer_sw_config.json` |
| config size | `1,141 bytes` |
| config SHA-256 | `ab4ae4369276c2ff12ee86d55ce45c37a88a82f6744c33c0bb6a40c1c2f620f9` |
| license metadata | `unknown` |

公開weightsはStemTap形式のkey名を使う。ランタイム内で、1,915 keyを
既存Swift層名へ一対一で正規化してから不足・余剰を検証する。テンソル値や推論式は
変更しない。公開configのsnake_caseを読み込み、モデル構造を検証したうえで、
確認済みの`latency_safe_v3`相当のチャンク条件を使う。

## Python参照との一致

### MUSDB公式6.8秒音源

入力：

`benchmark/musdb_test_mixtures/000.wav`

Python参照：

- `mlx-audio-separator 0.1.5`
- MLX `0.31.2`
- `latency_safe_v3`
- 10秒未満のため256フレーム、3チャンク

Swift：

- MLX Swift `0.30.6`
- 同じ256フレーム、3チャンク
- Release build

| Stem | 相関 | RMSE | 最大絶対差 |
|---|---:|---:|---:|
| `bass` | 0.9999995266 | 0.0000851976 | 0.0004607569 |
| `drums` | 0.9999995781 | 0.0000849339 | 0.0004319213 |
| `other` | 0.9999992886 | 0.0000186982 | 0.0002365829 |
| `vocals` | 0.9999998960 | 0.0000384261 | 0.0004717028 |
| `guitar` | 0.9998600738 | 0.0000001031 | 0.0000078458 |
| `piano` | 0.9999750184 | 0.0000000194 | 0.0000005543 |

`guitar`と`piano`は、この抜粋ではPython参照のRMS自体がそれぞれ約`0.00000541`、
`0.00000268`と非常に小さい。相関だけでなくRMSEと最大絶対差も併記した。

Release実行：

- 処理時間：`4.21秒`
- maximum resident set size：`859,586,560 bytes`
- peak memory footprint：`2,790,737,312 bytes`
- スワップ：`0`

### ユーザー指定曲・同一44.1kHz入力

入力：

`input/星屑のシンパシー_44100_float32.wav`

PythonとSwiftへ同じ44.1kHz / stereo / Float32音声を入力した。

| Stem | 相関 | RMSE | 最大絶対差 |
|---|---:|---:|---:|
| `bass` | 0.9999993214 | 0.0000604928 | 0.0006263852 |
| `drums` | 0.9999996537 | 0.0000277049 | 0.0008654743 |
| `other` | 0.9999969574 | 0.0001231227 | 0.0022954121 |
| `vocals` | 0.9999997700 | 0.0000603032 | 0.0017816275 |
| `guitar` | 0.9999803870 | 0.0000709837 | 0.0011094771 |
| `piano` | 0.9999971242 | 0.0001094712 | 0.0021547526 |

Swift Release実行：

- チャンク数：`31`
- 処理時間：`120.16秒`
- maximum resident set size：`1,467,498,496 bytes`
- peak memory footprint：`8,096,647,784 bytes`
- スワップ：`0`

## ユーザー指定の元ファイルでの負荷

入力：

`Tests/Fixtures/Sample_audio/星屑のシンパシー.wav`

このファイルは48kHzのため、Swift CLIで44.1kHzへ変換してから推論した。

| 項目 | 結果 |
|---|---:|
| 出力sample rate | 44,100Hz |
| 出力frames | 10,857,420 |
| 出力channels | 2 |
| 出力stems | 6 |
| チャンク数 | 31 |
| 処理時間 | 112.31秒 |
| maximum resident set size | 1,454,243,840 bytes |
| peak memory footprint | 8,096,074,368 bytes |
| スワップ | 0 |

同じ曲のPython単独試験は`65.40秒`、peak memory footprint約`10.42GB`だった。
今回のSwift ReleaseはPython単独試験より約`1.72倍`遅く、peak memory footprintは
約`0.78倍`だった。実行系とMLX版が異なるため、これは今回の1回の実測比較として扱う。

48kHz原音を各実行系で変換した結果同士の相関は`0.9983903〜0.9999943`だった。
同一の44.1kHz入力では`0.9999804〜0.9999998`へ上がったため、入力変換条件と
Swift推論本体の差を分けて記録した。

## 検証コマンド

```bash
cd Vendor/bs-roformer-mlx-swift
swift test
swift build -c release
./scripts/prepare_mlx_runtime.sh release

.build/release/bs-roformer-mlx-swift \
  /path/to/BS-Roformer-SW.safetensors \
  Config/BS-Roformer-SW.json \
  /path/to/input.wav \
  /path/to/output
```

Python参照との数値比較：

```bash
python scripts/compare_python_outputs.py \
  /path/to/swift-output \
  /path/to/python-output \
  --python-prefix "000_"
```

## 未確認事項・制限

- 現行Stem Modeの既定分離器はHTDemucsのまま
- BS-RoFormer-SWからHTDemucsへの自動フォールバックはない
- 公開Float16モデルの6.8秒入力で6Stem出力を確認済み
- ユーザー指定実音源を、Release構成のアプリ本体workflowで分離、4Stem保存、
  Stem別解析・補正、再ミックス、マスタリングまで完走確認済み
- モデル選択、進捗表示、キャンセルのコード接続と自動テストは確認済み
- 実画面の既存右パネルでHTDemucs／BS-RoFormer-SWの切り替えと、
  選択モデルの状態表示を確認済み
- 実画面の既存取得確認から公開2資産を取得し、BS-RoFormer-SWが
  「利用可能」になることを確認済み
- 実画面からの全処理実行と、処理中キャンセルの手操作は未確認
- 実音源の速度とメモリは各条件1回の実測
- BS-RoFormer-SWチェックポイントの再配布ライセンスは未確認
- モデル同梱・再配布は行っていない

## アプリ統合結果

アプリ本体は、選択されたBS-RoFormer-SWの6ステムを次の4ステムへ変換し、
既存の`StemSeparationBackendOutput`へ渡す。

| 既存4Stem | BS-RoFormer-SW |
|---|---|
| `vocals` | `vocals` |
| `drums` | `drums` |
| `bass` | `bass` |
| `other` | `other + guitar + piano` |

既存右サイド内の選択だけを追加し、モデル保存、取得前確認、検証、進捗、
キャンセル、ログ、後続三段階workflowは既存の仕組みを共用する。HTDemucsの既定値、
通常モード、既存Stem解析・補正・再ミックス・マスタリングは変更していない。
