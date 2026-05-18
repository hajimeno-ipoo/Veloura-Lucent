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
    func progressMovesForwardWhenEventsArrive() {
        let job = ProcessingJob()
        let input = URL(fileURLWithPath: "/tmp/input.wav")

        job.prepareForSelection(input)
        job.beginProcessing()
        job.appendLog(ProcessingProgressEvent.correction(step: .loadAudio, state: .started, detail: nil).encodedMessage)
        job.appendLog(ProcessingProgressEvent.correction(step: .loadAudio, state: .completed, detail: nil).encodedMessage)
        job.appendLog(ProcessingProgressEvent.correction(step: .analyze, state: .started, detail: nil).encodedMessage)

        #expect(job.activeStep == .analyze)
        #expect(job.completedSteps.contains(.loadAudio))
        #expect(job.progressValue > 0)
    }

    @Test
    func humanLogTextDoesNotDriveProgress() {
        let job = ProcessingJob()

        job.beginProcessing()
        job.appendLog("入力音声を読み込みます")
        job.appendLog("音声を解析しています")

        #expect(job.activeStep == nil)
        #expect(job.completedSteps.isEmpty)
        #expect(job.logText.contains("入力音声を読み込みます"))
    }

    @Test
    func skippedCorrectionEventUpdatesProgress() {
        let job = ProcessingJob()

        job.beginProcessing()
        job.appendLog(ProcessingProgressEvent.correction(step: .repairShimmerGuard, state: .skipped, detail: "高域補修後のシマー危険が低い").encodedMessage)

        #expect(job.skippedSteps.contains(.repairShimmerGuard))
        #expect(job.progressValue > 0)
    }

    @Test
    func skippedMasteringEventUpdatesProgress() {
        let job = ProcessingJob()
        job.outputFile = URL(fileURLWithPath: "/tmp/output.wav")

        job.beginMastering()
        job.appendMasteringLog(ProcessingProgressEvent.mastering(step: .deEss, state: .skipped, detail: "刺さりとサ行ノイズが低い").encodedMessage)

        #expect(job.skippedMasteringSteps.contains(.deEss))
    }

    @Test
    func progressDetailUpdatesCurrentLabel() {
        let job = ProcessingJob()

        job.beginProcessing()
        job.appendLog(ProcessingProgressEvent.correction(step: .shimmerPeakLimit, state: .started, detail: nil).encodedMessage)
        job.appendLog(ProcessingProgressEvent.correction(step: .shimmerPeakLimit, state: .detail, detail: "2/5 回目を確認中").encodedMessage)

        #expect(job.activeStep == .shimmerPeakLimit)
        #expect(job.progressLabel == "シマー制限: 2/5 回目を確認中")
    }

    @Test
    func failedCorrectionStepIsKeptForProgressDisplay() {
        let job = ProcessingJob()

        job.beginProcessing()
        job.appendLog(ProcessingProgressEvent.correction(step: .denoise, state: .started, detail: nil).encodedMessage)
        job.finishFailure("テスト失敗")

        #expect(job.failedSteps.contains(.denoise))
        #expect(job.activeStep == nil)
    }

    @Test
    func cleanCorrectionRouteKeepsMandatoryStepsRunning() {
        let plan = CorrectionRoutePlan.make(
            analysis: makeAnalysis(),
            noiseMeasurements: makeNoiseSnapshot(
                hiss: -62,
                sibilance: 4,
                shimmer: -50,
                mud: -12,
                hum: 2,
                rumble: -16
            )
        )

        #expect(plan.decision(for: .lowNoiseCleanup).action == .skip)
        #expect(plan.decision(for: .denoise).action == .run)
        #expect(plan.decision(for: .harmonicRepair).action == .run)
        #expect(plan.decision(for: .peakSafety).action == .run)
    }

    @Test
    func noisyCorrectionRouteDoesNotSkipGuards() {
        let plan = CorrectionRoutePlan.make(
            analysis: AnalysisData(
                cutoffFrequency: 14_000,
                dominantHarmonics: [],
                harmonicConfidence: 0.4,
                hasShimmer: true,
                shimmerRatio: 0.35,
                brightnessRatio: 0.4,
                transientAmount: 0.3,
                noiseAmount: 0.5,
                rolloffDepth: 0.2,
                airBandEnergyRatio: 0.2,
                artifactBandRatio: 0.25,
                denoiseEffectMetrics: nil
            ),
            noiseMeasurements: makeNoiseSnapshot(
                hiss: -45,
                sibilance: 11,
                shimmer: -35,
                mud: -3,
                hum: 9,
                rumble: -4
            )
        )

        #expect(plan.decision(for: .lowNoiseCleanup).action == .run)
        #expect(plan.decision(for: .sibilanceShimmerGuard).action == .run)
        #expect(plan.decision(for: .shimmerPeakLimit).action == .run)
    }

    @Test
    func shortShimmerDoesNotSkipShimmerLimitEvenWhenHighNoiseFloorIsQuiet() {
        let plan = CorrectionRoutePlan.make(
            analysis: AnalysisData(
                cutoffFrequency: 16_000,
                dominantHarmonics: [],
                harmonicConfidence: 0.2,
                hasShimmer: true,
                shimmerRatio: 0.24,
                brightnessRatio: 0.3,
                transientAmount: 0.35,
                noiseAmount: 0.2,
                rolloffDepth: 0.1,
                airBandEnergyRatio: 0.2,
                artifactBandRatio: 0.1,
                denoiseEffectMetrics: nil
            ),
            noiseMeasurements: makeNoiseSnapshot(
                hiss: -62,
                sibilance: 4,
                shimmer: -50,
                mud: -12,
                hum: 2,
                rumble: -16
            )
        )

        #expect(plan.decision(for: .shimmerPeakLimit).action == .run)
    }

    @Test
    func missingCorrectionNoiseMeasurementsDoNotSkipNoiseSensitiveSteps() {
        let plan = CorrectionRoutePlan.make(
            analysis: makeAnalysis(),
            noiseMeasurements: NoiseMeasurementSnapshot(values: [])
        )

        #expect(plan.decision(for: .lowNoiseCleanup).action == .run)
        #expect(plan.decision(for: .sibilanceShimmerGuard).action == .run)
        #expect(plan.decision(for: .lowMidResidueGuard).action == .run)
        #expect(plan.decision(for: .shimmerPeakLimit).action == .run)
    }

    @Test
    func missingMasteringNoiseMeasurementsDoNotSkipNoiseSensitiveSteps() {
        let plan = MasteringRoutePlan.make(
            analysis: makeMasteringAnalysis(),
            settings: MasteringProfile.streaming.settings,
            noiseMeasurements: NoiseMeasurementSnapshot(values: [])
        )

        #expect(plan.decision(for: .deEss).action == .run)
        #expect(plan.decision(for: .highReturnGuard).action == .skip)
        #expect(plan.decision(for: .noiseReturnGuard).action == .run)
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
    func masteringProgressMovesForwardWhenEventsArrive() {
        let job = ProcessingJob()
        let input = URL(fileURLWithPath: "/tmp/input.wav")

        job.prepareForSelection(input)
        job.beginMastering()
        job.appendMasteringLog(ProcessingProgressEvent.mastering(step: .analyze, state: .started, detail: nil).encodedMessage)
        job.appendMasteringLog(ProcessingProgressEvent.mastering(step: .analyze, state: .completed, detail: nil).encodedMessage)
        job.appendMasteringLog(ProcessingProgressEvent.mastering(step: .tone, state: .started, detail: nil).encodedMessage)

        #expect(job.masteringActiveStep == .tone)
        #expect(job.completedMasteringSteps.contains(.analyze))
    }

    @Test
    func failedMasteringStepIsKeptForProgressDisplay() {
        let job = ProcessingJob()
        job.outputFile = URL(fileURLWithPath: "/tmp/output.wav")

        job.beginMastering()
        job.appendMasteringLog(ProcessingProgressEvent.mastering(step: .noiseReturnGuard, state: .started, detail: nil).encodedMessage)
        job.finishMasteringFailure("テスト失敗")

        #expect(job.failedMasteringSteps.contains(.noiseReturnGuard))
        #expect(job.masteringActiveStep == nil)
    }

    @Test
    func beginMasteringClearsOldMasteredOutput() {
        let job = ProcessingJob()
        job.outputFile = URL(fileURLWithPath: "/tmp/output.wav")
        job.masteredOutputFile = URL(fileURLWithPath: "/tmp/old_mastered.wav")
        job.hasExistingMasteredOutput = true
        job.masteredMetrics = makeSnapshot()

        job.beginMastering()

        #expect(job.masteredOutputFile == nil)
        #expect(job.hasExistingMasteredOutput == false)
        #expect(job.masteredMetrics == nil)
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
            artifactBandRatio: 0,
            denoiseEffectMetrics: nil
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

    private func makeNoiseSnapshot(
        hiss: Double,
        sibilance: Double,
        shimmer: Double,
        mud: Double,
        hum: Double,
        rumble: Double
    ) -> NoiseMeasurementSnapshot {
        NoiseMeasurementSnapshot(values: [
            NoiseMeasurementValue(id: "hiss", label: "ヒス・シュワシュワ", comparableLevelDB: hiss, measuredLevelDB: hiss),
            NoiseMeasurementValue(id: "sibilance", label: "サ行・歯擦音", comparableLevelDB: sibilance, measuredLevelDB: sibilance),
            NoiseMeasurementValue(id: "shimmer", label: "高域のチラつき", comparableLevelDB: shimmer, measuredLevelDB: shimmer),
            NoiseMeasurementValue(id: "mud", label: "こもり・低いザラつき", comparableLevelDB: mud, measuredLevelDB: mud),
            NoiseMeasurementValue(id: "hum", label: "ハム・電源ノイズ", comparableLevelDB: hum, measuredLevelDB: hum),
            NoiseMeasurementValue(id: "rumble", label: "低域ゴロゴロ", comparableLevelDB: rumble, measuredLevelDB: rumble)
        ])
    }
}
