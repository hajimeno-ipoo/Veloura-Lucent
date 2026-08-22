import Foundation
import Testing
@testable import VelouraLucent

struct StemTransientRecoveryServiceTests {
    private let service = StemTransientRecoveryService()

    @Test
    func restoresOnlyMissingRawDrumAttackWithoutExceedingRawSampleEnvelope() throws {
        let raw = makeDrumSignal()
        let corrected = AudioSignal(
            channels: raw.channels.map {
                SpectralDSP.lowPass($0, cutoff: 900, sampleRate: raw.sampleRate)
            },
            sampleRate: raw.sampleRate
        )

        let recovered = try service.recover(
            role: .drums,
            rawSignal: raw,
            correctedSignal: corrected
        )

        #expect(recovered.channels != corrected.channels)
        for channelIndex in recovered.channels.indices {
            for frameIndex in recovered.channels[channelIndex].indices {
                #expect(
                    abs(recovered.channels[channelIndex][frameIndex])
                        <= max(
                            abs(raw.channels[channelIndex][frameIndex]),
                            abs(corrected.channels[channelIndex][frameIndex])
                        ) + 1e-6
                )
            }
        }
        #expect(transientEnergy(recovered) > transientEnergy(corrected))
        #expect(transientEnergy(recovered) <= transientEnergy(raw) * 1.01)
    }

    @Test
    func doesNotGenerateTransientWhenCorrectedAlreadyMatchesOrExceedsRaw() throws {
        let raw = makeDrumSignal()
        let louder = AudioSignal(
            channels: raw.channels.map { $0.map { $0 * 1.1 } },
            sampleRate: raw.sampleRate
        )

        #expect(try service.recover(
            role: .drums,
            rawSignal: raw,
            correctedSignal: raw
        ).channels == raw.channels)
        #expect(try service.recover(
            role: .drums,
            rawSignal: raw,
            correctedSignal: louder
        ).channels == louder.channels)
    }

    @Test
    func recoveredAttackDoesNotGenerateUltraHighAboveTwentyOneKilohertz() throws {
        let rawBase = makeDrumSignal()
        let raw = addingUltraHighReference(to: rawBase)
        let correctedBase = AudioSignal(
            channels: rawBase.channels.map {
                SpectralDSP.lowPass($0, cutoff: 900, sampleRate: rawBase.sampleRate)
            },
            sampleRate: rawBase.sampleRate
        )
        let corrected = addingUltraHighReference(to: correctedBase)

        let recovered = try service.recover(
            role: .drums,
            rawSignal: raw,
            correctedSignal: corrected
        )

        let correctedUltraHigh = bandLevelDB(corrected, lower: 21_000, upper: 24_000)
        let recoveredUltraHigh = bandLevelDB(recovered, lower: 21_000, upper: 24_000)
        #expect(recoveredUltraHigh <= correctedUltraHigh + 0.25)
        #expect(recoveredUltraHigh >= correctedUltraHigh - 0.25)
        #expect(transientEnergy(recovered) > transientEnergy(corrected))
    }

    @Test
    func leavesNonDrumRolesUnchanged() throws {
        let raw = makeDrumSignal()
        let corrected = AudioSignal(
            channels: raw.channels.map { $0.map { $0 * 0.5 } },
            sampleRate: raw.sampleRate
        )

        for role in [StemRole.vocals, .bass, .other] {
            #expect(try service.recover(
                role: role,
                rawSignal: raw,
                correctedSignal: corrected
            ).channels == corrected.channels)
        }
    }

    @Test
    func rejectsMismatchedStructures() {
        let raw = makeDrumSignal()
        let corrected = AudioSignal(
            channels: [Array(raw.channels[0].dropLast()), raw.channels[1]],
            sampleRate: raw.sampleRate
        )

        #expect(throws: StemTransientRecoveryError.structuralMismatch) {
            try service.recover(
                role: .drums,
                rawSignal: raw,
                correctedSignal: corrected
            )
        }
    }

    private func makeDrumSignal() -> AudioSignal {
        let frameCount = 9_600
        var left = Array(repeating: Float.zero, count: frameCount)
        var right = left
        for onset in stride(from: 600, to: frameCount, by: 2_400) {
            for offset in 0..<160 where onset + offset < frameCount {
                let envelope = exp(-Double(offset) / 32)
                let high = sin(2 * .pi * 4_800 * Double(offset) / 48_000)
                let low = sin(2 * .pi * 120 * Double(offset) / 48_000)
                left[onset + offset] += Float((high * 0.38 + low * 0.18) * envelope)
                right[onset + offset] += Float((high * 0.34 + low * 0.16) * envelope)
            }
        }
        return AudioSignal(channels: [left, right], sampleRate: 48_000)
    }

    private func transientEnergy(_ signal: AudioSignal) -> Double {
        signal.channels.reduce(0.0) { total, channel in
            let band = SpectralDSP.highPass(
                channel,
                cutoff: 1_200,
                sampleRate: signal.sampleRate
            )
            return total + band.reduce(0.0) { $0 + Double($1 * $1) }
        }
    }

    private func addingUltraHighReference(to signal: AudioSignal) -> AudioSignal {
        let channels = signal.channels.map { channel in
            channel.indices.map { index in
                let time = Double(index) / signal.sampleRate
                return channel[index] + Float(sin(2 * .pi * 22_000 * time) * 0.002)
            }
        }
        return AudioSignal(channels: channels, sampleRate: signal.sampleRate)
    }

    private func bandLevelDB(_ signal: AudioSignal, lower: Double, upper: Double) -> Double {
        let spectrogram = SpectralDSP.stft(signal.monoMixdown())
        let frequencyStep = signal.sampleRate / Double(spectrogram.fftSize)
        let lowerBin = max(0, Int(ceil(lower / frequencyStep)))
        let upperBin = min(spectrogram.binCount - 1, Int(floor(upper / frequencyStep)))
        guard lowerBin <= upperBin else { return -120 }

        var energy = 0.0
        var count = 0
        for frameIndex in 0..<spectrogram.frameCount {
            for binIndex in lowerBin...upperBin {
                let magnitude = Double(spectrogram.magnitude(frameIndex: frameIndex, binIndex: binIndex))
                energy += magnitude * magnitude
                count += 1
            }
        }
        return 10 * log10(max(energy / Double(max(count, 1)), 1e-12))
    }
}
