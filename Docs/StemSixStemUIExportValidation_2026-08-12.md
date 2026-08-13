# BS-RoFormer-SW 6Stem UI・試聴・書き出し検証記録

日付: 2026-08-12

## 対象

承認済み完全6Stem化計画の手順11として、BS-RoFormer-SWのGuitar／Pianoを、選択、波形、個別A/B、補正・再ミックス設定、詳細解析、画面とアプリの書き出しメニューへ接続した。HTDemucsの4Stem表示と通常モードUIは変更対象にしていない。

## 変更前に確認した状態

- 画面の役割一覧は、実行結果のrun契約がない時にHTDemucsの4役割へ戻る経路があり、選択中BSモデルの6役割を実行前に表示できなかった。
- 契約外のGuitar／Pianoを直接選択でき、HTへ切り替えた後も無効な役割選択が残り得た。
- Controllerが検証済みartifactを追加した後、選択中Stemのraw／補正後previewを更新し直す経路がなかった。
- Rootの書き出しメニューは補正済みDrums／Bass／Other／Vocalsを固定列挙し、Guitar／Pianoと補正済み純粋加算を除外していた。
- Stem Modeの見出しと詳細解析には`4Stem`固定文言が残っていた。

## 実装した契約

- `StemModeModelPresentation`が、検証済みmodel installationから得た`StemModelRunContract`を保持する。
- `StemModeWorkspaceModel.availableStemRoles`は、実行後なら結果run契約、実行前なら検証済み選択モデル契約を使用する。結果runがある間は、選択モデルを変えても結果の役割を変更しない。
- 現在の契約にない役割選択は受け付けない。契約変更で選択役割が無効になる場合はStem previewを停止し、Vocals、Vocalsがなければ最初の有効役割へ移す。
- Controllerから検証済みartifact一覧が渡された時、選択中役割のraw／補正後URLをStem previewへ再接続する。
- BSではBass／Drums／Other／Vocals／Guitar／Pianoを役割選択に表示し、Guitar／Pianoも既存共通波形部品へ個別のraw／補正後URLを渡す。同じ部品のA/B再生、外部プレイヤー、Finder表示を使用する。
- 見出し、詳細解析の説明、解析待ち文言は、現在の契約から4Stem／6Stemを表示する。
- 実行前の補正工程一覧も、HT固定のSession初期値を直接表示せず、検証済み選択モデル契約から生成する。実行開始後はSessionが保持するrun契約の実進捗へ切り替える。
- `StemModeWorkspaceModel.exportableArtifacts`を画面上部とアプリのコマンドメニューの共通入力にした。表示順は、補正済み純粋加算、再ミックス済み、マスタリング済み、補正済みDrums／Bass／Other／Vocals／Guitar／Piano。存在しないartifactとraw Stemは表示しない。

## 検証結果

- `swift test --filter 'StemModeWorkspaceModelTests|StemModeWorkspaceWordingTests|StemModeCorrectionSettingsViewTests|StemModeSettingsTests|StemModePresentationTextTests'`: 61 tests／5 suites成功。
- `swift test --filter 'StemModeWorkspace|StemWorkflowController|StemWorkflowSession|VelouraAppRuntime|StemModePresentationText'`: 88 tests／6 suites成功。
- `swift build`: 成功。
- BSのGuitar／Pianoが個別の検証済みraw／補正後URLをA/Bへ受け取り、HT契約では選択できないことをテストで確認した。
- 選択モデルをBSからHTへ変えても、既存BS結果は6役割を保持することをテストで確認した。
- 画面とコマンドメニューが同じ`exportActions`を読み、BSの補正済みGuitar／Pianoを含む検証済み書き出し対象だけを列挙することを確認した。
- Stem個別波形が共通波形部品へraw／補正後URLを渡し、その部品のFinder表示が同じURLを`NSWorkspace.shared.activateFileViewerSelecting`へ渡すことをコード契約テストで確認した。
- 実行前工程一覧の補足修正後、`swift test --filter 'StemModeWorkspace|StemWorkflowSession' --quiet`は70 tests／3 suites成功、`swift build`と`git diff --check`も成功した。
- `./script/build_and_run.sh --verify`で署名済みRelease bundleを再構築・起動し、HT選択時は`4Stem分離`と4役割、BS選択時は実行前から`6Stem分離`とBass／Drums／Other／Vocals／Guitar／Pianoを実画面で確認した。
- 6.8秒互換性音源を実画面から選択し、BS-RoFormer-SWで6Stem補正、純粋加算検証、再ミックス、最終マスタリングを完走した。補正、再ミックス、マスタリングの各画面進捗は100%・完了となり、最終版の実測表示は-21.2 LUFS／-9.2 dBTPだった。
- GuitarとPianoを画面で個別選択し、それぞれrawと補正後をA/B切替して実際に再生した。両役割とも分離直後波形と補正後波形、再生中対象が役割名・raw／補正後と一致した。
- 画面上部と`ファイル > 書き出し`の両方で、高品質WAV、配信・納品用WAV、CD用WAV、共有AACの各形式にGuitar／Pianoが表示された。高品質Guitarを選ぶと`corrected-guitar-export.wav`の保存パネルが開くことを確認し、確認用操作では保存をキャンセルした。実ファイル生成は同じproduction exporterを使う実モデル統合testでGuitar／Piano各4形式、計8ファイルを確認済み。
- 完了後に選択モデルだけHTDemucsへ変更しても、既存BS結果は6 Stem、`6Stem分離`工程、Guitar／Piano波形・成果物を維持した。選択モデルと結果run契約を実画面でも混同していない。

## 未確認事項

- Finder表示ボタンでFinder自体を開く外部画面操作は未実施。渡すURLとボタン有効化はコード契約testおよび実画面で確認済み。
- 実画面の保存パネルから利用者フォルダへ新しいファイルを書き込む操作は、不要な確認ファイルを残さないためキャンセルした。実ファイルの4形式書き出しは、画面と同じproduction exporterを使う実モデル統合testで確認済み。
