import Foundation
import Testing
@testable import VelouraLucent

private enum VelouraAppRuntimeFixtureError: Error {
    case pendingAcquisitionMissing
    case timeout
}

private actor RuntimeStemModelInspector: StemModelLocalInspecting {
    private let inspection: StemModelLocalInspection
    private var callCountStorage = 0

    init(inspection: StemModelLocalInspection) {
        self.inspection = inspection
    }

    func inspect() async -> StemModelLocalInspection {
        callCountStorage += 1
        return inspection
    }

    var callCount: Int { callCountStorage }
}

private actor SuspendedStemModelAcquisitionController: StemModelAcquisitionControlling {
    private nonisolated let authorizationIssuer = StemModelAcquisitionService()
    private var pending: [
        UUID: CheckedContinuation<ValidatedStemModelInstallation, any Error>
    ] = [:]

    nonisolated func issueOneTimeAuthorizationAfterExplicitUserConfirmation(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose
    ) -> StemModelAcquisitionAuthorization {
        authorizationIssuer.issueOneTimeAuthorizationAfterExplicitUserConfirmation(
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
        progressHandler(
            StemModelAcquisitionProgress(
                operationIdentifier: authorization.operationIdentifier,
                purpose: purpose,
                phase: .downloading,
                assetKind: .modelWeights,
                receivedBytes: 1_024,
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
        guard let continuation = pending.removeValue(forKey: operationIdentifier) else {
            throw VelouraAppRuntimeFixtureError.pendingAcquisitionMissing
        }
        continuation.resume(
            throwing: StemModelAcquisitionError.cancelled(
                operationIdentifier: operationIdentifier
            )
        )
    }

    var hasPendingAcquisition: Bool {
        !pending.isEmpty
    }
}

@MainActor
struct VelouraAppRuntimeTests {
    @Test("通常画面とfallbackは同じRootを使い、window消失ではruntimeを停止しない")
    func appEntryUsesRootAndShutsDownOnlyAtApplicationTermination() throws {
        let appSource = try source("Sources/VelouraLucent/App/VelouraLucentApp.swift")
        let rootSource = try source("Sources/VelouraLucent/Views/VelouraRootView.swift")

        #expect(appSource.components(separatedBy: "VelouraRootView()").count - 1 == 2)
        #expect(appSource.contains("func applicationWillTerminate"))
        #expect(appSource.contains("VelouraAppRuntime.shared.shutdown()"))
        #expect(appSource.contains("await VelouraAppRuntime.shared.startIfNeeded()"))
        #expect(appSource.contains("return false"))
        #expect(!rootSource.contains("runtime.shutdown()"))
        #expect(!rootSource.contains("await runtime.startIfNeeded()"))
    }

    @Test("モデル確認はアプリ起動時に一度だけ行いモード切替では再実行しない")
    func startupInspectionIsIdempotentAndIndependentFromModeSelection() async throws {
        let fixture = try VelouraAppRuntimeFixture()
        let inspector = RuntimeStemModelInspector(inspection: fixture.inspection)
        let manager = StemModelManager(inspector: inspector)
        let runtime = VelouraAppRuntime(
            standardActions: ProcessingActions(
                notificationReporter: NoOpCompletionNotificationReporter.shared
            ),
            stemModelManager: manager
        )
        defer { runtime.shutdown() }

        await runtime.startIfNeeded()
        await runtime.startIfNeeded()
        #expect(runtime.selectMode(.stem))
        #expect(runtime.selectMode(.standard))

        #expect(await inspector.callCount == 1)
    }

    @Test("モード切替時は離れる側の試聴再生だけを停止する")
    func modeSelectionStopsPlaybackOwnedByPreviousMode() {
        let actions = ProcessingActions(
            notificationReporter: NoOpCompletionNotificationReporter.shared
        )
        let runtime = VelouraAppRuntime(
            standardActions: actions,
            stemModelManager: StemModelManager()
        )
        defer { runtime.shutdown() }

        actions.preview.activeTarget = .input
        #expect(runtime.selectMode(.stem))
        #expect(actions.preview.activeTarget == nil)

        runtime.stemWorkspaceModel.previewController.activeTarget = .corrected
        runtime.stemWorkspaceModel.stemPreviewController.activeTarget = .input
        #expect(runtime.selectMode(.standard))
        #expect(runtime.stemWorkspaceModel.previewController.activeTarget == nil)
        #expect(runtime.stemWorkspaceModel.stemPreviewController.activeTarget == nil)
    }

    @Test("モデル取得中でも明示した通常モード切替を許可し取得を継続する")
    func explicitStandardSelectionKeepsApprovedAcquisitionRunning() async throws {
        let fixture = try VelouraAppRuntimeFixture()
        let inspector = RuntimeStemModelInspector(inspection: fixture.inspection)
        let controller = SuspendedStemModelAcquisitionController()
        let manager = StemModelManager(
            inspector: inspector,
            acquisitionController: controller
        )
        let runtime = VelouraAppRuntime(
            standardActions: ProcessingActions(
                notificationReporter: NoOpCompletionNotificationReporter.shared
            ),
            stemModelManager: manager
        )
        defer { runtime.shutdown() }

        #expect(runtime.selectMode(.stem))
        await runtime.startIfNeeded()
        try manager.prepareAcquisitionConfirmation(purpose: .initialInstall)
        try manager.confirmAcquisition()
        try await waitForRuntimeCondition { await controller.hasPendingAcquisition }
        try await waitForRuntimeCondition {
            guard case .acquiring(let progress) = manager.operationState else {
                return false
            }
            return progress.isWaitingForConnectivity
        }

        #expect(manager.isAcquiringModels)
        #expect(!runtime.isModeSwitchDisabled)
        #expect(runtime.selectMode(.standard))
        #expect(runtime.processingMode == .standard)
        #expect(manager.isAcquiringModels)
        #expect(await controller.hasPendingAcquisition)

        manager.requestAcquisitionCancellation()
        try await waitForRuntimeCondition { manager.operationState == .idle }
    }

    @Test("通常補正またはマスタリング実行中は従来どおりモード切替を禁止する")
    func standardProcessingAndMasteringStillDisableModeSwitch() {
        let actions = ProcessingActions(
            notificationReporter: NoOpCompletionNotificationReporter.shared
        )
        let runtime = VelouraAppRuntime(
            standardActions: actions,
            stemModelManager: StemModelManager()
        )
        defer { runtime.shutdown() }

        actions.job.isProcessing = true
        #expect(runtime.isModeSwitchDisabled)
        #expect(!runtime.selectMode(.stem))
        #expect(runtime.processingMode == .standard)

        actions.job.isProcessing = false
        #expect(runtime.selectMode(.stem))
        actions.job.isMastering = true
        #expect(runtime.isModeSwitchDisabled)
        #expect(!runtime.selectMode(.standard))
        #expect(runtime.processingMode == .stem)
    }
}

private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repositoryRoot.appending(path: relativePath),
        encoding: .utf8
    )
}

private struct VelouraAppRuntimeFixture {
    let inspection: StemModelLocalInspection

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
        let runtime = StemBundledRuntimeValidationReport(
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
        inspection = StemModelLocalInspection(
            platform: .supportedAppleSilicon,
            manifest: .valid(manifest),
            installedModel: .missing,
            bundledRuntime: .ready(runtime)
        )
    }
}

@MainActor
private func waitForRuntimeCondition(
    timeout: Duration = .seconds(2),
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !(await condition()) {
        guard clock.now < deadline else {
            throw VelouraAppRuntimeFixtureError.timeout
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
