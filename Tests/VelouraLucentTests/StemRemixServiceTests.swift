import Foundation
import Testing
@testable import VelouraLucent

struct StemRemixServiceTests {
    private let service = StemRemixService()

    @Test
    func neutralSettingsMatchThePureSumWithoutMasteringProcessing() throws {
        let stems = makeStems()
        let contract = makeStemTestRunContract()
        let result = try service.render(
            stems: stems,
            settings: StemRemixSettings(),
            runContract: contract
        )
        let pure = try pureSum(stems, runContract: contract)

        #expect(result.signal.channels == pure.channels)
        #expect(result.drySignal.channels == pure.channels)
        #expect(result.reverbReturn.channels.allSatisfy {
            $0.allSatisfy { $0 == 0 }
        })
    }

    @Test
    func bsNeutralSettingsMatchTheSixStemPureSumInContractOrder() throws {
        let contract = makeStemTestRunContract(model: .bsRoformerSW)
        let stems = makeStems(model: .bsRoformerSW)

        let result = try service.render(
            stems: stems,
            settings: StemRemixSettings(),
            runContract: contract
        )
        let pure = try pureSum(stems, runContract: contract)

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
            settings: StemRemixSettings(),
            runContract: makeStemTestRunContract()
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
        let plan = try service.makeAutomaticPlan(
            stems: stems,
            runContract: makeStemTestRunContract()
        )

        for role in StemProductionModelProfile.profile(for: .htdemucs).sourceOrder {
            #expect(abs(plan.gainEvidenceDB[role, default: 0] - 6.0206) < 0.05)
            #expect(plan.settings.settings(for: role).gainDB == 6)
            #expect(abs(plan.settings.settings(for: role).pan) < 0.001)
        }
    }

    @Test
    func bsAutomaticPlanMeasuresAllSixRolesAndKeepsIndependentManualValues() throws {
        let contract = makeStemTestRunContract(model: .bsRoformerSW)
        let stems = makeStems(model: .bsRoformerSW, correctedScale: 0.5)
        let plan = try service.makeAutomaticPlan(
            stems: stems,
            runContract: contract
        )

        #expect(Set(plan.gainEvidenceDB.keys) == Set(contract.validationRoles))
        #expect(Set(plan.panEvidence.keys) == Set(contract.validationRoles))
        #expect(Set(plan.reverbLossEvidence.keys) == Set(contract.validationRoles))
        for role in contract.validationRoles {
            #expect(plan.settings.settings(for: role).gainDB == 6)
        }

        var overrides = StemRemixManualOverrides()
        overrides.setOverrides(
            StemRemixRoleOverrides(gainDB: 2.5, pan: -0.35, reverbSend: 0.22),
            for: .guitar
        )
        overrides.setOverrides(
            StemRemixRoleOverrides(gainDB: -1.5, pan: 0.4, reverbSend: 0.31),
            for: .piano
        )
        let effective = overrides.applying(to: plan.settings)

        #expect(effective.settings(for: .guitar) == StemRemixRoleSettings(
            gainDB: 2.5,
            pan: -0.35,
            reverbSend: 0.22
        ))
        #expect(effective.settings(for: .piano) == StemRemixRoleSettings(
            gainDB: -1.5,
            pan: 0.4,
            reverbSend: 0.31
        ))
        #expect(effective.settings(for: .other) == plan.settings.settings(for: .other))
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
                vocalsToAccompanimentEnabled: true,
                vocalsToAccompanimentAmount: 0.1
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
        #expect(effective.masking.vocalsToAccompanimentEnabled)
        #expect(effective.masking.vocalsToAccompanimentAmount == 0.1)
        #expect(effective.reverbReturnLevel == 0.25)
        #expect(effective.reverbDecaySeconds == 1.6)
    }

    @Test
    func automaticPanRequiresAStableChangeOutsideTheCenterDisplayRange() throws {
        let subtlePlan = try service.makeAutomaticPlan(
            stems: makePanStems { _ in (1, 0.996) },
            runContract: makeStemTestRunContract()
        )
        let stablePlan = try service.makeAutomaticPlan(
            stems: makePanStems { _ in (1, 0.8) },
            runContract: makeStemTestRunContract()
        )
        let unstablePlan = try service.makeAutomaticPlan(
            stems: makePanStems { index in
                index < 4_800 ? (1, 0.8) : (0.8, 1)
            },
            runContract: makeStemTestRunContract()
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
                vocalsToAccompanimentAmount: 0
            )
        )

        let activeResult = try service.render(
            stems: active,
            settings: settings,
            runContract: makeStemTestRunContract()
        )
        let silentResult = try service.render(
            stems: silent,
            settings: settings,
            runContract: makeStemTestRunContract()
        )
        let silentPure = try pureSum(silent)
        let activePure = try pureSum(active)

        #expect(activeResult.signal.channels != activePure.channels)
        #expect(silentResult.signal.channels == silentPure.channels)
    }

    @Test
    func htVocalsToOtherMaskingKeepsTheApprovedFloat32Output() throws {
        let settings = StemRemixSettings(
            masking: StemRemixMaskingSettings(
                vocalsToAccompanimentEnabled: true,
                vocalsToAccompanimentAmount: 0.3
            )
        )

        let result = try service.render(
            stems: makeHTVocalsMaskingStems(),
            settings: settings,
            runContract: makeStemTestRunContract()
        )

        #expect(floatFingerprint(result.signal) == 8_742_540_710_301_265_695)
    }

    @Test
    func bsVocalsMaskingUsesOneSharedEnvelopeForTheThreeAccompanimentStems() throws {
        let contract = makeStemTestRunContract(model: .bsRoformerSW)
        let settings = StemRemixSettings(
            masking: StemRemixMaskingSettings(
                vocalsToAccompanimentEnabled: true,
                vocalsToAccompanimentAmount: 0.35
            )
        )
        let split = try service.render(
            stems: makeBSSharedMaskingStems(combineAccompanimentIntoOther: false),
            settings: settings,
            runContract: contract
        )
        let combined = try service.render(
            stems: makeBSSharedMaskingStems(combineAccompanimentIntoOther: true),
            settings: settings,
            runContract: contract
        )

        #expect(maximumAbsoluteDifference(split.drySignal, combined.drySignal) < 1e-5)
    }

    @Test
    func bsVocalsMaskingLeavesTheSixStemSumUnchangedWhenVocalsAreSilent() throws {
        let contract = makeStemTestRunContract(model: .bsRoformerSW)
        let stems = makeBSSharedMaskingStems(
            combineAccompanimentIntoOther: false,
            vocalsAreSilent: true
        )
        let settings = StemRemixSettings(
            masking: StemRemixMaskingSettings(
                vocalsToAccompanimentEnabled: true,
                vocalsToAccompanimentAmount: 0.35
            )
        )

        let result = try service.render(
            stems: stems,
            settings: settings,
            runContract: contract
        )
        let pure = try pureSum(stems, runContract: contract)

        #expect(result.drySignal.channels == pure.channels)
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

        let result = try service.render(
            stems: stems,
            settings: settings,
            runContract: makeStemTestRunContract()
        )
        let pure = try pureSum(stems)

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

        let enabledResult = try service.render(
            stems: stems,
            settings: enabled,
            runContract: makeStemTestRunContract()
        )
        let disabledResult = try service.render(
            stems: stems,
            settings: disabled,
            runContract: makeStemTestRunContract()
        )

        #expect(enabledResult.signal.channels == disabledResult.signal.channels)
    }

    @Test
    func oneSharedReverbReturnUsesEveryStemSendAndStaysFinite() throws {
        let contract = makeStemTestRunContract(model: .bsRoformerSW)
        let stems = makeStems(model: .bsRoformerSW)
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

        let result = try service.render(
            stems: stems,
            settings: settings,
            runContract: contract
        )

        #expect(result.reverbReturn.channels.contains {
            $0.contains(where: { abs($0) > 1e-7 })
        })
        #expect(result.signal.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        #expect(result.signal.channels != result.drySignal.channels)
    }

    @Test
    func bsGuitarAndPianoEachFeedTheSingleSharedReverbReturn() throws {
        let contract = makeStemTestRunContract(model: .bsRoformerSW)
        let stems = makeStems(model: .bsRoformerSW)
        var guitarSettings = StemRemixSettings(
            reverbReturnLevel: 0.3,
            reverbDecaySeconds: 1.4
        )
        guitarSettings.setSettings(
            StemRemixRoleSettings(reverbSend: 0.25),
            for: .guitar
        )
        var pianoSettings = StemRemixSettings(
            reverbReturnLevel: 0.3,
            reverbDecaySeconds: 1.4
        )
        pianoSettings.setSettings(
            StemRemixRoleSettings(reverbSend: 0.25),
            for: .piano
        )

        let guitar = try service.render(
            stems: stems,
            settings: guitarSettings,
            runContract: contract
        )
        let piano = try service.render(
            stems: stems,
            settings: pianoSettings,
            runContract: contract
        )

        #expect(guitar.reverbReturn.channels.contains { channel in
            channel.contains { abs($0) > 1e-7 }
        })
        #expect(piano.reverbReturn.channels.contains { channel in
            channel.contains { abs($0) > 1e-7 }
        })
        #expect(guitar.reverbReturn.channels != piano.reverbReturn.channels)
    }

    @Test
    func missingDuplicateAndNonFiniteStemsAreRejected() {
        let stems = makeStems()
        #expect(throws: StemRemixServiceError.missingRole(.vocals)) {
            try service.render(
                stems: stems.filter { $0.role != .vocals },
                settings: StemRemixSettings(),
                runContract: makeStemTestRunContract()
            )
        }

        #expect(throws: StemRemixServiceError.duplicateRole(.drums)) {
            try service.render(
                stems: stems + [stems[0]],
                settings: StemRemixSettings(),
                runContract: makeStemTestRunContract()
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
            try service.render(
                stems: invalid,
                settings: StemRemixSettings(),
                runContract: makeStemTestRunContract()
            )
        }
    }

    @Test
    func contractRejectsUnexpectedRolesAndInvalidPureSumMembership() {
        let htContract = makeStemTestRunContract()
        let guitar = makeStems(model: .bsRoformerSW).first { $0.role == .guitar }!
        #expect(throws: StemRemixServiceError.unexpectedRole(.guitar)) {
            try service.render(
                stems: makeStems() + [guitar],
                settings: StemRemixSettings(),
                runContract: htContract
            )
        }

        let profile = StemProductionModelProfile.profile(for: .bsRoformerSW)
        let invalidContract = StemModelRunContract(
            separationModel: .bsRoformerSW,
            modelIdentifier: profile.modelIdentifier,
            modelOutputOrder: profile.sourceOrder,
            activeRoles: profile.sourceOrder,
            validationRoles: profile.sourceOrder,
            pureSumOrder: profile.pureSumOrder.filter { $0 != .piano }
        )
        #expect(throws: StemRemixServiceError.invalidRunContract) {
            try service.render(
                stems: makeStems(model: .bsRoformerSW),
                settings: StemRemixSettings(),
                runContract: invalidContract
            )
        }
    }

    private func makeStems(
        model: StemSeparationModel = .htdemucs,
        frameCount: Int = 9_600,
        correctedScale: Float = 1
    ) -> [StemRemixSignal] {
        StemProductionModelProfile.profile(for: model).sourceOrder.enumerated().map { roleIndex, role in
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

    private func pureSum(
        _ stems: [StemRemixSignal],
        runContract: StemModelRunContract = makeStemTestRunContract()
    ) throws -> AudioSignal {
        return try StemMixService().pureSum(
            stems: stems.map { StemMixInput(role: $0.role, signal: $0.corrected) },
            validationRoles: runContract.validationRoles,
            order: runContract.pureSumOrder
        ).signal
    }

    private func makeBSSharedMaskingStems(
        combineAccompanimentIntoOther: Bool,
        vocalsAreSilent: Bool = false
    ) -> [StemRemixSignal] {
        let frameCount = 9_600
        let accompanimentRoles = [StemRole.other, .guitar, .piano]
        let accompanimentSignals = Dictionary(uniqueKeysWithValues: accompanimentRoles.enumerated().map {
            roleIndex, role in
            let frequency = Double(1_900 + roleIndex * 650)
            let samples = (0..<frameCount).map { index -> Float in
                let period = 1_600 + roleIndex * 500
                let active = index % period < period / 2 ? Float(1) : Float(0)
                return Float(sin(2 * .pi * frequency * Double(index) / 48_000))
                    * Float(0.035 + Double(roleIndex) * 0.012)
                    * active
            }
            return (role, samples)
        })
        let combined = (0..<frameCount).map { index in
            accompanimentRoles.reduce(Float.zero) { partial, role in
                partial + accompanimentSignals[role]![index]
            }
        }
        let silence = Array(repeating: Float.zero, count: frameCount)

        return makeStemTestRunContract(model: .bsRoformerSW).validationRoles.map { role in
            let samples: [Float] = switch role {
            case .other:
                combineAccompanimentIntoOther ? combined : accompanimentSignals[role]!
            case .guitar, .piano:
                combineAccompanimentIntoOther ? silence : accompanimentSignals[role]!
            case .vocals:
                vocalsAreSilent ? silence : (0..<frameCount).map { index in
                    let active = index % 2_400 < 1_500 ? Float(1) : Float(0)
                    return Float(sin(2 * .pi * 2_200 * Double(index) / 48_000))
                        * 0.1 * active
                }
            case .drums:
                (0..<frameCount).map { index in
                    Float(sin(2 * .pi * 90 * Double(index) / 48_000)) * 0.015
                }
            case .bass:
                (0..<frameCount).map { index in
                    Float(sin(2 * .pi * 120 * Double(index) / 48_000)) * 0.015
                }
            }
            let signal = AudioSignal(channels: [samples, samples], sampleRate: 48_000)
            return StemRemixSignal(role: role, raw: signal, corrected: signal)
        }
    }

    private func maximumAbsoluteDifference(
        _ lhs: AudioSignal,
        _ rhs: AudioSignal
    ) -> Float {
        zip(lhs.channels, rhs.channels).flatMap { left, right in
            zip(left, right).map { abs($0 - $1) }
        }.max() ?? 0
    }

    private func makeCollisionStems(triggerIsSilent: Bool) -> [StemRemixSignal] {
        let frameCount = 9_600
        return StemProductionModelProfile.profile(for: .htdemucs).sourceOrder.map { role in
            let frequency: Double = switch role {
            case .drums, .bass: 80
            case .other: 300
            case .vocals: 600
            case .guitar: 1_200
            case .piano: 880
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
        return StemProductionModelProfile.profile(for: .htdemucs).sourceOrder.map { role in
            let channels: [[Float]] = switch role {
            case .drums:
                [tone, tone.map { -$0 }]
            case .bass:
                [tone, tone]
            case .vocals, .other, .guitar, .piano:
                [silence, silence]
            }
            let signal = AudioSignal(channels: channels, sampleRate: 48_000)
            return StemRemixSignal(role: role, raw: signal, corrected: signal)
        }
    }

    private func makeHTVocalsMaskingStems() -> [StemRemixSignal] {
        let frameCount = 9_600
        return StemProductionModelProfile.profile(for: .htdemucs).sourceOrder.map { role in
            let frequency: Double = switch role {
            case .vocals, .other: 2_200
            case .drums: 90
            case .bass: 120
            case .guitar: 1_200
            case .piano: 880
            }
            let amplitude: Float = switch role {
            case .vocals: 0.11
            case .other: 0.08
            case .drums, .bass, .guitar, .piano: 0.02
            }
            let samples = (0..<frameCount).map { index -> Float in
                let active = index % 2_400 < 1_500 ? Float(1) : Float(0)
                return Float(sin(2 * .pi * frequency * Double(index) / 48_000))
                    * amplitude * active
            }
            let signal = AudioSignal(channels: [samples, samples], sampleRate: 48_000)
            return StemRemixSignal(role: role, raw: signal, corrected: signal)
        }
    }

    private func floatFingerprint(_ signal: AudioSignal) -> UInt64 {
        signal.channels.flatMap { $0 }.reduce(UInt64(1_469_598_103_934_665_603)) { hash, sample in
            (hash ^ UInt64(sample.bitPattern)) &* 1_099_511_628_211
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
