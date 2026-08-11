import Foundation
import Testing
@testable import VelouraLucent

struct StemAudioEvaluationServiceTests {
    @Test
    func retainsEveryRequestedNormalModeSnapshot() async throws {
        let request = StemAudioEvaluationRequest(
            purpose: .canonicalInput,
            includeAudioAnalyzerSnapshot: true,
            includeMasteringAnalysisSnapshot: true
        )

        let snapshot = try await StemAudioEvaluationService.evaluate(
            signal: Self.makeSignal(),
            request: request
        )

        #expect(snapshot.purpose == .canonicalInput)
        #expect(snapshot.completedMeasurements == request.requestedMeasurements)
        #expect(snapshot.audioMetrics.duration > 0)
        #expect(snapshot.audioMetrics.bandEnergies.isEmpty == false)
        #expect(snapshot.audioMetrics.masteringBandEnergies.isEmpty == false)
        #expect(snapshot.audioMetrics.completionReportAnalysis.displayWaveform.isEmpty == false)
        #expect(snapshot.noiseMeasurements.values.count == 7)
        #expect(snapshot.audioAnalysis != nil)
        #expect(snapshot.masteringAnalysis != nil)
    }

    @Test
    func optionalSnapshotsFollowTheExplicitPurposeRequest() async throws {
        let rawStemRequest = StemAudioEvaluationRequest(
            purpose: .rawStem(role: .drums),
            includeAudioAnalyzerSnapshot: true,
            includeMasteringAnalysisSnapshot: false
        )
        let finalMasterRequest = StemAudioEvaluationRequest(
            purpose: .finalMaster,
            includeAudioAnalyzerSnapshot: false,
            includeMasteringAnalysisSnapshot: true
        )

        let rawStemSnapshot = try await StemAudioEvaluationService.evaluate(
            signal: Self.makeSignal(),
            request: rawStemRequest
        )
        let finalMasterSnapshot = try await StemAudioEvaluationService.evaluate(
            signal: Self.makeSignal(),
            request: finalMasterRequest
        )

        #expect(rawStemSnapshot.completedMeasurements == [
            .audioComparisonSnapshot,
            .noiseMeasurementSnapshot,
            .audioAnalyzerSnapshot
        ])
        #expect(rawStemSnapshot.audioAnalysis != nil)
        #expect(rawStemSnapshot.masteringAnalysis == nil)
        #expect(rawStemSnapshot.audioMetrics.completionReportAnalysis == .unavailable)

        #expect(finalMasterSnapshot.completedMeasurements == [
            .audioComparisonSnapshot,
            .noiseMeasurementSnapshot,
            .masteringAnalysisSnapshot
        ])
        #expect(finalMasterSnapshot.audioAnalysis == nil)
        #expect(finalMasterSnapshot.masteringAnalysis != nil)
        #expect(finalMasterSnapshot.audioMetrics.completionReportAnalysis.displayWaveform.isEmpty == false)
    }

    @Test
    func rawRemixPurposeIsRecordedWithoutInferringOptionalMeasurements() async throws {
        let request = StemAudioEvaluationRequest(
            purpose: .rawRemix,
            includeAudioAnalyzerSnapshot: false,
            includeMasteringAnalysisSnapshot: false
        )

        let snapshot = try await StemAudioEvaluationService.evaluate(
            signal: Self.makeSignal(),
            request: request
        )

        #expect(snapshot.purpose == .rawRemix)
        #expect(snapshot.completedMeasurements == [
            .audioComparisonSnapshot,
            .noiseMeasurementSnapshot
        ])
        #expect(snapshot.audioAnalysis == nil)
        #expect(snapshot.masteringAnalysis == nil)
    }

    @Test
    func authoritative44100SignalUsesTheShared48000AnalysisCopy() async throws {
        let authoritative = Self.makeSignal(duration: 1.6, sampleRate: 44_100)
        let originalChannels = authoritative.channels
        let analysisCopy = try AudioSignalSampleRateConverter.convert(authoritative, to: 48_000)
        let request = StemAudioEvaluationRequest(
            purpose: .rawStem(role: .vocals),
            includeAudioAnalyzerSnapshot: true,
            includeMasteringAnalysisSnapshot: true
        )

        let fromAuthoritative = try await StemAudioEvaluationService.evaluate(
            signal: authoritative,
            request: request
        )
        let fromExplicitCopy = try await StemAudioEvaluationService.evaluate(
            signal: analysisCopy,
            request: request
        )

        #expect(authoritative.sampleRate == 44_100)
        #expect(authoritative.channels == originalChannels)
        #expect(fromAuthoritative.audioMetrics.integratedLoudnessLUFS.bitPattern
            == fromExplicitCopy.audioMetrics.integratedLoudnessLUFS.bitPattern)
        #expect(fromAuthoritative.audioMetrics.truePeakDBFS.bitPattern
            == fromExplicitCopy.audioMetrics.truePeakDBFS.bitPattern)
        #expect(fromAuthoritative.audioMetrics.loudnessRangeLU?.bitPattern
            == fromExplicitCopy.audioMetrics.loudnessRangeLU?.bitPattern)
        #expect(fromAuthoritative.noiseMeasurements == fromExplicitCopy.noiseMeasurements)
    }

    @Test
    func invalidSignalThrowsInsteadOfReturningFabricatedMeasurements() async {
        let request = StemAudioEvaluationRequest(
            purpose: .correctedPureSum,
            includeAudioAnalyzerSnapshot: false,
            includeMasteringAnalysisSnapshot: true
        )
        let signal = AudioSignal(channels: [[]], sampleRate: 48_000)

        do {
            _ = try await StemAudioEvaluationService.evaluate(signal: signal, request: request)
            Issue.record("空の音声を測定済みsnapshotとして返してはいけません")
        } catch let error as StemAudioEvaluationError {
            #expect(error == .emptySignal)
        } catch {
            Issue.record("想定外のエラーです: \(error)")
        }
    }

    @Test
    func evaluationStopsWhenCancelled() async {
        let request = StemAudioEvaluationRequest(
            purpose: .rawStem(role: .vocals),
            includeAudioAnalyzerSnapshot: true,
            includeMasteringAnalysisSnapshot: true
        )
        let task = Task.detached(priority: .utility) {
            try await StemAudioEvaluationService.evaluate(
                signal: Self.makeSignal(duration: 8),
                request: request
            )
        }

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("キャンセル済みのStem評価は完了snapshotを返してはいけません")
        } catch is CancellationError {
            // Expected.
        } catch {
            Issue.record("CancellationError以外が返りました: \(error)")
        }
    }

    @Test
    func evaluationPurposesPreserveRawAndCorrectedStemRolesInMemory() {
        let purposes = [
            StemAudioEvaluationPurpose.rawStem(role: .drums),
            .correctedStem(role: .vocals),
            .correctedPureSum,
        ]

        #expect(purposes == [.rawStem(role: .drums), .correctedStem(role: .vocals), .correctedPureSum])
        #expect(StemAudioEvaluationPurpose.canonicalInput.includesCompletionReportAnalysis)
        #expect(StemAudioEvaluationPurpose.remix.includesCompletionReportAnalysis)
        #expect(StemAudioEvaluationPurpose.finalMaster.includesCompletionReportAnalysis)
        #expect(!StemAudioEvaluationPurpose.rawStem(role: .drums).includesCompletionReportAnalysis)
        #expect(!StemAudioEvaluationPurpose.correctedStem(role: .vocals).includesCompletionReportAnalysis)
        #expect(!StemAudioEvaluationPurpose.rawRemix.includesCompletionReportAnalysis)
        #expect(!StemAudioEvaluationPurpose.correctedPureSum.includesCompletionReportAnalysis)
    }

    @Test
    func selectedAnalysisModeStaysWithTheCurrentEvaluationRequest() async throws {
        let request = StemAudioEvaluationRequest(
            purpose: .canonicalInput,
            includeAudioAnalyzerSnapshot: true,
            includeMasteringAnalysisSnapshot: false,
            analysisMode: .cpu
        )

        let snapshot = try await StemAudioEvaluationService.evaluate(
            signal: Self.makeSignal(),
            request: request
        )
        #expect(snapshot.request.analysisMode == .cpu)
        #expect(snapshot.audioAnalysis != nil)
        #expect(
            StemAudioAnalysisMode.experimentalMetal.resolvedAudioAnalysisMode
                == AudioAnalysisMode.experimentalMetal.resolvedMode
        )
    }

    private static func makeSignal(
        duration: Double = 0.5,
        sampleRate: Double = 48_000
    ) -> AudioSignal {
        let frameCount = Int(sampleRate * duration)
        let left = (0..<frameCount).map { frameIndex in
            let time = Double(frameIndex) / sampleRate
            return Float(
                sin(2 * Double.pi * 440 * time) * 0.10
                    + sin(2 * Double.pi * 7_000 * time) * 0.01
            )
        }
        let right = (0..<frameCount).map { frameIndex in
            let time = Double(frameIndex) / sampleRate
            return Float(
                sin(2 * Double.pi * 440 * time + 0.1) * 0.09
                    + sin(2 * Double.pi * 12_000 * time) * 0.005
            )
        }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }
}
