import Foundation

struct AppStorageMaintenance: Sendable {
    static var production: AppStorageMaintenance {
        let modelPaths = StemModelStorePaths.production
        return AppStorageMaintenance(
            standardPreviewRootURL: PreviewFileStore.directory,
            stemTemporaryRootURL: StemWorkflowService.temporaryRootURL,
            applicationSupportRootURL: modelPaths.rootURL.deletingLastPathComponent(),
            modelStore: StemModelInstallationStore(paths: modelPaths)
        )
    }

    let standardPreviewRootURL: URL
    let stemTemporaryRootURL: URL
    let applicationSupportRootURL: URL
    let modelStore: StemModelInstallationStore

    func prepareForLaunch() async {
        removeDirectoryIfPresent(standardPreviewRootURL)
        removeDirectoryIfPresent(stemTemporaryRootURL)
        removeDirectoryIfPresent(
            applicationSupportRootURL.appending(path: "StemRuns", directoryHint: .isDirectory)
        )
        removeDirectoryIfPresent(
            applicationSupportRootURL.appending(path: "StemCalibrationRuns", directoryHint: .isDirectory)
        )
        try? await modelStore.discardStaleStagingDirectories()

        for model in StemSeparationModel.allCases {
            let validator = StemModelAssetValidator(selectedModel: model)
            guard let manifest = try? validator.loadBundledManifest(),
                  let installation = try? await modelStore.loadActive(manifest: manifest) else {
                continue
            }
            try? await modelStore.pruneInactiveGenerations(
                assetSetIdentifier: installation.receipt.assetSetIdentifier,
                keeping: installation.receipt.generationIdentifier
            )
        }
    }

    private func removeDirectoryIfPresent(_ url: URL) {
        let normalized = url.standardizedFileURL
        guard normalized.isFileURL,
              FileManager.default.fileExists(atPath: normalized.path) else {
            return
        }
        try? FileManager.default.removeItem(at: normalized)
    }
}
