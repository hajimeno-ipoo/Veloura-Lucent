import Foundation

enum StemSeparationModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case htdemucs

    var id: String { rawValue }

    var displayName: String {
        "HTDemucs"
    }

    var manifestResourceRelativePath: String {
        "StemModels/stem-model-manifest.json"
    }

    var activePointerFileName: String {
        StemModelStorePaths.activePointerFileName
    }

    var rightsAndProvenance: StemModelRightsAndProvenance {
        StemModelRightsAndProvenance(
            licenseStatus: "取得元のモデルカードはMITを示し、元のDemucsもMITと記載しています。",
            provenance: "adefossez/demucsの事前学習済みweightを、MLX用のsafetensorsとJSON設定へ直接変換したモデルです。"
        )
    }
}

struct StemModelRightsAndProvenance: Equatable, Sendable {
    let licenseStatus: String
    let provenance: String
}

struct StemProductionModelProfile: Sendable {
    let model: StemSeparationModel
    let assetSetIdentifier: String
    let modelIdentifier: String
    let modelName: String
    let repository: String
    let revision: String
    let license: String
    let runtimePins: [String: StemRuntimePin]
    let downloadableAssets: [StemModelAssetKind: StemDownloadableModelAsset]
    let defaultSegmentSeconds: Double?
    let sourceOrder: [StemRole]
    let pureSumOrder: [StemRole]

    static func profile(for model: StemSeparationModel) -> Self {
        switch model {
        case .htdemucs:
            let revision = "d4519e24ddc2dd4a11d56a193092433d852c3961"
            return Self(
                model: model,
                assetSetIdentifier: "htdemucs-\(revision)",
                modelIdentifier: "mlx-community/demucs-mlx:htdemucs",
                modelName: "Demucs v4 htdemucs",
                repository: "mlx-community/demucs-mlx",
                revision: revision,
                license: "mit",
                runtimePins: [
                    "demucs-mlx-swift": StemRuntimePin(
                        name: "demucs-mlx-swift",
                        repo: "https://github.com/kylehowells/demucs-mlx-swift.git",
                        version: nil,
                        revision: "c81c47178828db2d8bc66e64f80c745c64abdc94"
                    ),
                    "mlx-swift": StemRuntimePin(
                        name: "mlx-swift",
                        repo: "https://github.com/ml-explore/mlx-swift.git",
                        version: "0.30.6",
                        revision: "6ba4827fb82c97d012eec9ab4b2de21f85c3b33d"
                    ),
                    "swift-transformers": StemRuntimePin(
                        name: "swift-transformers",
                        repo: "https://github.com/huggingface/swift-transformers.git",
                        version: "1.1.6",
                        revision: "573e5c9036c2f136b3a8a071da8e8907322403d0"
                    ),
                    "swift-jinja": StemRuntimePin(
                        name: "swift-jinja",
                        repo: "https://github.com/huggingface/swift-jinja.git",
                        version: "2.3.2",
                        revision: "f731f03bf746481d4fda07f817c3774390c4d5b9"
                    ),
                    "swift-collections": StemRuntimePin(
                        name: "swift-collections",
                        repo: "https://github.com/apple/swift-collections.git",
                        version: "1.4.0",
                        revision: "8d9834a6189db730f6264db7556a7ffb751e99ee"
                    ),
                    "swift-numerics": StemRuntimePin(
                        name: "swift-numerics",
                        repo: "https://github.com/apple/swift-numerics",
                        version: "1.1.1",
                        revision: "0c0290ff6b24942dadb83a929ffaaa1481df04a2"
                    ),
                ],
                downloadableAssets: [
                    .modelWeights: StemDownloadableModelAsset(
                        kind: .modelWeights,
                        downloadURL: "https://huggingface.co/mlx-community/demucs-mlx/resolve/\(revision)/htdemucs.safetensors",
                        installationRelativePath: "htdemucs/htdemucs.safetensors",
                        byteCount: 168_005_865,
                        sha256: "339d267a7a6983a11eedbdc00413c602a65e9b9103f695fb5c2b2a481cd9d297"
                    ),
                    .modelConfiguration: StemDownloadableModelAsset(
                        kind: .modelConfiguration,
                        downloadURL: "https://huggingface.co/mlx-community/demucs-mlx/resolve/\(revision)/htdemucs_config.json",
                        installationRelativePath: "htdemucs/htdemucs_config.json",
                        byteCount: 1_892,
                        sha256: "9258499513944fc062fbca0f11be425a446ec5702869a87e225323d7a57d2a01"
                    ),
                ],
                defaultSegmentSeconds: 7.8,
                sourceOrder: [.drums, .bass, .other, .vocals],
                pureSumOrder: [.vocals, .drums, .bass, .other]
            )
        }
    }

    static func identify(_ manifest: StemModelManifest) -> StemSeparationModel? {
        StemSeparationModel.allCases.first {
            let profile = Self.profile(for: $0)
            return manifest.assetSetIdentifier == profile.assetSetIdentifier
                && manifest.model.repo == profile.repository
                && manifest.model.revision == profile.revision
        }
    }
}
