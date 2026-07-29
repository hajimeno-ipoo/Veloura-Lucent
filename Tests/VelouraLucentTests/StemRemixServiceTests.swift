import Foundation
import Testing
@testable import VelouraLucent

struct StemRemixServiceTests {
    private let service = StemRemixService()

    @Test
    func neutralSettingsMatchThePureSumWithoutMasteringProcessing() throws {
        let stems = makeStems()
        let result = try service.render(
            stems: stems,
            settings: StemRemixSettings()
        )
        let pure = try StemMixService().pureSum(stems: stems.map {
            StemMixInput(role: $0.role, signal: $0.corrected)
        }).signal

        #expect(result.signal.channels == pure.channels)
        #expect(result.drySignal.channels == pure.channels)
        #expect(result.reverbReturn.channels.allSatisfy {
            $0.allSatisfy { $0 == 0 }
        })
    }

    @Test
    func renderReportsTheExistingAudioStagesInProcessingOrder() throws {
        let recorder = StemRemixStageRecorder()

        _ = try service.render(
            stems: makeStems(),
            settings: StemRemixSettings()
        ) { stage, state in
            recorder.append(stage: stage, state: state)
        }

        #expect(recorder.values() == StemRemixRenderStage.allCases.flatMap {
            [
                StemRemixStageEvent(stage: $0, state: .running),
                StemRemixStageEvent(stage: $0, state: .completed),
            ]
        })
    }

    @Test
    func automaticGainCompensatesOnlyTheMeasuredRawToCorrectedDifference() throws {
        let stems = makeStems(correctedScale: 0.5)
        let plan = try service.makeAutomaticPlan(stems: stems)

        for role in StemRole.allCases {
            #expect(abs(plan.gainEvidenceDB[role, default: 0] - 6.0206) < 0.05)
            #expect(plan.settings.settings(for: role).gainDB == 6)
            #expect(abs(plan.settings.settings(for: role).pan) < 0.001)
        }
    }

    @Test
    func manualOverridesReplaceOnlyTheEditedAutomaticFields() {
        var automatic = StemRemixSettings(
            roleValues: [
                .drums: StemRemixRoleSettings(gainDB: 2, pan: -0.2, reverbSend: 0.1),
            ],
            masking: StemRemixMaskingSettings(
                drumsToBassEnabled: true,
                drumsToBassAmount: 0.2,
                vocalsToOtherEnabled: true,
                vocalsToOtherAmount: 0.1
            ),
            reverbReturnLevel: 0.15,
            reverbDecaySeconds: 1.6
        )
        automatic.setSettings(
            StemRemixRoleSettings(gainDB: -1, pan: 0.1, reverbSend: 0.05),
            for: .vocals
        )
        var overrides = StemRemixManualOverrides()
        overrides.setOverrides(
            StemRemixRoleOverrides(gainDB: nil, pan: 0.5, reverbSend: nil),
            for: .drums
        )
        overrides.reverbReturnLevel = 0.25
        overrides.drumsToBassEnabled = false

        let effective = overrides.applying(to: automatic)

        #expect(effective.settings(for: .drums).gainDB == 2)
        #expect(effective.settings(for: .drums).pan == 0.5)
        #expect(effective.settings(for: .drums).reverbSend == 0.1)
        #expect(effective.settings(for: .vocals) == automatic.settings(for: .vocals))
        #expect(!effective.masking.drumsToBassEnabled)
        #expect(effective.masking.drumsToBassAmount == 0.2)
        #expect(effective.masking.vocalsToOtherEnabled)
        #expect(effective.masking.vocalsToOtherAmount == 0.1)
        #expect(effective.reverbReturnLevel == 0.25)
        #expect(effective.reverbDecaySeconds == 1.6)
    }

    @Test
    func automaticPanRequiresAStableChangeOutsideTheCenterDisplayRange() throws {
        let subtlePlan = try service.makeAutomaticPlan(
            stems: makePanStems { _ in (1, 0.996) }
        )
        let stablePlan = try service.makeAutomaticPlan(
            stems: makePanStems { _ in (1, 0.8) }
        )
        let unstablePlan = try service.makeAutomaticPlan(
            stems: makePanStems { index in
                index < 4_800 ? (1, 0.8) : (0.8, 1)
            }
        )

        #expect(abs(subtlePlan.panEvidence[.vocals, default: 0]) < 0.005)
        #expect(subtlePlan.settings.settings(for: .vocals).pan == 0)
        #expect(stablePlan.panEvidence[.vocals, default: 0] > 0.05)
        #expect(stablePlan.settings.settings(for: .vocals).pan > 0.05)
        #expect(unstablePlan.settings.settings(for: .vocals).pan == 0)
    }

    @Test
    func maskingChangesOnlyAnActiveCollisionAndLeavesSilentTriggerUnchanged() throws {
        let active = makeCollisionStems(triggerIsSilent: false)
        let silent = makeCollisionStems(triggerIsSilent: true)
        let settings = StemRemixSettings(
            masking: StemRemixMaskingSettings(
                drumsToBassEnabled: true,
                drumsToBassAmount: 0.4,
                vocalsToOtherAmount: 0
            )
        )

        let activeResult = try service.render(stems: active, settings: settings)
        let silentResult = try service.render(stems: silent, settings: settings)
        let silentPure = try StemMixService().pureSum(stems: silent.map {
            StemMixInput(role: $0.role, signal: $0.corrected)
        }).signal
        let activePure = try StemMixService().pureSum(
            stems: active.map {
                StemMixInput(role: $0.role, signal: $0.corrected)
            }
        ).signal

        #expect(activeResult.signal.channels != activePure.channels)
        #expect(silentResult.signal.channels == silentPure.channels)
    }

    @Test
    func maskingCanBeDisabledWithoutDiscardingItsAmount() throws {
        let stems = makeCollisionStems(triggerIsSilent: false)
        let settings = StemRemixSettings(
            masking: StemRemixMaskingSettings(
                drumsToBassEnabled: false,
                drumsToBassAmount: 0.4
            )
        )

        let result = try service.render(stems: stems, settings: settings)
        let pure = try StemMixService().pureSum(stems: stems.map {
            StemMixInput(role: $0.role, signal: $0.corrected)
        }).signal

        #expect(settings.masking.drumsToBassAmount == 0.4)
        #expect(result.signal.channels == pure.channels)
    }

    @Test
    func maskingReadsTheGainedSignalBeforePan() throws {
        let stems = makeOrderSensitiveStems()
        var enabled = StemRemixSettings(
            masking: StemRemixMaskingSettings(
                drumsToBassEnabled: true,
                drumsToBassAmount: 0.4
            )
        )
        enabled.setSettings(
            StemRemixRoleSettings(pan: 1),
            for: .drums
        )
        var disabled = enabled
        disabled.masking.drumsToBassEnabled = false

        let enabledResult = try service.render(stems: stems, settings: enabled)
        let disabledResult = try service.render(stems: stems, settings: disabled)

        #expect(enabledResult.signal.channels == disabledResult.signal.channels)
    }

    @Test
    func oneSharedReverbReturnUsesEveryStemSendAndStaysFinite() throws {
        let stems = makeStems()
        var settings = StemRemixSettings(
            reverbReturnLevel: 0.3,
            reverbDecaySeconds: 1.4
        )
        for role in StemRole.allCases {
            settings.setSettings(
                StemRemixRoleSettings(reverbSend: 0.2),
                for: role
            )
        }

        let result = try service.render(stems: stems, settings: settings)

        #expect(result.reverbReturn.channels.contains {
            $0.contains(where: { abs($0) > 1e-7 })
        })
        #expect(result.signal.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        #expect(result.signal.channels != result.drySignal.channels)
    }

    @Test
    func missingDuplicateAndNonFiniteStemsAreRejected() {
        let stems = makeStems()
        #expect(throws: StemRemixServiceError.missingRole(.vocals)) {
            try service.render(
                stems: stems.filter { $0.role != .vocals },
                settings: StemRemixSettings()
            )
        }

        #expect(throws: StemRemixServiceError.duplicateRole(.drums)) {
            try service.render(
                stems: stems + [stems[0]],
                settings: StemRemixSettings()
            )
        }

        var invalid = stems
        var channels = invalid[1].corrected.channels
        channels[0][10] = .nan
        invalid[1] = StemRemixSignal(
            role: .bass,
            raw: invalid[1].raw,
            corrected: AudioSignal(channels: channels, sampleRate: 48_000)
        )
        #expect(throws: StemRemixServiceError.invalidSignal(.bass)) {
            try service.render(stems: invalid, settings: StemRemixSettings())
        }
    }

    private func makeStems(
        frameCount: Int = 9_600,
        correctedScale: Float = 1
    ) -> [StemRemixSignal] {
        StemRole.allCases.enumerated().map { roleIndex, role in
            let frequency = Double(90 + roleIndex * 170)
            let left = (0..<frameCount).map { index -> Float in
                Float(sin(2 * .pi * frequency * Double(index) / 48_000)) * 0.08
            }
            let right = (0..<frameCount).map { index -> Float in
                Float(sin(2 * .pi * frequency * Double(index) / 48_000 + 0.08)) * 0.08
            }
            let raw = AudioSignal(channels: [left, right], sampleRate: 48_000)
            let corrected = AudioSignal(
                channels: raw.channels.map { $0.map { $0 * correctedScale } },
                sampleRate: raw.sampleRate
            )
            return StemRemixSignal(role: role, raw: raw, corrected: corrected)
        }
    }

    private func makeCollisionStems(triggerIsSilent: Bool) -> [StemRemixSignal] {
        let frameCount = 9_600
        return StemRole.allCases.map { role in
            let frequency: Double = switch role {
            case .drums, .bass: 80
            case .other: 300
            case .vocals: 600
            }
            let amplitude: Float = role == .drums && triggerIsSilent ? 0 : 0.1
            let samples = (0..<frameCount).map { index -> Float in
                let pulse = index % 2_400 < 1_200 ? 1.0 : 0.0
                return Float(sin(2 * .pi * frequency * Double(index) / 48_000))
                    * amplitude * Float(pulse)
            }
            let signal = AudioSignal(channels: [samples, samples], sampleRate: 48_000)
            return StemRemixSignal(role: role, raw: signal, corrected: signal)
        }
    }

    private func makePanStems(
        correctedScales: (Int) -> (left: Float, right: Float)
    ) -> [StemRemixSignal] {
        var stems = makeStems()
        let frameCount = stems[0].raw.frameCount
        let samples = (0..<frameCount).map { index -> Float in
            Float(sin(2 * .pi * 220 * Double(index) / 48_000)) * 0.1
        }
        let correctedLeft = samples.indices.map {
            samples[$0] * correctedScales($0).left
        }
        let correctedRight = samples.indices.map {
            samples[$0] * correctedScales($0).right
        }
        let raw = AudioSignal(channels: [samples, samples], sampleRate: 48_000)
        let corrected = AudioSignal(
            channels: [correctedLeft, correctedRight],
            sampleRate: 48_000
        )
        guard let vocalsIndex = stems.firstIndex(where: { $0.role == .vocals }) else {
            preconditionFailure("vocals fixture is required")
        }
        stems[vocalsIndex] = StemRemixSignal(
            role: .vocals,
            raw: raw,
            corrected: corrected
        )
        return stems
    }

    private func makeOrderSensitiveStems() -> [StemRemixSignal] {
        let frameCount = 9_600
        let tone = (0..<frameCount).map { index -> Float in
            Float(sin(2 * .pi * 80 * Double(index) / 48_000)) * 0.1
        }
        let silence = Array(repeating: Float.zero, count: frameCount)
        return StemRole.allCases.map { role in
            let channels: [[Float]] = switch role {
            case .drums:
                [tone, tone.map { -$0 }]
            case .bass:
                [tone, tone]
            case .vocals, .other:
                [silence, silence]
            }
            let signal = AudioSignal(channels: channels, sampleRate: 48_000)
            return StemRemixSignal(role: role, raw: signal, corrected: signal)
        }
    }
}

private struct StemRemixStageEvent: Equatable {
    let stage: StemRemixRenderStage
    let state: StemRemixRenderStageState
}

private final class StemRemixStageRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StemRemixStageEvent] = []

    func append(stage: StemRemixRenderStage, state: StemRemixRenderStageState) {
        lock.lock()
        storage.append(StemRemixStageEvent(stage: stage, state: state))
        lock.unlock()
    }

    func values() -> [StemRemixStageEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
