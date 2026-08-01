import CryptoKit
import Foundation
import Testing
@testable import VelouraLucent

@Suite(.serialized)
struct StemModelInstallationStoreTests {
    @Test
    func productionRootUsesApplicationSupportStemModelsDirectory() {
        let expected = URL.applicationSupportDirectory
            .appending(path: "Veloura Lucent", directoryHint: .isDirectory)
            .appending(path: "StemModels", directoryHint: .isDirectory)

        #expect(StemModelStorePaths.production.rootURL == expected)
    }

    @Test
    func bothModelsKeepIndependentActivePointers() {
        let paths = StemModelStorePaths(
            rootURL: URL(filePath: "/tmp/VelouraStemModelPointerTests")
        )

        #expect(paths.activePointerURL(for: .htdemucs) == paths.activePointerURL)
        #expect(
            paths.activePointerURL(for: .bsRoformerSW).lastPathComponent
                == "active-bs-roformer-sw.json"
        )
        #expect(
            paths.activePointerURL(for: .htdemucs)
                != paths.activePointerURL(for: .bsRoformerSW)
        )
    }

    @Test
    func missingActivePointerReturnsNoInstallation() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }

        let active = try await fixture.store.loadActive(manifest: fixture.manifest)

        #expect(active == nil)
    }

    @Test
    func firstActivationPersistsValidatedGenerationAndReloadsIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let generationIdentifier = UUID()
        let activatedAt = Date(timeIntervalSince1970: 1_735_689_600)
        _ = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)

        let activated = try await fixture.store.activate(
            operationIdentifier: operationIdentifier,
            generationIdentifier: generationIdentifier,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence,
            activatedAt: activatedAt
        )

        #expect(activated.receipt.generationIdentifier == generationIdentifier)
        #expect(activated.receipt.activatedAt == activatedAt)
        #expect(activated.receipt.revision == fixture.manifest.model.revision)
        #expect(activated.receipt.schemaVersion == 2)
        #expect(activated.receipt.sourceEvidence == fixture.sourceEvidence)
        #expect(Set(activated.snapshot.assets.map(\.kind)) == [.modelWeights, .modelConfiguration])
        #expect(FileManager.default.fileExists(atPath: activated.generationDirectoryURL.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.paths.stagingDirectoryURL(operationIdentifier: operationIdentifier).path
            )
        )

        let reloaded = try #require(try await fixture.store.loadActive(manifest: fixture.manifest))
        #expect(reloaded == activated)
    }

    @Test
    func reactivationSwitchesPointerAndKeepsPreviousValidatedGeneration() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let firstOperation = UUID()
        let firstGeneration = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: firstOperation)
        let first = try await fixture.store.activate(
            operationIdentifier: firstOperation,
            generationIdentifier: firstGeneration,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )

        let secondOperation = UUID()
        let secondGeneration = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: secondOperation)
        let second = try await fixture.store.activate(
            operationIdentifier: secondOperation,
            generationIdentifier: secondGeneration,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )

        #expect(first.generationDirectoryURL != second.generationDirectoryURL)
        #expect(FileManager.default.fileExists(atPath: first.generationDirectoryURL.path))
        #expect(FileManager.default.fileExists(atPath: second.generationDirectoryURL.path))
        let active = try #require(try await fixture.store.loadActive(manifest: fixture.manifest))
        #expect(active.receipt.generationIdentifier == secondGeneration)
    }

    @Test
    func failedReactivationLeavesPreviousActiveGenerationSelected() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let firstOperation = UUID()
        let firstGeneration = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: firstOperation)
        _ = try await fixture.store.activate(
            operationIdentifier: firstOperation,
            generationIdentifier: firstGeneration,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )
        let pointerBeforeFailure = try Data(contentsOf: fixture.paths.activePointerURL)

        let failedOperation = UUID()
        let failedGeneration = UUID()
        let stagingURL = try await fixture.prepareStaging(operationIdentifier: failedOperation)
        let weightsURL = try fixture.assetURL(kind: .modelWeights, rootURL: stagingURL)
        var corruptedWeights = fixture.weights
        corruptedWeights[corruptedWeights.startIndex] ^= 0xff
        try corruptedWeights.write(to: weightsURL)

        do {
            _ = try await fixture.store.activate(
                operationIdentifier: failedOperation,
                generationIdentifier: failedGeneration,
                manifest: fixture.manifest,
                sourceEvidence: fixture.sourceEvidence
            )
            Issue.record("検証に失敗したモデル世代が有効化されました")
        } catch let error as StemModelAssetValidationError {
            guard case .assetChecksumMismatch(kind: .modelWeights, _, _, _) = error else {
                Issue.record("想定外の資産検証エラーです: \(error)")
                return
            }
        }

        #expect(try Data(contentsOf: fixture.paths.activePointerURL) == pointerBeforeFailure)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.paths.generationDirectoryURL(
                    assetSetIdentifier: fixture.manifest.assetSetIdentifier,
                    generationIdentifier: failedGeneration
                ).path
            )
        )
        let active = try #require(try await fixture.store.loadActive(manifest: fixture.manifest))
        #expect(active.receipt.generationIdentifier == firstGeneration)
    }

    @Test
    func failureAfterReceiptCreationStillLeavesPreviousActiveGenerationSelected() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let firstOperation = UUID()
        let activeGeneration = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: firstOperation)
        _ = try await fixture.store.activate(
            operationIdentifier: firstOperation,
            generationIdentifier: activeGeneration,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )
        let pointerBeforeFailure = try Data(contentsOf: fixture.paths.activePointerURL)

        let failedOperation = UUID()
        let failedStagingURL = try await fixture.prepareStaging(operationIdentifier: failedOperation)
        do {
            _ = try await fixture.store.activate(
                operationIdentifier: failedOperation,
                generationIdentifier: activeGeneration,
                manifest: fixture.manifest,
                sourceEvidence: fixture.sourceEvidence
            )
            Issue.record("既存世代への再配置が成功扱いになりました")
        } catch let error as StemModelInstallationStoreError {
            guard case .generationAlreadyExists = error else {
                Issue.record("想定外のstoreエラーです: \(error)")
                return
            }
        }

        #expect(
            FileManager.default.fileExists(
                atPath: fixture.paths.receiptURL(in: failedStagingURL).path
            )
        )
        #expect(try Data(contentsOf: fixture.paths.activePointerURL) == pointerBeforeFailure)
        let active = try #require(try await fixture.store.loadActive(manifest: fixture.manifest))
        #expect(active.receipt.generationIdentifier == activeGeneration)
    }

    @Test
    func corruptedActiveAssetIsRejectedOnEveryReload() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let generationIdentifier = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)
        let activated = try await fixture.store.activate(
            operationIdentifier: operationIdentifier,
            generationIdentifier: generationIdentifier,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )
        let weightsURL = try fixture.assetURL(
            kind: .modelWeights,
            rootURL: activated.generationDirectoryURL
        )
        var corruptedWeights = fixture.weights
        corruptedWeights[corruptedWeights.startIndex] ^= 0xff
        try corruptedWeights.write(to: weightsURL)

        do {
            _ = try await fixture.store.loadActive(manifest: fixture.manifest)
            Issue.record("破損したactiveモデルが再検証を通過しました")
        } catch let error as StemModelAssetValidationError {
            guard case .assetChecksumMismatch(kind: .modelWeights, _, _, _) = error else {
                Issue.record("想定外の資産検証エラーです: \(error)")
                return
            }
        }
    }

    @Test
    func unexpectedStagingFileIsRejectedBeforeReceiptOrPointerWrite() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let stagingURL = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)
        let unexpectedURL = stagingURL.appending(path: "unapproved.bin")
        try Data([0x01]).write(to: unexpectedURL)

        do {
            _ = try await fixture.store.activate(
                operationIdentifier: operationIdentifier,
                generationIdentifier: UUID(),
                manifest: fixture.manifest,
                sourceEvidence: fixture.sourceEvidence
            )
            Issue.record("未承認ファイルを含むstagingが有効化されました")
        } catch let error as StemModelAssetValidationError {
            guard case .unexpectedInstallationEntry(let path) = error else {
                Issue.record("想定外の資産検証エラーです: \(error)")
                return
            }
            #expect(path.hasSuffix("/unapproved.bin"))
        }

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.activePointerURL.path))
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.paths.receiptURL(in: stagingURL).path
            )
        )
    }

    @Test
    func finderMetadataDoesNotInvalidateValidatedModelAssets() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let generationIdentifier = UUID()
        let stagingURL = try await fixture.prepareStaging(
            operationIdentifier: operationIdentifier
        )
        try Data([0x00]).write(
            to: stagingURL.appending(path: ".DS_Store")
        )

        let installation = try await fixture.store.activate(
            operationIdentifier: operationIdentifier,
            generationIdentifier: generationIdentifier,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )

        #expect(
            installation.snapshot.assets.count
                == fixture.manifest.downloadableModelAssets.count
        )
        #expect(installation.receipt.generationIdentifier == generationIdentifier)
    }

    @Test
    func symbolicLinkAssetIsRejectedBeforeActivation() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let stagingURL = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)
        let weightsURL = try fixture.assetURL(kind: .modelWeights, rootURL: stagingURL)
        let externalURL = fixture.temporaryRootURL.appending(path: "external-weights.bin")
        try fixture.weights.write(to: externalURL)
        try FileManager.default.removeItem(at: weightsURL)
        try FileManager.default.createSymbolicLink(at: weightsURL, withDestinationURL: externalURL)

        do {
            _ = try await fixture.store.activate(
                operationIdentifier: operationIdentifier,
                generationIdentifier: UUID(),
                manifest: fixture.manifest,
                sourceEvidence: fixture.sourceEvidence
            )
            Issue.record("symbolic linkのモデル資産が有効化されました")
        } catch let error as StemModelAssetValidationError {
            guard case .assetSymbolicLink(_, let path) = error else {
                Issue.record("想定外の資産検証エラーです: \(error)")
                return
            }
            #expect(path.hasSuffix("/htdemucs/htdemucs.safetensors"))
        }

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.activePointerURL.path))
    }

    @Test
    func symbolicLinkActivePointerIsRejectedWithoutFollowingIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        try FileManager.default.createDirectory(
            at: fixture.paths.rootURL,
            withIntermediateDirectories: true
        )
        let externalPointerURL = fixture.temporaryRootURL.appending(path: "external-active.json")
        try Data("{}".utf8).write(to: externalPointerURL)
        try FileManager.default.createSymbolicLink(
            at: fixture.paths.activePointerURL,
            withDestinationURL: externalPointerURL
        )

        do {
            _ = try await fixture.store.loadActive(manifest: fixture.manifest)
            Issue.record("symbolic linkのactive pointerが読み込まれました")
        } catch let error as StemModelInstallationStoreError {
            guard case .storePathSymbolicLink(let path) = error else {
                Issue.record("想定外のstoreエラーです: \(error)")
                return
            }
            #expect(path.hasSuffix("/active.json"))
        }
    }

    @Test
    func configurationSegmentMustUseExactDemucsFractionString() async throws {
        let invalidConfiguration = try configurationData(segment: 7.8)
        let fixture = try makeFixture(configuration: invalidConfiguration)
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let stagingURL = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)
        let configurationURL = try fixture.assetURL(kind: .modelConfiguration, rootURL: stagingURL)

        do {
            _ = try await fixture.store.activate(
                operationIdentifier: operationIdentifier,
                generationIdentifier: UUID(),
                manifest: fixture.manifest,
                sourceEvidence: fixture.sourceEvidence
            )
            Issue.record("Demucs設定のsegment型が異なるモデルが有効化されました")
        } catch let error as StemModelAssetValidationError {
            guard case .modelConfigurationInvalid(let path, let field, let expected, _) = error else {
                Issue.record("想定外の資産検証エラーです: \(error)")
                return
            }
            #expect(path.hasSuffix("/htdemucs/htdemucs_config.json"))
            #expect(path.hasSuffix(configurationURL.lastPathComponent))
            #expect(field == "kwargs.segment")
            #expect(expected == "39/5")
        }
    }

    @Test
    func configurationIntegerFieldsDoNotAcceptJSONBooleanValues() async throws {
        let invalidConfiguration = try configurationData(segment: "39/5", numModels: true)
        let fixture = try makeFixture(configuration: invalidConfiguration)
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)

        do {
            _ = try await fixture.store.activate(
                operationIdentifier: operationIdentifier,
                generationIdentifier: UUID(),
                manifest: fixture.manifest,
                sourceEvidence: fixture.sourceEvidence
            )
            Issue.record("Demucs設定の整数欄にJSON booleanを持つモデルが有効化されました")
        } catch let error as StemModelAssetValidationError {
            guard case .modelConfigurationInvalid(_, let field, let expected, _) = error else {
                Issue.record("想定外の資産検証エラーです: \(error)")
                return
            }
            #expect(field == "num_models")
            #expect(expected == "1")
        }
    }

    @Test
    func missingSourceEvidenceIsRejectedBeforeGenerationMoveAndKeepsOldActive() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let evidence = fixture.sourceEvidence.filter { $0.kind != .modelWeights }

        try await expectSourceEvidenceRejection(
            fixture: fixture,
            sourceEvidence: evidence,
            expected: .sourceEvidenceMissing(kind: .modelWeights)
        )
    }

    @Test
    func duplicateSourceEvidenceIsRejectedBeforeGenerationMoveAndKeepsOldActive() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let duplicated = try #require(fixture.sourceEvidence.first)
        let evidence = [duplicated, duplicated] + fixture.sourceEvidence.dropFirst()

        try await expectSourceEvidenceRejection(
            fixture: fixture,
            sourceEvidence: Array(evidence),
            expected: .sourceEvidenceDuplicate(kind: duplicated.kind)
        )
    }

    @Test
    func wrongStableURLSourceEvidenceIsRejectedBeforeGenerationMoveAndKeepsOldActive() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        var evidence = fixture.sourceEvidence
        let index = try #require(evidence.firstIndex { $0.kind == .modelWeights })
        let original = evidence[index]
        let redirectURL = "https://cas-bridge.xethub.hf.co/temporary-download"
        evidence[index] = StemModelInstallationSourceEvidence(
            kind: original.kind,
            stableDownloadURL: redirectURL,
            responseHeaderName: original.responseHeaderName,
            revision: original.revision
        )

        try await expectSourceEvidenceRejection(
            fixture: fixture,
            sourceEvidence: evidence,
            expected: .sourceEvidenceStableURLMismatch(
                kind: original.kind,
                expected: try fixture.downloadableAsset(kind: original.kind).downloadURL
            )
        )
    }

    @Test
    func wrongHeaderSourceEvidenceIsRejectedBeforeGenerationMoveAndKeepsOldActive() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        var evidence = fixture.sourceEvidence
        let index = try #require(evidence.firstIndex { $0.kind == .modelConfiguration })
        let original = evidence[index]
        let wrongHeader = "ETag"
        evidence[index] = StemModelInstallationSourceEvidence(
            kind: original.kind,
            stableDownloadURL: original.stableDownloadURL,
            responseHeaderName: wrongHeader,
            revision: original.revision
        )

        try await expectSourceEvidenceRejection(
            fixture: fixture,
            sourceEvidence: evidence,
            expected: .sourceEvidenceHeaderMismatch(
                kind: original.kind,
                expected: fixture.manifest.downloadPolicy.revisionResponseHeader,
                actual: wrongHeader
            )
        )
    }

    @Test
    func wrongRevisionSourceEvidenceIsRejectedBeforeGenerationMoveAndKeepsOldActive() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        var evidence = fixture.sourceEvidence
        let index = try #require(evidence.firstIndex { $0.kind == .modelWeights })
        let original = evidence[index]
        let wrongRevision = String(repeating: "0", count: 40)
        evidence[index] = StemModelInstallationSourceEvidence(
            kind: original.kind,
            stableDownloadURL: original.stableDownloadURL,
            responseHeaderName: original.responseHeaderName,
            revision: wrongRevision
        )

        try await expectSourceEvidenceRejection(
            fixture: fixture,
            sourceEvidence: evidence,
            expected: .sourceEvidenceRevisionMismatch(
                kind: original.kind,
                expected: fixture.manifest.model.revision,
                actual: wrongRevision
            )
        )
    }

    @Test
    func unexpectedSourceEvidenceKindIsRejectedBeforeGenerationMoveAndKeepsOldActive() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        var evidence = fixture.sourceEvidence
        let index = try #require(evidence.firstIndex { $0.kind == .modelWeights })
        let original = evidence[index]
        evidence[index] = StemModelInstallationSourceEvidence(
            kind: .metalLibrary,
            stableDownloadURL: original.stableDownloadURL,
            responseHeaderName: original.responseHeaderName,
            revision: original.revision
        )

        try await expectSourceEvidenceRejection(
            fixture: fixture,
            sourceEvidence: evidence,
            expected: .sourceEvidenceUnexpectedKind(kind: .metalLibrary)
        )
    }

    @Test
    func tamperedReceiptSourceEvidenceIsRejectedOnReload() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let generationIdentifier = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)
        let activated = try await fixture.store.activate(
            operationIdentifier: operationIdentifier,
            generationIdentifier: generationIdentifier,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )
        let receiptURL = fixture.paths.receiptURL(in: activated.generationDirectoryURL)
        var changedEvidence = activated.receipt.sourceEvidence
        let index = try #require(changedEvidence.firstIndex { $0.kind == .modelWeights })
        let original = changedEvidence[index]
        let redirectURL = "https://cas-bridge.xethub.hf.co/temporary-download"
        changedEvidence[index] = StemModelInstallationSourceEvidence(
            kind: original.kind,
            stableDownloadURL: redirectURL,
            responseHeaderName: original.responseHeaderName,
            revision: original.revision
        )
        let changedReceipt = StemModelInstallationReceipt(
            schemaVersion: activated.receipt.schemaVersion,
            assetSetIdentifier: activated.receipt.assetSetIdentifier,
            modelIdentifier: activated.receipt.modelIdentifier,
            revision: activated.receipt.revision,
            generationIdentifier: activated.receipt.generationIdentifier,
            activatedAt: activated.receipt.activatedAt,
            assets: activated.receipt.assets,
            sourceEvidence: changedEvidence
        )
        try writeJSON(changedReceipt, to: receiptURL)

        do {
            _ = try await fixture.store.loadActive(manifest: fixture.manifest)
            Issue.record("改変された取得元証拠を持つreceiptが再検証を通過しました")
        } catch let error as StemModelInstallationStoreError {
            #expect(
                error == .sourceEvidenceStableURLMismatch(
                    kind: original.kind,
                    expected: try fixture.downloadableAsset(kind: original.kind).downloadURL
                )
            )
        }
    }

    @Test
    func schemaOneReceiptWithoutSourceEvidenceIsNotAcceptedOrCompleted() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)
        let activated = try await fixture.store.activate(
            operationIdentifier: operationIdentifier,
            generationIdentifier: UUID(),
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )
        let receiptURL = fixture.paths.receiptURL(in: activated.generationDirectoryURL)
        let data = try Data(contentsOf: receiptURL)
        var schemaOne = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        schemaOne["schemaVersion"] = 1
        schemaOne.removeValue(forKey: "sourceEvidence")
        try JSONSerialization.data(
            withJSONObject: schemaOne,
            options: [.sortedKeys]
        ).write(to: receiptURL, options: [.atomic])

        do {
            _ = try await fixture.store.loadActive(manifest: fixture.manifest)
            Issue.record("source evidenceのないschema 1 receiptが受理されました")
        } catch let error as StemModelInstallationStoreError {
            guard case .receiptUnreadable(let path, _) = error else {
                Issue.record("想定外のstoreエラーです: \(error)")
                return
            }
            #expect(path == receiptURL.path)
        }
    }

    @Test
    func tamperedReceiptRevisionIsRejectedOnReload() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let generationIdentifier = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)
        let activated = try await fixture.store.activate(
            operationIdentifier: operationIdentifier,
            generationIdentifier: generationIdentifier,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )
        let receiptURL = fixture.paths.receiptURL(in: activated.generationDirectoryURL)
        let changedReceipt = StemModelInstallationReceipt(
            schemaVersion: activated.receipt.schemaVersion,
            assetSetIdentifier: activated.receipt.assetSetIdentifier,
            modelIdentifier: activated.receipt.modelIdentifier,
            revision: "0000000000000000000000000000000000000000",
            generationIdentifier: activated.receipt.generationIdentifier,
            activatedAt: activated.receipt.activatedAt,
            assets: activated.receipt.assets,
            sourceEvidence: activated.receipt.sourceEvidence
        )
        try writeJSON(changedReceipt, to: receiptURL)

        do {
            _ = try await fixture.store.loadActive(manifest: fixture.manifest)
            Issue.record("改変されたreceiptが再検証を通過しました")
        } catch let error as StemModelInstallationStoreError {
            guard case .receiptMismatch(let field, _, _) = error else {
                Issue.record("想定外のstoreエラーです: \(error)")
                return
            }
            #expect(field == "revision")
        }
    }

    @Test
    func unsafeReceiptAssetPathIsRejectedWithoutResolvingIt() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        let operationIdentifier = UUID()
        let generationIdentifier = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: operationIdentifier)
        let activated = try await fixture.store.activate(
            operationIdentifier: operationIdentifier,
            generationIdentifier: generationIdentifier,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )
        let receiptURL = fixture.paths.receiptURL(in: activated.generationDirectoryURL)
        var changedAssets = activated.receipt.assets
        let first = changedAssets[0]
        changedAssets[0] = StemModelInstallationReceiptAsset(
            kind: first.kind,
            installationRelativePath: "../../outside",
            byteCount: first.byteCount,
            sha256: first.sha256
        )
        let changedReceipt = StemModelInstallationReceipt(
            schemaVersion: activated.receipt.schemaVersion,
            assetSetIdentifier: activated.receipt.assetSetIdentifier,
            modelIdentifier: activated.receipt.modelIdentifier,
            revision: activated.receipt.revision,
            generationIdentifier: activated.receipt.generationIdentifier,
            activatedAt: activated.receipt.activatedAt,
            assets: changedAssets,
            sourceEvidence: activated.receipt.sourceEvidence
        )
        try writeJSON(changedReceipt, to: receiptURL)

        do {
            _ = try await fixture.store.loadActive(manifest: fixture.manifest)
            Issue.record("不正相対パスを含むreceiptが再検証を通過しました")
        } catch let error as StemModelInstallationStoreError {
            guard case .receiptMismatch(let field, _, _) = error else {
                Issue.record("想定外のstoreエラーです: \(error)")
                return
            }
            #expect(field == "assets")
        }
    }

    @Test
    func malformedGenerationIdentifierInActivePointerIsRejected() async throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryRoot() }
        try FileManager.default.createDirectory(
            at: fixture.paths.rootURL,
            withIntermediateDirectories: true
        )
        let malformedPointer = Data(
            "{\"schemaVersion\":1,\"assetSetIdentifier\":\"\(fixture.manifest.assetSetIdentifier)\",\"generationIdentifier\":\"../../outside\"}".utf8
        )
        try malformedPointer.write(to: fixture.paths.activePointerURL)

        do {
            _ = try await fixture.store.loadActive(manifest: fixture.manifest)
            Issue.record("不正なgeneration identifierを含むactive pointerが使用されました")
        } catch let error as StemModelInstallationStoreError {
            guard case .activePointerUnreadable(let path, _) = error else {
                Issue.record("想定外のstoreエラーです: \(error)")
                return
            }
            #expect(path == fixture.paths.activePointerURL.path)
        }
    }

    private func expectSourceEvidenceRejection(
        fixture: StoreFixture,
        sourceEvidence: [StemModelInstallationSourceEvidence],
        expected: StemModelInstallationStoreError
    ) async throws {
        let activeOperation = UUID()
        let activeGeneration = UUID()
        _ = try await fixture.prepareStaging(operationIdentifier: activeOperation)
        let installationBeforeFailure = try await fixture.store.activate(
            operationIdentifier: activeOperation,
            generationIdentifier: activeGeneration,
            manifest: fixture.manifest,
            sourceEvidence: fixture.sourceEvidence
        )
        let pointerBeforeFailure = try Data(contentsOf: fixture.paths.activePointerURL)

        let rejectedOperation = UUID()
        let rejectedGeneration = UUID()
        let rejectedStaging = try await fixture.prepareStaging(
            operationIdentifier: rejectedOperation
        )
        do {
            _ = try await fixture.store.activate(
                operationIdentifier: rejectedOperation,
                generationIdentifier: rejectedGeneration,
                manifest: fixture.manifest,
                sourceEvidence: sourceEvidence
            )
            Issue.record("不正な取得元証拠を持つモデル世代が有効化されました")
        } catch let error as StemModelInstallationStoreError {
            #expect(error == expected)
        } catch {
            Issue.record("想定外のエラー型です: \(error)")
        }

        #expect(try Data(contentsOf: fixture.paths.activePointerURL) == pointerBeforeFailure)
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.paths.generationDirectoryURL(
                    assetSetIdentifier: fixture.manifest.assetSetIdentifier,
                    generationIdentifier: rejectedGeneration
                ).path
            )
        )
        #expect(
            !FileManager.default.fileExists(
                atPath: fixture.paths.receiptURL(in: rejectedStaging).path
            )
        )
        let active = try #require(
            try await fixture.store.loadActive(manifest: fixture.manifest)
        )
        #expect(active == installationBeforeFailure)
    }

    private func makeFixture(configuration: Data? = nil) throws -> StoreFixture {
        try StoreFixture(configurationOverride: configuration)
    }

    private func configurationData(segment: Any, numModels: Any = 1) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "model_name": "htdemucs",
                "model_class": "BagOfModelsMLX",
                "num_models": numModels,
                "sub_model_class": "HTDemucsMLX",
                "kwargs": [
                    "samplerate": 44_100,
                    "audio_channels": 2,
                    "sources": ["drums", "bass", "other", "vocals"],
                    "segment": segment
                ]
            ],
            options: [.sortedKeys]
        )
    }

    private func writeJSON<Value: Encodable>(_ value: Value, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(value).write(to: url, options: [.atomic])
    }
}

