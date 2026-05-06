import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct ProcessingJobTests {
    @Test
    func selectingInputDoesNotExposeOldOutputs() {
        let job = ProcessingJob()
        let input = URL(fileURLWithPath: "/tmp/song.wav")

        job.prepareForSelection(input)

        #expect(job.hasExistingOutput == false)
        #expect(job.hasExistingMasteredOutput == false)
    }

    @Test
    func analysisModeDefaultsToAuto() {
        let job = ProcessingJob()

        #expect(job.selectedAnalysisMode == .auto)
    }

    @Test
    func selectingInputClearsPrecomputedCorrectionAnalysis() {
        let job = ProcessingJob()
        job.finishInputCorrectionAnalysis(makeAnalysis(), mode: .cpu)
        job.finishOutputMasteringAnalysis(makeMasteringAnalysis())

        job.prepareForSelection(URL(fileURLWithPath: "/tmp/next.wav"))

        #expect(job.inputCorrectionAnalysis?.cutoffFrequency == nil)
        #expect(job.inputCorrectionAnalysisMode == nil)
        #expect(job.outputMasteringAnalysis == nil)
    }

    @Test
    func autoAnalysisModeReportsResolvedMode() {
        let expected = MetalAudioAnalysisProcessor().isAvailable ? AudioAnalysisMode.experimentalMetal : .cpu

        #expect(AudioAnalysisMode.auto.resolvedMode == expected)
        #expect(AudioAnalysisMode.auto.resolvedSummary.contains(expected.title))
    }

    @Test
    func progressMovesForwardWhenLogsArrive() {
        let job = ProcessingJob()
        let input = URL(fileURLWithPath: "/tmp/input.wav")

        job.prepareForSelection(input)
        job.beginProcessing()
        job.appendLog("入力音声を読み込みます")
        job.appendLog("音声を解析します")

        #expect(job.activeStep == .analyze)
        #expect(job.completedSteps.contains(.loadAudio))
        #expect(job.progressValue > 0)
    }

    @Test
    func denoiseEffectReportUpdatesFromLogs() {
        let job = ProcessingJob()

        job.appendLog("ノイズ除去/10-16kHzチラつき: -1.5 dB")
        job.appendLog("ノイズ除去/12kHz以上: -0.8 dB")
        job.appendLog("ノイズ除去/16kHz以上: +0.3 dB")
        job.appendLog("ノイズ除去/18kHz以上: ±0.0 dB")

        #expect(job.denoiseEffectReport?.shimmerFlickerChangeDB == -1.5)
        #expect(job.denoiseEffectReport?.hf12ChangeDB == -0.8)
        #expect(job.denoiseEffectReport?.hf16ChangeDB == 0.3)
        #expect(job.denoiseEffectReport?.hf18ChangeDB == 0.0)
    }

    @Test
    func processingResetClearsDenoiseEffectReport() {
        let job = ProcessingJob()

        job.appendLog("ノイズ除去/12kHz以上: -0.8 dB")
        job.beginProcessing()

        #expect(job.denoiseEffectReport == nil)
    }

    @Test
    func successMarksAllStepsComplete() {
        let job = ProcessingJob()
        let output = URL(fileURLWithPath: "/tmp/output.wav")

        job.finishSuccess(output)

        #expect(job.progressValue == 1)
        #expect(job.completedSteps.count == ProcessingStep.allCases.count)
        #expect(job.activeStep == nil)
    }

    @Test
    func masteringProgressMovesForwardWhenLogsArrive() {
        let job = ProcessingJob()
        let input = URL(fileURLWithPath: "/tmp/input.wav")

        job.prepareForSelection(input)
        job.beginMastering()
        job.appendMasteringLog("補正済み音源を解析します")
        job.appendMasteringLog("帯域バランスを整えます")

        #expect(job.masteringActiveStep == .tone)
        #expect(job.completedMasteringSteps.contains(.analyze))
    }

    @Test
    func masteringSuccessMarksAllStepsComplete() {
        let job = ProcessingJob()
        let output = URL(fileURLWithPath: "/tmp/output_mastered.wav")

        job.finishMasteringSuccess(output)

        #expect(job.completedMasteringSteps.count == MasteringStep.allCases.count)
        #expect(job.masteringActiveStep == nil)
        #expect(job.masteredOutputFile == output)
    }

    @Test
    func applyingProfileResetsEditableSettings() {
        let job = ProcessingJob()

        job.updateMasteringSettings { settings in
            settings.targetLoudness = -11
        }
        #expect(job.isUsingCustomMasteringSettings)

        job.applyMasteringProfile(.natural)

        #expect(job.isUsingCustomMasteringSettings == false)
        #expect(job.editableMasteringSettings == MasteringProfile.natural.settings)
    }

    @Test
    func applyingCorrectionProfileResetsEditableSettings() {
        let job = ProcessingJob()

        job.updateCorrectionSettings { settings in
            settings.highNaturalness = 0.9
        }
        #expect(job.isUsingCustomCorrectionSettings)

        job.applyCorrectionProfile(.strong)

        #expect(job.isUsingCustomCorrectionSettings == false)
        #expect(job.selectedDenoiseStrength == .strong)
        #expect(job.editableCorrectionSettings == DenoiseStrength.strong.settings)
    }

    @Test
    func appliedCorrectionSettingsStayFixedAfterEditing() {
        let job = ProcessingJob()
        var applied = DenoiseStrength.balanced.settings
        applied.highNaturalness = 0.58

        job.beginProcessing(appliedSettings: applied)
        job.updateCorrectionSettings { settings in
            settings.highNaturalness = 0.90
        }
        job.finishSuccess(URL(fileURLWithPath: "/tmp/output.wav"), appliedSettings: applied)

        #expect(job.appliedCorrectionSettings?.highNaturalness == 0.58)
        #expect(job.editableCorrectionSettings.highNaturalness == 0.90)
    }

    @Test
    func appliedMasteringSettingsStayFixedAfterEditing() {
        let job = ProcessingJob()
        job.outputFile = URL(fileURLWithPath: "/tmp/output.wav")
        var applied = MasteringProfile.streaming.settings
        applied.highShelfGain = 0.48

        job.beginMastering(appliedSettings: applied)
        job.updateMasteringSettings { settings in
            settings.highShelfGain = 0.10
        }
        job.finishMasteringSuccess(URL(fileURLWithPath: "/tmp/output_mastered.wav"), appliedSettings: applied)

        #expect(job.appliedMasteringSettings?.highShelfGain == 0.48)
        #expect(job.editableMasteringSettings.highShelfGain == 0.10)
    }

    @Test
    func processingClearsOldOutputMetricsUntilNewAnalysisFinishes() {
        let job = ProcessingJob()
        job.finishOutputMetricAnalysis(makeSnapshot())

        job.beginProcessing(appliedSettings: DenoiseStrength.balanced.settings)

        #expect(job.outputMetrics == nil)
        #expect(job.appliedCorrectionSettings == nil)
    }

    private func makeSnapshot() -> AudioMetricSnapshot {
        AudioMetricSnapshot(
            peakDBFS: -1,
            rmsDBFS: -18,
            crestFactorDB: 12,
            loudnessRangeLU: 5,
            integratedLoudnessLUFS: -18,
            truePeakDBFS: -1,
            stereoWidth: 0.5,
            stereoCorrelation: 0.8,
            harshnessScore: 0.2,
            centroidHz: 2_000,
            hf12Ratio: 0.1,
            hf16Ratio: 0.04,
            hf18Ratio: 0.02,
            bandEnergies: [],
            masteringBandEnergies: [],
            shortTermLoudness: [],
            dynamics: [],
            averageSpectrum: []
        )
    }

    private func makeAnalysis() -> AnalysisData {
        AnalysisData(
            cutoffFrequency: 16_000,
            dominantHarmonics: [],
            harmonicConfidence: 0,
            hasShimmer: false,
            shimmerRatio: 0,
            brightnessRatio: 0,
            transientAmount: 0,
            noiseAmount: 0,
            rolloffDepth: 0,
            airBandEnergyRatio: 0,
            artifactBandRatio: 0
        )
    }

    private func makeMasteringAnalysis() -> MasteringAnalysis {
        MasteringAnalysis(
            integratedLoudness: -16,
            truePeakDBFS: -1,
            lowBandLevelDB: -24,
            midBandLevelDB: -18,
            highBandLevelDB: -20,
            harshnessScore: 0.25,
            stereoWidth: 0.8
        )
    }
}
