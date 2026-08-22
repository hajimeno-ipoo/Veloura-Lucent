import CryptoKit
import Foundation
import Testing
@testable import VelouraLucent

private enum AcquisitionFixtureError: Error, Equatable, Sendable {
    case downloadFailed(StemModelAssetKind)
    case manifestRejected
}

private struct AcquisitionDownloadCall: Equatable, Sendable {
    let downloadIdentifier: UUID
    let kind: StemModelAssetKind
    let stagingDirectoryURL: URL
}

private actor AcquisitionDownloaderDouble: StemModelDownloading {
    private let payloads: [StemModelAssetKind: Data]
    private var failureKind: StemModelAssetKind?
    private var suspendedKind: StemModelAssetKind?
    private var revisionOverrides: [StemModelAssetKind: String] = [:]
    private var headerOverrides: [StemModelAssetKind: String] = [:]
    private var emitsWaitingForConnectivity = false
    private var callsStorage: [AcquisitionDownloadCall] = []
    private var cancelledIdentifiersStorage: [UUID] = []
    private var pending: [UUID: CheckedContinuation<StemModelDownloadResult, Error>] = [:]

    init(payloads: [StemModelAssetKind: Data]) {
        self.payloads = payloads
    }

    func download(
        downloadIdentifier: UUID,
        asset: StemDownloadableModelAsset,
        modelRevision: String,
        policy: StemModelDownloadPolicy,
        stagingDirectoryURL: URL,
        eventHandler: @escaping @Sendable (StemModelDownloadEvent) -> Void
    ) async throws -> StemModelDownloadResult {
        callsStorage.append(
            AcquisitionDownloadCall(
                downloadIdentifier: downloadIdentifier,
                kind: asset.kind,
                stagingDirectoryURL: stagingDirectoryURL
            )
        )
        if emitsWaitingForConnectivity {
            eventHandler(.waitingForConnectivity)
        }
        if suspendedKind == asset.kind {
            return try await withCheckedThrowingContinuation { continuation in
                pending[downloadIdentifier] = continuation
            }
        }
        if failureKind == asset.kind {
            throw AcquisitionFixtureError.downloadFailed(asset.kind)
        }

        let payload = payloads[asset.kind] ?? Data()
        let destinationURL = try StemModelAssetValidator.safeDescendantURL(
            rootURL: stagingDirectoryURL,
            relativePath: asset.installationRelativePath,
            field: "fixture"
        )
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: destinationURL)
        let half = Int64(payload.count / 2)
        eventHandler(
            .progress(
                receivedBytes: half,
                expectedBytes: Int64(payload.count)
            )
        )
        eventHandler(
            .progress(
                receivedBytes: Int64(payload.count),
                expectedBytes: Int64(payload.count)
            )
        )

        return StemModelDownloadResult(
            stagedURL: destinationURL,
            sourceRevisionEvidence: StemModelSourceRevisionEvidence(
                responseHeaderName: headerOverrides[asset.kind]
                    ?? policy.revisionResponseHeader,
                revision: revisionOverrides[asset.kind] ?? modelRevision
            )
        )
    }

    func cancel(downloadIdentifier: UUID) async throws {
        guard let continuation = pending.removeValue(forKey: downloadIdentifier) else {
            throw StemModelDownloadError.downloadNotFound(downloadIdentifier)
        }
        cancelledIdentifiersStorage.append(downloadIdentifier)
        continuation.resume(throwing: StemModelDownloadError.cancelled)
    }

    func setFailure(kind: StemModelAssetKind?) {
        failureKind = kind
    }

    func setSuspended(kind: StemModelAssetKind?) {
        suspendedKind = kind
    }

    func setRevisionOverride(kind: StemModelAssetKind, revision: String) {
        revisionOverrides[kind] = revision
    }

    func setHeaderOverride(kind: StemModelAssetKind, header: String) {
        headerOverrides[kind] = header
    }

    func setEmitsWaitingForConnectivity(_ value: Bool) {
        emitsWaitingForConnectivity = value
    }

    var calls: [AcquisitionDownloadCall] {
        callsStorage
    }

    var cancelledIdentifiers: [UUID] {
        cancelledIdentifiersStorage
    }
}

