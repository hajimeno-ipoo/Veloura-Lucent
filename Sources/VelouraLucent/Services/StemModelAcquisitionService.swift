import Foundation

enum StemModelAcquisitionPurpose: String, CaseIterable, Equatable, Sendable {
    case initialInstall
    case repair
    case redownload
}

/// A non-persistable, one-operation capability created only after the user accepts the
/// model-download confirmation UI. Copies remain bound to the same operation and are
/// rejected after the first acquisition attempt.
struct StemModelAcquisitionAuthorization: Sendable {
    let operationIdentifier: UUID
    let assetSetIdentifier: String
    let purpose: StemModelAcquisitionPurpose

    fileprivate let authorizationIdentifier: UUID
    fileprivate let issuerIdentifier: UUID
    fileprivate let manifestSnapshot: StemModelManifest

    private init(
        operationIdentifier: UUID,
        assetSetIdentifier: String,
        purpose: StemModelAcquisitionPurpose,
        authorizationIdentifier: UUID,
        issuerIdentifier: UUID,
        manifestSnapshot: StemModelManifest
    ) {
        self.operationIdentifier = operationIdentifier
        self.assetSetIdentifier = assetSetIdentifier
        self.purpose = purpose
        self.authorizationIdentifier = authorizationIdentifier
        self.issuerIdentifier = issuerIdentifier
        self.manifestSnapshot = manifestSnapshot
    }

    fileprivate static func confirmedByUser(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose,
        issuerIdentifier: UUID
    ) -> StemModelAcquisitionAuthorization {
        StemModelAcquisitionAuthorization(
            operationIdentifier: UUID(),
            assetSetIdentifier: manifest.assetSetIdentifier,
            purpose: purpose,
            authorizationIdentifier: UUID(),
            issuerIdentifier: issuerIdentifier,
            manifestSnapshot: manifest
        )
    }
}

struct StemModelAcquisitionProgress: Equatable, Sendable {
    enum Phase: String, Equatable, Sendable {
        case preparing
        case downloading
        case validating
        case activating
        case completed
    }

    let operationIdentifier: UUID
    let purpose: StemModelAcquisitionPurpose
    let phase: Phase
    let assetKind: StemModelAssetKind?
    let receivedBytes: Int64
    let totalBytes: Int64
    let isWaitingForConnectivity: Bool

    init(
        operationIdentifier: UUID,
        purpose: StemModelAcquisitionPurpose,
        phase: Phase = .downloading,
        assetKind: StemModelAssetKind?,
        receivedBytes: Int64,
        totalBytes: Int64,
        isWaitingForConnectivity: Bool
    ) {
        self.operationIdentifier = operationIdentifier
        self.purpose = purpose
        self.phase = phase
        self.assetKind = assetKind
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
        self.isWaitingForConnectivity = isWaitingForConnectivity
    }
}

enum StemModelAcquisitionError: Error, Equatable, LocalizedError, Sendable {
    case authorizationIssuerMismatch
    case authorizationAlreadyUsed(operationIdentifier: UUID)
    case authorizationAssetSetMismatch(expected: String, actual: String)
    case authorizationPurposeMismatch(
        expected: StemModelAcquisitionPurpose,
        actual: StemModelAcquisitionPurpose
    )
    case authorizationManifestMismatch(assetSetIdentifier: String)
    case manifestDoesNotRequireExplicitConfirmation
    case invalidDownloadableAssetSet
    case invalidDownloadByteTotal
    case operationAlreadyInProgress(activeOperationIdentifier: UUID)
    case operationNotActive(requested: UUID, active: UUID?)
    case operationCannotBeCancelledDuringActivation(UUID)
    case stagedAssetURLMismatch(kind: StemModelAssetKind, expected: String, actual: String)
    case revisionEvidenceMismatch(
        kind: StemModelAssetKind,
        expectedHeader: String,
        actualHeader: String,
        expectedRevision: String,
        actualRevision: String
    )
    case cancelled(operationIdentifier: UUID)
    case stagingCleanupFailed(
        operationIdentifier: UUID,
        originalFailure: String,
        cleanupFailure: String
    )

