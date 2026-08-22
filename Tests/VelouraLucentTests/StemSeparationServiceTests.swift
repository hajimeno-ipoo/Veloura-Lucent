import Foundation
import Testing
@testable import VelouraLucent

private struct StubStemBackendFactory: StemSeparationBackendCreating {
    let output: StemSeparationBackendOutput

    func makeBackend(configuration: StemSeparationBackendConfiguration) async throws -> any StemSeparationBackend {
        StubStemBackend(output: output)
    }
}

private struct FailingValidationStemArtifactStore: StemSeparationArtifactStoring {
    let base = StemTemporaryAudioStore()
    let failingRole: StemRole

    func save(
        signal: AudioSignal,
        id: String,
        kind: StemArtifactKind,
        to url: URL
    ) async throws -> StemAudioArtifact {
        try await base.save(signal: signal, id: id, kind: kind, to: url)
    }

    func validate(
        artifact: StemAudioArtifact,
        expectedURL: URL,
        expectedKind: StemArtifactKind
    ) async throws -> StemAudioArtifactValidationReport {
        if expectedKind == .rawStem(failingRole) {
            throw StemTemporaryAudioStoreError.formatMismatch("forced validation failure")
        }
        return try await base.validate(
            artifact: artifact,
            expectedURL: expectedURL,
            expectedKind: expectedKind
        )
    }

    func load(
        artifact: StemAudioArtifact,
        expectedURL: URL,
        expectedKind: StemArtifactKind
    ) async throws -> AudioSignal {
        try await base.load(
            artifact: artifact,
            expectedURL: expectedURL,
            expectedKind: expectedKind
        )
    }

    func removeIfPresent(_ url: URL) throws {
        try base.removeIfPresent(url)
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
        let bsProfile = StemProductionModelProfile.profile(for: .bsRoformerSW)
        let bsContract = StemModelContract(
            separationModel: .bsRoformerSW,
            identifier: "MrSimmo/BS_Roformer_SW-MLX:bs-roformer-sw",
            version: sourceContract.version,
            assetSetIdentifier: sourceContract.assetSetIdentifier,
            inputName: sourceContract.inputName,
            outputNames: Dictionary(
                uniqueKeysWithValues: bsProfile.sourceOrder.map { ($0, $0.rawValue) }
            ),
            sourceOrder: bsProfile.sourceOrder,
            sampleRate: sourceContract.sampleRate,
            channelCount: sourceContract.channelCount,
            inputShape: sourceContract.inputShape,
            outputShapes: Dictionary(
                uniqueKeysWithValues: bsProfile.sourceOrder.map { ($0, [-1, 2, -1]) }
            ),
            scalarType: sourceContract.scalarType,
            normalization: sourceContract.normalization,
            runtime: sourceContract.runtime,
            defaultSegmentSeconds: nil,
            downloadableModelAssets: sourceContract.downloadableModelAssets,
            bundledRuntimeAssets: sourceContract.bundledRuntimeAssets,
            runContract: makeStemTestRunContract(model: .bsRoformerSW)
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
                output: Self.backendOutput(from: inputSignal, model: .bsRoformerSW)
            )
        )

        let outputDirectory = directory.appending(path: "stems", directoryHint: .isDirectory)
        let result = try await service.separate(
            inputArtifact: input,
            installation: installation,
            settings: .bsRoformerSWProduction,
            outputDirectory: outputDirectory,
            progressHandler: { _ in }
        )

