import Foundation
import Testing
@testable import VelouraLucent

struct AppStorageMaintenanceTests {
    @Test
    func launchCleanupRemovesOwnedTemporaryAndLegacyDirectoriesOnly() async throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "AppStorageMaintenanceTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let preview = root.appending(path: "Preview", directoryHint: .isDirectory)
        let stemPreview = root.appending(path: "StemPreview", directoryHint: .isDirectory)
        let applicationSupport = root.appending(path: "ApplicationSupport", directoryHint: .isDirectory)
        let stemRuns = applicationSupport.appending(path: "StemRuns", directoryHint: .isDirectory)
        let calibrationRuns = applicationSupport.appending(
            path: "StemCalibrationRuns",
            directoryHint: .isDirectory
        )
        let unrelated = applicationSupport.appending(path: "KeepMe", directoryHint: .isDirectory)
        let modelPaths = StemModelStorePaths(
            rootURL: applicationSupport.appending(path: "StemModels", directoryHint: .isDirectory)
        )
        let staleStaging = modelPaths.stagingDirectoryURL(operationIdentifier: UUID())
        for directory in [preview, stemPreview, stemRuns, calibrationRuns, unrelated, staleStaging] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: directory.appending(path: "fixture.tmp"))
        }

        await AppStorageMaintenance(
            standardPreviewRootURL: preview,
            stemTemporaryRootURL: stemPreview,
            applicationSupportRootURL: applicationSupport,
            modelStore: StemModelInstallationStore(paths: modelPaths)
        ).prepareForLaunch()

        #expect(!FileManager.default.fileExists(atPath: preview.path))
        #expect(!FileManager.default.fileExists(atPath: stemPreview.path))
        #expect(!FileManager.default.fileExists(atPath: stemRuns.path))
        #expect(!FileManager.default.fileExists(atPath: calibrationRuns.path))
        #expect(!FileManager.default.fileExists(atPath: modelPaths.stagingRootURL.path))
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
    }
}