    var errorDescription: String? {
        switch self {
        case .authorizationIssuerMismatch:
            return "Stem Modeの取得確認が別の取得サービスから発行されています。"
        case .authorizationAlreadyUsed(let operationIdentifier):
            return "Stem Modeのモデル取得確認は既に使用済みです: \(operationIdentifier)"
        case .authorizationAssetSetMismatch(let expected, let actual):
            return "Stem Modeの取得確認とモデル一式が一致しません（期待: \(expected)、実際: \(actual)）。"
        case .authorizationPurposeMismatch(let expected, let actual):
            return "Stem Modeの取得確認目的が一致しません（期待: \(expected.rawValue)、実際: \(actual.rawValue)）。"
        case .authorizationManifestMismatch(let assetSetIdentifier):
            return "Stem Modeの取得確認後にmanifestが変更されました: \(assetSetIdentifier)"
        case .manifestDoesNotRequireExplicitConfirmation:
            return "Stem Modeのmanifestに明示確認必須の取得方針がありません。"
        case .invalidDownloadableAssetSet:
            return "Stem Modeの取得対象はweightsとconfigの2資産でなければなりません。"
        case .invalidDownloadByteTotal:
            return "Stem Modeの取得容量を安全に集計できません。"
        case .operationAlreadyInProgress(let activeOperationIdentifier):
            return "別のStem Modeモデル取得が進行中です: \(activeOperationIdentifier)"
        case .operationNotActive(let requested, let active):
            return "Stem Modeの取得操作が進行中ではありません（要求: \(requested)、進行中: \(active?.uuidString ?? "なし")）。"
        case .operationCannotBeCancelledDuringActivation(let operationIdentifier):
            return "Stem Modeのモデルを原子的に有効化しているため、この時点では中断できません: \(operationIdentifier)"
        case .stagedAssetURLMismatch(let kind, let expected, let actual):
            return "Stem Modeの取得済み資産パスが一致しません: \(kind.rawValue)（期待: \(expected)、実際: \(actual)）"
        case .revisionEvidenceMismatch(
            let kind,
            let expectedHeader,
            let actualHeader,
            let expectedRevision,
            let actualRevision
        ):
            return "Stem ModeのRevision証拠が一致しません: \(kind.rawValue)（header: \(expectedHeader)/\(actualHeader)、revision: \(expectedRevision)/\(actualRevision)）"
        case .cancelled(let operationIdentifier):
            return "Stem Modeのモデル取得を中断しました: \(operationIdentifier)"
        case .stagingCleanupFailed(
            let operationIdentifier,
            let originalFailure,
            let cleanupFailure
        ):
            return "Stem Modeの取得失敗後に一時資産を削除できませんでした: \(operationIdentifier)（元の失敗: \(originalFailure)、削除失敗: \(cleanupFailure)）"
        }
    }
}

protocol StemModelAcquisitionValidating: Sendable {
    func validateManifest(_ manifest: StemModelManifest) throws -> StemModelContract
}

extension StemModelAssetValidator: StemModelAcquisitionValidating {}

protocol StemModelAcquisitionStoring: Sendable {
    func makeStagingDirectory(operationIdentifier: UUID) async throws -> URL

    func discardStagingDirectory(operationIdentifier: UUID) async throws

    func activate(
        operationIdentifier: UUID,
        generationIdentifier: UUID,
        manifest: StemModelManifest,
        sourceEvidence: [StemModelInstallationSourceEvidence],
        activatedAt: Date
    ) async throws -> ValidatedStemModelInstallation
}

extension StemModelInstallationStore: StemModelAcquisitionStoring {}

