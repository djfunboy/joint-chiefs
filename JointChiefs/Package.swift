// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "JointChiefs",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "JointChiefsCore", targets: ["JointChiefsCore"]),
        .executable(name: "jointchiefs", targets: ["JointChiefsCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
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
        .testTarget(
            name: "JointChiefsCoreTests",
            dependencies: ["JointChiefsCore"],
            path: "Tests/JointChiefsCoreTests"
        )
    ]
)
