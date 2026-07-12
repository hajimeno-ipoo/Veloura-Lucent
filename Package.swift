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
    targets: [
        .executableTarget(
            name: "VelouraLucent",
            path: "Sources/VelouraLucent",
            resources: [
                .process("Resources/AppIcon-1024.png"),
                .process("Resources/Rotary_Knob")
            ]
        ),
        .testTarget(
            name: "VelouraLucentTests",
            dependencies: ["VelouraLucent"],
            path: "Tests/VelouraLucentTests"
        )
    ]
)
