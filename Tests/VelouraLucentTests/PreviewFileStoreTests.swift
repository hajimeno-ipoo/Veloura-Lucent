import Foundation
import Testing
@testable import VelouraLucent

struct PreviewFileStoreTests {
    @Test
    func ownedPreviewRemovalDoesNotDeleteFilesOutsideThePreviewDirectory() throws {
        let owned = PreviewFileStore.directory.appending(
            path: "owned-\(UUID().uuidString).wav"
        )
        let externalRoot = FileManager.default.temporaryDirectory.appending(
            path: "PreviewFileStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let external = externalRoot.appending(path: "external.wav")
        defer {
            try? FileManager.default.removeItem(at: owned)
            try? FileManager.default.removeItem(at: externalRoot)
        }
        try FileManager.default.createDirectory(
            at: PreviewFileStore.directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: externalRoot, withIntermediateDirectories: true)
        try Data("owned".utf8).write(to: owned)
        try Data("external".utf8).write(to: external)

        PreviewFileStore.removeOwnedPreviewFileIfPresent(owned)
        PreviewFileStore.removeOwnedPreviewFileIfPresent(external)

        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(FileManager.default.fileExists(atPath: external.path))
    }
}
