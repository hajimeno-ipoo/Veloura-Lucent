// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VelouraLucent",
    defaultLocalization: "ja",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "VelouraLucent", targets: ["VelouraLucent"])
    ],
    dependencies: [
        .package(path: "Vendor/demucs-mlx-swift"),
        .package(path: "Vendor/bs-roformer-mlx-swift"),
        .package(
            url: "https://github.com/apple/swift-collections.git",
            exact: "1.4.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "VelouraLucent",
            dependencies: [
                .product(name: "DemucsMLX", package: "demucs-mlx-swift"),
                .product(name: "BSRoformerMLX", package: "bs-roformer-mlx-swift")
            ],
            path: "Sources/VelouraLucent",
            resources: [
                .process("Resources/AppIcon-1024.png"),
                .process("Resources/Rotary_Knob"),
                .copy("Resources/StemModels"),
                .copy("Resources/ThirdPartyNotices")
            ]
        ),
        .testTarget(
            name: "VelouraLucentTests",
            dependencies: [
                "VelouraLucent",
                .product(name: "BSRoformerMLX", package: "bs-roformer-mlx-swift")
            ],
            path: "Tests/VelouraLucentTests"
        )
    ]
)
