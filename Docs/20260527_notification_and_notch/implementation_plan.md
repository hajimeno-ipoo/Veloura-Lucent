# ノッチ進捗UI＆通知機能 追加設計書 (Implementation Plan)

本ドキュメントは、Veloura Lucentにおいてマスタリングおよび音声補正の進捗状況をノッチ周辺に可視化し、完了時にOS標準のローカル通知を送信する機能の設計書でございます。

---

## 1. 概要 (Goal)
音声の補正やマスタリングは時間のかかる処理であるため、アプリをバックグラウンドに置いている間でも進捗を美しく直感的に把握でき、完了時に音付き通知で知らされ、ワンクリックでアプリへ戻れる仕組みを提供します。

---

## 2. 決定された仕様 (Requirements)

### 画面上部 (ノッチ直下) のカプセルUI
*   物理ノッチの直下に、中身のテキストが判別できる適度な大きさの黒いカプセルを表示します。
*   カプセル内には、現在進行中の工程名と進捗率（例: `Mastering... 45%`）を表示します。

### Siri色のU字進捗ライン
*   **色**: iPhoneでSiriを起動した際のようなネオン調のグラデーションカラー（シアン、ブルー、パープル、マゼンタなどのブレンド）を採用します。
*   **パスの経路**:
    1.  物理ノッチの左側（メニューバー領域）からスタート。
    2.  ノッチ下にぶら下がっているカプセルUIの底辺（ウィンドウ底）をなぞるように通過。
    3.  物理ノッチの右側へと上って抜けていくU字型（バスタブ型）のラインを描画します。
*   **進捗表示**: 左から右へと進捗率（0%〜100%）に合わせてこのラインが伸びていきます。

### 完了時の演出とインタラクション
*   **完了状態**: 100%に達した際、テキストを「Complete!」に変更し、グラデーションラインおよびカプセルのテーマ色をグリーン系に変更して画面に常駐させます。
*   **クリック時の挙動**: 処理進行中はマウスクリックを透過（他の作業を邪魔しない）させますが、完了状態になった時点でクリック可能にします。ユーザー様がこのカプセルやラインの領域をクリックすると、アプリが最前面にアクティブ化され、ウィンドウはフェードアウトして消去（クローズ）されます。

### ローカル通知
*   マスタリング、または補正処理が完全に完了（100%）したタイミングでのみ、OS標準の音付きローカル通知（バナー）を1回送信します。

---

## 3. 提案される変更 (Proposed Changes)

### [NEW] [NotificationService.swift](file:///Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Services/NotificationService.swift)
通知管理および進捗表示用ウィンドウのライフサイクルと座標検出を司るサービスです。
*   `UNUserNotificationCenter` を使用した音付きローカル通知の送信。
*   `NSScreen.main` から `auxiliaryTopLeftArea`、`auxiliaryTopRightArea`、`safeAreaInsets.top` を取得し、ノッチの正確なX座標および幅・高さを検出。ノッチが検出できない環境ではウィンドウ表示をスキップし、通知のみに安全にフォールバック。
*   `NotchProgressWindow` の生成、破棄、進捗データの更新、および完了時における `ignoresMouseEvents` の `false` への切り替え処理。

### [NEW] [NotchProgressWindow.swift](file:///Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Views/NotchProgressWindow.swift)
進捗表示を重ねるための透明な最前面ウィンドウクラスです。
*   `NSWindow` のサブクラス。
*   `styleMask` に `.borderless` を指定し、`backgroundColor` を `.clear` に設定。
*   `level` を `CGWindowLevelForKey(.mainMenuWindow) + 1` （メニューバーより前面）に設定。
*   SwiftUIの `NotchProgressView` を `NSHostingView` を介して配置。

### [NEW] [NotchProgressView.swift](file:///Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Views/NotchProgressView.swift)
進捗表示UIを描画するSwiftUIビューです。
*   黒いカプセル、工程名テキスト、進捗率テキストの描画。
*   SwiftUIの `Path` を用いたU字型パス（ノッチ左端外側 → カプセル底辺 → ノッチ右端外側）の定義と、Siri風グラデーションカラーの適用、`trim` を用いた進捗率アニメーション。
*   完了時の表示状態への遷移（テキスト「Complete!」、ラインのグリーン化）。
*   クリック（タップ）を検知した際に、`NotificationService` を通じてアプリのアクティブ化要求およびウィンドウ閉鎖アニメーションをトリガー。

### [MODIFY] [VelouraLucentApp.swift](file:///Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/App/VelouraLucentApp.swift)
*   アプリ起動時（`AppDelegate.applicationDidFinishLaunching`）に、`UNUserNotificationCenter.current().requestAuthorization` を呼び出してローカル通知の許可をユーザー様に要求します。

### [MODIFY] [ProcessingJob.swift](file:///Users/apple/Desktop/Dev_App/Veloura%20Lucent/Sources/VelouraLucent/Models/ProcessingJob.swift)
*   処理進行時（進捗パーセンテージの更新）に `NotificationService` に進捗率と工程名（Denoising/Masteringなど）を通知し、ノッチ進捗UIを更新。
*   最終完了時に `NotificationService` を通じてローカル通知を送信し、進捗ウィンドウを完了状態（Complete!）に移行。

---

## 4. 検証計画 (Verification Plan)

### 自動テスト (Automated Tests)
*   ノッチ検出ロジック（`NSScreen` の拡張またはユーティリティメソッド）が、ノッチ情報が取得できないディスプレイ環境（非搭載モデルや外部ディスプレイ）においてもクラッシュせず、正しく `nil` を返すことの単体テストを記述・実行します。

### 手動検証 (Manual Verification)
*   **UIと描画の目視確認**:
    *   処理開始時にノッチの下に黒いカプセルが出現し、Siri色ネオングラデーションのU字ラインがノッチの左側からカプセル底を通ってノッチの右側へ綺麗に伸びていくか。
*   **マウスクリック透過テスト**:
    *   処理が進行中（0%〜99%）のとき、進捗ウィンドウの周辺をクリックしても後ろのデスクトップや別アプリを問題なく操作できるか（クリックイベントが透過するか）。
*   **完了状態の常駐テスト**:
    *   100%完了時にカプセルが「Complete!」と緑色に変化し、消えずに画面に留まるか。
*   **クリック復帰テスト**:
    *   完了状態のカプセルまたはライン領域をクリックした際、Veloura Lucentアプリが最前面にアクティブ化され、カプセルUIがフェードアウトして消えるか。
*   **通知の検証**:
    *   アプリがバックグラウンドにある状態で完了した際、OSのバナー通知（音付き）が届くか。
