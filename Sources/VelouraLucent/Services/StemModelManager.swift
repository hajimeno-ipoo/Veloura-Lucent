import Foundation
import Observation

enum StemPlatformLocalStatus: Equatable, Sendable {
    case supportedAppleSilicon
    case unsupported(processArchitecture: String)

    static var current: StemPlatformLocalStatus {
        #if arch(arm64)
        .supportedAppleSilicon
        #elseif arch(x86_64)
        .unsupported(processArchitecture: "x86_64")
        #else
        .unsupported(processArchitecture: "unknown")
        #endif
    }
}

enum StemManifestLocalStatus: Equatable, Sendable {
    case valid(StemModelManifest)
    case invalid(message: String)
}

enum StemInstalledModelLocalStatus: Equatable, Sendable {
    case notChecked
    case missing
    case invalid(message: String)
    case ready(ValidatedStemModelInstallation)
}

enum StemBundledRuntimeLocalStatus: Equatable, Sendable {
    case notChecked
    case invalid(message: String)
    case ready(StemBundledRuntimeValidationReport)
}

struct StemModelLocalInspection: Equatable, Sendable {
    let platform: StemPlatformLocalStatus
    let manifest: StemManifestLocalStatus
    let installedModel: StemInstalledModelLocalStatus
    let bundledRuntime: StemBundledRuntimeLocalStatus

    var validatedManifest: StemModelManifest? {
        guard case .valid(let manifest) = manifest else { return nil }
        return manifest
    }

    var isReadyForStemProcessing: Bool {
        guard case .supportedAppleSilicon = platform,
              case .valid = manifest,
              case .ready = installedModel,
              case .ready = bundledRuntime else {
            return false
        }
        return true
    }

    var recoveryActions: [StemModelRecoveryAction] {
        guard case .supportedAppleSilicon = platform else {
            return []
        }
        guard case .valid = manifest else {
            return []
        }
        guard case .ready = bundledRuntime else {
            // mlx.metallib is an app-bundled runtime asset. Model downloading cannot repair it.
            return []
        }
        switch installedModel {
        case .notChecked:
            return []
        case .missing:
            return [.initialDownload]
        case .invalid:
            return [.redownload]
        case .ready:
            return []
        }
    }
}

enum StemModelInspectionState: Equatable, Sendable {
    case checking
    case loaded(StemModelLocalInspection)
}

struct StemModelDownloadConfirmation: Equatable, Sendable, Identifiable {
    struct Asset: Equatable, Sendable, Identifiable {
        let kind: StemModelAssetKind
        let fileName: String
        let byteCount: Int64
        let sha256: String
        let stableDownloadURL: String

        var id: StemModelAssetKind { kind }
    }

    let id: UUID
    let model: StemSeparationModel
    let purpose: StemModelAcquisitionPurpose
    let repository: String
    let revision: String
    let license: String
    let totalByteCount: Int64
    let assets: [Asset]

    var sourceHost: String? {
        assets.compactMap { URL(string: $0.stableDownloadURL)?.host }.first
    }
}

enum StemModelManagerOperationState: Equatable, Sendable {
    case idle
    case awaitingConfirmation(StemModelDownloadConfirmation)
    case acquiring(StemModelAcquisitionProgress)
    case cancelling(StemModelAcquisitionProgress)
    case failed(
        message: String,
        retryPurpose: StemModelAcquisitionPurpose?
    )
}

enum StemModelManagerError: LocalizedError, Equatable, Sendable {
    case unsupportedPlatform(processArchitecture: String)
    case resourcesStillChecking
    case manifestUnavailable
    case runtimeCannotBeRepairedByModelDownload
    case recoveryActionUnavailable(StemModelRecoveryAction)
    case acquisitionAlreadyInProgress
    case noPendingConfirmation
    case confirmationNoLongerMatchesCurrentManifest
    case invalidDownloadByteTotal
    case acquiredAssetsDidNotBecomeReady
    case modelOperationAlreadyInProgress
    case modelRemovalUnavailable
    case selectedModelChanged