private final class AcquisitionValidatorProbe: StemModelAcquisitionValidating, @unchecked Sendable {
    private let lock = NSLock()
    private let validator: StemModelAssetValidator
    private var rejectsManifest = false
    private var manifestValidationCountStorage = 0

    init(manifest: StemModelManifest) {
        validator = StemModelAssetValidator(validationReference: manifest)
    }

    func validateManifest(_ manifest: StemModelManifest) throws -> StemModelContract {
        lock.lock()
        manifestValidationCountStorage += 1
        let shouldReject = rejectsManifest
        lock.unlock()
        if shouldReject { throw AcquisitionFixtureError.manifestRejected }
        return try validator.validateManifest(manifest)
    }

    func setRejectsManifest(_ value: Bool) {
        lock.lock()
        rejectsManifest = value
        lock.unlock()
    }

    var manifestValidationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return manifestValidationCountStorage
    }

}

private actor AcquisitionRecordingStore: StemModelAcquisitionStoring {
    private let backing: StemModelInstallationStore
    private var makeStagingOperationIdentifiersStorage: [UUID] = []
    private var discardedOperationIdentifiersStorage: [UUID] = []
    private var activatedOperationIdentifiersStorage: [UUID] = []

    init(backing: StemModelInstallationStore) {
        self.backing = backing
    }

    func makeStagingDirectory(operationIdentifier: UUID) async throws -> URL {
        makeStagingOperationIdentifiersStorage.append(operationIdentifier)
        return try await backing.makeStagingDirectory(
            operationIdentifier: operationIdentifier
        )
    }

    func discardStagingDirectory(operationIdentifier: UUID) async throws {
        discardedOperationIdentifiersStorage.append(operationIdentifier)
        try await backing.discardStagingDirectory(
            operationIdentifier: operationIdentifier
        )
    }

    func activate(
        operationIdentifier: UUID,
        generationIdentifier: UUID,
        manifest: StemModelManifest,
        sourceEvidence: [StemModelInstallationSourceEvidence],
        activatedAt: Date
    ) async throws -> ValidatedStemModelInstallation {
        activatedOperationIdentifiersStorage.append(operationIdentifier)
        return try await backing.activate(
            operationIdentifier: operationIdentifier,
            generationIdentifier: generationIdentifier,
            manifest: manifest,
            sourceEvidence: sourceEvidence,
            activatedAt: activatedAt
        )
    }

    func loadActive(
        manifest: StemModelManifest
    ) async throws -> ValidatedStemModelInstallation? {
        try await backing.loadActive(manifest: manifest)
    }

    var makeStagingOperationIdentifiers: [UUID] {
        makeStagingOperationIdentifiersStorage
    }

    var discardedOperationIdentifiers: [UUID] {
        discardedOperationIdentifiersStorage
    }

    var activatedOperationIdentifiers: [UUID] {
        activatedOperationIdentifiersStorage
    }
}

private final class AcquisitionProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [StemModelAcquisitionProgress] = []

    func record(_ progress: StemModelAcquisitionProgress) {
        lock.lock()
        storage.append(progress)
        lock.unlock()
    }

    var values: [StemModelAcquisitionProgress] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@Suite("Stem model acquisition", .serialized)
