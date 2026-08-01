import Foundation

enum StemSeparationModel: String, CaseIterable, Codable, Identifiable, Sendable {
    case htdemucs
    case bsRoformerSW

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .htdemucs: "HTDemucs"
        case .bsRoformerSW: "BS-RoFormer-SW"
        }
    }

    var manifestResourceRelativePath: String {
        switch self {
        case .htdemucs:
            "StemModels/stem-model-manifest.json"
        case .bsRoformerSW:
            "StemModels/bs-roformer-sw-manifest.json"
        }
    }

    var activePointerFileName: String {
        switch self {
        case .htdemucs:
            StemModelStorePaths.activePointerFileName
        case .bsRoformerSW:
            "active-bs-roformer-sw.json"
        }
    }
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
                    "swift-argument-parser": StemRuntimePin(
                        name: "swift-argument-parser",
                        repo: "https://github.com/apple/swift-argument-parser",
                        version: "1.8.2",
                        revision: "6a52f3251125d74daf04fcbd5e6f08a75d074382"
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
                defaultSegmentSeconds: 7.8
            )
        case .bsRoformerSW:
            let revision = "13edef2e713151522e4049e92f011e0543c45d53"
            return Self(
                model: model,
                assetSetIdentifier: "bs-roformer-sw-\(revision)",
                modelIdentifier: "MrSimmo/BS_Roformer_SW-MLX:bs-roformer-sw",
                modelName: "BS-RoFormer-SW",
                repository: "MrSimmo/BS_Roformer_SW-MLX",
                revision: revision,
                license: "unknown",
                runtimePins: [
                    "bs-roformer-mlx-swift": StemRuntimePin(
                        name: "bs-roformer-mlx-swift",
                        repo: "local:Vendor/bs-roformer-mlx-swift",
                        version: nil,
                        revision: "cee13b8a16bd9b6eb51ac52f94d997e424069673"
                    ),
                    "mlx-swift": StemRuntimePin(
                        name: "mlx-swift",
                        repo: "https://github.com/ml-explore/mlx-swift.git",
                        version: "0.30.6",
                        revision: "6ba4827fb82c97d012eec9ab4b2de21f85c3b33d"
                    ),
                ],
                downloadableAssets: [
                    .modelWeights: StemDownloadableModelAsset(
                        kind: .modelWeights,
                        downloadURL: "https://huggingface.co/MrSimmo/BS_Roformer_SW-MLX/resolve/\(revision)/bs_roformer_sw.safetensors",
                        installationRelativePath: "bs-roformer-sw/bs_roformer_sw.safetensors",
                        byteCount: 349_521_144,
                        sha256: "6c8303a829575d03f21562ea185be7b6b23e922052883dec1b9518ca00a920fc"
                    ),
                    .modelConfiguration: StemDownloadableModelAsset(
                        kind: .modelConfiguration,
                        downloadURL: "https://huggingface.co/MrSimmo/BS_Roformer_SW-MLX/resolve/\(revision)/bs_roformer_sw_config.json",
                        installationRelativePath: "bs-roformer-sw/bs_roformer_sw_config.json",
                        byteCount: 1_141,
                        sha256: "ab4ae4369276c2ff12ee86d55ce45c37a88a82f6744c33c0bb6a40c1c2f620f9"
                    ),
                ],
                defaultSegmentSeconds: nil
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
