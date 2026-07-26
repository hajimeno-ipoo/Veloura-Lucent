import CryptoKit
import CoreFoundation
import Darwin
import Foundation

enum StemBundledRuntimeAssetLayout: Equatable, Sendable {
    case swiftPackageResources(rootURL: URL)
    case packagedApplicationResources(contentsResourcesURL: URL)

    var rootURL: URL {
        switch self {
        case .swiftPackageResources(let rootURL):
            return rootURL
        case .packagedApplicationResources(let contentsResourcesURL):
            return contentsResourcesURL
        }
    }

    func fileURL(for asset: StemBundledRuntimeAsset) throws -> URL {
        switch self {
        case .swiftPackageResources(let rootURL):
            return try StemModelAssetValidator.safeDescendantURL(
                rootURL: rootURL,
                relativePath: asset.resourceRelativePath,
                field: "bundledRuntimeAssets.resourceRelativePath"
            )
        case .packagedApplicationResources(let contentsResourcesURL):
            return try StemModelAssetValidator.safeDescendantURL(
                rootURL: contentsResourcesURL,
                relativePath: asset.runtimeRelativePath,
                field: "bundledRuntimeAssets.runtimeRelativePath"
            )
        }
    }
}

struct ValidatedStemModelAsset: Equatable, Sendable {
    let kind: StemModelAssetKind
    let fileURL: URL
    let byteCount: Int64
    let sha256: String
}

struct StemBundledRuntimeValidationReport: Equatable, Sendable {
    let contract: StemModelContract
    let assets: [ValidatedStemModelAsset]
}

struct ValidatedStemModelSnapshot: Equatable, Sendable {
    let contract: StemModelContract
    let installationRootURL: URL
    let modelDirectoryURL: URL
    let assets: [ValidatedStemModelAsset]
}

enum StemModelAssetValidationError: LocalizedError, Equatable {
    case manifestMissing(path: String)
    case manifestUnreadable(path: String, reason: String)
    case contractMismatch(field: String, expected: String, actual: String)
    case duplicateRuntimePin(name: String)
    case duplicateAsset(kind: StemModelAssetKind)
    case duplicateRedirectHost(host: String)
    case unsafeRelativePath(field: String, path: String)
    case invalidDownloadURL(kind: StemModelAssetKind, value: String)
    case disallowedDownloadHost(kind: StemModelAssetKind, host: String)
    case downloadURLMissingRevision(kind: StemModelAssetKind, revision: String)
    case directoryMissing(path: String)
    case directoryNotDirectory(path: String)
    case assetMissing(kind: StemModelAssetKind, path: String)
    case bundledRuntimeMissing(path: String)
    case assetSymbolicLink(kind: StemModelAssetKind?, path: String)
    case assetNotRegularFile(kind: StemModelAssetKind?, path: String)
    case assetUnreadable(kind: StemModelAssetKind, path: String, reason: String)
    case assetSizeMismatch(kind: StemModelAssetKind, path: String, expected: Int64, actual: Int64)
    case assetChecksumMismatch(kind: StemModelAssetKind, path: String, expected: String, actual: String)
    case unexpectedInstallationEntry(path: String)
    case modelConfigurationInvalid(path: String, field: String, expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .manifestMissing(let path):
            return "Stem Modeのモデルmanifestが見つかりません: \(path)"
        case .manifestUnreadable(let path, let reason):
            return "Stem Modeのモデルmanifestを読み込めません: \(path)（\(reason)）"
        case .contractMismatch(let field, let expected, let actual):
            return "Stem Modeのモデル契約が一致しません: \(field)（期待: \(expected)、実際: \(actual)）"
        case .duplicateRuntimePin(let name):
            return "Stem Modeの依存関係が重複しています: \(name)"
        case .duplicateAsset(let kind):
            return "Stem Modeの資産定義が重複しています: \(kind.rawValue)"
        case .duplicateRedirectHost(let host):
            return "Stem Modeの許可済みredirect hostが重複しています: \(host)"
        case .unsafeRelativePath(let field, let path):
            return "Stem Modeの相対パスが安全ではありません: \(field)（\(path)）"
        case .invalidDownloadURL(let kind, let value):
            return "Stem Modeの取得URLが無効です: \(kind.rawValue)（\(value)）"
        case .disallowedDownloadHost(let kind, let host):
            return "Stem Modeで許可されていない取得先です: \(kind.rawValue)（\(host)）"
        case .downloadURLMissingRevision(let kind, let revision):
            return "Stem Modeの取得URLに固定Revisionが含まれていません: \(kind.rawValue)（\(revision)）"
        case .directoryMissing(let path):
            return "Stem Modeのモデルディレクトリが見つかりません: \(path)"
        case .directoryNotDirectory(let path):
            return "Stem Modeのモデル保存先がディレクトリではありません: \(path)"
        case .assetMissing(let kind, let path):
            return "Stem Modeに必要なモデル資産が見つかりません: \(kind.rawValue)（\(path)）"
        case .bundledRuntimeMissing(let path):
            return "Stem Modeに必要な同梱MLX実行資産が見つかりません: \(path)"
        case .assetSymbolicLink(let kind, let path):
            return "Stem Modeの資産にsymbolic linkは使用できません: \(kind?.rawValue ?? "directory")（\(path)）"
        case .assetNotRegularFile(let kind, let path):
            return "Stem Modeの資産が通常ファイルではありません: \(kind?.rawValue ?? "directory")（\(path)）"
        case .assetUnreadable(let kind, let path, let reason):
            return "Stem Modeの資産を読み込めません: \(kind.rawValue)（\(path)、\(reason)）"
        case .assetSizeMismatch(let kind, let path, let expected, let actual):
            return "Stem Modeの資産サイズが一致しません: \(kind.rawValue)（\(path)、期待: \(expected)、実際: \(actual)）"
        case .assetChecksumMismatch(let kind, let path, let expected, let actual):
            return "Stem Modeの資産checksumが一致しません: \(kind.rawValue)（\(path)、期待: \(expected)、実際: \(actual)）"
        case .unexpectedInstallationEntry(let path):
            return "Stem Modeのモデル保存先に未承認の項目があります: \(path)"
        case .modelConfigurationInvalid(let path, let field, let expected, let actual):
            return "Stem Modeのモデル設定が一致しません: \(path):\(field)（期待: \(expected)、実際: \(actual)）"
        }
    }
}

