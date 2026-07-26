import Darwin
import Foundation

enum StemModelInstallationStoreError: LocalizedError, Equatable {
    case stagingDirectoryAlreadyExists(path: String)
    case stagingDirectoryMissing(path: String)
    case generationAlreadyExists(path: String)
    case storePathSymbolicLink(path: String)
    case storePathNotDirectory(path: String)
    case activePointerNotRegularFile(path: String)
    case activePointerUnreadable(path: String, reason: String)
    case activePointerMismatch(field: String, expected: String, actual: String)
    case receiptMissing(path: String)
    case receiptUnreadable(path: String, reason: String)
    case receiptMismatch(field: String, expected: String, actual: String)
    case sourceEvidenceMissing(kind: StemModelAssetKind)
    case sourceEvidenceDuplicate(kind: StemModelAssetKind)
    case sourceEvidenceUnexpectedKind(kind: StemModelAssetKind)
    case sourceEvidenceStableURLMismatch(
        kind: StemModelAssetKind,
        expected: String
    )
    case sourceEvidenceHeaderMismatch(
        kind: StemModelAssetKind,
        expected: String,
        actual: String
    )
    case sourceEvidenceRevisionMismatch(
        kind: StemModelAssetKind,
        expected: String,
        actual: String
    )
    case crossVolumeActivation(stagingPath: String, versionsPath: String)
    case fileOperationFailed(operation: String, path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case .stagingDirectoryAlreadyExists(let path):
            return "Stem Modeの一時保存先が既に存在します: \(path)"
        case .stagingDirectoryMissing(let path):
            return "Stem Modeの一時保存先が見つかりません: \(path)"
        case .generationAlreadyExists(let path):
            return "Stem Modeのモデル世代が既に存在します: \(path)"
        case .storePathSymbolicLink(let path):
            return "Stem Modeの保存先にsymbolic linkは使用できません: \(path)"
        case .storePathNotDirectory(let path):
            return "Stem Modeの保存先がディレクトリではありません: \(path)"
        case .activePointerNotRegularFile(let path):
            return "Stem Modeのactive pointerが通常ファイルではありません: \(path)"
        case .activePointerUnreadable(let path, let reason):
            return "Stem Modeのactive pointerを読み込めません: \(path)（\(reason)）"
        case .activePointerMismatch(let field, let expected, let actual):
            return "Stem Modeのactive pointerが一致しません: \(field)（期待: \(expected)、実際: \(actual)）"
        case .receiptMissing(let path):
            return "Stem Modeのモデルreceiptが見つかりません: \(path)"
        case .receiptUnreadable(let path, let reason):
            return "Stem Modeのモデルreceiptを読み込めません: \(path)（\(reason)）"
        case .receiptMismatch(let field, let expected, let actual):
            return "Stem Modeのモデルreceiptが一致しません: \(field)（期待: \(expected)、実際: \(actual)）"
        case .sourceEvidenceMissing(let kind):
            return "Stem Modeの取得元証拠がありません: \(kind.rawValue)"
        case .sourceEvidenceDuplicate(let kind):
            return "Stem Modeの取得元証拠が重複しています: \(kind.rawValue)"
        case .sourceEvidenceUnexpectedKind(let kind):
            return "Stem Modeの取得元証拠に対象外の資産があります: \(kind.rawValue)"
        case .sourceEvidenceStableURLMismatch(let kind, let expected):
            return "Stem Modeのstable URL証拠が一致しません: \(kind.rawValue)（期待: \(expected)）"
        case .sourceEvidenceHeaderMismatch(let kind, let expected, let actual):
            return "Stem ModeのRevision header証拠が一致しません: \(kind.rawValue)（期待: \(expected)、実際: \(actual)）"
        case .sourceEvidenceRevisionMismatch(let kind, let expected, let actual):
            return "Stem ModeのRevision証拠が一致しません: \(kind.rawValue)（期待: \(expected)、実際: \(actual)）"
        case .crossVolumeActivation(let stagingPath, let versionsPath):
            return "Stem Modeのモデルを原子的に有効化できない保存場所です: \(stagingPath) → \(versionsPath)"
        case .fileOperationFailed(let operation, let path, let reason):
            return "Stem Modeのファイル操作に失敗しました: \(operation)（\(path)、\(reason)）"
        }
    }
}

