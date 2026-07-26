import Foundation

enum StemRoleProtectionGuardDecision: Equatable, Sendable {
    case acceptedDSPOutput
    case weakenedDSPDelta(components: Set<StemRoleProtectedComponent>)
    case restoredStageInput(components: Set<StemRoleProtectedComponent>)
}

enum StemRoleProtectionRestorationReason: Equatable, Sendable {
    case clearPolarityInversion
    case fullySuppressedDSPDelta

    var logDescription: String {
        switch self {
        case .clearPolarityInversion:
            "明確な極性反転を検出"
        case .fullySuppressedDSPDelta:
            "保護対象と重なるDSP差分を全て抑制"
        }
    }
}

struct StemRoleProtectionGuardSummary: Equatable, Sendable {
    let affectedTimeRatio: Double
    let averageRetainedDSPDeltaRatio: Double
    let minimumRetainedDSPDeltaRatio: Double
    let restorationReason: StemRoleProtectionRestorationReason?
}

struct StemRoleProtectionGuardResult: Sendable {
    let signal: AudioSignal
    let profile: StemRoleProtectionProfile
    let decision: StemRoleProtectionGuardDecision
    let summary: StemRoleProtectionGuardSummary?
}

enum StemRoleProtectionGuardError: LocalizedError, Equatable, Sendable {
    case structuralMismatch
    case profileMismatch
    case nonFiniteComparison(StemRoleProtectedComponent)

    var errorDescription: String? {
        switch self {
        case .structuralMismatch:
            "Stem役割保護guardのDSP前後音声構造が一致しません。"
        case .profileMismatch:
            "Stem役割保護guardの時系列解析位置が一致しません。"
        case let .nonFiniteComparison(component):
            "Stem役割保護guardで有限値ではない比較結果が発生しました（\(component.rawValue)）。"
        }
    }
}

protocol StemRoleProtectionGuarding: Sendable {
    func protect(
        role: StemRole,
        stageInput: AudioSignal,
        proposedOutput: AudioSignal,
        rawProfile: StemRoleProtectionProfile,
        inputProfile: StemRoleProtectionProfile
    ) throws -> StemRoleProtectionGuardResult
}

/// DSP直前音と直後音を同じ時間位置で比較し、今回のraw Stemに存在する役割成分だけを守ります。
///
/// 完成候補の生成・順位付け・品質スコアは行いません。保護量は今回のraw Stemにおける
/// 成分の相対的な存在量と、当該DSPが生じさせた相対変化から連続的に算出します。
/// サンプル音源由来の閾値、固定mapping、絶対合否値は持ちません。
struct StemRoleProtectionGuardService: StemRoleProtectionGuarding, Sendable {
    private static let numericalFloor = Double.leastNormalMagnitude

    private let analyzer: StemRoleAnalysisService

    init(analyzer: StemRoleAnalysisService = StemRoleAnalysisService()) {
        self.analyzer = analyzer
    }

