import Foundation
import Testing
@testable import VelouraLucent

struct CompletionReportServiceTests {
    @Test
    func reportRequiresFinalMetricsAndNoiseMeasurements() {
        let input = makeMetrics(loudness: -18, truePeak: -3)
        let corrected = makeMetrics(loudness: -19, truePeak: -4)

        let report = CompletionReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: nil,
            inputNoise: makeNoise(hiss: -80, shimmer: -78),
            correctedNoise: makeNoise(hiss: -84, shimmer: -82),
            masteredNoise: makeNoise(hiss: -83, shimmer: -81),
            correctionSettings: DenoiseStrength.balanced.settings,
            masteringSettings: MasteringProfile.youtubeSpotify.settings
        )

        #expect(report == nil)
    }

    @Test
    func reportSummarizesLoudnessPeakNoiseAndHighBands() throws {
        let input = makeMetrics(
            loudness: -18,
            truePeak: -5,
            bands: ["sparkle": -42, "air": -46, "ultraAir": -51]
        )
        let corrected = makeMetrics(
            loudness: -19,
            truePeak: -6,
            bands: ["sparkle": -43, "air": -47, "ultraAir": -52]
        )
        let mastered = makeMetrics(
            loudness: -14.2,
            truePeak: -1.1,
            bands: ["sparkle": -42.5, "air": -47.2, "ultraAir": -53.8]
        )

        let report = try #require(CompletionReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered,
            inputNoise: makeNoise(hiss: -80, shimmer: -78),
            correctedNoise: makeNoise(hiss: -85, shimmer: -83),
            masteredNoise: makeNoise(hiss: -84, shimmer: -81),
            correctionSettings: DenoiseStrength.balanced.settings,
            masteringSettings: MasteringProfile.youtubeSpotify.settings
        ))

        #expect(report.loudnessRows.contains { $0.id == "loudness" && $0.value == "-14.2 LUFS" })
        #expect(report.loudnessRows.contains { $0.id == "truePeak" && $0.detail.contains("余裕 +0.10 dB") })
        #expect(report.loudnessRows.contains { $0.id == "loudnessChange" && $0.value == "入力差 +3.8 LU" })
        #expect(report.noiseRows.contains { $0.id == "noise-hiss" && $0.title == "ヒス・シュワシュワ" })
        #expect(report.highFrequencyRows.contains { $0.id == "high-air" && $0.detail.contains("入力差 -1.20 dB") })
        #expect(report.highFrequencyRows.contains { $0.id == "high-ultraAir" && $0.severity == .caution })
        #expect(report.highFrequencyRows.contains { $0.id == "high-generatedUltraHigh" })
        #expect(report.lowFrequencyRows.count == 2)
        #expect(report.lowFrequencyRows.contains {
            $0.id == "low-low" && $0.detail.contains("入力→補正後 +0.00 dB")
        })
        #expect(report.reminder.contains("入力・中間段階・最終版を同じ音量で聴き比べて"))
        #expect(report.comparisonRows.first { $0.id == "loudness" }?.inputValue == "-18.00 LUFS")
        #expect(report.comparisonRows.first { $0.id == "loudness" }?.processedValue == "-19.00 LUFS")
        #expect(report.comparisonRows.first { $0.id == "loudness" }?.masteredValue == "-14.20 LUFS")
        #expect(report.sections.map(\.title) == [
            "1. 原音の分析",
            "2. 補正後音源の分析",
            "3. マスタリング音源の分析",
            "ノイズ除去・補正・マスタリングの総合評価"
        ])
        #expect(report.sections[0].subsections.map(\.title) == [
            "音楽的な性格",
            "音量とダイナミクス",
            "周波数バランス",
            "ステレオと位相",
            "原音の評価"
        ])
        #expect(report.sections[1].subsections.map(\.title) == [
            "原音の再現性",
            "トランジェントの変化",
            "低域の変化",
            "中高域の変化",
            "ノイズ除去・補正の評価",
            "補正による問題について",
            "補正後音源の評価"
        ])
        let noiseSubsection = try #require(
            report.sections[1].subsections.first { $0.id == "processed-noise" }
        )
        #expect(noiseSubsection.stageDeltaRows.count == 7)
        #expect(noiseSubsection.paragraphs.allSatisfy { !$0.contains("／") })
        #expect(noiseSubsection.stageDeltaRows.first { $0.id == "hiss" } == CompletionReportStageDeltaRow(
            id: "hiss",
            title: "ヒス・シュワシュワ",
            inputToProcessedValue: "-5.00 dB",
            processedToMasteredValue: "+1.00 dB"
        ))
        #expect(report.sections[2].subsections.map(\.title) == [
            "ラウドネス処理",
            "ダイナミクス処理",
            "周波数バランス",
            "高域処理の評価",
            "低域保護の評価",
            "ステレオ処理",
            "クリッピングとピーク"
        ])
        #expect(report.sections[3].subsections.map(\.title) == [
            "ノイズ除去",
            "補正",
            "マスタリング",
            "最終評価"
        ])
    }

    @Test
    func truePeakOverCeilingIsWarning() throws {
        let report = try #require(CompletionReportService.makeReport(
            input: makeMetrics(loudness: -18, truePeak: -4),
            corrected: makeMetrics(loudness: -18, truePeak: -4),
            mastered: makeMetrics(loudness: -14, truePeak: -0.4),
            inputNoise: makeNoise(hiss: -80, shimmer: -78),
            correctedNoise: makeNoise(hiss: -84, shimmer: -82),
            masteredNoise: makeNoise(hiss: -83, shimmer: -81),
            correctionSettings: DenoiseStrength.balanced.settings,
            masteringSettings: MasteringProfile.youtubeSpotify.settings
        ))

        #expect(report.loudnessRows.first { $0.id == "truePeak" }?.severity == .warning)
        #expect(report.severity == .warning)
        #expect(report.safetyRows.first?.id == "peak-over")
    }

    @Test
    func transientGeneratedUltraHighIncreaseUsesSameStageSeverityAsQualityWarning() throws {
        let report = try #require(CompletionReportService.makeReport(
            input: makeMetrics(
                loudness: -18,
                truePeak: -4,
                bands: ["generatedUltraHigh": -60]
            ),
            corrected: makeMetrics(
                loudness: -18,
                truePeak: -4,
                bands: ["generatedUltraHigh": -56]
            ),
            mastered: makeMetrics(
                loudness: -14,
                truePeak: -1,
                bands: ["generatedUltraHigh": -60]
            ),
            inputNoise: makeNoise(hiss: -80, shimmer: -78),
            correctedNoise: makeNoise(hiss: -84, shimmer: -82),
            masteredNoise: makeNoise(hiss: -83, shimmer: -81),
            correctionSettings: DenoiseStrength.balanced.settings,
            masteringSettings: MasteringProfile.youtubeSpotify.settings
        ))

        #expect(report.highFrequencyRows.first { $0.id == "high-generatedUltraHigh" }?.severity == .warning)
    }

    @Test
    func lowBalanceChangeDoesNotBecomeAnOverallSafetyWarning() throws {
        let report = try #require(CompletionReportService.makeReport(
            input: makeMetrics(
                loudness: -14,
                truePeak: -5,
                masteringBands: ["low": -36, "lowMid": -36]
            ),
            corrected: makeMetrics(
                loudness: -14,
                truePeak: -5,
                masteringBands: ["low": -32.9, "lowMid": -36]
            ),
            mastered: makeMetrics(
                loudness: -14,
                truePeak: -5,
                masteringBands: ["low": -36, "lowMid": -36]
            ),
            inputNoise: makeNoise(hiss: -80, shimmer: -78),
            correctedNoise: makeNoise(hiss: -80, shimmer: -78),
            masteredNoise: makeNoise(hiss: -80, shimmer: -78),
            correctionSettings: DenoiseStrength.balanced.settings,
            masteringSettings: MasteringProfile.youtubeSpotify.settings
        ))

        #expect(report.lowFrequencyRows.first { $0.id == "low-low" }?.severity == .warning)
        #expect(report.severity == .normal)
        #expect(report.safetyRows.isEmpty)
    }

    @Test
    func reportIncludesFourAnalysisChartsForStandardMode() throws {
        let sampleRate = 1_000.0
        let mono: [Float] = (0..<10_000).map { index in
            Float(sin(2 * Double.pi * 80 * Double(index) / sampleRate) * 0.4)
        }
        let spectrum = [
            SpectrumMetric(id: "20", frequencyHz: 20, levelDB: -50),
            SpectrumMetric(id: "100", frequencyHz: 100, levelDB: -30),
            SpectrumMetric(id: "1000", frequencyHz: 1_000, levelDB: -36),
            SpectrumMetric(id: "10000", frequencyHz: 10_000, levelDB: -48),
            SpectrumMetric(id: "24000", frequencyHz: 24_000, levelDB: -60)
        ]
        let analysis = CompletionReportAudioAnalysisService.analyze(
            signal: AudioSignal(channels: [mono, mono], sampleRate: sampleRate),
            mono: mono,
            averageSpectrum: spectrum
        )
        let report = try #require(CompletionReportService.makeReport(
            input: makeMetrics(loudness: -16, truePeak: -4, spectrum: spectrum, completionAnalysis: analysis),
            corrected: makeMetrics(loudness: -16, truePeak: -3, spectrum: spectrum, completionAnalysis: analysis),
            mastered: makeMetrics(loudness: -14, truePeak: -1.5, spectrum: spectrum, completionAnalysis: analysis),
            inputNoise: makeNoise(hiss: -80, shimmer: -78),
            correctedNoise: makeNoise(hiss: -84, shimmer: -82),
            masteredNoise: makeNoise(hiss: -83, shimmer: -81),
            correctionSettings: DenoiseStrength.balanced.settings,
            masteringSettings: MasteringProfile.youtubeSpotify.settings
        ))

        #expect(report.charts.map(\.title) == [
            "400 ms RMSによる音量推移比較",
            "入力・補正後・最終版の周波数比較",
            "入力を基準にした周波数差分",
            "入力・補正後・最終版の波形比較"
        ])
    }

    @Test
    func flatEnvelopeDoesNotCreateFalseTimeOffsetWarning() throws {
        let analysis = makeCompletionAnalysis(
            envelope: Array(repeating: 0, count: 100)
        )
        let report = try #require(CompletionReportService.makeReport(
            input: makeMetrics(loudness: -18, truePeak: -4, completionAnalysis: analysis),
            corrected: makeMetrics(loudness: -18, truePeak: -4, completionAnalysis: analysis),
            mastered: makeMetrics(loudness: -14, truePeak: -1.5, completionAnalysis: analysis),
            inputNoise: makeNoise(hiss: -80, shimmer: -78),
            correctedNoise: makeNoise(hiss: -84, shimmer: -82),
            masteredNoise: makeNoise(hiss: -83, shimmer: -81),
            correctionSettings: DenoiseStrength.balanced.settings,
            masteringSettings: MasteringProfile.youtubeSpotify.settings
        ))

        #expect(!report.safetyRows.contains { $0.id == "time-offset" })
        #expect(report.comparisonNotes == ["3音源の開始位置は未測定です。"])
    }

    @Test
    func alignmentTextMatchesTwentyMillisecondEnvelopeCalculation() throws {
        let envelope: [Float] = (0..<100).map { $0.isMultiple(of: 2) ? 0.2 : 0.8 }
        let analysis = makeCompletionAnalysis(envelope: envelope)
        let report = try #require(CompletionReportService.makeReport(
            input: makeMetrics(loudness: -18, truePeak: -4, completionAnalysis: analysis),
            corrected: makeMetrics(loudness: -18, truePeak: -4, completionAnalysis: analysis),
            mastered: makeMetrics(loudness: -14, truePeak: -1.5, completionAnalysis: analysis),
            inputNoise: makeNoise(hiss: -80, shimmer: -78),
            correctedNoise: makeNoise(hiss: -84, shimmer: -82),
            masteredNoise: makeNoise(hiss: -83, shimmer: -81),
            correctionSettings: DenoiseStrength.balanced.settings,
            masteringSettings: MasteringProfile.youtubeSpotify.settings
        ))
        let reportText = report.summary
            + report.comparisonNotes
            + report.sections.flatMap(\.subsections).flatMap(\.paragraphs)

        #expect(reportText.contains { $0.contains("20 ms RMS包絡") })
        #expect(reportText.allSatisfy { !$0.contains("400 ms RMS包絡") })
        #expect(!report.safetyRows.contains { $0.id == "time-offset" })
    }

    private func makeCompletionAnalysis(
        envelope: [Float]
    ) -> CompletionReportAudioAnalysis {
        CompletionReportAudioAnalysis(
            estimatedTempoBPM: nil,
            tempoConfidence: 0,
            estimatedKey: nil,
            keyConfidence: 0,
            densityTransitionTimes: [],
            lowBandStereoCorrelation: nil,
            sideMidRatioDB: nil,
            lowBandSideMidRatioDB: nil,
            leftRightWaveformCorrelation: nil,
            clippedSampleCount: 0,
            nearPeakSampleCount: 0,
            rms400MillisecondDB: [],
            rms400MillisecondRateHz: 2.5,
            displayWaveform: [],
            waveformEnvelope: envelope,
            waveformEnvelopeRateHz: 50
        )
    }

    private func makeMetrics(
        loudness: Double,
        truePeak: Double,
        bands: [String: Double] = [:],
        masteringBands: [String: Double] = [:],
        spectrum: [SpectrumMetric] = [],
        completionAnalysis: CompletionReportAudioAnalysis = .unavailable
    ) -> AudioMetricSnapshot {
        let defaultBands: [(id: String, label: String, range: String, level: Double)] = [
            ("sparkle", "煌びやかさ", "8-12kHz", -42),
            ("air", "空気感", "12-16kHz", -46),
            ("ultraAir", "超高域", "16-20kHz", -51),
            ("generatedUltraHigh", "生成超高域", "21-24kHz", -60),
            ("mud", "こもり", "300Hz-1kHz", -30)
        ]

        return AudioMetricSnapshot(
            duration: 1,
            peakDBFS: truePeak - 0.2,
            rmsDBFS: -26,
            crestFactorDB: 8,
            loudnessRangeLU: 3,
            integratedLoudnessLUFS: loudness,
            truePeakDBFS: truePeak,
            stereoWidth: 0.8,
            stereoCorrelation: 0.8,
            stereoCorrelationTimeline: [],
            stereoCorrelationTimelineStatus: .unavailable,
            harshnessScore: 0.2,
            centroidHz: 2_500,
            hf12Ratio: 0.08,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02,
            bandEnergies: defaultBands.map { band in
                BandEnergyMetric(
                    id: band.id,
                    label: band.label,
                    rangeDescription: band.range,
                    levelDB: bands[band.id] ?? band.level
                )
            },
            masteringBandEnergies: AudioBandCatalog.masteringBands.map { band in
                BandEnergyMetric(
                    id: band.id,
                    label: band.label,
                    rangeDescription: band.rangeDescription,
                    levelDB: masteringBands[band.id] ?? -36
                )
            },
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: spectrum,
            completionReportAnalysis: completionAnalysis
        )
    }

    private func makeNoise(hiss: Double, shimmer: Double) -> NoiseMeasurementSnapshot {
        NoiseMeasurementSnapshot(values: [
            NoiseMeasurementValue(
                id: "hiss",
                label: "ヒス・シュワシュワ",
                comparableLevelDB: hiss,
                measuredLevelDB: hiss,
                unitLabel: "dBFS",
                measurementDescription: "静かな区間の8kHz以上の床"
            ),
            NoiseMeasurementValue(
                id: "shimmer",
                label: "高域のチラつき",
                comparableLevelDB: shimmer,
                measuredLevelDB: shimmer,
                unitLabel: "dBFS",
                measurementDescription: "10〜16kHzの短い揺れ"
            )
        ])
    }
}
