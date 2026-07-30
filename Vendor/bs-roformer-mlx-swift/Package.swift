// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "bs-roformer-mlx-swift",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "BSRoformerMLX", targets: ["BSRoformerMLX"]),
        .executable(name: "bs-roformer-mlx-swift", targets: ["BSRoformerCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", exact: "0.30.6"),
    ],
    targets: [
        .target(
            name: "BSRoformerMLX",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
            ]
        ),
        .executableTarget(
            name: "BSRoformerCLI",
            dependencies: ["BSRoformerMLX"]
        ),
        .testTarget(
            name: "BSRoformerMLXTests",
            dependencies: ["BSRoformerMLX"]
        ),
    ]
)