    var errorDescription: String? {
        switch self {
        case let .unsupportedPlatform(processArchitecture):
            return "Stem ModeはApple Silicon専用です。現在の実行アーキテクチャは\(processArchitecture)です。通常モードは引き続き利用できます。"
        case .resourcesStillChecking:
            return "Stem Modeのローカル資産を確認中です。"
        case .manifestUnavailable:
            return "Stem Modeの同梱manifestを検証できないため、モデル取得を開始できません。"
        case .runtimeCannotBeRepairedByModelDownload:
            return "同梱MLX実行資産の問題は、AIモデルの再取得では修復できません。"
        case .recoveryActionUnavailable(let action):
            return "現在のStem Mode資産状態では、この復旧操作を実行できません: \(action.rawValue)"
        case .acquisitionAlreadyInProgress:
            return "Stem Modeのモデル取得または確認が既に進行中です。"
        case .noPendingConfirmation:
            return "Stem Modeのモデル取得確認がありません。"
        case .confirmationNoLongerMatchesCurrentManifest:
            return "表示したStem Modeモデル取得内容が現在の検証済みmanifestと一致しないため、取得を開始できません。"
        case .invalidDownloadByteTotal:
            return "Stem Modeのモデル取得容量を安全に集計できません。"
        case .acquiredAssetsDidNotBecomeReady:
            return "取得後の再検証でStem Modeのモデル資産を有効化できませんでした。"
        case .modelOperationAlreadyInProgress:
            return "Stem Modeのモデル操作が既に進行中です。"
        case .modelRemovalUnavailable:
            return "選択中のStem Modeモデルには削除できる取得データがありません。"
        case .selectedModelChanged:
            return "削除確認後に選択中のStem Modeモデルが変わったため、削除を中止しました。"
        }
    }
}

protocol StemModelLocalInspecting: Sendable {
    func inspect() async -> StemModelLocalInspection
}

protocol StemModelSelectionInspecting: StemModelLocalInspecting {
    func inspect(model: StemSeparationModel) async -> StemModelLocalInspection
}

struct ProductionStemModelLocalInspector: StemModelSelectionInspecting, Sendable {
    private let store: StemModelInstallationStore

    init(
        store: StemModelInstallationStore = StemModelInstallationStore()
    ) {
        self.store = store
    }

    func inspect() async -> StemModelLocalInspection {
        await inspect(model: .htdemucs)
    }

    func inspect(model: StemSeparationModel) async -> StemModelLocalInspection {
        let validator = StemModelAssetValidator(selectedModel: model)
        let manifest: StemModelManifest
        do {
            manifest = try validator.loadBundledManifest()
            _ = try validator.validateManifest(manifest)
        } catch {
            return StemModelLocalInspection(
                platform: .current,
                manifest: .invalid(message: error.localizedDescription),
                installedModel: .notChecked,
                bundledRuntime: .notChecked
            )
        }

        let platform = StemPlatformLocalStatus.current
        guard case .supportedAppleSilicon = platform else {
            return StemModelLocalInspection(
                platform: platform,
                manifest: .valid(manifest),
                installedModel: .notChecked,
                bundledRuntime: .notChecked
            )
        }

        let runtimeTask = Task.detached(priority: .utility) { [validator] in
            do {
                return StemBundledRuntimeLocalStatus.ready(
                    try validator.validateBundledRuntimeAssets()
                )
            } catch {
                return StemBundledRuntimeLocalStatus.invalid(
                    message: error.localizedDescription
                )
            }
        }

        let installedModel: StemInstalledModelLocalStatus
        do {
            if let installation = try await store.loadActive(manifest: manifest) {
                installedModel = .ready(installation)
            } else {
                installedModel = .missing
            }
        } catch {
            installedModel = .invalid(message: error.localizedDescription)
        }

        return StemModelLocalInspection(
            platform: platform,
            manifest: .valid(manifest),
            installedModel: installedModel,
            bundledRuntime: await runtimeTask.value
        )
    }
}

protocol StemModelAcquisitionControlling: Sendable {
    nonisolated func issueOneTimeAuthorizationAfterExplicitUserConfirmation(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose
    ) -> StemModelAcquisitionAuthorization

    func acquireModels(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose,
        authorization: StemModelAcquisitionAuthorization,
        progressHandler: @escaping @Sendable (StemModelAcquisitionProgress) -> Void
    ) async throws -> ValidatedStemModelInstallation

    func cancelAcquisition(operationIdentifier: UUID) async throws
}

