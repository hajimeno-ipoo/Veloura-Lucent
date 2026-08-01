import Foundation
import Testing
@testable import VelouraLucent

private struct StubStemBackendFactory: StemSeparationBackendCreating {
    let output: StemSeparationBackendOutput

    func makeBackend(configuration: StemSeparationBackendConfiguration) async throws -> any StemSeparationBackend {
        StubStemBackend(output: output)
    }
}

private actor StemBackendConfigurationRecorder {
    private var configurationStorage: StemSeparationBackendConfiguration?

    func record(_ configuration: StemSeparationBackendConfiguration) {
        configurationStorage = configuration
    }

    var configuration: StemSeparationBackendConfiguration? {
        configurationStorage
    }
}

private struct RecordingStemBackendFactory: StemSeparationBackendCreating {
    let recorder: StemBackendConfigurationRecorder
    let output: StemSeparationBackendOutput

    func makeBackend(
        configuration: StemSeparationBackendConfiguration
    ) async throws -> any StemSeparationBackend {
        await recorder.record(configuration)
        return StubStemBackend(output: output)
    }
}

private struct StubStemBackend: StemSeparationBackend {
    let output: StemSeparationBackendOutput

    func separate(
        input: StemSeparationPCM,
        cancellationToken: StemSeparationCancellationToken,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> StemSeparationBackendOutput {
        try Task.checkCancellation()
        progressHandler(1, "分離完了")
        return output
    }
}

struct StemSeparationServiceTests {
    @Test
    func bsRoformerSelectionReachesBackendWithValidatedModelAssets() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeStemTestInstallation(rootURL: directory)
        let sourceContract = fixture.installation.snapshot.contract
        let bsContract = StemModelContract(
            separationModel: .bsRoformerSW,
            identifier: "MrSimmo/BS_Roformer_SW-MLX:bs-roformer-sw",
            version: sourceContract.version,
            assetSetIdentifier: sourceContract.assetSetIdentifier,
            inputName: sourceContract.inputName,
            outputNames: sourceContract.outputNames,
            sourceOrder: sourceContract.sourceOrder,
            sampleRate: sourceContract.sampleRate,
            channelCount: sourceContract.channelCount,
            inputShape: sourceContract.inputShape,
            outputShapes: sourceContract.outputShapes,
            scalarType: sourceContract.scalarType,
            normalization: sourceContract.normalization,
            runtime: sourceContract.runtime,
            defaultSegmentSeconds: nil,
            downloadableModelAssets: sourceContract.downloadableModelAssets,
            bundledRuntimeAssets: sourceContract.bundledRuntimeAssets
        )
        let installation = ValidatedStemModelInstallation(
            snapshot: ValidatedStemModelSnapshot(
                contract: bsContract,
                installationRootURL: fixture.installation.snapshot.installationRootURL,
                modelDirectoryURL: fixture.installation.snapshot.installationRootURL
                    .appending(path: "bs-roformer-sw", directoryHint: .isDirectory),
                assets: fixture.installation.snapshot.assets.map { asset in
                    ValidatedStemModelAsset(
                        kind: asset.kind,
                        fileURL: fixture.installation.snapshot.installationRootURL.appending(
                            path: asset.kind == .modelWeights
                                ? "bs-roformer-sw/bs_roformer_sw.safetensors"
                                : "bs-roformer-sw/bs_roformer_sw_config.json"
                        ),
                        byteCount: asset.byteCount,
                        sha256: asset.sha256
                    )
                }
            ),
            receipt: fixture.installation.receipt,
            generationDirectoryURL: fixture.installation.generationDirectoryURL
        )
        let store = StemTemporaryAudioStore()
        let inputSignal = makeStemTestSignal()
        let input = try await store.save(
            signal: inputSignal,
            id: "input",
            kind: .input44100,
            to: directory.appending(path: "input.wav")
        )
        let recorder = StemBackendConfigurationRecorder()
        let service = StemSeparationService(
            artifactStore: store,
            backendFactory: RecordingStemBackendFactory(
                recorder: recorder,
                output: Self.backendOutput(from: inputSignal)
            )
        )

        _ = try await service.separate(
            inputArtifact: input,
            installation: installation,
            settings: .bsRoformerSWProduction,
            outputDirectory: directory.appending(path: "stems", directoryHint: .isDirectory),
            progressHandler: { _ in }
        )

        let configuration = try #require(await recorder.configuration)
        #expect(configuration.model == .bsRoformerSW)
        #expect(configuration.modelWeightsURL.lastPathComponent == "bs_roformer_sw.safetensors")
        #expect(configuration.modelConfigurationURL.lastPathComponent == "bs_roformer_sw_config.json")
        #expect(configuration.seed == nil)
    }

