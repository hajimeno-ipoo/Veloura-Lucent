import AVFoundation
import Foundation
import Testing
@testable import VelouraLucent

struct MasteringPipelineTests {
    @Test
    func masteringProducesOutputFile() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "song_lifter.wav")
        let logs = MasteringLogCollector()

        try makeTestTone(at: inputURL)

        let output = try await MasteringService().process(inputFile: inputURL, profile: .streaming) { message in
            logs.append(message)
        }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(output.lastPathComponent.contains("song_lifter_mastered"))
        #expect(logs.values.contains("解析モード: マスタリングCPU"))
        #expect(logs.values.contains { $0.hasPrefix("解析/STFT: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析/ラウドネス: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析/トゥルーピーク: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析/帯域集計") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析/ステレオ幅: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("解析: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("合計: ") && $0.hasSuffix("秒") })
        let noiseReturnProbeCount = try #require(parsedInteger(prefix: "ノイズ戻り/軽量判定回数: ", from: logs.values))
        let noiseReturnFullCount = parsedInteger(prefix: "ノイズ戻り/最終確認回数: ", from: logs.values) ?? 0
        #expect(noiseReturnProbeCount <= 8)
        #expect(noiseReturnFullCount <= 1)
        #expect(logs.values.contains("ノイズ戻り: 一括判定を開始"))
        #expect(logs.values.contains { $0.hasPrefix("ノイズ戻り/軽量判定: ") })
        #expect(logs.values.contains("ノイズ戻り: 完了") || logs.values.contains("ノイズ戻り: 安全上限に到達"))
        #expect(logs.values.contains { $0.hasPrefix("マスタリング/計測: 高域保持: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("マスタリング/計測: 最終ノイズ上限: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("マスタリング/計測: 最終高域保持: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains("高域保持/基準測定: 2工程で再利用"))
        #expect(logs.values.contains { $0.hasPrefix("マスタリング/計測: 最終音量復帰: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("マスタリング/計測: 最終ノイズ確認: ") && $0.hasSuffix("秒") })
        #expect(logs.values.contains { $0.hasPrefix("マスタリング/計測: 最終音量上限: ") && $0.hasSuffix("秒") })
        let total = try #require(parsedDuration(prefix: "合計: ", from: logs.values))
        let stagePrefixes = ["解析: ", "音色: ", "ディエッサー: ", "ダイナミクス: ", "倍音: ", "空気感: ", "広がり: ", "ラウドネス: ", "ノイズ戻りガード: ", "マスタリング/計測: 高域保持: ", "マスタリング/計測: 最終ノイズ上限: ", "マスタリング/計測: 最終高域保持: ", "マスタリング/計測: 最終音量復帰: ", "マスタリング/計測: 最終ノイズ確認: ", "マスタリング/計測: 最終音量上限: ", "保存: "]
        var summedStages = 0.0
        for prefix in stagePrefixes {
            summedStages += try #require(parsedDuration(prefix: prefix, from: logs.values))
        }
        #expect(total + 0.10 >= summedStages)
        #expect(logs.values.contains("高域戻りガード: 早期終了 - 高域戻りガードを通常マスタリングでは使わない"))
        #expect(logs.values.contains(MasteringStep.noiseReturnGuard.rawValue))

        let written = try AVAudioFile(forReading: output)
        #expect(written.length > 0)
        let buffer = AVAudioPCMBuffer(pcmFormat: written.processingFormat, frameCapacity: AVAudioFrameCount(written.length))!
        try written.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        #expect(samples.contains { $0.isFinite })
        #expect(samples.map { abs($0) }.max() ?? 0 <= 1.01)
    }

    @Test
    func masteringAcceptsEditableSettings() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "song_lifter.wav")

        try makeTestTone(at: inputURL)

        var settings = MasteringProfile.streaming.settings
        settings.targetLoudness = -13.2
        settings.stereoWidth = 1.15
        settings.lowMidGain = 0.45
        settings.presenceGain = 0.38
        settings.deEsserAmount = 0.52

        let output = try await MasteringService().process(inputFile: inputURL, settings: settings) { _ in }

        #expect(FileManager.default.fileExists(atPath: output.path()))
    }

    @Test
    func masteringCanReuseReferenceNoiseMeasurements() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "noise-cache-check.wav")
        let logs = MasteringLogCollector()

        try makeTestTone(at: inputURL)
        let signal = try AudioFileService.loadAudio(from: inputURL)
        let noiseMeasurements = NoiseMeasurementService.analyze(signal: signal)

        let output = try await MasteringService().process(
            inputFile: inputURL,
            settings: MasteringProfile.streaming.settings,
            referenceNoiseMeasurements: noiseMeasurements
        ) { message in
            logs.append(message)
        }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(logs.values.contains("ノイズ測定: 既存結果を使用"))
        #expect(logs.values.contains("ノイズ戻り: 専用測定を開始"))
    }

    @Test
    func noiseReturnGuardDoesNotUseEightFullMeasurementPasses() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "noise-return-loop.wav")
        let logs = MasteringLogCollector()

        try makeHarshAirTone(at: inputURL)

        let output = try await MasteringService().process(
            inputFile: inputURL,
            profile: .forward
        ) { message in
            logs.append(message)
        }

        let fullMeasurementCount = parsedInteger(prefix: "ノイズ戻り/最終確認回数: ", from: logs.values) ?? 0
        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(fullMeasurementCount <= 1)
        #expect(logs.values.contains { $0.hasPrefix("ノイズ戻り/軽量判定: ") })
        #expect((parsedInteger(prefix: "ノイズ戻り/軽量判定回数: ", from: logs.values) ?? 0) <= 3)
        #expect(!logs.values.contains("ノイズ戻り/測定: 8/8"))
    }

    @Test
    func masteringCanReuseInitialAnalysis() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "analysis-cache-check.wav")
        let logs = MasteringLogCollector()

        try makeTestTone(at: inputURL)
        let signal = try AudioFileService.loadAudio(from: inputURL)
        let analysis = MasteringAnalysisService.analyze(signal: signal)

        let output = try await MasteringService().process(
            inputFile: inputURL,
            settings: MasteringProfile.streaming.settings,
            initialAnalysis: analysis
        ) { message in
            logs.append(message)
        }

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(logs.values.contains("解析: 既存結果を使用"))
        #expect(!logs.values.contains { $0.hasPrefix("解析/STFT: ") })
    }

    @Test
    func masteringKeepsTruePeakNearCeiling() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "ceiling-check.wav")

        try makeHotTransientTone(at: inputURL)

        let output = try await MasteringService().process(inputFile: inputURL, profile: .forward) { _ in }
        let mastered = try MasteringAnalysisService.analyze(fileURL: output)

        #expect(mastered.truePeakDBFS <= -0.4)
    }

    @Test
    func forwardMasteringPreservesUsefulDynamics() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "dynamic-check.wav")

        try makeHotTransientTone(at: inputURL)

        let before = try AudioComparisonService.analyze(fileURL: inputURL)
        let output = try await MasteringService().process(inputFile: inputURL, profile: .forward) { _ in }
        let after = try AudioComparisonService.analyze(fileURL: output)

        #expect(after.loudnessRangeLU >= before.loudnessRangeLU * 0.60)
        #expect(after.crestFactorDB >= before.crestFactorDB * 0.60)
    }

    @Test
    func masteringLimitsHighReturnForHarshMaterial() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "harsh-air-check.wav")

        try makeHarshAirTone(at: inputURL)

        let before = try AudioComparisonService.analyze(fileURL: inputURL)
        let output = try await MasteringService().process(inputFile: inputURL, profile: .streaming) { _ in }
        let after = try AudioComparisonService.analyze(fileURL: output)

        let beforeHigh = try #require(before.bandEnergies.first { $0.id == "air" }?.levelDB)
        let afterHigh = try #require(after.bandEnergies.first { $0.id == "air" }?.levelDB)

        #expect(afterHigh - after.rmsDBFS <= beforeHigh - before.rmsDBFS + 3.6)
    }

    @Test
    func masteringBalancesNoiseGuardWithHighBandPreservation() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "balanced-high-floor.wav")
        let logs = MasteringLogCollector()

        try makeHarshAirTone(at: inputURL)

        let reference = try AudioFileService.loadAudio(from: inputURL)
        let output = try await MasteringService().process(inputFile: inputURL, profile: .streaming) { message in
            logs.append(message)
        }
        let mastered = try AudioFileService.loadAudio(from: output)

        let referencePresence = bandRMSDB(signal: reference, lower: 5_000, upper: 10_000)
        let masteredPresence = bandRMSDB(signal: mastered, lower: 5_000, upper: 10_000)

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(masteredPresence >= referencePresence - 2.0)
        expectHighBandsNotDulled(reference: reference, processed: mastered)
        #expect(!logs.values.contains("高域保持: ノイズ戻り抑制 mix 0.00"))
        #expect(logs.values.contains { $0.hasPrefix("高域保持: ") } || masteredPresence >= referencePresence - 2.0)
    }

    @Test
    func masteringPreservesAirAndPresenceWithinMusicalGoal() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "mastering-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "musical-air-goal.wav")

        try makeMusicalAirTone(at: inputURL)

        let reference = try AudioFileService.loadAudio(from: inputURL)
        let output = try await MasteringService().process(
            inputFile: inputURL,
            settings: MasteringProfile.streaming.settings,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }
        let mastered = try AudioFileService.loadAudio(from: output)

        let referencePresence = bandRMSDB(signal: reference, lower: 5_000, upper: 8_000)
        let masteredPresence = bandRMSDB(signal: mastered, lower: 5_000, upper: 8_000)
        let referenceRoom = bandRMSDB(signal: reference, lower: 300, upper: 3_000)
        let masteredRoom = bandRMSDB(signal: mastered, lower: 300, upper: 3_000)
        let referenceMetrics = try AudioComparisonService.analyze(fileURL: inputURL)
        let masteredMetrics = try AudioComparisonService.analyze(fileURL: output)
        let baselineMetrics = try masteringLoudnessBaselineMetrics(in: diagnostics)
        let policy = MasteringProfile.streaming.settings.loudnessAdjustmentPolicy

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(masteredPresence >= referencePresence - 2.0)
        expectHighBandsNotDulled(reference: reference, processed: mastered)
        #expect(masteredRoom - masteredMetrics.rmsDBFS <= referenceRoom - referenceMetrics.rmsDBFS + 1.2)
        #expect(masteredMetrics.integratedLoudnessLUFS <= baselineMetrics.integratedLoudnessLUFS + policy.maxBoostDB + 0.2)
        #expect(masteredMetrics.integratedLoudnessLUFS >= baselineMetrics.integratedLoudnessLUFS - policy.maxCutDB - 0.2)
        #expect(masteredMetrics.truePeakDBFS <= -1.5)
    }

    @Test
    func masteringRestoresFinalLoudnessAfterNoiseGuards() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "mastering-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "final-loudness-restore.wav")
        let logs = MasteringLogCollector()

        try makeCleanHeadroomTone(at: inputURL)
        var settings = MasteringProfile.streaming.settings
        settings.targetLoudness = -16.2

        let output = try await MasteringService().process(
            inputFile: inputURL,
            settings: settings,
            diagnosticOutputDirectory: diagnostics
        ) { message in
            logs.append(message)
        }
        let masteredMetrics = try AudioComparisonService.analyze(fileURL: output)
        let baselineMetrics = try masteringLoudnessBaselineMetrics(in: diagnostics)
        let beforeFinalRestore = try AudioComparisonService.analyze(
            fileURL: diagnosticFile(in: diagnostics, containing: "12_mastering_finalHighPreserve")
        )
        let afterFinalRestore = try AudioComparisonService.analyze(
            fileURL: diagnosticFile(in: diagnostics, containing: "13_mastering_finalLoudnessRestore")
        )
        let policy = settings.loudnessAdjustmentPolicy

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(afterFinalRestore.integratedLoudnessLUFS >= beforeFinalRestore.integratedLoudnessLUFS + 1.0)
        #expect(afterFinalRestore.integratedLoudnessLUFS <= beforeFinalRestore.integratedLoudnessLUFS + 2.2)
        #expect(afterFinalRestore.truePeakDBFS <= Double(settings.peakCeilingDB) + 0.05)
        #expect(masteredMetrics.integratedLoudnessLUFS <= baselineMetrics.integratedLoudnessLUFS + policy.maxBoostDB + 0.2)
        #expect(masteredMetrics.integratedLoudnessLUFS >= baselineMetrics.integratedLoudnessLUFS - policy.maxCutDB - 0.2)
        #expect(masteredMetrics.truePeakDBFS <= Double(settings.peakCeilingDB) + 0.05)
        #expect(logs.values.contains { $0.hasPrefix("最終音量復帰: +") })
    }

    @Test
    func masteringLimitsLoudnessBoostByProfilePolicy() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "mastering-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "quiet-policy-check.wav")
        let logs = MasteringLogCollector()

        try makeTestTone(at: inputURL)
        var quiet = try AudioFileService.loadAudio(from: inputURL)
        quiet = AudioSignal(
            channels: quiet.channels.map { channel in channel.map { $0 * 0.08 } },
            sampleRate: quiet.sampleRate
        )
        try AudioFileService.saveAudio(quiet, to: inputURL)

        var settings = MasteringProfile.streaming.settings
        settings.targetLoudness = -9.0
        let output = try await MasteringService().process(
            inputFile: inputURL,
            settings: settings,
            diagnosticOutputDirectory: diagnostics
        ) { message in
            logs.append(message)
        }
        let after = try AudioComparisonService.analyze(fileURL: output)
        let baseline = try masteringLoudnessBaselineMetrics(in: diagnostics)
        let policy = settings.loudnessAdjustmentPolicy

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(after.integratedLoudnessLUFS <= baseline.integratedLoudnessLUFS + policy.maxBoostDB + 0.2)
        #expect(after.truePeakDBFS <= Double(settings.peakCeilingDB) + 0.05)
        #expect(logs.values.contains { $0.hasPrefix("ラウドネス方針: 聴きやすく整える") })
        #expect(logs.values.contains { $0.hasPrefix("最終音量上限: ") })
    }

    @Test
    func masteringLimitsLoudnessCutByProfilePolicy() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let diagnostics = tempDirectory.appending(path: "mastering-stages")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "hot-policy-check.wav")
        let logs = MasteringLogCollector()

        try makeHotTransientTone(at: inputURL)

        var settings = MasteringProfile.streaming.settings
        settings.targetLoudness = -40.0
        let output = try await MasteringService().process(
            inputFile: inputURL,
            settings: settings,
            diagnosticOutputDirectory: diagnostics
        ) { message in
            logs.append(message)
        }
        let after = try AudioComparisonService.analyze(fileURL: output)
        let baseline = try masteringLoudnessBaselineMetrics(in: diagnostics)
        let policy = settings.loudnessAdjustmentPolicy

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(after.integratedLoudnessLUFS >= baseline.integratedLoudnessLUFS - policy.maxCutDB - 0.2)
        #expect(after.truePeakDBFS <= Double(settings.peakCeilingDB) + 0.05)
        #expect(logs.values.contains { $0.hasPrefix("ラウドネス方針: 聴きやすく整える") })
        #expect(logs.values.contains { $0.hasPrefix("最終音量上限: ") || $0.hasPrefix("最終音量下限: ") })
    }

    @Test
    func youtubeSpotifyPresetReachesTargetWhenHeadroomAllows() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "youtube-spotify-target.wav")

        try makeCleanHeadroomTone(at: inputURL)

        let settings = MasteringProfile.youtubeSpotify.settings
        let output = try await MasteringService().process(
            inputFile: inputURL,
            settings: settings
        ) { _ in }
        let metrics = try AudioComparisonService.analyze(fileURL: output)

        #expect(FileManager.default.fileExists(atPath: output.path()))
        #expect(abs(metrics.integratedLoudnessLUFS - Double(settings.targetLoudness)) <= 1.5)
        #expect(metrics.truePeakDBFS <= Double(settings.peakCeilingDB) + 0.05)
    }

    @Test
    func masteringUsesOriginalReferenceWhenCorrectedInputLostAir() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let originalURL = tempDirectory.appending(path: "original-air-reference.wav")
        let correctedURL = tempDirectory.appending(path: "corrected-air-loss.wav")
        let logs = MasteringLogCollector()

        try makeBrightAirReferenceTone(at: originalURL)
        let original = try AudioFileService.loadAudio(from: originalURL)
        var corrected = attenuateBand(signal: original, lower: 8_000, upper: 16_000, gainDB: -10)
        corrected = attenuateBand(signal: corrected, lower: 16_000, upper: 20_000, gainDB: -6)
        try AudioFileService.saveAudio(corrected, to: correctedURL)

        let correctedNoise = NoiseMeasurementService.analyze(signal: corrected)
        let originalNoise = NoiseMeasurementService.analyze(signal: original)
        let outputWithOriginal = try await MasteringService().process(
            inputFile: correctedURL,
            settings: MasteringProfile.streaming.settings,
            referenceNoiseMeasurements: correctedNoise,
            originalReferenceFile: originalURL,
            originalReferenceNoiseMeasurements: originalNoise
        ) { message in
            logs.append(message)
        }

        let masteredWithOriginal = try AudioFileService.loadAudio(from: outputWithOriginal)
        let correctedBrilliance = bandBalanceDB(signal: corrected, lower: 8_000, upper: 12_000)
        let correctedAir = bandBalanceDB(signal: corrected, lower: 12_000, upper: 16_000)
        let originalBrilliance = bandBalanceDB(signal: original, lower: 8_000, upper: 12_000)
        let withOriginalBrilliance = bandBalanceDB(signal: masteredWithOriginal, lower: 8_000, upper: 12_000)
        let originalAir = bandBalanceDB(signal: original, lower: 12_000, upper: 16_000)
        let withOriginalAir = bandBalanceDB(signal: masteredWithOriginal, lower: 12_000, upper: 16_000)

        #expect(withOriginalBrilliance >= correctedBrilliance + 0.75)
        #expect(withOriginalAir >= correctedAir + 0.75)
        #expect(withOriginalBrilliance >= originalBrilliance - 4.0)
        #expect(withOriginalAir >= originalAir - 4.0)
        #expect(logs.values.contains { $0.hasPrefix("原音参照読み込み: ") })
    }

    @Test
    func masteringNoiseReturnHissReductionIsBoundedForAudioQuality() {
        let hissRule = InternalAudioJudgementPolicy.masteringNoiseReturnLimits.first {
            $0.id == NoiseMeasurementID.hiss
        }
        let shimmerRule = InternalAudioJudgementPolicy.masteringNoiseReturnLimits.first {
            $0.id == NoiseMeasurementID.shimmer
        }

        #expect(hissRule?.lowerFrequency == 8_000)
        #expect(hissRule?.allowedReturnDB == 1.5)
        #expect(hissRule?.reductionMultiplier == 0.35)
        #expect(hissRule?.maxReductionDB == 2.0)
        #expect(shimmerRule?.lowerFrequency == 8_000)
        #expect(shimmerRule?.upperFrequency == 16_000)
        #expect(shimmerRule?.reductionMultiplier == 0.30)
        #expect(shimmerRule?.maxReductionDB == 1.4)
    }

    @Test
    func noiseReturnGuardPreservesSustainedMusicalHighBands() async throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let inputURL = tempDirectory.appending(path: "noise-return-musical-high.wav")
        let diagnostics = tempDirectory.appending(path: "mastering-stages")

        try makeMusicalAirTone(at: inputURL)

        _ = try await MasteringService().process(
            inputFile: inputURL,
            settings: MasteringProfile.streaming.settings,
            diagnosticOutputDirectory: diagnostics
        ) { _ in }

        let beforeGuard = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "08_mastering_highReturnGuard"))
        let afterGuard = try AudioFileService.loadAudio(from: diagnosticFile(in: diagnostics, containing: "09_mastering_noiseReturnGuard"))
        let brillianceDrop = bandRMSDB(signal: afterGuard, lower: 8_000, upper: 12_000)
            - bandRMSDB(signal: beforeGuard, lower: 8_000, upper: 12_000)
        let airDrop = bandRMSDB(signal: afterGuard, lower: 12_000, upper: 16_000)
            - bandRMSDB(signal: beforeGuard, lower: 12_000, upper: 16_000)
        let ultraDrop = bandRMSDB(signal: afterGuard, lower: 16_000, upper: 20_000)
            - bandRMSDB(signal: beforeGuard, lower: 16_000, upper: 20_000)

        #expect(brillianceDrop >= -0.50)
        #expect(airDrop >= -0.50)
        #expect(ultraDrop >= -0.60)
    }

    @Test
    func shimmerLimiterReductionLimitsStayModerateByCorrectionStrength() {
        let rules = InternalAudioJudgementPolicy.shimmerLimitRules(improvementDB: 1.0)
        #expect(rules == [
            ShimmerLimitRule(id: NoiseMeasurementID.shimmer, lowerFrequency: 8_000, upperFrequency: 14_000, improvementDB: 1.0)
        ])
        #expect(InternalAudioJudgementPolicy.shimmerMaxReductionPerPassDB(correctionIntensity: 0.72) == 4.0)
        #expect(InternalAudioJudgementPolicy.shimmerMaxReductionPerPassDB(correctionIntensity: 0.50) == 3.0)
        #expect(InternalAudioJudgementPolicy.shimmerMaxReductionPerPassDB(correctionIntensity: 0.30) == 2.0)
        #expect(InternalAudioJudgementPolicy.shimmerReductionScale(correctionIntensity: 0.72) == 0.65)
        #expect(InternalAudioJudgementPolicy.shimmerReductionScale(correctionIntensity: 0.50) == 0.50)
        #expect(InternalAudioJudgementPolicy.shimmerReductionScale(correctionIntensity: 0.30) == 0.35)
    }

    @Test
    func masteredOutputURLsStayWav() {
        let inputURL = URL(fileURLWithPath: "/tmp/song_lifter.mp3")

        let defaultOutput = MasteringService.defaultOutputURL(for: inputURL)
        let temporaryOutput = MasteringService.temporaryOutputURL(for: inputURL)

        #expect(defaultOutput.pathExtension == AudioFileService.outputFileExtension)
        #expect(temporaryOutput.pathExtension == AudioFileService.outputFileExtension)
    }

    private func makeTestTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            left[index] = Float(sin(2 * Double.pi * 220 * t) * 0.08 + sin(2 * Double.pi * 8_000 * t) * 0.02)
            right[index] = Float(sin(2 * Double.pi * 220 * t + 0.12) * 0.08 + sin(2 * Double.pi * 7_600 * t) * 0.018)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private func makeCleanHeadroomTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 220 * t) * 0.14
            let support = sin(2 * Double.pi * 440 * t) * 0.035
            left[index] = Float(body + support)
            right[index] = Float(body * 0.98 + support * 0.96)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private func makeHotTransientTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 2.5)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let body = sin(2 * Double.pi * 180 * t) * 0.32
            let bright = sin(2 * Double.pi * 6_400 * t) * 0.10
            let transient = index % 7_200 < 120 ? 0.55 : 0
            left[index] = Float(body + bright + transient)
            right[index] = Float(body * 0.96 + sin(2 * Double.pi * 7_100 * t) * 0.09 + transient * 0.92)
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private func makeHarshAirTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 3)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let body = Float(sin(2 * Double.pi * 260 * t) * 0.06)
            let presence = Float(sin(2 * Double.pi * 6_800 * t) * 0.026)
            let air = Float(sin(2 * Double.pi * 13_500 * t) * 0.018)
            let shimmer = Float(sin(2 * Double.pi * 15_500 * t + sin(2 * Double.pi * 11 * t)) * 0.012)
            left[index] = body + presence + air + shimmer
            right[index] = body * 0.97 + presence * 0.92 - air * 0.28 + shimmer * 0.7
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private func makeMusicalAirTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 4)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let swell = 0.74 + 0.18 * sin(2 * Double.pi * 0.32 * t)
            let body = sin(2 * Double.pi * 190 * t) * 0.11
                + sin(2 * Double.pi * 380 * t) * 0.045
                + sin(2 * Double.pi * 760 * t) * 0.022
            let presence = sin(2 * Double.pi * 6_400 * t) * 0.014 * swell
            let brilliance = sin(2 * Double.pi * 9_800 * t) * 0.012 * swell
            let air = sin(2 * Double.pi * 13_400 * t) * 0.009 * swell
            let ultraAir = sin(2 * Double.pi * 17_800 * t) * 0.006 * swell
            let transient = index % 9_600 < 90 ? 0.045 : 0

            left[index] = Float(body + presence + brilliance + air + ultraAir + transient)
            right[index] = Float(
                body * 0.96
                    + presence * 0.88
                    + brilliance * 0.72
                    - air * 0.40
                    - ultraAir * 0.34
                    + transient * 0.82
            )
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }

    private func makeBrightAirReferenceTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * 4)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]

        for index in 0..<frameCount {
            let t = Double(index) / sampleRate
            let swell = 0.76 + 0.16 * sin(2 * Double.pi * 0.28 * t)
            let body = sin(2 * Double.pi * 210 * t) * 0.10
                + sin(2 * Double.pi * 420 * t) * 0.040
                + sin(2 * Double.pi * 840 * t) * 0.020
            let presence = sin(2 * Double.pi * 6_200 * t) * 0.016 * swell
            let brilliance = sin(2 * Double.pi * 9_600 * t) * 0.040 * swell
            let air = sin(2 * Double.pi * 13_200 * t) * 0.032 * swell
            let ultraAir = sin(2 * Double.pi * 17_600 * t) * 0.014 * swell

            left[index] = Float(body + presence + brilliance + air + ultraAir)
            right[index] = Float(
                body * 0.96
                    + presence * 0.88
                    + brilliance * 0.70
                    - air * 0.36
                    - ultraAir * 0.30
            )
        }

        let file = try AVAudioFile(
            forWriting: url,
            settings: AudioFileService.interleavedFileSettings(sampleRate: sampleRate, channels: 2)
        )
        try file.write(from: buffer)
    }
}

