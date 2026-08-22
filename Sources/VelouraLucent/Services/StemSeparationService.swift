import DemucsMLX
import Foundation

struct StemSeparationProgress: Equatable, Sendable {
    let fraction: Double
    let detail: String
}

enum StemSeparationServiceError: LocalizedError, Equatable, Sendable {
    case invalidOutputDirectory(String)
    case missingModelAsset(StemModelAssetKind)
    case inputSampleRateMismatch(expected: Double, actual: Double)
    case inputChannelCountMismatch(expected: Int, actual: Int)
    case inputFrameCountMismatch(expected: Int, actual: Int)
    case nonFiniteInputSample(channel: Int, frame: Int)
    case outputStemCountMismatch(expected: Int, actual: Int)
    case missingOutputStem(StemRole)
    case unexpectedOutputStem(String)
    case outputSampleRateMismatch(role: StemRole, expected: Int, actual: Int)
    case outputChannelCountMismatch(role: StemRole, expected: Int, actual: Int)
    case outputSampleCountMismatch(role: StemRole, expected: Int, actual: Int)
    case nonFiniteOutputSample(role: StemRole, channel: Int, frame: Int)
    case cleanupFailed(originalFailure: String, cleanupFailures: [String])

    var errorDescription: String? {
        switch self {
        case .invalidOutputDirectory(let path):
            "Stem分離の出力先が安全なローカルディレクトリではありません（\(path)）。"
        case .missingModelAsset(let kind):
            "検証済みStemモデルに必要な資産がありません（\(kind.rawValue)）。"
        case let .inputSampleRateMismatch(expected, actual):
            "Stem分離入力のサンプルレートが一致しません（必要: \(expected) Hz、実際: \(actual) Hz）。"
        case let .inputChannelCountMismatch(expected, actual):
            "Stem分離入力のチャンネル数が一致しません（必要: \(expected)、実際: \(actual)）。"
        case let .inputFrameCountMismatch(expected, actual):
            "Stem分離入力のフレーム数が一致しません（必要: \(expected)、実際: \(actual)）。"
        case let .nonFiniteInputSample(channel, frame):
            "Stem分離入力にNaNまたはInfinityがあります（channel \(channel)、frame \(frame)）。"
        case let .outputStemCountMismatch(expected, actual):
            "Stem分離結果の数が一致しません（必要: \(expected)、実際: \(actual)）。"
        case .missingOutputStem(let role): "Stem分離結果に\(role.rawValue)がありません。"
        case .unexpectedOutputStem(let name): "Stem分離結果に契約外の出力があります（\(name)）。"
        case let .outputSampleRateMismatch(role, expected, actual):
            "\(role.rawValue)のサンプルレートが一致しません（必要: \(expected)、実際: \(actual)）。"
        case let .outputChannelCountMismatch(role, expected, actual):
            "\(role.rawValue)のチャンネル数が一致しません（必要: \(expected)、実際: \(actual)）。"
        case let .outputSampleCountMismatch(role, expected, actual):
            "\(role.rawValue)のサンプル数が一致しません（必要: \(expected)、実際: \(actual)）。"
        case let .nonFiniteOutputSample(role, channel, frame):
            "\(role.rawValue)にNaNまたはInfinityがあります（channel \(channel)、frame \(frame)）。"
        case let .cleanupFailed(originalFailure, cleanupFailures):
            "Stem分離失敗後の未完成ファイルを削除できませんでした（元の失敗: \(originalFailure)、削除失敗: \(cleanupFailures.joined(separator: "; "))）。"
        }
    }
}

protocol StemSeparating: Sendable {
    func separate(
        inputArtifact: StemAudioArtifact,
        installation: ValidatedStemModelInstallation,
        settings: StemSeparationSettings,
        outputDirectory: URL,
        progressHandler: @escaping @Sendable (StemSeparationProgress) -> Void
    ) async throws -> StemSeparationResult
}

protocol StemSeparationArtifactStoring: Sendable {
    func save(signal: AudioSignal, id: String, kind: StemArtifactKind, to: URL) async throws -> StemAudioArtifact
    func validate(
        artifact: StemAudioArtifact,
        expectedURL: URL,
        expectedKind: StemArtifactKind
    ) async throws -> StemAudioArtifactValidationReport
    func load(
        artifact: StemAudioArtifact,
        expectedURL: URL,
        expectedKind: StemArtifactKind
    ) async throws -> AudioSignal
    func removeIfPresent(_ url: URL) throws
}

