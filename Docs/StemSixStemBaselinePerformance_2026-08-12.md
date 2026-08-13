# Stem Mode 6Stem化前後の性能比較（2026-08-12）

## 目的

BS-RoFormer-SWの6Stem化前後で、HTDemucs／BS-RoFormer-SWを同じ入力と
同じアプリ全工程へ通し、処理時間、最大RSS、一時WAV容量、artifact数を比較する。

これはStem分離精度の比較ではない。両モデルとも現行コードでは4Stemとして保存され、
BS-RoFormer-SWの`guitar`と`piano`は`other`へ加算された後の基準である。

## 共通条件

- Apple Silicon上のSwiftPM Release build
- MLX Swift `0.30.6`
- アプリ本体と同じ`StemWorkflowService`の補正、再ミックス、マスタリング全工程
- 補正設定: `DenoiseStrength.balanced`
- マスタリング設定: `MasteringProfile.natural`
- 解析: CPU
- HTDemucs: `metaHTDemucsProduction(seed: 20_260_719)`
- BS-RoFormer-SW: `.bsRoformerSWProduction`
- 最大RSS: 各モデルを別processで`/usr/bin/time -l`により測定
- 一時容量とartifact数: 各工程完了時のrun directory内の通常ファイルを実測
- 各条件1回の基準測定。速度の統計評価ではなく、6Stem化前後の同条件比較に使う。

## 6.8秒互換性音源

入力: `.stem-model-cache/bs-roformer-sw/compatibility-input/sample-6.8s-44100-f32.wav`

| 項目 | HTDemucs | BS-RoFormer-SW |
|---|---:|---:|
| 入力 | 44.1kHz / stereo / 299,880 frames | 同左 |
| 補正工程 | 8.381秒 | 9.797秒 |
| 再ミックス工程 | 0.739秒 | 0.729秒 |
| マスタリング工程 | 1.279秒 | 1.250秒 |
| 全工程 | 10.400秒 | 11.776秒 |
| 最大RSS | 452,870,144 bytes（431.89 MiB） | 948,224,000 bytes（904.30 MiB） |
| 最大一時artifact数 | 12 | 12 |
| 最大一時容量 | 30,322,752 bytes（28.92 MiB） | 同左 |
| swap | 0 | 0 |

この1回の測定では、BSはHTに対し全工程時間が1.132倍、最大RSSが2.094倍だった。

## 代表実曲

入力: `Tests/Fixtures/Sample_audio/星屑のシンパシー.wav`

- 元ファイル: 48kHz / stereo / 246.2秒
- canonical input: 44.1kHz / stereo / 10,857,420 frames

| 項目 | HTDemucs | BS-RoFormer-SW |
|---|---:|---:|
| 補正工程 | 292.701秒 | 361.281秒 |
| 再ミックス工程 | 28.547秒 | 28.743秒 |
| マスタリング工程 | 40.590秒 | 41.644秒 |
| 全工程 | 361.839秒 | 431.670秒 |
| 最大RSS | 1,941,553,152 bytes（1,851.61 MiB） | 2,101,411,840 bytes（2,004.06 MiB） |
| 最大一時artifact数 | 12 | 12 |
| 最大一時容量 | 1,096,131,552 bytes（1,045.35 MiB） | 同左 |
| swap | 0 | 0 |

この1回の測定では、BSはHTに対し全工程時間が1.193倍、最大RSSが1.082倍、
補正工程時間が1.234倍だった。

## 工程ごとの一時成果物

両入力・両モデルでartifact数は同じだった。

| 工程完了時 | artifact数 | 6.8秒容量 | 代表実曲容量 |
|---|---:|---:|---:|
| 補正 | 10 | 25,092,160 bytes | 907,041,760 bytes |
| 再ミックス | 11 | 27,707,456 bytes | 1,001,586,656 bytes |
| マスタリング | 12 | 30,322,752 bytes | 1,096,131,552 bytes |

現行の内訳はcanonical input 1本、raw 4本、corrected 4本、純粋加算1本、
再ミックス1本、最終版1本で合計12本である。成功終了後はbenchmarkのdeferで
run directoryを削除し、`VelouraLucentStemPreview`直下が0 bytesであることを確認した。

6Stem化後はraw／correctedが各2本増えるため、完了時の期待artifact数は16本になる。
ただし、実際の容量・時間・最大RSSは実装後に同じbenchmarkで再測定して確定する。

## 6Stem化後の同条件実測

変更前と同じモデル、入力、Release build、CPU解析、補正設定、マスタリング設定で、
完全6Stem化後のコードを各条件1回ずつ別processで実行した。HTDemucsは4Stem、
BS-RoFormer-SWは6Stemで、両モデルとも入力から最終版まで成功した。

