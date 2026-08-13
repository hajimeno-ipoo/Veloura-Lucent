# BS-RoFormer-SW 6Stem再ミックス実装・検証記録

## 対象

承認済み計画の手順8「自動・手動再ミックスと共有伴奏マスキング」のみを対象とする。マスタリング報告、Session全状態、書き出し、実画面、実モデル全工程は後続手順で扱う。

## 変更前

- 再ミックス対象とFloat32加算順は `vocals / drums / bass / other` の4本で固定されていた。
- 自動gain、pan、reverb send、dry加算、共有reverb送信はGuitar／Pianoを読まなかった。
- Vocals衝突回避はOtherだけを判定・処理した。
- Workflowの再ミックス開始条件と詳細ログは4役割を前提にした。

## 変更後

- `StemRemixService` は実行時の `StemModelRunContract` を必須入力にし、HTは4本、BSは `bass / drums / other / vocals / guitar / piano` の6本を契約順で処理する。
- 全有効Stemが独立した自動gain、pan、reverb sendと手動上書きを持つ。
- Drums→Bassは既存処理と順序を維持する。
- HTのVocals→Otherは従来と同じ1本を対象にする。
- BSのVocals側は `other + guitar + piano` の伴奏バスを無係数加算し、そこから1つの時間エンベロープを作る。同じエンベロープを伴奏3本の対象帯域へ適用し、各Stemを別々に判定しない。
- 全有効Stemのsendを1つへ加算し、共有reverb returnを1本だけdry合計へ戻す。
- 契約外、欠落、重複、構造不一致、非有限値は再ミックスを失敗させ、4本だけで進むfallbackを作らない。
- Workflow失敗時は補正済み全Stemと純粋加算を保持し、未完成の再ミックスと最終版を削除する。

## 検証済みの事実

- HT Vocals→Otherの既存fixtureは、変更前に固定したFloat32指紋 `8742540710301265695` と一致した。
- HT中立設定は従来4本の純粋加算とサンプル一致した。
- BS中立設定はrun契約順の6本純粋加算とサンプル一致した。
- BS自動計画は6役割すべてのgain、pan、reverb根拠と設定を生成した。
- GuitarとPianoは異なる手動gain、pan、reverb sendを保持できた。
- 伴奏3本を分けた入力と、同じ3本をOtherへ事前加算した検証入力は、共有マスキング後のdry出力の最大差が `1e-5` 未満だった。
- Vocalsが無音のBS入力では、共有マスキングを有効にしても6本純粋加算から変化しなかった。
- Guitarだけ、Pianoだけを送った場合も、各送信から有限値の共有reverb returnが生成された。
- BS Workflowは6本の補正済みStemを再ミックスへ読み、Guitar／Pianoの自動根拠と「伴奏（その他／ギター／ピアノ）」をログへ記録した。
- 再ミックス直前にGuitarが欠落する異常では処理が失敗し、6本の補正済みStemと純粋加算は残り、再ミックスと最終版は残らなかった。

## 未確認

- BS実モデルの実音源による再ミックス聴感、ピーク、処理時間、最大RSS。
- 実画面でのGuitar／Pianoノブ操作とA/B試聴。
- 6Stem再ミックスから最終マスタリング、完了報告、個別書き出しまでの接続。

これらを手順8の成功へ混ぜず、後続の承認済み手順で確認する。
