import Foundation
import Testing
@testable import VelouraLucent

struct LoudnessMeasurementServiceTests {
    @Test
    func sameWaveformProducesSameLoudness() {
        let signal = sineSignal(amplitude: 0.1, duration: 2.0)

        let first = LoudnessMeasurementService.measure(signal: signal)
        let second = LoudnessMeasurementService.measure(signal: signal)

        expectClose(first.integratedLoudnessLUFS, second.integratedLoudnessLUFS, tolerance: 0.0001)
        expectClose(first.truePeakDBFS, second.truePeakDBFS, tolerance: 0.0001)
        expectClose(first.loudnessRangeLU, second.loudnessRangeLU, tolerance: 0.0001)
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
    func lraSeparatesFlatAndChangingMaterial() {
        let flat = sineSignal(amplitude: 0.1, duration: 4.0)
        let changing = changingLevelSignal()

        let flatLRA = LoudnessMeasurementService.measure(signal: flat).loudnessRangeLU
        let changingLRA = LoudnessMeasurementService.measure(signal: changing).loudnessRangeLU

        #expect(flatLRA < 0.5)
        #expect(changingLRA > flatLRA + 3.0)
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

    private func sineSamples(amplitude: Float, duration: Double, sampleRate: Double) -> [Float] {
        let frameCount = Int(sampleRate * duration)
        return (0..<frameCount).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / sampleRate)) * amplitude
        }
    }

    private func expectClose(_ actual: Double, _ expected: Double, tolerance: Double) {
        #expect(abs(actual - expected) <= tolerance)
    }
}
