# Veloura Lucent — Stem Mode 実装進捗

最終更新：2026-07-28

この文書は、現在の承認済み仕様と現行コードだけを根拠にする。廃止した永続run、checkpoint、schema、作業再開の過去記録は完了根拠に使用せず、本文から削除した。

## チェック規約

- `[x]`：現行コード、実行結果、またはテストで完了を確認済み
- `[ ]`：未実施または確認未完了
- 数値の変化だけで音質合否を決めない
- サンプル音源の値を本番用閾値や固定mappingにしない

## 現在の状態

- [x] Stem Modeは通常モードと別画面で動作する
- [x] Stem Mode画面の工程表示、直近ログ、全体進捗、詳細ログを通常モードの表示契約へ揃える
- [x] 補正段、再ミックス段、マスタリング段を別のユーザー操作に分離した
- [x] 作業状態は通常モードと同じくアプリ起動中のメモリで保持する
- [x] Stem一時音声はsystem temporary directory配下に限定した
- [x] モデル管理と音楽処理を分離した
- [x] AIの責務は4Stem分離で終了する
- [x] 補正後は保存済み4Stemと補正済み純粋加算を表示し、`readyForRemix`で停止する
- [x] 再ミックス後は純粋加算A／再ミックスBを表示し、`readyForMastering`で停止する
- [x] 自動再ミックス値と、項目ごとの手動上書きを両方使用できる
- [x] 検証済み再ミックスが揃うまでマスタリングを開始できない
- [ ] 実画面で入力選択から書き出しまでの全操作を最終確認する
- [ ] 完成音のユーザー試聴を完了する

## 1. 通常モード保護

- [x] 通常モードの補正段とマスタリング段をコードから確認
- [x] 通常モードのUI所有元、表示データ、操作ボタン、一時音声、書き出しを確認
- [x] 通常モードの解析、`NoiseMeasurementService`、route、下位DSP、DSP内部guardをStem側から呼び出す
- [x] 通常モードの音質処理ファイルにStem条件を混在させない
- [x] 通常モード既存ファイルの変更を、承認済み共通UI境界の`VelouraLucentApp.swift`、`VelouraCommands.swift`、`ContentView.swift`、`VelouraMainWorkspaceView.swift`、`WorkspaceFooterView.swift`に限定し、音質処理ファイルを変更しない（worktreeに元からある`DAWKnobMetrics.swift`の資産Bundle取得差分は別変更として区別）
- [ ] 実画面で通常モードの見た目と操作が変化していないことを最終確認

## 2. モデル管理

- [x] AIモデル2資産の取得前にユーザー確認を行う
- [x] 固定Revision、容量、SHA-256を検証してから有効化する
- [x] `mlx.metallib`等のMLX実行資産はアプリへ同梱する
- [x] ルート`Package.swift`から`mlx-swift`、`swift-transformers`、`swift-jinja`の重複直接宣言を除去し、未使用依存警告なしでDebug／Release build成功。`Package.resolved`の固定内容は不変、`StemModelContractTests`は15 tests／1 suite、失敗0
- [x] 取得、修復、「モデル検証」（資産の再検証）、「モデル再取得」（AIモデル2資産の完全再取得）を右サイド「アプリ」タブの「Stem分離」へ統合
- [x] モデル状態にかかわらずStem Mode画面を維持し、入力選択・入力表示解析を利用可能にする
- [x] モデル未準備時は補正だけを無効にする
- [x] モデル名、固定Revision、分離設定を`!`アイコンのポップアップへ集約
- [x] 専用モデル管理画面と、その画面へ切り替える遷移を除去
- [x] 音楽処理開始時にモデル取得やSHA-256再検証を実行しない
- [x] 音楽処理は確認済みinstallationを受け取る

## 3. 入力と補正段

