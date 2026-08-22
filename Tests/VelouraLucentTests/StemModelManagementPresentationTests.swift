import Foundation
import Testing
@testable import VelouraLucent

@MainActor
struct StemModelManagementPresentationTests {
    @Test("モデル未取得では初回取得だけを表示する")
    func missingModelPresentsInitialDownloadWithoutSilentFallback() throws {
        let fixture = try Fixture()

        let presentation = StemModelManagementSection.Presentation.make(
            inspectionState: .loaded(fixture.inspection(installedModel: .missing))
        )

        #expect(presentation.title == "AIモデルが必要です")
        #expect(presentation.statusText == "未取得")
        #expect(presentation.allowsModelDownload)
        #expect(presentation.actions == [.initialDownload])
        #expect(!presentation.actions.contains(.repair))
        #expect(!presentation.actions.contains(.redownload))
        #expect(!presentation.requiresAppReinstallation)
    }

    @Test("モデル破損でも取得ボタンを1つだけ表示する")
    func invalidModelPresentsOneDownloadAction() throws {
        let fixture = try Fixture()

        let presentation = StemModelManagementSection.Presentation.make(
            inspectionState: .loaded(
                fixture.inspection(
                    installedModel: .invalid(message: "fixture checksum mismatch")
                )
            )
        )

        #expect(presentation.title == "AIモデルの修復が必要です")
        #expect(presentation.statusText == "修復必要")
        #expect(presentation.detail == "fixture checksum mismatch")
        #expect(presentation.actions == [.redownload])
        #expect(presentation.allowsModelDownload)
    }

    @Test("検証済みモデルには無効な取得ボタンを表示する")
    func readyModelShowsDisabledDownloadAction() throws {
        let fixture = try Fixture()

        let presentation = StemModelManagementSection.Presentation.make(
            inspectionState: .loaded(
                fixture.inspection(installedModel: .ready(fixture.installation))
            )
        )

        #expect(presentation.title == "Stem Modeのモデルを利用できます")
        #expect(presentation.statusText == "利用可能")
        #expect(presentation.actions.isEmpty)
        #expect(presentation.visibleActions == [.initialDownload])
        #expect(!presentation.allowsModelDownload)
    }

    @Test("同梱MLX実行資産の異常時はモデル取得を禁止し再インストールを案内する")
    func invalidBundledRuntimeNeverOffersModelDownload() throws {
        let fixture = try Fixture()
        let inspection = StemModelLocalInspection(
            platform: .supportedAppleSilicon,
            manifest: .valid(fixture.manifest),
            installedModel: .missing,
            bundledRuntime: .invalid(message: "fixture metallib mismatch")
        )

        let presentation = StemModelManagementSection.Presentation.make(
            inspectionState: .loaded(inspection)
        )

        #expect(presentation.title == "MLX実行資産を検証できません")
        #expect(presentation.detail == "fixture metallib mismatch")
        #expect(presentation.requiresAppReinstallation)
        #expect(!presentation.allowsModelDownload)
        #expect(presentation.actions.isEmpty)
    }

    @Test("manifest異常時は右サイドのモデル操作を表示しない")
    func invalidManifestNeverOffersModelDownload() {
        let inspection = StemModelLocalInspection(
            platform: .supportedAppleSilicon,
            manifest: .invalid(message: "fixture manifest mismatch"),
            installedModel: .notChecked,
            bundledRuntime: .notChecked
        )

        let presentation = StemModelManagementSection.Presentation.make(
            inspectionState: .loaded(inspection)
        )

        #expect(presentation.title == "モデル定義を検証できません")
        #expect(presentation.detail == "fixture manifest mismatch")
        #expect(presentation.requiresAppReinstallation)
        #expect(!presentation.allowsModelDownload)
        #expect(presentation.actions.isEmpty)
    }

    @Test("非Apple Siliconでは右サイドのモデル操作を表示しない")
    func unsupportedPlatformNeverOffersModelDownload() throws {
        let fixture = try Fixture()
        let inspection = StemModelLocalInspection(
            platform: .unsupported(processArchitecture: "x86_64"),
            manifest: .valid(fixture.manifest),
            installedModel: .missing,
            bundledRuntime: .ready(fixture.runtime)
        )

        let presentation = StemModelManagementSection.Presentation.make(
            inspectionState: .loaded(inspection)
        )

        #expect(presentation.title == "このMacではStem Modeを実行できません")
        #expect(presentation.detail == "実行アーキテクチャ: x86_64")
        #expect(!presentation.allowsModelDownload)
        #expect(presentation.actions.isEmpty)
    }

