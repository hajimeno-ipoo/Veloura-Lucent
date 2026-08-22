import Foundation
import Testing
@testable import VelouraLucent

struct CompletionReportAudioAnalysisServiceTests {
    @Test
    func estimatesTempoFromRegularTransientPulses() throws {
        let sampleRate = 1_000.0
        let duration = 20
        var mono = Array(repeating: Float.zero, count: Int(sampleRate) * duration)
        let beatInterval = Int(sampleRate * 0.5)
        for start in stride(from: 0, to: mono.count, by: beatInterval) {
            for offset in 0..<20 where start + offset < mono.count {
                mono[start + offset] = 0.9
            }
        }

        let analysis = CompletionReportAudioAnalysisService.analyze(
            signal: AudioSignal(channels: [mono, mono], sampleRate: sampleRate),
            mono: mono,
            averageSpectrum: []
        )

        let tempo = try #require(analysis.estimatedTempoBPM)
        #expect(abs(tempo - 120) < 1)
        #expect(analysis.tempoConfidence >= 0.18)
    }

    @Test
    func weakEvidenceDoesNotInventTempoOrKey() {
        let silence = Array(repeating: Float.zero, count: 10_000)
        let analysis = CompletionReportAudioAnalysisService.analyze(
            signal: AudioSignal(channels: [silence, silence], sampleRate: 1_000),
            mono: silence,
            averageSpectrum: []
        )

        #expect(analysis.estimatedTempoBPM == nil)
        #expect(analysis.estimatedKey == nil)
    }

    @Test
    func estimatesKeyFromAStableMajorPitchClassProfile() {
        let spectrum = [
            SpectrumMetric(id: "c3", frequencyHz: 130.81, levelDB: -3),
            SpectrumMetric(id: "e3", frequencyHz: 164.81, levelDB: -7),
            SpectrumMetric(id: "g3", frequencyHz: 196.00, levelDB: -5),
            SpectrumMetric(id: "c4", frequencyHz: 261.63, levelDB: -6),
            SpectrumMetric(id: "e4", frequencyHz: 329.63, levelDB: -10),
            SpectrumMetric(id: "g4", frequencyHz: 392.00, levelDB: -8)
        ]
        let samples = Array(repeating: Float(0.1), count: 10_000)
        let analysis = CompletionReportAudioAnalysisService.analyze(
            signal: AudioSignal(channels: [samples], sampleRate: 1_000),
            mono: samples,
            averageSpectrum: spectrum
        )

        #expect(analysis.estimatedKey == "Cメジャー")
        #expect(analysis.keyConfidence >= 0.12)
    }

    @Test
    func reportsStableLowBandCorrelationAndSideMidRatio() throws {
        let sampleRate = 2_000.0
        let frames = 4_000
        let angularStep = 2 * Double.pi * 80 / sampleRate
        let mono: [Float] = (0..<frames).map { index in
            Float(Foundation.sin(angularStep * Double(index)) * 0.5)
        }
        let analysis = CompletionReportAudioAnalysisService.analyze(
            signal: AudioSignal(channels: [mono, mono], sampleRate: sampleRate),
            mono: mono,
            averageSpectrum: []
        )

        #expect(try #require(analysis.lowBandStereoCorrelation) > 0.999)
        #expect(try #require(analysis.sideMidRatioDB) < -100)
        #expect(try #require(analysis.lowBandSideMidRatioDB) < -100)
        #expect(try #require(analysis.leftRightWaveformCorrelation) > 0.999)
        #expect(!analysis.rms400MillisecondDB.isEmpty)
        #expect(!analysis.displayWaveform.isEmpty)
    }

    @Test
    func countsClippedAndNearPeakSamplesSeparately() {
        let mono: [Float] = [0, 0.5, 0.91, 0.99, 1.0, -1.1]
        let analysis = CompletionReportAudioAnalysisService.analyze(
            signal: AudioSignal(channels: [mono], sampleRate: 10),
            mono: mono,
            averageSpectrum: []
        )

        #expect(analysis.clippedSampleCount == 2)
        #expect(analysis.nearPeakSampleCount == 4)
    }

    @Test
    func injectedCancellationStopsReportAnalysisDuringSampleScanning() {
        let samples = Array(repeating: Float(0.1), count: 100_000)
        var checkCount = 0

        #expect(throws: CancellationError.self) {
            _ = try CompletionReportAudioAnalysisService.analyze(
                signal: AudioSignal(channels: [samples, samples], sampleRate: 48_000),
                mono: samples,
                averageSpectrum: [],
                cancellationCheck: {
                    checkCount += 1
                    if checkCount == 3 {
                        throw CancellationError()
                    }
                }
            )
        }
        #expect(checkCount == 3)
    }
}
