# Veloura Lucent — Stem Mode 実装資料

- 対象リポジトリ: `hajimeno-ipoo/Veloura-Lucent`
- 確認対象: `master` ブランチを 2026-07-02（JST）に取得した時点の実装
- 現状アプリ再照合: 2026-07-13（JST）に、Stem Mode未実装の現状、2mix補正・マスタリング経路、根拠一覧のblob SHAを再確認
- Stem Mode検証: 2026-07-02（JST）に `/tmp/veloura-stem-verify` で実施した `Demucs v4 htdemucs` / Core ML / MLX Swift / Python MLX の実測結果を反映
- 文書目的: `2mix → ステム分離 → ステム別補正 → 再ミックス → マスタリング` を実装するための、仕様・設計・検証・導入条件を一つにまとめる
- 根拠: 本文の「現状」は、末尾に列挙した実コードおよび公式ドキュメントのみを根拠とする
- 非根拠: READMEだけの記述、未検証モデルの性能、未測定の長尺処理速度、未確認の分離品質、未確認の再配布可否は根拠に含めない
- 表記: 「現状」はリポジトリ内で確認できた事実。「提案」は実装のために本書で定義する追加設計。両者を混同しない

---

## 1. 結論

### 1.1 実装可否

Stem Mode は実装可能である。

現行アプリには、Stem Mode の後半に必要な次の基盤が存在する。

- 音声を `AudioSignal` として読み込み、48 kHzへ変換する入出力層
- 補正処理の段階的な実装
- 再ミックス後の2mixを入力にできるマスタリングサービス
- 原音を参照としてマスタリングへ渡す経路
- ピーク、ノイズ戻り、高域、低中域、最終音量を確認する既存のマスタリング工程
- 補正・マスタリングの個別テスト

一方で、Stem Mode の中核である次の機能は、確認対象の実装には存在しない。

- ステム分離器
- ステムを表すデータモデル
- ステム別処理ポリシー
- 再ミックス器
- 分離／再ミックスの品質検証
- Stem Mode専用の進捗・UI状態
- Stem Mode専用のログ、最近の操作、完了通知ドメイン
- ステム書き出し
- Core MLまたはMLXモデルの同梱と推論

したがって、既存の通常モードを改変して無理に組み込むのではなく、既存の `MasteringService` の前に新しいワークフローを追加する。

```text
Stem Mode
入力2mix
  ↓
ステム分離
  ↓
ステム別補正
  ↓
再ミックス
  ↓
既存 MasteringService
  ↓
最終版
```

### 1.2 初期版の対象範囲

本書では、初期版の内部処理を4ステムに固定する。

```text
vocals
drums
bass
other
```

ユーザー向けの簡易表示や書き出しでは、必要に応じて次の2系統も生成してよい。

```text
vocals
no_vocals = drums + bass + other
```

ただし、ステム別補正の判断単位は4ステムを基本とする。理由は、`Demucs v4 htdemucs` と `mlx-community/demucs-mlx` の `htdemucs` が4ステム（drums / bass / other / vocals）を出力する契約であり、内部を2ステムへ潰すとドラム、ベース、その他に別々の補正ポリシーを適用できなくなるためである。

---

## 2. 実コードから確認した現状

### 2.1 パッケージとリソース

現行の `Package.swift` は以下を定義している。

- Swift tools version: 6.2
- 対象プラットフォーム: macOS 26
- 実行ターゲット: `VelouraLucent`
- 現在登録されているリソース:
  - `Resources/AppIcon-1024.png`
  - `Resources/Rotary_Knob`

確認した `Package.swift` に、ステム分離モデル、Core MLモデル、MLX依存、外部パッケージ依存は記述されていない。

このため、Stem Modeでモデルを同梱する場合は、モデル資産の配置とリソース登録を新設する必要がある。

### 2.2 音声入出力

`AudioFileService.loadAudio(from:)` は次の順序で音声を読み込む。

1. `AVAudioFile` で読み込む
2. `pcmFormatFloat32` の非インターリーブ形式へ読み込む
3. `AudioSignal` へ変換する
4. サンプルレートが48 kHzでない場合、48 kHzへ変換する

`AudioFileService.saveAudio(_:to:)` は `AudioSignal` を書き出す。

重要な事実:

- 現行の読み込みはファイル全体を `AVAudioPCMBuffer` に格納している
- 現行のサービス境界は、主にファイルURLを受け、WAVを出力する形である
- `AudioSignal.frameCount` は先頭チャンネルの長さを返すだけで、全チャンネルの長さ一致を型では保証しない
- Stem Modeは複数ステムを扱うため、長尺ファイルで一時ファイルとメモリの両方をどう扱うかを設計に含める必要がある

採用モデルは `htdemucs` とする。ただし、アプリ本体へ組み込んだ状態でのチャンク長・オーバーラップ長・メモリ上限は、長尺音源での実測後に固定する。

### 2.3 現行の補正経路

`AudioProcessingService.process(...)` は、入力ファイルURLを受け、`NativeAudioProcessor.process(...)` を呼び、補正後URLを返す。

`NativeAudioProcessor` の現在のトップレベル経路は、以下の順で構成される。

```text
入力読み込み
→ 原音解析
→ ルート用ノイズ測定
→ 補正ルート決定
→ 低域ノイズ整理
→ ノイズ除去
→ サ行／シマー保護
→ 高域修復準備
→ 高域修復
→ 修復後シマー保護
→ 低中域残り整理
→ シマー制限
→ 補正後高域保持
→ 補正後mudガード
→ ピーク保護
→ 保存
```

現状の公開入口は、入力ファイルURLと出力ファイルURLを扱う `process(...)` である。

現行コードには、役割名を入力として「ボーカル用」「伴奏用」などの工程を選択する公開APIは確認できない。

このため、Stem Modeのステム別補正では、既存の補正エンジンをそのまま全ステムへ一律適用してはならない。役割別に通す工程を選べる追加設計が必要である。

### 2.4 現行のマスタリング経路

`MasteringService.process(...)` は次を行う。

```text
入力読込
→ 任意の原音参照読込
→ マスタリング解析
→ ノイズ測定
→ MasteringProcessor.process
→ 保存
```

`MasteringService.process(...)` は `originalReferenceFile` と `originalReferenceNoiseMeasurements` を受け取れる。

したがってStem Modeでは、次の接続が可能である。

```text
MasteringService の入力:
  再ミックス後の補正済み2mix

originalReferenceFile:
  分離前の原音2mix
```

`MasteringProcessor` には、音色、ディエッサー、ダイナミクス、倍音、空気感、ステレオ、ラウドネス、高域／ノイズ戻りガード、高域保持、最終音量復帰、最終低中域保護、最終音量上限の工程がある。

### 2.5 UIと状態管理

`ProcessingJob` は、現在以下の3段階を中心に保持する。

```text
inputFile
outputFile
masteredOutputFile
```

UIの実行操作も、現状は次の2つである。

```text
補正を実行
マスタリングを実行
```

また、補正進捗とマスタリング進捗は分かれている。

```text
isProcessing / correctionProgress
isMastering / masteringProgress
```

現行UIはステムの一覧、ステム別プレビュー、再ミックス出力、Stem Modeの固有進捗を持たない。

現行の `RecentActivityDomain` は `input` / `correction` / `mastering` / `export` の4種類である。

現行の `ProcessingProgressEvent.Domain` は `correction` / `mastering` の2種類である。

現行の `CompletionNotificationDomain` は `correction` / `mastering` の2種類である。

このため、Stem Modeを独立した処理として表示・記録・通知するには、既存の補正・マスタリング用ドメインを流用せず、Stem Mode用の扱いを追加する必要がある。

### 2.6 テストの現状

確認したテストには、通常の補正およびマスタリングについて、次の確認がある。

- 出力ファイル作成
- 有限値であること
- ピーク上限
- ノイズ戻りガードの反復数
- ダイナミクス保持
- 高域保持
- 最終音量復帰
- 原音参照を使った高域回復

一方、Stem Modeについて次のテストは確認できない。

- 4ステム合算と原音の残差
- ステム同期
- 再ミックスの位相／相関
- ステム別補正
- 分離失敗時のフォールバック
- Core ML推論またはMLX推論の入力／出力契約
- Core ML変換後またはMLX変換後の出力一致

---

## 3. 実装方針

### 3.1 既存の通常モードを保持する

通常モードは変更しない。

```text
Standard Mode
入力2mix
→ AudioProcessingService
→ MasteringService
→ 最終版
```

Stem Modeは別経路として追加する。

```text
Stem Mode
入力2mix
→ StemSeparationService
→ StemRepairService
→ StemMixService
→ MasteringService
→ 最終版
```

### 3.2 2mix補正を分離前に実行しない

Stem Modeでは、既存の `AudioProcessingService` を分離前に通さない。

これは本書の設計要件である。

分離前に2mixへ補正を適用すると、分離器への入力波形が通常モードと異なる処理済み信号になる。Stem Modeでは、分離器の入力は原音2mixに統一し、補正は分離後に役割別に適用する。

### 3.3 初期版は4ステムを役割別に補正する

初期版の補正対象は、分離された4ステムを基本とする。

