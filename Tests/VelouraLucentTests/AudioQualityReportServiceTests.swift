import Testing
@testable import VelouraLucent

struct AudioQualityReportServiceTests {
    @Test
    func normalMetricsReturnNoItems() throws {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.0,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )
        let corrected = makeSnapshot(
            integratedLoudnessLUFS: -18.3,
            truePeakDBFS: -0.8,
            stereoWidth: 0.86,
            crestFactorDB: 9.2,
            hf12Ratio: 0.13,
            hf16Ratio: 0.06,
            hf18Ratio: 0.03
        )
        let mastered = makeSnapshot(
            integratedLoudnessLUFS: -16.5,
            truePeakDBFS: -0.5,
            stereoWidth: 0.92,
            crestFactorDB: 8.5,
            hf12Ratio: 0.16,
            hf16Ratio: 0.08,
            hf18Ratio: 0.04
        )

        let report = try #require(AudioQualityReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered
        ))

        #expect(report.items.isEmpty)
        #expect(report.severity == .info)
    }

    @Test
    func riskyChangesReturnJapaneseWarnings() throws {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.0,
            stereoWidth: 0.80,
            crestFactorDB: 12.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.01
        )
        let corrected = makeSnapshot(
            integratedLoudnessLUFS: -19.4,
            truePeakDBFS: -0.8,
            stereoWidth: 1.05,
            crestFactorDB: 8.5,
            hf12Ratio: 0.13,
            hf16Ratio: 0.05,
            hf18Ratio: 0.02
        )
        let mastered = makeSnapshot(
            integratedLoudnessLUFS: -13.8,
            truePeakDBFS: -0.1,
            stereoWidth: 1.35,
            crestFactorDB: 5.0,
            hf12Ratio: 0.30,
            hf16Ratio: 0.16,
            hf18Ratio: 0.09
        )

        let report = try #require(AudioQualityReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered
        ))

        #expect(report.severity == .warning)
        #expect(report.items.contains { $0.title == "補正後は音量を作らないため音量が下がっています" && $0.severity == .info })
        #expect(report.items.contains { $0.title == "マスタリング後のピークが高すぎます" })
        #expect(report.items.contains { $0.title == "マスタリング後の18kHz以上が増えています" })
        #expect(report.items.contains { $0.title == "補正後のステレオ幅が大きく変わっています" })
        #expect(report.items.contains { $0.title == "マスタリング後の音の起伏が小さくなっています" })
        #expect(report.items.contains { $0.title == "最終版の音量感が大きく上がっています" })
    }

    @Test
    func inputOnlyReturnsNil() {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.0,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )

        let report = AudioQualityReportService.makeReport(
            input: input,
            corrected: nil,
            mastered: nil
        )

        #expect(report == nil)
    }

    @Test
    func correctedOnlyReturnsNilUntilMasteringFinishes() {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.0,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )
        let corrected = makeSnapshot(
            integratedLoudnessLUFS: -18.3,
            truePeakDBFS: -0.8,
            stereoWidth: 0.86,
            crestFactorDB: 9.2,
            hf12Ratio: 0.13,
            hf16Ratio: 0.06,
            hf18Ratio: 0.03
        )

        let report = AudioQualityReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: nil
        )

        #expect(report == nil)
    }

    @Test
    func correctedLoudnessDropIsInformationalUntilFinalStaysLow() throws {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.2,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )
        let corrected = makeSnapshot(
            integratedLoudnessLUFS: -20.0,
            truePeakDBFS: -1.5,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )
        let mastered = makeSnapshot(
            integratedLoudnessLUFS: -18.1,
            truePeakDBFS: -0.8,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )

        let report = try #require(AudioQualityReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered
        ))

        #expect(report.items.count == 1)
        #expect(report.items.first?.severity == .info)
    }

    @Test
    func finalLoudnessDropReturnsCaution() throws {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.2,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )
        let corrected = makeSnapshot(
            integratedLoudnessLUFS: -20.0,
            truePeakDBFS: -1.5,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )
        let mastered = makeSnapshot(
            integratedLoudnessLUFS: -20.0,
            truePeakDBFS: -0.8,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02
        )

        let report = try #require(AudioQualityReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered
        ))

        #expect(report.items.contains { $0.title == "最終版の音量感が低めです" && $0.severity == .caution })
        #expect(report.severity == .caution)
    }

    @Test
    func measuredBandDeltasReportDarkerAndMuddierChanges() throws {
        let input = makeSnapshot(
            integratedLoudnessLUFS: -18.0,
            truePeakDBFS: -1.2,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02,
            bands: [
                "sparkle": -34,
                "air": -40,
                "ultraAir": -50,
                "mud": -28
            ]
        )
        let corrected = makeSnapshot(
            integratedLoudnessLUFS: -18.5,
            truePeakDBFS: -1.3,
            stereoWidth: 0.80,
            crestFactorDB: 10.0,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02,
            bands: [
                "sparkle": -37,
                "air": -43,
                "ultraAir": -53,
                "mud": -25
            ]
        )
        let mastered = makeSnapshot(
            integratedLoudnessLUFS: -16.5,
            truePeakDBFS: -0.8,
            stereoWidth: 0.82,
            crestFactorDB: 9.8,
            hf12Ratio: 0.10,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02,
            bands: [
                "sparkle": -38,
                "air": -44,
                "ultraAir": -54,
                "mud": -24
            ]
        )

        let report = try #require(AudioQualityReportService.makeReport(
            input: input,
            corrected: corrected,
            mastered: mastered
        ))

        #expect(report.items.contains { $0.title == "補正後の煌びやかさが下がっています" })
        #expect(report.items.contains { $0.title == "補正後の空気感が下がっています" })
        #expect(report.items.contains { $0.title == "補正後の超高域が下がっています" })
        #expect(report.items.contains { $0.title == "補正後のこもりが増えています" })
        #expect(report.items.contains { $0.detail.contains("8kHz〜12kHz が 3.0 dB") })
        #expect(report.items.contains { $0.detail.contains("16kHz〜20kHz が 3.0 dB") })
    }

    private func makeSnapshot(
        integratedLoudnessLUFS: Double,
        truePeakDBFS: Double,
        stereoWidth: Double,
        crestFactorDB: Double,
        hf12Ratio: Double,
        hf16Ratio: Double,
        hf18Ratio: Double,
        bands: [String: Double] = [:]
    ) -> AudioMetricSnapshot {
        let defaultBands: [(id: String, label: String, range: String, level: Double)] = [
            ("rumble", "低域ノイズ", "20-150Hz", -42),
            ("warmth", "太さ", "150-300Hz", -30),
            ("mud", "こもり", "300Hz-1kHz", -28),
            ("core", "声の芯", "1-4kHz", -24),
            ("presence", "刺さり", "4-8kHz", -35),
            ("sparkle", "煌びやかさ", "8-12kHz", -38),
            ("air", "空気感", "12-16kHz", -44),
            ("ultraAir", "超高域", "16-20kHz", -50)
        ]

        return AudioMetricSnapshot(
            peakDBFS: truePeakDBFS - 0.2,
            rmsDBFS: truePeakDBFS - crestFactorDB,
            crestFactorDB: crestFactorDB,
            loudnessRangeLU: 3.0,
            integratedLoudnessLUFS: integratedLoudnessLUFS,
            truePeakDBFS: truePeakDBFS,
            stereoWidth: stereoWidth,
            stereoCorrelation: 0.8,
            harshnessScore: 0.2,
            centroidHz: 2_500,
            hf12Ratio: hf12Ratio,
            hf16Ratio: hf16Ratio,
            hf18Ratio: hf18Ratio,
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
}