struct StemModelAcquisitionServiceTests {
    @Test("Authorization issuance is synchronous, local, and starts no work")
    func authorizationIssuanceStartsNoValidationStoreOrNetworkWork() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }

        let authorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .initialInstall
            )

        #expect(authorization.assetSetIdentifier == fixture.manifest.assetSetIdentifier)
        #expect(authorization.purpose == .initialInstall)
        #expect(await fixture.downloader.calls.isEmpty)
        #expect(fixture.validator.manifestValidationCount == 0)
        #expect(await fixture.store.makeStagingOperationIdentifiers.isEmpty)
    }

    @Test("Initial, repair, and redownload each require their own confirmation")
    func everyPurposeUsesItsOwnOneTimeAuthorization() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }

        for purpose in StemModelAcquisitionPurpose.allCases {
            let authorization = fixture.service
                .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                    manifest: fixture.manifest,
                    purpose: purpose
                )
            _ = try await fixture.service.acquireModels(
                manifest: fixture.manifest,
                purpose: purpose,
                authorization: authorization,
                progressHandler: { _ in }
            )
        }

        #expect(await fixture.downloader.calls.map(\.kind) == [
            .modelWeights, .modelConfiguration,
            .modelWeights, .modelConfiguration,
            .modelWeights, .modelConfiguration,
        ])
        #expect(await fixture.store.activatedOperationIdentifiers.count == 3)
    }

    @Test("Successful acquisition validates both assets and atomically activates one generation")
    func successfulAcquisitionUsesExistingValidatorAndStore() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        let progress = AcquisitionProgressRecorder()
        await fixture.downloader.setEmitsWaitingForConnectivity(true)
        let authorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .initialInstall
            )

        let installation = try await fixture.service.acquireModels(
            manifest: fixture.manifest,
            purpose: .initialInstall,
            authorization: authorization,
            progressHandler: progress.record
        )

        let active = try #require(
            try await fixture.store.loadActive(manifest: fixture.manifest)
        )
        #expect(active == installation)
        #expect(installation.receipt.revision == fixture.manifest.model.revision)
        #expect(Set(installation.receipt.assets.map(\.kind)) == [
            .modelWeights, .modelConfiguration,
        ])
        let expectedEvidence = fixture.manifest.downloadableModelAssets
            .sorted(by: { $0.kind.rawValue < $1.kind.rawValue })
            .map { asset in
                StemModelInstallationSourceEvidence(
                    kind: asset.kind,
                    stableDownloadURL: asset.downloadURL,
                    responseHeaderName: fixture.manifest.downloadPolicy.revisionResponseHeader,
                    revision: fixture.manifest.model.revision
                )
            }
        #expect(installation.receipt.schemaVersion == 2)
        #expect(installation.receipt.sourceEvidence == expectedEvidence)
        #expect(await fixture.store.activatedOperationIdentifiers == [
            authorization.operationIdentifier,
        ])
        #expect(await fixture.store.makeStagingOperationIdentifiers == [
            authorization.operationIdentifier,
        ])
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.paths.stagingDirectoryURL(
                    operationIdentifier: authorization.operationIdentifier
                ).path
            )
        )

        let values = progress.values
        let totalBytes = fixture.totalDownloadBytes
        #expect(values.last?.receivedBytes == totalBytes)
        #expect(values.last?.totalBytes == totalBytes)
        #expect(values.last?.assetKind == nil)
        #expect(values.first?.phase == .preparing)
        #expect(values.contains { $0.phase == .downloading })
        let validatingIndex = try #require(values.firstIndex { $0.phase == .validating })
        let completedIndex = try #require(values.firstIndex { $0.phase == .completed })
        #expect(!values.contains { $0.phase == .activating })
        #expect(validatingIndex < completedIndex)
        #expect(completedIndex == values.indices.last)
        #expect(values.contains { $0.isWaitingForConnectivity })
        #expect(values.allSatisfy { $0.operationIdentifier == authorization.operationIdentifier })
        #expect(values.allSatisfy { $0.purpose == .initialInstall })
        #expect(values.allSatisfy { $0.totalBytes == totalBytes })
        #expect(
            zip(values, values.dropFirst()).allSatisfy { pair in
                pair.0.receivedBytes <= pair.1.receivedBytes
            }
        )
    }

    @Test("Purpose misuse is rejected without network and consumes the confirmation")
    func purposeMisuseIsRejectedAndAuthorizationCannotBeRetried() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        let authorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .repair
            )

        await expectAcquisitionError(
            .authorizationPurposeMismatch(expected: .repair, actual: .redownload)
        ) {
            try await fixture.service.acquireModels(
                manifest: fixture.manifest,
                purpose: .redownload,
                authorization: authorization,
                progressHandler: { _ in }
            )
        }
        await expectAcquisitionError(
            .authorizationAlreadyUsed(
                operationIdentifier: authorization.operationIdentifier
            )
        ) {
            try await fixture.service.acquireModels(
                manifest: fixture.manifest,
                purpose: .repair,
                authorization: authorization,
                progressHandler: { _ in }
            )
        }
        #expect(await fixture.downloader.calls.isEmpty)
    }

    @Test("Authorization is bound to both asset set and the complete manifest")
    func authorizationRejectsDifferentAssetSetAndChangedManifest() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }

        let sameAssetAuthorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .repair
            )
        let changedPolicy = StemModelDownloadPolicy(
            requiresExplicitUserConfirmation: true,
            revisionResponseHeader: fixture.manifest.downloadPolicy.revisionResponseHeader,
            allowedRedirectHosts: Array(
                fixture.manifest.downloadPolicy.allowedRedirectHosts.reversed()
            )
        )
        let changedManifest = copiedManifest(
            fixture.manifest,
            downloadPolicy: changedPolicy
        )
        await expectAcquisitionError(
            .authorizationManifestMismatch(
                assetSetIdentifier: fixture.manifest.assetSetIdentifier
            )
        ) {
            try await fixture.service.acquireModels(
                manifest: changedManifest,
                purpose: .repair,
                authorization: sameAssetAuthorization,
                progressHandler: { _ in }
            )
        }

        let assetSetAuthorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .redownload
            )
        let differentAssetSet = fixture.manifest.assetSetIdentifier + "-different"
        let differentAssetSetManifest = copiedManifest(
            fixture.manifest,
            assetSetIdentifier: differentAssetSet
        )
        await expectAcquisitionError(
            .authorizationAssetSetMismatch(
                expected: fixture.manifest.assetSetIdentifier,
                actual: differentAssetSet
            )
        ) {
            try await fixture.service.acquireModels(
                manifest: differentAssetSetManifest,
                purpose: .redownload,
                authorization: assetSetAuthorization,
                progressHandler: { _ in }
            )
        }
        #expect(await fixture.downloader.calls.isEmpty)
    }

    @Test("A used authorization cannot start a second network operation")
    func authorizationReuseIsRejectedAfterSuccess() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        let authorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .initialInstall
            )
        _ = try await fixture.service.acquireModels(
            manifest: fixture.manifest,
            purpose: .initialInstall,
            authorization: authorization,
            progressHandler: { _ in }
        )

        await expectAcquisitionError(
            .authorizationAlreadyUsed(
                operationIdentifier: authorization.operationIdentifier
            )
        ) {
            try await fixture.service.acquireModels(
                manifest: fixture.manifest,
                purpose: .initialInstall,
                authorization: authorization,
                progressHandler: { _ in }
            )
        }
        #expect(await fixture.downloader.calls.count == 2)
    }

    @Test("Authorization cannot be consumed by another acquisition service")
    func authorizationIsBoundToItsIssuingService() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        let authorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .initialInstall
            )
        let otherService = StemModelAcquisitionService(
            downloader: fixture.downloader,
            validator: fixture.validator,
            store: fixture.store
        )

        await expectAcquisitionError(.authorizationIssuerMismatch) {
            try await otherService.acquireModels(
                manifest: fixture.manifest,
                purpose: .initialInstall,
                authorization: authorization,
                progressHandler: { _ in }
            )
        }
        #expect(await fixture.downloader.calls.isEmpty)
        #expect(await fixture.store.makeStagingOperationIdentifiers.isEmpty)
    }

    @Test("Revision evidence mismatch discards only staging and never activates")
    func revisionMismatchRejectsGenerationBeforeValidationAndActivation() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        let wrongRevision = String(repeating: "a", count: 40)
        await fixture.downloader.setRevisionOverride(
            kind: .modelConfiguration,
            revision: wrongRevision
        )
        let authorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .repair
            )

        await expectAcquisitionError(
            .revisionEvidenceMismatch(
                kind: .modelConfiguration,
                expectedHeader: fixture.manifest.downloadPolicy.revisionResponseHeader,
                actualHeader: fixture.manifest.downloadPolicy.revisionResponseHeader,
                expectedRevision: fixture.manifest.model.revision,
                actualRevision: wrongRevision
            )
        ) {
            try await fixture.service.acquireModels(
                manifest: fixture.manifest,
                purpose: .repair,
                authorization: authorization,
                progressHandler: { _ in }
            )
        }

        #expect(await fixture.store.activatedOperationIdentifiers.isEmpty)
        #expect(await fixture.store.discardedOperationIdentifiers == [
            authorization.operationIdentifier,
        ])
        #expect(try await fixture.store.loadActive(manifest: fixture.manifest) == nil)
    }

    @Test("Second asset failure preserves the previous active generation")
    func secondAssetFailurePreservesOldActiveAndDiscardsNewStaging() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        let firstAuthorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .initialInstall
            )
        let firstInstallation = try await fixture.service.acquireModels(
            manifest: fixture.manifest,
            purpose: .initialInstall,
            authorization: firstAuthorization,
            progressHandler: { _ in }
        )

        await fixture.downloader.setFailure(kind: .modelConfiguration)
        let repairAuthorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .repair
            )
        do {
            _ = try await fixture.service.acquireModels(
                manifest: fixture.manifest,
                purpose: .repair,
                authorization: repairAuthorization,
                progressHandler: { _ in }
            )
            Issue.record("The failed repair unexpectedly activated a generation")
        } catch let error as AcquisitionFixtureError {
            #expect(error == .downloadFailed(.modelConfiguration))
        }

        let active = try #require(
            try await fixture.store.loadActive(manifest: fixture.manifest)
        )
        #expect(active == firstInstallation)
        #expect(FileManager.default.fileExists(atPath: firstInstallation.generationDirectoryURL.path))
        #expect(await fixture.store.activatedOperationIdentifiers == [
            firstAuthorization.operationIdentifier,
        ])
        #expect(await fixture.store.discardedOperationIdentifiers == [
            repairAuthorization.operationIdentifier,
        ])
    }

    @Test("Cancellation stops the active download, removes staging, and keeps active unchanged")
    func cancellationStopsDownloadAndDiscardsOnlyItsStaging() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        let initialAuthorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .initialInstall
            )
        let initialInstallation = try await fixture.service.acquireModels(
            manifest: fixture.manifest,
            purpose: .initialInstall,
            authorization: initialAuthorization,
            progressHandler: { _ in }
        )

        await fixture.downloader.setSuspended(kind: .modelWeights)
        let authorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .redownload
            )
        let service = fixture.service
        let manifest = fixture.manifest
        let task = Task {
            try await service.acquireModels(
                manifest: manifest,
                purpose: .redownload,
                authorization: authorization,
                progressHandler: { _ in }
            )
        }
        try await waitForDownloadCallCount(fixture.downloader, expected: 3)

        try await fixture.service.cancelAcquisition(
            operationIdentifier: authorization.operationIdentifier
        )
        do {
            _ = try await task.value
            Issue.record("Cancelled acquisition unexpectedly succeeded")
        } catch let error as StemModelAcquisitionError {
            #expect(
                error == .cancelled(
                    operationIdentifier: authorization.operationIdentifier
                )
            )
        }

        #expect(await fixture.downloader.cancelledIdentifiers.count == 1)
        #expect(await fixture.store.discardedOperationIdentifiers == [
            authorization.operationIdentifier,
        ])
        #expect(await fixture.store.activatedOperationIdentifiers == [
            initialAuthorization.operationIdentifier,
        ])
        #expect(
            try await fixture.store.loadActive(manifest: fixture.manifest)
                == initialInstallation
        )
        #expect(
            FileManager.default.fileExists(
                atPath: initialInstallation.generationDirectoryURL.path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.paths.stagingDirectoryURL(
                    operationIdentifier: authorization.operationIdentifier
                ).path
            )
        )
    }

    @Test("Concurrent acquisition is rejected without starting another download")
    func actorSerializesCompetingAcquisitions() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        await fixture.downloader.setSuspended(kind: .modelWeights)
        let firstAuthorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .initialInstall
            )
        let service = fixture.service
        let manifest = fixture.manifest
        let firstTask = Task {
            try await service.acquireModels(
                manifest: manifest,
                purpose: .initialInstall,
                authorization: firstAuthorization,
                progressHandler: { _ in }
            )
        }
        try await waitForDownloadCallCount(fixture.downloader, expected: 1)

        let secondAuthorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .redownload
            )
        await expectAcquisitionError(
            .operationAlreadyInProgress(
                activeOperationIdentifier: firstAuthorization.operationIdentifier
            )
        ) {
            try await fixture.service.acquireModels(
                manifest: fixture.manifest,
                purpose: .redownload,
                authorization: secondAuthorization,
                progressHandler: { _ in }
            )
        }
        #expect(await fixture.downloader.calls.count == 1)

        try await fixture.service.cancelAcquisition(
            operationIdentifier: firstAuthorization.operationIdentifier
        )
        _ = try? await firstTask.value
    }

    @Test("Manifest failure stops before download and final asset validation is delegated to activation")
    func validationResponsibilitiesStayAtTheirSingleBoundaries() async throws {
        let manifestFailureFixture = try AcquisitionFixture()
        defer { manifestFailureFixture.removeTemporaryRoot() }
        manifestFailureFixture.validator.setRejectsManifest(true)
        let firstAuthorization = manifestFailureFixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: manifestFailureFixture.manifest,
                purpose: .initialInstall
            )
        do {
            _ = try await manifestFailureFixture.service.acquireModels(
                manifest: manifestFailureFixture.manifest,
                purpose: .initialInstall,
                authorization: firstAuthorization,
                progressHandler: { _ in }
            )
            Issue.record("Rejected manifest unexpectedly started acquisition")
        } catch let error as AcquisitionFixtureError {
            #expect(error == .manifestRejected)
        }
        #expect(await manifestFailureFixture.downloader.calls.isEmpty)
        #expect(await manifestFailureFixture.store.makeStagingOperationIdentifiers.isEmpty)

        let successFixture = try AcquisitionFixture()
        defer { successFixture.removeTemporaryRoot() }
        let secondAuthorization = successFixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: successFixture.manifest,
                purpose: .initialInstall
            )
        _ = try await successFixture.service.acquireModels(
            manifest: successFixture.manifest,
            purpose: .initialInstall,
            authorization: secondAuthorization,
            progressHandler: { _ in }
        )
        #expect(await successFixture.downloader.calls.count == 2)
        #expect(await successFixture.store.activatedOperationIdentifiers == [
            secondAuthorization.operationIdentifier,
        ])
    }

    @Test("Bundled MLX runtime is never part of model acquisition")
    func bundledRuntimeValidationAndRecoveryStaySeparateFromModelDownload() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        #expect(fixture.manifest.bundledRuntimeAssets.map(\.kind) == [.metalLibrary])
        let authorization = fixture.service
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: fixture.manifest,
                purpose: .repair
            )

        _ = try await fixture.service.acquireModels(
            manifest: fixture.manifest,
            purpose: .repair,
            authorization: authorization,
            progressHandler: { _ in }
        )

        #expect(await fixture.downloader.calls.map(\.kind) == [
            .modelWeights, .modelConfiguration,
        ])
        let runtimeRelativePath = try #require(
            fixture.manifest.bundledRuntimeAssets.first?.runtimeRelativePath
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.temporaryRootURL.appending(path: runtimeRelativePath).path
            )
        )
    }

    @Test("Cancellation with an unrelated operation identifier is rejected")
    func cancelRejectsUnrelatedOperationIdentifier() async throws {
        let fixture = try AcquisitionFixture()
        defer { fixture.removeTemporaryRoot() }
        let requested = UUID()

        await expectAcquisitionError(
            .operationNotActive(requested: requested, active: nil)
        ) {
            try await fixture.service.cancelAcquisition(
                operationIdentifier: requested
            )
        }
        #expect(await fixture.downloader.calls.isEmpty)
    }
}