    @Test
    func writesExactlyFourValidatedRawStems() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeStemTestInstallation(rootURL: directory)
        let store = StemTemporaryAudioStore()
        let inputURL = directory.appending(path: "input.wav")
        let inputSignal = makeStemTestSignal()
        let input = try await store.save(
            signal: inputSignal,
            id: "input",
            kind: .input44100,
            to: inputURL
        )
        let service = StemSeparationService(
            artifactStore: store,
            backendFactory: StubStemBackendFactory(output: Self.backendOutput(from: inputSignal))
        )
        let outputDirectory = directory.appending(path: "stems", directoryHint: .isDirectory)

        let result = try await service.separate(
            inputArtifact: input,
            installation: fixture.installation,
            settings: StemSeparationSettings.metaHTDemucsProduction(seed: 7),
            outputDirectory: outputDirectory,
            progressHandler: { _ in }
        )

        #expect(Set(result.stems.map(\.kind)) == Set(StemRole.allCases.map { StemArtifactKind.rawStem($0) }))
        #expect(result.stems.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
        #expect(result.stems.allSatisfy { $0.sampleRate == 44_100 && $0.channelCount == 2 })
    }

    @Test
    func invalidBackendOutputPublishesNoRawStemFiles() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeStemTestInstallation(rootURL: directory)
        let store = StemTemporaryAudioStore()
        let inputSignal = makeStemTestSignal()
        let inputURL = directory.appending(path: "input.wav")
        let input = try await store.save(
            signal: inputSignal,
            id: "input",
            kind: .input44100,
            to: inputURL
        )
        var invalid = Self.backendOutput(from: inputSignal).stems
        invalid.removeValue(forKey: StemRole.vocals.rawValue)
        let outputDirectory = directory.appending(path: "stems", directoryHint: .isDirectory)
        let service = StemSeparationService(
            artifactStore: store,
            backendFactory: StubStemBackendFactory(output: StemSeparationBackendOutput(stems: invalid))
        )

        await #expect(throws: StemSeparationServiceError.outputStemCountMismatch(expected: 4, actual: 3)) {
            _ = try await service.separate(
                inputArtifact: input,
                installation: fixture.installation,
                settings: StemSeparationSettings.metaHTDemucsProduction(seed: 7),
                outputDirectory: outputDirectory,
                progressHandler: { _ in }
            )
        }

        let files = (try? FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        #expect(files.filter { $0.pathExtension == "wav" }.isEmpty)
    }

    @Test
    func failedAttemptPreservesPreexistingFileAndRemovesOnlyFilesCreatedByThatAttempt() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeStemTestInstallation(rootURL: directory)
        let store = StemTemporaryAudioStore()
        let inputSignal = makeStemTestSignal()
        let inputURL = directory.appending(path: "input.wav")
        let input = try await store.save(
            signal: inputSignal,
            id: "input",
            kind: .input44100,
            to: inputURL
        )
        let outputDirectory = directory.appending(path: "stems", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let existingURL = outputDirectory.appending(path: "raw-drums.wav")
        let existing = try await store.save(
            signal: inputSignal,
            id: "existing-drums",
            kind: .rawStem(.drums),
            to: existingURL
        )
        let service = StemSeparationService(
            artifactStore: store,
            backendFactory: StubStemBackendFactory(output: Self.backendOutput(from: inputSignal))
        )

        await #expect(throws: StemTemporaryAudioStoreError.outputAlreadyExists(existingURL.path)) {
            _ = try await service.separate(
                inputArtifact: input,
                installation: fixture.installation,
                settings: StemSeparationSettings.metaHTDemucsProduction(seed: 7),
                outputDirectory: outputDirectory,
                progressHandler: { _ in }
            )
        }

        _ = try await store.validate(
            artifact: existing,
            expectedURL: existingURL,
            expectedKind: .rawStem(.drums)
        )
        let files = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        )
        let wavFiles = files.filter { $0.pathExtension == "wav" }
        #expect(wavFiles.count == 1)
        #expect(wavFiles.first?.lastPathComponent == existingURL.lastPathComponent)
    }

    private static func backendOutput(from signal: AudioSignal) -> StemSeparationBackendOutput {
        var stems: [String: StemSeparationPCM] = [:]
        for role in StemRole.allCases {
            stems[role.rawValue] = StemSeparationPCM(
                channelMajorSamples: signal.channels.flatMap { $0 },
                channelCount: 2,
                sampleRate: 44_100
            )
        }
        return StemSeparationBackendOutput(stems: stems)
    }

    private static func temporaryDirectory() throws -> URL {
        let URL = FileManager.default.temporaryDirectory
            .appending(path: "StemSeparationServiceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: URL, withIntermediateDirectories: true)
        return URL
    }
}