    @Test("右サイドは両モデルで取得ボタン名を統一する")
    func recoveryActionLabelsCoverEveryApprovedChoice() {
        let presentations = StemModelRecoveryAction.allCases.map {
            StemModelManagementSection.ActionPresentation(action: $0)
        }

        #expect(
            presentations.map(\.title) == [
                "AIモデルを取得",
                "AIモデルを修復",
                "AIモデルを取得"
            ]
        )
        #expect(
            presentations.filter(\.isPrimary).map(\.action)
                == [.initialDownload, .repair]
        )
    }

    @Test("取得確認は削除確認と同じ簡潔な標準アラート文にする")
    func downloadConfirmationUsesConciseAlertCopy() {
        let confirmation = StemModelDownloadConfirmation(
            id: UUID(),
            model: .htdemucs,
            purpose: .initialInstall,
            repository: "example/repository",
            revision: "example-revision",
            license: "example-license",
            totalByteCount: 123,
            assets: []
        )

        let presentation = StemModelManagementSection.DownloadConfirmationPresentation(
            confirmation: confirmation
        )

        #expect(presentation.title == "AIモデルを取得しますか？")
        #expect(presentation.affirmativeTitle == "取得")
        #expect(presentation.alertMessage == "Stem分離に必要なAIモデルを取得します。")
        #expect(!presentation.alertMessage.contains(confirmation.repository))
        #expect(!presentation.alertMessage.contains(confirmation.revision))
        #expect(!presentation.alertMessage.contains(confirmation.license))
    }

    @Test("About画面はモデル2資産の配布情報と保存先を表示する")
    func aboutPresentationContainsCompleteDownloadContract() throws {
        let fixture = try Fixture()

        let presentation = VelouraAboutView.ModelPresentation(
            model: .htdemucs,
            manifest: fixture.manifest
        )

        #expect(presentation.repository == fixture.manifest.model.repo)
        #expect(presentation.revision == fixture.manifest.model.revision)
        #expect(presentation.license == fixture.manifest.model.licenseMetadata)
        #expect(presentation.licenseStatus.contains("MIT"))
        #expect(presentation.provenance.contains("adefossez/demucs"))
        #expect(presentation.totalByteCount == 168_007_757)
        #expect(presentation.assets.count == 2)
        #expect(presentation.assets.map(\.kind) == [.modelWeights, .modelConfiguration])
        #expect(
            presentation.assets.map(\.fileName)
                == ["htdemucs.safetensors", "htdemucs_config.json"]
        )
        #expect(presentation.assets[0].byteCount == 168_005_865)
        #expect(
            presentation.assets[0].sha256
                == "339d267a7a6983a11eedbdc00413c602a65e9b9103f695fb5c2b2a481cd9d297"
        )
        #expect(presentation.assets[1].byteCount == 1_892)
        #expect(
            presentation.assets[1].sha256
                == "9258499513944fc062fbca0f11be425a446ec5702869a87e225323d7a57d2a01"
        )
        #expect(
            presentation.saveDestination
                == NSString(
                    string: StemModelStorePaths.production.rootURL.path
                ).abbreviatingWithTildeInPath
        )
    }

    @Test("Aboutで表示する両モデルの権利・来歴情報を保持する")
    func rightsAndProvenanceInformationCoversBothModels() {
        let htdemucs = StemSeparationModel.htdemucs.rightsAndProvenance
        let bsRoformer = StemSeparationModel.bsRoformerSW.rightsAndProvenance

        #expect(htdemucs.licenseStatus.contains("MIT"))
        #expect(htdemucs.provenance.contains("adefossez/demucs"))
        #expect(bsRoformer.licenseStatus.contains("unknown"))
        #expect(bsRoformer.licenseStatus.contains("未宣言"))
        #expect(bsRoformer.provenance.contains("enerjazzer/BS-ROFO-SW-Fixed"))
    }

    @Test("取得進捗は現在資産と全体を別々に算出する")
    func progressPresentationSeparatesAssetAndOverallProgress() throws {
        let fixture = try Fixture()
        let weights = try #require(
            fixture.manifest.downloadableModelAssets.first {
                $0.kind == .modelWeights
            }
        )
        let configuration = try #require(
            fixture.manifest.downloadableModelAssets.first {
                $0.kind == .modelConfiguration
            }
        )
        let receivedConfigurationBytes: Int64 = 946
        let progress = StemModelAcquisitionProgress(
            operationIdentifier: UUID(),
            purpose: .initialInstall,
            assetKind: .modelConfiguration,
            receivedBytes: weights.byteCount + receivedConfigurationBytes,
            totalBytes: weights.byteCount + configuration.byteCount,
            isWaitingForConnectivity: false
        )

        let presentation = StemModelManagementSection.ProgressPresentation.make(
            progress: progress,
            manifest: fixture.manifest,
            isCancelling: false
        )

        #expect(presentation.assetProgresses.count == 2)
        #expect(presentation.assetProgresses[0].fileName == "htdemucs.safetensors")
        #expect(presentation.assetProgresses[0].fraction == 1)
        #expect(presentation.assetProgresses[0].receivedBytes == weights.byteCount)
        #expect(presentation.assetProgresses[1].fileName == "htdemucs_config.json")
        #expect(presentation.assetProgresses[1].receivedBytes == receivedConfigurationBytes)
        #expect(presentation.assetProgresses[1].totalBytes == configuration.byteCount)
        #expect(presentation.assetProgresses[1].fraction == 0.5)
        #expect(presentation.assetProgresses[1].isCurrent)
        #expect(presentation.receivedBytes == weights.byteCount + receivedConfigurationBytes)
        #expect(presentation.overallFraction > 0.99)
        #expect(presentation.overallFraction < 1)
        #expect(presentation.phase == .downloading)
        #expect(presentation.canRequestCancellation)
    }

    @Test("検証phaseは容量RevisionSHA検証を明示して中断を残す")
    func validatingPhaseUsesExplicitProgressPhase() throws {
        let fixture = try Fixture()
        let totalBytes = fixture.manifest.downloadableModelAssets.reduce(Int64.zero) {
            $0 + $1.byteCount
        }
        let progress = StemModelAcquisitionProgress(
            operationIdentifier: UUID(),
            purpose: .redownload,
            phase: .validating,
            assetKind: .modelConfiguration,
            receivedBytes: totalBytes,
            totalBytes: totalBytes,
            isWaitingForConnectivity: false
        )

        let presentation = StemModelManagementSection.ProgressPresentation.make(
            progress: progress,
            manifest: fixture.manifest,
            isCancelling: false
        )

        #expect(presentation.phase == .validating)
        #expect(presentation.stageTitle == "取得済み資産を検証中")
        #expect(presentation.stageDetail.contains("固定Revision"))
        #expect(presentation.stageDetail.contains("SHA-256"))
        #expect(presentation.overallFraction == 1)
        #expect(presentation.canRequestCancellation)
    }

    @Test("オフライン待機中は進捗モーダルに接続待機と中断可否を表示する")
    func offlineWaitingKeepsProgressAndCancellationVisible() throws {
        let fixture = try Fixture()
        let totalBytes = fixture.manifest.downloadableModelAssets.reduce(Int64.zero) {
            $0 + $1.byteCount
        }
        let progress = StemModelAcquisitionProgress(
            operationIdentifier: UUID(),
            purpose: .initialInstall,
            phase: .downloading,
            assetKind: .modelWeights,
            receivedBytes: 1_024,
            totalBytes: totalBytes,
            isWaitingForConnectivity: true
        )

        let presentation = StemModelManagementSection.ProgressPresentation.make(
            progress: progress,
            manifest: fixture.manifest,
            isCancelling: false
        )

        #expect(presentation.isWaitingForConnectivity)
        #expect(presentation.stageTitle == "ネットワーク接続を待っています")
        #expect(presentation.canRequestCancellation)
    }

    @Test("有効化phaseはtransaction commit中として中断を禁止する")
    func activatingPhaseDisablesCancellation() throws {
        let fixture = try Fixture()
        let totalBytes = fixture.manifest.downloadableModelAssets.reduce(Int64.zero) {
            $0 + $1.byteCount
        }
        let progress = StemModelAcquisitionProgress(
            operationIdentifier: UUID(),
            purpose: .repair,
            phase: .activating,
            assetKind: nil,
            receivedBytes: totalBytes,
            totalBytes: totalBytes,
            isWaitingForConnectivity: false
        )

        let presentation = StemModelManagementSection.ProgressPresentation.make(
            progress: progress,
            manifest: fixture.manifest,
            isCancelling: false
        )

        #expect(presentation.phase == .activating)
        #expect(presentation.stageTitle.contains("中断不可"))
        #expect(presentation.stageDetail.contains("中断できません"))
        #expect(!presentation.canRequestCancellation)
    }

    @Test("完了phaseはチェック表示用の完了状態となり中断を禁止する")
    func completedPhaseShowsCompletionAndDisablesCancellation() throws {
        let fixture = try Fixture()
        let totalBytes = fixture.manifest.downloadableModelAssets.reduce(Int64.zero) {
            $0 + $1.byteCount
        }
        let progress = StemModelAcquisitionProgress(
            operationIdentifier: UUID(),
            purpose: .redownload,
            phase: .completed,
            assetKind: nil,
            receivedBytes: totalBytes,
            totalBytes: totalBytes,
            isWaitingForConnectivity: false
        )

        let presentation = StemModelManagementSection.ProgressPresentation.make(
            progress: progress,
            manifest: fixture.manifest,
            isCancelling: false
        )

        #expect(presentation.phase == .completed)
        #expect(presentation.stageTitle == "モデル取得が完了しました")
        #expect(!presentation.canRequestCancellation)
    }
}

