import Foundation

struct CompletionReportDocumentBuild: Sendable {
    let summary: [String]
    let comparisonRows: [CompletionReportComparisonRow]
    let comparisonNotes: [String]
    let sections: [CompletionReportSection]
    let charts: [CompletionReportChart]
    let masteredOffsetSeconds: Double?
}

enum CompletionReportDocumentService {
    private struct Alignment {
        let offsetSeconds: Double
        let correlation: Double
    }

    private struct BandChange {
        let label: String
        let range: String
        let deltaDB: Double
    }

    static func make(
        input: AudioMetricSnapshot,
        processed: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot,
        noiseReport: NoiseCheckReport,
        mode: CompletionReportMode,
        trackTitle: String?,
        processingSourceName: String?,
        inputFileInfo: AudioFileInfo?,
        processedFileInfo: AudioFileInfo?,
        masteredFileInfo: AudioFileInfo?
    ) -> CompletionReportDocumentBuild {
        let processedAlignment = alignment(
            reference: input.completionReportAnalysis,
            target: processed.completionReportAnalysis
        )
        let masteredAlignment = alignment(
            reference: input.completionReportAnalysis,
            target: mastered.completionReportAnalysis
        )
        let resolvedTitle = trackTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let inputSectionTitle = resolvedTitle.flatMap { $0.isEmpty ? nil : $0 }
            .map { "1. 原音「\($0)」の分析" }
            ?? "1. 原音の分析"

        return CompletionReportDocumentBuild(
            summary: summary(
                input: input,
                processed: processed,
                mastered: mastered,
                noiseReport: noiseReport,
                mode: mode,
                processedAlignment: processedAlignment
            ),
            comparisonRows: comparisonRows(
                input: input,
                processed: processed,
                mastered: mastered,
                inputFileInfo: inputFileInfo,
                processedFileInfo: processedFileInfo,
                masteredFileInfo: masteredFileInfo
            ),
            comparisonNotes: [alignmentSummary(
                processed: processedAlignment,
                mastered: masteredAlignment,
                middleTitle: mode.middleStageTitle
            )],
            sections: [
                inputSection(
                    title: inputSectionTitle,
                    input: input
                ),
                processedSection(
                    input: input,
                    processed: processed,
                    noiseReport: noiseReport,
                    mode: mode,
                    processingSourceName: processingSourceName,
                    alignment: processedAlignment
                ),
                masteringSection(
                    input: input,
                    processed: processed,
                    mastered: mastered
                ),
                overallSection(
                    input: input,
                    processed: processed,
                    mastered: mastered,
                    noiseReport: noiseReport,
                    mode: mode,
                    processedAlignment: processedAlignment
                )
            ],
            charts: charts(input: input, processed: processed, mastered: mastered, mode: mode),
            masteredOffsetSeconds: masteredAlignment?.offsetSeconds
        )
    }

    private static func summary(
        input: AudioMetricSnapshot,
        processed: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot,
        noiseReport: NoiseCheckReport,
        mode: CompletionReportMode,
        processedAlignment: Alignment?
    ) -> [String] {
        let middle = mode.middleStageTitle
        let low = bandChange(reference: input, target: mastered, lower: 20, upper: 150)
        let presence = bandChange(reference: input, target: mastered, lower: 2_000, upper: 10_000)
        let noiseDecreaseCount = noiseReport.rows.filter { ($0.correctionDeltaDB ?? 0) < -0.05 }.count
        let noiseIncreaseCount = noiseReport.rows.filter { ($0.correctionDeltaDB ?? 0) > 0.05 }.count
        let noiseItemCount = noiseReport.rows.count
        let alignmentText: String
        if let processedAlignment {
            alignmentText = "入力と\(middle)は、20 ms RMS包絡の時間差が\(milliseconds(processedAlignment.offsetSeconds))、相関が\(plain(processedAlignment.correlation, 3))です。"
        } else {
            alignmentText = "入力と\(middle)の時間差と包絡相関は未測定です。"
        }

        return [
            "今回のレポートは、入力・\(middle)・最終版を同じ測定方法で比較しています。\(alignmentText)",
            "入力から\(middle)では、Integrated Loudnessが\(signed(processed.integratedLoudnessLUFS - input.integratedLoudnessLUFS, 2, "LU"))、クレストファクターが\(signed(processed.crestFactorDB - input.crestFactorDB, 2, "dB"))変化しました。ノイズ\(noiseItemCount)項目では減少\(noiseDecreaseCount)項目、増加\(noiseIncreaseCount)項目です。",
            "入力から最終版の全体音量差を除いた帯域変化は、20〜150 Hzが\(optionalSigned(low, 2, "dB"))、2〜10 kHzが\(optionalSigned(presence, 2, "dB"))です。最終版のTrue Peakは\(format(mastered.truePeakDBFS, 2, "dBTP"))、クリップ検出数は\(mastered.completionReportAnalysis.clippedSampleCount)です。",
            "音楽的な好みは数値だけでは確定できません。本レポートでは、構造保持、帯域、ダイナミクス、ノイズ、ピーク、ステレオの測定結果を工程ごとに分けて示します。"
        ]
    }