private struct AcquisitionFixture {
    let temporaryRootURL: URL
    let paths: StemModelStorePaths
    let manifest: StemModelManifest
    let payloads: [StemModelAssetKind: Data]
    let validator: AcquisitionValidatorProbe
    let store: AcquisitionRecordingStore
    let downloader: AcquisitionDownloaderDouble
    let service: StemModelAcquisitionService

    init() throws {
        let temporaryRootURL = FileManager.default.temporaryDirectory.appending(
            path: "VelouraStemAcquisitionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let paths = StemModelStorePaths(
            rootURL: temporaryRootURL.appending(
                path: "StemModels",
                directoryHint: .isDirectory
            )
        )
        let weights = Data("acquisition-fixture-weights".utf8)
        let configuration = try JSONSerialization.data(
            withJSONObject: [
                "model_name": "htdemucs",
                "model_class": "BagOfModelsMLX",
                "num_models": 1,
                "sub_model_class": "HTDemucsMLX",
                "kwargs": [
                    "samplerate": 44_100,
                    "audio_channels": 2,
                    "sources": ["drums", "bass", "other", "vocals"],
                    "segment": "39/5",
                ],
            ],
            options: [.sortedKeys]
        )
        let payloads: [StemModelAssetKind: Data] = [
            .modelWeights: weights,
            .modelConfiguration: configuration,
        ]
        let productionValidator = StemModelAssetValidator()
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let productionManifest = try productionValidator.loadManifest(
            at: repositoryRoot.appending(
                path: "Sources/VelouraLucent/Resources/StemModels/stem-model-manifest.json"
            )
        )
        let manifest = StemModelManifest(
            schemaVersion: productionManifest.schemaVersion,
            assetSetIdentifier: productionManifest.assetSetIdentifier,
            model: productionManifest.model,
            runtimePins: productionManifest.runtimePins,
            audioContract: productionManifest.audioContract,
            downloadPolicy: productionManifest.downloadPolicy,
            downloadableModelAssets: productionManifest.downloadableModelAssets.map { asset in
                let payload = payloads[asset.kind] ?? Data()
                return StemDownloadableModelAsset(
                    kind: asset.kind,
                    downloadURL: asset.downloadURL,
                    installationRelativePath: asset.installationRelativePath,
                    byteCount: Int64(payload.count),
                    sha256: Self.sha256(payload)
                )
            },
            bundledRuntimeAssets: productionManifest.bundledRuntimeAssets,
            metalLibraryBuildProvenance: productionManifest.metalLibraryBuildProvenance
        )
        let validator = AcquisitionValidatorProbe(manifest: manifest)
        let backingValidator = StemModelAssetValidator(validationReference: manifest)
        let backingStore = StemModelInstallationStore(
            paths: paths,
            validator: backingValidator
        )
        let store = AcquisitionRecordingStore(backing: backingStore)
        let downloader = AcquisitionDownloaderDouble(payloads: payloads)
        let service = StemModelAcquisitionService(
            downloader: downloader,
            validator: validator,
            store: store
        )

        self.temporaryRootURL = temporaryRootURL
        self.paths = paths
        self.manifest = manifest
        self.payloads = payloads
        self.validator = validator
        self.store = store
        self.downloader = downloader
        self.service = service
    }

