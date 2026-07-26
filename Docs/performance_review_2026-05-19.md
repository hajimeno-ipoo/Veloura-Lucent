# Veloura Lucent 性能レビュー 2026-05-19

## 結論

性能上の主因は、音声処理そのものだけではなく、解析、ノイズ測定、表示用解析の重複です。

この報告は、実コード、実行したテスト、実音源ベンチの結果に基づきます。予測や憶測は含めていません。

## 実行した確認

| 確認 | 結果 |
|---|---:|
| `swift build` | 成功、0.20秒 |
| `swift test --filter NativeAudioProcessorBenchmarkTests` | 成功、8.819秒 |
| `swift test --filter MasteringAnalysisServiceTests` | 成功、1.755秒 |
| `swift test --filter AudioAnalysisModeTests` | 成功、24.676秒 |
| `swift test --filter ContentViewAnalysisLoggingTests` | 成功、0.001秒 |
| `VELOURA_RUN_REAL_AUDIO_BENCHMARK=1 swift test --filter NativeAudioProcessorBenchmarkTests/recordsRealAudioCPUAndExperimentalMetalBenchmark` | 成功、2203.567秒 |

## 実音源ベンチ結果

対象音源:

`/Users/apple/Desktop/Dev_App/Veloura Lucent/Tests/Fixtures/Sample_audio/violin #002 睡眠.wav`

| 項目 | CPU | 実験Metal | CPU / 実験Metal |
|---|---:|---:|---:|
| 合計 | 1302.124034秒 | 901.368122秒 | 1.445倍 |
| 読み込み | 0.024584秒 | 0.035421秒 | 0.694倍 |
| 解析 | 296.771831秒 | 85.245400秒 | 3.481倍 |
| ルート用ノイズ測定 | 197.400838秒 | 224.861296秒 | 0.878倍 |
| 低域整理 | 66.250676秒 | 77.420606秒 | 0.856倍 |
| ノイズ除去 | 150.052794秒 | 151.481255秒 | 0.991倍 |
| サ行保護 | 10.831726秒 | 11.322381秒 | 0.957倍 |
| 再解析 | 312.470222秒 | 90.315185秒 | 3.460倍 |
| 解析補助 | 0.000004秒 | 0.000002秒 | 1.915倍 |
| 高域修復 | 22.327769秒 | 19.161398秒 | 1.165倍 |
| 修復後シマー保護 | 0.000000秒 | 0.000000秒 | 0.000倍 |
| 低中域整理 | 0.000000秒 | 0.000000秒 | 0.000倍 |
| シマー制限 | 0.000000秒 | 0.000000秒 | 0.000倍 |
| 補正後高域保持 | 140.154458秒 | 141.185888秒 | 0.993倍 |
| 低中域残り確認 | 78.111870秒 | 75.599595秒 | 1.033倍 |
| ピーク保護 | 27.661134秒 | 24.680377秒 | 1.121倍 |
| 書き出し | 0.066130秒 | 0.059318秒 | 1.115倍 |

## 指摘 1: 実音源の補正処理が長すぎる

優先度: P1

実音源ベンチでは、CPU版が 1302.124034秒、実験Metal版が 901.368122秒でした。

実験Metalでも約15分かかっています。

重い工程は次の通りです。

| 工程 | 実験Metalでの時間 |
|---|---:|
| ルート用ノイズ測定 | 224.861296秒 |
| ノイズ除去 | 151.481255秒 |
| 補正後高域保持 | 141.185888秒 |
| 再解析 | 90.315185秒 |
| 解析 | 85.245400秒 |
| 低中域残り確認 | 75.599595秒 |

根拠箇所:

