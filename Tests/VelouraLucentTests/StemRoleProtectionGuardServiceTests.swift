import Foundation
import Testing
@testable import VelouraLucent

struct StemRoleProtectionGuardServiceTests {
    @Test("DSPが変更しなければ同じ音声と解析をそのまま維持する", arguments: StemRole.allCases)
    func acceptsUnchangedSignal(role: StemRole) throws {
        let signal = makeRoleProtectionSignal()
        let profile = try StemRoleAnalysisService().analyzeWithProtection(
            role: role,
            processingSignal48000: signal
        ).protectionProfile

        let result = try StemRoleProtectionGuardService().protect(
            role: role,
            stageInput: signal,
            proposedOutput: signal,
            rawProfile: profile,
            inputProfile: profile
        )

        #expect(result.signal.channels == signal.channels)
        #expect(result.profile == profile)
        #expect(result.decision == .acceptedDSPOutput)
        #expect(result.summary == nil)
    }

    @Test("今回のraw Stemに存在する成分を一律に削るDSP差分をそのまま通さない", arguments: StemRole.allCases)
    func weakensLossAgainstCurrentRawStem(role: StemRole) throws {
        let input = makeRoleProtectionSignal()
        let output = AudioSignal(
            channels: input.channels.map { channel in channel.map { $0 * 0.4 } },
            sampleRate: input.sampleRate
        )
        let profile = try StemRoleAnalysisService().analyzeWithProtection(
            role: role,
            processingSignal48000: input
        ).protectionProfile

        let result = try StemRoleProtectionGuardService().protect(
            role: role,
            stageInput: input,
            proposedOutput: output,
            rawProfile: profile,
            inputProfile: profile
        )

        #expect(result.signal.channels != output.channels)
        #expect(result.signal.channels.allSatisfy { $0.allSatisfy(\.isFinite) })
        switch result.decision {
        case .weakenedDSPDelta, .restoredStageInput:
            break
        case .acceptedDSPOutput:
            Issue.record("音楽成分を一律に削るDSP差分が保護なしで通過しました")
        }
        let summary = try #require(result.summary)
        #expect(summary.affectedTimeRatio > 0)
        #expect((0...1).contains(summary.averageRetainedDSPDeltaRatio))
        #expect((0...1).contains(summary.minimumRetainedDSPDeltaRatio))
        #expect(summary.minimumRetainedDSPDeltaRatio <= summary.averageRetainedDSPDeltaRatio)
    }

    @Test("成分別の増減方向を固定せずDSP差分の重なりを弱める", arguments: StemRole.allCases)
    func weakensOverlappingDSPDeltaInEitherDirection(role: StemRole) throws {
        let input = makeRoleProtectionSignal()
        let output = AudioSignal(
            channels: input.channels.map { channel in channel.map { $0 * 1.2 } },
            sampleRate: input.sampleRate
        )
        let profile = try StemRoleAnalysisService().analyzeWithProtection(
            role: role,
            processingSignal48000: input
        ).protectionProfile

        let result = try StemRoleProtectionGuardService().protect(
            role: role,
            stageInput: input,
            proposedOutput: output,
            rawProfile: profile,
            inputProfile: profile
        )

        #expect(result.signal.channels != output.channels)
        switch result.decision {
        case .weakenedDSPDelta, .restoredStageInput:
            break
        case .acceptedDSPOutput:
            Issue.record("保護成分と重なるDSP差分が固定方向ルールなしで制限されませんでした")
        }
    }

    @Test("別roleの時系列profileを混在させない")
    func rejectsMismatchedRoleProfiles() throws {
        let signal = makeRoleProtectionSignal()
        let vocals = try StemRoleAnalysisService().analyzeWithProtection(
            role: .vocals,
            processingSignal48000: signal
        ).protectionProfile
        let drums = try StemRoleAnalysisService().analyzeWithProtection(
            role: .drums,
            processingSignal48000: signal
        ).protectionProfile

        #expect(throws: StemRoleProtectionGuardError.profileMismatch) {
            try StemRoleProtectionGuardService().protect(
                role: .vocals,
                stageInput: signal,
                proposedOutput: AudioSignal(
                    channels: signal.channels.map { $0.map { $0 * 0.8 } },
                    sampleRate: signal.sampleRate
                ),
                rawProfile: vocals,
                inputProfile: drums
            )
        }
    }

    @Test("明確な極性反転を作ったDSPをその工程で特定して直前Stemへ戻す", arguments: StemRole.allCases)
    func restoresStageInputForPolarityInversion(role: StemRole) throws {
        let input = makeRoleProtectionSignal()
        let inverted = AudioSignal(
            channels: input.channels.map { $0.map { -$0 } },
            sampleRate: input.sampleRate
        )
        let profile = try StemRoleAnalysisService().analyzeWithProtection(
            role: role,
            processingSignal48000: input
        ).protectionProfile

        let result = try StemRoleProtectionGuardService().protect(
            role: role,
            stageInput: input,
            proposedOutput: inverted,
            rawProfile: profile,
            inputProfile: profile
        )

        #expect(result.signal.channels == input.channels)
        if case .restoredStageInput = result.decision {
            // expected
        } else {
            Issue.record("極性反転を作ったDSPが処理直前Stemへ戻されませんでした")
        }
        let summary = try #require(result.summary)
        #expect(summary.affectedTimeRatio == 1)
        #expect(summary.averageRetainedDSPDeltaRatio == 0)
        #expect(summary.minimumRetainedDSPDeltaRatio == 0)
        #expect(summary.restorationReason == .clearPolarityInversion)
    }
}

private func makeRoleProtectionSignal(frameCount: Int = 12_288) -> AudioSignal {
    let sampleRate = 48_000.0
    var left = Array(repeating: Float.zero, count: frameCount)
    var right = Array(repeating: Float.zero, count: frameCount)
    for index in 0..<frameCount {
        let time = Double(index) / sampleRate
        let envelope = 0.5 + 0.5 * sin(2 * .pi * 2.7 * time)
        let transient = index.isMultiple(of: 2_400) ? 0.35 : 0
        left[index] = Float(
            envelope * (
                0.26 * sin(2 * .pi * 55 * time)
                    + 0.22 * sin(2 * .pi * 165 * time)
                    + 0.12 * sin(2 * .pi * 2_700 * time)
                    + 0.06 * sin(2 * .pi * 7_500 * time)
            ) + transient
        )
        right[index] = Float(
            envelope * (
                0.25 * sin(2 * .pi * 55 * time + 0.02)
                    + 0.20 * sin(2 * .pi * 220 * time)
                    + 0.10 * sin(2 * .pi * 3_200 * time + 0.1)
                    + 0.05 * sin(2 * .pi * 8_200 * time)
            ) + transient * 0.82
        )
    }
    return AudioSignal(channels: [left, right], sampleRate: sampleRate)
}