- [x] 入力2mix選択後、波形・再生・スペクトログラム・通常解析値の表示解析を開始
- [x] 入力表示解析中でも補正を開始可能
- [x] 補正開始と補正キャンセルで入力表示解析を消去しない
- [x] 入力変更時だけ旧入力解析をキャンセルし、遅延結果で新入力を上書きしない
- [x] 入力のchannel layoutを確認し、自動判定できない場合だけユーザーへ確認する
- [x] Demucs入力を44.1 kHz、stereo、Float32で生成
- [x] `shifts=2`、`overlap=0.25`、`split=true`、モデル契約segment、`batchSize=1`、seedの明示値を使用
- [x] vocals、drums、bass、otherの4Stemを分離
- [x] raw 4Stemを44.1 kHzで一時保存
- [x] 各raw Stemを補正開始境界で1回だけ48 kHzへ変換
- [x] 各Stemで通常モード共通解析、NoiseMeasurement、route、下位DSP、DSP内部guardを一本道で実行
- [x] 各Stemの補正設定を実処理へ接続
- [x] vocalsの息、子音、サ行、formant、倍音、声の芯を役割別guardで保護
- [x] drumsのattack、transient、シンバルの余韻を役割別guardで保護
- [x] bassの基音、倍音、音程、50 Hz／60 Hz付近、低域位相を役割別guardで保護
- [x] otherの残響、ambience、空間、ステレオ感を役割別guardで保護
- [x] 新しい絶対閾値、固定mapping、Stem専用品質スコアを追加しない
- [x] 候補生成、候補比較、16通り評価、AI品質選択を行わない
- [x] 補正済み4Stemを48 kHzで一時保存
- [x] 補正済み4StemをFloat32で純粋加算
- [x] raw再ミックスは入力2mixで代用できない内部診断中だけメモリ上で作成し、保存しない
- [x] 補正済み4Stemをgain・pan・reverb・normalization・dynamics・limitingなしで純粋加算
- [x] `corrected-pure-sum-48000.wav`を48 kHz、stereo、Float32で一時保存して検証
- [x] 補正完了直後に純粋加算の波形、解析値、試聴を接続
- [x] 正常な補正済み4Stemと検証済み純粋加算が揃った時だけ補正完了と100%にする
- [x] 補正完了後は再ミックス待機で停止

## 4. guardと局所fallback

- [x] guardを独立候補の品質選択に使用しない
- [x] 通常モードと同じく、DSP内部で補正量の弱化、skip、処理前信号維持を行う
- [x] Stem役割別guardは通常routeを強めず、保護に必要な場合だけ弱化またはskip方向へ制限
- [x] 1Stemの非致命的失敗で残り3Stemを破棄しない
- [x] 問題DSPだけを弱化またはskip
- [x] 必要な場合だけDSP処理前Stemを維持
- [x] Stem処理自体が非致命的に失敗した場合だけ該当raw Stemへfallback
- [x] NaN、Infinity、音声構造不正、読込不能等の継続不能を致命的エラーとして分離
- [x] 位相・相関・帯域・ピークの数値変化だけを失敗にしない
- [x] 明確な全体極性反転は原因Stemへ帰属し、局所的に処理前状態へ戻す
- [x] ドラムのraw／補正済みStemを同じ時間位置で比較し、失われた高域アタックだけをraw sample包絡線内で回復
- [x] 補正済み側がrawと同等以上のアタックを持つ場合はトランジェントを生成しない

## 4.5 再ミックス段