    private static func comparisonRows(
        input: AudioMetricSnapshot,
        processed: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot,
        inputFileInfo: AudioFileInfo?,
        processedFileInfo: AudioFileInfo?,
        masteredFileInfo: AudioFileInfo?
    ) -> [CompletionReportComparisonRow] {
        var rows = [
            row("duration", "長さ", duration(input.duration), duration(processed.duration), duration(mastered.duration)),
            row("loudness", "Integrated Loudness", format(input.integratedLoudnessLUFS, 2, "LUFS"), format(processed.integratedLoudnessLUFS, 2, "LUFS"), format(mastered.integratedLoudnessLUFS, 2, "LUFS")),
            row("lra", "Loudness Range", optional(input.loudnessRangeLU, 2, "LU"), optional(processed.loudnessRangeLU, 2, "LU"), optional(mastered.loudnessRangeLU, 2, "LU")),
            row("true-peak", "True Peak", format(input.truePeakDBFS, 2, "dBTP"), format(processed.truePeakDBFS, 2, "dBTP"), format(mastered.truePeakDBFS, 2, "dBTP")),
            row("crest", "全体クレストファクター", format(input.crestFactorDB, 2, "dB"), format(processed.crestFactorDB, 2, "dB"), format(mastered.crestFactorDB, 2, "dB")),
            row("stereo-correlation", "ステレオ相関", plain(input.stereoCorrelation, 3), plain(processed.stereoCorrelation, 3), plain(mastered.stereoCorrelation, 3)),
            row("low-correlation", "低域150 Hz以下の相関", optional(input.completionReportAnalysis.lowBandStereoCorrelation, 3, ""), optional(processed.completionReportAnalysis.lowBandStereoCorrelation, 3, ""), optional(mastered.completionReportAnalysis.lowBandStereoCorrelation, 3, ""))
        ]
        if let inputFileInfo, let processedFileInfo, let masteredFileInfo {
            rows.insert(row("sample-rate", "サンプルレート", inputFileInfo.sampleRateText, processedFileInfo.sampleRateText, masteredFileInfo.sampleRateText), at: 1)
            rows.insert(row("channels", "チャンネル", inputFileInfo.channelText, processedFileInfo.channelText, masteredFileInfo.channelText), at: 2)
            rows.insert(row("encoding", "形式", inputFileInfo.encodingText, processedFileInfo.encodingText, masteredFileInfo.encodingText), at: 3)
        }
        return rows
    }

    private static func inputSection(
        title: String,
        input: AudioMetricSnapshot
    ) -> CompletionReportSection {
        let analysis = input.completionReportAnalysis
        let transitions = analysis.densityTransitionTimes.isEmpty
            ? "測定上、明確な密度転換点は特定できませんでした。"
            : "密度変化は\(analysis.densityTransitionTimes.map(time).joined(separator: "、"))付近で検出されました。"
        let tempo = analysis.estimatedTempoBPM.map { "推定テンポは\(plain($0, 1)) BPM" } ?? "テンポは判定困難"
        let key = analysis.estimatedKey.map { "推定調性は\($0)" } ?? "調性は判定困難"
        let strongest = strongestBand(input)
        let weakest = weakestBand(input)
        let dynamicSpan = dynamicsSpan(input)
        let negativeRatio = negativeCorrelationRatio(input)

        return CompletionReportSection(
            id: "input",
            title: title,
            subsections: [
                subsection("input-musical", "音楽的な性格", [
                    "\(tempo)、\(key)です。いずれも解析上の推定で、確定情報ではありません。",
                    transitions
                ]),
                subsection("input-dynamics", "音量とダイナミクス", [
                    "入力は\(format(input.integratedLoudnessLUFS, 2, "LUFS"))、True Peak \(format(input.truePeakDBFS, 2, "dBTP"))、Loudness Range \(optional(input.loudnessRangeLU, 2, "LU"))です。",
                    "クレストファクターは\(format(input.crestFactorDB, 2, "dB"))、短時間RMSの95％点と10％点の差は\(optional(dynamicSpan, 2, "dB"))、Peak-to-Loudness Ratioは\(format(peakToLoudnessRatio(input), 2, "dB"))です。"
                ]),
                subsection("input-frequency", "周波数バランス", [
                    "スペクトル重心は\(format(input.centroidHz, 0, "Hz"))です。",
                    "全体音量差を除いた帯域比では、最も高い帯域は\(strongest)、最も低い帯域は\(weakest)です。これは帯域構成の説明であり、良し悪しの判定ではありません。"
                ]),
                subsection("input-stereo", "ステレオと位相", [
                    "全体のステレオ相関は\(plain(input.stereoCorrelation, 3))、150 Hz以下は\(optional(analysis.lowBandStereoCorrelation, 3, ""))です。",
                    "左右波形相関は\(optional(analysis.leftRightWaveformCorrelation, 3, ""))です。全体のSide/Mid比は\(optional(analysis.sideMidRatioDB, 2, "dB"))、150 Hz以下は\(optional(analysis.lowBandSideMidRatioDB, 2, "dB"))です。負の相関区間は\(optionalPercent(negativeRatio))です。"
                ]),
                subsection("input-assessment", "原音の評価", [
                    "入力の特徴は、音量、ダイナミクス、周波数重心、ステレオ相関の実測値から上記の通り確認できます。ノイズ量や帯域の偏りは中間音源との比較で工程別に評価します。",
                    "制作意図や聴感上の好みは測定だけでは確定できないため、原音の音楽的な合否は断定しません。"
                ])
            ]
        )
    }

