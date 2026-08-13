# 完全6Stem化 ログ・通知・Help・文書の整合確認

## 対象

BS-RoFormer-SWの6Stem化に伴う、処理ログ、補正・マスタリング完了通知、モデル管理Help、現在仕様のREADME、モデル資産README、開発者向け説明を対象とする。HTDemucsの4Stem表示、通知設定と通知回数、通常モード、過去のMUSDB 4Stem比較は維持する。

## 変更前と確認済みの問題

| 対象 | 変更前 | 確認済みの問題 |
| --- | --- | --- |
| 処理ログ | 分離・保存・補正の個別ログはあった | 1回の処理で使うモデル、Stem数、全役割を開始時にまとめて確認できなかった |
| 補正完了通知 | `補正済み4Stem`の固定本文 | BS-RoFormer-SWの6Stem処理でも4Stemと通知し、次工程もマスタリングとしていた |
| マスタリング完了通知 | モデル名とStem数を含まない固定本文 | どのrun契約の最終版か本文から確認できなかった |
| モデル管理Help | BS-RoFormer-SWを`6Stem → 既存4Stem`と表示 | 現在の独立6Stem出力と一致しなかった |
| 現在仕様の文書 | Stem Modeを4Stem、補正とマスタリングの二段階として説明する箇所があった | Guitar／Piano、独立した再ミックス工程、動的な個別書き出しを確認できなかった |
| 過去のSwiftランタイム検証記録 | 当時の6→4Stem互換実装を現在仕様と区別する注記がなかった | 歴史的な実測結果と現在の6Stem仕様を混同できた |

## 変更後

### 処理ログ

補正処理の開始時に、`StemModelRunContract`からモデル名、4／6 Stem数、有効役割の完全な一覧を1行で記録する。HTDemucsは`HTDemucs / 4Stem / ドラム、ベース、その他、ボーカル`、BS-RoFormer-SWは`BS-RoFormer-SW / 6Stem / ベース、ドラム、その他、ボーカル、ギター、ピアノ`となる。既存のStem別保存、解析、補正、raw復帰、純粋加算、再ミックス、マスタリングの工程ログは維持する。

常駐telemetry、外部送信、永続ログ、利用者追跡は追加していない。既存の画面内処理ログだけをrun契約に揃えた。

### 通知

通知の発行段階は従来どおり補正完了とマスタリング完了の2種類とし、回数も各成功時1回のまま維持する。通知本文だけへ、その成功結果が保持する`StemModelRunContract`を渡す。

- 補正完了: モデル名、補正済み4／6 Stem数、次工程が別操作の再ミックスであることを表示する。
- マスタリング完了: モデル名、4／6 Stem数、Stem Mode最終版であることを表示する。

通知を無効にした場合は登録しない。OS通知登録が失敗した場合に既存`Logger`へエラーを残す動作も維持する。

### Help

選択中モデルの検証済みrun契約がある場合はその有効役割、ない場合は同じ本番モデルprofileの出力順から表示を組み立てる。

- HTDemucs: `4Stem（ドラム、ベース、その他、ボーカル）`
- BS-RoFormer-SW: `6Stem（ベース、ドラム、その他、ボーカル、ギター、ピアノ）`

`6Stem → 既存4Stem`という旧表示は削除した。モデルRevision、方式、固定設定の表示は変更していない。

### 文書

- ルート`README.md`は、HTDemucs 4Stem／BS-RoFormer-SW 6Stem、Stem Modeの補正・再ミックス・マスタリング3段階、Guitar／Pianoを含む役割別補正、純粋加算、全有効Stem再ミックス、検証済み再ミックスからのマスタリング、工程別キャンセル、動的な個別書き出しへ更新した。
- モデル資産READMEは、HTDemucsとBS-RoFormer-SWの独立出力順、BSがGuitar／PianoをOtherへ統合しないこと、別モデル契約へfallbackしないことを明記した。
- `FOR[hazimeno_ipoo].md`は、Help、ログ、通知がrun契約のモデル名、Stem数、役割へ一致する現在構造を追記した。
- `Docs/BSRoformerSwiftRuntimeValidation_2026-07-30.md`は過去の数値と本文を置換せず、2026-07-30時点の6→4Stem互換記録であることと、現在仕様の参照先だけを冒頭へ追記した。
- `Docs/StemSeparationModelBenchmark_2026-07-30.md`はMUSDB 4Stem比較の歴史的条件なので変更していない。

## 検証

- `StemCompletionNotificationServiceTests`: 通知無効時は0件、HT4／BS6と補正／マスタリングの全組合せで各1件、モデル名とStem数を含む本文を確認する。
- `StemWorkflowControllerTests`: BS6補正成功から通知へ同じrun契約が1回だけ渡ることを確認する。
- `StemWorkflowServiceTests`: HT4とBS6の処理開始ログがモデル名、Stem数、全役割を同じ契約から出すことを確認する。
- `StemModeWorkspaceWordingTests`: Helpがrun契約または本番profileから役割を生成し、旧6→4表示を持たないことを確認する。現行README、モデル資産README、歴史的Swift検証記録の役割も確認する。

実行結果は次のとおり。

- `swift test --filter 'StemCompletionNotificationServiceTests|StemWorkflowServiceTests|StemWorkflowControllerTests|StemModeWorkspaceWordingTests'`: 43 tests／4 suites成功。初回は通知本文メソッドの明示return不足、2回目は動的Helpへ変更後も残っていた固定完成文字列のソース期待を確認し、原因へ限定して修正した。3回目は全件成功した。
- `swift test --filter 'StemCompletionNotification|StemWorkflow|StemModeWorkspace|CompletionReport|NoiseCheckReport'`: 127 tests／10 suites成功。通知、run契約、全工程ログ、Session、画面モデル、Help、Completion Report、Noise Reportの横断回帰を確認した。
- `swift build`: Debug build成功。
- `git diff --check`: 成功。
- `graphify update .`: 成功。結果のnode、edge、community数はGoal継続記録へ記載する。

## 未確認事項

macOS通知センターへ実際に表示された通知の外観、Helpと画面内ログの実画面表示は未確認である。これらは後続の実アプリ全工程確認で行う。現在の自動テストが確認するのは、通知要求、動的本文、run契約の受け渡し、ソースと文書の整合である。