| 内容 | ファイル |
|---|---|
| 補正後高域保持でノイズ測定を繰り返す | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/NativeAudioProcessor.swift:614` |
| ノイズ測定で指定IDごとに測定処理を実行する | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/NoiseMeasurementService.swift:60` |
| `QuietFloorContext` が1回の測定内で静かな区間のフレームを再利用する | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/NoiseMeasurementService.swift:102` |
| `bandPass` が highPass と lowPass を4回繰り返す | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/NoiseMeasurementService.swift:135` |
| `frameRMS` がフレームごとにサンプルを走査する | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/NoiseMeasurementService.swift:288` |

改善対象:

`NoiseMeasurementService.analyze` 1回の中で、hiss、shimmer、rumble、room が共通で使う `referenceFrames` を再利用する必要があります。

今回の実装では、この範囲だけ対応済みです。

工程をまたぐ測定結果キャッシュ、ファイル単位のキャッシュ、`NativeAudioProcessor` / `MasteringProcessor` の処理順変更は行っていません。

## 指摘 2: 表示用解析とプレビュー生成で同じ音源を別々に読み込み・解析している

優先度: P1

入力ファイルを選ぶと、`analyzeMetrics` が実行されます。

同時に `preparePreviewCards` も呼ばれ、`AudioPreviewController.preparePreview` が同じ音源を読み込んでプレビュー用データを作ります。

つまり、入力直後から同じ音源に対して重い処理が二重に走る構造です。

根拠箇所:

| 内容 | ファイル |
|---|---|
| 入力選択後に `analyzeMetrics` を実行 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Views/ContentView.swift:68` |
| 表示用解析でファイル読み込み、比較指標、ノイズ測定、スペクトログラム生成を実行 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Views/ContentView.swift:2233` |
| プレビュー側でもファイル読み込み、プレビュー生成、ラウドネス測定を実行 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Models/AudioPreviewController.swift:192` |

改善対象:

表示用解析で読み込んだ `AudioSignal` と、そこから作ったプレビュー情報をプレビュー側へ渡し、同じ音源を再読み込みしない構造にする必要があります。

## 指摘 3: プレビュー用STFTとスペクトログラム用STFTが重複している

優先度: P1

`makePreviewSnapshot` は `makeBandLevels` 内で STFT を作ります。

`makeSpectrogramSnapshot` も、同じ `fftSize = 1024`、`hopSize = 1024` で STFT を作ります。

補正後、最終版では、`makeAnalysisArtifacts` の中でプレビュー生成とスペクトログラム生成が同時に走るため、同じ音源に対してSTFTが重複します。

根拠箇所:

| 内容 | ファイル |
|---|---|
| プレビュー生成で帯域レベルを作る | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/AudioFileService.swift:90` |
| スペクトログラム生成でSTFTを作る | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/AudioFileService.swift:111` |
| プレビュー用帯域レベルでもSTFTを作る | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/AudioFileService.swift:201` |

改善対象:

同じ `Spectrogram` から、プレビュー用帯域レベルとスペクトログラム表示用セルを作る構造にする必要があります。

## 指摘 4: 重い解析を同時に走らせすぎている

優先度: P2

`makeAnalysisArtifacts` は、次の処理を `async let` で同時に走らせています。

- プレビュー生成
- 比較指標
- マスタリング解析
- 補正解析
- ノイズ測定
- スペクトログラム生成

さらに `AudioComparisonService.analyzeConcurrently` の中でも `Task.detached` を複数作っています。

構造上、CPUとメモリを一気に使う設計です。

UI固まりへの直接影響はこのレビューでは未計測です。ただし、重い処理を同時に増やしていることはコードで確認済みです。

根拠箇所:

| 内容 | ファイル |
|---|---|
| 表示用解析を `Task.detached` と `async let` で同時実行 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Views/ContentView.swift:2233` |
| 比較指標の中でも複数の `Task.detached` を作成 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Services/AudioComparisonService.swift:33` |

改善対象:

表示に必須の解析と、後から表示できる解析を分ける必要があります。

また、同時実行数を制限し、UI操作中にCPUを使い切らない構造にする必要があります。

## 指摘 5: 再生中UIは20回/秒で状態を書き換える

優先度: P2

`meterInterval = 0.05` なので、再生中は毎秒20回 `updateMeters` が動きます。

その中で `playbackProgresses` と `liveBandLevels` を更新します。

`PreviewPanelView` はカード表示の中で、波形、ライブ帯域、再生時間を表示します。

実際のフレーム落ちはこのレビューでは未計測です。ただし、20回/秒でUI状態を書き換える構造はコードで確認済みです。

根拠箇所:

| 内容 | ファイル |
|---|---|
| 20回/秒のメーター更新間隔 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Models/AudioPreviewController.swift:36` |
| Timerで `updateMeters` を繰り返し実行 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Models/AudioPreviewController.swift:257` |
| プレビューカードで波形とライブ帯域を表示 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Views/PreviewPanelView.swift:107` |

