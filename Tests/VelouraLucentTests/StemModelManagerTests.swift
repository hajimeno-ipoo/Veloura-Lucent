import Foundation
import Testing
@testable import VelouraLucent

private enum StemModelManagerFixtureError: Error, Equatable, Sendable {
    case acquisitionFailed
    case pendingAcquisitionMissing
}

private actor StemModelInspectorDouble: StemModelLocalInspecting {
    private let inspections: [StemModelLocalInspection]
    private var nextIndex = 0
    private var callCountStorage = 0

    init(inspections: [StemModelLocalInspection]) {
        precondition(!inspections.isEmpty)
        self.inspections = inspections
    }

    func inspect() async -> StemModelLocalInspection {
        callCountStorage += 1
        let index = min(nextIndex, inspections.index(before: inspections.endIndex))
        nextIndex += 1
        return inspections[index]
    }

    var callCount: Int {
        callCountStorage
    }
}

private final class StemModelAuthorizationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var countStorage = 0

    func increment() {
        lock.lock()
        countStorage += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return countStorage
    }
}

private actor StemModelAcquisitionControllerDouble: StemModelAcquisitionControlling {
    struct Call: Equatable, Sendable {
        let operationIdentifier: UUID
        let assetSetIdentifier: String
        let purpose: StemModelAcquisitionPurpose
    }

    private nonisolated let authorizationIssuer = StemModelAcquisitionService()
    private nonisolated let authorizationCounter = StemModelAuthorizationCounter()
    private let successfulInstallation: ValidatedStemModelInstallation
    private var callsStorage: [Call] = []
    private var cancellationIdentifiersStorage: [UUID] = []
    private var pending: [
        UUID: CheckedContinuation<ValidatedStemModelInstallation, any Error>
    ] = [:]

    init(successfulInstallation: ValidatedStemModelInstallation) {
        self.successfulInstallation = successfulInstallation
    }

    nonisolated func issueOneTimeAuthorizationAfterExplicitUserConfirmation(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose
    ) -> StemModelAcquisitionAuthorization {
        authorizationCounter.increment()
        return authorizationIssuer
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: manifest,
                purpose: purpose
            )
    }

    func acquireModels(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose,
        authorization: StemModelAcquisitionAuthorization,
        progressHandler: @escaping @Sendable (StemModelAcquisitionProgress) -> Void
    ) async throws -> ValidatedStemModelInstallation {
        callsStorage.append(
            Call(
                operationIdentifier: authorization.operationIdentifier,
                assetSetIdentifier: manifest.assetSetIdentifier,
                purpose: purpose
            )
        )
        progressHandler(
            StemModelAcquisitionProgress(
                operationIdentifier: authorization.operationIdentifier,
                purpose: purpose,
                assetKind: .modelWeights,
                receivedBytes: 42,
                totalBytes: manifest.downloadableModelAssets.reduce(0) {
                    $0 + $1.byteCount
                },
                isWaitingForConnectivity: true
            )
        )
        return try await withCheckedThrowingContinuation { continuation in
            pending[authorization.operationIdentifier] = continuation
        }
    }

    func cancelAcquisition(operationIdentifier: UUID) async throws {
        cancellationIdentifiersStorage.append(operationIdentifier)
        guard let continuation = pending.removeValue(forKey: operationIdentifier) else {
            throw StemModelManagerFixtureError.pendingAcquisitionMissing
        }
        continuation.resume(
            throwing: StemModelAcquisitionError.cancelled(
                operationIdentifier: operationIdentifier
            )
        )
    }

    nonisolated var authorizationIssueCount: Int {
        authorizationCounter.count
    }

    var calls: [Call] {
        callsStorage
    }

    var cancellationIdentifiers: [UUID] {
        cancellationIdentifiersStorage
    }

    var hasPendingAcquisition: Bool {
        !pending.isEmpty
    }

    func completeSuccessfully() throws {
        guard let identifier = pending.keys.first,
              let continuation = pending.removeValue(forKey: identifier) else {
            throw StemModelManagerFixtureError.pendingAcquisitionMissing
        }
        continuation.resume(returning: successfulInstallation)
    }

    func failAcquisition() throws {
        guard let identifier = pending.keys.first,
              let continuation = pending.removeValue(forKey: identifier) else {
            throw StemModelManagerFixtureError.pendingAcquisitionMissing
        }
        continuation.resume(throwing: StemModelManagerFixtureError.acquisitionFailed)
    }
}