    private static func processedSection(
        input: AudioMetricSnapshot,
        processed: AudioMetricSnapshot,
        noiseReport: NoiseCheckReport,
        mode: CompletionReportMode,
        processingSourceName: String?,
        alignment: Alignment?
    ) -> CompletionReportSection {
        let middle = mode.middleStageTitle
        let sectionTitle = mode == .stem ? "2. 再ミックス音源の分析" : "2. 補正後音源の分析"
        let sourceName = processingSourceName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let issueTitle: String
        if mode == .stem {
            issueTitle = sourceName.flatMap { $0.isEmpty ? nil : $0 }
                .map { "\($0)由来の問題について" }
                ?? "分離モデル由来の問題について"
        } else {
            issueTitle = "補正による問題について"
        }
        let lowChanges = bandChangeText(reference: input, target: processed, ranges: [
            ("20〜60 Hz", 20, 60), ("60〜150 Hz", 60, 150), ("150〜300 Hz", 150, 300)
        ])
        let highChanges = bandChangeText(reference: input, target: processed, ranges: [
            ("2〜5 kHz", 2_000, 5_000), ("5〜10 kHz", 5_000, 10_000), ("10〜20 kHz", 10_000, 20_000)
        ])
        let lowTotalChange = bandChange(reference: input, target: processed, lower: 20, upper: 150)
        let presenceChange = bandChange(reference: input, target: processed, lower: 2_000, upper: 10_000)
        let crestChange = processed.crestFactorDB - input.crestFactorDB
        let noiseDecreaseCount = noiseReport.rows.filter { ($0.correctionDeltaDB ?? 0) < -0.05 }.count
        let noiseIncreaseCount = noiseReport.rows.filter { ($0.correctionDeltaDB ?? 0) > 0.05 }.count
        let noiseStableCount = max(noiseReport.rows.count - noiseDecreaseCount - noiseIncreaseCount, 0)
        let issueFacts = processingIssueFacts(input: input, processed: processed, alignment: alignment)

        return CompletionReportSection(
            id: "processed",
            title: sectionTitle,
            subsections: [
                subsection("processed-fidelity", "原音の再現性", [
                    alignment.map { "入力との20 ms RMS包絡の時間差は\(milliseconds($0.offsetSeconds))、相関は\(plain($0.correlation, 3))です。" }
                        ?? "入力との時間差と包絡相関は未測定です。",
                    "長さは\(format(input.duration, 2, "秒"))→\(format(processed.duration, 2, "秒"))、ステレオ相関は\(plain(input.stereoCorrelation, 3))→\(plain(processed.stereoCorrelation, 3))です。"
                ]),
                subsection("processed-transient", "トランジェントの変化", [
                    "Peakは\(format(input.peakDBFS, 2, "dBFS"))→\(format(processed.peakDBFS, 2, "dBFS"))、RMSは\(format(input.rmsDBFS, 2, "dBFS"))→\(format(processed.rmsDBFS, 2, "dBFS"))です。",
                    "クレストファクターは\(format(input.crestFactorDB, 2, "dB"))→\(format(processed.crestFactorDB, 2, "dB"))、差は\(signed(crestChange, 2, "dB"))です。",
                    crestInterpretation(crestChange, stageTitle: middle)
                ]),
                subsection("processed-low", "低域の変化", [
                    lowChanges,
                    "20〜150 Hz全体は、全体音量差を除くと\(optionalSigned(lowTotalChange, 2, "dB"))です。150 Hz以下の相関は\(optional(input.completionReportAnalysis.lowBandStereoCorrelation, 3, ""))→\(optional(processed.completionReportAnalysis.lowBandStereoCorrelation, 3, ""))、Side/Mid比は\(optional(input.completionReportAnalysis.lowBandSideMidRatioDB, 2, "dB"))→\(optional(processed.completionReportAnalysis.lowBandSideMidRatioDB, 2, "dB"))です。",
                    "低域の量、左右の同相性、中央成分に対する側面成分の比率を分けて表示しているため、低域量の増減だけを位相変化とは扱いません。"
                ]),
                subsection("processed-high", "中高域の変化", [
                    highChanges,
                    "2〜10 kHz全体は、全体音量差を除くと\(optionalSigned(presenceChange, 2, "dB"))です。スペクトル重心は\(format(input.centroidHz, 0, "Hz"))→\(format(processed.centroidHz, 0, "Hz"))です。",
                    "帯域差は全体音量差を除いているため、単純なゲイン変更ではなく、入力に対する帯域構成の移動量を示します。"
                ]),
                subsection(
                    "processed-noise",
                    "ノイズ除去・補正の評価",
                    noiseReport.rows.isEmpty
                        ? ["ノイズ測定は未測定です。"]
                        : [
                            "ノイズ\(noiseReport.rows.count)項目の工程別差です。",
                            "入力から\(middle)では、減少\(noiseDecreaseCount)項目、増加\(noiseIncreaseCount)項目、±0.05 dB以内\(noiseStableCount)項目です。ノイズ量の減少と楽音の保持は別の確認事項として扱います。"
                        ],
                    stageDeltaRows: noiseStageDeltaRows(noiseReport: noiseReport)
                ),
                subsection("processed-issues", issueTitle, issueFacts),
                subsection("processed-assessment", mode == .stem ? "再ミックスの評価" : "補正後音源の評価", [
                    "入力から\(middle)までのクレスト差は\(signed(crestChange, 2, "dB"))、20〜150 Hz差は\(optionalSigned(lowTotalChange, 2, "dB"))、2〜10 kHz差は\(optionalSigned(presenceChange, 2, "dB"))です。いずれも全体音量の上下と分けて比較しています。",
                    alignmentInterpretation(alignment, stageTitle: middle),
                    "測定値で確認できない分離アーティファクト、残響の質感、声や楽器の自然さは試聴しないと判断できません。"
                ])
            ]
        )
    }

