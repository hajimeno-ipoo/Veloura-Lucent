import Foundation

struct StemRemixRoleSettings: Equatable, Sendable {
    var gainDB: Float
    var pan: Float
    var reverbSend: Float

    init(gainDB: Float = 0, pan: Float = 0, reverbSend: Float = 0) {
        self.gainDB = Self.clamp(gainDB, to: -12...12)
        self.pan = Self.clamp(pan, to: -1...1)
        self.reverbSend = Self.clamp(reverbSend, to: 0...0.6)
    }

    private static func clamp(_ value: Float, to range: ClosedRange<Float>) -> Float {
        min(max(value.isFinite ? value : 0, range.lowerBound), range.upperBound)
    }
}

struct StemRemixMaskingSettings: Equatable, Sendable {
    var drumsToBassEnabled: Bool
    var drumsToBassAmount: Float
    var vocalsToOtherEnabled: Bool
    var vocalsToOtherAmount: Float

    init(
        drumsToBassEnabled: Bool = false,
        drumsToBassAmount: Float = 0,
        vocalsToOtherEnabled: Bool = false,
        vocalsToOtherAmount: Float = 0
    ) {
        self.drumsToBassEnabled = drumsToBassEnabled
        self.drumsToBassAmount = Self.clamp(drumsToBassAmount)
        self.vocalsToOtherEnabled = vocalsToOtherEnabled
        self.vocalsToOtherAmount = Self.clamp(vocalsToOtherAmount)
    }

    private static func clamp(_ value: Float) -> Float {
        min(max(value.isFinite ? value : 0, 0), 0.5)
    }
}

struct StemRemixSettings: Equatable, Sendable {
    private var roleValues: [StemRole: StemRemixRoleSettings]
    var masking: StemRemixMaskingSettings
    var reverbReturnLevel: Float
    var reverbDecaySeconds: Float

    init(
        roleValues: [StemRole: StemRemixRoleSettings] = [:],
        masking: StemRemixMaskingSettings = StemRemixMaskingSettings(),
        reverbReturnLevel: Float = 0,
        reverbDecaySeconds: Float = 1
    ) {
        self.roleValues = Dictionary(
            uniqueKeysWithValues: StemRole.allCases.map { role in
                (role, roleValues[role] ?? StemRemixRoleSettings())
            }
        )
        self.masking = masking
        self.reverbReturnLevel = min(
            max(reverbReturnLevel.isFinite ? reverbReturnLevel : 0, 0),
            0.5
        )
        self.reverbDecaySeconds = min(
            max(reverbDecaySeconds.isFinite ? reverbDecaySeconds : 1, 0.25),
            4
        )
    }

    func settings(for role: StemRole) -> StemRemixRoleSettings {
        roleValues[role] ?? StemRemixRoleSettings()
    }

    mutating func setSettings(_ settings: StemRemixRoleSettings, for role: StemRole) {
        roleValues[role] = settings
    }
}

struct StemRemixRoleOverrides: Equatable, Sendable {
    var gainDB: Float?
    var pan: Float?
    var reverbSend: Float?

    var isEmpty: Bool {
        gainDB == nil && pan == nil && reverbSend == nil
    }
}

struct StemRemixManualOverrides: Equatable, Sendable {
    private var roleValues: [StemRole: StemRemixRoleOverrides] = [:]
    var drumsToBassEnabled: Bool?
    var drumsToBassAmount: Float?
    var vocalsToOtherEnabled: Bool?
    var vocalsToOtherAmount: Float?
    var reverbReturnLevel: Float?
    var reverbDecaySeconds: Float?

    var isEmpty: Bool {
        roleValues.isEmpty
            && drumsToBassEnabled == nil
            && drumsToBassAmount == nil
            && vocalsToOtherEnabled == nil
            && vocalsToOtherAmount == nil
            && reverbReturnLevel == nil
            && reverbDecaySeconds == nil
    }

    func overrides(for role: StemRole) -> StemRemixRoleOverrides {
        roleValues[role] ?? StemRemixRoleOverrides()
    }

    mutating func setOverrides(_ overrides: StemRemixRoleOverrides, for role: StemRole) {
        if overrides.isEmpty {
            roleValues.removeValue(forKey: role)
        } else {
            roleValues[role] = overrides
        }
    }

    mutating func reset() {
        self = StemRemixManualOverrides()
    }

    func applying(to automatic: StemRemixSettings) -> StemRemixSettings {
        var effective = automatic
        for role in StemRole.allCases {
            let automaticRole = automatic.settings(for: role)
            let override = overrides(for: role)
            effective.setSettings(
                StemRemixRoleSettings(
                    gainDB: override.gainDB ?? automaticRole.gainDB,
                    pan: override.pan ?? automaticRole.pan,
                    reverbSend: override.reverbSend ?? automaticRole.reverbSend
                ),
                for: role
            )
        }
        effective.masking = StemRemixMaskingSettings(
            drumsToBassEnabled: drumsToBassEnabled
                ?? automatic.masking.drumsToBassEnabled,
            drumsToBassAmount: drumsToBassAmount
                ?? automatic.masking.drumsToBassAmount,
            vocalsToOtherEnabled: vocalsToOtherEnabled
                ?? automatic.masking.vocalsToOtherEnabled,
            vocalsToOtherAmount: vocalsToOtherAmount
                ?? automatic.masking.vocalsToOtherAmount
        )
        effective.reverbReturnLevel = min(
            max(reverbReturnLevel ?? automatic.reverbReturnLevel, 0),
            0.5
        )
        effective.reverbDecaySeconds = min(
            max(reverbDecaySeconds ?? automatic.reverbDecaySeconds, 0.25),
            4
        )
        return effective
    }
}

struct StemRemixAutomaticPlan: Equatable, Sendable {
    let settings: StemRemixSettings
    let gainEvidenceDB: [StemRole: Float]
    let panEvidence: [StemRole: Float]
    let reverbLossEvidence: [StemRole: Float]
    let drumsBassCollision: Float
    let vocalsOtherCollision: Float
}

enum StemRemixRenderStage: CaseIterable, Equatable, Sendable {
    case gain
    case masking
    case pan
    case reverbSend
    case sharedReverb
    case dryReturnMix
}

enum StemRemixRenderStageState: Equatable, Sendable {
    case running
    case completed
}

struct StemRemixRenderResult: Sendable {
    let signal: AudioSignal
    let drySignal: AudioSignal
    let reverbReturn: AudioSignal
    let appliedSettings: StemRemixSettings
}
