import Foundation
import Testing
@testable import VelouraLucent

struct AnalysisReportingConsistencyTests {
    @Test
    func displayStateDistinguishesUnselectedRunningCompletedAndFailed() {
        #expect(DisplayAnalysisPresentationState.resolve(
            hasSource: false,
            hasMetrics: false,
            isRunning: false,
            hasFailed: false
        ) == .notSelected)
        #expect(DisplayAnalysisPresentationState.resolve(
            hasSource: true,
            hasMetrics: false,
            isRunning: true,
            hasFailed: false
        ) == .running)
        #expect(DisplayAnalysisPresentationState.resolve(
            hasSource: true,
            hasMetrics: true,
            isRunning: false,
            hasFailed: false
        ) == .completed)
        #expect(DisplayAnalysisPresentationState.resolve(
            hasSource: true,
            hasMetrics: false,
            isRunning: false,
            hasFailed: true
        ) == .failed)
    }

    @Test
    func audioComparisonMeasuresIndependentTwentyOneToTwentyFourKilohertzBand() throws {
        let sampleRate = 48_000.0
        let frequency = 22_000.0
        let samples = (0..<4_800).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate) * 0.1)
        }
        let metrics = try AudioComparisonService.analyze(
            signal: AudioSignal(channels: [samples, samples], sampleRate: sampleRate)
        )

        let band = try #require(metrics.bandEnergies.first { $0.id == "generatedUltraHigh" })
        #expect(band.rangeDescription == "21-24kHz")
        #expect(band.levelDB.isFinite)
    }

    @Test
    func stemCompletionUsesLowFrequencyMeasurementsWithoutDuplicatingQualityRows() throws {
        let input = metrics(
            rms: -20,
            low: -30,
            lowMid: -32
        )
        let remixed = metrics(
            rms: -18,
            low: -27,
            lowMid: -31
        )
        let mastered = metrics(
            rms: -16,
            low: -27,
            lowMid: -27
        )
        let emptyNoise = NoiseMeasurementSnapshot(values: [])

        let report = try #require(StemAudioReportAdapter.makeCompletionReport(
            input: input,
            remixed: remixed,
            mastered: mastered,
            inputNoise: emptyNoise,
            remixedNoise: emptyNoise,
            masteredNoise: emptyNoise,
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringSettings: MasteringProfile.youtubeSpotify.settings,
            sourceDisplayName: "test-source",
            separationModelDisplayName: "HTDemucs",
            inputFileInfo: testFileInfo(sampleRate: 44_100),
            remixedFileInfo: testFileInfo(sampleRate: 48_000),
            masteredFileInfo: testFileInfo(sampleRate: 48_000)
        ))

        #expect(report.qualityRows.isEmpty)
        #expect(report.lowFrequencyRows.count == 2)
        #expect(report.lowFrequencyRows.first { $0.id == "stem-low-low" }?.value == "入力比 -1.00 dB")
        #expect(report.lowFrequencyRows.first { $0.id == "stem-low-low" }?.detail.contains("入力→Stem再ミックス +1.00 dB") == true)
        #expect(report.lowFrequencyRows.first { $0.id == "stem-low-low" }?.detail.contains("Stem再ミックス→最終版 -2.00 dB") == true)
        #expect(report.lowFrequencyRows.first { $0.id == "stem-low-low" }?.severity == .caution)
        #expect(report.lowFrequencyRows.first { $0.id == "stem-low-lowMid" }?.value == "入力比 +1.00 dB")
        #expect(report.severity == .normal)
        #expect(report.safetyRows.isEmpty)
        #expect(report.mode == .stem)
        #expect(report.comparisonRows.first { $0.id == "loudness" } != nil)
        #expect(report.comparisonRows.first { $0.id == "sample-rate" }?.inputValue == "44.1 kHz")
        #expect(report.sections.map(\.title) == [
            "1. 原音「test-source」の分析",
            "2. 再ミックス音源の分析",
            "3. マスタリング音源の分析",
            "ノイズ除去・補正・再ミックス・マスタリングの総合評価"
        ])
        #expect(report.sections[1].subsections.map(\.title).contains("HTDemucs由来の問題について"))
        #expect(report.sections[3].subsections.map(\.title).contains("4ステム分離と再ミックス"))
    }

    private func testFileInfo(sampleRate: Double) -> AudioFileInfo {
        AudioFileInfo(
            formatName: "WAV",
            sampleRate: sampleRate,
            channelCount: 2,
            duration: 1,
            bitDepth: 32,
            isFloatingPoint: true
        )
    }

    @Test
    func lowBalanceUsesSharedNormalCautionAndWarningBoundaries() throws {
        let rule = try #require(
            AudioQualityAssessmentService.lowBalanceRules.first { $0.id == "low" }
        )

        #expect(AudioQualityAssessmentService.severity(for: 1.49, rule: rule) == .normal)
        #expect(AudioQualityAssessmentService.severity(for: -1.50, rule: rule) == .caution)
        #expect(AudioQualityAssessmentService.severity(for: 2.99, rule: rule) == .caution)
        #expect(AudioQualityAssessmentService.severity(for: -3.00, rule: rule) == .warning)
    }

    private func metrics(
        rms: Double,
        low: Double,
        lowMid: Double
    ) -> AudioMetricSnapshot {
        AudioMetricSnapshot(
            duration: 1,
            peakDBFS: -6,
            rmsDBFS: rms,
            crestFactorDB: 12,
            loudnessRangeLU: 8,
            integratedLoudnessLUFS: -14,
            truePeakDBFS: -5,
            stereoWidth: 0.6,
            stereoCorrelation: 0.5,
            stereoCorrelationTimeline: [],
            stereoCorrelationTimelineStatus: .unavailable,
            harshnessScore: 0.5,
            centroidHz: 2_000,
            hf12Ratio: 0,
            hf16Ratio: 0,
            hf18Ratio: 0,
            bandEnergies: AudioBandCatalog.comparisonBands.map { band in
                return BandEnergyMetric(
                    id: band.id,
                    label: band.label,
                    rangeDescription: band.rangeDescription,
                    levelDB: rms - 10
                )
            },
            masteringBandEnergies: AudioBandCatalog.masteringBands.map { band in
                let levelDB: Double
                switch band.id {
                case "low":
                    levelDB = low
                case "lowMid":
                    levelDB = lowMid
                default:
                    levelDB = rms - 10
                }

                return BandEnergyMetric(
                    id: band.id,
                    label: band.label,
                    rangeDescription: band.rangeDescription,
                    levelDB: levelDB
                )
            },
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: []
        )
    }
}
