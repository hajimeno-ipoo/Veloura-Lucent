import Foundation
import Testing
@testable import VelouraLucent

struct StemModelContractTests {
    private let validator = StemModelAssetValidator()

    @Test
    func trackedManifestMatchesProductionContract() throws {
        let manifest = try loadTrackedManifest()
        let contract = try validator.validateManifest(manifest)

        #expect(manifest.schemaVersion == 2)
        #expect(contract.identifier == "mlx-community/demucs-mlx:htdemucs")
        #expect(contract.version == StemModelAssetValidator.expectedModelRevision)
        #expect(contract.assetSetIdentifier == StemModelAssetValidator.expectedAssetSetIdentifier)
        #expect(contract.inputName == "batchData")
        #expect(contract.sourceOrder == [.drums, .bass, .other, .vocals])
        #expect(contract.outputNames == [
            .drums: "drums",
            .bass: "bass",
            .other: "other",
            .vocals: "vocals"
        ])
        #expect(contract.sampleRate == 44_100)
        #expect(contract.channelCount == 2)
        #expect(contract.inputShape == [-1, 2, -1])
        #expect(contract.outputShapes.values.allSatisfy { $0 == [-1, 2, -1] })
        #expect(contract.scalarType == .float32)
        #expect(contract.normalization == .modelManagedIdentityBoundary)
        #expect(contract.runtime == .mlx)
        #expect(contract.defaultSegmentSeconds == 7.8)
        #expect(Set(contract.downloadableModelAssets.map(\.kind)) == [.modelWeights, .modelConfiguration])
        #expect(contract.bundledRuntimeAssets.map(\.kind) == [.metalLibrary])
        #expect(manifest.downloadPolicy.requiresExplicitUserConfirmation)
    }

    @Test
    func manifestRuntimePinsMatchVendoredAndRemoteDependencies() throws {
        let manifest = try loadTrackedManifest()
        let vendoredPin = try #require(manifest.runtimePins.first { $0.name == "demucs-mlx-swift" })
        let provenanceURL = repositoryRootURL
            .appending(path: "Vendor/demucs-mlx-swift/VENDORED_FROM.md")
        let provenance = try String(contentsOf: provenanceURL, encoding: .utf8)

        #expect(provenance.contains("Upstream repository: <\(vendoredPin.repo)>") )
        #expect(provenance.contains("Upstream commit: `\(vendoredPin.revision)`"))

        let lockfileData = try Data(contentsOf: repositoryRootURL.appending(path: "Package.resolved"))
        let lockfile = try JSONDecoder().decode(PackageResolved.self, from: lockfileData)
        let manifestPins = Dictionary(
            uniqueKeysWithValues: manifest.runtimePins
                .filter { $0.name != "demucs-mlx-swift" }
                .map {
                    (
                        $0.name,
                        ResolvedContractPin(
                            location: $0.repo,
                            revision: $0.revision,
                            version: $0.version
                        )
                    )
                }
        )
        let resolvedPins = Dictionary(
            uniqueKeysWithValues: lockfile.pins.map {
                (
                    $0.identity,
                    ResolvedContractPin(
                        location: $0.location,
                        revision: $0.state.revision,
                        version: $0.state.version
                    )
                )
            }
        )

        #expect(manifestPins == resolvedPins)
    }

    @Test
    func vendoredDemucsInventoryMatchesReviewedContent() throws {
        let vendoredRoot = repositoryRootURL.appending(
            path: "Vendor/demucs-mlx-swift",
            directoryHint: .isDirectory
        )
        let inventoryURL = vendoredRoot.appending(path: "VENDORED_INVENTORY.sha256")
        let expectedInventorySHA256 =
            "af2d5babe1a71cc5260d27401a7e9afc5a850e2d0406e6325f64b569a9c4e085"

        #expect(try validator.sha256(fileURL: inventoryURL) == expectedInventorySHA256)

        let inventory = try String(contentsOf: inventoryURL, encoding: .utf8)
        let lines = inventory.split(separator: "\n", omittingEmptySubsequences: true)
        var expectedHashesByPath: [String: String] = [:]
        for line in lines {
            let text = String(line)
            try #require(text.count > 66)
            try #require(String(text.dropFirst(64).prefix(2)) == "  ")
            let relativePath = String(text.dropFirst(66))
            try #require(relativePath.hasPrefix("./"))
            try #require(expectedHashesByPath[relativePath] == nil)
            expectedHashesByPath[relativePath] = String(text.prefix(64))
        }

        let actualFiles = try reviewedVendoredFiles(
            rootURL: vendoredRoot,
            directoryURL: vendoredRoot,
            relativeDirectory: ""
        )
        #expect(Set(actualFiles.keys) == Set(expectedHashesByPath.keys))
        #expect(lines.count == 51)

        for relativePath in expectedHashesByPath.keys.sorted() {
            let fileURL = try #require(actualFiles[relativePath])
            let expectedSHA256 = try #require(expectedHashesByPath[relativePath])
            #expect(try validator.sha256(fileURL: fileURL) == expectedSHA256)
        }
    }

    @Test
    func runtimeAndInstalledModelUseSeparateFixedLayouts() throws {
        let manifest = try loadTrackedManifest()
        let weights = try #require(manifest.downloadableModelAssets.first { $0.kind == .modelWeights })
        let metalLibrary = try #require(manifest.bundledRuntimeAssets.first { $0.kind == .metalLibrary })
        let packageRoot = URL(filePath: "/tmp/package-resources", directoryHint: .isDirectory)
        let applicationRoot = URL(
            filePath: "/tmp/VelouraLucent.app/Contents/Resources",
            directoryHint: .isDirectory
        )
        let installationRoot = URL(filePath: "/tmp/application-support/generation", directoryHint: .isDirectory)

        #expect(
            try StemBundledRuntimeAssetLayout.swiftPackageResources(rootURL: packageRoot)
                .fileURL(for: metalLibrary).path
                == "/tmp/package-resources/StemModels/MLX/mlx.metallib"
        )
        #expect(
            try StemBundledRuntimeAssetLayout.packagedApplicationResources(
                contentsResourcesURL: applicationRoot
            ).fileURL(for: metalLibrary).path
                == "/tmp/VelouraLucent.app/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
        )
        #expect(
            try StemModelAssetValidator.safeDescendantURL(
                rootURL: installationRoot,
                relativePath: weights.installationRelativePath,
                field: "test"
            ).path
                == "/tmp/application-support/generation/htdemucs/htdemucs.safetensors"
        )
    }

    @Test
    func installationReceiptSchemaTwoRoundTripsPerAssetStableSourceEvidence() throws {
        let manifest = try loadTrackedManifest()
        let sourceEvidence = manifest.downloadableModelAssets
            .sorted(by: { $0.kind.rawValue < $1.kind.rawValue })
            .map { asset in
                StemModelInstallationSourceEvidence(
                    kind: asset.kind,
                    stableDownloadURL: asset.downloadURL,
                    responseHeaderName: manifest.downloadPolicy.revisionResponseHeader,
                    revision: manifest.model.revision
                )
            }
        let assets = manifest.downloadableModelAssets
            .sorted(by: { $0.kind.rawValue < $1.kind.rawValue })
            .map { asset in
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
            modelIdentifier: StemModelAssetValidator.modelIdentifier,
            revision: manifest.model.revision,
            generationIdentifier: UUID(),
            activatedAt: Date(timeIntervalSince1970: 1_735_689_600),
            assets: assets,
            sourceEvidence: sourceEvidence
        )

        let data = try JSONEncoder().encode(receipt)
        let decoded = try JSONDecoder().decode(
            StemModelInstallationReceipt.self,
            from: data
        )

        #expect(StemModelInstallationReceipt.currentSchemaVersion == 2)
        #expect(decoded == receipt)
        #expect(decoded.sourceEvidence.count == 2)
        #expect(decoded.sourceEvidence.map(\.stableDownloadURL) == sourceEvidence.map(\.stableDownloadURL))
    }

    @Test
    func missingManifestProducesExplicitError() {
        let missingURL = URL(filePath: "/tmp/veloura-missing-stem-manifest.json")

        #expect(throws: StemModelAssetValidationError.manifestMissing(path: missingURL.path)) {
            try validator.loadManifest(at: missingURL)
        }
    }

    @Test
    func unknownManifestFieldIsRejectedBeforeDecoding() throws {
        let sourceURL = trackedManifestURL
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let changedURL = temporaryRoot.appending(path: "manifest.json")
        let data = try Data(contentsOf: sourceURL)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["unapprovedField"] = true
        try JSONSerialization.data(withJSONObject: json).write(to: changedURL)

        #expect(throws: StemModelAssetValidationError.self) {
            try validator.loadManifest(at: changedURL)
        }
    }

    @Test
    func unknownNestedProvenanceFieldIsRejectedBeforeDecoding() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let changedURL = temporaryRoot.appending(path: "manifest.json")
        let data = try Data(contentsOf: trackedManifestURL)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var provenance = try #require(json["metalLibraryBuildProvenance"] as? [String: Any])
        var toolchain = try #require(provenance["verifiedToolchain"] as? [String: Any])
        toolchain["unapprovedField"] = true
        provenance["verifiedToolchain"] = toolchain
        json["metalLibraryBuildProvenance"] = provenance
        try JSONSerialization.data(withJSONObject: json).write(to: changedURL)

        #expect(throws: StemModelAssetValidationError.self) {
            try validator.loadManifest(at: changedURL)
        }
    }

    @Test
    func changedModelRevisionIsRejected() throws {
        let manifest = try loadTrackedManifest()
        let changed = replacing(
            manifest,
            model: StemModelManifestModel(
                name: manifest.model.name,
                repo: manifest.model.repo,
                revision: "0000000000000000000000000000000000000000",
                licenseMetadata: manifest.model.licenseMetadata
            )
        )

        #expect(throws: StemModelAssetValidationError.self) {
            try validator.validateManifest(changed)
        }
    }

    @Test
    func nonHTTPSDownloadURLIsRejected() throws {
        let manifest = try loadTrackedManifest()
        var assets = manifest.downloadableModelAssets
        let original = assets[0]
        assets[0] = StemDownloadableModelAsset(
            kind: original.kind,
            downloadURL: original.downloadURL.replacingOccurrences(of: "https://", with: "http://"),
            installationRelativePath: original.installationRelativePath,
            byteCount: original.byteCount,
            sha256: original.sha256
        )

        #expect(throws: StemModelAssetValidationError.self) {
            try validator.validateManifest(replacing(manifest, downloadableModelAssets: assets))
        }
    }

    @Test
    func unsafeInstallationRelativePathIsRejected() throws {
        let manifest = try loadTrackedManifest()
        var assets = manifest.downloadableModelAssets
        let original = assets[0]
        assets[0] = StemDownloadableModelAsset(
            kind: original.kind,
            downloadURL: original.downloadURL,
            installationRelativePath: "../htdemucs.safetensors",
            byteCount: original.byteCount,
            sha256: original.sha256
        )

        #expect(throws: StemModelAssetValidationError.unsafeRelativePath(
            field: "downloadableModelAssets.installationRelativePath",
            path: "../htdemucs.safetensors"
        )) {
            try validator.validateManifest(replacing(manifest, downloadableModelAssets: assets))
        }
    }

    @Test
    func missingBundledMetalLibraryProducesTypedError() throws {
        let manifest = try loadTrackedManifest()
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let metal = try #require(manifest.bundledRuntimeAssets.first)
        let expectedURL = try StemBundledRuntimeAssetLayout
            .swiftPackageResources(rootURL: temporaryRoot)
            .fileURL(for: metal)

        #expect(throws: StemModelAssetValidationError.bundledRuntimeMissing(path: expectedURL.path)) {
            try validator.validateBundledRuntimeAssets(
                manifest: manifest,
                layout: .swiftPackageResources(rootURL: temporaryRoot)
            )
        }
    }

    @Test
    func wrongBundledRuntimeSizeStopsBeforeUse() throws {
        let manifest = try loadTrackedManifest()
        let metal = try #require(manifest.bundledRuntimeAssets.first)
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let metalURL = try StemBundledRuntimeAssetLayout
            .swiftPackageResources(rootURL: temporaryRoot)
            .fileURL(for: metal)
        try FileManager.default.createDirectory(
            at: metalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0]).write(to: metalURL)

        #expect(throws: StemModelAssetValidationError.assetSizeMismatch(
            kind: .metalLibrary,
            path: metalURL.path,
            expected: metal.byteCount,
            actual: 1
        )) {
            try validator.validateBundledRuntimeAssets(
                manifest: manifest,
                layout: .swiftPackageResources(rootURL: temporaryRoot)
            )
        }
    }

    @Test
    func fileChecksumUsesSHA256() throws {
        let temporaryRoot = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let fileURL = temporaryRoot.appending(path: "fixture.bin")
        try Data("abc".utf8).write(to: fileURL)

        #expect(
            try validator.sha256(fileURL: fileURL)
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test
    func preparedBundledRuntimePassesProductionValidator() throws {
        let report = try validator.validateBundledRuntimeAssets()

        #expect(report.contract.identifier == StemModelAssetValidator.modelIdentifier)
        #expect(report.assets.map(\.kind) == [.metalLibrary])
        #expect(report.assets.allSatisfy { $0.byteCount > 0 && $0.sha256.count == 64 })
    }

    private var repositoryRootURL: URL {
        URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private var trackedManifestURL: URL {
        repositoryRootURL.appending(
            path: "Sources/VelouraLucent/Resources/StemModels/stem-model-manifest.json"
        )
    }

    private func loadTrackedManifest() throws -> StemModelManifest {
        try validator.loadManifest(at: trackedManifestURL)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "VelouraStemContractTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func reviewedVendoredFiles(
        rootURL: URL,
        directoryURL: URL,
        relativeDirectory: String
    ) throws -> [String: URL] {
        var files: [String: URL] = [:]
        let entries = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey
            ],
            options: []
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }

        for entry in entries {
            if entry.lastPathComponent == ".DS_Store" {
                continue
            }
            let relativePath = relativeDirectory.isEmpty
                ? entry.lastPathComponent
                : "\(relativeDirectory)/\(entry.lastPathComponent)"
            if relativePath == ".build" || relativePath == ".git" {
                continue
            }
            if relativePath == "VENDORED_INVENTORY.sha256" {
                continue
            }

            let values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            try #require(values.isSymbolicLink != true)
            if values.isDirectory == true {
                let nested = try reviewedVendoredFiles(
                    rootURL: rootURL,
                    directoryURL: entry,
                    relativeDirectory: relativePath
                )
                for (path, url) in nested {
                    try #require(files[path] == nil)
                    files[path] = url
                }
            } else {
                try #require(values.isRegularFile == true)
                let standardized = entry.standardizedFileURL
                try #require(standardized.path.hasPrefix(rootURL.standardizedFileURL.path + "/"))
                files["./\(relativePath)"] = standardized
            }
        }

        return files
    }

    private func replacing(
        _ manifest: StemModelManifest,
        model: StemModelManifestModel? = nil,
        downloadableModelAssets: [StemDownloadableModelAsset]? = nil
    ) -> StemModelManifest {
        StemModelManifest(
            schemaVersion: manifest.schemaVersion,
            assetSetIdentifier: manifest.assetSetIdentifier,
            model: model ?? manifest.model,
            runtimePins: manifest.runtimePins,
            audioContract: manifest.audioContract,
            downloadPolicy: manifest.downloadPolicy,
            downloadableModelAssets: downloadableModelAssets ?? manifest.downloadableModelAssets,
            bundledRuntimeAssets: manifest.bundledRuntimeAssets,
            metalLibraryBuildProvenance: manifest.metalLibraryBuildProvenance
        )
    }
}

private struct PackageResolved: Decodable {
    let pins: [ResolvedPin]
}

private struct ResolvedPin: Decodable {
    let identity: String
    let location: String
    let state: ResolvedState
}

private struct ResolvedState: Decodable, Equatable {
    let revision: String
    let version: String?
}

private struct ResolvedContractPin: Equatable {
    let location: String
    let revision: String
    let version: String?
}