actor StemModelInstallationStore {
    let paths: StemModelStorePaths
    private let validator: StemModelAssetValidator
    private let fileManager: FileManager

    init(
        paths: StemModelStorePaths = .production,
        validator: StemModelAssetValidator = StemModelAssetValidator(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.validator = validator
        self.fileManager = fileManager
    }

    func makeStagingDirectory(operationIdentifier: UUID) throws -> URL {
        try ensureDirectory(paths.rootURL)
        try ensureDirectory(paths.stagingRootURL)

        let stagingURL = paths.stagingDirectoryURL(operationIdentifier: operationIdentifier)
        if pathExistsIncludingSymbolicLink(stagingURL) {
            throw StemModelInstallationStoreError.stagingDirectoryAlreadyExists(path: stagingURL.path)
        }
        do {
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: false)
            try requireDirectory(stagingURL)
            return stagingURL
        } catch let error as StemModelInstallationStoreError {
            throw error
        } catch {
            throw StemModelInstallationStoreError.fileOperationFailed(
                operation: "staging directory creation",
                path: stagingURL.path,
                reason: error.localizedDescription
            )
        }
    }

    func stagingDirectoryURL(operationIdentifier: UUID) -> URL {
        paths.stagingDirectoryURL(operationIdentifier: operationIdentifier)
    }

    func discardStagingDirectory(operationIdentifier: UUID) throws {
        let stagingURL = paths.stagingDirectoryURL(operationIdentifier: operationIdentifier)
        guard pathExistsIncludingSymbolicLink(stagingURL) else { return }
        try requireNoSymbolicLinks(from: paths.rootURL, through: stagingURL)
        do {
            try fileManager.removeItem(at: stagingURL)
        } catch {
            throw StemModelInstallationStoreError.fileOperationFailed(
                operation: "staging directory removal",
                path: stagingURL.path,
                reason: error.localizedDescription
            )
        }
    }

    func activate(
        operationIdentifier: UUID,
        generationIdentifier: UUID,
        manifest: StemModelManifest,
        sourceEvidence: [StemModelInstallationSourceEvidence],
        activatedAt: Date = Date()
    ) throws -> ValidatedStemModelInstallation {
        let contract = try validator.validateManifest(manifest)
        let validatedSourceEvidence = try validateSourceEvidence(
            sourceEvidence,
            manifest: manifest
        )
        let stagingURL = paths.stagingDirectoryURL(operationIdentifier: operationIdentifier)
        guard pathExistsIncludingSymbolicLink(stagingURL) else {
            throw StemModelInstallationStoreError.stagingDirectoryMissing(path: stagingURL.path)
        }
        try requireNoSymbolicLinks(from: paths.rootURL, through: stagingURL)

        let stagedSnapshot = try validator.validateStagedModelAssets(
            manifest: manifest,
            rootURL: stagingURL
        )
        let receipt = makeReceipt(
            contract: contract,
            manifest: manifest,
            snapshot: stagedSnapshot,
            generationIdentifier: generationIdentifier,
            activatedAt: activatedAt,
            sourceEvidence: validatedSourceEvidence
        )
        let stagedReceiptURL = paths.receiptURL(in: stagingURL)
        try writeJSONAtomically(receipt, to: stagedReceiptURL, operation: "receipt write")

        // Recheck the exact installed layout after adding the receipt. Nothing is active yet.
        _ = try validator.validateInstalledModelAssets(manifest: manifest, rootURL: stagingURL)
        let decodedReceipt: StemModelInstallationReceipt = try readJSONRegularFile(
            StemModelInstallationReceipt.self,
            at: stagedReceiptURL,
            missingError: .receiptMissing(path: stagedReceiptURL.path),
            unreadable: { .receiptUnreadable(path: stagedReceiptURL.path, reason: $0) }
        )
        try validateReceipt(decodedReceipt, manifest: manifest, generationIdentifier: generationIdentifier)

        try ensureDirectory(paths.versionsRootURL)
        let assetSetDirectory = paths.assetSetDirectoryURL(assetSetIdentifier: manifest.assetSetIdentifier)
        try ensureDirectory(assetSetDirectory)
        let generationURL = paths.generationDirectoryURL(
            assetSetIdentifier: manifest.assetSetIdentifier,
            generationIdentifier: generationIdentifier
        )
        guard !pathExistsIncludingSymbolicLink(generationURL) else {
            throw StemModelInstallationStoreError.generationAlreadyExists(path: generationURL.path)
        }
        try requireSameVolume(stagingURL, assetSetDirectory)

        do {
            try fileManager.moveItem(at: stagingURL, to: generationURL)
        } catch {
            throw StemModelInstallationStoreError.fileOperationFailed(
                operation: "validated generation move",
                path: generationURL.path,
                reason: error.localizedDescription
            )
        }

        // The old active pointer is left untouched until the complete generation is in place.
        let pointer = StemModelActivePointer(
            schemaVersion: StemModelActivePointer.currentSchemaVersion,
            assetSetIdentifier: manifest.assetSetIdentifier,
            generationIdentifier: generationIdentifier
        )
        // Validate the generation in its final location before switching the active pointer.
        // After the pointer is replaced, activation must not fail while re-reading the new files;
        // otherwise callers could receive an error even though the active generation changed.
        let installation = try loadInstallation(
            pointer: pointer,
            manifest: manifest,
            generationURL: generationURL
        )
        try replaceActivePointerAtomically(pointer)
        return installation
    }

    func loadActive(manifest: StemModelManifest) throws -> ValidatedStemModelInstallation? {
        _ = try validator.validateManifest(manifest)
        guard pathExistsIncludingSymbolicLink(paths.activePointerURL) else { return nil }
        try ensureDirectory(paths.rootURL)
        try requireNoSymbolicLinks(from: paths.rootURL, through: paths.activePointerURL)

        let pointer: StemModelActivePointer = try readJSONRegularFile(
            StemModelActivePointer.self,
            at: paths.activePointerURL,
            missingError: .activePointerUnreadable(path: paths.activePointerURL.path, reason: "missing"),
            unreadable: { .activePointerUnreadable(path: paths.activePointerURL.path, reason: $0) }
        )
        try validatePointer(pointer, manifest: manifest)
        let generationURL = paths.generationDirectoryURL(
            assetSetIdentifier: pointer.assetSetIdentifier,
            generationIdentifier: pointer.generationIdentifier
        )
        try requireNoSymbolicLinks(from: paths.rootURL, through: generationURL)
        return try loadInstallation(pointer: pointer, manifest: manifest, generationURL: generationURL)
    }

    private func loadInstallation(
        pointer: StemModelActivePointer,
        manifest: StemModelManifest,
        generationURL: URL
    ) throws -> ValidatedStemModelInstallation {
        let receiptURL = paths.receiptURL(in: generationURL)
        let snapshot = try validator.validateInstalledModelAssets(
            manifest: manifest,
            rootURL: generationURL
        )
        let receipt: StemModelInstallationReceipt = try readJSONRegularFile(
            StemModelInstallationReceipt.self,
            at: receiptURL,
            missingError: .receiptMissing(path: receiptURL.path),
            unreadable: { .receiptUnreadable(path: receiptURL.path, reason: $0) }
        )
        try validateReceipt(
            receipt,
            manifest: manifest,
            generationIdentifier: pointer.generationIdentifier
        )
        return ValidatedStemModelInstallation(
            snapshot: snapshot,
            receipt: receipt,
            generationDirectoryURL: generationURL
        )
    }

    private func makeReceipt(
        contract: StemModelContract,
        manifest: StemModelManifest,
        snapshot: ValidatedStemModelSnapshot,
        generationIdentifier: UUID,
        activatedAt: Date,
        sourceEvidence: [StemModelInstallationSourceEvidence]
    ) -> StemModelInstallationReceipt {
        let assetsByKind = Dictionary(uniqueKeysWithValues: snapshot.assets.map { ($0.kind, $0) })
        let assets = manifest.downloadableModelAssets
            .sorted(by: { $0.kind.rawValue < $1.kind.rawValue })
            .compactMap { definition -> StemModelInstallationReceiptAsset? in
                guard let validated = assetsByKind[definition.kind] else { return nil }
                return StemModelInstallationReceiptAsset(
                    kind: definition.kind,
                    installationRelativePath: definition.installationRelativePath,
                    byteCount: validated.byteCount,
                    sha256: validated.sha256
                )
            }
        return StemModelInstallationReceipt(
            schemaVersion: StemModelInstallationReceipt.currentSchemaVersion,
            assetSetIdentifier: manifest.assetSetIdentifier,
            modelIdentifier: contract.identifier,
            revision: manifest.model.revision,
            generationIdentifier: generationIdentifier,
            activatedAt: activatedAt,
            assets: assets,
            sourceEvidence: sourceEvidence
        )
    }

    private func validatePointer(
        _ pointer: StemModelActivePointer,
        manifest: StemModelManifest
    ) throws {
        try requirePointerEqual(
            field: "schemaVersion",
            expected: StemModelActivePointer.currentSchemaVersion,
            actual: pointer.schemaVersion
        )
        try requirePointerEqual(
            field: "assetSetIdentifier",
            expected: manifest.assetSetIdentifier,
            actual: pointer.assetSetIdentifier
        )
    }

    private func validateReceipt(
        _ receipt: StemModelInstallationReceipt,
        manifest: StemModelManifest,
        generationIdentifier: UUID
    ) throws {
        try requireReceiptEqual(
            field: "schemaVersion",
            expected: StemModelInstallationReceipt.currentSchemaVersion,
            actual: receipt.schemaVersion
        )
        try requireReceiptEqual(
            field: "assetSetIdentifier",
            expected: manifest.assetSetIdentifier,
            actual: receipt.assetSetIdentifier
        )
        try requireReceiptEqual(
            field: "modelIdentifier",
            expected: StemModelAssetValidator.modelIdentifier,
            actual: receipt.modelIdentifier
        )
        try requireReceiptEqual(
            field: "revision",
            expected: manifest.model.revision,
            actual: receipt.revision
        )
        try requireReceiptEqual(
            field: "generationIdentifier",
            expected: generationIdentifier,
            actual: receipt.generationIdentifier
        )

        let expectedAssets = manifest.downloadableModelAssets
            .sorted(by: { $0.kind.rawValue < $1.kind.rawValue })
            .map {
                StemModelInstallationReceiptAsset(
                    kind: $0.kind,
                    installationRelativePath: $0.installationRelativePath,
                    byteCount: $0.byteCount,
                    sha256: $0.sha256
                )
            }
        try requireReceiptEqual(field: "assets", expected: expectedAssets, actual: receipt.assets)
        _ = try validateSourceEvidence(receipt.sourceEvidence, manifest: manifest)
    }

    private func validateSourceEvidence(
        _ sourceEvidence: [StemModelInstallationSourceEvidence],
        manifest: StemModelManifest
    ) throws -> [StemModelInstallationSourceEvidence] {
        let expectedAssetsByKind = Dictionary(
            uniqueKeysWithValues: manifest.downloadableModelAssets.map { ($0.kind, $0) }
        )
        var seenKinds: Set<StemModelAssetKind> = []

        for evidence in sourceEvidence {
            guard let expectedAsset = expectedAssetsByKind[evidence.kind] else {
                throw StemModelInstallationStoreError.sourceEvidenceUnexpectedKind(
                    kind: evidence.kind
                )
            }
            guard seenKinds.insert(evidence.kind).inserted else {
                throw StemModelInstallationStoreError.sourceEvidenceDuplicate(
                    kind: evidence.kind
                )
            }
            guard evidence.stableDownloadURL == expectedAsset.downloadURL else {
                throw StemModelInstallationStoreError.sourceEvidenceStableURLMismatch(
                    kind: evidence.kind,
                    expected: expectedAsset.downloadURL
                )
            }
            guard evidence.responseHeaderName
                == manifest.downloadPolicy.revisionResponseHeader else {
                throw StemModelInstallationStoreError.sourceEvidenceHeaderMismatch(
                    kind: evidence.kind,
                    expected: manifest.downloadPolicy.revisionResponseHeader,
                    actual: evidence.responseHeaderName
                )
            }
            guard evidence.revision == manifest.model.revision else {
                throw StemModelInstallationStoreError.sourceEvidenceRevisionMismatch(
                    kind: evidence.kind,
                    expected: manifest.model.revision,
                    actual: evidence.revision
                )
            }
        }

        for expectedKind in expectedAssetsByKind.keys
            .sorted(by: { $0.rawValue < $1.rawValue }) where !seenKinds.contains(expectedKind) {
            throw StemModelInstallationStoreError.sourceEvidenceMissing(kind: expectedKind)
        }

        return sourceEvidence.sorted(by: { $0.kind.rawValue < $1.kind.rawValue })
    }

    private func replaceActivePointerAtomically(_ pointer: StemModelActivePointer) throws {
        try ensureDirectory(paths.rootURL)
        let temporaryURL = paths.rootURL.appending(
            path: ".active-\(UUID().uuidString.lowercased()).tmp",
            directoryHint: .notDirectory
        )
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try writeJSONAtomically(pointer, to: temporaryURL, operation: "active pointer staging")

        do {
            if pathExistsIncludingSymbolicLink(paths.activePointerURL) {
                try requireRegularFileWithoutSymbolicLink(paths.activePointerURL, activePointer: true)
            }
            // POSIX rename is one same-volume operation: on failure an existing pointer is unchanged.
            guard Darwin.rename(temporaryURL.path, paths.activePointerURL.path) == 0 else {
                throw StemModelInstallationStoreError.fileOperationFailed(
                    operation: "active pointer replacement",
                    path: paths.activePointerURL.path,
                    reason: posixReason()
                )
            }
        } catch let error as StemModelInstallationStoreError {
            throw error
        } catch {
            throw StemModelInstallationStoreError.fileOperationFailed(
                operation: "active pointer replacement",
                path: paths.activePointerURL.path,
                reason: error.localizedDescription
            )
        }
    }

    private func writeJSONAtomically<Value: Encodable>(
        _ value: Value,
        to url: URL,
        operation: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
            try requireRegularFileWithoutSymbolicLink(url, activePointer: false)
        } catch let error as StemModelInstallationStoreError {
            throw error
        } catch {
            throw StemModelInstallationStoreError.fileOperationFailed(
                operation: operation,
                path: url.path,
                reason: error.localizedDescription
            )
        }
    }

    private func readJSONRegularFile<Value: Decodable>(
        _ type: Value.Type,
        at url: URL,
        missingError: StemModelInstallationStoreError,
        unreadable: (String) -> StemModelInstallationStoreError
    ) throws -> Value {
        guard pathExistsIncludingSymbolicLink(url) else { throw missingError }
        try requireRegularFileWithoutSymbolicLink(url, activePointer: url == paths.activePointerURL)

        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw unreadable(posixReason()) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            let data = try handle.readToEnd() ?? Data()
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch {
            throw unreadable(error.localizedDescription)
        }
    }

    private func ensureDirectory(_ url: URL) throws {
        if pathExistsIncludingSymbolicLink(url) {
            try requireDirectory(url)
            return
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            try requireDirectory(url)
        } catch let error as StemModelInstallationStoreError {
            throw error
        } catch {
            throw StemModelInstallationStoreError.fileOperationFailed(
                operation: "directory creation",
                path: url.path,
                reason: error.localizedDescription
            )
        }
    }

    private func requireDirectory(_ url: URL) throws {
        var fileStat = stat()
        guard Darwin.lstat(url.path, &fileStat) == 0 else {
            throw StemModelInstallationStoreError.storePathNotDirectory(path: url.path)
        }
        if (fileStat.st_mode & S_IFMT) == S_IFLNK {
            throw StemModelInstallationStoreError.storePathSymbolicLink(path: url.path)
        }
        guard (fileStat.st_mode & S_IFMT) == S_IFDIR else {
            throw StemModelInstallationStoreError.storePathNotDirectory(path: url.path)
        }
    }

    private func requireRegularFileWithoutSymbolicLink(_ url: URL, activePointer: Bool) throws {
        var fileStat = stat()
        guard Darwin.lstat(url.path, &fileStat) == 0 else {
            if activePointer {
                throw StemModelInstallationStoreError.activePointerNotRegularFile(path: url.path)
            }
            throw StemModelInstallationStoreError.receiptMissing(path: url.path)
        }
        if (fileStat.st_mode & S_IFMT) == S_IFLNK {
            throw StemModelInstallationStoreError.storePathSymbolicLink(path: url.path)
        }
        guard (fileStat.st_mode & S_IFMT) == S_IFREG else {
            if activePointer {
                throw StemModelInstallationStoreError.activePointerNotRegularFile(path: url.path)
            }
            throw StemModelInstallationStoreError.receiptUnreadable(
                path: url.path,
                reason: "not a regular file"
            )
        }
    }

    private func requireNoSymbolicLinks(from rootURL: URL, through descendantURL: URL) throws {
        let root = rootURL.standardizedFileURL
        let descendant = descendantURL.standardizedFileURL
        guard descendant == root || descendant.path.hasPrefix(root.path + "/") else {
            throw StemModelInstallationStoreError.storePathNotDirectory(path: descendant.path)
        }

        if pathExistsIncludingSymbolicLink(root) { try requireDirectory(root) }
        guard descendant != root else { return }
        let relative = String(descendant.path.dropFirst(root.path.count + 1))
        var current = root
        for component in relative.split(separator: "/") {
            current.append(path: String(component))
            guard pathExistsIncludingSymbolicLink(current) else { continue }
            var fileStat = stat()
            guard Darwin.lstat(current.path, &fileStat) == 0 else { continue }
            if (fileStat.st_mode & S_IFMT) == S_IFLNK {
                throw StemModelInstallationStoreError.storePathSymbolicLink(path: current.path)
            }
        }
    }

    private func requireSameVolume(_ firstURL: URL, _ secondURL: URL) throws {
        do {
            let first = try firstURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            let second = try secondURL.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            guard let firstHashable = first as? AnyHashable,
                  let secondHashable = second as? AnyHashable,
                  firstHashable == secondHashable else {
                throw StemModelInstallationStoreError.crossVolumeActivation(
                    stagingPath: firstURL.path,
                    versionsPath: secondURL.path
                )
            }
        } catch let error as StemModelInstallationStoreError {
            throw error
        } catch {
            throw StemModelInstallationStoreError.fileOperationFailed(
                operation: "volume validation",
                path: firstURL.path,
                reason: error.localizedDescription
            )
        }
    }

    private func pathExistsIncludingSymbolicLink(_ url: URL) -> Bool {
        var fileStat = stat()
        return Darwin.lstat(url.path, &fileStat) == 0
    }

    private func requirePointerEqual<Value: Equatable>(field: String, expected: Value, actual: Value) throws {
        guard expected == actual else {
            throw StemModelInstallationStoreError.activePointerMismatch(
                field: field,
                expected: String(describing: expected),
                actual: String(describing: actual)
            )
        }
    }

    private func requireReceiptEqual<Value: Equatable>(field: String, expected: Value, actual: Value) throws {
        guard expected == actual else {
            throw StemModelInstallationStoreError.receiptMismatch(
                field: field,
                expected: String(describing: expected),
                actual: String(describing: actual)
            )
        }
    }

    private func posixReason() -> String {
        String(cString: strerror(errno))
    }
}