@MainActor
struct StemModelManagerTests {
    @Test("起動確認と再検証はローカルinspectorだけを使う")
    func startupAndRevalidationRemainLocalOnly() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.missingInspection, fixture.invalidInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )

        await manager.inspectLocalResources()
        #expect(manager.localInspection == fixture.missingInspection)
        await manager.inspectLocalResources()

        #expect(manager.localInspection == fixture.invalidInspection)
        #expect(await inspector.callCount == 2)
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)
    }

    @Test("missing・invalid・readyは承認済みの取得操作だけを提示する")
    func recoveryActionsMatchInstalledModelState() throws {
        let fixture = try StemModelManagerFixture()

        #expect(fixture.missingInspection.recoveryActions == [
            .initialDownload, .revalidate,
        ])
        #expect(fixture.invalidInspection.recoveryActions == [
            .repair, .redownload, .revalidate,
        ])
        #expect(fixture.readyInspection.recoveryActions == [
            .redownload, .revalidate,
        ])
    }

    @Test("MLX実行資産が不正な場合はモデル取得を準備しない")
    func invalidBundledRuntimeNeverStartsModelDownload() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.runtimeInvalidInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )
        await manager.inspectLocalResources()

        #expect(manager.recoveryActions == [
            .revalidate,
        ])
        for purpose in StemModelAcquisitionPurpose.allCases {
            #expect(
                throws: StemModelManagerError.runtimeCannotBeRepairedByModelDownload
            ) {
                try manager.prepareAcquisitionConfirmation(purpose: purpose)
            }
        }
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)
    }

    @Test("確認表示後の再検証でMLX実行資産が不正になれば取得しない")
    func staleConfirmationCannotBypassRuntimeRevalidation() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.missingInspection, fixture.runtimeInvalidInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )
        await manager.inspectLocalResources()
        try manager.prepareAcquisitionConfirmation(purpose: .initialInstall)

        // The runtime can be revalidated while the confirmation is still visible.
        await manager.inspectLocalResources()
        var confirmationWasRejected = false
        do {
            try manager.confirmAcquisition()
        } catch StemModelManagerError.runtimeCannotBeRepairedByModelDownload,
                StemModelManagerError.noPendingConfirmation {
            confirmationWasRejected = true
        } catch {
            Issue.record("Unexpected stale-confirmation error: \(error)")
            confirmationWasRejected = true
        }

        // Clean up the deliberately failing implementation path without leaking
        // the fake controller's checked continuation.
        if !confirmationWasRejected {
            try await waitUntil { await controller.hasPendingAcquisition }
            manager.requestAcquisitionCancellation()
            try await waitUntil { manager.operationState == .idle }
        }

        #expect(confirmationWasRejected)
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)
    }

    @Test("取得準備は固定配布情報を示すだけで権限発行も通信も行わない")
    func preparationIsLocalAndUsesProductionSchemaTwoContract() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.missingInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )
        await manager.inspectLocalResources()

        try manager.prepareAcquisitionConfirmation(purpose: .initialInstall)
        let confirmation = try #require(manager.pendingConfirmation)

        #expect(manager.pendingDownloadConfirmation == confirmation)

        #expect(fixture.installation.receipt.schemaVersion == 2)
        #expect(fixture.installation.receipt.sourceEvidence.count == 2)
        #expect(confirmation.repository == fixture.manifest.model.repo)
        #expect(confirmation.revision == fixture.manifest.model.revision)
        #expect(confirmation.license == fixture.manifest.model.licenseMetadata)
        #expect(confirmation.assets.count == 2)
        #expect(
            confirmation.totalByteCount
                == fixture.manifest.downloadableModelAssets.reduce(0) {
                    $0 + $1.byteCount
                }
        )
        #expect(
            Set(confirmation.assets.map(\.stableDownloadURL))
                == Set(fixture.installation.receipt.sourceEvidence.map(\.stableDownloadURL))
        )
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)

        manager.cancelPendingConfirmation()
        #expect(manager.operationState == .idle)
        #expect(manager.pendingDownloadConfirmation == nil)
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)
    }

    @Test("肯定操作だけが一回限りの権限を発行し進捗後に再検証する")
    func affirmativeConfirmationIssuesAuthorizationAndSuccessReinspects() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.missingInspection, fixture.readyInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )
        await manager.inspectLocalResources()
        try manager.prepareAcquisitionConfirmation(purpose: .initialInstall)

        try manager.confirmAcquisition()
        #expect(controller.authorizationIssueCount == 1)
        #expect(manager.pendingDownloadConfirmation == nil)
        #expect(throws: StemModelManagerError.noPendingConfirmation) {
            try manager.confirmAcquisition()
        }
        #expect(controller.authorizationIssueCount == 1)

        try await waitUntil { await controller.hasPendingAcquisition }
        try await waitUntil {
            guard case .acquiring(let progress) = manager.operationState else {
                return false
            }
            return progress.receivedBytes == 42 && progress.isWaitingForConnectivity
        }
        try await controller.completeSuccessfully()
        try await waitUntil { manager.operationState == .idle }

        #expect(await inspector.callCount == 2)
        #expect(manager.localInspection == fixture.readyInspection)
        #expect(manager.isReadyForStemProcessing)
        #expect(await controller.calls.count == 1)
    }

    @Test("取得後モデルがreadyでなければ局所エラーとして保持する")
    func successThatDoesNotValidateBecomesLocalFailure() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.missingInspection, fixture.invalidInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )
        await manager.inspectLocalResources()
        try manager.prepareAcquisitionConfirmation(purpose: .initialInstall)
        try manager.confirmAcquisition()
        try await waitUntil { await controller.hasPendingAcquisition }
        try await controller.completeSuccessfully()
        try await waitUntil { manager.isFailureState }

        #expect(await inspector.callCount == 2)
        #expect(manager.localInspection == fixture.invalidInspection)
        #expect(!manager.isReadyForStemProcessing)
    }

    @Test("取得失敗後もローカル資産を再検証して通常モードを阻害しない")
    func acquisitionFailureReinspectsWithoutGlobalFailure() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.missingInspection, fixture.missingInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )
        await manager.inspectLocalResources()
        try manager.prepareAcquisitionConfirmation(purpose: .initialInstall)
        try manager.confirmAcquisition()
        try await waitUntil { await controller.hasPendingAcquisition }
        try await controller.failAcquisition()
        try await waitUntil { manager.isFailureState }

        #expect(await inspector.callCount == 2)
        #expect(manager.localInspection == fixture.missingInspection)
        #expect(manager.recoveryActions == [.initialDownload, .revalidate])
        #expect(!manager.isReadyForStemProcessing)
    }

    @Test("取得中断後もローカル資産を再検証し取得状態を終了する")
    func cancellationReinspectsAndReturnsToIdle() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.invalidInspection, fixture.invalidInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )
        await manager.inspectLocalResources()
        try manager.prepareAcquisitionConfirmation(purpose: .repair)
        try manager.confirmAcquisition()
        try await waitUntil { await controller.hasPendingAcquisition }

        let operationIdentifier = try #require(manager.currentAcquisitionIdentifier)
        manager.requestAcquisitionCancellation()
        try await waitUntil { manager.operationState == .idle }

        #expect(await controller.cancellationIdentifiers == [operationIdentifier])
        #expect(await inspector.callCount == 2)
        #expect(manager.localInspection == fixture.invalidInspection)
        #expect(manager.recoveryActions == [.repair, .redownload, .revalidate])
    }

    @Test("manifest不正はStem内に閉じ再検証だけを提示する")
    func invalidManifestRemainsAStemLocalState() async throws {
        let fixture = try StemModelManagerFixture()
        let inspection = StemModelLocalInspection(
            platform: .supportedAppleSilicon,
            manifest: .invalid(message: "manifest fixture invalid"),
            installedModel: .notChecked,
            bundledRuntime: .notChecked
        )
        let inspector = StemModelInspectorDouble(inspections: [inspection])
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )

        await manager.inspectLocalResources()

        #expect(manager.operationState == .idle)
        #expect(manager.localInspection == inspection)
        #expect(manager.recoveryActions == [.revalidate])
        #expect(!manager.isReadyForStemProcessing)
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)
    }

    @Test("Apple Silicon以外ではモデル取得を提示せず再検証だけを残す")
    func unsupportedArchitectureDoesNotOfferModelAcquisition() async throws {
        let fixture = try StemModelManagerFixture()
        let inspection = StemModelLocalInspection(
            platform: .unsupported(processArchitecture: "x86_64"),
            manifest: .valid(fixture.manifest),
            installedModel: .notChecked,
            bundledRuntime: .notChecked
        )
        let inspector = StemModelInspectorDouble(inspections: [inspection])
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )

        await manager.inspectLocalResources()

        #expect(!manager.isReadyForStemProcessing)
        #expect(manager.recoveryActions == [.revalidate])
        #expect(throws: StemModelManagerError.unsupportedPlatform(processArchitecture: "x86_64")) {
            try manager.prepareAcquisitionConfirmation(purpose: .initialInstall)
        }
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)
    }
}