extension StemModelAcquisitionService: StemModelAcquisitionControlling {}

protocol StemModelRemovalControlling: Sendable {
    func removeInstalledModel(manifest: StemModelManifest) async throws
}

extension StemModelInstallationStore: StemModelRemovalControlling {}

@MainActor
@Observable
final class StemModelManager {
    private(set) var selectedModel: StemSeparationModel = .htdemucs
    private(set) var inspectionState: StemModelInspectionState = .checking
    private(set) var operationState: StemModelManagerOperationState = .idle
    private(set) var isRemovingModel = false

    @ObservationIgnored private let inspector: any StemModelLocalInspecting
    @ObservationIgnored private let acquisitionController: any StemModelAcquisitionControlling
    @ObservationIgnored private let removalController: any StemModelRemovalControlling
    @ObservationIgnored private var inspectionIdentifier = UUID()
    @ObservationIgnored private var acquisitionTask: Task<Void, Never>?

    init(
        inspector: any StemModelLocalInspecting = ProductionStemModelLocalInspector(),
        acquisitionController: any StemModelAcquisitionControlling = StemModelAcquisitionService(),
        removalController: any StemModelRemovalControlling = StemModelInstallationStore()
    ) {
        self.inspector = inspector
        self.acquisitionController = acquisitionController
        self.removalController = removalController
    }

    var localInspection: StemModelLocalInspection? {
        guard case .loaded(let inspection) = inspectionState else { return nil }
        return inspection
    }

    var isReadyForStemProcessing: Bool {
        localInspection?.isReadyForStemProcessing == true
    }

    var recoveryActions: [StemModelRecoveryAction] {
        localInspection?.recoveryActions ?? []
    }

    var isAcquiringModels: Bool {
        switch operationState {
        case .acquiring, .cancelling:
            return true
        case .idle, .awaitingConfirmation, .failed:
            return false
        }
    }

    var isModelOperationInProgress: Bool {
        isAcquiringModels || isRemovingModel
    }

    var canRemoveSelectedModel: Bool {
        guard !isModelOperationInProgress,
              case .loaded(let inspection) = inspectionState,
              case .supportedAppleSilicon = inspection.platform,
              case .valid = inspection.manifest else {
            return false
        }
        switch inspection.installedModel {
        case .ready, .invalid:
            return true
        case .notChecked, .missing:
            return false
        }
    }

    var pendingDownloadConfirmation: StemModelDownloadConfirmation? {
        guard case .awaitingConfirmation(let confirmation) = operationState else {
            return nil
        }
        return confirmation
    }

    func inspectLocalResources() async {
        guard !isAcquiringModels else { return }
        if case .awaitingConfirmation = operationState {
            // A confirmation only authorizes the exact local inspection that produced it.
            // Reinspection invalidates the displayed contract before any async work begins.
            operationState = .idle
        }
        let identifier = UUID()
        inspectionIdentifier = identifier
        inspectionState = .checking
        let inspection: StemModelLocalInspection
        if let selectingInspector = inspector as? any StemModelSelectionInspecting {
            inspection = await selectingInspector.inspect(model: selectedModel)
        } else {
            inspection = await inspector.inspect()
        }
        guard !Task.isCancelled, inspectionIdentifier == identifier else { return }
        inspectionState = .loaded(inspection)
    }

    func selectModel(_ model: StemSeparationModel) async {
        guard model != selectedModel, !isModelOperationInProgress else { return }
        if case .awaitingConfirmation = operationState {
            operationState = .idle
        }
        if case .failed = operationState {
            operationState = .idle
        }
        selectedModel = model
        await inspectLocalResources()
    }

    func prepareAcquisitionConfirmation(
        purpose: StemModelAcquisitionPurpose
    ) throws {
        guard !isRemovingModel else {
            throw StemModelManagerError.modelOperationAlreadyInProgress
        }
        guard operationState == .idle || isFailedState else {
            throw StemModelManagerError.acquisitionAlreadyInProgress
        }
        guard case .loaded(let inspection) = inspectionState else {
            throw StemModelManagerError.resourcesStillChecking
        }
        if case let .unsupported(processArchitecture) = inspection.platform {
            throw StemModelManagerError.unsupportedPlatform(
                processArchitecture: processArchitecture
            )
        }
        guard let manifest = inspection.validatedManifest else {
            throw StemModelManagerError.manifestUnavailable
        }
        guard case .ready = inspection.bundledRuntime else {
            throw StemModelManagerError.runtimeCannotBeRepairedByModelDownload
        }

        let requiredAction = recoveryAction(for: purpose)
        guard inspection.recoveryActions.contains(requiredAction) else {
            throw StemModelManagerError.recoveryActionUnavailable(requiredAction)
        }
        operationState = .awaitingConfirmation(
            try makeConfirmation(manifest: manifest, purpose: purpose)
        )
    }