- [x] 今回のraw／補正済みStemだけから自動設定を作る
- [x] active program level差に基づくStem別gainを±6 dB内で設定
- [x] raw／補正済みStemの同じ20 ms活動区間で左右中心差の方向と大きさが明確な場合だけStem別panを設定
- [x] drums／bassの35〜180 Hzとvocals／otherの1.5〜5.5 kHzについて、両者が実際に活動する区間だけ帯域ducking
- [x] 2系統の帯域duckingで、有効・無効と処理量を別々に自動設定・手動上書き
- [x] 再ミックス処理順をStem別gain、条件付き帯域ducking、Stem別pan、pan後send、共有reverb、dry／return加算、構造検証へ固定
- [x] Stem別sendを1基の共有reverbへ送り、減衰制御付きfeedback combとall-pass拡散を使用
- [x] 手動に切り替えた項目だけ自動値を上書きし、自動値更新後も保持して新しい補正セッション開始時だけ初期化
- [x] 再ミックス段ではnormalization、saturation、limiting、固定-3 dBを行わない
- [x] `stem-remix-48000.wav`を保存・検証し、純粋加算とのA/Bへ接続
- [x] 再ミックス設定変更、失敗、キャンセルで再ミックスと最終版だけを無効化し、補正済み4Stemと純粋加算を保持

## 5. マスタリング段

- [x] ユーザーの「マスタリングを実行」操作でだけ開始
- [x] raw再ミックスを保存成果物、A/B対象、書き出し、fallback、マスタリング入力にしない
- [x] 再ミックス段で保存・検証した同一の`stem-remix-48000.wav`を、再生成や重複WAVコピーなしで既存`MasteringService`へ直接渡す
- [x] 既存マスタリング前解析、トーン、de-ess、ダイナミクス、ステレオ、ラウドネス、ピーク、最終guardを維持
- [x] Stem Mode最終版を一時WAVとして保存
- [x] 通常モード共通の最終解析・品質レポートを生成
- [x] ユーザー操作で純粋加算、再ミックス、補正済みStem、最終版を書き出す

## 6. 一時保存とキャンセル

- [x] 保持するStem一時音声を分離入力、raw 4Stem、補正済み4Stem、純粋加算、再ミックス、最終版に限定
- [x] 各WAVを`.partial.wav`へ書込み、サンプルレート、channel数、frame数、NaN／Infinityを検証後に最終名へ移動
- [x] 書込み失敗時は作成中の未完成ファイルだけを削除
- [x] 4raw Stem分離は4本の書込みと音声検証が全て成功した時だけ有効とする
- [x] 分離失敗時は今回の未完成raw Stem群だけを削除
- [x] 分離開始前から存在したファイルを失敗時削除の対象にしない
- [x] 補正キャンセル時は今回のStem一時音声を削除し、選択入力、入力表示解析、設定を維持
- [x] 再ミックスキャンセル／失敗時は補正済み4Stemと純粋加算を維持し、再ミックスと最終版の未完成音声だけを削除
- [x] マスタリングキャンセル／失敗時は再ミックスまでを維持し、最終版の未完成音声だけを削除
- [x] 入力変更時に変更前セッションのStem一時音声を削除
- [x] アプリ終了時に現在セッションのStem一時音声を削除
- [x] 永続run、checkpoint、workflow schema、設定／解析JSON、保存履歴、起動後再開を処理経路から除去
- [x] 未使用の「直近操作履歴」状態を削除
- [x] 完了直後に取り出すだけだった未処理完了イベント状態を削除し、完了時の直接通知へ簡素化

## 7. UI・UX

