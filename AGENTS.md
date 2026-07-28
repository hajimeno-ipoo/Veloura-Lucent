# Veloura Lucent 固有ルール

共通の理解確認、承認境界、調査、実装、検証、報告形式は、グローバルの `AGENTS.md` に従う。

## 設計範囲と過剰実装の防止

- 新機能は、既存機能の実コード、状態管理、保存、キャンセル、UI、テストを確認し、承認された要件に必要な差分だけを追加する。
- 「一般的な設計」「堅牢性」「将来対応」を理由に、未承認のrun、checkpoint、schema、resume、履歴管理、互換shim、候補生成、候補比較、別の状態管理を追加しない。
- 既存機能にない仕組みが必要な場合は、既存処理で代用できないコード上の理由、追加しない場合に成立しない要件、影響範囲、より小さい代替案を示し、承認前に実装しない。
- Stem Modeに技術的または音響的に必要な分離、Stem別解析、役割別guard、再ミックス検証は、通常モードに存在しないことだけを理由に削除しない。
- 新しい型、Service、永続化ファイルを追加する前に、現在の要件で使用する呼び出し元、保持するデータ、必要な保持期間を確認する。
- 旧仕様との互換性や将来利用だけを目的とするコードは、承認された互換要件がない限り追加しない。
- 既存実装より複雑な構造を採用する場合は、単純な構造では要件を満たせない根拠を示して承認を受ける。

## 音質判断

- 音は耳と制作意図で作り、測定値は事故防止に使う。測定値の改善自体を音質改善の目的にしない。
- 自動処理は、原音、参照音源、ジャンル、ユーザーの仕上げ意図に対して自然に聞こえる音を目標にする。
- LUFS、True Peak、ノイズ値、スペクトル量は判断材料とし、目標値へ機械的に合わせない。
- クリップ、True Peak上限超過、NaN、異常値、書き出し破損、明確な破綻ノイズは防ぐ。ただし、安全ガードの追加や解除だけを音質改善と扱わない。
- ノイズ除去では不要なノイズだけを減らし、息感、倍音、空気感、煌びやかさを一緒に削らない。
- 高域は一括で扱わず、ヒス、サ行、シマー、煌びやかさ、空気感、息感、倍音、超高域を区別する。特に8〜16kHzは測定値だけで削らない。
- `hiss`、`shimmer`、`sibilance`、`mud` は、測定値が高いだけで無条件に下げない。
- 音楽成分を戻す場合は、ノイズ再発の可能性と、同じ帯域を重ねて削る既存処理の有無を確認する。副作用を避けるために効果のない修正へ弱めない。
- 合否は数値だけで決めず、原音、補正後、最終版、参照音源のA/B試聴と、必要に応じたエンコード後確認で判断する。
- 規格や公式資料は測定方法と配信事故防止に使い、音楽的な良し悪しを決める絶対基準にしない。

## 音質変更前の報告

- 対象の音、発生条件、対象帯域、変更する処理、期待する聴こえ方、副作用の可能性を具体的に示す。
- 「寄せる」「見直す」「守る」「強い」「弱い」だけで説明せず、何をどの条件でどう変えるかを記載する。

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `$graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Treat only `EXTRACTED` relationships as directly confirmed by Graphify. Verify every `INFERRED` and `AMBIGUOUS` relationship against the current source code before reporting it as fact.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