    var totalDownloadBytes: Int64 {
        manifest.downloadableModelAssets.reduce(0) { $0 + $1.byteCount }
    }

    func removeTemporaryRoot() {
        try? FileManager.default.removeItem(at: temporaryRootURL)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private func copiedManifest(
    _ manifest: StemModelManifest,
    assetSetIdentifier: String? = nil,
    downloadPolicy: StemModelDownloadPolicy? = nil
) -> StemModelManifest {
    StemModelManifest(
        schemaVersion: manifest.schemaVersion,
        assetSetIdentifier: assetSetIdentifier ?? manifest.assetSetIdentifier,
        model: manifest.model,
        runtimePins: manifest.runtimePins,
        audioContract: manifest.audioContract,
        downloadPolicy: downloadPolicy ?? manifest.downloadPolicy,
        downloadableModelAssets: manifest.downloadableModelAssets,
        bundledRuntimeAssets: manifest.bundledRuntimeAssets,
        metalLibraryBuildProvenance: manifest.metalLibraryBuildProvenance
    )
}

private func expectAcquisitionError<T: Sendable>(
    _ expected: StemModelAcquisitionError,
    operation: () async throws -> T
) async {
    do {
        _ = try await operation()
        Issue.record("Expected acquisition error was not thrown: \(expected)")
    } catch let error as StemModelAcquisitionError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected acquisition error type: \(error)")
    }
}

private func waitForDownloadCallCount(
    _ downloader: AcquisitionDownloaderDouble,
    expected: Int,
    timeout: Duration = .seconds(2)
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while await downloader.calls.count < expected {
        guard clock.now < deadline else {
            throw AcquisitionFixtureError.downloadFailed(.modelWeights)
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