struct StemModelAssetValidator: Sendable {
    static let manifestResourceRelativePath = "StemModels/stem-model-manifest.json"
    static let expectedModelRevision = "d4519e24ddc2dd4a11d56a193092433d852c3961"
    static let expectedAssetSetIdentifier = "htdemucs-\(expectedModelRevision)"
    static let modelIdentifier = "mlx-community/demucs-mlx:htdemucs"

    private static let expectedSchemaVersion = 2
    private static let expectedModelName = "Demucs v4 htdemucs"
    private static let expectedModelRepository = "mlx-community/demucs-mlx"
    private static let expectedModelLicense = "mit"
    private static let expectedSourceOrder: [StemRole] = [.drums, .bass, .other, .vocals]
    private static let expectedRedirectHosts = ["huggingface.co", "cas-bridge.xethub.hf.co"]
    private static let expectedRuntimePins: [String: StemRuntimePin] = [
        "demucs-mlx-swift": StemRuntimePin(
            name: "demucs-mlx-swift",
            repo: "https://github.com/kylehowells/demucs-mlx-swift.git",
            version: nil,
            revision: "c81c47178828db2d8bc66e64f80c745c64abdc94"
        ),
        "mlx-swift": StemRuntimePin(
            name: "mlx-swift",
            repo: "https://github.com/ml-explore/mlx-swift.git",
            version: "0.30.6",
            revision: "6ba4827fb82c97d012eec9ab4b2de21f85c3b33d"
        ),
        "swift-transformers": StemRuntimePin(
            name: "swift-transformers",
            repo: "https://github.com/huggingface/swift-transformers.git",
            version: "1.1.6",
            revision: "573e5c9036c2f136b3a8a071da8e8907322403d0"
        ),
        "swift-jinja": StemRuntimePin(
            name: "swift-jinja",
            repo: "https://github.com/huggingface/swift-jinja.git",
            version: "2.3.2",
            revision: "f731f03bf746481d4fda07f817c3774390c4d5b9"
        ),
        "swift-collections": StemRuntimePin(
            name: "swift-collections",
            repo: "https://github.com/apple/swift-collections.git",
            version: "1.4.0",
            revision: "8d9834a6189db730f6264db7556a7ffb751e99ee"
        ),
        "swift-argument-parser": StemRuntimePin(
            name: "swift-argument-parser",
            repo: "https://github.com/apple/swift-argument-parser",
            version: "1.8.2",
            revision: "6a52f3251125d74daf04fcbd5e6f08a75d074382"
        ),
        "swift-numerics": StemRuntimePin(
            name: "swift-numerics",
            repo: "https://github.com/apple/swift-numerics",
            version: "1.1.1",
            revision: "0c0290ff6b24942dadb83a929ffaaa1481df04a2"
        )
    ]
    private static let expectedDownloadableAssets: [StemModelAssetKind: StemDownloadableModelAsset] = [
        .modelWeights: StemDownloadableModelAsset(
            kind: .modelWeights,
            downloadURL: "https://huggingface.co/mlx-community/demucs-mlx/resolve/\(expectedModelRevision)/htdemucs.safetensors",
            installationRelativePath: "htdemucs/htdemucs.safetensors",
            byteCount: 168_005_865,
            sha256: "339d267a7a6983a11eedbdc00413c602a65e9b9103f695fb5c2b2a481cd9d297"
        ),
        .modelConfiguration: StemDownloadableModelAsset(
            kind: .modelConfiguration,
            downloadURL: "https://huggingface.co/mlx-community/demucs-mlx/resolve/\(expectedModelRevision)/htdemucs_config.json",
            installationRelativePath: "htdemucs/htdemucs_config.json",
            byteCount: 1_892,
            sha256: "9258499513944fc062fbca0f11be425a446ec5702869a87e225323d7a57d2a01"
        )
    ]
    private static let expectedBundledRuntimeAssets: [StemModelAssetKind: StemBundledRuntimeAsset] = [
        .metalLibrary: StemBundledRuntimeAsset(
            kind: .metalLibrary,
            resourceRelativePath: "StemModels/MLX/mlx.metallib",
            runtimeRelativePath: "mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib",
            byteCount: 106_957_102,
            sha256: "82be53f327e9a39cb19a18272187187b7636f31989c44ad7ff474f7fe8171974"
        )
    ]

    private let validationReference: StemModelManifest?

    init(validationReference: StemModelManifest? = nil) {
        self.validationReference = validationReference
    }

    func manifestURL(in resourceRootURL: URL) -> URL {
        resourceRootURL.appending(path: Self.manifestResourceRelativePath)
    }

    func loadBundledManifest() throws -> StemModelManifest {
        guard let resourceRootURL = AppResourceBundle.resourceURL else {
            let expectedPath = Bundle.main.resourceURL?
                .appending(path: AppResourceBundle.bundleName, directoryHint: .isDirectory)
                .appending(path: Self.manifestResourceRelativePath)
                .path ?? AppResourceBundle.bundleName
            throw StemModelAssetValidationError.manifestMissing(path: expectedPath)
        }
        return try loadManifest(at: manifestURL(in: resourceRootURL))
    }

