// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JointChiefs",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "JointChiefsCore", targets: ["JointChiefsCore"]),
        .executable(name: "jointchiefs", targets: ["JointChiefsCLI"]),
        .executable(name: "jointchiefs-mcp", targets: ["JointChiefsMCP"]),
        .executable(name: "jointchiefs-keygetter", targets: ["JointChiefsKeygetter"]),
        .executable(name: "jointchiefs-setup", targets: ["JointChiefsSetup"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.9.0")
    ],
    targets: [
        .target(
            name: "JointChiefsCore",
            path: "Sources/JointChiefsCore"
        ),
        .executableTarget(
            name: "JointChiefsCLI",
            dependencies: [
                "JointChiefsCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/JointChiefsCLI"
        ),
        .executableTarget(
            name: "JointChiefsMCP",
            dependencies: [
                "JointChiefsCore",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/JointChiefsMCP"
        ),
        .executableTarget(
            name: "JointChiefsKeygetter",
            dependencies: ["JointChiefsCore"],
            path: "Sources/JointChiefsKeygetter"
        ),
        .executableTarget(
            name: "JointChiefsSetup",
            dependencies: [
                "JointChiefsCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/JointChiefsSetup"
        ),
        .testTarget(
            name: "JointChiefsCoreTests",
            dependencies: ["JointChiefsCore"],
            path: "Tests/JointChiefsCoreTests"
        )
    ]
)