private struct Fixture {
    let manifest: StemModelManifest
    let installation: ValidatedStemModelInstallation
    let runtime: StemBundledRuntimeValidationReport

    init() throws {
        let repositoryRoot = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let validator = StemModelAssetValidator()
        let loadedManifest = try validator.loadManifest(
            at: repositoryRoot.appending(
                path: "Sources/VelouraLucent/Resources/StemModels/stem-model-manifest.json"
            )
        )
        let contract = try validator.validateManifest(loadedManifest)
        let generationIdentifier = UUID()
        let generationDirectoryURL = FileManager.default.temporaryDirectory.appending(
            path: "StemModelManagementPresentationTests-\(generationIdentifier.uuidString)",
            directoryHint: .isDirectory
        )
        let assets = loadedManifest.downloadableModelAssets.map { asset in
            ValidatedStemModelAsset(
                kind: asset.kind,
                fileURL: generationDirectoryURL.appending(path: asset.installationRelativePath),
                byteCount: asset.byteCount,
                sha256: asset.sha256
            )
        }
        let receiptAssets = loadedManifest.downloadableModelAssets.map { asset in
            StemModelInstallationReceiptAsset(
                kind: asset.kind,
                installationRelativePath: asset.installationRelativePath,
                byteCount: asset.byteCount,
                sha256: asset.sha256
            )
        }
        let sourceEvidence = loadedManifest.downloadableModelAssets.map { asset in
            StemModelInstallationSourceEvidence(
                kind: asset.kind,
                stableDownloadURL: asset.downloadURL,
                responseHeaderName: loadedManifest.downloadPolicy.revisionResponseHeader,
                revision: loadedManifest.model.revision
            )
        }
        installation = ValidatedStemModelInstallation(
            snapshot: ValidatedStemModelSnapshot(
                contract: contract,
                installationRootURL: generationDirectoryURL,
                modelDirectoryURL: generationDirectoryURL.appending(
                    path: "model",
                    directoryHint: .isDirectory
                ),
                assets: assets
            ),
            receipt: StemModelInstallationReceipt(
                schemaVersion: StemModelInstallationReceipt.currentSchemaVersion,
                assetSetIdentifier: loadedManifest.assetSetIdentifier,
                modelIdentifier: contract.identifier,
                revision: loadedManifest.model.revision,
                generationIdentifier: generationIdentifier,
                activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
                assets: receiptAssets,
                sourceEvidence: sourceEvidence
            ),
            generationDirectoryURL: generationDirectoryURL
        )
        runtime = StemBundledRuntimeValidationReport(
            contract: contract,
            assets: loadedManifest.bundledRuntimeAssets.map { asset in
                ValidatedStemModelAsset(
                    kind: asset.kind,
                    fileURL: repositoryRoot.appending(path: asset.runtimeRelativePath),
                    byteCount: asset.byteCount,
                    sha256: asset.sha256
                )
            }
        )
        manifest = loadedManifest
    }

    func inspection(
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
