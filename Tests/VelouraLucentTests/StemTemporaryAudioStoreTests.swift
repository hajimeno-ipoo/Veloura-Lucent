import Foundation
import Testing
@testable import VelouraLucent

struct StemTemporaryAudioStoreTests {
    @Test
    func savesValidatesAndLoadsFloatWAVWithoutChangingSamples() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appending(path: "corrected-vocals.wav")
        let signal = AudioSignal(
            channels: [[-1.5, -0.25, 0, 0.75, 1.25], [1.5, 0.25, 0, -0.75, -1.25]],
            sampleRate: 48_000
        )
        let store = StemTemporaryAudioStore()

        let artifact = try await store.save(
            signal: signal,
            id: "corrected-vocals",
            kind: .correctedStem(.vocals),
            to: outputURL
        )
        let report = try await store.validate(
            artifact: artifact,
            expectedURL: outputURL,
            expectedKind: .correctedStem(.vocals)
        )
        let loaded = try await store.load(
            artifact: artifact,
            expectedURL: outputURL,
            expectedKind: .correctedStem(.vocals)
        )

        #expect(report.sampleRate == 48_000)
        #expect(report.channelCount == 2)
        #expect(report.frameCount == 5)
        #expect(loaded.channels == signal.channels)
        #expect(try partialFiles(in: directory).isEmpty)
    }

    @Test
    func nonFiniteSignalCreatesNeitherFinalNorPartialFile() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appending(path: "corrected-bass.wav")
        let store = StemTemporaryAudioStore()

        await #expect(throws: StemTemporaryAudioStoreError.nonFiniteSample(channel: 0, frame: 1)) {
            _ = try await store.save(
                signal: AudioSignal(channels: [[0, .nan], [0, 0]], sampleRate: 48_000),
                id: "corrected-bass",
                kind: .correctedStem(.bass),
                to: outputURL
            )
        }

        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
        #expect(try partialFiles(in: directory).isEmpty)
    }

    @Test
    func existingVerifiedFileIsNotOverwritten() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appending(path: "corrected-drums.wav")
        let existing = Data("existing".utf8)
        try existing.write(to: outputURL)

        await #expect(throws: StemTemporaryAudioStoreError.outputAlreadyExists(outputURL.path)) {
            _ = try await StemTemporaryAudioStore().save(
                signal: AudioSignal(channels: [[0.1], [-0.1]], sampleRate: 48_000),
                id: "corrected-drums",
                kind: .correctedStem(.drums),
                to: outputURL
            )
        }

        #expect(try Data(contentsOf: outputURL) == existing)
        #expect(try partialFiles(in: directory).isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let URL = FileManager.default.temporaryDirectory
            .appending(path: "StemTemporaryAudioStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: URL, withIntermediateDirectories: true)
        return URL
    }

    private func partialFiles(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.contains(".partial.wav") }
    }
}