    func protect(
        role: StemRole,
        stageInput: AudioSignal,
        proposedOutput: AudioSignal,
        rawProfile: StemRoleProtectionProfile,
        inputProfile: StemRoleProtectionProfile
    ) throws -> StemRoleProtectionGuardResult {
        guard structurallyMatches(stageInput, proposedOutput) else {
            throw StemRoleProtectionGuardError.structuralMismatch
        }
        guard profilesMatch(rawProfile, inputProfile),
              rawProfile.role == role else {
            throw StemRoleProtectionGuardError.profileMismatch
        }
        guard stageInput.channels != proposedOutput.channels else {
            return StemRoleProtectionGuardResult(
                signal: stageInput,
                profile: inputProfile,
                decision: .acceptedDSPOutput,
                summary: nil
            )
        }

        if hasClearPolarityInversion(input: stageInput, output: proposedOutput) {
            return StemRoleProtectionGuardResult(
                signal: stageInput,
                profile: inputProfile,
                decision: .restoredStageInput(components: Set(
                    StemRoleProtectedComponent.allCases.filter { $0.role == role }
                )),
                summary: StemRoleProtectionGuardSummary(
                    affectedTimeRatio: 1,
                    averageRetainedDSPDeltaRatio: 0,
                    minimumRetainedDSPDeltaRatio: 0,
                    restorationReason: .clearPolarityInversion
                )
            )
        }

        let outputProfile = try analyzer.analyzeWithProtection(
            role: role,
            processingSignal48000: proposedOutput
        ).protectionProfile
        guard profilesMatch(rawProfile, outputProfile),
              profilesMatch(inputProfile, outputProfile) else {
            throw StemRoleProtectionGuardError.profileMismatch
        }

        let components = StemRoleProtectedComponent.allCases.filter { $0.role == role }
        let rawMaxima = try componentMaxima(components: components, profile: rawProfile)
        var frameProtection = Array(repeating: 0.0, count: inputProfile.frames.count)
        var affectedComponents = Set<StemRoleProtectedComponent>()

        for frameIndex in inputProfile.frames.indices {
            let rawFrame = rawProfile.frames[frameIndex]
            let inputFrame = inputProfile.frames[frameIndex]
            let outputFrame = outputProfile.frames[frameIndex]
            var maximumProtection = 0.0

            for component in components {
                guard let rawValue = rawFrame.values[component],
                      let inputValue = inputFrame.values[component],
                      let outputValue = outputFrame.values[component],
                      rawValue.isFinite,
                      inputValue.isFinite,
                      outputValue.isFinite else {
                    throw StemRoleProtectionGuardError.nonFiniteComparison(component)
                }

                let rawMaximum = rawMaxima[component] ?? 0
                guard rawMaximum > Self.numericalFloor else { continue }
                let presence = min(1, abs(rawValue) / rawMaximum)
                let change = protectedChange(
                    rawValue: rawValue,
                    inputValue: inputValue,
                    outputValue: outputValue
                )
                let protection = min(1, max(0, presence * change))
                guard protection.isFinite else {
                    throw StemRoleProtectionGuardError.nonFiniteComparison(component)
                }
                if protection > 0 {
                    affectedComponents.insert(component)
                    maximumProtection = max(maximumProtection, protection)
                }
            }
            frameProtection[frameIndex] = maximumProtection
        }

        guard frameProtection.contains(where: { $0 > 0 }) else {
            return StemRoleProtectionGuardResult(
                signal: proposedOutput,
                profile: outputProfile,
                decision: .acceptedDSPOutput,
                summary: nil
            )
        }

        let protected = blendDSPDelta(
            input: stageInput,
            output: proposedOutput,
            profile: inputProfile,
            frameProtection: frameProtection
        )
        if protected.signal.channels == stageInput.channels {
            return StemRoleProtectionGuardResult(
                signal: stageInput,
                profile: inputProfile,
                decision: .restoredStageInput(components: affectedComponents),
                summary: StemRoleProtectionGuardSummary(
                    affectedTimeRatio: protected.summary.affectedTimeRatio,
                    averageRetainedDSPDeltaRatio: 0,
                    minimumRetainedDSPDeltaRatio: 0,
                    restorationReason: .fullySuppressedDSPDelta
                )
            )
        }

        let protectedProfile = try analyzer.analyzeWithProtection(
            role: role,
            processingSignal48000: protected.signal
        ).protectionProfile
        return StemRoleProtectionGuardResult(
            signal: protected.signal,
            profile: protectedProfile,
            decision: .weakenedDSPDelta(components: affectedComponents),
            summary: protected.summary
        )
    }

    /// 今回のraw Stemに存在する成分と同じ時間位置で、当該DSPが生じさせた差分量だけを測ります。
    /// 成分ごとの固定mappingや増減方向の固定ルールは使いません。
    private func protectedChange(
        rawValue: Double,
        inputValue: Double,
        outputValue: Double
    ) -> Double {
        let denominator = max(
            abs(rawValue),
            abs(inputValue),
            abs(outputValue),
            Self.numericalFloor
        )
        return abs(outputValue - inputValue) / denominator
    }

    private func componentMaxima(
        components: [StemRoleProtectedComponent],
        profile: StemRoleProtectionProfile
    ) throws -> [StemRoleProtectedComponent: Double] {
        try Dictionary(uniqueKeysWithValues: components.map { component in
            let values = try profile.frames.map { frame -> Double in
                guard let value = frame.values[component], value.isFinite else {
                    throw StemRoleProtectionGuardError.nonFiniteComparison(component)
                }
                return abs(value)
            }
            return (component, values.max() ?? 0)
        })
    }

