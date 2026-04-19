// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VelouraLucent",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "VelouraLucent", targets: ["VelouraLucent"])
    ],
    targets: [
        .executableTarget(
            name: "VelouraLucent",
            path: "Sources/VelouraLucent"
        ),
        .testTarget(
            name: "VelouraLucentTests",
            dependencies: ["VelouraLucent"],
            path: "Tests/VelouraLucentTests"
        )
    ]
)