private final class MasteringLogCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ message: String) {
        lock.lock()
        storage.append(message)
        lock.unlock()
    }
}

private func parsedDuration(prefix: String, from logs: [String]) -> Double? {
    guard let line = logs.first(where: { $0.hasPrefix(prefix) && $0.hasSuffix("秒") }) else {
        return nil
    }
    let trimmed = line
        .replacingOccurrences(of: prefix, with: "")
        .replacingOccurrences(of: "秒", with: "")
    return Double(trimmed)
}

private func parsedInteger(prefix: String, from logs: [String]) -> Int? {
    guard let line = logs.first(where: { $0.hasPrefix(prefix) }) else {
        return nil
    }
    return Int(line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines))
}

private func diagnosticFile(in directory: URL, containing fragment: String) throws -> URL {
    let contents = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    return try #require(contents.first { $0.lastPathComponent.contains(fragment) })
}

private func masteringLoudnessBaselineMetrics(in directory: URL) throws -> AudioMetricSnapshot {
    try AudioComparisonService.analyze(fileURL: diagnosticFile(in: directory, containing: "06_mastering_stereo"))
}

private func bandRMSDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
    let upperBound = min(upper, signal.sampleRate * 0.5 - 100)
    guard lower < upperBound else { return -120 }
    let mono = signal.monoMixdown()
    let band = SpectralDSP.lowPass(
        SpectralDSP.highPass(mono, cutoff: lower, sampleRate: signal.sampleRate),
        cutoff: upperBound,
        sampleRate: signal.sampleRate
    )
    let meanSquare = band.reduce(0.0) { partial, sample in
        partial + Double(sample * sample)
    } / Double(max(band.count, 1))
    return 10 * log10(max(meanSquare, 1e-12))
}