    func loadManifest(at manifestURL: URL) throws -> StemModelManifest {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw StemModelAssetValidationError.manifestMissing(path: manifestURL.path)
        }

        do {
            let data = try Data(contentsOf: manifestURL, options: [.mappedIfSafe])
            try validateManifestJSONShape(data)
            return try JSONDecoder().decode(StemModelManifest.self, from: data)
        } catch let error as StemModelAssetValidationError {
            throw error
        } catch {
            throw StemModelAssetValidationError.manifestUnreadable(
                path: manifestURL.path,
                reason: error.localizedDescription
            )
        }
    }

    func validateManifest(_ manifest: StemModelManifest) throws -> StemModelContract {
        try validateManifestSafety(manifest)
        if let validationReference {
            try requireEqual(field: "manifest", expected: validationReference, actual: manifest)
        } else {
            try validateProductionManifest(manifest)
        }

        let outputNames = Dictionary(uniqueKeysWithValues: Self.expectedSourceOrder.map { ($0, $0.rawValue) })
        let outputShapes = Dictionary(
            uniqueKeysWithValues: Self.expectedSourceOrder.map { ($0, [-1, 2, -1]) }
        )

        return StemModelContract(
            identifier: Self.modelIdentifier,
            version: manifest.model.revision,
            assetSetIdentifier: manifest.assetSetIdentifier,
            inputName: "batchData",
            outputNames: outputNames,
            sourceOrder: Self.expectedSourceOrder,
            sampleRate: Double(manifest.audioContract.sampleRateHz),
            channelCount: manifest.audioContract.channelCount,
            inputShape: [-1, 2, -1],
            outputShapes: outputShapes,
            scalarType: manifest.audioContract.scalarType,
            normalization: .modelManagedIdentityBoundary,
            runtime: .mlx,
            defaultSegmentSeconds: 7.8,
            downloadableModelAssets: manifest.downloadableModelAssets,
            bundledRuntimeAssets: manifest.bundledRuntimeAssets
        )
    }

    func validateBundledRuntimeAssets() throws -> StemBundledRuntimeValidationReport {
        let manifest = try loadBundledManifest()
        guard let resourceRootURL = AppResourceBundle.resourceURL else {
            throw StemModelAssetValidationError.manifestMissing(path: AppResourceBundle.bundleName)
        }

        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let contentsResourcesURL = Bundle.main.resourceURL else {
                throw StemModelAssetValidationError.manifestMissing(
                    path: Bundle.main.bundleURL.appending(path: "Contents/Resources").path
                )
            }
            return try validateBundledRuntimeAssets(
                manifest: manifest,
                layout: .packagedApplicationResources(contentsResourcesURL: contentsResourcesURL)
            )
        }

        return try validateBundledRuntimeAssets(
            manifest: manifest,
            layout: .swiftPackageResources(rootURL: resourceRootURL)
        )
    }

    func validateBundledRuntimeAssets(
        manifest: StemModelManifest,
        layout: StemBundledRuntimeAssetLayout
    ) throws -> StemBundledRuntimeValidationReport {
        let contract = try validateManifest(manifest)
        var validated: [ValidatedStemModelAsset] = []
        for asset in manifest.bundledRuntimeAssets.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
            let fileURL = try layout.fileURL(for: asset)
            try requireNoSymbolicLinks(rootURL: layout.rootURL, fileURL: fileURL, kind: asset.kind)
            validated.append(
                try validateFile(
                    kind: asset.kind,
                    fileURL: fileURL,
                    expectedByteCount: asset.byteCount,
                    expectedSHA256: asset.sha256,
                    bundledRuntime: true
                )
            )
        }
        return StemBundledRuntimeValidationReport(contract: contract, assets: validated)
    }

    func validateStagedModelAssets(
        manifest: StemModelManifest,
        rootURL: URL
    ) throws -> ValidatedStemModelSnapshot {
        try validateModelDirectoryContents(
            rootURL: rootURL,
            expectedRelativeFiles: Set(manifest.downloadableModelAssets.map(\.installationRelativePath))
        )
        return try validateModelAssets(manifest: manifest, rootURL: rootURL)
    }

    func validateInstalledModelAssets(
        manifest: StemModelManifest,
        rootURL: URL
    ) throws -> ValidatedStemModelSnapshot {
        var expected = Set(manifest.downloadableModelAssets.map(\.installationRelativePath))
        expected.insert(StemModelStorePaths.receiptFileName)
        try validateModelDirectoryContents(rootURL: rootURL, expectedRelativeFiles: expected)
        return try validateModelAssets(manifest: manifest, rootURL: rootURL)
    }

    func sha256(fileURL: URL) throws -> String {
        try inspectRegularFile(fileURL).sha256
    }

    static func safeDescendantURL(
        rootURL: URL,
        relativePath: String,
        field: String
    ) throws -> URL {
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("\\"),
              !relativePath.contains("\0"),
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw StemModelAssetValidationError.unsafeRelativePath(field: field, path: relativePath)
        }

        let result = components.reduce(rootURL.standardizedFileURL) { partial, component in
            partial.appending(path: component)
        }.standardizedFileURL
        let rootPath = rootURL.standardizedFileURL.path
        guard result.path.hasPrefix(rootPath + "/") else {
            throw StemModelAssetValidationError.unsafeRelativePath(field: field, path: relativePath)
        }
        return result
    }

    private func validateProductionManifest(_ manifest: StemModelManifest) throws {
        try requireEqual(field: "schemaVersion", expected: Self.expectedSchemaVersion, actual: manifest.schemaVersion)
        try requireEqual(
            field: "assetSetIdentifier",
            expected: Self.expectedAssetSetIdentifier,
            actual: manifest.assetSetIdentifier
        )
        try requireEqual(field: "model.name", expected: Self.expectedModelName, actual: manifest.model.name)
        try requireEqual(field: "model.repo", expected: Self.expectedModelRepository, actual: manifest.model.repo)
        try requireEqual(field: "model.revision", expected: Self.expectedModelRevision, actual: manifest.model.revision)
        try requireEqual(
            field: "model.licenseMetadata",
            expected: Self.expectedModelLicense,
            actual: manifest.model.licenseMetadata.lowercased()
        )
        try requireEqual(
            field: "downloadPolicy",
            expected: StemModelDownloadPolicy(
                requiresExplicitUserConfirmation: true,
                revisionResponseHeader: "X-Repo-Commit",
                allowedRedirectHosts: Self.expectedRedirectHosts
            ),
            actual: manifest.downloadPolicy
        )

        try validateRuntimePins(manifest.runtimePins)
        try validateAudioContract(manifest.audioContract)
        try validateDownloadableAssetDefinitions(manifest.downloadableModelAssets)
        try validateBundledRuntimeAssetDefinitions(manifest.bundledRuntimeAssets)
        try validateMetalLibraryProvenance(manifest.metalLibraryBuildProvenance)
    }

    private func validateManifestSafety(_ manifest: StemModelManifest) throws {
        guard manifest.downloadPolicy.requiresExplicitUserConfirmation else {
            throw StemModelAssetValidationError.contractMismatch(
                field: "downloadPolicy.requiresExplicitUserConfirmation",
                expected: "true",
                actual: "false"
            )
        }

        var redirectHosts = Set<String>()
        for host in manifest.downloadPolicy.allowedRedirectHosts {
            let normalized = host.lowercased()
            guard !normalized.isEmpty,
                  normalized == host,
                  !normalized.contains("/"),
                  !normalized.contains(":") else {
                throw StemModelAssetValidationError.contractMismatch(
                    field: "downloadPolicy.allowedRedirectHosts",
                    expected: "lowercase host names",
                    actual: host
                )
            }
            guard redirectHosts.insert(normalized).inserted else {
                throw StemModelAssetValidationError.duplicateRedirectHost(host: normalized)
            }
        }

        _ = try uniqueDictionary(manifest.downloadableModelAssets, key: \StemDownloadableModelAsset.kind) {
            StemModelAssetValidationError.duplicateAsset(kind: $0)
        }
        _ = try uniqueDictionary(manifest.bundledRuntimeAssets, key: \StemBundledRuntimeAsset.kind) {
            StemModelAssetValidationError.duplicateAsset(kind: $0)
        }

        for asset in manifest.downloadableModelAssets {
            _ = try Self.safeDescendantURL(
                rootURL: URL(filePath: "/validated-root", directoryHint: .isDirectory),
                relativePath: asset.installationRelativePath,
                field: "downloadableModelAssets.installationRelativePath"
            )
            try validateSHA256(asset.sha256, field: "downloadableModelAssets.sha256")
            guard asset.byteCount > 0 else {
                throw StemModelAssetValidationError.contractMismatch(
                    field: "downloadableModelAssets.byteCount",
                    expected: "> 0",
                    actual: String(asset.byteCount)
                )
            }
            try validateDownloadURL(asset: asset, manifest: manifest)
        }

        for asset in manifest.bundledRuntimeAssets {
            _ = try Self.safeDescendantURL(
                rootURL: URL(filePath: "/validated-root", directoryHint: .isDirectory),
                relativePath: asset.resourceRelativePath,
                field: "bundledRuntimeAssets.resourceRelativePath"
            )
            _ = try Self.safeDescendantURL(
                rootURL: URL(filePath: "/validated-root", directoryHint: .isDirectory),
                relativePath: asset.runtimeRelativePath,
                field: "bundledRuntimeAssets.runtimeRelativePath"
            )
            try validateSHA256(asset.sha256, field: "bundledRuntimeAssets.sha256")
            guard asset.byteCount > 0 else {
                throw StemModelAssetValidationError.contractMismatch(
                    field: "bundledRuntimeAssets.byteCount",
                    expected: "> 0",
                    actual: String(asset.byteCount)
                )
            }
        }
    }

    private func validateDownloadURL(
        asset: StemDownloadableModelAsset,
        manifest: StemModelManifest
    ) throws {
        guard let url = URL(string: asset.downloadURL),
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.query == nil,
              url.fragment == nil else {
            throw StemModelAssetValidationError.invalidDownloadURL(kind: asset.kind, value: asset.downloadURL)
        }
        guard manifest.downloadPolicy.allowedRedirectHosts.contains(host) else {
            throw StemModelAssetValidationError.disallowedDownloadHost(kind: asset.kind, host: host)
        }
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        guard pathComponents.count >= 5,
              pathComponents[2] == "resolve",
              pathComponents[3] == manifest.model.revision,
              manifest.model.revision.count == 40,
              manifest.model.revision.allSatisfy({ $0.isHexDigit }) else {
            throw StemModelAssetValidationError.downloadURLMissingRevision(
                kind: asset.kind,
                revision: manifest.model.revision
            )
        }
    }

    private func validateModelAssets(
        manifest: StemModelManifest,
        rootURL: URL
    ) throws -> ValidatedStemModelSnapshot {
        let contract = try validateManifest(manifest)
        var validated: [ValidatedStemModelAsset] = []
        validated.reserveCapacity(manifest.downloadableModelAssets.count)

        for asset in manifest.downloadableModelAssets.sorted(by: { $0.kind.rawValue < $1.kind.rawValue }) {
            let fileURL = try Self.safeDescendantURL(
                rootURL: rootURL,
                relativePath: asset.installationRelativePath,
                field: "downloadableModelAssets.installationRelativePath"
            )
            try requireNoSymbolicLinks(rootURL: rootURL, fileURL: fileURL, kind: asset.kind)
            validated.append(
                try validateFile(
                    kind: asset.kind,
                    fileURL: fileURL,
                    expectedByteCount: asset.byteCount,
                    expectedSHA256: asset.sha256,
                    bundledRuntime: false
                )
            )
        }

        guard let configuration = manifest.downloadableModelAssets.first(where: { $0.kind == .modelConfiguration }) else {
            throw StemModelAssetValidationError.contractMismatch(
                field: "downloadableModelAssets.modelConfiguration",
                expected: "present",
                actual: "missing"
            )
        }
        let configurationURL = try Self.safeDescendantURL(
            rootURL: rootURL,
            relativePath: configuration.installationRelativePath,
            field: "downloadableModelAssets.installationRelativePath"
        )
        try validateModelConfiguration(at: configurationURL)

        let modelDirectoryURL = configurationURL.deletingLastPathComponent().standardizedFileURL
        return ValidatedStemModelSnapshot(
            contract: contract,
            installationRootURL: rootURL.standardizedFileURL,
            modelDirectoryURL: modelDirectoryURL,
            assets: validated
        )
    }

    private func validateFile(
        kind: StemModelAssetKind,
        fileURL: URL,
        expectedByteCount: Int64,
        expectedSHA256: String,
        bundledRuntime: Bool
    ) throws -> ValidatedStemModelAsset {
        let inspection: (byteCount: Int64, sha256: String)
        do {
            inspection = try inspectRegularFile(fileURL)
        } catch let error as FileInspectionError {
            switch error {
            case .missing:
                if bundledRuntime {
                    throw StemModelAssetValidationError.bundledRuntimeMissing(path: fileURL.path)
                }
                throw StemModelAssetValidationError.assetMissing(kind: kind, path: fileURL.path)
            case .symbolicLink:
                throw StemModelAssetValidationError.assetSymbolicLink(kind: kind, path: fileURL.path)
            case .notRegularFile:
                throw StemModelAssetValidationError.assetNotRegularFile(kind: kind, path: fileURL.path)
            case .unreadable(let reason):
                throw StemModelAssetValidationError.assetUnreadable(
                    kind: kind,
                    path: fileURL.path,
                    reason: reason
                )
            }
        }

        guard inspection.byteCount == expectedByteCount else {
            throw StemModelAssetValidationError.assetSizeMismatch(
                kind: kind,
                path: fileURL.path,
                expected: expectedByteCount,
                actual: inspection.byteCount
            )
        }
        guard inspection.sha256 == expectedSHA256 else {
            throw StemModelAssetValidationError.assetChecksumMismatch(
                kind: kind,
                path: fileURL.path,
                expected: expectedSHA256,
                actual: inspection.sha256
            )
        }
        return ValidatedStemModelAsset(
            kind: kind,
            fileURL: fileURL,
            byteCount: inspection.byteCount,
            sha256: inspection.sha256
        )
    }

    private func validateModelConfiguration(at fileURL: URL) throws {
        let data: Data
        do {
            data = try readRegularFileData(fileURL)
        } catch {
            throw StemModelAssetValidationError.assetUnreadable(
                kind: .modelConfiguration,
                path: fileURL.path,
                reason: error.localizedDescription
            )
        }

        let json: [String: Any]
        do {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            json = value
        } catch {
            throw StemModelAssetValidationError.modelConfigurationInvalid(
                path: fileURL.path,
                field: "JSON",
                expected: "object",
                actual: error.localizedDescription
            )
        }

        try requireConfigurationValue(json["model_name"], field: "model_name", expected: "htdemucs", path: fileURL.path)
        try requireConfigurationValue(
            json["model_class"],
            field: "model_class",
            expected: "BagOfModelsMLX",
            path: fileURL.path
        )
        try requireConfigurationInteger(json["num_models"], field: "num_models", expected: 1, path: fileURL.path)
        try requireConfigurationValue(
            json["sub_model_class"],
            field: "sub_model_class",
            expected: "HTDemucsMLX",
            path: fileURL.path
        )

        guard let kwargs = json["kwargs"] as? [String: Any] else {
            throw StemModelAssetValidationError.modelConfigurationInvalid(
                path: fileURL.path,
                field: "kwargs",
                expected: "object",
                actual: description(of: json["kwargs"])
            )
        }
        try requireConfigurationInteger(kwargs["samplerate"], field: "kwargs.samplerate", expected: 44_100, path: fileURL.path)
        try requireConfigurationInteger(kwargs["audio_channels"], field: "kwargs.audio_channels", expected: 2, path: fileURL.path)
        try requireConfigurationValue(kwargs["segment"], field: "kwargs.segment", expected: "39/5", path: fileURL.path)
        let sources = kwargs["sources"] as? [String]
        guard sources == Self.expectedSourceOrder.map(\.rawValue) else {
            throw StemModelAssetValidationError.modelConfigurationInvalid(
                path: fileURL.path,
                field: "kwargs.sources",
                expected: String(describing: Self.expectedSourceOrder.map(\.rawValue)),
                actual: description(of: kwargs["sources"])
            )
        }
    }

    private func validateModelDirectoryContents(
        rootURL: URL,
        expectedRelativeFiles: Set<String>
    ) throws {
        let root = rootURL.standardizedFileURL
        guard FileManager.default.fileExists(atPath: root.path) else {
            throw StemModelAssetValidationError.directoryMissing(path: root.path)
        }
        let rootValues: URLResourceValues
        do {
            rootValues = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        } catch {
            throw StemModelAssetValidationError.directoryNotDirectory(path: root.path)
        }
        if rootValues.isSymbolicLink == true {
            throw StemModelAssetValidationError.assetSymbolicLink(kind: nil, path: root.path)
        }
        guard rootValues.isDirectory == true else {
            throw StemModelAssetValidationError.directoryNotDirectory(path: root.path)
        }

        var expectedDirectories = Set<String>()
        for relativePath in expectedRelativeFiles {
            _ = try Self.safeDescendantURL(
                rootURL: root,
                relativePath: relativePath,
                field: "installationRelativePath"
            )
            let parts = relativePath.split(separator: "/").map(String.init)
            if parts.count > 1 {
                for count in 1..<parts.count {
                    expectedDirectories.insert(parts.prefix(count).joined(separator: "/"))
                }
            }
        }

        try validateDirectoryEntries(
            directoryURL: root,
            relativePrefix: "",
            expectedRelativeFiles: expectedRelativeFiles,
            expectedDirectories: expectedDirectories
        )
    }

    private func validateDirectoryEntries(
        directoryURL: URL,
        relativePrefix: String,
        expectedRelativeFiles: Set<String>,
        expectedDirectories: Set<String>
    ) throws {
        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                options: []
            )
        } catch {
            throw StemModelAssetValidationError.directoryNotDirectory(path: directoryURL.path)
        }

        for entry in entries {
            let relativePath = relativePrefix.isEmpty
                ? entry.lastPathComponent
                : "\(relativePrefix)/\(entry.lastPathComponent)"
            let values = try entry.resourceValues(
                forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                throw StemModelAssetValidationError.assetSymbolicLink(kind: nil, path: entry.path)
            }
            if values.isDirectory == true {
                guard expectedDirectories.contains(relativePath) else {
                    throw StemModelAssetValidationError.unexpectedInstallationEntry(path: entry.path)
                }
                try validateDirectoryEntries(
                    directoryURL: entry,
                    relativePrefix: relativePath,
                    expectedRelativeFiles: expectedRelativeFiles,
                    expectedDirectories: expectedDirectories
                )
            } else if values.isRegularFile == true {
                guard expectedRelativeFiles.contains(relativePath) else {
                    throw StemModelAssetValidationError.unexpectedInstallationEntry(path: entry.path)
                }
            } else {
                throw StemModelAssetValidationError.assetNotRegularFile(kind: nil, path: entry.path)
            }
        }
    }

    private func requireNoSymbolicLinks(
        rootURL: URL,
        fileURL: URL,
        kind: StemModelAssetKind
    ) throws {
        let root = rootURL.standardizedFileURL
        let file = fileURL.standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else {
            throw StemModelAssetValidationError.unsafeRelativePath(
                field: "resolvedAssetPath",
                path: file.path
            )
        }

        let relative = String(file.path.dropFirst(root.path.count + 1))
        var current = root
        for component in relative.split(separator: "/") {
            current.append(path: String(component))
            guard FileManager.default.fileExists(atPath: current.path) else { continue }
            let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values.isSymbolicLink == true {
                throw StemModelAssetValidationError.assetSymbolicLink(kind: kind, path: current.path)
            }
        }
    }

    private func inspectRegularFile(_ fileURL: URL) throws -> (byteCount: Int64, sha256: String) {
        var linkStat = stat()
        guard Darwin.lstat(fileURL.path, &linkStat) == 0 else {
            if errno == ENOENT { throw FileInspectionError.missing }
            throw FileInspectionError.unreadable(posixReason())
        }
        if (linkStat.st_mode & S_IFMT) == S_IFLNK {
            throw FileInspectionError.symbolicLink
        }
        guard (linkStat.st_mode & S_IFMT) == S_IFREG else {
            throw FileInspectionError.notRegularFile
        }

        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ELOOP { throw FileInspectionError.symbolicLink }
            if errno == ENOENT { throw FileInspectionError.missing }
            throw FileInspectionError.unreadable(posixReason())
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)

        var openedStat = stat()
        guard Darwin.fstat(descriptor, &openedStat) == 0 else {
            throw FileInspectionError.unreadable(posixReason())
        }
        guard (openedStat.st_mode & S_IFMT) == S_IFREG else {
            throw FileInspectionError.notRegularFile
        }

        var hasher = SHA256()
        do {
            while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                hasher.update(data: data)
            }
        } catch {
            throw FileInspectionError.unreadable(error.localizedDescription)
        }
        return (Int64(openedStat.st_size), hexadecimalString(hasher.finalize()))
    }

    private func readRegularFileData(_ fileURL: URL) throws -> Data {
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        return try handle.readToEnd() ?? Data()
    }

    private func hexadecimalString<Digest: Sequence>(_ digest: Digest) -> String where Digest.Element == UInt8 {
        let digits = Array("0123456789abcdef".utf8)
        var result: [UInt8] = []
        result.reserveCapacity(64)
        for byte in digest {
            result.append(digits[Int(byte >> 4)])
            result.append(digits[Int(byte & 0x0f)])
        }
        return String(decoding: result, as: UTF8.self)
    }

    private func posixReason() -> String {
        String(cString: strerror(errno))
    }

    private func validateRuntimePins(_ runtimePins: [StemRuntimePin]) throws {
        let pinsByName = try uniqueDictionary(runtimePins, key: \StemRuntimePin.name) {
            StemModelAssetValidationError.duplicateRuntimePin(name: $0)
        }
        try requireEqual(field: "runtimePins.count", expected: Self.expectedRuntimePins.count, actual: pinsByName.count)
        for (name, expected) in Self.expectedRuntimePins {
            guard let actual = pinsByName[name] else {
                throw StemModelAssetValidationError.contractMismatch(
                    field: "runtimePins.\(name)", expected: "present", actual: "missing"
                )
            }
            try requireEqual(field: "runtimePins.\(name)", expected: expected, actual: actual)
        }
    }

    private func validateAudioContract(_ contract: StemModelAudioContract) throws {
        try requireEqual(field: "audioContract.sampleRateHz", expected: 44_100, actual: contract.sampleRateHz)
        try requireEqual(field: "audioContract.channelCount", expected: 2, actual: contract.channelCount)
        try requireEqual(field: "audioContract.channelLayout", expected: .stereo, actual: contract.channelLayout)
        try requireEqual(field: "audioContract.scalarType", expected: .float32, actual: contract.scalarType)
        try requireEqual(field: "audioContract.inputTensorLayout", expected: .channelMajor, actual: contract.inputTensorLayout)
        try requireEqual(field: "audioContract.outputTensorLayout", expected: .sourceMajor, actual: contract.outputTensorLayout)
        try requireEqual(
            field: "audioContract.channelLayoutWithinSource",
            expected: .channelMajor,
            actual: contract.channelLayoutWithinSource
        )
        try requireEqual(field: "audioContract.sourceOrder", expected: Self.expectedSourceOrder, actual: contract.sourceOrder)
    }

    private func validateDownloadableAssetDefinitions(_ assets: [StemDownloadableModelAsset]) throws {
        let byKind = try uniqueDictionary(assets, key: \StemDownloadableModelAsset.kind) {
            StemModelAssetValidationError.duplicateAsset(kind: $0)
        }
        try requireEqual(field: "downloadableModelAssets.count", expected: 2, actual: byKind.count)
        try requireEqual(
            field: "downloadableModelAssets.kinds",
            expected: Set([StemModelAssetKind.modelWeights, .modelConfiguration]),
            actual: Set(byKind.keys)
        )
        for (kind, expected) in Self.expectedDownloadableAssets {
            guard let actual = byKind[kind] else {
                throw StemModelAssetValidationError.contractMismatch(
                    field: "downloadableModelAssets.\(kind.rawValue)", expected: "present", actual: "missing"
                )
            }
            try requireEqual(field: "downloadableModelAssets.\(kind.rawValue)", expected: expected, actual: actual)
        }
    }

    private func validateBundledRuntimeAssetDefinitions(_ assets: [StemBundledRuntimeAsset]) throws {
        let byKind = try uniqueDictionary(assets, key: \StemBundledRuntimeAsset.kind) {
            StemModelAssetValidationError.duplicateAsset(kind: $0)
        }
        try requireEqual(field: "bundledRuntimeAssets.count", expected: 1, actual: byKind.count)
        try requireEqual(field: "bundledRuntimeAssets.kinds", expected: Set([StemModelAssetKind.metalLibrary]), actual: Set(byKind.keys))
        for (kind, expected) in Self.expectedBundledRuntimeAssets {
            guard let actual = byKind[kind] else {
                throw StemModelAssetValidationError.contractMismatch(
                    field: "bundledRuntimeAssets.\(kind.rawValue)", expected: "present", actual: "missing"
                )
            }
            try requireEqual(field: "bundledRuntimeAssets.\(kind.rawValue)", expected: expected, actual: actual)
        }
    }

    private func validateMetalLibraryProvenance(_ provenance: StemMetalLibraryBuildProvenance) throws {
        let expected = StemMetalLibraryBuildProvenance(
            sourceRepo: "https://github.com/ml-explore/mlx-swift.git",
            sourceVersion: "0.30.6",
            sourceRevision: "6ba4827fb82c97d012eec9ab4b2de21f85c3b33d",
            sourceDirectory: "Source/Cmlx/mlx/mlx/backend/metal/kernels",
            sourceSelection: "all *.metal files except *_nax.metal, sorted with LC_ALL=C",
            sourceFileCount: 32,
            compilerCommand: "xcrun -sdk macosx metal",
            linkerCommand: "xcrun -sdk macosx metallib",
            compilerFlags: [
                "-x", "metal", "-Wall", "-Wextra", "-fno-fast-math",
                "-Wno-c++17-extensions", "-Wno-c++20-extensions"
            ],
            includeDirectories: [
                "Source/Cmlx/mlx/mlx/backend/metal/kernels",
                "Source/Cmlx/mlx"
            ],
            verifiedToolchain: StemMetalToolchainProvenance(
                xcodeVersion: "26.6",
                xcodeBuildVersion: "17F113",
                macosSdkVersion: "26.5",
                metalVersion: "Apple metal version 32023.883 (metalfe-32023.883)",
                metallibVersion: "AIR-LLD 32023.883 (metalfe-32023.883) (compatible with legacy metallib linker)"
            )
        )
        try requireEqual(field: "metalLibraryBuildProvenance", expected: expected, actual: provenance)
    }

    private func validateSHA256(_ value: String, field: String) throws {
        guard value.count == 64,
              value.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw StemModelAssetValidationError.contractMismatch(
                field: field,
                expected: "64 lowercase hexadecimal characters",
                actual: value
            )
        }
    }

    private func requireConfigurationValue(
        _ actual: Any?,
        field: String,
        expected: String,
        path: String
    ) throws {
        guard actual as? String == expected else {
            throw StemModelAssetValidationError.modelConfigurationInvalid(
                path: path, field: field, expected: expected, actual: description(of: actual)
            )
        }
    }

    private func requireConfigurationInteger(
        _ actual: Any?,
        field: String,
        expected: Int,
        path: String
    ) throws {
        guard let number = actual as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.stringValue == String(expected) else {
            throw StemModelAssetValidationError.modelConfigurationInvalid(
                path: path, field: field, expected: String(expected), actual: description(of: actual)
            )
        }
    }

    private func description(of value: Any?) -> String {
        value.map { String(describing: $0) } ?? "missing"
    }

    private func requireEqual<Value: Equatable>(
        field: String,
        expected: Value,
        actual: Value
    ) throws {
        guard expected == actual else {
            throw StemModelAssetValidationError.contractMismatch(
                field: field,
                expected: String(describing: expected),
                actual: String(describing: actual)
            )
        }
    }

    private func uniqueDictionary<Element, Key: Hashable>(
        _ elements: [Element],
        key: KeyPath<Element, Key>,
        duplicateError: (Key) -> StemModelAssetValidationError
    ) throws -> [Key: Element] {
        var result: [Key: Element] = [:]
        for element in elements {
            let elementKey = element[keyPath: key]
            guard result[elementKey] == nil else { throw duplicateError(elementKey) }
            result[elementKey] = element
        }
        return result
    }

    private func validateManifestJSONShape(_ data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw StemModelAssetValidationError.contractMismatch(
                field: "manifest", expected: "JSON object", actual: "non-object"
            )
        }
        try requireKeys(
            root,
            path: "manifest",
            expected: [
                "schemaVersion", "assetSetIdentifier", "model", "runtimePins", "audioContract",
                "downloadPolicy", "downloadableModelAssets", "bundledRuntimeAssets",
                "metalLibraryBuildProvenance"
            ]
        )
        try requireObjectKeys(root["model"], path: "model", expected: ["name", "repo", "revision", "licenseMetadata"])
        try requireRuntimePinKeys(root["runtimePins"])
        try requireObjectKeys(
            root["audioContract"],
            path: "audioContract",
            expected: [
                "sampleRateHz", "channelCount", "channelLayout", "scalarType", "inputTensorLayout",
                "outputTensorLayout", "channelLayoutWithinSource", "sourceOrder"
            ]
        )
        try requireObjectKeys(
            root["downloadPolicy"],
            path: "downloadPolicy",
            expected: ["requiresExplicitUserConfirmation", "revisionResponseHeader", "allowedRedirectHosts"]
        )
        try requireArrayObjectKeys(
            root["downloadableModelAssets"],
            path: "downloadableModelAssets",
            expected: ["kind", "downloadURL", "installationRelativePath", "byteCount", "sha256"]
        )
        try requireArrayObjectKeys(
            root["bundledRuntimeAssets"],
            path: "bundledRuntimeAssets",
            expected: ["kind", "resourceRelativePath", "runtimeRelativePath", "byteCount", "sha256"]
        )
        try requireObjectKeys(
            root["metalLibraryBuildProvenance"],
            path: "metalLibraryBuildProvenance",
            expected: [
                "sourceRepo", "sourceVersion", "sourceRevision", "sourceDirectory", "sourceSelection",
                "sourceFileCount", "compilerCommand", "linkerCommand", "compilerFlags",
                "includeDirectories", "verifiedToolchain"
            ]
        )
        guard let provenance = root["metalLibraryBuildProvenance"] as? [String: Any] else {
            throw StemModelAssetValidationError.contractMismatch(
                field: "metalLibraryBuildProvenance",
                expected: "JSON object",
                actual: description(of: root["metalLibraryBuildProvenance"])
            )
        }
        try requireObjectKeys(
            provenance["verifiedToolchain"],
            path: "metalLibraryBuildProvenance.verifiedToolchain",
            expected: [
                "xcodeVersion", "xcodeBuildVersion", "macosSdkVersion", "metalVersion",
                "metallibVersion"
            ]
        )
    }

    private func requireRuntimePinKeys(_ value: Any?) throws {
        guard let pins = value as? [[String: Any]] else {
            throw StemModelAssetValidationError.contractMismatch(
                field: "runtimePins",
                expected: "array of JSON objects",
                actual: description(of: value)
            )
        }
        for (index, pin) in pins.enumerated() {
            let expected: Set<String>
            if pin["name"] as? String == "demucs-mlx-swift" {
                expected = ["name", "repo", "revision"]
            } else {
                expected = ["name", "repo", "version", "revision"]
            }
            try requireKeys(pin, path: "runtimePins[\(index)]", expected: expected)
        }
    }

    private func requireObjectKeys(_ value: Any?, path: String, expected: Set<String>) throws {
        guard let object = value as? [String: Any] else {
            throw StemModelAssetValidationError.contractMismatch(
                field: path, expected: "JSON object", actual: description(of: value)
            )
        }
        try requireKeys(object, path: path, expected: expected)
    }

    private func requireArrayObjectKeys(_ value: Any?, path: String, expected: Set<String>) throws {
        guard let objects = value as? [[String: Any]] else {
            throw StemModelAssetValidationError.contractMismatch(
                field: path, expected: "array of JSON objects", actual: description(of: value)
            )
        }
        for (index, object) in objects.enumerated() {
            try requireKeys(object, path: "\(path)[\(index)]", expected: expected)
        }
    }

    private func requireKeys(_ object: [String: Any], path: String, expected: Set<String>) throws {
        let actual = Set(object.keys)
        guard actual == expected else {
            throw StemModelAssetValidationError.contractMismatch(
                field: "\(path).keys",
                expected: String(describing: expected.sorted()),
                actual: String(describing: actual.sorted())
            )
        }
    }
}

private enum FileInspectionError: Error {
    case missing
    case symbolicLink
    case notRegularFile
    case unreadable(String)
}