```text
vocals:
  ボーカル向けのノイズ、サ行、息感、高域保持を中心に補正

drums:
  アタック、シンバル、空気感を削りすぎない範囲で補正

bass:
  低域の芯、位相、過剰な低域ノイズを中心に補正

other:
  残りの楽器成分として、過剰処理を避けて補正
```

初期版では、4ステムを個別に解析し、役割別に通す工程を選ぶ。
既存の2mix向け補正を全ステムへ一律適用してはならない。

再ミックスでは、ユーザーまたは自動処理による音量・パン・ステレオ幅の変更を初期版で行わない。

```text
remix = repairedVocals + repairedDrums + repairedBass + repairedOther
```

この仕様は、初期版の再ミックスを「素材の再解釈」ではなく「役割別に必要な成分だけを補正した復元」と位置づけるための設計上の制約である。

---

## 4. 新規コンポーネント仕様

### 4.1 新規ファイル一覧

| パス | 種別 | 役割 |
|---|---|---|
| `Sources/VelouraLucent/Models/StemModels.swift` | 新規 | ステムの役割、成果物、検証結果 |
| `Sources/VelouraLucent/Models/StemModeSettings.swift` | 新規 | Stem Modeの設定と適用済み設定 |
| `Sources/VelouraLucent/Services/StemSeparationService.swift` | 新規 | 分離器の共通インターフェース |
| `Sources/VelouraLucent/Services/MLXStemSeparationService.swift` | 新規 | `htdemucs` のMLX Swift推論実装 |
| `Sources/VelouraLucent/Services/CoreMLStemSeparationService.swift` | 初期版対象外 | Core ML再検証を行う場合だけ追加 |
| `Sources/VelouraLucent/Services/StemRepairService.swift` | 新規 | ステム別補正の統括 |
| `Sources/VelouraLucent/Services/StemMixService.swift` | 新規 | 再ミックスと検証前の整合 |
| `Sources/VelouraLucent/Services/StemValidationService.swift` | 新規 | 分離・再ミックスの品質検証 |
| `Sources/VelouraLucent/Services/StemWorkflowService.swift` | 新規 | Stem Mode全体の実行 |
| `Sources/VelouraLucent/Services/StemWorkflowLogging.swift` | 新規 | Stem Mode専用ログと進捗イベント |
| `Sources/VelouraLucent/Models/StemWorkflowState.swift` | 新規 | Stem Mode専用の実行状態 |
| `Sources/VelouraLucent/Models/StemWorkflowProgress.swift` | 新規 | Stem Mode専用の進捗状態 |
| `Sources/VelouraLucent/Views/StemModeRootView.swift` | 新規 | Stem Mode専用画面一式の親View |
| `Sources/VelouraLucent/Views/StemModeToolbarView.swift` | 新規 | Stem Mode専用の実行、キャンセル、書き出し操作 |
| `Sources/VelouraLucent/Views/StemModeSidebarView.swift` | 新規 | Stem成果物とStem Mode専用工程進捗 |
| `Sources/VelouraLucent/Views/StemModeWorkspaceView.swift` | 新規 | Stem別プレビュー、再ミックス、最終版比較 |
| `Sources/VelouraLucent/Views/StemModeInspectorView.swift` | 新規 | Stem Mode設定、補正方針、検証結果、モデル情報 |
| `Sources/VelouraLucent/Views/StemModeFooterView.swift` | 新規 | Stem Mode専用ログと全体進捗 |
| `Tests/VelouraLucentTests/StemMixServiceTests.swift` | 新規 | 再ミックス単体テスト |
| `Tests/VelouraLucentTests/StemValidationServiceTests.swift` | 新規 | 残差、同期、位相検証テスト |
| `Tests/VelouraLucentTests/StemWorkflowTests.swift` | 新規 | ワークフロー統合テスト |
| `Tests/VelouraLucentTests/MLXStemSeparationContractTests.swift` | 新規 | MLX案の入出力契約テスト |
| `Tests/VelouraLucentTests/CoreMLStemSeparationContractTests.swift` | 初期版対象外 | Core ML案を再開する場合だけ追加 |

### 4.2 データモデル

以下は提案APIであり、現行実装には存在しない。

```swift
enum StemRole: String, CaseIterable, Identifiable, Sendable, Codable {
    case vocals
    case drums
    case bass
    case other

    var id: String { rawValue }
}

struct StemAudioArtifact: Sendable {
    let role: StemRole
    let fileURL: URL
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
}

struct StemSeparationResult: Sendable {
    let source: StemAudioArtifact
    let stems: [StemAudioArtifact]
    let modelIdentifier: String
    let modelVersion: String
}

struct StemMixResult: Sendable {
    let mixedFileURL: URL
    let sourceFileURL: URL
}

struct StemValidationResult: Sendable {
    let passed: Bool
    let failedChecks: [StemValidationCheck]
    let measurements: [StemValidationMeasurement]
}

enum StemValidationCheck: String, CaseIterable, Sendable, Codable {
    case stemCount
    case roleCoverage
    case channelFrameCounts
    case sampleRate
    case channelCount
    case finiteSamples
    case residual
    case peak
    case correlation
}

struct StemValidationMeasurement: Sendable, Codable {
    let id: String
    let value: Double
    let unit: String
}
```

`modelIdentifier` には `mlx-community/demucs-mlx/htdemucs`、`modelVersion` には採用したモデル配布元のrevisionまたはchecksumを保存する。
実装時には、推論結果とともに必ず保存する。

### 4.3 分離サービスのインターフェース

```swift
protocol StemSeparationService: Sendable {
    func separate(
        inputFile: URL,
        mode: StemModeSettings,
        outputDirectory: URL,
        logger: StemWorkflowLogging
    ) async throws -> StemSeparationResult
}
```

このプロトコルの責務は、モデル固有の差異を `MLXStemSeparationService` の内部へ閉じ込めることにある。

上位の `StemWorkflowService` は、モデル名、テンソル名、入力shape、出力shape、チャンク方法を直接知ってはならない。

`StemWorkflowLogging` は、既存の `AudioProcessingLogger` と同じように処理ログを流せることに加え、Stem Mode専用の進捗イベントを発行できる責務を持つ。

### 4.4 分離サービス実装の責務

`MLXStemSeparationService` は、`StemSeparationService` に準拠し、以下を担当する。

1. モデル資産の取得
2. モデルの入力仕様の読み取りまたは固定契約の検証
3. 入力音声のモデル入力形式への変換
4. 分離推論
5. モデル出力を `drums` / `bass` / `other` / `vocals` へ対応付ける
6. 一時ステムファイルの保存
7. 推論に使ったモデル識別情報の記録

MLX案では、MLX Swiftを使い、Swift側でMLX配列へ音声チャンクを渡す。MLX SwiftはApple Silicon向けのMLXをSwiftから扱うAPIである。

Core ML案は、2026-07-02の検証で `htdemucs` の通常変換が失敗したため、初期版では実装しない。将来Core ML案を再開する場合は、Core ML向けに固定長・固定shapeへモデル処理を書き換える別作業として扱う。

モデルの入出力、dtype、チャンネル順、正規化、サンプルレート、チャンク長、実行方式は、`StemModelContract` としてコードおよびテストへ固定する。

---

## 5. Stem Modeワークフロー仕様

### 5.1 全体フロー

```text
[1] 入力検証
  ↓
[2] 原音2mixを保持し、分離用に44.1 kHz / stereo / Float32へ変換
  ↓
[3] MLX Swift `htdemucs` による4ステム分離
  ↓
[4] 分離直後の検証
  ↓
[5] 4ステムを役割別に補正
  ↓
[6] 再ミックス
  ↓
[7] 再ミックス検証
  ↓
[8] 既存MasteringServiceで最終仕上げ
  ↓
[9] 最終出力検証・書き出し
```

### 5.2 入力検証

Stem Mode開始時に、以下を確認する。

| 項目 | 判定 |
|---|---|
| 入力ファイル存在 | 必須 |
| 読み込み可否 | 必須 |
| チャンネル数 | 分離器入力はstereo |
| サンプルレート | 分離器入力は44.1 kHz、既存マスタリング入力では現行どおり48 kHzへ変換され得る |
| フレーム数 | 0より大きい |
| 有限値 | NaN / ±Infinityを含まない |

### 5.3 分離直後の検証

分離直後に、以下を必ず測る。

| 検証 | 定義 |
|---|---|
| ステム数 | 初期版は必ず4 |
| 役割 | `drums` / `bass` / `other` / `vocals` が一つずつ |
| フレーム数 | 分離用に44.1 kHz化した原音と各ステムで一致 |
| チャンネル内フレーム数 | 各ステム内の全チャンネルで一致 |
| サンプルレート | 分離用原音と各ステムで一致 |
| チャンネル数 | stereoで一致 |
| 有限値 | 各ステムにNaN / ±Infinityがない |
| 合算残差 | `source44100 - (drums + bass + other + vocals)` |
| ピーク | 各ステムのピークを記録 |
| 相関 | 原音と再合成音、および左右相関を記録 |

合算残差の測定式:

```text
residual[n] = source44100[n] - drums[n] - bass[n] - other[n] - vocals[n]
```

本書では、合格・不合格の数値閾値を固定しない。

閾値は、採用モデル、モデル契約、ライセンス上利用可能な評価音源、実装後の測定結果を根拠として別途決定する。根拠がない段階でdB値を決めない。