actor StemModelAcquisitionService {
    private enum OperationPhase: Sendable {
        case preparing
        case downloading
        case validating
        case activating
    }

    private struct ActiveOperation: Sendable {
        let operationIdentifier: UUID
        var phase: OperationPhase
        var currentDownloadIdentifier: UUID?
        var cancellationRequested: Bool
    }

    private let downloader: any StemModelDownloading
    private let validator: any StemModelAcquisitionValidating
    private let store: any StemModelAcquisitionStoring
    private nonisolated let authorizationIssuerIdentifier: UUID

    private var consumedAuthorizationIdentifiers: Set<UUID> = []
    private var activeOperation: ActiveOperation?

    init(
        downloader: any StemModelDownloading = StemModelDownloadClient(),
        validator: any StemModelAcquisitionValidating = StemModelAssetValidator(selectedModel: nil),
        store: any StemModelAcquisitionStoring = StemModelInstallationStore()
    ) {
        self.downloader = downloader
        self.validator = validator
        self.store = store
        self.authorizationIssuerIdentifier = UUID()
    }

    /// This synchronous, local-only method must be called directly from the affirmative
    /// action of the model-download confirmation UI. It performs no validation or network I/O.
    nonisolated func issueOneTimeAuthorizationAfterExplicitUserConfirmation(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose
    ) -> StemModelAcquisitionAuthorization {
        .confirmedByUser(
            manifest: manifest,
            purpose: purpose,
            issuerIdentifier: authorizationIssuerIdentifier
        )
    }

    func acquireModels(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose,
        authorization: StemModelAcquisitionAuthorization,
        progressHandler: @escaping @Sendable (StemModelAcquisitionProgress) -> Void
    ) async throws -> ValidatedStemModelInstallation {
        try consumeAndValidate(
            authorization: authorization,
            manifest: manifest,
            purpose: purpose
        )

        if let activeOperation {
            throw StemModelAcquisitionError.operationAlreadyInProgress(
                activeOperationIdentifier: activeOperation.operationIdentifier
            )
        }

        _ = try validator.validateManifest(manifest)
        guard manifest.downloadPolicy.requiresExplicitUserConfirmation else {
            throw StemModelAcquisitionError.manifestDoesNotRequireExplicitConfirmation
        }
        let assets = try orderedDownloadableAssets(in: manifest)
        let totalBytes = try totalByteCount(of: assets)
        let operationIdentifier = authorization.operationIdentifier
        activeOperation = ActiveOperation(
            operationIdentifier: operationIdentifier,
            phase: .preparing,
            currentDownloadIdentifier: nil,
            cancellationRequested: false
        )

        do {
            let stagingDirectoryURL = try await store.makeStagingDirectory(
                operationIdentifier: operationIdentifier
            )
            try requireOperationCanContinue(operationIdentifier)

            var completedBytes: Int64 = 0
            var sourceEvidence: [StemModelInstallationSourceEvidence] = []
            progressHandler(
                Self.progress(
                    operationIdentifier: operationIdentifier,
                    purpose: purpose,
                    phase: .preparing,
                    assetKind: assets.first?.kind,
                    receivedBytes: 0,
                    totalBytes: totalBytes,
                    isWaitingForConnectivity: false
                )
            )

            for asset in assets {
                try requireOperationCanContinue(operationIdentifier)
                let downloadIdentifier = UUID()
                setDownload(
                    downloadIdentifier,
                    operationIdentifier: operationIdentifier
                )
                let completedBeforeAsset = completedBytes
                let result: StemModelDownloadResult
                do {
                    result = try await downloader.download(
                        downloadIdentifier: downloadIdentifier,
                        asset: asset,
                        modelRevision: manifest.model.revision,
                        policy: manifest.downloadPolicy,
                        stagingDirectoryURL: stagingDirectoryURL
                    ) { event in
                        switch event {
                        case .waitingForConnectivity:
                            progressHandler(
                                Self.progress(
                                    operationIdentifier: operationIdentifier,
                                    purpose: purpose,
                                    assetKind: asset.kind,
                                    receivedBytes: completedBeforeAsset,
                                    totalBytes: totalBytes,
                                    isWaitingForConnectivity: true
                                )
                            )
                        case .progress(let receivedBytes, _):
                            progressHandler(
                                Self.progress(
                                    operationIdentifier: operationIdentifier,
                                    purpose: purpose,
                                    assetKind: asset.kind,
                                    receivedBytes: Self.saturatingAdd(
                                        completedBeforeAsset,
                                        max(receivedBytes, 0)
                                    ),
                                    totalBytes: totalBytes,
                                    isWaitingForConnectivity: false
                                )
                            )
                        }
                    }
                } catch {
                    clearDownload(
                        downloadIdentifier,
                        operationIdentifier: operationIdentifier
                    )
                    throw error
                }
                clearDownload(
                    downloadIdentifier,
                    operationIdentifier: operationIdentifier
                )
                try requireOperationCanContinue(operationIdentifier)
                try validateDownloadResult(
                    result,
                    asset: asset,
                    manifest: manifest,
                    stagingDirectoryURL: stagingDirectoryURL
                )
                sourceEvidence.append(
                    StemModelInstallationSourceEvidence(
                        kind: asset.kind,
                        stableDownloadURL: asset.downloadURL,
                        responseHeaderName: result.sourceRevisionEvidence.responseHeaderName,
                        revision: result.sourceRevisionEvidence.revision
                    )
                )
                completedBytes = try addingByteCount(completedBytes, asset.byteCount)
                progressHandler(
                    Self.progress(
                        operationIdentifier: operationIdentifier,
                        purpose: purpose,
                        assetKind: asset.kind,
                        receivedBytes: completedBytes,
                        totalBytes: totalBytes,
                        isWaitingForConnectivity: false
                    )
                )
            }

            setPhase(.validating, operationIdentifier: operationIdentifier)
            try requireOperationCanContinue(operationIdentifier)
            progressHandler(
                Self.progress(
                    operationIdentifier: operationIdentifier,
                    purpose: purpose,
                    phase: .validating,
                    assetKind: nil,
                    receivedBytes: completedBytes,
                    totalBytes: totalBytes,
                    isWaitingForConnectivity: false
                )
            )
            try requireOperationCanContinue(operationIdentifier)

            // The store performs the single full asset validation immediately before
            // activation. Once entered, cancellation is refused rather than reporting
            // cancellation after the active pointer changed.
            setPhase(.activating, operationIdentifier: operationIdentifier)
            let installation = try await store.activate(
                operationIdentifier: operationIdentifier,
                generationIdentifier: UUID(),
                manifest: manifest,
                sourceEvidence: sourceEvidence,
                activatedAt: Date()
            )
            finishOperation(operationIdentifier)
            progressHandler(
                Self.progress(
                    operationIdentifier: operationIdentifier,
                    purpose: purpose,
                    phase: .completed,
                    assetKind: nil,
                    receivedBytes: totalBytes,
                    totalBytes: totalBytes,
                    isWaitingForConnectivity: false
                )
            )
            return installation
        } catch {
            let shouldReportCancellation = isCancellation(
                error,
                operationIdentifier: operationIdentifier
            )
            do {
                try await store.discardStagingDirectory(
                    operationIdentifier: operationIdentifier
                )
            } catch let cleanupError {
                finishOperation(operationIdentifier)
                throw StemModelAcquisitionError.stagingCleanupFailed(
                    operationIdentifier: operationIdentifier,
                    originalFailure: error.localizedDescription,
                    cleanupFailure: cleanupError.localizedDescription
                )
            }
            finishOperation(operationIdentifier)
            if shouldReportCancellation {
                throw StemModelAcquisitionError.cancelled(
                    operationIdentifier: operationIdentifier
                )
            }
            throw error
        }
    }

    func cancelAcquisition(operationIdentifier: UUID) async throws {
        guard var operation = activeOperation,
              operation.operationIdentifier == operationIdentifier else {
            throw StemModelAcquisitionError.operationNotActive(
                requested: operationIdentifier,
                active: activeOperation?.operationIdentifier
            )
        }
        guard operation.phase != .activating else {
            throw StemModelAcquisitionError.operationCannotBeCancelledDuringActivation(
                operationIdentifier
            )
        }

        operation.cancellationRequested = true
        activeOperation = operation
        guard let downloadIdentifier = operation.currentDownloadIdentifier else { return }

        do {
            try await downloader.cancel(downloadIdentifier: downloadIdentifier)
        } catch StemModelDownloadError.downloadNotFound(_) {
            // Completion won the race. The cancellation flag is still observed before the
            // next asset, validation, or activation begins.
        }
    }

    private func consumeAndValidate(
        authorization: StemModelAcquisitionAuthorization,
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose
    ) throws {
        guard authorization.issuerIdentifier == authorizationIssuerIdentifier else {
            throw StemModelAcquisitionError.authorizationIssuerMismatch
        }
        guard !consumedAuthorizationIdentifiers.contains(
            authorization.authorizationIdentifier
        ) else {
            throw StemModelAcquisitionError.authorizationAlreadyUsed(
                operationIdentifier: authorization.operationIdentifier
            )
        }
        consumedAuthorizationIdentifiers.insert(
            authorization.authorizationIdentifier
        )

        guard authorization.assetSetIdentifier == manifest.assetSetIdentifier else {
            throw StemModelAcquisitionError.authorizationAssetSetMismatch(
                expected: authorization.assetSetIdentifier,
                actual: manifest.assetSetIdentifier
            )
        }
        guard authorization.purpose == purpose else {
            throw StemModelAcquisitionError.authorizationPurposeMismatch(
                expected: authorization.purpose,
                actual: purpose
            )
        }
        guard authorization.manifestSnapshot == manifest else {
            throw StemModelAcquisitionError.authorizationManifestMismatch(
                assetSetIdentifier: manifest.assetSetIdentifier
            )
        }
    }

    private func orderedDownloadableAssets(
        in manifest: StemModelManifest
    ) throws -> [StemDownloadableModelAsset] {
        var assetsByKind: [StemModelAssetKind: StemDownloadableModelAsset] = [:]
        for asset in manifest.downloadableModelAssets {
            guard assetsByKind[asset.kind] == nil else {
                throw StemModelAcquisitionError.invalidDownloadableAssetSet
            }
            assetsByKind[asset.kind] = asset
        }
        guard manifest.downloadableModelAssets.count == 2,
              assetsByKind.count == 2,
              let weights = assetsByKind[.modelWeights],
              let configuration = assetsByKind[.modelConfiguration] else {
            throw StemModelAcquisitionError.invalidDownloadableAssetSet
        }
        return [weights, configuration]
    }

    private func totalByteCount(
        of assets: [StemDownloadableModelAsset]
    ) throws -> Int64 {
        var total: Int64 = 0
        for asset in assets {
            guard asset.byteCount >= 0 else {
                throw StemModelAcquisitionError.invalidDownloadByteTotal
            }
            total = try addingByteCount(total, asset.byteCount)
        }
        return total
    }

    private func addingByteCount(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw StemModelAcquisitionError.invalidDownloadByteTotal
        }
        return value
    }

    private func validateDownloadResult(
        _ result: StemModelDownloadResult,
        asset: StemDownloadableModelAsset,
        manifest: StemModelManifest,
        stagingDirectoryURL: URL
    ) throws {
        let expectedURL = try StemModelAssetValidator.safeDescendantURL(
            rootURL: stagingDirectoryURL,
            relativePath: asset.installationRelativePath,
            field: "downloadableModelAssets.installationRelativePath"
        )
        guard result.stagedURL.standardizedFileURL == expectedURL.standardizedFileURL else {
            throw StemModelAcquisitionError.stagedAssetURLMismatch(
                kind: asset.kind,
                expected: expectedURL.path,
                actual: result.stagedURL.path
            )
        }

        let evidence = result.sourceRevisionEvidence
        let headerMatches = evidence.responseHeaderName.caseInsensitiveCompare(
            manifest.downloadPolicy.revisionResponseHeader
        ) == .orderedSame
        guard headerMatches, evidence.revision == manifest.model.revision else {
            throw StemModelAcquisitionError.revisionEvidenceMismatch(
                kind: asset.kind,
                expectedHeader: manifest.downloadPolicy.revisionResponseHeader,
                actualHeader: evidence.responseHeaderName,
                expectedRevision: manifest.model.revision,
                actualRevision: evidence.revision
            )
        }
    }

    private func requireOperationCanContinue(_ operationIdentifier: UUID) throws {
        guard let activeOperation,
              activeOperation.operationIdentifier == operationIdentifier else {
            throw StemModelAcquisitionError.operationNotActive(
                requested: operationIdentifier,
                active: activeOperation?.operationIdentifier
            )
        }
        if activeOperation.cancellationRequested || Task.isCancelled {
            throw StemModelAcquisitionError.cancelled(
                operationIdentifier: operationIdentifier
            )
        }
    }

    private func setDownload(
        _ downloadIdentifier: UUID,
        operationIdentifier: UUID
    ) {
        guard var operation = activeOperation,
              operation.operationIdentifier == operationIdentifier else { return }
        operation.phase = .downloading
        operation.currentDownloadIdentifier = downloadIdentifier
        activeOperation = operation
    }

    private func clearDownload(
        _ downloadIdentifier: UUID,
        operationIdentifier: UUID
    ) {
        guard var operation = activeOperation,
              operation.operationIdentifier == operationIdentifier,
              operation.currentDownloadIdentifier == downloadIdentifier else { return }
        operation.currentDownloadIdentifier = nil
        activeOperation = operation
    }

    private func setPhase(
        _ phase: OperationPhase,
        operationIdentifier: UUID
    ) {
        guard var operation = activeOperation,
              operation.operationIdentifier == operationIdentifier else { return }
        operation.phase = phase
        operation.currentDownloadIdentifier = nil
        activeOperation = operation
    }

    private func finishOperation(_ operationIdentifier: UUID) {
        guard activeOperation?.operationIdentifier == operationIdentifier else { return }
        activeOperation = nil
    }

    private func isCancellation(
        _ error: Error,
        operationIdentifier: UUID
    ) -> Bool {
        if Task.isCancelled { return true }
        if error is CancellationError { return true }
        if let error = error as? StemModelDownloadError, error == .cancelled {
            return true
        }
        if let error = error as? StemModelAcquisitionError,
           error == .cancelled(operationIdentifier: operationIdentifier) {
            return true
        }
        return activeOperation?.operationIdentifier == operationIdentifier
            && activeOperation?.cancellationRequested == true
    }

    private static func progress(
        operationIdentifier: UUID,
        purpose: StemModelAcquisitionPurpose,
        phase: StemModelAcquisitionProgress.Phase = .downloading,
        assetKind: StemModelAssetKind?,
        receivedBytes: Int64,
        totalBytes: Int64,
        isWaitingForConnectivity: Bool
    ) -> StemModelAcquisitionProgress {
        StemModelAcquisitionProgress(
            operationIdentifier: operationIdentifier,
            purpose: purpose,
            phase: phase,
            assetKind: assetKind,
            receivedBytes: receivedBytes,
            totalBytes: totalBytes,
            isWaitingForConnectivity: isWaitingForConnectivity
        )
    }

    private static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : value
    }
}
