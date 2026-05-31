# タスク管理表 (task.md)

通知機能およびノッチ周辺の進捗表示機能の開発タスク一覧でございます。

## 設計および要件定義
- [x] ユーザー様との通知・ノッチ進捗ラインのデザインおよびインタラクション仕様の合意
- [x] 設計ドキュメント（`implementation_plan.md`）の作成
- [x] タスク管理ドキュメント（`task.md`）の作成
- [x] 変更概要ドキュメント（`walkthrough.md`）の骨組み作成

## 通知機能の土台実装
- [ ] アプリ起動時の通知許可申請ロジックの追加 (`VelouraLucentApp.swift`)
- [ ] 音付きローカル通知送信メソッドの実装 (`NotificationService.swift`)

## ノッチ進捗UIウィンドウの構築
- [ ] `NSScreen` のノッチ座標（`auxiliaryTopLeftArea`、`auxiliaryTopRightArea`、`safeAreaInsets.top`）検出処理の実装 (`NotificationService.swift`)
- [ ] 最前面の透明なボーダーレスウィンドウ `NotchProgressWindow` の作成 (`NotchProgressWindow.swift`)

## SwiftUIによるU字SiriラインおよびカプセルUIの実装
- [ ] 工程名・進捗率を表示する黒いカプセルUIの描画 (`NotchProgressView.swift`)
- [ ] SwiftUI `Path` を用いたU字グラデーション（Siri色）ラインの描画と `trim` アニメーション (`NotchProgressView.swift`)
- [ ] 100%完了時のUIのグリーン系変更と常駐化の実装 (`NotchProgressView.swift`)
- [ ] ウィンドウクリック（タップ）によるアプリのアクティブ化とフェードアウト閉鎖処理の実装

## 処理の結合と状態フック
- [ ] 音声処理の進捗更新イベントから `NotificationService` への進捗伝播の実装 (`ProcessingJob.swift`)
- [ ] 処理の最終完了時におけるローカル通知送信およびノッチウィンドウの完了状態遷移フックの実装 (`ProcessingJob.swift`)

## テストと動作検証
- [ ] 非ノッチ環境における安全なフォールバック（クラッシュ防止）の検証
- [ ] 処理中のクリック透過性とSiri色U字ラインアニメーションの目視確認
- [ ] 完了時の「Complete!」およびグリーン系表示による常駐の検証
- [ ] クリック時のアプリ最前面アクティブ化とフェードアウトクローズの動作検証
- [ ] バックグラウンド処理完了時のOSローカル通知（音付き）の受信テスト