private struct StoreFixture: Sendable {
    let temporaryRootURL: URL
    let paths: StemModelStorePaths
    let manifest: StemModelManifest
    let weights: Data
    let configuration: Data
    let store: StemModelInstallationStore

    init(configurationOverride: Data? = nil) throws {
        temporaryRootURL = FileManager.default.temporaryDirectory.appending(
            path: "VelouraStemStoreTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        paths = StemModelStorePaths(
            rootURL: temporaryRootURL.appending(path: "StemModels", directoryHint: .isDirectory)
        )
        let fixtureWeights = Data("fixture-weights-v1".utf8)
        let fixtureConfiguration = try configurationOverride ?? JSONSerialization.data(
            withJSONObject: Self.configurationObject(segment: "39/5"),
            options: [.sortedKeys]
        )
        weights = fixtureWeights
        configuration = fixtureConfiguration

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
        manifest = StemModelManifest(
            schemaVersion: productionManifest.schemaVersion,
            assetSetIdentifier: productionManifest.assetSetIdentifier,
            model: productionManifest.model,
            runtimePins: productionManifest.runtimePins,
            audioContract: productionManifest.audioContract,
            downloadPolicy: productionManifest.downloadPolicy,
            downloadableModelAssets: productionManifest.downloadableModelAssets.map { asset in
                let data = asset.kind == .modelWeights ? fixtureWeights : fixtureConfiguration
                return StemDownloadableModelAsset(
                    kind: asset.kind,
                    downloadURL: asset.downloadURL,
                    installationRelativePath: asset.installationRelativePath,
                    byteCount: Int64(data.count),
                    sha256: Self.sha256(data)
                )
            },
            bundledRuntimeAssets: productionManifest.bundledRuntimeAssets,
            metalLibraryBuildProvenance: productionManifest.metalLibraryBuildProvenance
        )
        let validator = StemModelAssetValidator(validationReference: manifest)
        store = StemModelInstallationStore(paths: paths, validator: validator)
    }

