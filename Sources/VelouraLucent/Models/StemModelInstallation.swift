import Foundation

struct StemModelInstallationReceiptAsset: Codable, Equatable, Sendable {
    let kind: StemModelAssetKind
    let installationRelativePath: String
    let byteCount: Int64
    let sha256: String
}

struct StemModelInstallationSourceEvidence: Codable, Equatable, Sendable {
    let kind: StemModelAssetKind
    let stableDownloadURL: String
    let responseHeaderName: String
    let revision: String
}

struct StemModelInstallationReceipt: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let assetSetIdentifier: String
    let modelIdentifier: String
    let revision: String
    let generationIdentifier: UUID
    let activatedAt: Date
    let assets: [StemModelInstallationReceiptAsset]
    let sourceEvidence: [StemModelInstallationSourceEvidence]
}

struct StemModelActivePointer: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let assetSetIdentifier: String
    let generationIdentifier: UUID
}

struct ValidatedStemModelInstallation: Equatable, Sendable {
    let snapshot: ValidatedStemModelSnapshot
    let receipt: StemModelInstallationReceipt
    let generationDirectoryURL: URL

    var modelDirectoryURL: URL {
        snapshot.modelDirectoryURL
    }
}
