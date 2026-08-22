// swift-tools-version: 6.2
import Foundation
import PackageDescription

let localOnlyExcludedPaths = (FileManager.default.enumerator(atPath: "Sources/VelouraLucent")?
    .compactMap { $0 as? String }
    .filter { path in
        path.hasSuffix("SeparationBackend.swift") ||
        path.hasSuffix(".png") ||
        path.hasSuffix(".jpg") ||
        path.hasSuffix(".jpeg") ||
        path.hasSuffix(".svg") ||
        path.hasPrefix("Resources/VelouraLucent.icon")
    } ?? [])

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
        .package(
            url: "https://github.com/apple/swift-collections.git",
            exact: "1.4.0"
        )
    ],
    targets: [
        .executableTarget(
            name: "VelouraLucent",
            dependencies: [
                .product(name: "DemucsMLX", package: "demucs-mlx-swift")
            ],
            path: "Sources/VelouraLucent",
            exclude: localOnlyExcludedPaths,
            resources: [
                .copy("Resources/StemModels"),
                .copy("Resources/ThirdPartyNotices")
            ]
        )
    ]
)