- [x] 通常モードの上部操作を変えず、Stem Modeだけに入力、補正、再ミックス、マスタリング、書き出しを表示
- [x] 通常補正／Stem Modeの切り替えを共通Liquid Glass segmented pickerで表示する
- [x] Rootが単一の`.principal` toolbarを常時所有し、通常補正／Stem Mode切り替え時は同じtoolbar内の処理先と有効状態だけを変更する
- [x] メニューバーの音声選択、補正、マスタリング、2mix再生、書き出しをRoot所有の現在モード操作へ接続し、Stem Modeだけに再ミックス操作を追加する
- [x] 表示メニューの「モード」から通常補正／Stem Modeを選び、アプリ本体を既存`selectMode`で切り替える
- [x] Stem Modeのメニューバー書き出しに、純粋加算、再ミックス、補正済み4Stem、Stem Mode最終版を表示し、未生成項目だけを無効化する
- [x] SwiftUI標準sidebarボタンをsidebar列で除去し、切り替え後に非同期削除する一時表示をなくす
- [x] 上部の入力、補正、マスタリング、書き出しを通常モードと同じLiquid Glass表示・hover動作にする
- [x] Stem Modeの書き出しボタン全体を無効化せず、通常モードと同じhover表示を維持し、未生成の成果物だけを無効化する
- [x] 中央の基本表示／詳細解析を通常モードと同じヘッダー位置・幅・余白にする
- [x] 基本表示／詳細解析タブ直下の重複した画面名・説明文・通常詳細解析のヘルプポップアップを削除し、実内容から表示する
- [x] 詳細解析の共通部分を通常モードと同じ順序・表示・単位・差分・help・hover・未取得時動作で接続する
- [x] 詳細解析へStem役割別解析、役割別guard証跡、raw／補正後Stem比較を接続する
- [x] 詳細解析へ入力2mix／raw再ミックス／補正済み純粋加算／実行済み再ミックスの既存検証測定値を接続する
- [x] 入力解析の一部だけ成功した場合も、成功済みの表示用解析結果を保持する
- [x] Stem固有解析／再ミックス固有解析を通常詳細解析と同じ開閉・初期閉状態・ヘルプへ統一し、本文を`callout`以上で表示する
- [x] Stem固有解析／再ミックス固有解析の専用カード装飾を削除し、通常詳細解析と同じ`analysisCard()`と`DisclosureToggleButton`を直接使用する
- [x] Stem固有解析を詳細ログの複製にせず、構造化した最終適用結果と時系列ログの役割をヘルプ・見出しで区別する
- [x] Stem固有解析と補正ログから、通常モードが現在処理しているように見える表記を除き、「共通の補正判定」「既存DSP」などStem Mode内の役割が分かる表記にする
- [x] 左の音源区画と工程区画を維持
- [x] 補正、再ミックス、マスタリングの状態、現在工程、詳細、進捗率、実際の全内部工程を別ブロックで表示
- [x] ドラムのraw基準トランジェント保護を補正欄の独立工程として表示
- [x] 再ミックス欄をgain、条件付き帯域制御、pan、pan後send、共通reverb、dry／return加算、保存、検証の実処理順で表示
- [x] 中央の入力、純粋加算、再ミックス、最終版の波形・解析・試聴を接続
- [x] 純粋加算A／再ミックスBの専用A/Bと任意の再生時ラウドネス合わせを接続
- [x] 通常3音源、Stem raw／補正後、純粋加算／再ミックスの波形・試聴操作を同じ`AudioWaveformWorkspaceView`へ統一
- [x] A/Bはユーザーの試聴だけに使用し、DSP採否やマスタリング入力に影響させない
- [x] 2mix試聴欄と独立したStem試聴欄を基本表示へ追加
- [x] 選択中役割の検証済みraw／補正後Stemを上下2段の波形で表示
- [x] Stem専用の再生・一時停止・停止・raw／補正後切替・シーク・音量・ラウドネス合わせを接続
- [x] 2mix試聴とStem試聴の状態を分離し、一方の再生開始時に他方だけを停止
- [x] 中央と右設定欄のStem選択を同じ役割へ統一
- [x] 入力変更・補正キャンセル・未検証成果物でStem試聴対象を正しく消去または無効化
- [x] 右上へStem専用の補正、再ミックス、マスタリング、アプリ設定を接続
- [x] 再ミックス設定にStem別gain／pan／send、2系統のmasking、共有reverb return／decayの自動値と手動切替を表示
- [x] 再ミックス連続値を既存DAWノブへ統一し、gain差、pan差、空間成分減少、衝突量と自動判断を表示
- [x] 補正タブにStem選択、Stem別プリセット、内部補正値の調整を追加
- [x] 補正タブの基本・掃除と修復・上級を通常モードと同じロータリーノブと列配置で表示
- [x] マスタリングタブは通常モードと同じプロファイルメニュー、説明、目標値、復帰操作、警告、基本・音色・上級の開閉カード、ロータリーノブ、単位、3点ラベル、ヘルプ、列配置を使用し、実行中だけ操作を無効化
- [x] アプリタブは解析モードとアプリ設定を扱う
- [x] 右下の「解析結果と品質確認」は、選択中の入力／純粋加算または再ミックス／最終版についてIntegrated Loudness、True Peak、ダイナミクス、ステレオ幅、品質警告、完了後レポートを表示し、未解析時は小型状態表示にする
- [x] 直近ログを入力、補正、再ミックス、マスタリング、ユーザー書き出しの構造化操作履歴にする
- [x] 全体進捗の書き出しを、内部最終版生成ではなくユーザーによる外部保存として扱う
- [x] 詳細ログは補正、再ミックス、マスタリングを分け、制御イベントを除いた主要工程を短い行で実行順に表示する
- [x] 通常／Stemの左工程一覧、詳細ログ外枠、右詳細設定タブを共通表示部品へ統一
- [x] 「省略」はrouteが処理不要と判断した工程だけに使用し、DSP失敗・構造不正・Stem役割別guard不確実から処理直前Stemを安全に維持できた工程は「完了」として理由をログ・guard記録へ残す
- [x] 独自6ページナビゲーション、14工程の単一系列、専用操作体系を使用しない
- [x] Rootが通常／Stem共通のワークスペース外枠を1個だけ所有する
- [x] Root所有の1個の`NavigationSplitView`で、左サイドを最小220 pt・基準260 pt・最大300 ptとし、通常モードと同じシステムサイドバー外観を使う
- [x] 右インスペクタを440 pt、中央を620 pt以上の可変領域にする
- [x] モード別の`NavigationSplitView`、列幅状態、幅履歴、座標補正を追加しない
- [x] モード切り替えでは左・中央・右の内容だけを交換し、外枠、toolbar、左右開閉状態、window設定を維持する
- [x] 通常／Stemの中央を共通の固定ヘッダー、スクロール本文、固定下部、詳細ログ切り替えで構成する
- [x] 通常／Stemの下部を共通寸法の直近ログ・全体進捗配置にする
- [x] 左右のタイトルバー開閉ボタンを同じ`LiquidGlassMotion.panel`とモーション低減対応へ統一する
- [ ] 共通外枠修正後の通常／Stem切り替え、最大化、フルスクリーン、左右開閉を実画面で確認する