private struct StemModelManagerFixture {
    let manifest: StemModelManifest
    let installation: ValidatedStemModelInstallation
    let runtime: StemBundledRuntimeValidationReport

    init() throws {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let validator = StemModelAssetValidator()
        let manifest = try validator.loadManifest(
            at: repositoryRoot.appending(
                path: "Sources/VelouraLucent/Resources/StemModels/stem-model-manifest.json"
            )
        )
        let contract = try validator.validateManifest(manifest)
        let generationIdentifier = UUID()
        let generationDirectoryURL = FileManager.default.temporaryDirectory.appending(
            path: "StemModelManagerFixture-\(generationIdentifier.uuidString)",
            directoryHint: .isDirectory
        )
        let modelDirectoryURL = generationDirectoryURL.appending(
            path: "model",
            directoryHint: .isDirectory
        )
        let validatedModelAssets = manifest.downloadableModelAssets.map { asset in
            ValidatedStemModelAsset(
                kind: asset.kind,
                fileURL: generationDirectoryURL.appending(
                    path: asset.installationRelativePath
                ),
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
        let sourceEvidence = manifest.downloadableModelAssets.map { asset in
            StemModelInstallationSourceEvidence(
                kind: asset.kind,
                stableDownloadURL: asset.downloadURL,
                responseHeaderName: manifest.downloadPolicy.revisionResponseHeader,
                revision: manifest.model.revision
            )
        }
        let snapshot = ValidatedStemModelSnapshot(
            contract: contract,
            installationRootURL: generationDirectoryURL,
            modelDirectoryURL: modelDirectoryURL,
            assets: validatedModelAssets
        )
        installation = ValidatedStemModelInstallation(
            snapshot: snapshot,
            receipt: StemModelInstallationReceipt(
                schemaVersion: StemModelInstallationReceipt.currentSchemaVersion,
                assetSetIdentifier: manifest.assetSetIdentifier,
                modelIdentifier: contract.identifier,
                revision: manifest.model.revision,
                generationIdentifier: generationIdentifier,
                activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                assets: receiptAssets,
                sourceEvidence: sourceEvidence
            ),
            generationDirectoryURL: generationDirectoryURL
        )
        runtime = StemBundledRuntimeValidationReport(
            contract: contract,
            assets: manifest.bundledRuntimeAssets.map { asset in
                ValidatedStemModelAsset(
                    kind: asset.kind,
                    fileURL: repositoryRoot.appending(path: asset.runtimeRelativePath),
                    byteCount: asset.byteCount,
                    sha256: asset.sha256
                )
            }
        )
        self.manifest = manifest
    }

    var missingInspection: StemModelLocalInspection {
        inspection(installedModel: .missing)
    }

    var invalidInspection: StemModelLocalInspection {
        inspection(installedModel: .invalid(message: "fixture model invalid"))
    }

    var readyInspection: StemModelLocalInspection {
        inspection(installedModel: .ready(installation))
    }

    var runtimeInvalidInspection: StemModelLocalInspection {
        StemModelLocalInspection(
            platform: .supportedAppleSilicon,
            manifest: .valid(manifest),
            installedModel: .missing,
            bundledRuntime: .invalid(message: "fixture runtime invalid")
        )
    }

    private func inspection(
        installedModel: StemInstalledModelLocalStatus
    ) -> StemModelLocalInspection {
        StemModelLocalInspection(
            platform: .supportedAppleSilicon,
            manifest: .valid(manifest),
            installedModel: installedModel,
            bundledRuntime: .ready(runtime)
        )
    }
}

private extension StemModelManager {
    var pendingConfirmation: StemModelDownloadConfirmation? {
        guard case .awaitingConfirmation(let confirmation) = operationState else {
            return nil
        }
        return confirmation
    }

    var currentAcquisitionIdentifier: UUID? {
        switch operationState {
        case .acquiring(let progress), .cancelling(let progress):
            return progress.operationIdentifier
        case .idle, .awaitingConfirmation, .failed:
            return nil
        }
    }

    var isFailureState: Bool {
        guard case .failed = operationState else { return false }
        return true
    }
}

@MainActor
private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
        guard clock.now < deadline else {
            throw StemModelManagerFixtureError.pendingAcquisitionMissing
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
