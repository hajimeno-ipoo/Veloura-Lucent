import Foundation

struct StemMixInput: Sendable {
    let role: StemRole
    let signal: AudioSignal
}

enum StemMixTruePeakMeasurement: Equatable, Sendable {
    case measured(Float)
    case unavailable

    var linearValue: Float? {
        guard case .measured(let value) = self else { return nil }
        return value
    }
}

struct StemMixPeakRecord: Equatable, Sendable {
    let samplePeakLinear: Float
    let truePeakMeasurement: StemMixTruePeakMeasurement
    let overRangeSampleCount: Int

    var truePeakLinear: Float? {
        truePeakMeasurement.linearValue
    }

    var samplePeakExceedsFullScale: Bool {
        samplePeakLinear > 1
    }

    var truePeakExceedsFullScale: Bool? {
        truePeakLinear.map { $0 > 1 }
    }

    var hasOverRange: Bool {
        overRangeSampleCount > 0 || truePeakExceedsFullScale == true
    }
}

struct StemPureSumResult: Sendable {
    let signal: AudioSignal
    let peaks: StemMixPeakRecord
}

enum StemMixError: LocalizedError, Equatable, Sendable {
    case duplicateRole(StemRole)
    case missingRole(StemRole)
    case unexpectedRole(StemRole)
    case invalidRoleContract
    case invalidSampleRate(role: StemRole)
    case missingChannels(role: StemRole)
    case emptyFrames(role: StemRole)
    case unevenChannelFrameCount(role: StemRole, channelIndex: Int, expected: Int, actual: Int)
    case sampleRateMismatch(role: StemRole, expected: Double, actual: Double)
    case channelCountMismatch(role: StemRole, expected: Int, actual: Int)
    case frameCountMismatch(role: StemRole, expected: Int, actual: Int)
    case nonFiniteSample(role: StemRole, channelIndex: Int, frameIndex: Int)
    case nonFiniteMixedSample(channelIndex: Int, frameIndex: Int)
    case nonFinitePeakMeasurement

    var errorDescription: String? {
        switch self {
        case .duplicateRole(let role):
            return "Stem Modeの再ミックス入力に\(role.rawValue)が重複しています。"
        case .missingRole(let role):
            return "Stem Modeの再ミックス入力に\(role.rawValue)がありません。"
        case .unexpectedRole(let role):
            return "Stem Modeの再ミックス入力に契約外の\(role.rawValue)があります。"
        case .invalidRoleContract:
            return "Stem Modeの検証役割と純粋加算順が一致しません。"
        case .invalidSampleRate(let role):
            return "Stem Modeの\(role.rawValue)に有効なサンプルレートがありません。"
        case .missingChannels(let role):
            return "Stem Modeの\(role.rawValue)に音声チャンネルがありません。"
        case .emptyFrames(let role):
            return "Stem Modeの\(role.rawValue)に音声フレームがありません。"
        case .unevenChannelFrameCount(let role, let channelIndex, let expected, let actual):
            return "Stem Modeの\(role.rawValue)内でチャンネル長が一致しません（channel \(channelIndex)、期待: \(expected)、実際: \(actual)）。"
        case .sampleRateMismatch(let role, let expected, let actual):
            return "Stem Modeの\(role.rawValue)のサンプルレートが一致しません（期待: \(expected)、実際: \(actual)）。"
        case .channelCountMismatch(let role, let expected, let actual):
            return "Stem Modeの\(role.rawValue)のチャンネル数が一致しません（期待: \(expected)、実際: \(actual)）。"
        case .frameCountMismatch(let role, let expected, let actual):
            return "Stem Modeの\(role.rawValue)のフレーム数が一致しません（期待: \(expected)、実際: \(actual)）。"
        case .nonFiniteSample(let role, let channelIndex, let frameIndex):
            return "Stem Modeの\(role.rawValue)にNaNまたはInfinityがあります（channel \(channelIndex)、frame \(frameIndex)）。"
        case .nonFiniteMixedSample(let channelIndex, let frameIndex):
            return "Stem Modeのraw再ミックスで有限値を維持できませんでした（channel \(channelIndex)、frame \(frameIndex)）。"
        case .nonFinitePeakMeasurement:
            return "Stem Modeの純粋加算再ミックスで有限なピーク値を測定できませんでした。"
        }
    }
}

struct StemMixService: Sendable {
    private static let defaultValidationRoles: [StemRole] = [.drums, .bass, .other, .vocals]
    private static let defaultPureSumOrder: [StemRole] = [.vocals, .drums, .bass, .other]

    /// Adds the contracted role signals in the explicit Float32 order without applying
    /// gain, pan, normalization, dynamics, or limiting.
    func pureSum(
        stems: [StemMixInput],
        validationRoles: [StemRole] = Self.defaultValidationRoles,
        order: [StemRole] = Self.defaultPureSumOrder
    ) throws -> StemPureSumResult {
        guard !validationRoles.isEmpty,
              Set(validationRoles).count == validationRoles.count,
              Set(order).count == order.count,
              Set(validationRoles) == Set(order) else {
            throw StemMixError.invalidRoleContract
        }
        let signals = try validatedSignals(stems, roles: validationRoles)
        let reference = try requiredSignal(for: validationRoles[0], in: signals)
        let signal = try sum(
            signals,
            order: order,
            sampleRate: reference.sampleRate,
            channelCount: reference.channels.count,
            frameCount: reference.frameCount
        )
        return StemPureSumResult(
            signal: signal,
            peaks: try peakRecord(for: signal)
        )
    }

