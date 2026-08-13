# Stem Mode 4／6 Stemマスタリング・最終報告検証

## 対象

- HTDemucs 4 StemとBS-RoFormer-SW 6 Stemの検証済み再ミックスから、既存マスタリング、Noise Report、Completion Reportへ接続する経路
- 通常モードのマスタリングDSPと報告経路は対象外であり、製品コードを変更していない

## 変更前

- `StemWorkflowService.processMastering`は補正済みStemを4本固定で要求したため、BSの6本が揃っていても開始できなかった。
- Stem用Noise ReportとCompletion Reportは6役割分の補正設定で同じ全体2mix報告を繰り返し生成し、全報告が完全一致しない場合は`nil`にしていた。
- 役割別の選択・実効補正設定、guard結果、raw復帰理由、実際の再ミックス設定を最終報告へ保持していなかった。

## 変更後

- マスタリング開始条件は、そのrunの`validationRoles`の完全一致と、処理済み再ミックスの継続可能な構造検証になった。HTは4本、BSは6本を別々に受ける。
- 既存`MasteringService`へ渡す音声は、型付き`.remixed48000`成果物1本のまま。Stem単体や純粋加算を直接渡さない。
- 入力／再ミックス／最終版のNoise Reportは全体2mixに対して1回だけ生成し、補正工程の候補を混ぜず、実際のマスタリング設定による候補だけを持つ。
- Completion Reportは同じNoise Reportを受け、モデル名、Stem数、役割、純粋加算順、共有再ミックス設定と、全役割の補正・guard・fallback・再ミックス実績をSectionへ記録する。
- 最終版の音声解析は1回だけ実行する。

## 検証結果

- `StemMasteringServiceTests`で、検証済み再ミックスURLが既存マスタリングへそのまま渡ること、最終解析が1回であること、最終WAV以外の成果物を保持することを確認した。
- `StemWorkflowServiceTests`で、HT 4 Stemの従来経路とBS 6 Stemのrun契約がマスタリング入口へ到達することを確認した。
- BS 6 Stemについて、6役割の実効設定と9工程guardが報告用契約へ渡ることを確認した。
- 構造検証に失敗した再ミックスは、マスタリングserviceを呼ぶ前に`remixIncomplete`で停止することを確認した。
- 役割別設定が異なる6 Stem報告で、BS-RoFormer-SW、6 Stem、全6役割、Guitarの強い補正と`+2.50 dB`、Pianoのraw復帰理由が欠落しないことを確認した。
- Noise Reportの行別候補と全体候補が、すべて`.mastering`工程だけであることを確認した。
- focused testは43件・5 suitesが成功した。

## 制限

- この手順では実モデルの全曲再実行、実画面、書き出しを行っていない。これらは承認済み計画の後続手順で確認する。
- Completion Reportの役割別Sectionはデータ生成まで検証済み。実画面上の読みやすさは後続のUI実画面確認対象である。