## 8. 自動テストとビルド

- [x] Debug build：`swift build`成功
- [x] 2026-07-22の工程表示・ログ・外部保存修正：対象47 tests／7 suites、失敗0、`swift build`成功
- [x] 2026-07-23の詳細ログ工程補完：`StemWorkflowServiceTests` 4件、`StemMasteringServiceTests` 2件、`StemWorkflowSessionTests` 12件、合計18 tests／3 suites、失敗0、`swift build`成功
- [x] 2026-07-23の工程状態意味修正：`StemCorrectionServiceTests`、`StemWorkflowSessionTests`、`StemWorkflowServiceTests`の23 tests／3 suites、失敗0
- [x] 2026-07-23の上部Liquid Glass・中央ヘッダー統一：`StemModeWorkspaceWordingTests` 11件、`UIWordingPolicyTests` 25件、合計36 tests／2 suites、失敗0
- [x] 2026-07-24の共通ワークスペース外枠とRoot所有`NavigationSplitView`復元：`UIWordingPolicyTests`、`StemModeWorkspaceWordingTests`、`ContentViewAnalysisLoggingTests`の39 tests／3 suites、失敗0、Debug／Release build成功
- [x] 2026-07-24の基本表示／詳細解析の重複ヘッダー削除：`UIWordingPolicyTests`、`StemModeWorkspaceWordingTests`の36 tests／2 suites、失敗0、Debug／Release build成功
- [x] 2026-07-24の独立Stem波形・試聴欄：`StemModeWorkspaceModelTests`、`StemModeWorkspaceWordingTests`、`AudioPreviewControllerTests`、`StemModeCorrectionSettingsViewTests`、`UIWordingPolicyTests`の102 tests／5 suites、失敗0、Debug／Release build成功
- [x] 2026-07-26のStem補正ロータリーノブ統一：`StemModeCorrectionSettingsViewTests`、`StemModeWorkspaceWordingTests`の13 tests／2 suites、失敗0、対象ファイルのDebugコンパイル成功
- [x] 2026-07-26の詳細解析共通表示・Stem固有解析接続：`StemModeWorkspaceModelTests`、`StemModeWorkspaceWordingTests`、`StemCorrectionServiceTests`、`StemWorkflowServiceTests`、`UIWordingPolicyTests`、`StemInputDisplayAnalysisServiceTests`の73 tests／6 suites、失敗0、Debug／Release build成功
- [x] 2026-07-26のStem固有解析開閉・文字可読性・カード／開閉ボタン共通化・詳細ログとの役割区別：通常詳細解析と同じ`analysisCard()`と`DisclosureToggleButton`を直接使用し、`StemModeWorkspaceWordingTests`、`UIWordingPolicyTests`の37 tests／2 suites、失敗0、Debug／Release build成功
- [x] 2026-07-26のStem固有解析・補正ログの実行モード誤認表記修正：`StemCorrectionServiceTests`、`StemModeWorkspaceWordingTests`、`UIWordingPolicyTests`の44 tests／3 suites、失敗0、Debug／Release build成功
- [x] 2026-07-26の左右サイド開閉アニメーション統一：左のタイトルバーボタンも右と同じ`LiquidGlassMotion.panel`とモーション低減設定を使用し、`UIWordingPolicyTests`、`StemModeWorkspaceWordingTests`の37 tests／2 suites、失敗0、Debug／Release build成功
- [x] 2026-07-26の右サイド解析結果表示整理：通常／Stemの見出しを「解析結果と品質確認」へ統一し、未解析時を小型表示へ変更。`UIWordingPolicyTests`、`StemModeWorkspaceWordingTests`の38 tests／2 suites、失敗0、Debug／Release build成功
- [x] 2026-07-28の任意再ミックス段と仕様不一致修正：再ミックス／状態のfocused 33 tests／2 suites、workflow／controller／session／画面文言を含む関連71 tests／6 suitesが失敗0。Release build成功、`git diff --check`成功
- [x] 2026-07-28の全670 tests／78 suites並列実行で、既存`VelouraLucentPreview`を共有する8 suitesに27 issuesを確認。失敗8 suitesを別プロセスで順番に再実行し、合計113 testsが失敗0。再ミックス、トランジェント回復、Stem workflow／controller／sessionは全件実行内でも失敗0
- [x] 2026-07-28の左サイド工程、下部ログ、中央A/B、右設定の共通UI統一：workflow／再ミックス／試聴／画面文言を含む156 tests／11 suites、補正／トランジェント回復11 tests／2 suitesが失敗0。Release build成功、`git diff --check`成功。全テスト、実画面操作、実音比較は今回の完了根拠に使用しない
- [x] 2026-07-29の通常モード準拠監査修正：右の解析結果を共通部品化し、補正プリセット、解析モード、入力選択、処理済み音源名、ログアイコンを通常モードの表示・操作契約へ統一。`StemModeWorkspaceWordingTests`、`StemModeCorrectionSettingsViewTests`、`StemModeWorkspaceModelTests`、`UIWordingPolicyTests`の71 tests／4 suitesが失敗0、Release build成功。全テスト、実画面操作、実音比較は今回の完了根拠に使用しない
- [x] 一時音声／分離／workflow／マスタリング／状態・UI接続の最終重点テスト：28 tests／8 suites、失敗0
- [x] 解析／補正／Stem guard／再ミックス／UI接続の重点テスト：99 tests／14 suites、失敗0
- [x] `StemTemporaryAudioStore`のFloat32 WAV書込みが出していた不要なnon-interleaved警告を解消
- [ ] 全テストを現行差分で完走（実音・性能系を含む長大な直列実行は停止。未完了のまま扱う）
- [x] Release build：`swift build -c release`成功
- [x] `git diff --check`
- [x] 最終差分レビュー

