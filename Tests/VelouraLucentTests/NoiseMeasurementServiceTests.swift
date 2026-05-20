import Foundation
import Testing
@testable import VelouraLucent

struct NoiseMeasurementServiceTests {
    @Test
    func detectsHumProminenceWithoutTreatingAllLowEnergyAsHum() {
        let clean = testSignal { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let lowInstrument = sin(2 * Double.pi * 82 * time) * 0.04
            return Float(tone + lowInstrument)
        }
        let hum = testSignal { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let noise = sin(2 * Double.pi * 60 * time) * 0.025
            return Float(tone + noise)
        }

        let cleanValue = value("hum", in: NoiseMeasurementService.analyze(signal: clean))
        let humValue = value("hum", in: NoiseMeasurementService.analyze(signal: hum))

        #expect(cleanValue < 6)
        #expect(humValue > cleanValue + 4)
    }

    @Test
    func humMeasurementPreservesKnownFixtureValues() {
        let clean = testSignal { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let lowInstrument = sin(2 * Double.pi * 82 * time) * 0.04
            return Float(tone + lowInstrument)
        }
        let hum = testSignal { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let noise = sin(2 * Double.pi * 60 * time) * 0.025
            return Float(tone + noise)
        }

        let cleanValue = value("hum", in: NoiseMeasurementService.analyze(signal: clean, ids: [NoiseMeasurementID.hum]))
        let humValue = value("hum", in: NoiseMeasurementService.analyze(signal: hum, ids: [NoiseMeasurementID.hum]))

        #expect(abs(cleanValue - 0.0) < 0.0001)
        #expect(abs(humValue - 27.21716346666377) < 0.0001)
    }

    @Test
    func humSineFrequencyPlanSharesDuplicateFrameFrequencies() {
        let sampleRate = 48_000.0
        let harmonics = [
            50.0, 100.0, 150.0, 200.0, 250.0, 300.0, 350.0,
            60.0, 120.0, 180.0, 240.0, 300.0, 360.0
        ]

        let plan = HumSineFrequencyPlan(frequencies: harmonics, sampleRate: sampleRate)

        #expect(harmonics.count * 5 == 65)
        #expect(plan.uniqueMeasurementFrequencies.count == 56)
        #expect(plan.measurementFrequenciesByHarmonic[300]?.center == 300)
        #expect(plan.measurementFrequenciesByHarmonic[300]?.surrounding == [277, 283, 317, 323])
    }

    @Test
    func detectsSibilanceAsShortPeakExcess() {
        let smooth = testSignal { time in
            Float(sin(2 * Double.pi * 440 * time) * 0.08)
        }
        let spiky = testSignal { time in
            let base = sin(2 * Double.pi * 440 * time) * 0.08
            let gate = Int(time * 12) % 6 == 0 ? 1.0 : 0.0
            let spike = sin(2 * Double.pi * 7_000 * time) * 0.05 * gate
            return Float(base + spike)
        }

        let smoothValue = value("sibilance", in: NoiseMeasurementService.analyze(signal: smooth))
        let spikyValue = value("sibilance", in: NoiseMeasurementService.analyze(signal: spiky))

        #expect(spikyValue > smoothValue + 4)
    }

    @Test
    func detectsShimmerAsUpperHighShortPeakExcess() {
        let smooth = testSignal { time in
            Float(sin(2 * Double.pi * 440 * time) * 0.08)
        }
        let shimmering = testSignal { time in
            let base = sin(2 * Double.pi * 440 * time) * 0.08
            let shimmer = sin(2 * Double.pi * 12_000 * time) * 0.01
            return Float(base + shimmer)
        }

        let smoothValue = value("shimmer", in: NoiseMeasurementService.analyze(signal: smooth))
        let shimmerValue = value("shimmer", in: NoiseMeasurementService.analyze(signal: shimmering))

        #expect(shimmerValue > smoothValue + 4)
    }

    @Test
    func measuredLevelsReflectActualFileLevel() {
        let base = testSignal { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let hiss = sin(2 * Double.pi * 12_000 * time) * 0.006
            return Float(tone + hiss)
        }
        let louder = AudioSignal(
            channels: [base.channels[0].map { $0 * 2 }],
            sampleRate: base.sampleRate
        )

        let baseHiss = value("hiss", in: NoiseMeasurementService.analyze(signal: base))
        let louderHiss = value("hiss", in: NoiseMeasurementService.analyze(signal: louder))

        #expect(louderHiss > baseHiss + 5.0)
    }

    @Test
    func partialMeasurementMatchesFullMeasurementForRequestedIDs() throws {
        let signal = testSignal { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let hiss = sin(2 * Double.pi * 12_000 * time) * 0.006
            let rumble = sin(2 * Double.pi * 80 * time) * 0.02
            return Float(tone + hiss + rumble)
        }

        let ids = [NoiseMeasurementID.hiss, NoiseMeasurementID.mud, NoiseMeasurementID.rumble]
        let full = NoiseMeasurementService.analyze(signal: signal)
        let partial = NoiseMeasurementService.analyze(signal: signal, ids: ids)

        #expect(partial.values.map(\.id) == ids)
        #expect(partial.value(for: NoiseMeasurementID.sibilance) == nil)
        for id in ids {
            let fullValue = try #require(full.comparableLevel(for: id))
            let partialValue = try #require(partial.comparableLevel(for: id))
            #expect(abs(fullValue - partialValue) < 0.0001)
        }
    }

    @Test
    func cancellableMeasurementStopsWhenTaskIsCancelled() async {
        let signal = testSignal(duration: 8) { time in
            let tone = sin(2 * Double.pi * 440 * time) * 0.08
            let hiss = sin(2 * Double.pi * 12_000 * time) * 0.006
            let rumble = sin(2 * Double.pi * 80 * time) * 0.02
            return Float(tone + hiss + rumble)
        }
        let task = Task.detached(priority: .utility) {
            try NoiseMeasurementService.analyzeCancellable(signal: signal)
        }

        task.cancel()

        do {
            _ = try await task.value
            Issue.record("キャンセル済みのノイズ測定は完了せず CancellationError を返す必要があります")
        } catch is CancellationError {
            return
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
    }

    private func value(_ id: String, in snapshot: NoiseMeasurementSnapshot) -> Double {
        snapshot.value(for: id)?.comparableLevelDB ?? -120
    }

    private func testSignal(duration: Double = 2, _ sample: (Double) -> Float) -> AudioSignal {
        let sampleRate = 48_000.0
        let frameCount = Int(sampleRate * duration)
        let channel = (0..<frameCount).map { index in
            sample(Double(index) / sampleRate)
        }
        return AudioSignal(channels: [channel], sampleRate: sampleRate)
    }
}