### 5.4 ステム別補正

初期版の補正方針を次の通り固定する。

| ステム | 初期版の処理 |
|---|---|
| vocals | ボーカル向けのStemRepairServiceで補正 |
| drums | アタックとシンバルを削りすぎない範囲で補正 |
| bass | 低域の芯と位相を壊さない範囲で補正 |
| other | 残りの楽器成分として過剰処理を避けて補正 |
| 再ミックス後の2mix | 既存MasteringServiceでマスタリング |

各ステムの補正に使う既存処理は、役割別の工程選択を実装してから利用する。

現行 `NativeAudioProcessor` は、入力ファイルに対して一連の2mix向け補正工程を実行する。Stem Mode用には、少なくとも次の二択を明示的に実装する必要がある。

```text
A. NativeAudioProcessorへStem用の工程選択APIを追加する
B. StemRepairProcessorを新設し、既存DSP部品を役割別に呼ぶ
```

初期版の必須条件は、「各ステムに適用した工程」と「各ステムに適用しなかった工程」をログと成果物から再現可能にすることである。

### 5.5 再ミックス

初期版の再ミックス要件は次の通り。

```text
mix[n] = repairedVocals[n] + repairedDrums[n] + repairedBass[n] + repairedOther[n]
```

禁止事項:

- 自動音量調整
- 自動パン変更
- 自動ステレオ幅変更
- 自動コンプレッション
- 再ミックス段でのラウドネス目標追従
- 再ミックス段での最終リミッティング

再ミックス段の役割は、補正済み4ステムを同じ時間軸で合成することだけである。

再ミックス計算は、分離器出力と同じ44.1 kHzのステムを同一時間軸で合算する。
その後、既存 `MasteringService` へ渡す再ミックス成果物は、48 kHz / stereo / Float32のWAVとして保存する。
これにより、分離・残差検証は44.1 kHz基準で行い、既存表示・解析・マスタリング経路は現行アプリの48 kHz基準へ揃える。

ピーク処理は、再ミックス検証で記録し、最終的なラウドネス・リミッティングは既存の `MasteringService` に委ねる。

### 5.6 再ミックス検証

再ミックス後に、以下を検証する。

| 検証 | 内容 |
|---|---|
| 長さ | 48 kHz化した原音参照と再ミックスのフレーム数が一致 |
| チャンネル内フレーム数 | 再ミックス内の全チャンネルで一致 |
| 形式 | 48 kHz、チャンネル数の一致 |
| 有限値 | NaN / ±Infinityなし |
| ピーク | クリップ状態ではないこと |
| 相関 | 左右相関および原音との比較を記録 |
| 再ミックス差分 | 原音と再ミックスの帯域差分を記録 |
| ノイズ | Vocal補正により再ミックスのノイズ指標がどう変化したかを記録 |

再ミックス検証が失敗した場合の規約:

```text
Stem Modeの処理を失敗として終了する
→ 再ミックス音を最終版として保存しない
→ 既存Standard Modeを自動実行しない
```

自動でStandard Modeへ切り替えると、ユーザーがStem Modeを選んだのに別処理が走った事実が不透明になるためである。フォールバックはUI上で明示的に選択させる。

### 5.7 マスタリング

再ミックス検証に通過した場合のみ、既存の `MasteringService` を使用する。
ここで渡す `remixedFileURL` は、48 kHz / stereo / Float32で保存済みの再ミックス成果物とする。

```text
MasteringService.inputFile
  = remixedFileURL

MasteringService.originalReferenceFile
  = originalInputFileURL

MasteringService.referenceNoiseMeasurements
  = 再ミックス後の測定値

MasteringService.originalReferenceNoiseMeasurements
  = 原音2mixの測定値
```

原音のノイズ測定を、再ミックス音の `referenceNoiseMeasurements` として流用してはならない。

---

## 6. UI・状態管理仕様

### 6.0 UI設計方針

Stem Modeは、ステム分離だけを行う画面ではない。

Stem Modeは、2mix入力から、ステム分離、ステム別補正、再ミックス、マスタリング、最終版生成までを扱う専用ワークフロー画面とする。

Stem Mode追加によって変更するUIは、Stem Mode選択時に表示される専用画面一式に限定する。

通常モードの既存画面、既存ツールバー、左サイドバー、中央ワークスペース、右インスペクタ、下部フッター、進捗表示、最近の操作、書き出し導線は現行動作を維持する。

モード切り替えは、通常モード画面へStem要素を混ぜるためのものではない。
通常モードとStem Modeは同じウィンドウ内で切り替えるが、表示される作業画面一式は別物として扱う。

共通で持つのは、ウィンドウ枠、モード切り替え、入力音声選択など、両モードに必要な最小限の外枠だけとする。
通常モードの処理状態、進捗、ボタン、ログ、通知、書き出しメニューをStem Modeへ流用してはならない。

### 6.1 新しいモード

```swift
enum ProcessingMode: String, CaseIterable, Identifiable {
    case standard
    case stem

    var id: String { rawValue }
}
```

表示文言:

```text
通常補正
Stem Mode
```

### 6.2 モード切り替えとStem Mode専用状態

`processingMode` は、通常モードとStem Modeを切り替えるための共通外枠の状態である。
通常補正の工程状態として扱ってはならない。

```swift
var processingMode: ProcessingMode
var stemWorkflowState: StemWorkflowState
var stemWorkflowError: String?
var stemOutputFiles: [StemRole: URL]
var remixedOutputFile: URL?
var stemValidationResult: StemValidationResult?
var appliedStemModeSettings: StemModeSettings?
```

Stem Modeの状態は、通常モードの処理状態へ混ぜない。

現行の `outputFile`、`hasExistingOutput`、`isProcessing`、`progressValue`、`beginProcessing(...)`、`finishSuccess(...)`、`finishFailure(...)` は通常モード用の状態とする。

Stem Modeでは、再ミックス後・マスタリング前の2mixを `remixedOutputFile` として保持する。
通常モードの `outputFile` へ接続するのではなく、Stem Mode専用画面の中で再ミックス、最終版、ステム成果物を表示する。

Stem Modeには、専用の開始・完了・失敗・キャンセルメソッドを追加する。
これらはStem Mode専用の文言、進捗、通知、最近の操作、ログだけを更新する。

既存の波形、スペクトル、スペクトログラム、プレビュー部品をStem Mode画面で再利用する場合も、通常モードの状態を書き換えず、Stem Mode専用状態から表示用のURLと解析結果を渡す。

### 6.3 UI操作規約

Stem Mode選択時は、通常モードの画面にステム機能を追加するのではなく、Stem Mode専用の作業画面へ切り替える。

| 表示モード | 目的 | 画面構成 | 実行操作 |
|---|---|---|---|
| 通常モード | 既存の2mix補正とマスタリング | 現行の通常モード画面を維持 | 現行どおり `補正を実行` / `マスタリングを実行` |
| Stem Mode | 分離、ステム別補正、再ミックス、マスタリング、最終版生成 | Stem Mode専用の上部操作、左サイドバー、中央ワークスペース、右インスペクタ、下部フッター | `Stem Modeを実行` |

Stem Mode専用画面で扱う主な成果物:

```text
入力2mix
Vocals stem
Drums stem
Bass stem
Other stem
No vocals stem
再ミックス
マスタリング後の最終版
```

Stem Modeの主操作は、次の一連の処理を実行する。

```text
入力検証
→ ステム分離
→ 分離結果検証
→ ステム別補正
→ 再ミックス
→ 再ミックス検証
→ マスタリング
→ 最終版生成
```

Stem Mode選択時に専用化するUI領域:

```text
上部操作:
- Stem Mode実行
- Stem Modeキャンセル
- Stem Mode成果物の書き出し

左サイドバー:
- 入力2mix
- Vocals stem
- Drums stem
- Bass stem
- Other stem
- No vocals stem
- 再ミックス
- マスタリング後の最終版
- Stem Mode専用工程進捗

中央ワークスペース:
- Stem別プレビュー
- Stem別の波形または解析表示
- 再ミックスと最終版の比較表示

右インスペクタ:
- Stem Mode設定
- Stem別補正方針
- Stem検証結果
- モデル情報とchecksum表示

下部フッター:
- Stem Mode専用ログ
- Stem Mode全体の進捗
- 分離、ステム別補正、再ミックス、マスタリング、最終版生成、書き出しの状態
```

Stem Modeの書き出し導線は、最終版の書き出しを主導線とする。
ステム個別書き出し、No vocals書き出し、再ミックス書き出しは副導線として扱う。

通常モード中は、Stem Mode専用の成果物、Stem工程、Stem設定、Stemログを表示しない。
Stem Mode中は、通常補正の実行、通常マスタリングの単独実行、通常モード用書き出しを無効化する。

最近の操作には、Stem Mode用のドメインを追加する。

```swift
enum RecentActivityDomain: String, Sendable {
    case input
    case correction
    case mastering
    case export
    case stem
}
```

### 6.4 Stem Mode固有の進捗

既存の補正進捗・マスタリング進捗とは別に、Stem Mode用の進捗を新設する。

```swift
enum StemWorkflowStep: String, CaseIterable {
    case validateInput
    case separate
    case validateSeparatedStems
    case repairStems
    case remix
    case validateRemix
    case mastering
    case export
}
```