## 9. 実モデル・実画面・実音

- [x] 固定Revisionの実HTDemucsで4Stem生成を確認
- [x] 同じseedと設定で分離結果が再現することを確認
- [x] 192.999979秒、246.199979秒、304.8秒の所有AI生成音源で二段階workflowを完走した実績あり
- [x] 想定最大長の音源（約5分）として304.8秒音源のproduction完走を確認
- [x] 10分以上の人工連結音源を必須検証対象から除外
- [x] 現行のメモリ状態／一時WAV実装で、0.5秒入力による固定HTDemucsの補正段とマスタリング段を再確認（48.927秒、失敗0）
- [x] 2026-07-28追加の補正／再ミックス／マスタリング三段階を、0.5秒入力と固定HTDemucs実モデルで再実行（48.674秒、失敗0）
- [x] 署名済み配布アプリの起動継続と通常モードの基本画面・二段階操作表示をAccessibilityで確認
- [ ] 実画面で右サイド「Stem分離」のモデル状態・モデル検証・モデル再取得、入力選択、補正、再ミックス、マスタリング、書き出しを確認（2026-07-28はアプリ起動と通常画面取得まで成功。Stem Mode切替時に画面操作ツールが`native pipe closed`となり未完了）
- [ ] 実画面で補正、再ミックス、マスタリングの各キャンセルを確認
- [ ] 完成音について「自然」「違和感がある」「判断できない」の3段階でユーザー試聴
- [ ] 「判断できない」を自動品質選択に使用しない

