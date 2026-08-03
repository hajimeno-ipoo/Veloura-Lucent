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

private actor SelectingStemModelInspectorDouble: StemModelSelectionInspecting {
    private let inspection: StemModelLocalInspection
    private var selectedModelsStorage: [StemSeparationModel] = []

    init(inspection: StemModelLocalInspection) {
        self.inspection = inspection
    }

    func inspect() async -> StemModelLocalInspection {
        await inspect(model: .htdemucs)
    }

    func inspect(model: StemSeparationModel) async -> StemModelLocalInspection {
        selectedModelsStorage.append(model)
        return inspection
    }

    var selectedModels: [StemSeparationModel] {
        selectedModelsStorage
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

    func failValidation() throws {
        guard let identifier = pending.keys.first,
              let continuation = pending.removeValue(forKey: identifier) else {
            throw StemModelManagerFixtureError.pendingAcquisitionMissing
        }
        continuation.resume(
            throwing: StemModelAssetValidationError.assetChecksumMismatch(
                kind: .modelWeights,
                path: "/fixture/model.safetensors",
                expected: "expected",
                actual: "actual"
            )
        )
    }
}

@MainActor
struct StemModelManagerTests {
    @Test("モデル選択は同じmanagerで選択モデルだけを再検証する")
    func selectingModelReusesExistingManagerAndInspector() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = SelectingStemModelInspectorDouble(
            inspection: fixture.missingInspection
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )

        await manager.inspectLocalResources()
        await manager.selectModel(.bsRoformerSW)

        #expect(manager.selectedModel == .bsRoformerSW)
        #expect(await inspector.selectedModels == [.htdemucs, .bsRoformerSW])
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)
    }

    @Test("異常モデルから正常モデルへ切り替えるとStem処理可能状態へ戻る")
    func selectingReadyModelRestoresStemReadiness() async throws {
        let fixture = try StemModelManagerFixture()
        let inspector = StemModelInspectorDouble(
            inspections: [fixture.invalidInspection, fixture.readyInspection]
        )
        let controller = StemModelAcquisitionControllerDouble(
            successfulInstallation: fixture.installation
        )
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )

        await manager.inspectLocalResources()
        #expect(!manager.isReadyForStemProcessing)

        await manager.selectModel(.bsRoformerSW)

        #expect(manager.selectedModel == .bsRoformerSW)
        #expect(manager.localInspection == fixture.readyInspection)
        #expect(manager.isReadyForStemProcessing)
        #expect(await inspector.callCount == 2)
    }

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

    @Test("missing・invalidだけが承認済みの取得操作を提示する")
    func recoveryActionsMatchInstalledModelState() throws {
        let fixture = try StemModelManagerFixture()

        #expect(fixture.missingInspection.recoveryActions == [.initialDownload])
        #expect(fixture.invalidInspection.recoveryActions == [.redownload])
        #expect(fixture.readyInspection.recoveryActions.isEmpty)
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

        #expect(manager.recoveryActions.isEmpty)
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

    @Test("肯定操作だけが一回限りの権限を発行し取得済み検証結果を利用する")
    func affirmativeConfirmationIssuesAuthorizationAndUsesValidatedResult() async throws {
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

        #expect(await inspector.callCount == 1)
        #expect(manager.localInspection == fixture.readyInspection)
        #expect(manager.isReadyForStemProcessing)
        #expect(await controller.calls.count == 1)
    }

    @Test("右サイドの取得操作は確認待ちを残さず取得を開始し成功後に利用可能へ戻る")
    func explicitAcquisitionActionStartsImmediatelyAndClosesOnReadiness() async throws {
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

        manager.startAcquisition(purpose: .initialInstall)

        #expect(manager.pendingDownloadConfirmation == nil)
        #expect(controller.authorizationIssueCount == 1)
        try await waitUntil { await controller.hasPendingAcquisition }
        try await waitUntil {
            guard case .acquiring(let progress) = manager.operationState else {
                return false
            }
            return progress.receivedBytes == 42
        }

        try await controller.completeSuccessfully()
        try await waitUntil { manager.operationState == .idle }

        #expect(manager.localInspection == fixture.readyInspection)
        #expect(manager.isReadyForStemProcessing)
        #expect(await controller.calls.count == 1)
    }

    @Test("取得成功後は追加のSHA検証を行わず返却済みinstallationを利用する")
    func successfulAcquisitionDoesNotReinspectAssets() async throws {
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
        try await waitUntil { manager.operationState == .idle }

        #expect(await inspector.callCount == 1)
        #expect(manager.localInspection == fixture.readyInspection)
        #expect(manager.isReadyForStemProcessing)
    }

    @Test("通信などの取得失敗では再ダウンロード操作を表示しない")
    func nonValidationFailureDoesNotOfferRetryDownload() async throws {
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

        #expect(await inspector.callCount == 1)
        #expect(manager.localInspection == fixture.missingInspection)
        #expect(manager.recoveryActions == [.initialDownload])
        #expect(!manager.isReadyForStemProcessing)
        guard case .failed(_, let retryPurpose) = manager.operationState else {
            Issue.record("取得失敗状態が保持されていません")
            return
        }
        #expect(retryPurpose == nil)
    }

    @Test("最終検証の異常時だけ再ダウンロードし再検証できる")
    func validationFailureOffersFullRetryDownload() async throws {
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

        manager.startAcquisition(purpose: .initialInstall)
        try await waitUntil { await controller.hasPendingAcquisition }
        try await controller.failValidation()
        try await waitUntil { manager.isFailureState }

        guard case .failed(_, let retryPurpose) = manager.operationState else {
            Issue.record("検証異常が取得失敗状態として保持されていません")
            return
        }
        #expect(retryPurpose == .initialInstall)
        #expect(await inspector.callCount == 1)

        manager.retryFailedAcquisition()
        try await waitUntil { await controller.calls.count == 2 }
        try await waitUntil { await controller.hasPendingAcquisition }
        #expect(await controller.calls.map(\.purpose) == [
            .initialInstall, .initialInstall,
        ])

        try await controller.completeSuccessfully()
        try await waitUntil { manager.operationState == .idle }
        #expect(manager.isReadyForStemProcessing)
    }

    @Test("取得中断は追加検証を行わず取得状態を終了する")
    func cancellationReturnsToIdleWithoutReinspection() async throws {
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
        try manager.prepareAcquisitionConfirmation(purpose: .redownload)
        try manager.confirmAcquisition()
        try await waitUntil { await controller.hasPendingAcquisition }

        let operationIdentifier = try #require(manager.currentAcquisitionIdentifier)
        manager.requestAcquisitionCancellation()
        try await waitUntil { manager.operationState == .idle }

        #expect(await controller.cancellationIdentifiers == [operationIdentifier])
        #expect(await inspector.callCount == 1)
        #expect(manager.localInspection == fixture.invalidInspection)
        #expect(manager.recoveryActions == [.redownload])
    }

    @Test("manifest不正はStem内に閉じ右サイドの操作を表示しない")
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
        #expect(manager.recoveryActions.isEmpty)
        #expect(!manager.isReadyForStemProcessing)
        #expect(controller.authorizationIssueCount == 0)
        #expect(await controller.calls.isEmpty)
    }

    @Test("Apple Silicon以外では右サイドのモデル操作を表示しない")
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
        #expect(manager.recoveryActions.isEmpty)
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