各ステップは開始・完了・失敗を持つ。

現行の `ProcessingProgressEvent` は補正とマスタリングだけを表すため、Stem Mode用に次のどちらかを実装する。

```text
A. ProcessingProgressEvent.Domain に stem を追加する
B. StemWorkflowProgressEvent を別に作る
```

初期版では、Stem Mode全体の完了通知は1回だけ送る。

既存マスタリングを内部で呼ぶ場合でも、Stem Mode完了時とマスタリング完了時の通知が二重に出ないようにする。

---

## 7. モデル実行方式

### 7.1 結論

Stem Mode初期版では、`Demucs v4 htdemucs` を `MLX Swift` で実行する。

| 項目 | 採用内容 |
|---|---|
| モデル | `htdemucs` |
| 実行方式 | MLX Swift |
| 実装サービス | `MLXStemSeparationService` |
| 重み | `htdemucs.safetensors` |
| 設定 | `htdemucs_config.json` |
| 出力ステム | `drums` / `bass` / `other` / `vocals` |
| サンプルレート | 44.1 kHz |
| チャンネル数 | stereo |
| 対象Mac | Apple Silicon専用 |
| Core ML案 | 初期版では不採用 |
| Python版MLX | 検証用のみ。アプリ本体には組み込まない |

採用理由:

- PyTorch版Demucs `htdemucs` は短い検証音源で分離出力まで成功した
- Core ML案は `torch.jit.trace` 後の `coremltools.convert()` で失敗した
- `torch.export.export` でもDemucs内部の `int(self.segment * self.samplerate)` で失敗した
- MLX Swift案は、Metal Toolchain導入と `mlx.metallib` 生成後に、同じ短い検証音源で推論成功した
- Python版 `demucs-mlx` は `--prefetch-tracks 0` で推論成功したが、Pythonランタイムをアプリ本体へ組み込む設計は採用しない

注意:

- MLXはApple Silicon前提であるため、Intel MacはStem Mode初期版の対象外とする
- macOS 26対応MacにはIntel Macも含まれるため、`macOS 26対応` と `Apple Silicon専用` は同義ではない
- `mlx.metallib` は実行に必須である
- `htdemucs.safetensors` は約160 MBであり、初期版ではGitに入れず配布物へ同梱する

### 7.2 モデル情報の確定範囲

実装前に必要なモデル情報は、以下の通り確定済みである。

| 項目 | 結論 |
|---|---|
| モデル名 | `Demucs v4 htdemucs` |
| モデル配布元 | `mlx-community/demucs-mlx` |
| Hugging Face revision | `d4519e24ddc2dd4a11d56a193092433d852c3961` |
| ソースコードのライセンス | MIT License |
| 学習済み重みのライセンス | MIT License |
| 商用利用可否 | MIT License表記同梱を条件に可 |
| 再配布可否 | MIT License表記同梱を条件に可 |
| 実行方式 | MLX Swift |
| `demucs-mlx-swift` | `c81c47178828db2d8bc66e64f80c745c64abdc94` に固定 |
| `mlx-swift` | `0.30.6` / `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d` に固定 |
| 入力サンプルレート | 44.1 kHz |
| 入力チャンネル数 | stereo |
| 出力ステム | `drums` / `bass` / `other` / `vocals` |
| 対応Mac | Apple Silicon専用 |
| Core ML変換可否 | 初期版では不採用。通常の `torch.jit.trace` / `torch.export.export` 経路では失敗 |
| MLX Swiftでの実行可否 | 検証環境で成功 |
| モデル資産のGit管理 | Gitには入れない |
| モデル資産の配布 | 配布物へ同梱する |

実装中に `StemModelContract` と契約テストで固定する項目は、以下である。

| 項目 | 扱い |
|---|---|
| 入力shape | `MLXStemSeparationService` 実装時にコードとテストで固定する |
| 出力shape | `MLXStemSeparationService` 実装時にコードとテストで固定する |
| 出力順 | `drums` / `bass` / `other` / `vocals` への対応をコードとテストで固定する |
| dtype | MLX Swift実装時にコードとテストで固定する |
| 正規化／復元の仕様 | MLX Swift実装時にコードとテストで固定する |
| チャンク長・オーバーラップ長 | 初期実装の契約値として固定し、長尺実測後に必要なら変更理由を記録する |
| 変換前後一致試験 | PyTorch版、Python MLX版、MLX Swift版の差分を実装後に記録する |

上の「実装中に固定する項目」は、実装開始前の未決定事項ではない。
モデルロードと推論コードを作る時に、実モデルの入出力を読み取り、契約として固定する項目である。

### 7.3 Core ML案

Appleのcoremltoolsドキュメントに基づく事実:

- PyTorchモデルは、明示的なONNX保存を必須とせず、Core ML形式へ直接変換できる
- PyTorchモデルの変換では、元の `torch.nn.Module` から `torch.jit.trace` または `torch.export.export` でグラフを取得してから、Core ML ToolsのUnified Conversion APIで変換する
- `torch.jit.trace` 由来のTorchScriptモデルでは、変換時の `inputs` が必須であり、shapeを指定する必要がある
- `torch.export` 由来のExportedProgramでは、`inputs` と `outputs` は変換時に指定せず、ExportedProgramから推定される
- 新しいcoremltoolsでは、macOS 12以降を対象にする場合、`mlprogram` が既定になる
- macOS 13以降を対象にし、float32入力のdtypeを明示しない場合、float16として扱われる条件があるため、音声モデルではdtypeを契約に固定する
- Core MLの配列入力／出力はSwiftの `MLMultiArray` と対応する
- 計算ユニットは変換時またはモデルロード時に指定できる
- モデル読み込み・デバイス最適化・コンパイル済み資産の扱いは、初回と再利用時で異なり得るため、実装後に対象Macで測定する必要がある

これらは「Core ML化が必要な場合の公式の一般情報」であり、`htdemucs` が実際に変換できることを意味しない。

2026-07-02の検証結果:

| 検証 | 結果 |
|---|---|
| `torch.jit.trace` | 成功 |
| `coremltools.convert()` | 失敗 |
| `torch.export.export` | 失敗 |
| Torch 2.12.1 | `coremltools.convert()` で失敗 |
| Torch 2.7.0 | `coremltools.convert()` で失敗 |

確認した失敗理由:

- `torch.jit.trace` 経由では、Demucs内部の音声長に応じたshape計算が `aten::Int` として残る
- `coremltools` はこの `aten::Int` を変換中に処理できず、`TypeError: only 0-dimensional arrays can be converted to Python scalars` で停止した
- 短い入力だけが原因ではなく、`htdemucs` の学習時長さである343,980 framesでも別の `aten::Int` で同じ失敗になった
- `torch.export.export` 経由では、`demucs/htdemucs.py` の `training_length = int(self.segment * self.samplerate)` が `Fraction` 由来でトレースできず失敗した

該当するDemucs側の処理:

```text
demucs/htdemucs.py:433-435
  入力長からSTFT用の長さと右パディング量を計算

demucs/htdemucs.py:534-537
  学習時セグメント長へ満たない入力をパディング

demucs/htdemucs.py:658-659
  パディング前の長さへ切り戻し
```

結論:

```text
Core ML案は、初期版では採用しない。
```

Core ML案を再開する場合は、Demucs本体をCore ML向けに固定長・固定shapeへ書き換える別作業として扱う。

Core ML案の採用条件:

| 項目 | 条件 |
|---|---|
| 変換 | Demucs v4 `htdemucs` をCore MLへ変換できる |
| 入出力 | `StemModelContract` と実モデルの入出力名・shape・dtypeが一致する |
| 出力一致 | PyTorch版とCore ML版の同一入力に対する差分を測定できる |
| 実機推論 | 対象Macでロード、推論、チャンク結合、再ミックスまで完了する |
| 配布 | 変換済みモデルのアプリ同梱と再配布条件が確認済みである |

現時点では、最初の条件である変換が失敗しているため、初期版の採用条件を満たさない。

Core ML案の利点:

- Apple標準のCore MLとしてアプリへ組み込みやすい
- モデル資産をアプリバンドル内で管理しやすい
- 将来、Xcode InstrumentsやCore ML系の計測と接続しやすい

Core ML案のリスク:

- Demucs系モデルの変換が通るとは限らない
- 変換できても、チャンク処理、dtype、メモリ、実行速度で実用にならない可能性がある
- PyTorch版と完全一致するとは限らないため、出力一致試験が必須である

### 7.4 MLX案

MLX Swiftの公式説明に基づく事実:

- MLXはApple Silicon向けの機械学習用配列フレームワークである
- MLX SwiftはMLXをSwiftから扱うAPIである
- Swift.orgのMLX Swift紹介では、MLXは研究用途向けであり、アプリ内の本番モデル配布を目的とした枠組みではないと説明されている

Hugging Faceの `mlx-community/demucs-mlx` に基づく事実:

- 8種類の事前学習済みDemucsモデルを、Apple Silicon推論向けのMLX互換重みへ変換している
- `htdemucs` は速度と品質のバランス、`htdemucs_ft` は品質重視と説明されている
- 4ステム出力に加え、2ステムモードも持つ

MLX案の採用条件:

| 項目 | 条件 |
|---|---|
| 実行 | MLX Swiftから対象モデルをロードし、macOSアプリ内で推論できる |
| 重み | `htdemucs.safetensors`、形式、checksum、ライセンス、再配布条件を確認する |
| 出力一致 | PyTorch版DemucsまたはMLX公式実装との同一入力差分を測定できる |
| Apple Silicon | 対象Macでロード、推論、チャンク結合、再ミックスまで完了する |
| 非Apple Silicon | 初期版では対象外 |

2026-07-02の検証結果:

| 検証 | 結果 |
|---|---|
| `kylehowells/demucs-mlx-swift` のSwiftPM解析 | 成功 |
| `swift build -c release` | 成功 |
| `mlx.metallib` 生成 | Metal Toolchain導入後に成功 |
| MLX Swift CLI推論 | 成功 |
| 明示取得した `htdemucs.safetensors` と `htdemucs_config.json` の指定実行 | 成功 |
| Python `demucs-mlx` | `--prefetch-tracks 0` で成功 |

確認した失敗と対処:

| 失敗 | 原因 | 対処 |
|---|---|---|
| MLX Swift推論失敗 | `default.metallib` が無い | `xcodebuild -downloadComponent MetalToolchain` 後に `scripts/build_mlx_metallib.sh release` を実行 |
| Python `demucs-mlx` 推論失敗 | 既定の音声先読みスレッドで作ったMLX配列を別スレッドで評価した | 検証時は `--prefetch-tracks 0` を指定 |

MLX Swift実装で必須にすること:

- `demucs-mlx-swift` はタグが無いため、検証済みコミット `c81c47178828db2d8bc66e64f80c745c64abdc94` に固定する
- `mlx-swift` は検証済みの `0.30.6`、revision `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d` に固定する
- `mlx.metallib` はリリースビルドで生成し、アプリバンドルへ同梱する
- `htdemucs.safetensors` と `htdemucs_config.json` のchecksumを記録する
- 初期版では初回ダウンロード方式を採用しない
- アプリ内の対象要件にApple Silicon専用を明記する
- `htdemucs` の出力を4ステムとして扱い、`no_vocals` は `drums + bass + other` から派生させる

MLX案の利点:

- Apple Silicon上でDemucs系モデルを動かす実装として現実的である
- Core ML変換に詰まった場合でも、Demucs系の品質を維持できる可能性がある
- Swift APIがあるため、Python常駐を避けられる可能性がある

MLX案のリスク:

- Core MLではないため、既存資料のCore ML同梱前提とは実装・テスト・配布確認が変わる
- MLXはApple Silicon前提のため、Intel Macは初期版Stem Modeの対象外とし、非対応時のUI表示、エラーメッセージ、実行可否を実装時に固定する必要がある
- 研究・実験向けの位置づけがあるため、長期保守、アプリ審査、配布形式を事前に確認する必要がある
- `safetensors` 等の重み資産の同梱方法、読み込み方法、依存パッケージの固定が必要である

依存固定の方針:

| 対象 | 固定値 | 根拠 |
|---|---|---|
| `demucs-mlx-swift` | `c81c47178828db2d8bc66e64f80c745c64abdc94` | 2026-07-02のMLX Swift検証で使用したコミット |
| `mlx-swift` | `0.30.6` / `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d` | `demucs-mlx-swift` の `Package.resolved` で解決され、検証で推論成功 |

`demucs-mlx-swift` は2026-07-02時点のGitHub API確認でタグが無かったため、タグではなくコミットで固定する。
`mlx-swift` の最新releaseは2026-07-02時点で `0.31.6` だが、初期版では最新追従ではなく、推論成功済みの `0.30.6` を採用する。

### 7.5 実行方式の選定基準

| 判定項目 | Core ML案 | MLX案 |
|---|---|---|
| Apple標準フレームワークとの親和性 | 高い | 中 |
| Demucs系モデルをそのまま動かす現実性 | 低い。通常変換は失敗 | 高い。短い検証音源で実行成功 |
| Apple Silicon最適化 | Core ML変換結果次第 | 主目的 |
| Intel Mac対応 | Core MLなら可能性あり | 基本対象外 |
| アプリ同梱の分かりやすさ | 高い | 依存と資産管理の確認が必要 |
| 採用前の必須検証 | 固定shape化を含む再設計 | MLX Swift統合、出力一致、実機速度 |

初期判断:

```text
採用: MLX案
不採用: Core ML案
```

Core ML案は、将来の再検証候補として資料に残す。ただし初期版の実装対象には含めない。

### 7.6 モデル資産の配置

現行 `Package.swift` はリソースを `.process(...)` で登録している。

Swift Package Managerの公式ドキュメントは、ディレクトリへの `process` を再帰的に適用すると説明する。また、構造を保持する必要がある資産には `copy` を使えるとしている。

モデル資産は、Swift Package Managerの `.copy("Resources/StemModels")` で同梱する。

```text
Resources/StemModels/
  <model asset>
```

```swift
.copy("Resources/StemModels")
```

2026-07-02のSPM同梱検証では、`/tmp/veloura-spm-resource-probe` に `htdemucs.safetensors`、`htdemucs_config.json`、`mlx.metallib` を配置し、`.copy` と `.process` の両方を同時に検証した。
また、`/tmp/veloura-spm-stemmodels-probe` で実際に採用する `.copy("Resources/StemModels")` も検証した。

検証結果:

| 形式 | 結果 | 判断 |
|---|---|---|
| `.copy("CopyResources")` | `Bundle.module` から元のフォルダ構造と同じパスで3ファイルを読み込めた | 採用 |
| `.process("ProcessResources")` | 3ファイルはバンドル直下へ配置され、元のフォルダ構造のパスでは読めなかった | 不採用 |

確認した `.process` 後の配置:

```text
ResourceProbe_Probe.bundle/htdemucs.safetensors
ResourceProbe_Probe.bundle/htdemucs_config.json
ResourceProbe_Probe.bundle/mlx.metallib
```

モデルロードでは `StemModels/htdemucs/` と `StemModels/MLX/` の構造が意味を持つため、`.process` ではなく `.copy` を採用する。

`.copy("Resources/StemModels")` 採用時に確認したバンドル内配置:

```text
StemModels/htdemucs/htdemucs.safetensors
StemModels/htdemucs/htdemucs_config.json
StemModels/MLX/mlx.metallib
```

MLX案を採用するため、`Package.swift` にMLX Swift依存を追加する。

依存バージョンは、検証済みの `mlx-swift 0.30.6` に固定する。
対応macOS、Apple Silicon専用条件、ビルド成果物サイズ、署名・配布への影響は、実装後のビルド成果物で確認する。

初期版で必要な資産:

```text
Resources/StemModels/htdemucs/
  htdemucs.safetensors
  htdemucs_config.json

Resources/StemModels/MLX/
  mlx.metallib
```

`mlx.metallib` はMLX推論に必要であり、存在しない場合は `Failed to load the default metallib` で推論が停止する。

モデル資産のGit管理方針:

| 資産 | サイズ | Git管理 | 配布物 |
|---|---:|---|---|
| `htdemucs.safetensors` | 168,005,865 bytes | 入れない | 同梱する |
| `htdemucs_config.json` | 1,892 bytes | 入れない | 同梱する |
| `mlx.metallib` | 106,957,102 bytes | 入れない | 同梱する |

モデル資産は、サイズ差にかかわらずリポジトリには入れない。
ただし、アプリ実行時には必要なため、リリースビルドまたは配布用パッケージには同梱する。

Gitで管理するもの:

```text
モデル資産の取得元
Hugging Face revision
checksum
配置ルール
MIT License表記
```

Gitで管理しないもの:

```text
htdemucs.safetensors
htdemucs_config.json
mlx.metallib
```

#### モデル資産のビルド前供給手順

モデル資産はGitに入れないため、`Package.swift` に `.copy("Resources/StemModels")` を追加する前に、ビルド環境へ次の配置を作る。

```text
Sources/VelouraLucent/Resources/StemModels/htdemucs/
  htdemucs.safetensors
  htdemucs_config.json

Sources/VelouraLucent/Resources/StemModels/MLX/
  mlx.metallib
```

実装時に用意するもの:

```text
モデル資産取得手順
配置手順
checksum検証手順
欠落時にビルドまたはパッケージ作成を止める明確なエラー
MIT License表記の同梱手順
```

2026-07-13のSPM欠落検証では、`.copy("Resources/StemModels")` を指定した状態で `Resources/StemModels` が存在しない場合、`swift build` は次の理由で失敗した。

```text
Invalid Resource 'Resources/StemModels': File not found.
missing inputs: .../Sources/Probe/Resources/StemModels
```

したがって、Gitにはモデル本体を入れない方針を維持しつつ、リリースビルドまたは配布用パッケージ作成の前に資産配置とchecksum検証を必ず行う。

### 7.7 モデル契約をコードへ固定する

モデル導入時に、次をコード化する。