    func startAcquisition(purpose: StemModelAcquisitionPurpose) {
        do {
            try prepareAcquisitionConfirmation(purpose: purpose)
            try confirmAcquisition()
        } catch {
            guard !isAcquiringModels else { return }
            operationState = .failed(
                message: error.localizedDescription,
                retryPurpose: nil
            )
        }
    }

    /// Call only after an explicit model acquisition action from the UI.
    /// This is the sole point where the one-operation network capability is issued.
    func confirmAcquisition() throws {
        guard case .awaitingConfirmation(let confirmation) = operationState else {
            throw StemModelManagerError.noPendingConfirmation
        }
        guard case .loaded(let inspection) = inspectionState,
              let manifest = inspection.validatedManifest else {
            throw StemModelManagerError.manifestUnavailable
        }
        if case let .unsupported(processArchitecture) = inspection.platform {
            throw StemModelManagerError.unsupportedPlatform(
                processArchitecture: processArchitecture
            )
        }
        guard case .ready = inspection.bundledRuntime else {
            throw StemModelManagerError.runtimeCannotBeRepairedByModelDownload
        }

        let requiredAction = recoveryAction(for: confirmation.purpose)
        guard inspection.recoveryActions.contains(requiredAction) else {
            throw StemModelManagerError.recoveryActionUnavailable(requiredAction)
        }

        let currentConfirmation = try makeConfirmation(
            manifest: manifest,
            purpose: confirmation.purpose,
            id: confirmation.id
        )
        guard currentConfirmation == confirmation else {
            throw StemModelManagerError.confirmationNoLongerMatchesCurrentManifest
        }

        let authorization = acquisitionController
            .issueOneTimeAuthorizationAfterExplicitUserConfirmation(
                manifest: manifest,
                purpose: confirmation.purpose
            )
        let initialProgress = StemModelAcquisitionProgress(
            operationIdentifier: authorization.operationIdentifier,
            purpose: confirmation.purpose,
            phase: .preparing,
            assetKind: confirmation.assets.first?.kind,
            receivedBytes: 0,
            totalBytes: confirmation.totalByteCount,
            isWaitingForConnectivity: false
        )
        operationState = .acquiring(initialProgress)

        acquisitionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let installation = try await acquisitionController.acquireModels(
                    manifest: manifest,
                    purpose: confirmation.purpose,
                    authorization: authorization
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.receiveAcquisitionProgress(progress)
                    }
                }
                guard self.currentOperationIdentifier == authorization.operationIdentifier else {
                    return
                }
                inspectionState = .loaded(
                    StemModelLocalInspection(
                        platform: inspection.platform,
                        manifest: inspection.manifest,
                        installedModel: .ready(installation),
                        bundledRuntime: inspection.bundledRuntime
                    )
                )
                operationState = .idle
            } catch {
                guard self.currentOperationIdentifier == authorization.operationIdentifier else {
                    return
                }
                if let acquisitionError = error as? StemModelAcquisitionError,
                   acquisitionError == .cancelled(
                    operationIdentifier: authorization.operationIdentifier
                   ) {
                    operationState = .idle
                } else if error is CancellationError {
                    operationState = .idle
                } else {
                    operationState = .failed(
                        message: error.localizedDescription,
                        retryPurpose: error is StemModelAssetValidationError
                            ? confirmation.purpose
                            : nil
                    )
                }
            }
        }
    }

    func cancelPendingConfirmation() {
        guard case .awaitingConfirmation = operationState else { return }
        operationState = .idle
    }

    func removeSelectedModel(expectedModel: StemSeparationModel) async throws {
        guard !isModelOperationInProgress,
              operationState == .idle || isFailedState else {
            throw StemModelManagerError.modelOperationAlreadyInProgress
        }
        guard selectedModel == expectedModel else {
            throw StemModelManagerError.selectedModelChanged
        }
        guard case .loaded(let inspection) = inspectionState,
              case .supportedAppleSilicon = inspection.platform,
              case .valid(let manifest) = inspection.manifest else {
            throw StemModelManagerError.modelRemovalUnavailable
        }
        switch inspection.installedModel {
        case .ready, .invalid:
            break
        case .notChecked, .missing:
            throw StemModelManagerError.modelRemovalUnavailable
        }

        if isFailedState {
            operationState = .idle
        }
        isRemovingModel = true
        defer { isRemovingModel = false }
        do {
            try await removalController.removeInstalledModel(manifest: manifest)
            await inspectLocalResources()
        } catch {
            await inspectLocalResources()
            throw error
        }
    }

    func requestAcquisitionCancellation() {
        let progress: StemModelAcquisitionProgress
        switch operationState {
        case .acquiring(let current), .cancelling(let current):
            progress = current
        case .idle, .awaitingConfirmation, .failed:
            return
        }
        guard progress.phase != .activating, progress.phase != .completed else {
            return
        }
        operationState = .cancelling(progress)
        Task { [acquisitionController] in
            try? await acquisitionController.cancelAcquisition(
                operationIdentifier: progress.operationIdentifier
            )
        }
    }

    func dismissFailure() {
        guard case .failed = operationState else { return }
        operationState = .idle
    }

    func retryFailedAcquisition() {
        guard case .failed(_, let retryPurpose) = operationState,
              let retryPurpose else {
            return
        }
        operationState = .idle
        startAcquisition(purpose: retryPurpose)
    }

    func shutdown() {
        guard let operationIdentifier = currentOperationIdentifier else {
            acquisitionTask?.cancel()
            acquisitionTask = nil
            return
        }
        acquisitionTask?.cancel()
        acquisitionTask = nil
        Task { [acquisitionController] in
            try? await acquisitionController.cancelAcquisition(
                operationIdentifier: operationIdentifier
            )
        }
    }

    private var isFailedState: Bool {
        if case .failed = operationState { return true }
        return false
    }

    private var currentOperationIdentifier: UUID? {
        switch operationState {
        case .acquiring(let progress), .cancelling(let progress):
            return progress.operationIdentifier
        case .idle, .awaitingConfirmation, .failed:
            return nil
        }
    }

    private func receiveAcquisitionProgress(_ progress: StemModelAcquisitionProgress) {
        guard currentOperationIdentifier == progress.operationIdentifier else { return }
        if case .cancelling = operationState {
            operationState = .cancelling(progress)
        } else {
            operationState = .acquiring(progress)
        }
    }

    private func recoveryAction(
        for purpose: StemModelAcquisitionPurpose
    ) -> StemModelRecoveryAction {
        switch purpose {
        case .initialInstall: .initialDownload
        case .repair: .repair
        case .redownload: .redownload
        }
    }

    private func makeConfirmation(
        manifest: StemModelManifest,
        purpose: StemModelAcquisitionPurpose,
        id: UUID = UUID()
    ) throws -> StemModelDownloadConfirmation {
        let assets = manifest.downloadableModelAssets
            .sorted { $0.kind.rawValue < $1.kind.rawValue }
            .map {
                StemModelDownloadConfirmation.Asset(
                    kind: $0.kind,
                    fileName: URL(fileURLWithPath: $0.installationRelativePath)
                        .lastPathComponent,
                    byteCount: $0.byteCount,
                    sha256: $0.sha256,
                    stableDownloadURL: $0.downloadURL
                )
            }
        var totalByteCount: Int64 = 0
        for asset in assets {
            let (newTotal, overflow) = totalByteCount.addingReportingOverflow(asset.byteCount)
            guard !overflow, asset.byteCount >= 0 else {
                throw StemModelManagerError.invalidDownloadByteTotal
            }
            totalByteCount = newTotal
        }
        return StemModelDownloadConfirmation(
            id: id,
            model: selectedModel,
            purpose: purpose,
            repository: manifest.model.repo,
            revision: manifest.model.revision,
            license: manifest.model.licenseMetadata,
            totalByteCount: totalByteCount,
            assets: assets
        )
    }
}
