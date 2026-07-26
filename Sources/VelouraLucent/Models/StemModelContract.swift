import Foundation

enum StemRole: String, CaseIterable, Codable, Sendable {
    case drums
    case bass
    case other
    case vocals
}

enum StemModelScalarType: String, Codable, Sendable {
    case float32
    case float16
}

enum StemModelRuntime: String, Codable, Sendable {
    case coreML
    case mlx
}

enum StemChannelLayout: String, Codable, Sendable {
    case stereo
}

enum StemInputTensorLayout: String, Codable, Sendable {
    case channelMajor = "channel-major"
}

enum StemOutputTensorLayout: String, Codable, Sendable {
    case sourceMajor = "source-major"
}

enum StemModelAssetKind: String, CaseIterable, Codable, Sendable {
    case modelWeights
    case modelConfiguration
    case metalLibrary
}

struct StemNormalizationContract: Codable, Equatable, Sendable {
    enum Ownership: String, Codable, Sendable {
        case modelInternalMeanAndStandardDeviation
    }

    let inputScale: Double
    let inputOffset: Double
    let outputScale: Double
    let outputOffset: Double
    let ownership: Ownership

    static let modelManagedIdentityBoundary = StemNormalizationContract(
        inputScale: 1,
        inputOffset: 0,
        outputScale: 1,
        outputOffset: 0,
        ownership: .modelInternalMeanAndStandardDeviation
    )
}

struct StemModelContract: Codable, Equatable, Sendable {
    let identifier: String
    let version: String
    let assetSetIdentifier: String
    let inputName: String
    let outputNames: [StemRole: String]
    let sourceOrder: [StemRole]
    let sampleRate: Double
    let channelCount: Int
    let inputShape: [Int]
    let outputShapes: [StemRole: [Int]]
    let scalarType: StemModelScalarType
    let normalization: StemNormalizationContract
    let runtime: StemModelRuntime
    let defaultSegmentSeconds: Double
    let downloadableModelAssets: [StemDownloadableModelAsset]
    let bundledRuntimeAssets: [StemBundledRuntimeAsset]
}

struct StemModelManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let assetSetIdentifier: String
    let model: StemModelManifestModel
    let runtimePins: [StemRuntimePin]
    let audioContract: StemModelAudioContract
    let downloadPolicy: StemModelDownloadPolicy
    let downloadableModelAssets: [StemDownloadableModelAsset]
    let bundledRuntimeAssets: [StemBundledRuntimeAsset]
    let metalLibraryBuildProvenance: StemMetalLibraryBuildProvenance
}

struct StemModelManifestModel: Codable, Equatable, Sendable {
    let name: String
    let repo: String
    let revision: String
    let licenseMetadata: String
}

struct StemRuntimePin: Codable, Equatable, Sendable {
    let name: String
    let repo: String
    let version: String?
    let revision: String
}

struct StemModelAudioContract: Codable, Equatable, Sendable {
    let sampleRateHz: Int
    let channelCount: Int
    let channelLayout: StemChannelLayout
    let scalarType: StemModelScalarType
    let inputTensorLayout: StemInputTensorLayout
    let outputTensorLayout: StemOutputTensorLayout
    let channelLayoutWithinSource: StemInputTensorLayout
    let sourceOrder: [StemRole]
}

struct StemModelDownloadPolicy: Codable, Equatable, Sendable {
    let requiresExplicitUserConfirmation: Bool
    let revisionResponseHeader: String
    let allowedRedirectHosts: [String]
}

struct StemDownloadableModelAsset: Codable, Equatable, Sendable {
    let kind: StemModelAssetKind
    let downloadURL: String
    let installationRelativePath: String
    let byteCount: Int64
    let sha256: String
}

struct StemBundledRuntimeAsset: Codable, Equatable, Sendable {
    let kind: StemModelAssetKind
    let resourceRelativePath: String
    let runtimeRelativePath: String
    let byteCount: Int64
    let sha256: String
}

struct StemMetalLibraryBuildProvenance: Codable, Equatable, Sendable {
    let sourceRepo: String
    let sourceVersion: String
    let sourceRevision: String
    let sourceDirectory: String
    let sourceSelection: String
    let sourceFileCount: Int
    let compilerCommand: String
    let linkerCommand: String
    let compilerFlags: [String]
    let includeDirectories: [String]
    let verifiedToolchain: StemMetalToolchainProvenance
}

struct StemMetalToolchainProvenance: Codable, Equatable, Sendable {
    let xcodeVersion: String
    let xcodeBuildVersion: String
    let macosSdkVersion: String
    let metalVersion: String
    let metallibVersion: String
}
