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
            runContract: installation.snapshot.contract.runContract,
            sourceURL: inputURL,
            userConfirmedMatrix: nil,
            installation: installation,
            manifest: manifest,
            separationSettings: StemSeparationSettings.metaHTDemucsProduction(seed: 20_260_719),
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringSettings: MasteringProfile.natural.settings,
            analysisMode: .cpu
        ))

        #expect(correction.stemEvaluations.count == correction.runContract.validationRoles.count)
        #expect(
            Set(correction.stemEvaluations.map(\.role))
                == Set(correction.runContract.validationRoles)
        )
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

    /// 公開BS-RoFormer-SW資産とユーザー指定の実音源を、アプリ本体と同じ
    /// Stem分離 → Stem補正 → 再ミックス → マスタリング経路へ通す明示実行専用テストです。
    /// `VELOURA_RUN_BS_ROFORMER_INTEGRATION=1 swift test -c release --filter bsRoformer`
    @Test
    func bsRoformerFullWorkflowCompletesWithPinnedPublicModelWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["VELOURA_RUN_BS_ROFORMER_INTEGRATION"] == "1" else {
            return
        }

        #if arch(arm64)
        let temporaryMetalBundle = try Self.installMetalBundleForSwiftPMTest()
        defer {
            if let temporaryMetalBundle {
                try? FileManager.default.removeItem(at: temporaryMetalBundle)
            }
        }

        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let revision = StemProductionModelProfile.profile(for: .bsRoformerSW).revision
        let cachedAssets = projectRoot
            .appending(path: ".stem-model-cache/bs-roformer-sw/\(revision)", directoryHint: .isDirectory)
        let inputURL = projectRoot
            .appending(path: "Tests/Fixtures/Sample_audio/星屑のシンパシー.wav")

        let root = FileManager.default.temporaryDirectory
            .appending(path: "BSRoformerProductionInferenceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let validator = StemModelAssetValidator(selectedModel: .bsRoformerSW)
        let manifest = try validator.loadBundledManifest()
        for asset in manifest.downloadableModelAssets {
            let sourceURL = cachedAssets.appending(path: URL(filePath: asset.installationRelativePath).lastPathComponent)
            let destinationURL = try StemModelAssetValidator.safeDescendantURL(
                rootURL: root,
                relativePath: asset.installationRelativePath,
                field: "integrationAsset"
            )
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try FileManager.default.linkItem(at: sourceURL, to: destinationURL)
            } catch {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
        }

        let snapshot = try validator.validateStagedModelAssets(
            manifest: manifest,
            rootURL: root
        )
        let assetDefinitions = Dictionary(
            uniqueKeysWithValues: manifest.downloadableModelAssets.map { ($0.kind, $0) }
        )
        let generationIdentifier = UUID()
        let receipt = StemModelInstallationReceipt(
            schemaVersion: StemModelInstallationReceipt.currentSchemaVersion,
            assetSetIdentifier: manifest.assetSetIdentifier,
            modelIdentifier: snapshot.contract.identifier,
            revision: manifest.model.revision,
            generationIdentifier: generationIdentifier,
            activatedAt: Date(),
            assets: try snapshot.assets.map { validatedAsset in
                StemModelInstallationReceiptAsset(
                    kind: validatedAsset.kind,
                    installationRelativePath: try #require(
                        assetDefinitions[validatedAsset.kind]
                    ).installationRelativePath,
                    byteCount: validatedAsset.byteCount,
                    sha256: validatedAsset.sha256
                )
            },
            sourceEvidence: manifest.downloadableModelAssets.map {
                StemModelInstallationSourceEvidence(
                    kind: $0.kind,
                    stableDownloadURL: $0.downloadURL,
                    responseHeaderName: manifest.downloadPolicy.revisionResponseHeader,
                    revision: manifest.model.revision
                )
            }
        )
        let installation = ValidatedStemModelInstallation(
            snapshot: snapshot,
            receipt: receipt,
            generationDirectoryURL: root
        )
        let sessionID = UUID()
        let workflow = StemWorkflowService()
        defer { try? workflow.discardTemporarySession(runID: sessionID) }

        let correction = try await workflow.processCorrection(StemWorkflowRequest(
            runID: sessionID,
            runContract: installation.snapshot.contract.runContract,
            sourceURL: inputURL,
            userConfirmedMatrix: nil,
            installation: installation,
            manifest: manifest,
            separationSettings: .bsRoformerSWProduction,
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringSettings: MasteringProfile.natural.settings,
            analysisMode: .cpu
        ))
        let expectedRoles = installation.snapshot.contract.runContract.validationRoles
        #expect(correction.runContract.separationModel == .bsRoformerSW)
        #expect(expectedRoles == [.bass, .drums, .other, .vocals, .guitar, .piano])
        #expect(correction.separation.stems.count == expectedRoles.count)
        #expect(correction.stemEvaluations.count == expectedRoles.count)
        #expect(Set(correction.stemEvaluations.map(\.role)) == Set(expectedRoles))
        #expect(correction.stemEvaluations.allSatisfy { $0.correctedArtifact != nil })
        for role in [StemRole.guitar, .piano] {
            let evaluation = try #require(
                correction.stemEvaluations.first { $0.role == role }
            )
            #expect(evaluation.rawArtifact.kind == .rawStem(role))
            #expect(evaluation.correctedArtifact?.kind == .correctedStem(role))
            #expect(FileManager.default.fileExists(atPath: evaluation.rawArtifact.fileURL.path))
            #expect(
                FileManager.default.fileExists(
                    atPath: try #require(evaluation.correctedArtifact).fileURL.path
                )
            )
        }

        let remix = try await workflow.processRemix(
            correction: correction,
            settings: correction.automaticRemixPlan.settings
        )
        let result = try await workflow.processMastering(.init(
            remix: remix,
            masteringSettings: MasteringProfile.natural.settings
        ))
        #expect(result.runContract == correction.runContract)
        #expect(result.stemEvaluations.count == expectedRoles.count)
        #expect(FileManager.default.fileExists(atPath: result.remixedArtifact.fileURL.path))
        #expect(result.mastering.finalArtifact.kind == .finalMaster)
        #expect(FileManager.default.fileExists(atPath: result.mastering.finalArtifact.fileURL.path))
        #else
        Issue.record("実モデルStem推論はApple Silicon専用です")
        #endif
    }

    /// 実BS-RoFormer-SWの短い互換性音源で全工程を完了し、補正済みGuitar／Pianoを
    /// 画面と同じproduction exporterで全4形式へ個別書き出しする明示実行専用テストです。
    @Test
    func bsRoformerGuitarAndPianoExportThroughProductionFormatsWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["VELOURA_RUN_BS_ROFORMER_INTEGRATION"] == "1" else {
            return
        }

        #if arch(arm64)
        let temporaryMetalBundle = try Self.installMetalBundleForSwiftPMTest()
        defer {
            if let temporaryMetalBundle {
                try? FileManager.default.removeItem(at: temporaryMetalBundle)
            }
        }
        let root = FileManager.default.temporaryDirectory
            .appending(path: "BSRoformerExportIntegrationTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let (manifest, installation) = try Self.makeCachedInstallation(
            model: .bsRoformerSW,
            projectRoot: Self.projectRoot,
            installationRoot: root.appending(path: "model", directoryHint: .isDirectory)
        )
        let inputURL = Self.projectRoot.appending(
            path: ".stem-model-cache/bs-roformer-sw/compatibility-input/sample-6.8s-44100-f32.wav"
        )
        try #require(FileManager.default.fileExists(atPath: inputURL.path))

        let sessionID = UUID()
        let workflow = StemWorkflowService()
        defer { try? workflow.discardTemporarySession(runID: sessionID) }
        let correction = try await workflow.processCorrection(StemWorkflowRequest(
            runID: sessionID,
            runContract: installation.snapshot.contract.runContract,
            sourceURL: inputURL,
            userConfirmedMatrix: nil,
            installation: installation,
            manifest: manifest,
            separationSettings: .bsRoformerSWProduction,
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringSettings: MasteringProfile.natural.settings,
            analysisMode: .cpu
        ))
        let remix = try await workflow.processRemix(
            correction: correction,
            settings: correction.automaticRemixPlan.settings
        )
        let result = try await workflow.processMastering(.init(
            remix: remix,
            masteringSettings: MasteringProfile.natural.settings
        ))
        #expect(result.runContract.validationRoles == [
            .bass, .drums, .other, .vocals, .guitar, .piano,
        ])

        let exportDirectory = root.appending(path: "exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let exporter = ProductionStemWorkflowArtifactExporter()
        for role in [StemRole.guitar, .piano] {
            let artifact = try #require(
                result.stemEvaluations.first { $0.role == role }?.correctedArtifact
            )
            #expect(artifact.kind == .correctedStem(role))
            for format in AudioExportFormat.allCases {
                let destinationURL = exportDirectory.appending(
                    path: "\(role.rawValue)-\(format.rawValue).\(format.fileExtension)"
                )
                try await exporter.export(
                    sourceURL: artifact.fileURL,
                    destinationURL: destinationURL,
                    format: format
                )
                let fileInfo = try AudioFileService.fileInfo(for: destinationURL)
                #expect(FileManager.default.fileExists(atPath: destinationURL.path))
                #expect(fileInfo.channelCount == artifact.channelCount)
                #expect(fileInfo.duration > 0)
                #expect(fileInfo.sampleRate == (format == .cdWAV ? 44_100 : 48_000))
            }
        }
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: exportDirectory.path).count
                == 2 * AudioExportFormat.allCases.count
        )
        #else
        Issue.record("実モデルStem推論はApple Silicon専用です")
        #endif
    }

    /// HTDemucsとBS-RoFormer-SWを同じ入力・Release条件で比較する明示実行専用benchmarkです。
    /// 最大RSSは、このtest processを`/usr/bin/time -l`で個別実行して記録します。
    ///
    /// `VELOURA_RUN_STEM_BASELINE_BENCHMARK=1 VELOURA_STEM_BASELINE_MODEL=htdemucs \
    ///   VELOURA_STEM_BASELINE_INPUT=.stem-model-cache/bs-roformer-sw/compatibility-input/sample-6.8s-44100-f32.wav \
    ///   swift test -c release --skip-build --filter productionBaselineMetricsForSelectedModelWhenEnabled`
    @Test
    func productionBaselineMetricsForSelectedModelWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["VELOURA_RUN_STEM_BASELINE_BENCHMARK"] == "1" else {
            return
        }

        #if arch(arm64)
        let modelName = try #require(environment["VELOURA_STEM_BASELINE_MODEL"])
        let model = try #require(
            StemSeparationModel(rawValue: modelName),
            "VELOURA_STEM_BASELINE_MODELはhtdemucsまたはbsRoformerSWを指定してください"
        )
        let projectRoot = Self.projectRoot
        let inputPath = environment["VELOURA_STEM_BASELINE_INPUT"]
            ?? ".stem-model-cache/bs-roformer-sw/compatibility-input/sample-6.8s-44100-f32.wav"
        let inputURL = inputPath.hasPrefix("/")
            ? URL(fileURLWithPath: inputPath)
            : projectRoot.appending(path: inputPath)
        try #require(FileManager.default.fileExists(atPath: inputURL.path))

        let temporaryMetalBundle = try Self.installMetalBundleForSwiftPMTest()
        defer {
            if let temporaryMetalBundle {
                try? FileManager.default.removeItem(at: temporaryMetalBundle)
            }
        }

        let installationRoot = FileManager.default.temporaryDirectory
            .appending(path: "StemBaselineModel-\(model.rawValue)-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: installationRoot) }
        try FileManager.default.createDirectory(at: installationRoot, withIntermediateDirectories: true)
        let (manifest, installation) = try Self.makeCachedInstallation(
            model: model,
            projectRoot: projectRoot,
            installationRoot: installationRoot
        )

        let sessionID = UUID()
        let workflow = StemWorkflowService()
        defer { try? workflow.discardTemporarySession(runID: sessionID) }
        let request = StemWorkflowRequest(
            runID: sessionID,
            runContract: installation.snapshot.contract.runContract,
            sourceURL: inputURL,
            userConfirmedMatrix: nil,
            installation: installation,
            manifest: manifest,
            separationSettings: model == .htdemucs
                ? .metaHTDemucsProduction(seed: 20_260_719)
                : .bsRoformerSWProduction,
            correctionSettings: StemRoleCorrectionSettings(all: DenoiseStrength.balanced.settings),
            masteringSettings: MasteringProfile.natural.settings,
            analysisMode: .cpu
        )

        let totalStart = Date()
        let correctionStart = Date()
        let correction = try await workflow.processCorrection(request)
        let correctionSeconds = Date().timeIntervalSince(correctionStart)
        let correctionStats = try Self.directoryStats(at: correction.sessionDirectory)

        let remixStart = Date()
        let remix = try await workflow.processRemix(
            correction: correction,
            settings: correction.automaticRemixPlan.settings
        )
        let remixSeconds = Date().timeIntervalSince(remixStart)
        let remixStats = try Self.directoryStats(at: correction.sessionDirectory)

        let masteringStart = Date()
        let result = try await workflow.processMastering(.init(
            remix: remix,
            masteringSettings: MasteringProfile.natural.settings
        ))
        let masteringSeconds = Date().timeIntervalSince(masteringStart)
        let masteringStats = try Self.directoryStats(at: correction.sessionDirectory)
        let totalSeconds = Date().timeIntervalSince(totalStart)

        #expect(correction.stemEvaluations.count == correction.runContract.validationRoles.count)
        #expect(
            Set(correction.stemEvaluations.map(\.role))
                == Set(correction.runContract.validationRoles)
        )
        #expect(result.mastering.finalArtifact.kind == .finalMaster)
        #expect(FileManager.default.fileExists(atPath: result.mastering.finalArtifact.fileURL.path))

        let canonicalArtifact = correction.input.artifact
        let peakTemporaryBytes = max(
            correctionStats.byteCount,
            remixStats.byteCount,
            masteringStats.byteCount
        )
        let peakArtifactCount = max(
            correctionStats.fileCount,
            remixStats.fileCount,
            masteringStats.fileCount
        )
        let metrics: [String: Any] = [
            "model": model.rawValue,
            "inputPath": inputURL.path,
            "inputDurationSeconds": Double(canonicalArtifact.frameCount) / canonicalArtifact.sampleRate,
            "inputFrameCount": canonicalArtifact.frameCount,
            "correctionSeconds": correctionSeconds,
            "remixSeconds": remixSeconds,
            "masteringSeconds": masteringSeconds,
            "totalSeconds": totalSeconds,
            "afterCorrectionArtifactCount": correctionStats.fileCount,
            "afterCorrectionBytes": correctionStats.byteCount,
            "afterRemixArtifactCount": remixStats.fileCount,
            "afterRemixBytes": remixStats.byteCount,
            "afterMasteringArtifactCount": masteringStats.fileCount,
            "afterMasteringBytes": masteringStats.byteCount,
            "peakArtifactCount": peakArtifactCount,
            "peakTemporaryBytes": peakTemporaryBytes,
        ]
        let metricsData = try JSONSerialization.data(withJSONObject: metrics, options: [.sortedKeys])
        let metricsJSON = try #require(String(data: metricsData, encoding: .utf8))
        print("VELOURA_STEM_BASELINE_METRICS \(metricsJSON)")
        #else
        Issue.record("実モデルStem推論はApple Silicon専用です")
        #endif
    }

    private struct DirectoryStats {
        let fileCount: Int
        let byteCount: Int64
    }

    private static var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func makeCachedInstallation(
        model: StemSeparationModel,
        projectRoot: URL,
        installationRoot: URL
    ) throws -> (StemModelManifest, ValidatedStemModelInstallation) {
        let validator = StemModelAssetValidator(selectedModel: model)
        let manifest = try validator.loadBundledManifest()
        let cacheDirectory: URL
        switch model {
        case .htdemucs:
            cacheDirectory = projectRoot.appending(path: ".stem-model-cache/htdemucs", directoryHint: .isDirectory)
        case .bsRoformerSW:
            cacheDirectory = projectRoot.appending(
                path: ".stem-model-cache/bs-roformer-sw/\(StemProductionModelProfile.profile(for: model).revision)",
                directoryHint: .isDirectory
            )
        }

        for asset in manifest.downloadableModelAssets {
            let sourceURL = cacheDirectory.appending(path: URL(filePath: asset.installationRelativePath).lastPathComponent)
            let destinationURL = try StemModelAssetValidator.safeDescendantURL(
                rootURL: installationRoot,
                relativePath: asset.installationRelativePath,
                field: "baselineAsset"
            )
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            do {
                try FileManager.default.linkItem(at: sourceURL, to: destinationURL)
            } catch {
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            }
        }

        let snapshot = try validator.validateStagedModelAssets(
            manifest: manifest,
            rootURL: installationRoot
        )
        let definitions = Dictionary(
            uniqueKeysWithValues: manifest.downloadableModelAssets.map { ($0.kind, $0) }
        )
        let receipt = StemModelInstallationReceipt(
            schemaVersion: StemModelInstallationReceipt.currentSchemaVersion,
            assetSetIdentifier: manifest.assetSetIdentifier,
            modelIdentifier: snapshot.contract.identifier,
            revision: manifest.model.revision,
            generationIdentifier: UUID(),
            activatedAt: Date(),
            assets: try snapshot.assets.map { validatedAsset in
                StemModelInstallationReceiptAsset(
                    kind: validatedAsset.kind,
                    installationRelativePath: try #require(
                        definitions[validatedAsset.kind]
                    ).installationRelativePath,
                    byteCount: validatedAsset.byteCount,
                    sha256: validatedAsset.sha256
                )
            },
            sourceEvidence: manifest.downloadableModelAssets.map {
                StemModelInstallationSourceEvidence(
                    kind: $0.kind,
                    stableDownloadURL: $0.downloadURL,
                    responseHeaderName: manifest.downloadPolicy.revisionResponseHeader,
                    revision: manifest.model.revision
                )
            }
        )
        return (
            manifest,
            ValidatedStemModelInstallation(
                snapshot: snapshot,
                receipt: receipt,
                generationDirectoryURL: installationRoot
            )
        )
    }

    private static func directoryStats(at directory: URL) throws -> DirectoryStats {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return DirectoryStats(fileCount: 0, byteCount: 0)
        }
        var fileCount = 0
        var byteCount: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            fileCount += 1
            byteCount += Int64(values.fileSize ?? 0)
        }
        return DirectoryStats(fileCount: fileCount, byteCount: byteCount)
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