    private static func masteringSection(
        input: AudioMetricSnapshot,
        processed: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot
    ) -> CompletionReportSection {
        let processedSpan = dynamicsSpan(processed)
        let masteredSpan = dynamicsSpan(mastered)
        let frequencyChanges = bandChangeText(reference: processed, target: mastered, ranges: [
            ("20〜60 Hz", 20, 60), ("60〜150 Hz", 60, 150), ("400 Hz〜2 kHz", 400, 2_000),
            ("2〜5 kHz", 2_000, 5_000), ("5〜10 kHz", 5_000, 10_000), ("10〜20 kHz", 10_000, 20_000)
        ])
        let highChanges = bandChangeText(reference: processed, target: mastered, ranges: [
            ("2〜5 kHz", 2_000, 5_000), ("5〜10 kHz", 5_000, 10_000), ("10〜20 kHz", 10_000, 20_000)
        ])
        let lowChanges = bandChangeText(reference: processed, target: mastered, ranges: [
            ("20〜60 Hz", 20, 60), ("60〜150 Hz", 60, 150)
        ])
        let loudnessChange = mastered.integratedLoudnessLUFS - processed.integratedLoudnessLUFS
        let truePeakChange = mastered.truePeakDBFS - processed.truePeakDBFS
        let crestChange = mastered.crestFactorDB - processed.crestFactorDB
        let spanChange = optionalDifference(masteredSpan, processedSpan)
        let lowTotalChange = bandChange(reference: processed, target: mastered, lower: 20, upper: 150)
        let presenceChange = bandChange(reference: processed, target: mastered, lower: 2_000, upper: 10_000)
        let sideMidChange = optionalDifference(
            mastered.completionReportAnalysis.sideMidRatioDB,
            processed.completionReportAnalysis.sideMidRatioDB
        )

        return CompletionReportSection(
            id: "mastering",
            title: "3. マスタリング音源の分析",
            subsections: [
                subsection("mastering-loudness", "ラウドネス処理", [
                    "Integrated Loudnessは\(format(processed.integratedLoudnessLUFS, 2, "LUFS"))→\(format(mastered.integratedLoudnessLUFS, 2, "LUFS"))、True Peakは\(format(processed.truePeakDBFS, 2, "dBTP"))→\(format(mastered.truePeakDBFS, 2, "dBTP"))です。",
                    "ラウドネス差は\(signed(loudnessChange, 2, "LU"))、True Peak差は\(signed(truePeakChange, 2, "dB"))、RMSは\(format(processed.rmsDBFS, 2, "dBFS"))→\(format(mastered.rmsDBFS, 2, "dBFS"))です。",
                    loudnessInterpretation(loudnessChange: loudnessChange, truePeakChange: truePeakChange)
                ]),
                subsection("mastering-dynamics", "ダイナミクス処理", [
                    "短時間RMSの95％点と10％点の差は\(optional(processedSpan, 2, "dB"))→\(optional(masteredSpan, 2, "dB"))です。",
                    "短時間RMS幅の差は\(optionalSigned(spanChange, 2, "dB"))、クレストファクター差は\(signed(crestChange, 2, "dB"))です。Peak-to-Loudness Ratioは\(format(peakToLoudnessRatio(processed), 2, "dB"))→\(format(peakToLoudnessRatio(mastered), 2, "dB"))です。",
                    dynamicsInterpretation(spanChange: spanChange, crestChange: crestChange)
                ]),
                subsection("mastering-frequency", "周波数バランス", [
                    frequencyChanges,
                    "20〜150 Hz全体は\(optionalSigned(lowTotalChange, 2, "dB"))、2〜10 kHz全体は\(optionalSigned(presenceChange, 2, "dB"))です。いずれもマスタリング前後の全体音量差を除いた値です。"
                ]),
                subsection("mastering-high", "高域処理の評価", [
                    highChanges,
                    "高域の良し悪しは増減量だけでは確定できません。刺さり、ヒス、煌びやかさ、空気感は別の性質として試聴確認が必要です。"
                ]),
                subsection("mastering-low", "低域保護の評価", [
                    lowChanges,
                    "150 Hz以下の相関は\(optional(processed.completionReportAnalysis.lowBandStereoCorrelation, 3, ""))→\(optional(mastered.completionReportAnalysis.lowBandStereoCorrelation, 3, ""))です。低域量と中央定位を分けて確認できます。"
                ]),
                subsection("mastering-stereo", "ステレオ処理", [
                    "全体のSide/Mid比は\(optional(processed.completionReportAnalysis.sideMidRatioDB, 2, "dB"))→\(optional(mastered.completionReportAnalysis.sideMidRatioDB, 2, "dB"))、左右相関は\(plain(processed.stereoCorrelation, 3))→\(plain(mastered.stereoCorrelation, 3))です。",
                    "Side/Mid比の差は\(optionalSigned(sideMidChange, 2, "dB"))です。負の相関区間は\(optionalPercent(negativeCorrelationRatio(processed)))→\(optionalPercent(negativeCorrelationRatio(mastered)))、150 Hz以下のSide/Mid比は\(optional(processed.completionReportAnalysis.lowBandSideMidRatioDB, 2, "dB"))→\(optional(mastered.completionReportAnalysis.lowBandSideMidRatioDB, 2, "dB"))です。",
                    "全体幅と低域幅を別々に示すことで、中高域側の広がりと低域の中央定位を混同せず確認できます。"
                ]),
                subsection("mastering-peaks", "クリッピングとピーク", [
                    "最終版のTrue Peakは\(format(mastered.truePeakDBFS, 2, "dBTP"))です。振幅1.0以上のサンプルは\(mastered.completionReportAnalysis.clippedSampleCount)、−0.9 dBFS以上のサンプルは\(mastered.completionReportAnalysis.nearPeakSampleCount)です。",
                    "数値が0の場合は、今回のサンプル走査では該当するピークを検出していません。"
                ])
            ]
        )
    }

