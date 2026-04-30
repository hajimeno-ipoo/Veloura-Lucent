import Testing
@testable import VelouraLucent

struct NoiseReturnReportServiceTests {
    @Test
    func reportDetectsMasteringReturnAfterCorrectionReduction() throws {
        let corrected = snapshot(levels: [-34, -34, -34, -34])
        let mastered = snapshot(levels: [-32, -32, -32, -32])
        let denoise = DenoiseEffectReport(shimmerFlickerChangeDB: -4, hf12ChangeDB: -4, hf16ChangeDB: -4, hf18ChangeDB: -4)

        let report = try #require(NoiseReturnReportService.makeReport(denoiseEffect: denoise, corrected: corrected, mastered: mastered))
        let row = try #require(report.rows.first { $0.id == "high10to16" })

        #expect(row.denoiseDeltaDB == -4)
        #expect(row.masteringDeltaDB == 2)
        #expect(row.returnRatePercent == 50)
        #expect(row.severity == .caution)
        #expect(row.masteredDeltaFromInputDB == -2)
        #expect(report.primaryRow == row)
        #expect(report.severity == .caution)
    }

    @Test
    func reportStaysOkWhenMasteringDoesNotReturnHighBand() throws {
        let corrected = snapshot(levels: [-34, -34, -34, -34])
        let mastered = snapshot(levels: [-34.5, -34.5, -34.5, -34.5])
        let denoise = DenoiseEffectReport(shimmerFlickerChangeDB: -4, hf12ChangeDB: -4, hf16ChangeDB: -4, hf18ChangeDB: -4)

        let report = try #require(NoiseReturnReportService.makeReport(denoiseEffect: denoise, corrected: corrected, mastered: mastered))

        #expect(report.rows.allSatisfy { $0.masteringDeltaDB <= 0 })
        #expect(report.severity == .ok)
    }

    @Test
    func reportUsesDenoiseReductionEvenWhenCorrectionWholeStageIncreasesHighBand() throws {
        let corrected = snapshot(levels: [-29, -29, -29, -29])
        let mastered = snapshot(levels: [-28.5, -28.5, -28.5, -28.5])
        let denoise = DenoiseEffectReport(shimmerFlickerChangeDB: -0.5, hf12ChangeDB: -0.6, hf16ChangeDB: -0.6, hf18ChangeDB: -0.6)

        let report = try #require(NoiseReturnReportService.makeReport(denoiseEffect: denoise, corrected: corrected, mastered: mastered))
        let row = try #require(report.rows.first { $0.id == "hf12" })

        #expect(row.denoiseDeltaDB == -0.6)
        #expect(row.masteringDeltaDB == 0.5)
        #expect(row.returnRatePercent.map { abs($0 - 83.3333) < 0.01 } == true)
        #expect(row.severity == .warning)
        #expect(abs(row.masteredDeltaFromInputDB - -0.1) < 0.001)
    }

    @Test
    func reportIsNilUntilRequiredInputsExist() {
        let corrected = snapshot(levels: [-30, -30, -30, -30])
        let mastered = snapshot(levels: [-29, -29, -29, -29])
        let denoise = DenoiseEffectReport(shimmerFlickerChangeDB: -1, hf12ChangeDB: -1, hf16ChangeDB: -1, hf18ChangeDB: -1)

        #expect(NoiseReturnReportService.makeReport(denoiseEffect: nil, corrected: corrected, mastered: mastered) == nil)
        #expect(NoiseReturnReportService.makeReport(denoiseEffect: denoise, corrected: corrected, mastered: nil) == nil)
    }

    private func snapshot(levels: [Double]) -> AudioMetricSnapshot {
        AudioMetricSnapshot(
            peakDBFS: -1,
            rmsDBFS: -18,
            crestFactorDB: 17,
            loudnessRangeLU: 8,
            integratedLoudnessLUFS: -18,
            truePeakDBFS: -1,
            stereoWidth: 0.5,
            stereoCorrelation: 0.8,
            harshnessScore: 0.2,
            centroidHz: 8_000,
            hf12Ratio: 0.1,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02,
            bandEnergies: [],
            masteringBandEnergies: [],
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: [
                SpectrumMetric(id: "10k", frequencyHz: 10_000, levelDB: levels[0]),
                SpectrumMetric(id: "12k", frequencyHz: 12_000, levelDB: levels[1]),
                SpectrumMetric(id: "16k", frequencyHz: 16_000, levelDB: levels[2]),
                SpectrumMetric(id: "18k", frequencyHz: 18_000, levelDB: levels[3])
            ]
        )
    }
}