extension StemTemporaryAudioStore: StemSeparationArtifactStoring {}

struct StemSeparationBackendConfiguration: Equatable, Sendable {
    let model: StemSeparationModel
    let modelDirectoryURL: URL
    let modelWeightsURL: URL
    let modelConfigurationURL: URL
    let shifts: Int
    let overlap: Float
    let split: Bool
    let segmentSeconds: Double?
    let batchSize: Int
    let seed: Int?
}

struct StemSeparationPCM: Sendable {
    let channelMajorSamples: [Float]
    let channelCount: Int
    let sampleRate: Int
}

struct StemSeparationBackendOutput: Sendable {
    let stems: [String: StemSeparationPCM]
}

final class StemSeparationCancellationToken: @unchecked Sendable {
    fileprivate let demucsToken = DemucsCancelToken()
    var isCancelled: Bool { demucsToken.isCancelled }
    func cancel() { demucsToken.cancel() }
}

protocol StemSeparationBackend: Sendable {
    func separate(
        input: StemSeparationPCM,
        cancellationToken: StemSeparationCancellationToken,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> StemSeparationBackendOutput
}

protocol StemSeparationBackendCreating: Sendable {
    func makeBackend(configuration: StemSeparationBackendConfiguration) async throws -> any StemSeparationBackend
}

struct DemucsStemSeparationBackendFactory: StemSeparationBackendCreating {
    func makeBackend(configuration: StemSeparationBackendConfiguration) async throws -> any StemSeparationBackend {
        try await Task.detached(priority: .userInitiated) {
            let parameters = DemucsSeparationParameters(
                shifts: configuration.shifts,
                overlap: configuration.overlap,
                split: configuration.split,
                segmentSeconds: configuration.segmentSeconds,
                batchSize: configuration.batchSize,
                seed: configuration.seed
            )
            let separator = try DemucsSeparator(
                modelName: "htdemucs",
                parameters: parameters,
                modelDirectory: configuration.modelDirectoryURL,
                modelResolutionPolicy: .localOnly
            )
            return DemucsStemSeparationBackend(separator: separator)
        }.value
    }
}

struct StemSeparationBackendRouterFactory: StemSeparationBackendCreating {
    func makeBackend(
        configuration: StemSeparationBackendConfiguration
    ) async throws -> any StemSeparationBackend {
        switch configuration.model {
        case .htdemucs:
            return try await DemucsStemSeparationBackendFactory()
                .makeBackend(configuration: configuration)
        }
    }
}

private final class DemucsStemSeparationBackend: StemSeparationBackend, @unchecked Sendable {
    private let separator: DemucsSeparator
    init(separator: DemucsSeparator) { self.separator = separator }