    private func validatedSignals(
        _ stems: [StemMixInput],
        roles: [StemRole]
    ) throws -> [StemRole: AudioSignal] {
        var signals: [StemRole: AudioSignal] = [:]
        for stem in stems {
            guard signals[stem.role] == nil else {
                throw StemMixError.duplicateRole(stem.role)
            }
            signals[stem.role] = stem.signal
        }

        let expectedRoles = Set(roles)
        for role in signals.keys where !expectedRoles.contains(role) {
            throw StemMixError.unexpectedRole(role)
        }
        for role in roles where signals[role] == nil {
            throw StemMixError.missingRole(role)
        }

        for role in roles {
            try validateSignalStructure(try requiredSignal(for: role, in: signals), role: role)
        }

        let reference = try requiredSignal(for: roles[0], in: signals)
        for role in roles.dropFirst() {
            let signal = try requiredSignal(for: role, in: signals)
            guard signal.sampleRate == reference.sampleRate else {
                throw StemMixError.sampleRateMismatch(
                    role: role,
                    expected: reference.sampleRate,
                    actual: signal.sampleRate
                )
            }
            guard signal.channels.count == reference.channels.count else {
                throw StemMixError.channelCountMismatch(
                    role: role,
                    expected: reference.channels.count,
                    actual: signal.channels.count
                )
            }
            guard signal.frameCount == reference.frameCount else {
                throw StemMixError.frameCountMismatch(
                    role: role,
                    expected: reference.frameCount,
                    actual: signal.frameCount
                )
            }
        }

        return signals
    }

    private func validateSignalStructure(_ signal: AudioSignal, role: StemRole) throws {
        guard signal.sampleRate.isFinite, signal.sampleRate > 0 else {
            throw StemMixError.invalidSampleRate(role: role)
        }
        guard let firstChannel = signal.channels.first else {
            throw StemMixError.missingChannels(role: role)
        }
        guard !firstChannel.isEmpty else {
            throw StemMixError.emptyFrames(role: role)
        }

        for (channelIndex, channel) in signal.channels.enumerated() {
            guard channel.count == firstChannel.count else {
                throw StemMixError.unevenChannelFrameCount(
                    role: role,
                    channelIndex: channelIndex,
                    expected: firstChannel.count,
                    actual: channel.count
                )
            }
            for (frameIndex, sample) in channel.enumerated() where !sample.isFinite {
                throw StemMixError.nonFiniteSample(
                    role: role,
                    channelIndex: channelIndex,
                    frameIndex: frameIndex
                )
            }
        }
    }

    private func requiredSignal(
        for role: StemRole,
        in signals: [StemRole: AudioSignal]
    ) throws -> AudioSignal {
        guard let signal = signals[role] else {
            throw StemMixError.missingRole(role)
        }
        return signal
    }

    private func sum(
        _ signals: [StemRole: AudioSignal],
        order: [StemRole],
        sampleRate: Double,
        channelCount: Int,
        frameCount: Int
    ) throws -> AudioSignal {
        try sum(
            roles: order,
            signals: signals,
            sampleRate: sampleRate,
            channelCount: channelCount,
            frameCount: frameCount
        )
    }

    private func sum(
        roles: [StemRole],
        signals: [StemRole: AudioSignal],
        sampleRate: Double,
        channelCount: Int,
        frameCount: Int
    ) throws -> AudioSignal {
        let orderedSignals = try roles.map { try requiredSignal(for: $0, in: signals) }
        var mixedChannels: [[Float]] = []
        mixedChannels.reserveCapacity(channelCount)

        for channelIndex in 0..<channelCount {
            var mixedChannel = Array(repeating: Float.zero, count: frameCount)
            for frameIndex in 0..<frameCount {
                var mixedSample: Float = 0
                for signal in orderedSignals {
                    mixedSample += signal.channels[channelIndex][frameIndex]
                }
                guard mixedSample.isFinite else {
                    throw StemMixError.nonFiniteMixedSample(
                        channelIndex: channelIndex,
                        frameIndex: frameIndex
                    )
                }
                mixedChannel[frameIndex] = mixedSample
            }
            mixedChannels.append(mixedChannel)
        }

        return AudioSignal(channels: mixedChannels, sampleRate: sampleRate)
    }

    private func peakRecord(for signal: AudioSignal) throws -> StemMixPeakRecord {
        var samplePeakLinear: Float = 0
        var overRangeSampleCount = 0

        for channel in signal.channels {
            for sample in channel {
                let magnitude = abs(sample)
                samplePeakLinear = max(samplePeakLinear, magnitude)
                if magnitude > 1 {
                    overRangeSampleCount += 1
                }
            }
        }

        let truePeakLinear = LoudnessMeasurementService.truePeakLinear(signal.channels)
        guard samplePeakLinear.isFinite else {
            throw StemMixError.nonFinitePeakMeasurement
        }
        let truePeakMeasurement: StemMixTruePeakMeasurement
        if truePeakLinear.isFinite {
            truePeakMeasurement = .measured(truePeakLinear)
        } else {
            truePeakMeasurement = .unavailable
        }

        return StemMixPeakRecord(
            samplePeakLinear: samplePeakLinear,
            truePeakMeasurement: truePeakMeasurement,
            overRangeSampleCount: overRangeSampleCount
        )
    }
}