### 6.8秒互換性音源

| 項目 | HTDemucs 変更後 | BS-RoFormer-SW 変更後 |
|---|---:|---:|
| 補正工程 | 8.778秒 | 13.444秒 |
| 再ミックス工程 | 0.746秒 | 0.905秒 |
| マスタリング工程 | 1.300秒 | 1.279秒 |
| 全工程 | 10.824秒 | 15.629秒 |
| 最大RSS | 451,592,192 bytes（430.67 MiB） | 898,220,032 bytes（856.61 MiB） |
| 最大一時artifact数 | 12 | 16 |
| 最大一時容量 | 30,322,752 bytes（28.92 MiB） | 40,359,616 bytes（38.49 MiB） |
| swap | 0 | 0 |

変更前比は、HTの全工程`+4.08%`、最大RSS`-0.28%`、一時容量`±0%`。
BSの全工程`+32.72%`、補正`+37.23%`、再ミックス`+24.19%`、
マスタリング`+2.29%`、最大RSS`-5.27%`、一時容量`+33.10%`だった。

### 代表実曲

| 項目 | HTDemucs 変更後 | BS-RoFormer-SW 変更後 |
|---|---:|---:|
| 補正工程 | 295.404秒 | 565.861秒 |
| 再ミックス工程 | 28.030秒 | 36.790秒 |
| マスタリング工程 | 41.063秒 | 43.290秒 |
| 全工程 | 364.498秒 | 645.943秒 |
| 最大RSS | 2,200,748,032 bytes（2,098.80 MiB） | 2,724,560,896 bytes（2,598.34 MiB） |
| 最大一時artifact数 | 12 | 16 |
| 最大一時容量 | 1,096,131,552 bytes（1,045.35 MiB） | 1,458,948,256 bytes（1,391.36 MiB） |
| swap | 0 | 0 |

変更前比は、HTの全工程`+0.73%`、最大RSS`+13.35%`、一時容量`±0%`。
BSの全工程`+49.64%`、補正`+56.63%`、再ミックス`+27.99%`、
マスタリング`+3.95%`、最大RSS`+29.65%`、一時容量`+33.10%`だった。

BSの増加は、6Stem化でGuitar／Pianoのraw 2本と補正後2本を保存し、両役割の
専用解析・補正・再ミックスを行う現在の実装と一致する。代表実曲でも全工程は完走し、
最大RSS約2.60 GiB、swap 0だったため、このMac上の個人利用で実行不能となる異常は
確認されなかった。速度の反復分布や別Macでの性能を示す結果ではない。

### 変更後の一時成果物とcleanup

| モデル | 補正完了 | 再ミックス完了 | マスタリング完了 |
|---|---:|---:|---:|
| HTDemucs | 10 artifact | 11 artifact | 12 artifact |
| BS-RoFormer-SW | 14 artifact | 15 artifact | 16 artifact |

BS代表実曲の容量は、補正完了1,269,858,464 bytes、再ミックス完了
1,364,403,360 bytes、マスタリング完了1,458,948,256 bytesだった。
4回のbenchmark終了後、`StemBaselineModel-*`の一時installation directoryは0件で、
benchmarkのrun directoryも残っていない。`VelouraLucentStemPreview`に残る1 runは、
手順14の実画面A/B確認で使った別run `371d5999-a1b0-4a9e-ab02-dc15d4b4d8ad`であり、
今回のbenchmarkによるcleanup漏れではない。

## 実行方法

先にRelease test bundleをbuildする。

```bash
swift test -c release --filter productionBaselineMetricsForSelectedModelWhenEnabled
```

モデルごとに別processで実行する。

```bash
env \
  VELOURA_RUN_STEM_BASELINE_BENCHMARK=1 \
  VELOURA_STEM_BASELINE_MODEL=htdemucs \
  VELOURA_STEM_BASELINE_INPUT=.stem-model-cache/bs-roformer-sw/compatibility-input/sample-6.8s-44100-f32.wav \
  /usr/bin/time -l swift test -c release --skip-build \
  --filter productionBaselineMetricsForSelectedModelWhenEnabled
```

`VELOURA_STEM_BASELINE_MODEL`は`htdemucs`または`bsRoformerSW`、
`VELOURA_STEM_BASELINE_INPUT`はproject rootからの相対pathまたは絶対pathを指定する。
テストは`VELOURA_STEM_BASELINE_METRICS`に続けて工程別JSONを出力する。

## 測定上の制限

- 補正・再ミックス・マスタリング各工程単独の最大RSSは未測定。最大RSSは全工程process値。
- 代表実曲の数値は1回測定であり、反復分布は未測定。
- cancel、再ミックス失敗、マスタリング失敗後のcleanupは、別の異常系自動テストで確認した。
