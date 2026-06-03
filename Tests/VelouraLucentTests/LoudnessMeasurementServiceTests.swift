import Foundation
import Testing
@testable import VelouraLucent

struct LoudnessMeasurementServiceTests {
    @Test
    func sameWaveformProducesSameLoudness() throws {
        let signal = sineSignal(amplitude: 0.1, duration: 2.0)

        let first = LoudnessMeasurementService.measure(signal: signal)
        let second = LoudnessMeasurementService.measure(signal: signal)

        expectClose(first.integratedLoudnessLUFS, second.integratedLoudnessLUFS, tolerance: 0.0001)
        expectClose(first.truePeakDBFS, second.truePeakDBFS, tolerance: 0.0001)
        expectClose(try #require(first.loudnessRangeLU), try #require(second.loudnessRangeLU), tolerance: 0.0001)
    }

    @Test
    func silenceIsGatedOutOfIntegratedLoudness() {
        let sampleRate = 48_000.0
        let tone = sineSamples(amplitude: 0.1, duration: 1.0, sampleRate: sampleRate)
        let withSilence = tone + Array(repeating: Float.zero, count: Int(sampleRate * 2.0))

        let toneOnly = LoudnessMeasurementService.measure(signal: AudioSignal(channels: [tone], sampleRate: sampleRate))
        let mixed = LoudnessMeasurementService.measure(signal: AudioSignal(channels: [withSilence], sampleRate: sampleRate))

        expectClose(mixed.integratedLoudnessLUFS, toneOnly.integratedLoudnessLUFS, tolerance: 1.0)
    }

    @Test
    func stereoEnergyIsSummedForLoudness() {
        let mono = sineSignal(amplitude: 0.1, duration: 2.0)
        let stereo = AudioSignal(channels: [mono.channels[0], mono.channels[0]], sampleRate: mono.sampleRate)

        let monoMeasurement = LoudnessMeasurementService.measure(signal: mono)
        let stereoMeasurement = LoudnessMeasurementService.measure(signal: stereo)

        expectClose(stereoMeasurement.integratedLoudnessLUFS - monoMeasurement.integratedLoudnessLUFS, 3.0, tolerance: 0.2)
    }

    @Test
    func truePeakUsesInterpolatedSamples() {
        let channels: [[Float]] = [
            [0, 0.12, -0.37, 0.52, -0.18, 0.04, -0.09],
            [0.08, -0.16, 0.24, -0.31, 0.18, -0.02, 0.01]
        ]

        let samplePeak = channels.flatMap { $0 }.map { abs($0) }.max() ?? 0
        let truePeak = LoudnessMeasurementService.truePeakLinear(channels)

        #expect(truePeak >= samplePeak)
        #expect(truePeak == MasteringAnalysisService.approximateTruePeak(channels))
    }

    @Test
    func lraSeparatesFlatAndChangingMaterial() throws {
        let flat = sineSignal(amplitude: 0.1, duration: 10.0)
        let changing = levelSequenceSignal(amplitudes: [0.1, 0.01], durations: [20, 20])

        let flatLRA = LoudnessMeasurementService.loudnessRange(signal: flat)
        let changingLRA = LoudnessMeasurementService.loudnessRange(signal: changing)

        #expect(try #require(flatLRA) < 2.0)
        #expect(try #require(changingLRA) > (try #require(flatLRA)) + 3.0)
    }

    @Test
    func officialLRAStaysWithinEBUMinimumRequirementExamples() throws {
        let cases: [(amplitudes: [Float], durations: [Double], expected: Double)] = [
            ([0.1, 0.031622775], [20, 20], 10),
            ([0.1, 0.17782794], [20, 20], 5),
            ([0.01, 0.1], [20, 20], 20),
            ([0.0031622777, 0.017782794, 0.1, 0.017782794, 0.0031622777], [20, 20, 20, 20, 20], 15)
        ]

        for testCase in cases {
            let lra = LoudnessMeasurementService.loudnessRange(
                signal: levelSequenceSignal(amplitudes: testCase.amplitudes, durations: testCase.durations)
            )
            expectClose(try #require(lra), testCase.expected, tolerance: 1)
        }
    }

    @Test
    func officialLRAReturnsNilWhenMeasurementConditionsAreUnavailable() {
        let shortSignal = sineSignal(amplitude: 0.1, duration: 1.49)
        let non48kHzSignal = AudioSignal(channels: [shortSignal.channels[0]], sampleRate: 44_100)
        let threeChannelSignal = AudioSignal(
            channels: [shortSignal.channels[0], shortSignal.channels[0], shortSignal.channels[0]],
            sampleRate: shortSignal.sampleRate
        )

        #expect(LoudnessMeasurementService.loudnessRange(signal: AudioSignal(channels: [], sampleRate: 48_000)) == nil)
        #expect(LoudnessMeasurementService.loudnessRange(signal: shortSignal) == nil)
        #expect(LoudnessMeasurementService.loudnessRange(signal: non48kHzSignal) == nil)
        #expect(LoudnessMeasurementService.loudnessRange(signal: threeChannelSignal) == nil)
    }

    @Test
    func officialLRASupports48kHzMonoAndStereo() {
        let mono = sineSignal(amplitude: 0.1, duration: 2.0)
        let stereo = AudioSignal(channels: [mono.channels[0], mono.channels[0]], sampleRate: mono.sampleRate)

        #expect(LoudnessMeasurementService.loudnessRange(signal: mono) != nil)
        #expect(LoudnessMeasurementService.loudnessRange(signal: stereo) != nil)
    }

    @Test
    func integratedLoudnessOnlyMatchesFullMeasurement() {
        let mono = sineSignal(amplitude: 0.1, duration: 2.0)
        let signals = [
            AudioSignal(channels: [], sampleRate: 48_000),
            AudioSignal(channels: [[]], sampleRate: 48_000),
            mono,
            AudioSignal(channels: [mono.channels[0], mono.channels[0]], sampleRate: mono.sampleRate),
            changingLevelSignal()
        ]

        for signal in signals {
            let fullMeasurement = LoudnessMeasurementService.measure(signal: signal)
            let loudnessOnly = LoudnessMeasurementService.integratedLoudness(signal: signal)

            #expect(loudnessOnly.bitPattern == Float(fullMeasurement.integratedLoudnessLUFS).bitPattern)
        }
    }

    @Test
    func fullMeasurementCanSkipLoudnessRange() {
        let signal = sineSignal(amplitude: 0.1, duration: 2.0)

        let measurement = LoudnessMeasurementService.measure(signal: signal, includeLoudnessRange: false)

        #expect(measurement.loudnessRangeLU == nil)
    }

    private func changingLevelSignal() -> AudioSignal {
        let sampleRate = 48_000.0
        let quiet = sineSamples(amplitude: 0.01, duration: 2.0, sampleRate: sampleRate)
        let loud = sineSamples(amplitude: 0.5, duration: 2.0, sampleRate: sampleRate)
        return AudioSignal(channels: [quiet + loud], sampleRate: sampleRate)
    }

    private func sineSignal(amplitude: Float, duration: Double) -> AudioSignal {
        let sampleRate = 48_000.0
        return AudioSignal(channels: [sineSamples(amplitude: amplitude, duration: duration, sampleRate: sampleRate)], sampleRate: sampleRate)
    }

    private func levelSequenceSignal(amplitudes: [Float], durations: [Double]) -> AudioSignal {
        let sampleRate = 48_000.0
        let samples = zip(amplitudes, durations).flatMap {
            sineSamples(amplitude: $0, duration: $1, sampleRate: sampleRate, frequency: 1_000)
        }
        return AudioSignal(channels: [samples, samples], sampleRate: sampleRate)
    }

    private func sineSamples(amplitude: Float, duration: Double, sampleRate: Double, frequency: Double = 440) -> [Float] {
        let frameCount = Int(sampleRate * duration)
        return (0..<frameCount).map { index in
            Float(sin(2 * Double.pi * frequency * Double(index) / sampleRate)) * amplitude
        }
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