ユーザー報告による不具合再現記録：

- 2026-07-22、ユーザーから、署名済み配布アプリのStem Modeで所有音源`violin #002 睡眠.wav`（3分13秒、48 kHz／16 bit／stereo）を選択した際の画面状態が報告された。
- モデル管理画面では、「Stem中止」でStem Mode画面へ戻り、「通常モード切り替え」で通常モードへ移動したと報告された。
- 補正の開始・キャンセルでは、4Stem分離進捗が`0.010909091401845218`から`0.001818181900307536`へ後退したとして処理が停止したと報告された。
- マスタリングの開始・キャンセルと書き出しは、前段の4Stem分離で停止するため実行できなかったと報告された。
- 上記はユーザーが提示した不具合の再現資料であり、実画面確認の完了根拠には使用しない。実画面確認のチェック項目は未完了のままとする。

モデル管理UIの統合記録：

- 2026-07-24、専用モデル管理画面を廃止し、右サイド「アプリ」タブの「Stem分離」へモデル状態、再検証、取得、修復、完全再取得、進捗、中断、取得前確認を統合した。
- モデルが未取得・破損・未確認でもStem Mode画面は表示し、入力選択と入力表示解析を維持する。補正だけをモデル利用可能まで無効にする。
- モデル名、固定Revision、`shifts / overlap`、`split / segment`、`batch size / run seed`は`!`アイコンのポップアップへ移した。
- モデル検証・取得・有効化の中核処理と、通信前のユーザー確認契約は変更していない。
- 実画面操作はユーザー指示により実施しておらず、確認項目は未完了のままとする。

進捗・状態管理の修正記録：