    private func blendDSPDelta(
        input: AudioSignal,
        output: AudioSignal,
        profile: StemRoleProtectionProfile,
        frameProtection: [Double]
    ) -> (signal: AudioSignal, summary: StemRoleProtectionGuardSummary) {
        var protectionSums = Array(repeating: 0.0, count: input.frameCount)
        var coverage = Array(repeating: 0, count: input.frameCount)
        for (frameIndex, frame) in profile.frames.enumerated() {
            let end = min(input.frameCount, frame.startFrame + frame.validFrameCount)
            guard frame.startFrame < end else { continue }
            for sampleIndex in frame.startFrame..<end {
                protectionSums[sampleIndex] += frameProtection[frameIndex]
                coverage[sampleIndex] += 1
            }
        }

        let sampleProtection = input.channels[0].indices.map { index -> Float in
            guard coverage[index] > 0 else { return 0 }
            return Float(min(1, max(0, protectionSums[index] / Double(coverage[index]))))
        }
        let channels = zip(input.channels, output.channels).map { inputChannel, outputChannel in
            inputChannel.indices.map { index in
                let retainedDSPDelta = 1 - sampleProtection[index]
                return inputChannel[index]
                    + (outputChannel[index] - inputChannel[index]) * retainedDSPDelta
            }
        }
        let affectedProtection = sampleProtection.filter { $0 > 0 }
        let affectedTimeRatio = input.frameCount > 0
            ? Double(affectedProtection.count) / Double(input.frameCount)
            : 0
        let retainedDSPDelta = affectedProtection.map { 1 - Double($0) }
        let averageRetainedDSPDeltaRatio = retainedDSPDelta.isEmpty
            ? 1
            : retainedDSPDelta.reduce(0, +) / Double(retainedDSPDelta.count)
        let minimumRetainedDSPDeltaRatio = retainedDSPDelta.min() ?? 1
        return (
            AudioSignal(channels: channels, sampleRate: input.sampleRate),
            StemRoleProtectionGuardSummary(
                affectedTimeRatio: affectedTimeRatio,
                averageRetainedDSPDeltaRatio: averageRetainedDSPDeltaRatio,
                minimumRetainedDSPDeltaRatio: minimumRetainedDSPDeltaRatio,
                restorationReason: nil
            )
        )
    }

    private func structurallyMatches(_ lhs: AudioSignal, _ rhs: AudioSignal) -> Bool {
        lhs.sampleRate == rhs.sampleRate
            && lhs.channels.count == rhs.channels.count
            && lhs.frameCount == rhs.frameCount
            && !lhs.channels.isEmpty
            && lhs.channels.enumerated().allSatisfy { index, channel in
                channel.count == rhs.channels[index].count
                    && channel.allSatisfy(\.isFinite)
                    && rhs.channels[index].allSatisfy(\.isFinite)
            }
    }

    private func hasClearPolarityInversion(input: AudioSignal, output: AudioSignal) -> Bool {
        for channelIndex in input.channels.indices {
            if normalizedDot(input.channels[channelIndex], output.channels[channelIndex]).map({ $0 < 0 }) == true {
                return true
            }
        }
        let inputMid = zip(input.channels[0], input.channels[1]).map { ($0 + $1) * 0.5 }
        let outputMid = zip(output.channels[0], output.channels[1]).map { ($0 + $1) * 0.5 }
        if normalizedDot(inputMid, outputMid).map({ $0 < 0 }) == true {
            return true
        }
        let inputSide = zip(input.channels[0], input.channels[1]).map { ($0 - $1) * 0.5 }
        let outputSide = zip(output.channels[0], output.channels[1]).map { ($0 - $1) * 0.5 }
        return normalizedDot(inputSide, outputSide).map { $0 < 0 } ?? false
    }

    private func normalizedDot(_ lhs: [Float], _ rhs: [Float]) -> Double? {
        guard lhs.count == rhs.count, !lhs.isEmpty else { return nil }
        var dot = 0.0
        var lhsEnergy = 0.0
        var rhsEnergy = 0.0
        for index in lhs.indices {
            let left = Double(lhs[index])
            let right = Double(rhs[index])
            dot += left * right
            lhsEnergy += left * left
            rhsEnergy += right * right
        }
        guard lhsEnergy > 0, rhsEnergy > 0 else { return nil }
        return max(-1, min(1, dot / sqrt(lhsEnergy * rhsEnergy)))
    }

    private func profilesMatch(
        _ lhs: StemRoleProtectionProfile,
        _ rhs: StemRoleProtectionProfile
    ) -> Bool {
        lhs.role == rhs.role
            && lhs.sampleRate == rhs.sampleRate
            && lhs.signalFrameCount == rhs.signalFrameCount
            && lhs.analysisFrameSize == rhs.analysisFrameSize
            && lhs.hopSize == rhs.hopSize
            && lhs.frames.map(\.startFrame) == rhs.frames.map(\.startFrame)
            && lhs.frames.map(\.validFrameCount) == rhs.frames.map(\.validFrameCount)
    }
}
