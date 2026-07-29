import Foundation
import Testing
@testable import VelouraLucent

struct StemProductionInferenceTests {
    /// 固定モデルと同梱MLX runtimeを使う明示実行専用のproduction smoke testです。
    /// `VELOURA_RUN_STEM_MODEL_INTEGRATION=1 swift test --filter StemProductionInferenceTests`
    @Test
    func currentThreeStageWorkflowCompletesWithInstalledProductionModelWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["VELOURA_RUN_STEM_MODEL_INTEGRATION"] == "1" else {
            return
        }

        #if arch(arm64)
        let temporaryMetalBundle = try Self.installMetalBundleForSwiftPMTest()
        defer {
            if let temporaryMetalBundle {
                try? FileManager.default.removeItem(at: temporaryMetalBundle)
            }
        }
        let inspection = await ProductionStemModelLocalInspector().inspect()
        let manifest = try #require(inspection.validatedManifest)
        guard case .ready(let installation) = inspection.installedModel else {
            Issue.record("右サイドのStem分離で確認済みの固定モデルがありません")
            return
        }
        let root = FileManager.default.temporaryDirectory
            .appending(path: "StemProductionInferenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let inputURL = root.appending(path: "synthetic-input.wav")
        try AudioFileService.saveAudio(Self.syntheticSignal(durationSeconds: 0.5), to: inputURL)
        let sessionID = UUID()
        let workflow = StemWorkflowService()
        defer { try? workflow.discardTemporarySession(runID: sessionID) }

        let correction = try await workflow.processCorrection(StemWorkflowRequest(
            runID: sessionID,
            sourceURL: inputURL,
            userConfirmedMatrix: nil,
            installation: installation,
            manifest: manifest,
            separationSettings: StemSeparationSettings.metaHTDemucsProduction(seed: 20_260_719),
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringSettings: MasteringProfile.natural.settings,
            analysisMode: .cpu
        ))

        #expect(correction.stemEvaluations.count == 4)
        #expect(correction.stemEvaluations.allSatisfy { $0.correctedArtifact != nil })

        let remix = try await workflow.processRemix(
            correction: correction,
            settings: correction.automaticRemixPlan.settings
        )
        let result = try await workflow.processMastering(.init(
            remix: remix,
            masteringSettings: MasteringProfile.natural.settings
        ))
        #expect(result.mastering.finalArtifact.kind == .finalMaster)
        #expect(FileManager.default.fileExists(atPath: result.mastering.finalArtifact.fileURL.path))
        #else
        Issue.record("実モデルStem推論はApple Silicon専用です")
        #endif
    }

    private static func syntheticSignal(durationSeconds: Double) -> AudioSignal {
        let sampleRate = 44_100.0
        let frameCount = Int(sampleRate * durationSeconds)
        let left = (0..<frameCount).map { frame -> Float in
            let time = Double(frame) / sampleRate
            return Float(0.16 * sin(2 * .pi * 220 * time) + 0.07 * sin(2 * .pi * 880 * time))
        }
        let right = (0..<frameCount).map { frame -> Float in
            let time = Double(frame) / sampleRate
            return Float(0.15 * sin(2 * .pi * 220 * time + 0.08) + 0.06 * sin(2 * .pi * 1_320 * time))
        }
        return AudioSignal(channels: [left, right], sampleRate: sampleRate)
    }

    private static func installMetalBundleForSwiftPMTest() throws -> URL? {
        let resourceRoot = try #require(AppResourceBundle.resourceURL)
        let sourceURL = resourceRoot.appending(path: "StemModels/MLX/mlx.metallib")
        try #require(FileManager.default.fileExists(atPath: sourceURL.path))
        let bundleURL = resourceRoot.appending(path: "mlx-swift_Cmlx.bundle", directoryHint: .isDirectory)
        let resourcesURL = bundleURL.appending(path: "Contents/Resources", directoryHint: .isDirectory)
        let destinationURL = resourcesURL.appending(path: "default.metallib")
        if FileManager.default.fileExists(atPath: destinationURL.path) { return nil }
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        do {
            try FileManager.default.linkItem(at: sourceURL, to: destinationURL)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
        return bundleURL
    }
}