        let configuration = try #require(await recorder.configuration)
        #expect(configuration.model == .bsRoformerSW)
        #expect(configuration.modelWeightsURL.lastPathComponent == "bs_roformer_sw.safetensors")
        #expect(configuration.modelConfigurationURL.lastPathComponent == "bs_roformer_sw_config.json")
        #expect(configuration.seed == nil)
        #expect(result.stems.map(\.kind) == bsProfile.sourceOrder.map { .rawStem($0) })
        #expect(result.stems.map { $0.fileURL.lastPathComponent } == [
            "raw-bass.wav",
            "raw-drums.wav",
            "raw-other.wav",
            "raw-vocals.wav",
            "raw-guitar.wav",
            "raw-piano.wav",
        ])
        #expect(result.stems.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })
        for role in bsProfile.sourceOrder {
            let artifact = try #require(result.stems.first { $0.kind == .rawStem(role) })
            let savedSignal = try await store.load(
                artifact: artifact,
                expectedURL: artifact.fileURL,
                expectedKind: .rawStem(role)
            )
            #expect(savedSignal.channels == inputSignal.channels)
        }
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

        #expect(Set(result.stems.map(\.kind)) == Set(
            makeStemTestRunContract().activeRoles.map { StemArtifactKind.rawStem($0) }
        ))
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

    @Test
    func bsSixStemFailureRemovesEarlierFilesAndDoesNotFallbackToFourStems() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeStemTestInstallation(rootURL: directory, model: .bsRoformerSW)
        let store = StemTemporaryAudioStore()
        let inputSignal = makeStemTestSignal()
        let input = try await store.save(
            signal: inputSignal,
            id: "input",
            kind: .input44100,
            to: directory.appending(path: "input.wav")
        )
        let outputDirectory = directory.appending(path: "stems", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let existingGuitarURL = outputDirectory.appending(path: "raw-guitar.wav")
        let existingGuitar = try await store.save(
            signal: inputSignal,
            id: "existing-guitar",
            kind: .rawStem(.guitar),
            to: existingGuitarURL
        )
        let service = StemSeparationService(
            artifactStore: store,
            backendFactory: StubStemBackendFactory(
                output: Self.backendOutput(from: inputSignal, model: .bsRoformerSW)
            )
        )

        await #expect(throws: StemTemporaryAudioStoreError.outputAlreadyExists(existingGuitarURL.path)) {
            _ = try await service.separate(
                inputArtifact: input,
                installation: fixture.installation,
                settings: .bsRoformerSWProduction,
                outputDirectory: outputDirectory,
                progressHandler: { _ in }
            )
        }

        _ = try await store.validate(
            artifact: existingGuitar,
            expectedURL: existingGuitarURL,
            expectedKind: .rawStem(.guitar)
        )
        let wavFiles = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "wav" }
        #expect(wavFiles.map(\.lastPathComponent) == ["raw-guitar.wav"])
    }

    @Test
    func bsSixStemValidationFailureRemovesEveryFileCreatedByTheAttempt() async throws {
        let directory = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try makeStemTestInstallation(rootURL: directory, model: .bsRoformerSW)
        let baseStore = StemTemporaryAudioStore()
        let inputSignal = makeStemTestSignal()
        let input = try await baseStore.save(
            signal: inputSignal,
            id: "input",
            kind: .input44100,
            to: directory.appending(path: "input.wav")
        )
        let outputDirectory = directory.appending(path: "stems", directoryHint: .isDirectory)
        let service = StemSeparationService(
            artifactStore: FailingValidationStemArtifactStore(failingRole: .guitar),
            backendFactory: StubStemBackendFactory(
                output: Self.backendOutput(from: inputSignal, model: .bsRoformerSW)
            )
        )

        await #expect(
            throws: StemTemporaryAudioStoreError.formatMismatch("forced validation failure")
        ) {
            _ = try await service.separate(
                inputArtifact: input,
                installation: fixture.installation,
                settings: .bsRoformerSWProduction,
                outputDirectory: outputDirectory,
                progressHandler: { _ in }
            )
        }

        let wavFiles = (try? FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil
        ))?.filter { $0.pathExtension == "wav" } ?? []
        #expect(wavFiles.isEmpty)
    }

    @Test
    func bsSixStemRejectsInvalidRateChannelsFramesAndNonFiniteSamplesBeforeSaving() async throws {
        let inputSignal = makeStemTestSignal()
        let validSamples = inputSignal.channels.flatMap { $0 }
        let invalidCases: [(StemRole, StemSeparationPCM, StemSeparationServiceError)] = [
            (
                .piano,
                StemSeparationPCM(
                    channelMajorSamples: validSamples,
                    channelCount: 2,
                    sampleRate: 48_000
                ),
                .outputSampleRateMismatch(role: .piano, expected: 44_100, actual: 48_000)
            ),
            (
                .guitar,
                StemSeparationPCM(
                    channelMajorSamples: validSamples,
                    channelCount: 1,
                    sampleRate: 44_100
                ),
                .outputChannelCountMismatch(role: .guitar, expected: 2, actual: 1)
            ),
            (
                .piano,
                StemSeparationPCM(
                    channelMajorSamples: Array(validSamples.dropLast()),
                    channelCount: 2,
                    sampleRate: 44_100
                ),
                .outputSampleCountMismatch(role: .piano, expected: validSamples.count, actual: validSamples.count - 1)
            ),
            (
                .guitar,
                StemSeparationPCM(
                    channelMajorSamples: [.nan] + Array(validSamples.dropFirst()),
                    channelCount: 2,
                    sampleRate: 44_100
                ),
                .nonFiniteOutputSample(role: .guitar, channel: 0, frame: 0)
            ),
        ]

        for (role, invalidStem, expectedError) in invalidCases {
            let directory = try Self.temporaryDirectory()
            let fixture = try makeStemTestInstallation(rootURL: directory, model: .bsRoformerSW)
            let store = StemTemporaryAudioStore()
            let input = try await store.save(
                signal: inputSignal,
                id: "input",
                kind: .input44100,
                to: directory.appending(path: "input.wav")
            )
            var output = Self.backendOutput(from: inputSignal, model: .bsRoformerSW).stems
            output[role.rawValue] = invalidStem
            let outputDirectory = directory.appending(path: "stems", directoryHint: .isDirectory)
            let service = StemSeparationService(
                artifactStore: store,
                backendFactory: StubStemBackendFactory(
                    output: StemSeparationBackendOutput(stems: output)
                )
            )

            await #expect(throws: expectedError) {
                _ = try await service.separate(
                    inputArtifact: input,
                    installation: fixture.installation,
                    settings: .bsRoformerSWProduction,
                    outputDirectory: outputDirectory,
                    progressHandler: { _ in }
                )
            }
            let savedFiles = (try? FileManager.default.contentsOfDirectory(
                at: outputDirectory,
                includingPropertiesForKeys: nil
            )) ?? []
            #expect(savedFiles.filter { $0.pathExtension == "wav" }.isEmpty)
            try FileManager.default.removeItem(at: directory)
        }
    }

    private static func backendOutput(
        from signal: AudioSignal,
        model: StemSeparationModel = .htdemucs
    ) -> StemSeparationBackendOutput {
        var stems: [String: StemSeparationPCM] = [:]
        for role in StemProductionModelProfile.profile(for: model).sourceOrder {
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