改善対象:

再生中に更新する状態を、再生中カードだけへ限定する必要があります。

必要であれば、更新間隔を 0.05秒から 0.10秒へ変更する検証も行います。ただし、これは実装前に体感と表示品質を確認する必要があります。

## 指摘 6: ログを1つの長い文字列として伸ばし続けている

優先度: P2

`appendLog` と `appendMasteringLog` は、ログが増えるたびに `String` へ追記します。

画面側は、その全文を `Text` で表示します。

長時間処理ではログが増えるほど、文字列コピーと再描画の負担が増えます。

根拠箇所:

| 内容 | ファイル |
|---|---|
| 補正ログを文字列へ追記 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Models/ProcessingJob.swift:383` |
| マスタリングログを文字列へ追記 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Models/ProcessingJob.swift:399` |
| ログ全文を `Text` で表示 | `/Users/apple/Desktop/Dev_App/Veloura Lucent/Sources/VelouraLucent/Views/ContentView.swift:1975` |

改善対象:

ログは `[String]` で保持し、表示時だけ必要範囲を結合する構造にする必要があります。

また、進行状況は既存の `ProcessingProgressEvent` を使い、ログ全文の再描画に依存しない表示を優先します。

## 優先順位

| 優先 | 対象 | 理由 |
|---:|---|---|
| 1 | `NoiseMeasurementService` 内部の `referenceFrames` 再利用 | 実音源ベンチで長時間化の大きな原因になっているノイズ測定の一部を、音質処理の意味を変えずに減らせる |
| 2 | 表示用解析とプレビュー生成の統合 | 入力直後と処理後の重複読み込み、重複解析を減らせる |
| 3 | プレビュー用STFTとスペクトログラム用STFTの共有 | 同じ `fftSize` と `hopSize` のSTFTを二重に作っている |
| 4 | 表示用解析の同時実行数制限 | CPUとメモリを一気に使う状態を抑える |
| 5 | 再生中メーター更新範囲の縮小 | UI再描画の範囲を狭める |
| 6 | ログ保持形式の変更 | 長時間処理での文字列コピーとログ全文再描画を減らす |

## 未確認

| 未確認 | 理由 |
|---|---|
| 実アプリ画面でのフレーム落ち | Instruments または最小限の `OSLog` signpost を入れないと断定できない |
| 操作中の固まりがどのUI部品で発生するか | 実アプリ操作中の計測が必要 |
| メーター更新間隔を変更した時の見え方 | 体感と表示品質の確認が必要 |

## 次に進む場合の実装方針

1. `NoiseMeasurementService` 内部で、1回の `analyze` 実行中だけ `referenceFrames` を再利用する。これは対応済みです。
2. 次に `makeAnalysisArtifacts` と `AudioPreviewController.preparePreview` の重複読み込みをなくす。
3. その後、プレビュー用STFTとスペクトログラム用STFTを共有する。
4. 表示用解析は、すぐ必要なものと後から表示できるものに分ける。
5. UI再描画は、再生中カードとログ表示を中心に範囲を狭める。

この順番なら、音質処理の意図を変えずに、実測で重かった部分から改善できます。