- 2026-07-22、Demucsから順番に届いた分離進捗を個別`Task`へ分岐し、画面へ届く順序を壊していた接続を、通常モードの順序付き通知と同じ`AsyncStream`方式へ修正した。
- `progressRegressed`、工程後退、重複開始など、表示通知を理由に音楽処理を停止していたStem専用条件を削除した。
- 古い処理の表示イベントは現在の処理識別子と一致しない場合に反映せず、表示更新エラーは警告ログに留め、音楽処理Taskをキャンセルしない。
- 補正完了とマスタリング開始条件は表示進捗ではなく、補正処理成功、検証済み補正Stemが4役割すべて揃ったこと、検証済み補正後再ミックスが保存されたことを使用する。成功時に補正工程表示を100%へ確定する。
- `StemWorkflowSessionTests`、`StemWorkflowServiceTests`、`StemWorkflowControllerTests`の10 tests／3 suitesは失敗0。実画面の再確認は行っておらず、未完了のままとする。

補正後表示接続の修正記録：

- 2026-07-22、補正段が補正済み4Stemだけで終了し、補正後再ミックスの生成がマスタリング開始まで遅延していたため、補正完了後も波形・スペクトログラム・解析値が空になることをコードから確認した。
- 純粋加算、raw再ミックス内部診断、補正後再ミックス検証・保存を補正段へ移し、補正完了時に同じ成果物を表示へ接続した。
- マスタリング段は補正段で確定した同一の補正後再ミックスを読み、再生成せず既存`MasteringService`へ渡す。
- マスタリングキャンセル／失敗時は補正後再ミックスの成果物と表示を維持し、最終版だけを無効化する。
- `StemWorkflowSessionTests`、`StemWorkflowServiceTests`、`StemWorkflowControllerTests`、`StemModeWorkspaceModelTests`、`StemModeWorkspaceWordingTests`の37 tests／5 suitesは失敗0。実画面確認はユーザー指示により実施していない。

補正後2mix書き出しの修正記録：

- 2026-07-26、補正後再ミックスが生成・検証・保存済みでも、書き出し対象から明示的に除外されていたため、Stem Modeの書き出しメニューへ表示されないことをコードから確認した。
- 検証済みの補正後再ミックスを正式な書き出し対象へ追加し、補正後再ミックス、補正済み4Stem、Stem Mode最終版の順で個別に書き出せるようにした。
- 入力2mix、raw Stem、raw再ミックスは書き出し対象へ追加していない。
- 関係する`StemModePresentationTextTests`、`StemModeWorkspaceModelTests`、`StemModeWorkspaceWordingTests`の37 tests／3 suites、追加確認した`StemModeWorkspaceWordingTests`の11 tests／1 suite、Debug buildは失敗0。実画面操作はユーザー指示により実施していない。

## 10. 完了条件

次を全て満たした時だけStem Modeを完了とする。

- [x] 通常モードの音質経路に未承認のStem差分がない
- [x] モデル管理と音楽処理が分離している
- [x] AIが4Stem分離だけを行う
- [x] Stem別処理が通常モードの一本道routeを中核にする
- [x] Stem役割別の音楽成分保護guardが実処理へ接続している
- [x] 候補比較、AI品質選択、16通り評価がない
- [x] 補正段とマスタリング段が分離している
- [x] 補正処理成功、検証済み補正4Stem、検証済み補正後再ミックスの完了前はマスタリングを開始できず、成功時に補正表示を100%へ確定する
- [x] キャンセル時の保持・削除範囲が通常モードの思想に一致する
- [x] 永続作業状態、保存履歴、起動後再開、過剰な候補成果物がない
- [x] 補正後再ミックスが既存マスタリングへ直接接続している
- [ ] 現行差分の全テストが完走
- [x] Release buildが成功
- [x] 差分レビューが完了
- [ ] 実画面の全操作確認が完了
- [ ] 完成音のユーザー試聴が完了