```swift
struct StemModelContract: Sendable, Codable {
    let identifier: String
    let version: String
    let inputName: String
    let outputNames: [StemRole: String]
    let sampleRate: Double
    let channelCount: Int
    let inputShape: [Int]
    let outputShapes: [StemRole: [Int]]
    let scalarType: StemModelScalarType
    let normalization: StemNormalizationContract
    let runtime: StemModelRuntime
}

enum StemModelScalarType: String, Sendable, Codable {
    case float32
    case float16
}

enum StemModelRuntime: String, Sendable, Codable {
    case coreML
    case mlx
}

struct StemNormalizationContract: Sendable, Codable {
    let inputScale: Double
    let inputOffset: Double
    let outputScale: Double
    let outputOffset: Double
}
```

モデルの仕様は、UIやワークフローへ散在させない。

---

## 8. テスト仕様

### 8.1 テストの分類

| 層 | 対象 |
|---|---|
| Unit | StemModels、StemMixService、StemValidationService |
| Contract | MLXモデルの入出力契約 |
| Integration | 分離→補正→再ミックス→マスタリング |
| Regression | Standard Modeが変化しないこと |
| Manual Evaluation | 権利のある実音源を使う聴感比較 |

### 8.2 必須Unitテスト

| テスト名 | 確認内容 |
|---|---|
| `stemRoleIsUnique` | 4ステムの役割が重複しない |
| `mixPreservesFrameCount` | 再ミックス後のフレーム数が入力と一致 |
| `mixRejectsUnevenChannelFrameCounts` | 同じ音声内でチャンネル長が揃っていない場合に失敗 |
| `mixPreservesChannelCount` | チャンネル数が一致 |
| `mixRejectsMismatchedSignals` | 長さ・形式不一致を検出 |
| `mixRejectsNonFiniteSamples` | NaN / ±Infinityを検出 |
| `rawStemSumProducesResidualMeasurement` | 残差測定が実行できる |
| `validationReportsFailedChecks` | 不合格理由を列挙できる |
| `noVocalsIsDerivedFromDrumsBassOther` | `no_vocals` が `drums + bass + other` と一致 |
| `stemPoliciesAreRecordedPerRole` | 各ステムに適用した補正方針を記録できる |

### 8.3 必須モデル契約テスト

モデル採用後、公式モデル仕様から以下を固定する。

| テスト | 確認内容 |
|---|---|
| `modelLoadsFromBundle` | アプリ資産からロードできる |
| `modelInputNameMatchesContract` | 入力名が契約と一致 |
| `modelInputShapeMatchesContract` | 入力shapeが一致 |
| `modelOutputNamesMatchContract` | 出力名が一致 |
| `modelOutputShapesMatchContract` | 出力shapeが一致 |
| `modelOutputContainsFiniteSamples` | 出力が有限値 |
| `modelOutputMapsToFourStemRoles` | drums / bass / other / vocalsの対応が固定されている |
| `modelRuntimeMatchesContract` | MLX実行方式が契約と一致 |
| `modelOutputMatchesReferenceRuntime` | 基準実装との差分を記録できる |

MLX案を採用する場合は、`MLXStemSeparationContractTests` としてMLX Swiftからのロード、重み資産のchecksum、Apple Silicon上の推論完了を確認する。

Core ML案は初期版で不採用のため、`CoreMLStemSeparationContractTests` は追加しない。

### 8.4 必須統合テスト

| テスト | 確認内容 |
|---|---|
| `stemWorkflowProducesAllArtifacts` | vocals、drums、bass、other、no_vocals、再ミックス、最終版が存在 |
| `stemWorkflowRemixMatchesSourceDuration` | 再ミックス長が原音と一致 |
| `stemWorkflowPassesValidationBeforeMastering` | 再ミックス検証の通過後のみマスタリングへ進む |
| `stemWorkflowUsesOriginalReferenceForMastering` | 原音が `originalReferenceFile` として渡る |
| `stemWorkflowDoesNotRunStandardCorrectionBeforeSeparation` | 分離前に通常補正が走らない |
| `stemWorkflowRecordsPerStemCorrectionPolicy` | 4ステムそれぞれの補正方針が記録される |
| `stemWorkflowFailsExplicitlyOnSeparationValidationFailure` | 失敗時に黙って通常処理へ切り替えない |
| `stemWorkflowRecordsStemActivityAndProgress` | Stem Modeとして最近の操作と進捗に記録される |
| `stemWorkflowSendsSingleCompletionNotification` | 内部マスタリング完了とStem Mode完了で通知が二重にならない |

### 8.5 Standard Mode回帰テスト

Stem Mode追加後も、既存の通常補正・マスタリングテストをすべて維持する。

特に維持対象:

- 出力作成
- ピーク安全性
- ダイナミクス保持
- 高域保持
- ノイズ戻り制限
- 最終音量復帰
- 原音参照による高域回復
- 通常モードのツールバー、左サイドバー、中央ワークスペース、右インスペクタ、下部フッターの表示
- 通常モードの `isProcessing`、`beginProcessing(...)`、`finishSuccess(...)`、補正ログ、マスタリングログがStem Modeの状態で更新されないこと
- Stem Mode選択前の通常モードでは、Stem成果物、Stem工程、Stem設定、Stemログが表示されないこと

---

## 9. 実装順序

### フェーズ0: モデル資産・依存・契約準備

1. Git外で管理するモデル資産の取得手順と配置手順を用意
2. `htdemucs.safetensors`、`htdemucs_config.json`、`mlx.metallib` のchecksum検証手順を用意
3. モデル資産が欠落している場合に、ビルドまたは配布物作成を止める確認を用意
4. MIT License表記の同梱手順を用意
5. `Package.swift` に `.copy("Resources/StemModels")` とMLX Swift依存を追加
6. `StemModelContract` の土台と、モデル識別子、revision、checksum、バンドル内パスを確認する契約テストを追加

完了条件:

```text
Gitにモデル本体を入れないまま、
ビルド前に必要資産を配置し、
checksumとライセンス表記を追跡できる。
```

### フェーズ1: データ構造と検証器

1. `StemRole`、`StemAudioArtifact`、`StemSeparationResult`、`StemValidationResult` を追加
2. `StemValidationService` を追加
3. `StemMixService` を追加
4. 実際の分離器を使わないテスト用分離器を追加
5. 合算残差、長さ、チャンネル数、有限値をテスト

完了条件:

```text
テスト用の drums / bass / other / vocals から再ミックスを作り、
検証結果を構造化して返せる
```

### フェーズ2: Stem Mode専用ワークフローUI

1. 通常モードの既存UIを維持したまま、モード切り替えの外枠を追加
2. Stem Mode専用Root Viewを追加
3. Stem Mode専用ツールバーを追加
4. Stem Mode専用左サイドバーを追加
5. Stem Mode専用中央ワークスペースを追加
6. Stem Mode専用右インスペクタを追加
7. Stem Mode専用下部フッターを追加
8. Stem Mode専用進捗、ログ、最近の操作、完了通知を接続
9. 分離、ステム別補正、再ミックス、マスタリング、最終版生成の進捗をStem Mode専用UIへ接続
10. 最終版を主導線として表示・書き出しできるようにする
11. ステム個別、No vocals、再ミックスの表示・書き出しは副導線として追加する

完了条件:

```text
通常モードの見た目、操作、進捗、右インスペクタ、下部フッター、書き出し導線を変えずに、
Stem Mode選択時だけ専用画面一式が表示される。

Stem Mode専用画面で、
入力検証 → ステム分離 → 分離結果検証 → ステム別補正 → 再ミックス → 再ミックス検証 → マスタリング → 最終版生成
の画面遷移、進捗表示、ログ記録が成立する。
```

### フェーズ3: Stem別補正

1. `StemRepairService` を追加
2. `StemCorrectionPolicy` を追加
3. 4ステムの役割別補正方針を定義
4. 各ステムに適用した工程と適用しなかった工程をログへ記録
5. 修復前後のノイズ・帯域・ピークを記録

完了条件:

```text
4ステムを役割別に補正し、
再ミックス後に既存MasteringServiceへ渡せる
```

### フェーズ4: MLX Swift分離器

1. `MLXStemSeparationService` を実装
2. `Bundle.module` から `StemModels/htdemucs/` と `StemModels/MLX/` の資産を読み込む
3. 実モデルの入力shape、出力shape、dtype、チャンネル順、正規化、チャンク長を `StemModelContract` と契約テストへ固定
4. `htdemucs` から `drums` / `bass` / `other` / `vocals` の4ステムを取得
5. PyTorch版、Python MLX版、MLX Swift版の差分測定を記録する
6. macOS実機でロード・推論・再ミックスを検証

完了条件:

```text
アプリ内のMLX Swift実装で htdemucs を読み込み、
4ステムを出力し、
StemModelContract と契約テストで入出力契約を追跡できる。
```

### フェーズ5: 長尺・品質検証

4ステム化は初期版で扱う。フェーズ5では、実音源と長尺音源で品質と性能を確認する。

追加で必要になる項目:

```text
長尺音源での処理時間
長尺音源での最大メモリ
複数ジャンルでの残差、ピーク、相関
実音源での聴感確認
エンコード後確認
モデル資産同梱時のアプリサイズ
```

---

## 10. 受け入れ条件

Stem Mode初期版の完成条件を以下に固定する。

### 必須

