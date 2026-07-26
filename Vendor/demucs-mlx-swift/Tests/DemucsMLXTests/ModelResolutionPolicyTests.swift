@testable import DemucsMLX
import Foundation
import Testing

private let testModelName = "htdemucs"

private final class ResolutionInvocationRecorder {
    private(set) var candidateProviderCallCount = 0
    private(set) var hubDownloadCallCount = 0
    var candidates: [URL] = []

    func provideCandidates(modelName: String, preferred: URL?) -> [URL] {
        candidateProviderCallCount += 1
        return candidates
    }

    func download(modelName: String, repoID: String) throws -> URL {
        hubDownloadCallCount += 1
        throw DemucsError.unsupportedModelBackend("Unexpected Hub download")
    }
}

private func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("demucs-model-resolution-\(UUID().uuidString)", isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }
    try body(directory)
}

private func writePlaceholderModelFiles(
    to directory: URL,
    excluding excludedFilename: String? = nil
) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let contents: [(String, Data)] = [
        ("\(testModelName).safetensors", Data([0x00])),
        ("\(testModelName)_config.json", Data("{}".utf8)),
    ]
    for (filename, data) in contents where filename != excludedFilename {
        try data.write(to: directory.appendingPathComponent(filename))
    }
}

private func capturedError(_ operation: () throws -> Void) -> Error? {
    do {
        try operation()
        return nil
    } catch {
        return error
    }
}

@Test("Model resolution policy is Sendable")
func modelResolutionPolicyIsSendable() {
    func requireSendable<T: Sendable>(_: T) {}
    requireSendable(DemucsModelResolutionPolicy.localOnly)
    requireSendable(DemucsModelResolutionPolicy.localThenHub)
}

@Test("Local-only resolves the exact explicit directory")
func localOnlyResolvesExactPreferredDirectory() throws {
    try withTemporaryDirectory { root in
        let preferred = root.appendingPathComponent("validated-model", isDirectory: true)
        try writePlaceholderModelFiles(to: preferred)

        // A nested directory is deliberately also valid. `.localOnly` must not prefer it.
        try writePlaceholderModelFiles(
            to: preferred.appendingPathComponent(testModelName, isDirectory: true)
        )

        let recorder = ResolutionInvocationRecorder()
        let resolved = try ModelLoader.resolveModelDirectory(
            modelName: testModelName,
            preferred: preferred,
            policy: .localOnly,
            candidateProvider: recorder.provideCandidates,
            hubDownload: recorder.download
        )

        #expect(resolved == preferred)
        #expect(recorder.candidateProviderCallCount == 0)
        #expect(recorder.hubDownloadCallCount == 0)
    }
}

@Test("Local-only requires an explicit directory")
func localOnlyRejectsNilPreferredDirectory() {
    let recorder = ResolutionInvocationRecorder()
    let error = capturedError {
        _ = try ModelLoader.resolveModelDirectory(
            modelName: testModelName,
            preferred: nil,
            policy: .localOnly,
            candidateProvider: recorder.provideCandidates,
            hubDownload: recorder.download
        )
    }

    #expect(error?.localizedDescription.contains("requires an explicit modelDirectory") == true)
    #expect(recorder.candidateProviderCallCount == 0)
    #expect(recorder.hubDownloadCallCount == 0)
}

@Test("DemucsSeparator forwards local-only policy through the model factory")
func separatorForwardsLocalOnlyPolicy() {
    let error = capturedError {
        _ = try DemucsSeparator(
            modelName: testModelName,
            modelDirectory: nil,
            modelResolutionPolicy: .localOnly
        )
    }

    #expect(error?.localizedDescription.contains("requires an explicit modelDirectory") == true)
}

@Test("Local-only rejects either missing required model file")
func localOnlyRejectsMissingRequiredFiles() throws {
    let filenames = [
        "\(testModelName).safetensors",
        "\(testModelName)_config.json",
    ]

    for missingFilename in filenames {
        try withTemporaryDirectory { root in
            let preferred = root.appendingPathComponent("incomplete", isDirectory: true)
            try writePlaceholderModelFiles(to: preferred, excluding: missingFilename)
            let recorder = ResolutionInvocationRecorder()

            let error = capturedError {
                _ = try ModelLoader.resolveModelDirectory(
                    modelName: testModelName,
                    preferred: preferred,
                    policy: .localOnly,
                    candidateProvider: recorder.provideCandidates,
                    hubDownload: recorder.download
                )
            }

            #expect(error?.localizedDescription.contains(missingFilename) == true)
            #expect(recorder.candidateProviderCallCount == 0)
            #expect(recorder.hubDownloadCallCount == 0)
        }
    }
}

@Test("Local-only ignores every other local candidate provider")
func localOnlyIgnoresOtherLocalCandidates() throws {
    try withTemporaryDirectory { root in
        let preferred = root.appendingPathComponent("incomplete", isDirectory: true)
        try FileManager.default.createDirectory(at: preferred, withIntermediateDirectories: true)

        let otherwiseValidCandidate = root.appendingPathComponent("environment-cache-or-cwd", isDirectory: true)
        try writePlaceholderModelFiles(to: otherwiseValidCandidate)

        let recorder = ResolutionInvocationRecorder()
        recorder.candidates = [otherwiseValidCandidate]

        let error = capturedError {
            _ = try ModelLoader.resolveModelDirectory(
                modelName: testModelName,
                preferred: preferred,
                policy: .localOnly,
                candidateProvider: recorder.provideCandidates,
                hubDownload: recorder.download
            )
        }

        #expect(error != nil)
        #expect(recorder.candidateProviderCallCount == 0)
        #expect(recorder.hubDownloadCallCount == 0)
    }
}

@Test("Local-only never invokes Hub download")
func localOnlyNeverInvokesHubDownload() throws {
    try withTemporaryDirectory { root in
        let recorder = ResolutionInvocationRecorder()
        let error = capturedError {
            _ = try ModelLoader.resolveModelDirectory(
                modelName: testModelName,
                preferred: root,
                policy: .localOnly,
                candidateProvider: recorder.provideCandidates,
                hubDownload: recorder.download
            )
        }

        #expect(error != nil)
        #expect(recorder.hubDownloadCallCount == 0)
    }
}

@Test("Default policy preserves preferred-child local lookup")
func defaultPolicyPreservesLocalThenHubLookup() throws {
    try withTemporaryDirectory { root in
        let preferredRoot = root.appendingPathComponent("models", isDirectory: true)
        let nestedModel = preferredRoot.appendingPathComponent(testModelName, isDirectory: true)
        try writePlaceholderModelFiles(to: nestedModel)

        let recorder = ResolutionInvocationRecorder()
        let resolved = try ModelLoader.resolveModelDirectory(
            modelName: testModelName,
            preferred: preferredRoot,
            hubDownload: recorder.download
        )

        #expect(resolved == nestedModel)
        #expect(recorder.hubDownloadCallCount == 0)
    }
}
