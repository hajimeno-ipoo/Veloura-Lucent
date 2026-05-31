# タスク管理表 (task.md)

完了通知機能の開発タスク一覧です。

## 通知機能
- [x] アプリ起動時の通知許可申請 (`VelouraLucentApp.swift`)
- [x] 音付きローカル通知送信 (`NotificationService.swift`)

## 処理完了との結合
- [x] 補正完了時のローカル通知送信 (`ProcessingJob.swift`)
- [x] マスタリング完了時のローカル通知送信 (`ProcessingJob.swift`)
- [x] 各処理で完了通知を1回だけ送る制御 (`ProcessingJob.swift`)

## テストと動作検証
- [x] 補正完了通知が1回だけ送られることの単体テスト
- [x] マスタリング完了通知が1回だけ送られることの単体テスト
- [ ] バックグラウンド状態でOS通知バナーと通知音が出ることの目視確認