- [ ] 通常モードの既存処理が変更されない
- [ ] Stem Mode追加後も、通常モードの既存画面、ボタン、進捗、右インスペクタ、下部フッター、書き出し導線の見た目と動作が変わらない
- [ ] Stem Modeは原音2mixを直接分離器へ渡す
- [ ] 初期版は `drums` / `bass` / `other` / `vocals` の4ステムを扱う
- [ ] `no_vocals` は `drums + bass + other` から生成する
- [ ] 4ステムそれぞれの補正方針が成果物とログで確認できる
- [ ] 再ミックス前に、長さ・形式・有限値・残差を検証する
- [ ] 再ミックス後に、長さ・形式・有限値・ピーク・相関を検証する
- [ ] 検証失敗時に、最終版を出力しない
- [ ] 検証失敗時に、黙って通常モードへ切り替えない
- [ ] 再ミックス後の2mixを既存 `MasteringService` へ渡す
- [ ] 分離前の原音を `originalReferenceFile` として渡す
- [ ] vocals、drums、bass、other、no_vocals、再ミックス、最終版を書き出せる
- [ ] Stem Modeとして進捗、最近の操作、完了通知が確認できる
- [ ] Stem Modeの状態、進捗、ログ、通知、書き出し導線が通常モードの `isProcessing`、`beginProcessing(...)`、`finishSuccess(...)`、通常補正ログへ混ざらない
- [ ] Stem Mode選択時だけ、Stem Mode専用のツールバー、左サイドバー、中央ワークスペース、右インスペクタ、下部フッターが表示される
- [ ] 通常モード中はStem成果物、Stem工程、Stem設定、Stemログが表示されない
- [ ] Stem Mode中は通常補正と通常マスタリングの単独実行ができない
- [ ] Stem Modeの主導線は、ステム分離ではなく、再ミックス後のマスタリングと最終版生成まで完了する
- [ ] Stem Mode内部のマスタリングで完了通知が二重に出ない
- [ ] Standard Modeの既存テストを維持する
- [ ] Stem ModeのUnit／Contract／Integrationテストを追加する
- [ ] MLX案の採用理由とCore ML案の不採用理由を実測結果つきで記録する
- [ ] モデルのライセンスと変換手順または重み取得手順をリポジトリに記録する
- [ ] モデル資産はGitに入れず、ビルド前または配布物作成前に `Sources/VelouraLucent/Resources/StemModels/` へ配置できる
- [ ] `htdemucs.safetensors`、`htdemucs_config.json`、`mlx.metallib` のchecksumを検証できる
- [ ] モデル資産が欠落している場合に、黙って通常モードへ切り替えず、ビルド、配布物作成、またはStem Mode開始時に明確なエラーで止まる
- [ ] `Package.swift` の `.copy("Resources/StemModels")` で、バンドル内の `StemModels/htdemucs/` と `StemModels/MLX/` の構造を保持できる
- [ ] `StemModelContract` でモデル識別子、revision、checksum、入出力shape、dtype、サンプルレート、チャンネル数を追跡できる

### 初期版では行わない

- [ ] 自動ミックスバランス変更
- [ ] 自動パン変更
- [ ] 自動ステレオ幅変更
- [ ] ステム別マスタリング
- [ ] 分離品質を根拠なく点数化
- [ ] 根拠のない閾値設定
- [ ] ライセンス未確認モデルの同梱
- [ ] Core ML実装
- [ ] Pythonランタイムのアプリ同梱

---

## 11. モデル選定記録

### 11.1 採用記録

| 項目 | 内容 |
|---|---|
| 採用モデル | Demucs v4 `htdemucs` |
| 実行方式 | MLX Swift |
| モデル配布元 | `mlx-community/demucs-mlx` |
| 重み | `htdemucs.safetensors` |
| 設定 | `htdemucs_config.json` |
| 出力 | `drums` / `bass` / `other` / `vocals` |
| サンプルレート | 44.1 kHz |
| チャンネル数 | stereo |
| 初期版対象Mac | Apple Silicon |
| Core ML案 | 初期版不採用 |
| Python MLX | 検証用のみ |

### 11.2 2026-07-02 検証結果

検証環境:

| 項目 | 内容 |
|---|---|
| Mac | Apple M3 Pro |
| OS | macOS 26.5.1 |
| メモリ | 18 GB |
| Swift | Apple Swift 6.3.3 |
| Xcode | Xcode 26.6 |

PyTorch版Demucs:

| 項目 | 結果 |
|---|---|
| パッケージ | `demucs==4.0.1` |
| モデル | `htdemucs` |
| 実行 | 成功 |
| 出力 | `vocals.wav` / `no_vocals.wav` |
| 実行時間 | 8.03秒 |
| 最大RSS | 約1.82 GB |
| 出力形式 | 44.1 kHz / stereo |
| 再合成相関 | 0.999756 |
| 残差RMS | -48.26 dBFS |

Core ML案:

| 項目 | 結果 |
|---|---|
| `torch.jit.trace` | 成功 |
| `coremltools.convert()` | 失敗 |
| Torch 2.12.1 | 失敗 |
| Torch 2.7.0 | 失敗 |
| `torch.export.export` | 失敗 |
| 判断 | 初期版不採用 |

MLX Swift案:

| 項目 | 結果 |
|---|---|
| SwiftPM解析 | 成功 |
| `swift build -c release` | 成功 |
| `Metal Toolchain` | 追加導入で成功 |
| `mlx.metallib` 生成 | 成功 |
| `htdemucs.safetensors` 明示指定 | 成功 |
| 推論 | 成功 |
| 出力 | `vocals.wav` / `no_vocals.wav` |
| 必須資産 | `mlx.metallib`、`htdemucs.safetensors`、`htdemucs_config.json` |
| `demucs-mlx-swift` commit | `c81c47178828db2d8bc66e64f80c745c64abdc94` |
| `mlx-swift` | `0.30.6` / `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d` |

Python MLX案:

| 項目 | 結果 |
|---|---|
| パッケージ | `demucs-mlx==1.4.4` |
| 既定実行 | 失敗 |
| 失敗原因 | `--prefetch-tracks 2` によるMLX GPUストリーム不一致 |
| `--prefetch-tracks 0` | 成功 |
| 出力 | `drums` / `bass` / `other` / `vocals` |
| 判断 | アプリ本体では不採用。検証用基準としてのみ使用 |

実装中・実装後に確認する項目:

- 実音源、長尺音源での速度・メモリ・聴感確認
- MLX Swift実装をアプリ本体へ組み込んだ状態での計測

### 11.3 2026-07-02 再配布条件・checksum・SPM同梱検証

#### 再配布条件

確認した一次情報:

| 対象 | 確認元 | 確認結果 |
|---|---|---|
| `mlx-community/demucs-mlx` | Hugging Face model card / API | licenseは `mit` |
| `htdemucs.safetensors` / `htdemucs_config.json` | Hugging Face model card | repo rootの2ファイルとして配布。変換元はPyTorch checkpointで、fine-tuningおよび量子化なし |
| 上流Demucs | `facebookresearch/demucs` の `LICENSE` | MIT License |
| MLX Swift実装 | `kylehowells/demucs-mlx-swift` の `LICENSE` | MIT License |
| Python MLX検証実装 | `ssmall256/demucs-mlx` の `LICENSE` | MIT License |
| MLX Swift依存 | `ml-explore/mlx-swift` の `LICENSE` | MIT License |

事実として確認できた範囲:

- `mlx-community/demucs-mlx` のmodel cardは、licenseをMITと表示している
- 同model cardは、元モデルを `adefossez/demucs`、ライセンスを「original Demucsと同じMIT」と説明している
- 同model cardは、PyTorch checkpointsから `safetensors` とJSON configへ直接変換し、fine-tuningや量子化を行っていないと説明している
- MIT Licenseは、著作権表示と許諾表示を含めることを条件に、利用、複製、改変、配布、再許諾、販売を許可する

実装時の配布条件:

```text
アプリにモデル資産とMLX関連コードを同梱する場合は、
対象となるMIT Licenseの著作権表示と許諾表示をアプリ内または同梱文書に含める。
```

この確認は一次情報に基づく技術資料上の整理であり、法務判断そのものではない。

#### checksum

2026-07-02に `/tmp/veloura-stem-verify` の実ファイルからSHA-256を固定した。

| ファイル | サイズ | SHA-256 |
|---|---:|---|
| `htdemucs.safetensors` | 168,005,865 bytes | `339d267a7a6983a11eedbdc00413c602a65e9b9103f695fb5c2b2a481cd9d297` |
| `htdemucs_config.json` | 1,892 bytes | `9258499513944fc062fbca0f11be425a446ec5702869a87e225323d7a57d2a01` |
| `mlx.metallib` | 106,957,102 bytes | `82be53f327e9a39cb19a18272187187b7636f31989c44ad7ff474f7fe8171974` |

モデル配布元のrevision:

| 項目 | 値 |
|---|---|
| Hugging Face repo | `mlx-community/demucs-mlx` |
| revision SHA | `d4519e24ddc2dd4a11d56a193092433d852c3961` |
| lastModified | `2026-03-16T21:17:58.000Z` |
| license | `mit` |

#### SPM同梱形式

検証コマンド:

```text
cd /tmp/veloura-spm-resource-probe
swift run -c release Probe

cd /tmp/veloura-spm-stemmodels-probe
swift run -c release Probe
```

結果:

| 資産 | `.copy` | `.process` |
|---|---|---|
| `htdemucs.safetensors` | 元の階層で読込成功 | 元の階層では読込失敗 |
| `htdemucs_config.json` | 元の階層で読込成功 | 元の階層では読込失敗 |
| `mlx.metallib` | 元の階層で読込成功 | 元の階層では読込失敗 |

採用:

```swift
.copy("Resources/StemModels")
```

採用時の読込パス:

```text
Bundle.module.resourceURL / StemModels/htdemucs/htdemucs.safetensors
Bundle.module.resourceURL / StemModels/htdemucs/htdemucs_config.json
Bundle.module.resourceURL / StemModels/MLX/mlx.metallib
```

理由:

- Swift Package Manager公式ドキュメントは、特定のフォルダ構造を保持する必要がある資産には `copy` を使うと説明している
- 実測でも `.copy` は構造を保持し、`.process` はファイルをバンドル直下へ配置した
- モデルロードでは `htdemucs` と `MLX` のフォルダ構造を固定した方が、読み込み契約とchecksum検証を単純に保てる

### 11.4 2026-07-02 実装前決定事項

実装前に決める必要がある項目は、次で固定する。

| 項目 | 決定 |
|---|---|
| `demucs-mlx-swift` | `c81c47178828db2d8bc66e64f80c745c64abdc94` に固定 |
| `mlx-swift` | `0.30.6` / `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d` に固定 |
| モデル重み | Gitには入れない |
| `mlx.metallib` | Gitには入れない |
| `htdemucs_config.json` | Gitには入れない |
| 配布物 | `htdemucs.safetensors`、`htdemucs_config.json`、`mlx.metallib` を同梱する |
| モデル資産のビルド前供給 | Git外のモデル資産を `Sources/VelouraLucent/Resources/StemModels/` へ配置し、checksum検証後にビルドまたは配布物作成へ進む |
| 検証 | 配布物作成時にchecksum一致を確認する |
| ライセンス | MIT Licenseの著作権表示と許諾表示を同梱する |

この決定により、実装開始前に決めるべき項目は残っていない。

実装中または実装後に確認する項目は、13.2に残す。

---

## 12. 根拠一覧

### リポジトリの実コード

以下は2026-07-13（JST）の現状アプリ再照合時に取得したファイル内容の識別子である。リンクは `master` ブランチを指すため、将来の変更後に参照する場合は、各ファイルのblob SHAも併せて確認する。

| ファイル | 確認したblob SHA | 主な根拠 |
|---|---|---|
| `Package.swift` | `70fee391d3e452f7ea5c390e8a6ec8058066be2b` | macOS 26、リソース登録 |
| `Services/AudioFileService.swift` | `9a2f352bc77654730a94fcf9a0fbb99d472fd775` | Float32読込、48 kHz変換、保存 |
| `Services/AudioProcessingService.swift` | `d22434d254fb3772549907834fe5db1e4a84516c` | 補正サービスのURL入出力 |
| `Services/NativeAudioProcessor.swift` | `451a100c2104d77430b560ef6c173ed77fb784f7` | 補正工程 |
| `Services/MasteringService.swift` | `f986ef33fb4bd933723c0b7941b6b1a887328b46` | 原音参照、マスタリング経路 |
| `Services/MasteringProcessor.swift` | `ee036cbaf81aa736185b84e5b73dcc9f924ada8f` | マスタリング工程 |
| `Models/ProcessingJob.swift` | `36457ca2e47677ae6baeb5fec12416dc638ae9a2` | 現行状態管理 |
| `Views/ContentView.swift` | `8353c9b13b6e571802d472825e305324b644a727` | 現行UI操作 |
| `Tests/VelouraLucentTests/MasteringPipelineTests.swift` | `3ae1bccc0f8083c0a35d85f7f05f748722f2566c` | 現行マスタリングテスト |

- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Package.swift
- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Services/AudioFileService.swift
- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Services/AudioProcessingService.swift
- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Services/NativeAudioProcessor.swift
- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Services/MasteringService.swift
- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Services/MasteringProcessor.swift
- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Models/ProcessingJob.swift
- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Sources/VelouraLucent/Views/ContentView.swift
- https://github.com/hajimeno-ipoo/Veloura-Lucent/blob/master/Tests/VelouraLucentTests/MasteringPipelineTests.swift

### 公式ドキュメント

- Apple Core ML:
  - https://developer.apple.com/documentation/coreml
  - https://developer.apple.com/documentation/coreml/integrating-a-core-ml-model-into-your-app
- Apple coremltools:
  - PyTorch conversion:
    https://apple.github.io/coremltools/docs-guides/source/convert-pytorch.html
  - PyTorch conversion workflow:
    https://apple.github.io/coremltools/docs-guides/source/convert-pytorch-workflow.html
  - Load and convert workflow:
    https://apple.github.io/coremltools/docs-guides/source/load-and-convert-model.html
  - Model prediction / arrays / compute units:
    https://apple.github.io/coremltools/docs-guides/source/model-prediction.html
- Apple MLX / MLX Swift:
  - MLX Swift:
    https://github.com/ml-explore/mlx-swift
  - MLX:
    https://github.com/ml-explore/mlx
  - Swift.org MLX Swift overview:
    https://swift.org/blog/mlx-swift/
- Demucs MLX配布元:
  - mlx-community/demucs-mlx:
    https://huggingface.co/mlx-community/demucs-mlx
  - mlx-community/demucs-mlx-fp16:
    https://huggingface.co/mlx-community/demucs-mlx-fp16
- ライセンス確認:
  - Demucs:
    https://github.com/facebookresearch/demucs/blob/main/LICENSE
  - demucs-mlx-swift:
    https://github.com/kylehowells/demucs-mlx-swift/blob/master/LICENSE
  - demucs-mlx:
    https://github.com/ssmall256/demucs-mlx/blob/main/LICENSE
  - MLX Swift:
    https://github.com/ml-explore/mlx-swift/blob/main/LICENSE
- Swift Package Manager:
  - PackageDescription / Resource:
    https://docs.swift.org/package-manager/PackageDescription/PackageDescription.html#Resource

### ローカル検証

| 検証 | 場所 | 主な確認 |
|---|---|---|
| Stem Modeモデル検証 | `/tmp/veloura-stem-verify` | PyTorch版、Core ML案、MLX Swift案、Python MLX案 |
| SPM同梱形式比較 | `/tmp/veloura-spm-resource-probe` | `.copy` と `.process` のバンドル後配置 |
| SPM採用形式検証 | `/tmp/veloura-spm-stemmodels-probe` | `.copy("Resources/StemModels")` での読込パス |

---

## 13. 残確認事項

以下は、2026-07-02の検証結果を反映した残確認事項である。
実装開始前の未決定事項ではなく、実装中または実装後に実測で確認する項目を分けて記録する。

### 13.1 実装前に確定済み

| 項目 | 結論 |
|---|---|
| 採用する分離モデル | `Demucs v4 htdemucs` |
| 実行方式 | MLX Swift |
| Core ML案 | 初期版では不採用 |
| Core ML変換可否 | 通常の `torch.jit.trace` / `torch.export.export` 経路では失敗 |
| MLX Swiftでの実行可否 | 検証環境で成功 |
| Python MLXでの実行可否 | `--prefetch-tracks 0` で成功 |
| モデル出力 | 4ステム |
| サンプルレート | 44.1 kHz |
| チャンネル数 | stereo |
| Intel Mac | 初期版Stem Modeでは対象外 |
| 4ステム要件 | 初期版から対象 |
| モデル重みの再配布条件 | `mlx-community/demucs-mlx` のlicenseはMIT。配布時はMIT Licenseの著作権表示と許諾表示を同梱する |
| checksum | `htdemucs.safetensors`、`htdemucs_config.json`、`mlx.metallib` のSHA-256を固定済み |
| SPM同梱形式 | `.copy("Resources/StemModels")` を採用 |
| `demucs-mlx-swift` | `c81c47178828db2d8bc66e64f80c745c64abdc94` に固定 |
| `mlx-swift` | `0.30.6` / `6ba4827fb82c97d012eec9ab4b2de21f85c3b33d` に固定 |
| モデル資産のGit管理 | `htdemucs.safetensors`、`htdemucs_config.json`、`mlx.metallib` はGitに入れない |
| モデル資産の配布 | `htdemucs.safetensors`、`htdemucs_config.json`、`mlx.metallib` を配布物へ同梱する |
| モデル資産のビルド前供給 | `.copy("Resources/StemModels")` を使うため、ビルド前にGit外のモデル資産を `Sources/VelouraLucent/Resources/StemModels/` へ配置し、checksumを検証する |

### 13.2 実装中・実装後に確認する項目

| 項目 | 次の確認 |
|---|---|
| 長尺メモリ | 3分以上の実音源で最大メモリを測定する |
| 長尺処理時間 | 3分以上の実音源で処理時間を測定する |
| 合算残差の合格基準 | 権利のある複数音源で測定して決める |
| 相関の合格基準 | 権利のある複数音源で測定して決める |
| 帯域差分の合格基準 | 権利のある複数音源で測定して決める |
| 聴感基準 | 原音、分離後、補正後、再ミックス後、最終版のA/Bで確認する |

この文書では、実装中・実装後に実測で決める項目を、推測で埋めない。