    var sourceEvidence: [StemModelInstallationSourceEvidence] {
        manifest.downloadableModelAssets
            .sorted(by: { $0.kind.rawValue < $1.kind.rawValue })
            .map { asset in
                StemModelInstallationSourceEvidence(
                    kind: asset.kind,
                    stableDownloadURL: asset.downloadURL,
                    responseHeaderName: manifest.downloadPolicy.revisionResponseHeader,
                    revision: manifest.model.revision
                )
            }
    }

    func prepareStaging(operationIdentifier: UUID) async throws -> URL {
        let stagingURL = try await store.makeStagingDirectory(operationIdentifier: operationIdentifier)
        for asset in manifest.downloadableModelAssets {
            let destination = try StemModelAssetValidator.safeDescendantURL(
                rootURL: stagingURL,
                relativePath: asset.installationRelativePath,
                field: "fixture"
            )
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = asset.kind == .modelWeights ? weights : configuration
            try data.write(to: destination)
        }
        return stagingURL
    }

    func assetURL(kind: StemModelAssetKind, rootURL: URL) throws -> URL {
        let asset = try downloadableAsset(kind: kind)
        return try StemModelAssetValidator.safeDescendantURL(
            rootURL: rootURL,
            relativePath: asset.installationRelativePath,
            field: "fixture"
        )
    }

    func downloadableAsset(kind: StemModelAssetKind) throws -> StemDownloadableModelAsset {
        try #require(manifest.downloadableModelAssets.first { $0.kind == kind })
    }

    func removeTemporaryRoot() {
        try? FileManager.default.removeItem(at: temporaryRootURL)
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func configurationObject(segment: Any) -> [String: Any] {
        [
            "model_name": "htdemucs",
            "model_class": "BagOfModelsMLX",
            "num_models": 1,
            "sub_model_class": "HTDemucsMLX",
            "kwargs": [
                "samplerate": 44_100,
                "audio_channels": 2,
                "sources": ["drums", "bass", "other", "vocals"],
                "segment": segment
            ]
        ]
    }
}
