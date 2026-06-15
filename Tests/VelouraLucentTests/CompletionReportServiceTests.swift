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
        #expect(report.reminder == "数値は確認材料です。最終判断は試聴で行ってください。")
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
    }

    private func makeMetrics(
        loudness: Double,
        truePeak: Double,
        bands: [String: Double] = [:]
    ) -> AudioMetricSnapshot {
        let defaultBands: [(id: String, label: String, range: String, level: Double)] = [
            ("sparkle", "煌びやかさ", "8-12kHz", -42),
            ("air", "空気感", "12-16kHz", -46),
            ("ultraAir", "超高域", "16-20kHz", -51),
            ("mud", "こもり", "300Hz-1kHz", -30)
        ]

        return AudioMetricSnapshot(
            duration: 1,
            peakDBFS: truePeak - 0.2,
            rmsDBFS: loudness - 8,
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
            masteringBandEnergies: [],
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: []
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