    private static func overallSection(
        input: AudioMetricSnapshot,
        processed: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot,
        noiseReport: NoiseCheckReport,
        mode: CompletionReportMode,
        processedAlignment: Alignment?
    ) -> CompletionReportSection {
        let title = mode == .stem
            ? "ノイズ除去・補正・再ミックス・マスタリングの総合評価"
            : "ノイズ除去・補正・マスタリングの総合評価"
        let middleTitle = mode == .stem ? "4ステム分離と再ミックス" : "補正"
        let noiseDecreaseCount = noiseReport.rows.filter { ($0.correctionDeltaDB ?? 0) < -0.05 }.count
        let noiseIncreaseCount = noiseReport.rows.filter { ($0.correctionDeltaDB ?? 0) > 0.05 }.count
        let noiseItemCount = noiseReport.rows.count
        let processedStructure = processedAlignment.map {
            "20 ms RMS包絡の相関は\(plain($0.correlation, 3))、時間差は\(milliseconds($0.offsetSeconds))です。"
        } ?? "入力との包絡相関と時間差は未測定です。"

        return CompletionReportSection(
            id: "overall",
            title: title,
            subsections: [
                subsection("overall-noise", "ノイズ除去", [
                    "入力から\(mode.middleStageTitle)までのノイズ\(noiseItemCount)項目では、減少\(noiseDecreaseCount)項目、増加\(noiseIncreaseCount)項目です。各帯域の実測差は第2章に表示しています。",
                    "ノイズの増減と楽音の自然さは同一ではないため、ノイズ量だけで音質の合否は決めません。"
                ]),
                subsection("overall-middle", middleTitle, [
                    processedStructure,
                    "クレストファクターは\(format(input.crestFactorDB, 2, "dB"))→\(format(processed.crestFactorDB, 2, "dB"))、ステレオ相関は\(plain(input.stereoCorrelation, 3))→\(plain(processed.stereoCorrelation, 3))です。"
                ]),
                subsection("overall-mastering", "マスタリング", [
                    "Integrated Loudnessは\(format(processed.integratedLoudnessLUFS, 2, "LUFS"))→\(format(mastered.integratedLoudnessLUFS, 2, "LUFS"))、True Peakは\(format(processed.truePeakDBFS, 2, "dBTP"))→\(format(mastered.truePeakDBFS, 2, "dBTP"))です。",
                    "最終版のクリップ検出数は\(mastered.completionReportAnalysis.clippedSampleCount)です。帯域、ダイナミクス、ステレオの工程別変化は第3章に表示しています。"
                ]),
                subsection("overall-final", "最終評価", [
                    "入力、\(mode.middleStageTitle)、最終版の関係は、構造保持、ノイズ、周波数、ダイナミクス、ピーク、ステレオの各測定結果として確認できます。",
                    "技術的な安全性と音楽的な好みは分けて判断します。測定で確定できない質感、疲れやすさ、声や楽器の自然さについては、同じ音量での試聴が必要です。"
                ])
            ]
        )
    }

    private static func charts(
        input: AudioMetricSnapshot,
        processed: AudioMetricSnapshot,
        mastered: AudioMetricSnapshot,
        mode: CompletionReportMode
    ) -> [CompletionReportChart] {
        let stageTitles = ["入力", mode.middleStageTitle, "最終版"]
        let metrics = [input, processed, mastered]
        var result: [CompletionReportChart] = []

        let rmsSeries = zip(stageTitles, metrics).enumerated().map { index, value in
            CompletionReportChartSeries(
                id: "rms-\(index)",
                title: value.0,
                points: value.1.completionReportAnalysis.rms400MillisecondDB.enumerated().map {
                    CompletionReportChartPoint(
                        x: Double($0.offset) / max(value.1.completionReportAnalysis.rms400MillisecondRateHz, 1),
                        y: $0.element,
                        lowerY: nil
                    )
                }
            )
        }
        if rmsSeries.contains(where: { !$0.points.isEmpty }) {
            result.append(CompletionReportChart(
                id: "rms-400ms",
                title: "400 ms RMSによる音量推移比較",
                kind: .loudnessTimeline,
                horizontalAxisTitle: "時間（秒）",
                verticalAxisTitle: "RMS（dBFS）",
                series: rmsSeries
            ))
        }

        let spectrumSeries = zip(stageTitles, metrics).enumerated().map { index, value in
            CompletionReportChartSeries(
                id: "spectrum-\(index)",
                title: value.0,
                points: downsampleSpectrum(value.1.averageSpectrum).map {
                    CompletionReportChartPoint(x: $0.frequencyHz, y: $0.levelDB, lowerY: nil)
                }
            )
        }
        if spectrumSeries.contains(where: { !$0.points.isEmpty }) {
            result.append(CompletionReportChart(
                id: "spectrum-comparison",
                title: "入力・\(mode.middleStageTitle)・最終版の周波数比較",
                kind: .spectrumComparison,
                horizontalAxisTitle: "周波数（Hz）",
                verticalAxisTitle: "レベル（dB）",
                series: spectrumSeries
            ))
        }

        let processedDelta = spectrumDelta(reference: input, target: processed)
        let masteredDelta = spectrumDelta(reference: input, target: mastered)
        if !processedDelta.isEmpty || !masteredDelta.isEmpty {
            result.append(CompletionReportChart(
                id: "spectrum-delta",
                title: "入力を基準にした周波数差分",
                kind: .spectrumDelta,
                horizontalAxisTitle: "周波数（Hz）",
                verticalAxisTitle: "入力との差（dB）",
                series: [
                    CompletionReportChartSeries(id: "delta-processed", title: mode.middleStageTitle, points: processedDelta),
                    CompletionReportChartSeries(id: "delta-mastered", title: "最終版", points: masteredDelta)
                ]
            ))
        }

        let waveformSeries = zip(stageTitles, metrics).enumerated().map { index, value in
            CompletionReportChartSeries(
                id: "waveform-\(index)",
                title: value.0,
                points: value.1.completionReportAnalysis.displayWaveform.map {
                    CompletionReportChartPoint(x: $0.time, y: Double($0.maximum), lowerY: Double($0.minimum))
                }
            )
        }
        if waveformSeries.contains(where: { !$0.points.isEmpty }) {
            result.append(CompletionReportChart(
                id: "waveform-comparison",
                title: "入力・\(mode.middleStageTitle)・最終版の波形比較",
                kind: .waveformComparison,
                horizontalAxisTitle: "時間（秒）",
                verticalAxisTitle: "振幅",
                series: waveformSeries
            ))
        }
        return result
    }