private func bandBalanceDB(signal: AudioSignal, lower: Double, upper: Double) -> Double {
    bandRMSDB(signal: signal, lower: lower, upper: upper) - fullRMSDB(signal: signal)
}

private func expectHighBandsNotDulled(
    reference: AudioSignal,
    processed: AudioSignal,
    maxBrillianceDropDB: Double = 2.0,
    maxAirDropDB: Double = 2.0,
    maxUltraAirDropDB: Double = 2.5
) {
    #expect(
        bandRMSDB(signal: processed, lower: 8_000, upper: 12_000)
            >= bandRMSDB(signal: reference, lower: 8_000, upper: 12_000) - maxBrillianceDropDB
    )
    #expect(
        bandRMSDB(signal: processed, lower: 12_000, upper: 16_000)
            >= bandRMSDB(signal: reference, lower: 12_000, upper: 16_000) - maxAirDropDB
    )
    #expect(
        bandRMSDB(signal: processed, lower: 16_000, upper: 20_000)
            >= bandRMSDB(signal: reference, lower: 16_000, upper: 20_000) - maxUltraAirDropDB
    )
}

private func fullRMSDB(signal: AudioSignal) -> Double {
    let mono = signal.monoMixdown()
    let meanSquare = mono.reduce(0.0) { partial, sample in
        partial + Double(sample * sample)
    } / Double(max(mono.count, 1))
    return 10 * log10(max(meanSquare, 1e-12))
}

private func attenuateBand(signal: AudioSignal, lower: Double, upper: Double, gainDB: Float) -> AudioSignal {
    let upperBound = min(upper, signal.sampleRate * 0.5 - 100)
    guard lower < upperBound else { return signal }
    let gain = powf(10, gainDB / 20)
    let channels = signal.channels.map { channel in
        let band = SpectralDSP.lowPass(
            SpectralDSP.highPass(channel, cutoff: lower, sampleRate: signal.sampleRate),
            cutoff: upperBound,
            sampleRate: signal.sampleRate
        )
        return channel.indices.map { index in
            channel[index] + band[index] * (gain - 1)
        }
    }
    return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
}