    func separate(
        input: StemSeparationPCM,
        cancellationToken: StemSeparationCancellationToken,
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> StemSeparationBackendOutput {
        let audio = try DemucsAudio(
            channelMajor: input.channelMajorSamples,
            channels: input.channelCount,
            sampleRate: input.sampleRate
        )
        return try await withCheckedThrowingContinuation { continuation in
            separator.separate(
                audio: audio,
                cancelToken: cancellationToken.demucsToken,
                interpolateProgress: false,
                progress: { progress in
                    progressHandler(
                        Double(progress.fraction),
                        "HTDemucs \(progress.stage)"
                    )
                },
                completion: { result in
                    switch result {
                    case .success(let value):
                        continuation.resume(returning: StemSeparationBackendOutput(
                            stems: value.stems.mapValues { stem in
                                StemSeparationPCM(
                                    channelMajorSamples: stem.channelMajorSamples,
                                    channelCount: stem.channels,
                                    sampleRate: stem.sampleRate
                                )
                            }
                        ))
                    case .failure(let error):
                        if let demucsError = error as? DemucsError, case .cancelled = demucsError {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            )
        }
    }
}

struct StemSeparationService: StemSeparating, Sendable {
    private static let expectedSampleRate = 44_100
    private static let expectedChannelCount = 2
    private static let outputFileNames: [StemRole: String] = [
        .drums: "raw-drums.wav",
        .bass: "raw-bass.wav",
        .other: "raw-other.wav",
        .vocals: "raw-vocals.wav",
    ]

    private let artifactStore: any StemSeparationArtifactStoring
    private let backendFactory: any StemSeparationBackendCreating

    init(
        artifactStore: any StemSeparationArtifactStoring = StemTemporaryAudioStore(),
        backendFactory: any StemSeparationBackendCreating = StemSeparationBackendRouterFactory()
    ) {
        self.artifactStore = artifactStore
        self.backendFactory = backendFactory
    }

    func separate(
        inputArtifact: StemAudioArtifact,
        installation: ValidatedStemModelInstallation,
        settings: StemSeparationSettings,
        outputDirectory: URL,
        progressHandler: @escaping @Sendable (StemSeparationProgress) -> Void
    ) async throws -> StemSeparationResult {
        try Task.checkCancellation()
        let directory = try validatedDirectory(outputDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let inputSignal = try await artifactStore.load(
            artifact: inputArtifact,
            expectedURL: inputArtifact.fileURL,
            expectedKind: .input44100
        )
        try validateInput(inputSignal, artifact: inputArtifact)
        let validatedSettings = try settings.validated(modelContract: installation.snapshot.contract)
        let modelWeightsURL = try requiredModelAssetURL(
            .modelWeights,
            installation: installation
        )
        let modelConfigurationURL = try requiredModelAssetURL(
            .modelConfiguration,
            installation: installation
        )
        let backend = try await backendFactory.makeBackend(configuration: StemSeparationBackendConfiguration(
            model: installation.snapshot.contract.separationModel,
            modelDirectoryURL: installation.modelDirectoryURL,
            modelWeightsURL: modelWeightsURL,
            modelConfigurationURL: modelConfigurationURL,
            shifts: validatedSettings.shifts,
            overlap: validatedSettings.overlap,
            split: validatedSettings.split,
            segmentSeconds: validatedSettings.segmentLength.explicitSeconds,
            batchSize: validatedSettings.batchSize,
            seed: validatedSettings.seed
        ))
        let token = StemSeparationCancellationToken()
        let backendOutput = try await withTaskCancellationHandler {
            try await backend.separate(
                input: pcm(from: inputSignal),
                cancellationToken: token,
                progressHandler: { fraction, detail in
                    progressHandler(StemSeparationProgress(
                        fraction: min(max(fraction, 0), 1) * 0.9,
                        detail: detail
                    ))
                }
            )
        } onCancel: {
            token.cancel()
        }
        try Task.checkCancellation()
        let outputRoles = installation.snapshot.contract.runContract.modelOutputOrder
        let signals = try validatedSignals(
            backendOutput,
            expectedRoles: outputRoles,
            expectedFrameCount: inputSignal.frameCount
        )

        var saved: [StemAudioArtifact] = []
        var createdURLs: [URL] = []
        do {
            for (index, role) in outputRoles.enumerated() {
                try Task.checkCancellation()
                guard let signal = signals[role], let fileName = Self.outputFileNames[role] else {
                    throw StemSeparationServiceError.missingOutputStem(role)
                }
                let url = directory.appending(path: fileName)
                let artifact = try await artifactStore.save(
                    signal: signal,
                    id: "raw-\(role.rawValue)",
                    kind: .rawStem(role),
                    to: url
                )
                createdURLs.append(url)
                _ = try await artifactStore.validate(
                    artifact: artifact,
                    expectedURL: url,
                    expectedKind: .rawStem(role)
                )
                saved.append(artifact)
                progressHandler(StemSeparationProgress(
                    fraction: 0.9 + (Double(index + 1) / Double(outputRoles.count)) * 0.1,
                    detail: "\(role.rawValue)を保存・検証済み"
                ))
            }
            return StemSeparationResult(source: inputArtifact, stems: saved)
        } catch {
            var cleanupFailures: [String] = []
            for url in createdURLs {
                do { try artifactStore.removeIfPresent(url) }
                catch { cleanupFailures.append(error.localizedDescription) }
            }
            guard cleanupFailures.isEmpty else {
                throw StemSeparationServiceError.cleanupFailed(
                    originalFailure: error.localizedDescription,
                    cleanupFailures: cleanupFailures
                )
            }
            throw error
        }
    }

    private func requiredModelAssetURL(
        _ kind: StemModelAssetKind,
        installation: ValidatedStemModelInstallation
    ) throws -> URL {
        guard let asset = installation.snapshot.assets.first(where: { $0.kind == kind }) else {
            throw StemSeparationServiceError.missingModelAsset(kind)
        }
        return asset.fileURL
    }

    private func validatedDirectory(_ url: URL) throws -> URL {
        guard url.isFileURL, url.query == nil, url.fragment == nil else {
            throw StemSeparationServiceError.invalidOutputDirectory(url.absoluteString)
        }
        return url.standardizedFileURL
    }

    private func validateInput(_ signal: AudioSignal, artifact: StemAudioArtifact) throws {
        guard signal.sampleRate == Double(Self.expectedSampleRate) else {
            throw StemSeparationServiceError.inputSampleRateMismatch(
                expected: Double(Self.expectedSampleRate), actual: signal.sampleRate
            )
        }
        guard signal.channels.count == Self.expectedChannelCount else {
            throw StemSeparationServiceError.inputChannelCountMismatch(
                expected: Self.expectedChannelCount, actual: signal.channels.count
            )
        }
        guard signal.frameCount == artifact.frameCount else {
            throw StemSeparationServiceError.inputFrameCountMismatch(
                expected: artifact.frameCount, actual: signal.frameCount
            )
        }
        for (channelIndex, channel) in signal.channels.enumerated() {
            if let frame = channel.firstIndex(where: { !$0.isFinite }) {
                throw StemSeparationServiceError.nonFiniteInputSample(channel: channelIndex, frame: frame)
            }
        }
    }

    private func pcm(from signal: AudioSignal) -> StemSeparationPCM {
        StemSeparationPCM(
            channelMajorSamples: signal.channels.flatMap { $0 },
            channelCount: signal.channels.count,
            sampleRate: Int(signal.sampleRate.rounded())
        )
    }

    private func validatedSignals(
        _ output: StemSeparationBackendOutput,
        expectedRoles: [StemRole],
        expectedFrameCount: Int
    ) throws -> [StemRole: AudioSignal] {
        guard output.stems.count == expectedRoles.count else {
            throw StemSeparationServiceError.outputStemCountMismatch(
                expected: expectedRoles.count,
                actual: output.stems.count
            )
        }
        let expectedNames = Set(expectedRoles.map(\.rawValue))
        for name in output.stems.keys where !expectedNames.contains(name) {
            throw StemSeparationServiceError.unexpectedOutputStem(name)
        }
        var result: [StemRole: AudioSignal] = [:]
        for role in expectedRoles {
            guard let stem = output.stems[role.rawValue] else {
                throw StemSeparationServiceError.missingOutputStem(role)
            }
            guard stem.sampleRate == Self.expectedSampleRate else {
                throw StemSeparationServiceError.outputSampleRateMismatch(
                    role: role, expected: Self.expectedSampleRate, actual: stem.sampleRate
                )
            }
            guard stem.channelCount == Self.expectedChannelCount else {
                throw StemSeparationServiceError.outputChannelCountMismatch(
                    role: role, expected: Self.expectedChannelCount, actual: stem.channelCount
                )
            }
            let expectedSampleCount = expectedFrameCount * Self.expectedChannelCount
            guard stem.channelMajorSamples.count == expectedSampleCount else {
                throw StemSeparationServiceError.outputSampleCountMismatch(
                    role: role,
                    expected: expectedSampleCount,
                    actual: stem.channelMajorSamples.count
                )
            }
            var channels: [[Float]] = []
            for channelIndex in 0..<Self.expectedChannelCount {
                let start = channelIndex * expectedFrameCount
                let channel = Array(stem.channelMajorSamples[start..<(start + expectedFrameCount)])
                if let frame = channel.firstIndex(where: { !$0.isFinite }) {
                    throw StemSeparationServiceError.nonFiniteOutputSample(
                        role: role, channel: channelIndex, frame: frame
                    )
                }
                channels.append(channel)
            }
            result[role] = AudioSignal(channels: channels, sampleRate: Double(stem.sampleRate))
        }
        return result
    }
}