    private static func noiseStageDeltaRows(
        noiseReport: NoiseCheckReport
    ) -> [CompletionReportStageDeltaRow] {
        noiseReport.rows.map { row in
            CompletionReportStageDeltaRow(
                id: row.id,
                title: row.label,
                inputToProcessedValue: optionalSigned(row.correctionDeltaDB, 2, "dB"),
                processedToMasteredValue: optionalSigned(row.masteringDeltaDB, 2, "dB")
            )
        }
    }

    private static func processingIssueFacts(
        input: AudioMetricSnapshot,
        processed: AudioMetricSnapshot,
        alignment: Alignment?
    ) -> [String] {
        var facts: [String] = []
        if let alignment {
            facts.append("時間差は\(milliseconds(alignment.offsetSeconds))、20 ms RMS包絡相関は\(plain(alignment.correlation, 3))です。")
        } else {
            facts.append("時間差と20 ms RMS包絡相関は未測定です。")
        }
        facts.append("低域相関は\(optional(input.completionReportAnalysis.lowBandStereoCorrelation, 3, ""))→\(optional(processed.completionReportAnalysis.lowBandStereoCorrelation, 3, ""))、負の相関区間は\(optionalPercent(negativeCorrelationRatio(input)))→\(optionalPercent(negativeCorrelationRatio(processed)))です。")
        facts.append("クリップ検出数は入力\(input.completionReportAnalysis.clippedSampleCount)、処理後\(processed.completionReportAnalysis.clippedSampleCount)です。測定値だけでは水中感、金属的な揺れ、残響分離などは判定できません。")
        return facts
    }

    private static func alignmentSummary(
        processed: Alignment?,
        mastered: Alignment?,
        middleTitle: String
    ) -> String {
        guard let processed, let mastered else {
            return "3音源の開始位置は未測定です。"
        }
        return "入力を基準にした開始位置の差は、\(middleTitle) \(milliseconds(processed.offsetSeconds))、最終版 \(milliseconds(mastered.offsetSeconds))です。"
    }

    private static func alignment(
        reference: CompletionReportAudioAnalysis,
        target: CompletionReportAudioAnalysis
    ) -> Alignment? {
        guard reference.waveformEnvelopeRateHz > 0,
              abs(reference.waveformEnvelopeRateHz - target.waveformEnvelopeRateHz) < 0.001,
              reference.waveformEnvelope.count > 20,
              target.waveformEnvelope.count > 20 else { return nil }
        let rate = reference.waveformEnvelopeRateHz
        let maxLag = min(Int(rate * 0.5), min(reference.waveformEnvelope.count, target.waveformEnvelope.count) / 4)
        var bestLag: Int?
        var bestCorrelation: Double?
        for lag in (-maxLag)...maxLag {
            guard let value = correlation(
                reference.waveformEnvelope,
                target.waveformEnvelope,
                lag: lag
            ) else { continue }
            let shouldReplace: Bool
            if let currentCorrelation = bestCorrelation, let currentLag = bestLag {
                shouldReplace = value > currentCorrelation + 1e-12
                    || (abs(value - currentCorrelation) <= 1e-12 && abs(lag) < abs(currentLag))
            } else {
                shouldReplace = true
            }
            if shouldReplace {
                bestCorrelation = value
                bestLag = lag
            }
        }
        guard let bestLag, let bestCorrelation, bestCorrelation.isFinite else { return nil }
        return Alignment(offsetSeconds: Double(bestLag) / rate, correlation: bestCorrelation)
    }

    private static func correlation(_ reference: [Float], _ target: [Float], lag: Int) -> Double? {
        let referenceStart = max(0, -lag)
        let targetStart = max(0, lag)
        let count = min(reference.count - referenceStart, target.count - targetStart)
        guard count > 1 else { return nil }
        var referenceMean = 0.0
        var targetMean = 0.0
        for offset in 0..<count {
            referenceMean += Double(reference[referenceStart + offset])
            targetMean += Double(target[targetStart + offset])
        }
        referenceMean /= Double(count)
        targetMean /= Double(count)
        var cross = 0.0
        var referenceEnergy = 0.0
        var targetEnergy = 0.0
        for offset in 0..<count {
            let left = Double(reference[referenceStart + offset]) - referenceMean
            let right = Double(target[targetStart + offset]) - targetMean
            cross += left * right
            referenceEnergy += left * left
            targetEnergy += right * right
        }
        guard referenceEnergy > 1e-12, targetEnergy > 1e-12 else { return nil }
        return cross / sqrt(referenceEnergy * targetEnergy)
    }

