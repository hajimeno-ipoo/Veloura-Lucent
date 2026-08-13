# 完全6Stem化 Session・失敗・cancel・再実行の検証記録

## 対象

Veloura LucentのStem Modeについて、HTDemucsの4StemとBS-RoFormer-SWの6Stemが、同じSession／Controllerを使いながら各runの契約どおりに状態遷移することを確認した記録です。

音声の分離、補正、再ミックス、マスタリングDSPの計算内容は、この手順では変更していません。

## 実装した境界

- Sessionはrun契約から、補正完了時と全工程完了時に必要な成果物数を決めます。
  - HTDemucs: 補正完了10、全工程完了12
  - BS-RoFormer-SW: 補正完了14、全工程完了16
- 詳細進捗はrun契約の有効Stemだけで作ります。分離工程名も`4Stem分離`／`6Stem分離`へ切り替わります。
- 成果物、構造検証、Stem評価のeventはrun IDを明示してControllerへ渡します。
- 現在のrun ID、実行中の工程、run契約に一致しないeventは表示状態へ反映しません。
- 補正失敗・cancelでは当該runの成果物を破棄し、選択中入力を残します。
- 再ミックス失敗・cancelでは、補正済み全有効Stemと純粋加算を残します。
- マスタリング失敗・cancelでは、補正結果、純粋加算、検証済み再ミックスを残し、最終版だけを除きます。
- 再ミックス設定変更では再ミックスと最終版だけを無効化し、新入力では前runを破棄します。
- 最終版の保存・検証・解析を始めてからControllerが結果を確定するまで、cancelを受け付けないcommit lockを有効にします。

## 検証結果

2026-08-12に次を実行しました。

```bash
swift test --filter 'StemWorkflowSessionTests|StemWorkflowControllerTests|StemModeWorkspaceModelTests'
```

- 56 tests / 3 suites: 成功
- 確認対象: HT4／BS6成果物数、進捗分母、契約外artifact、古いrun event、補正失敗cleanup、retry、入力保持、再ミックスとマスタリングの失敗／cancel、設定変更、final commit lock

```bash
swift test --filter 'StemWorkflow|StemModeWorkspace'
```

- 91 tests / 6 suites: 成功
- 実行時間: 60.371秒
- Workflow ServiceのBS 6Stem補正、1Stem raw復帰、6Stem再ミックス、共有伴奏処理、マスタリング接続も同じ変更後に成功

## 未確認

- 全テスト、Release build、BS／HT実モデル全工程、実画面は後続の承認済み手順で確認します。
- UIのGuitar／Piano表示、個別試聴、個別書き出しは手順11の対象です。
