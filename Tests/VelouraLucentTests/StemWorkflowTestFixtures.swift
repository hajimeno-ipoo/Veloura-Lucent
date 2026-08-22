import Foundation
@testable import VelouraLucent

func makeStemTestRunContract(
    model: StemSeparationModel = .htdemucs
) -> StemModelRunContract {
    let profile = StemProductionModelProfile.profile(for: model)
    return StemModelRunContract(
        separationModel: model,
        modelIdentifier: profile.modelIdentifier,
        modelOutputOrder: profile.sourceOrder,
        activeRoles: profile.sourceOrder,
        validationRoles: profile.sourceOrder,
        pureSumOrder: profile.pureSumOrder
    )
}

func makeStemTestInstallation(
    rootURL: URL,
    model: StemSeparationModel = .htdemucs
) throws -> (
    manifest: StemModelManifest,
    installation: ValidatedStemModelInstallation
) {
    let validator = StemModelAssetValidator(selectedModel: model)
    let manifest = try validator.loadBundledManifest()
    let contract = try validator.validateManifest(manifest)
    let generationID = UUID()
    let generationURL = rootURL.appending(
        path: generationID.uuidString.lowercased(),
        directoryHint: .isDirectory
    )
    let assets = manifest.downloadableModelAssets.map { asset in
        ValidatedStemModelAsset(
            kind: asset.kind,
            fileURL: generationURL.appending(path: asset.installationRelativePath),
            byteCount: asset.byteCount,
            sha256: asset.sha256
        )
    }
    let receiptAssets = manifest.downloadableModelAssets.map { asset in
        StemModelInstallationReceiptAsset(
            kind: asset.kind,
            installationRelativePath: asset.installationRelativePath,
            byteCount: asset.byteCount,
            sha256: asset.sha256
        )
    }
    let receipt = StemModelInstallationReceipt(
        schemaVersion: StemModelInstallationReceipt.currentSchemaVersion,
        assetSetIdentifier: manifest.assetSetIdentifier,
        modelIdentifier: contract.identifier,
        revision: manifest.model.revision,
        generationIdentifier: generationID,
        activatedAt: Date(timeIntervalSince1970: 1_750_000_000),
        assets: receiptAssets,
        sourceEvidence: manifest.downloadableModelAssets.map { asset in
            StemModelInstallationSourceEvidence(
                kind: asset.kind,
                stableDownloadURL: asset.downloadURL,
                responseHeaderName: manifest.downloadPolicy.revisionResponseHeader,
                revision: manifest.model.revision
            )
        }
    )
    return (
        manifest,
        ValidatedStemModelInstallation(
            snapshot: ValidatedStemModelSnapshot(
                contract: contract,
                installationRootURL: generationURL,
                modelDirectoryURL: try StemModelAssetValidator.safeDescendantURL(
                    rootURL: generationURL,
                    relativePath: model == .htdemucs ? "htdemucs" : "bs-roformer-sw",
                    field: "testModelDirectory"
                ),
                assets: assets
            ),
            receipt: receipt,
            generationDirectoryURL: generationURL
        )
    )
}

func makeStemTestSignal(sampleRate: Double = 44_100, frameCount: Int = 32) -> AudioSignal {
    let left = (0..<frameCount).map { Float($0 % 7) * 0.01 }
    return AudioSignal(channels: [left, left.map(-)], sampleRate: sampleRate)
}
