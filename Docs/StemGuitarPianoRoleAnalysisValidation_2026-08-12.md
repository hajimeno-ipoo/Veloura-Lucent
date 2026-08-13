# Guitar／Piano専用解析候補の実Stem検証（2026-08-12）

## 結論

BS-RoFormer-SWの実Guitar／Piano Stemに対して、Other用解析を通さず、活動、アタック、調波成分、非調波性、帯域バランス、周波数別余韻、二段減衰、ステレオを個別に測定した。

用意した劣化12判定はGuitar／Pianoとも全件で変化を識別し、完全無音だけでなく原音を`0.0001`倍した微小残留も非活動と判定した。無加工複製は全数値が元音源と一致した。この結果から、専用解析に必要な候補特徴は実装へ進められる。Other解析の流用や代用品は不要である。

ただし、これは製品解析を実装する前の候補検証である。今回の判定値をそのまま製品の音質合否閾値にはしない。

## 何を根拠に役割を分けたか

| 対象 | 専用解析候補 | 採用根拠 | 製品内での役割 |
|---|---|---|---|
| 共通の活動判定 | フレームRMS、絶対下限`-70 dBFS` | EssentiaのEffectiveDurationは、信号包絡が指定閾値を超える区間を有効時間として扱う | 非活動Stemでは正規化特徴を作らず、誤判定を防ぐ |
| Guitarのアタック | complex-domain onset energy、attack crest | Essentiaのcomplex onsetは振幅スペクトルと位相からオンセット関数を計算する。ギターの撥弦位置・力は初期スペクトルと時間減衰へ影響する | ピッキング／アタックの潰れを検出する |
| Guitarの音色本体 | harmonic energy ratio、inharmonicity | HarmonicPeaksは基本周波数に対応する調波ピークを求め、Inharmonicityは最寄りの整数倍からのずれを測る | 調波・音色本体の欠落を検出する |
| Guitarの高域 | 6〜18 kHzの比率p90、centroid、roll-off | Centroidはスペクトルの重心、RollOffは指定割合のエネルギーを含む周波数であり、撥弦のスペクトル変化にもcentroidが使われる | 高域ディテール低下を補助判定する |
| Guitarの減衰 | 検出オンセットに対応した低／中／高域tail比 | 撥弦後は高次倍音が時間とともに異なる速度で減衰する | 音の伸びを一括RMSではなく帯域別に確認する |
| Pianoのアタック | complex-domain onset energy、attack crest | 打弦開始の変化を、Guitarと同じ定義のオンセット関数で測る。ただし判定結果はPiano役割へ別に保持する | ハンマーアタックの潰れを検出する |
| Pianoの部分音 | harmonic energy ratio、inharmonicity | Piano弦では部分音の非調波性が確認されており、調波量だけではなく整数倍からのずれも区別する | 部分音と非調波性を別々に確認する |
| Pianoの余韻 | 低／中／高域tail比、前半・後半の減衰傾斜差 | Piano弦の二段減衰は物理モデルと実測で扱われる | 周波数別余韻と二段減衰の崩れを検出する |
| Pianoの広帯域バランス | 低／中／高域比、centroid、roll-off | スペクトル重心とエネルギー包含周波数を組み合わせる | 鍵盤音域を一つの高域値へ単純化せず確認する |
| 共通のステレオ | side比、L/R相関 | EssentiaのFalseStereoDetectorもL/RのPearson相関を利用する | モノラル化や空間情報の消失を検出する |

参照した一次資料・公式仕様:

- [Essentia OnsetDetection](https://essentia.upf.edu/reference/streaming_OnsetDetection.html)
- [Essentia HarmonicPeaks](https://essentia.upf.edu/reference/streaming_HarmonicPeaks.html)
- [Essentia Inharmonicity](https://essentia.upf.edu/reference/std_Inharmonicity.html)
- [Essentia Centroid](https://essentia.upf.edu/reference/std_Centroid.html)
- [Essentia RollOff](https://essentia.upf.edu/reference/std_RollOff.html)
- [Essentia EffectiveDuration](https://essentia.upf.edu/reference/std_EffectiveDuration.html)
- [Essentia FalseStereoDetector](https://essentia.upf.edu/reference/std_FalseStereoDetector.html)
- [The influence of plucking point and plucking force on the timbre of a guitar](https://acoustics.org/pressroom/httpdocs/160th/carral.html)
- [弦楽器の発音機構](https://www.jstage.jst.go.jp/article/jasj/33/6/33_KJ00001454408/_article/-char/ja/)
- [The acoustics of the piano: Double decay revisited](https://doi.org/10.1121/10.0009012)

## 検証条件

- モデル: 現在アプリが使用するBS-RoFormer-SW実モデル
- 音声形式: `44,100 Hz`、stereo、Float32 WAV
- Guitar入力: `嘆き-2.wav`の116秒地点から16秒を分離した`guitar.wav`
- Piano入力: `星屑のシンパシー.wav`の26秒地点から16秒を分離した`piano.wav`
- 実Stemレベル:
  - Guitar: mean `-31.0 dB`、max `-15.3 dB`
  - Piano: mean `-22.8 dB`、max `-5.3 dB`
- 解析: `4,096` sample frame、`1,024` sample hop、左右チャンネル別スペクトルを合算
- 比較対象: 無加工複製、完全無音、微小残留、アタック低下、調波低下、余韻ゲート、高域低下、中域バランス低下、モノラル化
- 検証スクリプト: `script/analyze_stem_role_candidates.py`
- A/B WAVとJSON: `.stem-model-cache/bs-roformer-sw/role-analysis/`配下。検証用キャッシュでありGit管理外

## 途中で不採用にした簡易方式

1. 左右をmono合算してからスペクトル解析する方式
   - L/Rの位相差で成分が相殺され、Stem自体の調波・高域量を正しく残せなかった。
   - 左右を別々に変換してからパワーを合算する方式へ変更した。
2. フレーム単位のgainを直接切り替えるアタック低下
   - フレーム境界の段差が新しいオンセットとして検出され、Pianoの劣化判定を乱した。
   - STFT上で立ち上がり成分だけを連続的に抑える方式へ変更した。
3. 単なる静音閾値による余韻ゲート
   - 曲中の次の発音まで巻き込み、対応するアタックと余韻を比較できなかった。
   - 検出した各オンセットに揃え、次のオンセットを越えない範囲で帯域別tailを比較する方式へ変更した。

これらは製品処理ではなく候補検証の生成方法である。不採用方式は製品へ入れていない。

## 実測結果

変化率は元Stemに対する劣化Stemの差である。tailはdB差、二段減衰は傾斜差の絶対値である。

| 判定 | Guitar | Piano | 合格条件 | 結果 |
|---|---:|---:|---:|---|
| 完全無音の活動率 | 0.000000 | 0.000000 | 0.001以下 | 両方合格 |
| 微小残留の活動率 | 0.000000 | 0.000000 | 0.001以下 | 両方合格 |
| アタック低下 | 40.78% | 50.32% | 15%以上 | 両方合格 |
| 調波量低下 | 22.85% | 17.75% | 15%以上 | 両方合格 |
| 非調波性増加 | 73.39% | 23.99% | 15%以上 | 両方合格 |
| 低域tail低下 | 0.76 dB | 1.34 dB | 0.5 dB以上 | 両方合格 |
| 中域tail低下 | 1.62 dB | 0.94 dB | 0.5 dB以上 | 両方合格 |
| 高域tail低下 | 2.93 dB | 5.72 dB | 0.5 dB以上 | 両方合格 |
| 二段減衰傾斜の変化 | 15.87 dB/s | 5.44 dB/s | 1.0 dB/s以上 | 両方合格 |
| 高域量低下 | 75.61% | 90.09% | 60%以上 | 両方合格 |
| 中域バランス低下 | 85.65% | 75.43% | 30%以上 | 両方合格 |
| stereo side低下 | 100.00% | 100.00% | 95%以上 | 両方合格 |

- Guitar: 12判定中12件合格、無加工対照の数値不一致0件
- Piano: 12判定中12件合格、無加工対照の数値不一致0件
- 実互換性音源のGuitar残留も活動率`0.0`と判定した。
- 同じ互換性音源のPianoは活動率`0.7310`であり、無音対照には使用していない。

Pianoの6〜18 kHzの絶対量はclean時点で小さい。このため、Pianoでは高域量を主判定にせず、広帯域バランス、部分音・非調波性、周波数別余韻を主にし、高域量は補助情報に限定する。Guitarでは高域ディテールを独立候補として維持する。

## この結果で確定したこと

- Guitar／Pianoの専用候補は、実Stemと劣化模擬で別々に変化を識別できる。
- 活動前判定により、完全無音と非ゼロ微小残留の双方を解析対象外にできる。
- Other用の空間・残響中心の解析をコピーする必要はない。
- 次の判断工程で、代用品なしに製品用Guitar／Piano解析を設計できる。

## 手順4の採否判定

手順3の個別判定を、計画で必須とした役割へ次のように再対応させた。単なる総件数ではなく、各役割に必要な判定がすべて存在し、すべて合格していることをJSONから機械確認した。

| Stem | 必須役割 | 対応する検査 | 判定 |
|---|---|---|---|
| Guitar | 活動 | 完全無音、非ゼロ微小残留 | 採用 |
| Guitar | ピッキング／アタック | complex-domain onset低下 | 採用 |
| Guitar | 調波・音色本体 | harmonic energy低下、inharmonicity増加 | 採用 |
| Guitar | 高域ディテール | 6〜18 kHz比率p90低下 | 採用 |
| Guitar | 減衰 | 対応onset後の低／中／高域tail低下 | 採用 |
| Guitar | ステレオ | side比低下 | 採用 |
| Piano | 活動 | 完全無音、非ゼロ微小残留 | 採用 |
| Piano | ハンマーアタック | complex-domain onset低下 | 採用 |
| Piano | 部分音と非調波性 | harmonic energy低下、inharmonicity増加 | 採用 |
| Piano | 周波数別余韻 | 対応onset後の低／中／高域tail低下 | 採用 |
| Piano | 二段減衰 | 前半・後半の減衰傾斜差 | 採用 |
| Piano | 広帯域バランス | 中域比率低下。centroid／roll-off／帯域比も結果へ保持 | 採用 |
| Piano | ステレオ | side比低下 | 採用 |

無加工対照はGuitar／Pianoとも全数値一致し、検証スクリプトに`StemRole.other`、Other解析関数、Otherへのfallback参照は存在しない。

以上から、計画に定めた「識別できない特徴」は確認されなかった。停止条件は発動せず、Other流用や代用品を追加せずに手順5のモデル別run契約へ進んだ。

## 手順7前半の製品Swift実装と照合

`StemDedicatedInstrumentAnalysisService.swift`へ、候補検証と同じ定義を製品用として実装した。

- 共通: `4,096` sample frame、`1,024` sample hop、絶対活動下限`-70 dBFS`、左右別spectral power
- Guitar: complex-domain onset、attack crest、harmonic energy、inharmonicity、6〜18 kHz量、centroid、roll-off、低／中／高域tail、side比、L/R相関
- Piano: complex-domain onset、attack crest、partial energy、inharmonicity、低／中／高域tail、二段減衰、低／中域バランス、centroid、roll-off、side比、L/R相関
- Pianoの6〜18 kHz量は結果へ保持するが、専用feature／guard成分には使用しない
- 非活動frameのguard入力は全成分`0`とし、正規化特徴量を作らない

`StemRoleAnalysisService`はGuitar／Pianoだけをこの専用serviceへ明示dispatchする。既存の`featureValues`、`protectionValues`、`featureDefinitions`でGuitar／Pianoが呼ばれた場合は停止し、Other用解析へ進む経路はない。

製品Swiftと保存済みA/Bの照合条件:

- `guitar-degradations-approved`と`piano-degradations-approved`の各10 WAV、合計20ファイル
- clean、無加工identity、attack reduction、harmonic reduction、tail gate、high reduction、band balance、mono、silence、near silence
- 製品と同じ`AudioFileService`で48 kHz化してから解析
- `VELOURA_RUN_STEM_ROLE_ANALYSIS_FIXTURES=1 swift test --filter dedicatedRealABMetricsMatchApprovedReference`

結果は1 test成功。無加工identityはGuitar／Pianoとも製品解析結果がcleanと全項目一致し、silence／near silenceは活動frame `0`だった。attack、harmonic body、inharmonicity、低／中／高域tail、Guitar高域、Piano中域balance、stereo sideの劣化方向も製品時系列値で識別できた。

保存済みJSONは44.1 kHz解析値であり、製品は48 kHz信号を正本にする。この条件差を切り分けるため、Piano cleanとharmonic reductionをPython候補式へ48 kHzで再入力した。Swiftとの差はharmonic reductionのharmonic energy ratioで約`0.000021`、cleanの高域tailで約`0.0008 dB`となり、製品式と候補式が同じ48 kHz条件で一致することを確認した。44.1 kHz JSONとの許容幅はこのsample-rate条件差の照合にだけ使い、製品guardの音質閾値には使用していない。

Guitarは12個、Pianoは14個の役割別featureを持つ。guard用の時系列成分はGuitar 7個、Piano 11個であり、各roleの成分集合を過不足なく生成する。既存4役割は従来の`4,096`／`2,048` profileを維持する。

## 手順7後半のWorkflow接続

`StemWorkflowService.processCorrection`は、固定4役割ではなく、そのrun開始時に確定した`StemModelRunContract.validationRoles`を次の全区間へ渡す。

- raw Stemの48 kHz変換と役割別解析
- `StemCorrectionService`による補正と専用guard
- `corrected-guitar.wav`／`corrected-piano.wav`を含む役割別保存・再読込
- 補正失敗時の該当Stemだけのraw復帰と理由記録
- 明確な極性反転を検出したStemだけのraw復帰
- run契約の`pureSumOrder`による補正済み純粋加算
- Stem数を含む補正進捗とログ

BS用Workflowテストでは、6役割が契約順で補正器へ届き、補正済み成果物6本と6本純粋加算が保存されることを確認した。Guitar補正を強制失敗させた場合はGuitarだけがraw復帰し、残る5本の補正結果と6Stem結果を維持した。本番`StemCorrectionService`を接続したテストでは、Guitar／Pianoがそれぞれ専用活動結果・専用metrics・役割別feature・全9工程のguard記録を持ち、Other featureを含まないことを確認した。HTは同じ経路を4役割のまま通る。

## 未確認事項・制限

- 実曲2箇所の16秒Stemによる必要十分な候補検証であり、全ジャンルを証明する大規模評価ではない。
- 劣化模擬の合格閾値は「候補特徴が変化を識別できるか」の検証値であり、製品の音質合否値ではない。
- 製品Swiftの専用解析・活動判定・guard入力profileと、モデル別run契約による6Stem補正・Stem単位raw復帰・補正済み純粋加算まで実装済み。
- 画面、書き出し、6Stem再ミックスは後続手順であり、この工程では変更していない。