    private static func crestInterpretation(_ delta: Double, stageTitle: String) -> String {
        if delta > 0.05 {
            return "\(stageTitle)ではRMSに対するピークの比率が増え、瞬間成分が相対的に大きい構造へ変化しています。"
        }
        if delta < -0.05 {
            return "\(stageTitle)ではRMSに対するピークの比率が減り、瞬間成分と平均成分の差が小さい構造へ変化しています。"
        }
        return "\(stageTitle)ではRMSに対するピークの比率が±0.05 dB以内で維持されています。"
    }

    private static func alignmentInterpretation(_ alignment: Alignment?, stageTitle: String) -> String {
        guard let alignment else {
            return "入力と\(stageTitle)の時間整合と包絡の一致度は未測定です。"
        }
        if abs(alignment.offsetSeconds) > 0.05 {
            return "入力と\(stageTitle)には50 msを超える開始位置差があります。包絡相関は\(plain(alignment.correlation, 3))です。"
        }
        return "入力と\(stageTitle)の開始位置差は50 ms以内です。包絡相関は\(plain(alignment.correlation, 3))で、曲全体の音量推移の一致度を示します。"
    }

    private static func loudnessInterpretation(
        loudnessChange: Double,
        truePeakChange: Double
    ) -> String {
        if loudnessChange > 0.05, truePeakChange < -0.05 {
            return "Integrated Loudnessは上がり、True Peakは下がっています。単純な一括ゲインではなく、ピーク制御を含む変化です。"
        }
        if loudnessChange < -0.05, truePeakChange > 0.05 {
            return "Integrated Loudnessは下がり、True Peakは上がっています。平均的な音量と最大ピークが異なる方向へ変化しています。"
        }
        return "Integrated LoudnessとTrue Peakの増減方向を分けて表示し、平均的な音量変化とピーク変化を同一視しない評価にしています。"
    }

    private static func dynamicsInterpretation(
        spanChange: Double?,
        crestChange: Double
    ) -> String {
        let spanText: String
        if let spanChange {
            if spanChange > 0.05 {
                spanText = "短時間の音量幅は広がっています"
            } else if spanChange < -0.05 {
                spanText = "短時間の音量幅は狭まっています"
            } else {
                spanText = "短時間の音量幅は±0.05 dB以内です"
            }
        } else {
            spanText = "短時間の音量幅は未測定です"
        }
        let crestText: String
        if crestChange > 0.05 {
            crestText = "ピークと平均成分の差は広がっています"
        } else if crestChange < -0.05 {
            crestText = "ピークと平均成分の差は狭まっています"
        } else {
            crestText = "ピークと平均成分の差は±0.05 dB以内です"
        }
        return "\(spanText)。一方、\(crestText)。この2つを分けて、曲中の音量差と瞬間ピークの保持を確認します。"
    }

    private static func optionalDifference(_ target: Double?, _ reference: Double?) -> Double? {
        guard let target, let reference else { return nil }
        return target - reference
    }

    private static func dynamicsSpan(_ metrics: AudioMetricSnapshot) -> Double? {
        let values = metrics.dynamics.map(\.rmsDBFS).filter(\.isFinite).sorted()
        guard values.count >= 2 else { return nil }
        return percentile(values, 0.95) - percentile(values, 0.10)
    }

    private static func percentile(_ sorted: [Double], _ probability: Double) -> Double {
        let position = max(0, min(1, probability)) * Double(sorted.count - 1)
        let lower = Int(floor(position))
        let upper = Int(ceil(position))
        guard lower != upper else { return sorted[lower] }
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    private static func peakToLoudnessRatio(_ metrics: AudioMetricSnapshot) -> Double {
        metrics.truePeakDBFS - metrics.integratedLoudnessLUFS
    }

    private static func negativeCorrelationRatio(_ metrics: AudioMetricSnapshot) -> Double? {
        guard metrics.stereoCorrelationTimelineStatus == .available,
              !metrics.stereoCorrelationTimeline.isEmpty else { return nil }
        let negative = metrics.stereoCorrelationTimeline.filter { $0.value < 0 }.count
        return Double(negative) / Double(metrics.stereoCorrelationTimeline.count)
    }

    private static func strongestBand(_ metrics: AudioMetricSnapshot) -> String {
        guard let band = normalizedBands(metrics).max(by: { $0.level < $1.level }) else { return "未測定" }
        return "\(band.label)（\(band.range)）"
    }

    private static func weakestBand(_ metrics: AudioMetricSnapshot) -> String {
        guard let band = normalizedBands(metrics).min(by: { $0.level < $1.level }) else { return "未測定" }
        return "\(band.label)（\(band.range)）"
    }

    private static func normalizedBands(_ metrics: AudioMetricSnapshot) -> [(label: String, range: String, level: Double)] {
        metrics.bandEnergies.map { ($0.label, $0.rangeDescription, $0.levelDB - metrics.rmsDBFS) }
    }

    private static func bandChangeText(
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot,
        ranges: [(String, Double, Double)]
    ) -> String {
        ranges.map { label, lower, upper in
            "\(label)：\(optionalSigned(bandChange(reference: reference, target: target, lower: lower, upper: upper), 2, "dB"))"
        }.joined(separator: "／")
    }

    private static func bandChange(
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot,
        lower: Double,
        upper: Double
    ) -> Double? {
        guard let source = spectrumBandLevel(reference.averageSpectrum, lower: lower, upper: upper),
              let destination = spectrumBandLevel(target.averageSpectrum, lower: lower, upper: upper) else { return nil }
        return (destination - target.rmsDBFS) - (source - reference.rmsDBFS)
    }

    private static func spectrumBandLevel(
        _ spectrum: [SpectrumMetric],
        lower: Double,
        upper: Double
    ) -> Double? {
        let points = spectrum.filter { $0.frequencyHz >= lower && $0.frequencyHz < upper && $0.levelDB.isFinite }
        guard !points.isEmpty else { return nil }
        let meanPower = points.reduce(0.0) { $0 + pow(10, $1.levelDB / 10) } / Double(points.count)
        return 10 * log10(max(meanPower, 1e-20))
    }

    private static func downsampleSpectrum(_ spectrum: [SpectrumMetric]) -> [SpectrumMetric] {
        let valid = spectrum.filter { $0.frequencyHz >= 20 && $0.frequencyHz <= 24_000 && $0.levelDB.isFinite }
        guard valid.count > 384 else { return valid }
        let strideSize = max(1, valid.count / 384)
        return Swift.stride(from: 0, to: valid.count, by: strideSize).map { valid[$0] }
    }

    private static func spectrumDelta(
        reference: AudioMetricSnapshot,
        target: AudioMetricSnapshot
    ) -> [CompletionReportChartPoint] {
        let sourceSpectrum = reference.averageSpectrum
        let targetSpectrum = target.averageSpectrum
        guard !sourceSpectrum.isEmpty, !targetSpectrum.isEmpty else { return [] }
        let strideSize = max(1, sourceSpectrum.count / 384)
        let gainDifference = target.rmsDBFS - reference.rmsDBFS
        return Swift.stride(from: 0, to: sourceSpectrum.count, by: strideSize).compactMap { index in
            let source = sourceSpectrum[index]
            guard source.frequencyHz >= 20,
                  source.frequencyHz <= 24_000,
                  source.levelDB.isFinite,
                  let destinationLevel = interpolatedSpectrumLevel(
                    targetSpectrum,
                    frequencyHz: source.frequencyHz
                  ) else { return nil }
            return CompletionReportChartPoint(
                x: source.frequencyHz,
                y: destinationLevel - source.levelDB - gainDifference,
                lowerY: nil
            )
        }
    }

    private static func interpolatedSpectrumLevel(
        _ spectrum: [SpectrumMetric],
        frequencyHz: Double
    ) -> Double? {
        guard let first = spectrum.first,
              let last = spectrum.last,
              frequencyHz >= first.frequencyHz,
              frequencyHz <= last.frequencyHz else { return nil }
        var lower = 0
        var upper = spectrum.count - 1
        while lower + 1 < upper {
            let middle = (lower + upper) / 2
            if spectrum[middle].frequencyHz < frequencyHz {
                lower = middle
            } else {
                upper = middle
            }
        }
        let left = spectrum[lower]
        let right = spectrum[upper]
        guard left.levelDB.isFinite, right.levelDB.isFinite else { return nil }
        let width = right.frequencyHz - left.frequencyHz
        guard width > 0 else { return left.levelDB }
        let fraction = (frequencyHz - left.frequencyHz) / width
        return left.levelDB + (right.levelDB - left.levelDB) * fraction
    }

    private static func subsection(
        _ id: String,
        _ title: String,
        _ paragraphs: [String],
        stageDeltaRows: [CompletionReportStageDeltaRow] = []
    ) -> CompletionReportSubsection {
        CompletionReportSubsection(
            id: id,
            title: title,
            paragraphs: paragraphs,
            stageDeltaRows: stageDeltaRows
        )
    }

    private static func row(
        _ id: String,
        _ title: String,
        _ input: String,
        _ processed: String,
        _ mastered: String
    ) -> CompletionReportComparisonRow {
        CompletionReportComparisonRow(
            id: id,
            title: title,
            inputValue: input,
            processedValue: processed,
            masteredValue: mastered
        )
    }

    private static func duration(_ value: Double) -> String { "\(plain(value, 2)) 秒" }
    private static func time(_ value: Double) -> String { String(format: "%d:%02d", Int(value) / 60, Int(value) % 60) }
    private static func milliseconds(_ seconds: Double) -> String { signed(seconds * 1_000, 0, "ms") }

    private static func optionalPercent(_ value: Double?) -> String {
        guard let value else { return "未測定" }
        return "\(plain(value * 100, 1))%"
    }

    private static func optional(_ value: Double?, _ decimals: Int, _ unit: String) -> String {
        guard let value else { return "未測定" }
        return format(value, decimals, unit)
    }

    private static func optionalSigned(_ value: Double?, _ decimals: Int, _ unit: String) -> String {
        guard let value else { return "未測定" }
        return signed(value, decimals, unit)
    }

    private static func format(_ value: Double, _ decimals: Int, _ unit: String) -> String {
        let number = plain(value, decimals)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private static func signed(_ value: Double, _ decimals: Int, _ unit: String) -> String {
        let number = String(format: value >= 0 ? "+%.*f" : "%.*f", decimals, value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    private static func plain(_ value: Double, _ decimals: Int) -> String {
        String(format: "%.*f", decimals, value)
    }
}
